import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
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
  bool _obscure = true;
  bool _loading = false;

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
    super.dispose();
  }

  /// 칸의 지금 값에 대한 오류 문구. 전화번호는 `000-0000-0000` 만 받는다 —
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
          .register(email: email, password: password, name: name, phone: phone);
      if (!mounted) return;
      // New accounts land in first-run onboarding; the guard keeps the
      // (now authenticated) user on this protected route.
      context.go(AppRoutes.onboarding);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _error(
        e.response?.statusCode == 409 ? l.signUpEmailTaken : l.signUpFailed,
      );
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: const ValueKey<String>('member-signup-name'),
            controller: _name,
            hint: l.signUpNameHint,
            errorText: _errors.of(_Field.name),
            prefixIcon: Icons.person_rounded,
            size: AppFieldSize.large,
            textInputAction: TextInputAction.next,
            onChanged: _onEdited,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('member-signup-email'),
            controller: _email,
            hint: l.authEmailHint,
            errorText: _errors.of(_Field.email),
            prefixIcon: Icons.mail_rounded,
            size: AppFieldSize.large,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: _onEdited,
          ),
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
            prefixIcon: Icons.phone_rounded,
            size: AppFieldSize.large,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
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
            prefixIcon: Icons.lock_rounded,
            size: AppFieldSize.large,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            onChanged: _onEdited,
            // 아이콘만 있는 버튼이라 무엇을 켜고 끄는지 말할 데가 툴팁뿐이다(#972).
            suffix: AppIconButton(
              icon: _obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
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
            prefixIcon: Icons.lock_rounded,
            size: AppFieldSize.large,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onChanged: _onEdited,
            onSubmitted: (_) => _register(),
          ),
          const SizedBox(height: OnCareSpacing.s24),
          AppButton(
            key: const ValueKey<String>('member-signup-submit'),
            label: l.signUpAction,
            onPressed: _register,
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
    );
  }
}
