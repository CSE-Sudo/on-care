import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/features/auth/domain/signup_consent.dart';
import 'package:oncare/features/auth/domain/signup_email_code.dart';
import 'package:oncare/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/signup_email_code_providers.dart';
import 'package:oncare/features/auth/presentation/widgets/signup_consent_block.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 가입 화면에서 검사하는 칸. 이름도 꼭 받는다(#1784).
enum _Field { name, email, phone, password, passwordConfirm }

/// 회원가입 화면 — 이름/이메일/전화번호/비밀번호로 계정을 만들고, 성공 시 자동
/// 로그인해 대시보드로 진입한다(라우터 가드가 인증 상태를 감지).
///
/// 전화번호를 여기서 받는 이유는 가입 직후부터 연락처가 있어야 하기
/// 때문이다 (#1634). 예전처럼 MY 탭 프로필 편집에서만 받으면, 트레이너와
/// 연결된 뒤에도 회원의 연락처가 비어 있는 기간이 생긴다.
///
/// 이메일은 가입 전에 그 주소로 받은 6자리 코드로 확인한다(#3038). 코드 없이
/// 가입 버튼은 켜지지 않는다 — 남의 주소로 계정을 먼저 만들 수 없게 한다.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  /// 코드를 요청한 이메일(소문자). null 이면 아직 요청 전이고 코드 칸도 없다
  /// (#3038). 코드는 (이메일, 용도) 에 묶이므로 이메일을 고치면 다시 받는다.
  String? _codeEmail;

  /// 마지막 요청의 응답 — 유효 시간과 다시 받기 대기 시간.
  SignupEmailCodeSent? _codeSent;

  /// 마지막 요청 뒤 지난 초. 남은 시간·다시 받기 카운트다운이 이 값으로 줄어든다.
  int _codeElapsed = 0;
  Timer? _codeTimer;
  bool _codeRequesting = false;

  /// 서버가 코드를 거절한 이유(코드 칸 아래 문구). 코드를 고치면 지운다.
  String? _codeServerError;

  /// 체크한 동의 항목(#2819). 필수 항목이 모두 있어야 가입 버튼이 켜진다.
  Set<String> _consents = <String>{};

  bool get _consentsReady => SignupConsent.hasAllRequired(_consents);

  bool get _codeRequested => _codeEmail != null;

  /// 코드 여섯 자리를 다 넣었는가(#3038). 동의와 함께 가입 버튼을 켜는 조건이다.
  bool get _codeReady =>
      _codeRequested && SignupEmailCode.isComplete(_code.text);

  bool get _canSubmit => _consentsReady && _codeReady;

  /// 코드가 살아 있는 남은 초.
  int get _codeSecondsLeft {
    final SignupEmailCodeSent? sent = _codeSent;
    if (sent == null) return 0;
    return math.max(0, sent.expiresInMinutes * 60 - _codeElapsed);
  }

  /// 다시 받을 수 있을 때까지 남은 초.
  int get _resendSecondsLeft {
    final SignupEmailCodeSent? sent = _codeSent;
    if (sent == null) return 0;
    return math.max(0, sent.resendAfterSeconds - _codeElapsed);
  }

  /// 칸 아래 오류 문구. 첫 제출 전에는 숨기고, 오류를 보인 칸은 입력하는 대로
  /// 다시 검사한다(#1784).
  late final AppFieldErrors<_Field> _errors = AppFieldErrors<_Field>(_check);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _code.dispose();
    _codeTimer?.cancel();
    super.dispose();
  }

  /// 칸의 지금 값에 대한 오류 문구. 전화번호는 `010-0000-0000` 만 받는다 —
  /// 숫자만 쳐도 [AppPhoneNumberFormatter] 가 하이픈을 넣어 준다(#1784).
  String? _check(_Field field) =>
      authInputErrorText(AppLocalizations.of(context), switch (field) {
        _Field.name => AppInputRules.name(_name.text),
        _Field.email => AppInputRules.email(_email.text),
        _Field.phone => AppInputRules.phone(_phone.text),
        _Field.password => AppInputRules.signUpPassword(_password.text),
        _Field.passwordConfirm => AppInputRules.passwordConfirm(
          _password.text,
          _passwordConfirm.text,
        ),
      });

  /// 오류를 보인 칸이 있을 때만 입력마다 다시 그린다. 비밀번호를 고치면
  /// 확인 칸의 일치 여부도 바뀌므로 칸을 가리지 않고 다시 그린다.
  void _onEdited(String _) {
    if (_errors.isWatching) setState(() {});
  }

  /// 이메일을 고쳤다. 코드를 받은 뒤라면 코드는 그 주소의 것이므로 칸을 비우고
  /// 다시 받게 한다(#3038).
  void _onEmailEdited(String value) {
    if (_codeEmail != null && _normalizedEmail(value) != _codeEmail) {
      _codeTimer?.cancel();
      _code.clear();
      setState(() {
        _codeEmail = null;
        _codeSent = null;
        _codeServerError = null;
        _codeElapsed = 0;
      });
    }
    _onEdited(value);
  }

  void _onCodeEdited(String _) {
    // 버튼이 여섯 자리에 맞춰 켜지고 꺼지므로 입력마다 다시 그린다.
    setState(() => _codeServerError = null);
  }

  static String _normalizedEmail(String value) => value.trim().toLowerCase();

  /// 남은 초를 `9:59` 모양으로.
  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  /// 이메일로 인증 코드를 받는다(#3038). 이미 가입된 주소도 같은 응답이라 화면도
  /// 같은 모양으로 이어 간다 — 가입 여부를 이 버튼으로 알 수 없게 한다.
  Future<void> _requestCode() async {
    if (_codeRequesting || _loading) return;
    final AppLocalizations l = AppLocalizations.of(context);
    if (!_errors.validate(const <_Field>[_Field.email])) {
      setState(() {});
      return;
    }
    final String email = _email.text.trim();
    setState(() => _codeRequesting = true);
    try {
      final SignupEmailCodeSent sent = await ref
          .read(signupEmailCodeRepositoryProvider)
          .requestCode(email: email);
      if (!mounted) return;
      // 요청하는 사이 이메일을 고쳤다면 이 코드는 지금 칸의 주소 것이 아니다.
      if (_normalizedEmail(_email.text) != _normalizedEmail(email)) {
        setState(() => _codeRequesting = false);
        return;
      }
      _codeTimer?.cancel();
      _code.clear();
      setState(() {
        _codeRequesting = false;
        _codeEmail = _normalizedEmail(email);
        _codeSent = sent;
        _codeElapsed = 0;
        _codeServerError = null;
      });
      _codeTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _codeElapsed++);
        if (_codeSecondsLeft == 0 && _resendSecondsLeft == 0) t.cancel();
      });
    } on SignupEmailCodeError catch (e) {
      if (!mounted) return;
      setState(() => _codeRequesting = false);
      _error(switch (e.kind) {
        SignupEmailCodeFailure.invalidEmail => l.authEmailInvalid,
        SignupEmailCodeFailure.tooMany => l.passwordTooManyAttempts,
        SignupEmailCodeFailure.unavailable => l.signUpEmailCodeUnavailable,
        SignupEmailCodeFailure.temporary => l.passwordTemporaryFailure,
      });
    } on Object {
      if (!mounted) return;
      setState(() => _codeRequesting = false);
      _error(l.passwordTemporaryFailure);
    }
  }

  void _backToSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.signIn);
    }
  }

  void _error(String message) =>
      showAppToast(context, message, type: AppToastType.error);

  Future<void> _register() async {
    if (_loading) return;
    // 버튼은 꺼져 있지만 확인 칸의 완료 키로도 여기 온다(#2819). 코드 여섯
    // 자리도 같은 조건이다(#3038).
    if (!_canSubmit) return;
    final AppLocalizations l = AppLocalizations.of(context);
    // 틀린 칸이 하나라도 있으면 요청을 보내지 않고 칸 아래에 알린다. 서버가
    // 돌려준 실패(이메일 중복 등)만 아래에서 토스트로 알린다.
    if (!_errors.validate(_Field.values)) {
      setState(() {});
      return;
    }
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final password = _password.text;
    setState(() => _loading = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .register(
            email: email,
            password: password,
            name: name,
            phone: phone,
            emailCode: _code.text.trim(),
            consents: SignupConsent.toPayload(_consents),
          );
      // 계정이 만들어지고 로그인까지 된 뒤에만 새 비밀번호를 저장하게 한다
      // (#2295). 세션 가드가 곧 이 화면을 걷어 낼 수 있어 `mounted` 를 보기
      // 전에 알린다.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      // 가입한 사람은 언제나 이 앱을 처음 쓰는 사람이다 — 이 기기에서 다른
      // 계정이 사용 가이드를 본 적이 있어도 다시 보여 준다(#1857).
      ref.read(appGuideControllerProvider.notifier).resetSeen();
      // New accounts land in first-run onboarding; the guard keeps the
      // (now authenticated) user on this protected route.
      context.go(AppRoutes.onboarding);
    } on AccountCreatedSignInFailed {
      // 계정은 만들어졌다. 다시 가입하라고 하면 409 를 만나므로 로그인으로 보낸다.
      // 이 자격 증명은 이제 유효하다 — 저장해 두면 곧 볼 로그인 화면에서
      // 그대로 채워진다(#2295).
      TextInput.finishAutofillContext();
      if (!mounted) return;
      setState(() => _loading = false);
      _error(l.signUpCreatedSignInNeeded);
      context.go(AppRoutes.signIn);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.response?.statusCode == 409) {
        _error(l.signUpEmailTaken);
        return;
      }
      // 코드가 틀렸거나 빠졌다(#3038) — 폼은 그대로 두고 코드 칸 아래에 알린다.
      switch (signupCodeRejectionOf(e.response?.statusCode, e.response?.data)) {
        case SignupCodeRejection.invalid:
          setState(() => _codeServerError = l.signUpEmailCodeInvalid);
          return;
        case SignupCodeRejection.required:
          setState(() => _codeServerError = l.signUpEmailCodeEmpty);
          return;
        case null:
          break;
      }
      // 화면 규칙과 서버 기준이 같아(#1555) 여기까지 오는 일은 드물지만,
      // 서버가 비밀번호를 거절했다면 "가입에 실패했어요" 대신 무엇을 고칠지
      // 알린다. 서버는 문장이 아니라 코드를 주므로 문구는 이 앱의 로케일이다.
      final AppInputError? password = e.response?.statusCode == 422
          ? AppInputRules.serverPasswordError(e.response?.data)
          : null;
      _error(authInputErrorText(l, password) ?? l.signUpFailed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _error(l.signUpFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppAuthLayout(
      leading: AppBackButton(onPressed: _backToSignIn),
      title: l.signUpTitle,
      subtitle: l.signUpSubtitle,
      // 새 계정의 입력을 한 묶음으로 알린다(#2295). 가입하지 않고 떠날 때는
      // 저장하지 않는다 — 기본값(commit)이면 뒤로만 가도 쓰다 만 비밀번호의
      // 저장 제안이 뜬다.
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppTextField(
              key: const ValueKey<String>('member-signup-name'),
              controller: _name,
              hint: l.signUpNameHint,
              errorText: _errors.of(_Field.name),
              prefixIcon: AppIcons.person,
              size: AppFieldSize.large,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.name],
              onChanged: _onEdited,
            ),
            const SizedBox(height: OnCareSpacing.s12),
            AppTextField(
              key: const ValueKey<String>('member-signup-email'),
              controller: _email,
              hint: l.authEmailHint,
              errorText: _errors.of(_Field.email),
              prefixIcon: AppIcons.mail,
              size: AppFieldSize.large,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              // 새 비밀번호를 저장할 때 이 값이 아이디가 된다(#2295).
              autofillHints: const <String>[
                AutofillHints.username,
                AutofillHints.email,
              ],
              onChanged: _onEmailEdited,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _emailCodeSection(l),
            const SizedBox(height: OnCareSpacing.s12),
            // 왜 전화번호를 받는지 그 자리에서 말해 준다. 건강 앱이 이유 없이
            // 번호를 물으면 가입을 그만두는 쪽이 자연스럽다. 오류가 뜨면 도움말
            // 자리를 오류 문구가 대신한다.
            AppTextField(
              key: const ValueKey<String>('member-signup-phone'),
              controller: _phone,
              hint: l.signUpPhoneHint,
              helper: l.signUpPhoneHelper,
              errorText: _errors.of(_Field.phone),
              prefixIcon: AppIcons.phone,
              size: AppFieldSize.large,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              // 국가 번호 없는 국내 번호 — `+82` 가 붙어 채워지면 010 형식
              // 검사에 걸린다.
              autofillHints: const <String>[
                AutofillHints.telephoneNumberNational,
              ],
              inputFormatters: const <TextInputFormatter>[
                AppPhoneNumberFormatter(),
              ],
              onChanged: _onEdited,
            ),
            const SizedBox(height: OnCareSpacing.s12),
            AppTextField(
              key: const ValueKey<String>('member-signup-password'),
              controller: _password,
              hint: l.signUpPasswordHint,
              errorText: _errors.of(_Field.password),
              prefixIcon: AppIcons.lock,
              size: AppFieldSize.large,
              obscureText: _obscure,
              textInputAction: TextInputAction.next,
              // 저장된 비밀번호를 채우지 않고 새 비밀번호를 제안받는 칸이다.
              autofillHints: const <String>[AutofillHints.newPassword],
              onChanged: _onEdited,
              // 아이콘만 있는 버튼이라 무엇을 켜고 끄는지 말할 데가 툴팁뿐이다(#972).
              suffix: AppIconButton(
                icon: _obscure ? AppIcons.visibilityOff : AppIcons.visibility,
                tooltip: _obscure ? l.a11yShowPassword : l.a11yHidePassword,
                color: OnCareColors.textTertiary,
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            AppTextField(
              key: const ValueKey<String>('member-signup-password-confirm'),
              controller: _passwordConfirm,
              hint: l.signUpPasswordConfirmHint,
              errorText: _errors.of(_Field.passwordConfirm),
              prefixIcon: AppIcons.lock,
              size: AppFieldSize.large,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.newPassword],
              onChanged: _onEdited,
              onSubmitted: (_) => _register(),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            // 약관·개인정보·건강정보·만 14세 확인을 가입 전에 받는다(#2819).
            SignupConsentBlock(
              checked: _consents,
              enabled: !_loading,
              onChanged: (Set<String> next) => setState(() => _consents = next),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            AppButton(
              key: const ValueKey<String>('member-signup-submit'),
              label: l.signUpAction,
              onPressed: _canSubmit ? _register : null,
              loading: _loading,
              size: OnCareButtonSize.large,
              fullWidth: true,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            // Wrap 인 이유: 로케일에 따라 이 줄의 길이가 크게 달라진다.
            // Row 로 두면 영어에서 화면 밖으로 넘친다(폭 400 기준 실측).
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  l.signUpHaveAccountQuestion,
                  style: context.oncare
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                AppButton(
                  label: l.authSignInAction,
                  onPressed: _backToSignIn,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 이메일 칸 아래의 인증 코드 단계(#3038). 요청 전에는 `인증 코드 받기` 버튼,
  /// 요청한 뒤에는 코드 칸·남은 시간·`다시 받기` 다.
  Widget _emailCodeSection(AppLocalizations l) {
    if (!_codeRequested) {
      return AppButton(
        key: const ValueKey<String>('member-signup-code-send'),
        label: l.signUpEmailCodeSend,
        onPressed: _loading ? null : _requestCode,
        loading: _codeRequesting,
        variant: AppButtonVariant.secondary,
        fullWidth: true,
      );
    }
    final int left = _codeSecondsLeft;
    final int resendLeft = _resendSecondsLeft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTextField(
          key: const ValueKey<String>('member-signup-code'),
          controller: _code,
          hint: l.signUpEmailCodeHint,
          helper: left > 0
              ? l.signUpEmailCodeRemaining(_clock(left))
              : l.signUpEmailCodeExpired,
          errorText: _codeServerError,
          prefixIcon: AppIcons.lock,
          size: AppFieldSize.large,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.oneTimeCode],
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(SignupEmailCode.length),
          ],
          onChanged: _onCodeEdited,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: const ValueKey<String>('member-signup-code-resend'),
            label: resendLeft > 0
                ? l.signUpEmailCodeResendIn(resendLeft)
                : l.signUpEmailCodeResend,
            onPressed: resendLeft > 0 || _loading ? null : _requestCode,
            loading: _codeRequesting,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
          ),
        ),
        // 데모는 메일을 보내지 않는다 — 받아 주는 코드를 알려 끝까지 가입해 볼 수
        // 있게 한다.
        if (ref.watch(signupDemoCodeHintProvider))
          AppBanner(
            key: const ValueKey<String>('member-signup-code-demo'),
            title: l.signUpEmailCodeDemoNote(SignupEmailCode.demoCode),
            density: AppBannerDensity.compact,
          ),
      ],
    );
  }
}
