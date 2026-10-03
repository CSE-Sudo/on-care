import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/auth/data/repositories/signup_email_code_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/entities/signup_consent.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/signup_email_code_repository.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/auth/presentation/widgets/trainer_consent_block.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 가입 화면에서 검사하는 칸. 이름도 꼭 받는다(#1784).
enum _Field { name, email, password, passwordConfirm }

/// 트레이너 회원가입 화면 — 공용 [AppAuthLayout]. 이름/이메일/
/// 비밀번호로 계정을 만들고, 성공 시 자동 로그인해 고객 탭으로 진입한다
/// (라우터 가드가 인증 상태를 감지).
///
/// 소속 헬스장은 여기서 받지 않는다 — 가입 뒤 헬스장을 찾아 고른다(#1627).
/// 예전의 헬스장 초대 코드 칸은 발급 경로가 없어 걷어 냈다.
///
/// 가입 전에 이메일 인증 코드를 받는다(#3038). `인증 코드 받기` 를 누르면 코드
/// 칸이 열리고, 6자리를 넣어야 가입 버튼이 켜진다. 이메일을 고치면 그 코드는
/// 다른 주소의 것이라 칸을 비우고 닫는다.
class TrainerSignUpPage extends ConsumerStatefulWidget {
  /// Creates the trainer sign-up screen.
  const TrainerSignUpPage({super.key});

  @override
  ConsumerState<TrainerSignUpPage> createState() => _TrainerSignUpPageState();
}

class _TrainerSignUpPageState extends ConsumerState<TrainerSignUpPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  /// 인증 코드를 요청하는 중인가(#3038).
  bool _codeRequesting = false;

  /// 마지막 코드 요청의 응답. null 이면 코드 칸을 보이지 않는다.
  SignupEmailCodeSent? _codeSent;

  /// 코드를 받은 이메일([SignupEmailCode.emailKey] 모양). 이메일 칸이 이 값과
  /// 달라지면 코드를 버린다.
  String? _codeEmail;

  /// 코드가 살아 있는 남은 초 · 다시 받기까지 남은 초. 1초 [_codeTicker] 가 센다
  /// — 벽시계가 아니라 센 값이라 테스트의 가짜 시간에서도 같게 흐른다.
  int _codeSecondsLeft = 0;
  int _resendSecondsLeft = 0;
  Timer? _codeTicker;

  /// 서버가 돌려준 코드 칸 오류(틀림·만료·빠짐). 코드를 고치면 지운다.
  String? _codeServerError;

  bool get _codeReady =>
      _codeSent != null && SignupEmailCode.isComplete(_code.text);

  /// 체크한 동의 항목(#2819). 필수 항목이 모두 있어야 가입 버튼이 켜진다.
  Set<String> _consents = <String>{};

  bool get _consentsReady => TrainerSignupConsent.hasAllRequired(_consents);

  /// 칸 아래 오류 문구. 첫 제출 전에는 숨기고, 오류를 보인 칸은 입력하는 대로
  /// 다시 검사한다(#1784).
  late final AppFieldErrors<_Field> _errors = AppFieldErrors<_Field>(_check);

  @override
  void dispose() {
    _codeTicker?.cancel();
    _code.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  /// 칸의 지금 값에 대한 오류 문구.
  String? _check(_Field field) {
    final AppLocalizations l = AppLocalizations.of(context);
    return switch (field) {
      _Field.name => authInputErrorText(l, AppInputRules.name(_name.text)),
      _Field.email => authInputErrorText(l, AppInputRules.email(_email.text)),
      _Field.password => authInputErrorText(
        l,
        AppInputRules.signUpPassword(_password.text),
      ),
      _Field.passwordConfirm => authInputErrorText(
        l,
        AppInputRules.passwordConfirm(_password.text, _passwordConfirm.text),
      ),
    };
  }

  /// 오류를 보인 칸이 있을 때만 입력마다 다시 그린다. 비밀번호를 고치면
  /// 확인 칸의 일치 여부도 바뀌므로 칸을 가리지 않고 다시 그린다.
  void _onEdited(String _) {
    if (_errors.isWatching) setState(() {});
  }

  /// 이메일을 고치면 받아 둔 코드는 다른 주소의 것이다(#3038) — 코드는 (이메일,
  /// 목적) 에 묶인다. 칸을 비우고 닫아, 새 주소로 다시 받게 한다.
  void _onEmailEdited(String value) {
    final String? codeEmail = _codeEmail;
    if (codeEmail != null && SignupEmailCode.emailKey(value) != codeEmail) {
      _discardCode();
    }
    _onEdited(value);
  }

  void _discardCode() {
    _codeTicker?.cancel();
    _codeTicker = null;
    _code.clear();
    setState(() {
      _codeSent = null;
      _codeEmail = null;
      _codeServerError = null;
      _codeSecondsLeft = 0;
      _resendSecondsLeft = 0;
    });
  }

  void _onCodeEdited(String _) {
    // 버튼의 켜짐(6자리)이 입력마다 바뀐다.
    setState(() => _codeServerError = null);
  }

  void _tick(Timer timer) {
    if (!mounted) return;
    setState(() {
      if (_codeSecondsLeft > 0) _codeSecondsLeft--;
      if (_resendSecondsLeft > 0) _resendSecondsLeft--;
    });
    if (_codeSecondsLeft == 0 && _resendSecondsLeft == 0) {
      timer.cancel();
      _codeTicker = null;
    }
  }

  /// `인증 코드 받기` · `다시 받기`. 이메일 형식부터 본다 — 틀린 주소로는
  /// 요청하지 않고 이메일 칸 아래에 알린다.
  Future<void> _requestCode() async {
    if (_codeRequesting || _loading) return;
    if (!_errors.validate(const <_Field>[_Field.email])) {
      setState(() {});
      return;
    }
    final String email = _email.text.trim();
    setState(() => _codeRequesting = true);
    try {
      final SignupEmailCodeSent sent = await ref
          .read(signupEmailCodeRepositoryProvider)
          .request(email: email);
      if (!mounted) return;
      _codeTicker?.cancel();
      _code.clear();
      setState(() {
        _codeRequesting = false;
        _codeSent = sent;
        _codeEmail = SignupEmailCode.emailKey(email);
        _codeServerError = null;
        _codeSecondsLeft = sent.expiresInMinutes * 60;
        _resendSecondsLeft = sent.resendAfterSeconds;
      });
      _codeTicker = Timer.periodic(const Duration(seconds: 1), _tick);
    } on SignupEmailCodeError catch (e) {
      if (!mounted) return;
      setState(() => _codeRequesting = false);
      _showCodeRequestFailure(e.kind);
    } on Object {
      if (!mounted) return;
      setState(() => _codeRequesting = false);
      _showCodeRequestFailure(SignupEmailCodeFailure.temporary);
    }
  }

  void _showCodeRequestFailure(SignupEmailCodeFailure kind) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String message = switch (kind) {
      SignupEmailCodeFailure.invalidEmail => l.authErrEmailInvalid,
      SignupEmailCodeFailure.tooMany => l.signUpCodeTooMany,
      SignupEmailCodeFailure.unavailable => l.signUpCodeUnavailable,
      SignupEmailCodeFailure.temporary => l.signUpCodeRequestFailed,
    };
    showAppToast(context, message, type: AppToastType.error);
  }

  void _backToSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.signIn);
    }
  }

  Future<void> _register() async {
    if (_loading) return;
    // 버튼은 꺼져 있지만 확인 칸의 완료 키로도 여기 온다(#2819). 인증 코드
    // 6자리도 같다(#3038).
    if (!_consentsReady || !_codeReady) return;
    // 틀린 칸이 하나라도 있으면 요청을 보내지 않고 칸 아래에 알린다. 서버가
    // 돌려준 실패(이메일 중복 등)만 아래에서 토스트로 알린다.
    final bool valid = _errors.validate(<_Field>[
      _Field.name,
      _Field.email,
      _Field.password,
      _Field.passwordConfirm,
    ]);
    if (!valid) {
      setState(() {});
      return;
    }
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    setState(() => _loading = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .register(
            email: email,
            password: password,
            name: name,
            emailCode: _code.text.trim(),
            consents: TrainerSignupConsent.toPayload(_consents),
          );
      // 계정이 만들어진 뒤에만 새 비밀번호를 브라우저에 저장하게 한다(#2295).
      // 가입이 끝나면 인증 게이트가 곧 이 화면을 걷어 내므로 `mounted` 를
      // 보기 전에 알린다 — 실패한 경로는 여기를 지나지 않는다.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      // 소속 헬스장부터 고르게 한다 — 인증 게이트와 같은 목적지다(#2543).
      context.go(AppRoutes.mySection('edit'));
    } on AuthException catch (e) {
      // 가입 화면은 요청 중에도 뒤로 가기가 열려 있다 — 떠난 뒤 실패가 돌아오면
      // 해제된 context 로 로케일을 조회하게 된다.
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
      // 인증 코드 문제는 코드 칸 아래에 둔다(#3038) — 폼은 그대로 남는다.
      if (e.failure == AuthFailure.emailCodeInvalid ||
          e.failure == AuthFailure.emailCodeRequired) {
        setState(() {
          _loading = false;
          _codeServerError = authFailureText(l, e);
        });
        return;
      }
      setState(() => _loading = false);
      showAppToast(context, authFailureText(l, e), type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(
        context,
        AppLocalizations.of(context).authErrSignUpFailed,
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle mutedStyle = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);
    return AppAuthLayout(
      leading: AppBackButton(onPressed: _backToSignIn),
      title: l.authSignUpAction,
      subtitle: l.authSignUpSubtitle,
      // 새 계정의 이름·이메일·비밀번호를 한 묶음으로 알린다(#2295). 가입하지
      // 않고 떠날 때는 저장하지 않는다 — 기본값(commit)이면 뒤로만 가도
      // 쓰다 만 비밀번호의 저장 제안이 뜬다.
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppTextField(
              key: const ValueKey<String>('trainer-signup-name'),
              controller: _name,
              hint: l.authName,
              errorText: _errors.of(_Field.name),
              prefixIcon: AppIcons.person,
              size: AppFieldSize.large,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.name],
              onChanged: _onEdited,
            ),
            const SizedBox(height: OnCareSpacing.s12),
            AppTextField(
              key: const ValueKey<String>('trainer-signup-email'),
              controller: _email,
              hint: l.authEmailHint,
              errorText: _errors.of(_Field.email),
              // 로그인 화면과 같은 채운 편지·자물쇠다(#2466).
              prefixIcon: AppIcon.setOf(context).mail,
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
            ..._codeStep(l, mutedStyle),
            const SizedBox(height: OnCareSpacing.s12),
            AppTextField(
              key: const ValueKey<String>('trainer-signup-password'),
              controller: _password,
              hint: l.signUpPasswordHint,
              errorText: _errors.of(_Field.password),
              prefixIcon: AppIcon.setOf(context).lock,
              size: AppFieldSize.large,
              obscureText: _obscure,
              textInputAction: TextInputAction.next,
              // 저장된 비밀번호를 채우지 않고 새 비밀번호를 제안받는 칸이다.
              autofillHints: const <String>[AutofillHints.newPassword],
              onChanged: _onEdited,
              // 로그인 화면과 같은 부품이다(#2466). 아이콘만 있는 버튼이라
              // 무엇을 켜고 끄는지는 툴팁이 말한다(#972).
              suffix: AppPasswordToggle(
                obscure: _obscure,
                showLabel: l.a11yShowPassword,
                hideLabel: l.a11yHidePassword,
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            AppTextField(
              key: const ValueKey<String>('trainer-signup-password-confirm'),
              controller: _passwordConfirm,
              hint: l.authPasswordConfirm,
              errorText: _errors.of(_Field.passwordConfirm),
              prefixIcon: AppIcon.setOf(context).lock,
              size: AppFieldSize.large,
              obscureText: _obscure,
              // 마지막 칸이라 제출 액션이 여기 붙는다.
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.newPassword],
              onChanged: _onEdited,
              onSubmitted: (_) => _register(),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            // 간주 동의 대신 항목마다 명시적으로 체크한다(#2819). 문서는
            // 동의하기 전에 열 수 있다 — 세션 없이 열리는 라우트다(#968).
            TrainerConsentBlock(
              checked: _consents,
              enabled: !_loading,
              onChanged: (Set<String> next) => setState(() => _consents = next),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            AppButton(
              key: const ValueKey<String>('trainer-signup-submit'),
              label: l.authSignUpAndStart,
              onPressed: _consentsReady && _codeReady ? _register : null,
              size: OnCareButtonSize.large,
              loading: _loading,
              fullWidth: true,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            // Row 가 아니라 Wrap — 영어 문구가 길어 좁은 폭에서
            // 넘친다(로그인 화면과 같은 이유). (#501)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(l.authHasAccount, style: mutedStyle),
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

  /// 이메일 칸 아래의 인증 단계(#3038). 코드를 받기 전에는 `인증 코드 받기`
  /// 버튼만, 받은 뒤에는 코드 칸·남은 시간·`다시 받기` 가 선다.
  List<Widget> _codeStep(AppLocalizations l, TextStyle mutedStyle) {
    final SignupEmailCodeSent? sent = _codeSent;
    if (sent == null) {
      return <Widget>[
        AppButton(
          key: const ValueKey<String>('trainer-signup-code-send'),
          label: l.signUpCodeSend,
          onPressed: _loading ? null : _requestCode,
          loading: _codeRequesting,
          variant: AppButtonVariant.secondary,
          fullWidth: true,
        ),
      ];
    }
    final String? demoCode = sent.demoCode;
    return <Widget>[
      // 가입된 주소든 아니든 같은 안내다 — 다르게 말하면 가입 여부가 드러난다.
      Text(
        l.signUpCodeSentNotice,
        key: const ValueKey<String>('trainer-signup-code-notice'),
        style: mutedStyle,
      ),
      if (demoCode != null) ...<Widget>[
        const SizedBox(height: OnCareSpacing.s8),
        AppBanner(
          key: const ValueKey<String>('trainer-signup-code-demo'),
          title: l.signUpCodeDemoNote(demoCode),
          density: AppBannerDensity.compact,
        ),
      ],
      const SizedBox(height: OnCareSpacing.s8),
      AppTextField(
        key: const ValueKey<String>('trainer-signup-code'),
        controller: _code,
        hint: l.signUpCodeLabel,
        helper: _codeSecondsLeft > 0
            ? l.signUpCodeRemaining(_clock(_codeSecondsLeft))
            : l.signUpCodeExpired,
        errorText: _codeServerError,
        prefixIcon: AppIcon.setOf(context).lock,
        size: AppFieldSize.large,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(SignupEmailCode.length),
        ],
        autofillHints: const <String>[AutofillHints.oneTimeCode],
        onChanged: _onCodeEdited,
      ),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppButton(
          key: const ValueKey<String>('trainer-signup-code-resend'),
          label: _resendSecondsLeft > 0
              ? l.signUpCodeResendIn(_resendSecondsLeft)
              : l.signUpCodeResend,
          onPressed: _resendSecondsLeft > 0 || _loading ? null : _requestCode,
          loading: _codeRequesting,
          variant: AppButtonVariant.text,
          size: OnCareButtonSize.small,
        ),
      ),
    ];
  }

  /// 남은 초 → `9:05`. 숫자뿐이라 두 로케일이 같은 모양을 쓴다.
  static String _clock(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
