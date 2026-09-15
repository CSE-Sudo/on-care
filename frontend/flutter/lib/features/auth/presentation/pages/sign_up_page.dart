import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

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

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  /// 표기(하이픈·국번·공백)는 사람마다 달라 숫자만 세고, 그 이상은 여기서
  /// 따지지 않는다 — 가입을 막을 만큼 확실한 규칙이 아니고 회원은 MY 탭에서
  /// 언제든 고칠 수 있다.
  static bool _hasEnoughDigits(String phone) =>
      phone.replaceAll(RegExp(r'\D'), '').length >= 4;

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
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final password = _password.text;
    final confirm = _passwordConfirm.text;
    if (email.isEmpty || password.isEmpty) {
      _error(l.authMissingCredentials);
      return;
    }
    if (!_hasEnoughDigits(phone)) {
      _error(l.signUpPhoneInvalid);
      return;
    }
    if (password.length < 8) {
      _error(l.signUpPasswordTooShort);
      return;
    }
    if (password != confirm) {
      _error(l.signUpPasswordMismatch);
      return;
    }
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
      _error(e.response?.statusCode == 409 ? l.signUpEmailTaken : l.signUpFailed);
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
            controller: _name,
            hint: l.signUpNameHint,
            prefixIcon: Icons.person_rounded,
            size: AppFieldSize.large,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            controller: _email,
            hint: l.authEmailHint,
            prefixIcon: Icons.mail_rounded,
            size: AppFieldSize.large,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 왜 전화번호를 받는지 그 자리에서 말해 준다. 건강 앱이 이유 없이
          // 번호를 물으면 가입을 그만두는 쪽이 자연스럽다.
          AppTextField(
            controller: _phone,
            hint: l.signUpPhoneHint,
            helper: l.signUpPhoneHelper,
            prefixIcon: Icons.phone_rounded,
            size: AppFieldSize.large,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            controller: _password,
            hint: l.signUpPasswordHint,
            prefixIcon: Icons.lock_rounded,
            size: AppFieldSize.large,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
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
            controller: _passwordConfirm,
            hint: l.signUpPasswordConfirmHint,
            prefixIcon: Icons.lock_rounded,
            size: AppFieldSize.large,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _register(),
          ),
          const SizedBox(height: OnCareSpacing.s24),
          AppButton(
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
