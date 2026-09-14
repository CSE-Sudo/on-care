import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너 회원가입 화면 — 공용 [AppAuthLayout]. 이름/이메일/
/// 비밀번호와 **헬스장 초대 코드**로 계정을 만들고, 성공 시 자동 로그인해 고객
/// 탭으로 진입한다 (라우터 가드가 인증 상태를 감지).
///
/// 초대 코드가 소속 헬스장을 결정한다(#475). 소속 없는 트레이너는 상담 대상이
/// 될 수 없어(#443·#451) 가입 직후 아무것도 못 하는 계정이 된다.
///
/// **데모에서는 코드 입력을 아예 그리지 않는다.** 검증할 백엔드가 없어 무엇을
/// 넣든 통과하는 죽은 입력이 되고, 무엇보다 데모 화면이 지금과 달라진다.
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
  final TextEditingController _inviteCode = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _inviteCode.dispose();
    super.dispose();
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
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _passwordConfirm.text;
    // 데모에는 코드를 검증할 백엔드가 없어 입력 자체를 그리지 않는다.
    final requiresInviteCode = !ref.read(appConfigProvider).useMockApi;
    final inviteCode = _inviteCode.text.trim();
    if (email.isEmpty || password.isEmpty) {
      showAppToast(
        context,
        AppLocalizations.of(context).authErrEmptyCredentials,
      );
      return;
    }
    if (password.length < 8) {
      showAppToast(
        context,
        AppLocalizations.of(context).authErrPasswordTooShort,
      );
      return;
    }
    if (password != confirm) {
      showAppToast(
        context,
        AppLocalizations.of(context).authErrPasswordMismatch,
      );
      return;
    }
    if (requiresInviteCode && inviteCode.isEmpty) {
      showAppToast(
        context,
        AppLocalizations.of(context).authErrInviteCodeRequired,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .register(
            email: email,
            password: password,
            name: name,
            inviteCode: inviteCode,
          );
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } on AuthException catch (e) {
      // 가입 화면은 요청 중에도 뒤로 가기가 열려 있다 — 떠난 뒤 실패가 돌아오면
      // 해제된 context 로 로케일을 조회하게 된다.
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
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
    // 데모 가입 화면은 지금과 동일해야 한다 — 코드 입력을 그리지 않는다.
    final showInviteCode = !ref.watch(appConfigProvider).useMockApi;
    return AppAuthLayout(
      leading: AppBackButton(onPressed: _backToSignIn),
      title: l.authSignUp,
      subtitle: l.authSignUpSubtitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            controller: _name,
            hint: l.authName,
            prefixIcon: Icons.person_outline_rounded,
            size: AppFieldSize.large,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            controller: _email,
            hint: l.authEmail,
            prefixIcon: Icons.mail_outline_rounded,
            size: AppFieldSize.large,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            controller: _password,
            hint: l.authPasswordHint,
            prefixIcon: Icons.lock_outline_rounded,
            size: AppFieldSize.large,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            suffix: AppIconButton(
              // 아이콘만 있는 버튼이라 무엇을 켜고 끄는지 말할
              // 데가 툴팁뿐이다(#972).
              tooltip: _obscure ? l.a11yShowPassword : l.a11yHidePassword,
              icon: _obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: OnCareColors.textTertiary,
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            controller: _passwordConfirm,
            hint: l.authPasswordConfirm,
            prefixIcon: Icons.lock_outline_rounded,
            size: AppFieldSize.large,
            obscureText: _obscure,
            // 데모에서는 이 필드가 마지막이라 제출 액션이 여기 붙는다.
            textInputAction: showInviteCode
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: showInviteCode ? null : (_) => _register(),
          ),
          if (showInviteCode) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            AppTextField(
              controller: _inviteCode,
              hint: l.authInviteCode,
              prefixIcon: Icons.confirmation_number_rounded,
              size: AppFieldSize.large,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _register(),
            ),
            const SizedBox(height: OnCareSpacing.s4),
            Text(l.authInviteCodeHelp, style: mutedStyle),
          ],
          const SizedBox(height: OnCareSpacing.s24),
          AppButton(
            label: l.authSignUpAndStart,
            onPressed: _register,
            size: OnCareButtonSize.large,
            loading: _loading,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 동의 대상 문서는 동의하기 전에 열 수 있어야 한다 —
          // 두 문서 모두 세션 없이 열리는 라우트다. (#968)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(l.authLegalNotice, style: mutedStyle),
              _LegalLink(
                label: l.myLegalTermsTitle,
                document: AppRoutes.legalTerms,
              ),
              _LegalLink(
                label: l.myLegalPrivacyTitle,
                document: AppRoutes.legalPrivacy,
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          // Row 가 아니라 Wrap — 영어 문구가 길어 좁은 폭에서
          // 넘친다(로그인 화면과 같은 이유). (#501)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(l.authHasAccount, style: mutedStyle),
              AppButton(
                label: l.authSignIn,
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

/// 가입 화면의 약관 링크. 화면을 갈아치우지 않고 push 로 열어, 뒤로 누르면
/// 입력하던 값이 그대로 남아 있게 한다. (#968)
class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.document});

  final String label;
  final String document;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onPressed: () => context.push(AppRoutes.legalDocument(document)),
      variant: AppButtonVariant.text,
      size: OnCareButtonSize.small,
    );
  }
}
