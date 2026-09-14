import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Trainer login screen — email/password login. Layout follows the shared
/// [AppAuthLayout]. Wired to [SessionController].
///
/// "로그인 없이 데모 둘러보기" 진입은 화면에서 내렸다. 코드는 지우지 않고
/// [AppConfig.showDemoEntry] 로 감춰 두었으므로, 다시 열려면
/// `--dart-define=SHOW_DEMO_ENTRY=true` 로 빌드한다. (#1526)
class TrainerSignInPage extends ConsumerStatefulWidget {
  /// Creates the trainer login screen.
  const TrainerSignInPage({super.key});

  @override
  ConsumerState<TrainerSignInPage> createState() => _TrainerSignInPageState();
}

class _TrainerSignInPageState extends ConsumerState<TrainerSignInPage> {
  /// On-Care 로고 한 변. 부품 치수라 토큰 목록에 없다.
  static const double _logoSize = 132;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 로그인 뒤에 갈 자리. 딥링크로 들어와 로그인 화면을 거친 경우 인증 게이트가
  /// 목적지를 `?from=` 에 실어 두었으므로, 대시보드가 아니라 그 자리로 잇는다.
  /// 그냥 로그인하러 온 경우에는 없으니 대시보드다. (#701)
  String get _destination =>
      AppRoutes.resumeTarget(GoRouterState.of(context).uri.toString()) ??
      AppRoutes.dashboard;

  void _enterDemo() {
    final destination = _destination;
    ref.read(sessionControllerProvider.notifier).enterDemo();
    context.go(destination);
  }

  void _onSignUp() => context.push(AppRoutes.signUp);

  Future<void> _social(String provider) async {
    if (_loading) return;
    final destination = _destination;
    setState(() => _loading = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .socialLogin(provider: provider);
      if (!mounted) return;
      context.go(destination);
    } catch (_) {
      // 요청 중 화면을 떠났으면 여기서 끝낸다 — 아래 `AppLocalizations.of` 가
      // 이미 해제된 context 를 조회하게 된다.
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(
        context,
        AppLocalizations.of(context).authErrSocialFailed,
        type: AppToastType.error,
      );
    }
  }

  Future<void> _login() async {
    if (_loading) return;
    final destination = _destination;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      showAppToast(
        context,
        AppLocalizations.of(context).authErrEmptyCredentials,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .login(email: email, password: password);
      if (!mounted) return;
      context.go(destination);
    } on AuthException catch (e) {
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
      setState(() => _loading = false);
      showAppToast(context, authFailureText(l, e), type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(
        context,
        AppLocalizations.of(context).authErrSignInFailed,
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 가입 경로는 이제 실 API 모드에서도 열린다 — `/auth/trainer/register` 가
    // 헬스장 초대 코드로 트레이너 계정을 만든다(#475). 전에는 회원용
    // `/auth/register` 로 나가 role='member' 계정이 생겼고, 그 계정은
    // `/trainer/me` 에서 403 이라 가입해도 아무것도 할 수 없었다.
    const signUpEnabled = true;
    return AppAuthLayout(
      // 브랜드 — On-Care 로고(테두리 없이 크게).
      logo: Image.asset(
        'assets/images/oncare-logo.png',
        width: _logoSize,
        height: _logoSize,
        fit: BoxFit.contain,
      ),
      title: l.appTitleSpaced,
      subtitle: l.authTagline,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: const ValueKey<String>('trainer-login-email'),
            controller: _email,
            hint: l.authEmail,
            prefixIcon: Icons.mail_outline_rounded,
            size: AppFieldSize.large,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('trainer-login-password'),
            controller: _password,
            hint: l.authPassword,
            prefixIcon: Icons.lock_outline_rounded,
            size: AppFieldSize.large,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            suffix: AppIconButton(
              // 아이콘만 있는 버튼이라 무엇을 켜고 끄는지 말할 데가
              // 툴팁뿐이다(#972).
              tooltip: _obscure ? l.a11yShowPassword : l.a11yHidePassword,
              icon: _obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: OnCareColors.textTertiary,
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s24),
          AppButton(
            key: const ValueKey<String>('trainer-login-submit'),
            label: l.authSignIn,
            onPressed: _login,
            size: OnCareButtonSize.large,
            loading: _loading,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s16),
          const _OrDivider(),
          const SizedBox(height: OnCareSpacing.s16),
          _SocialButton.kakao(
            label: l.authContinueKakao,
            onTap: _loading ? null : () => _social('kakao'),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _SocialButton.google(
            label: l.authContinueGoogle,
            onTap: _loading ? null : () => _social('google'),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (signUpEnabled)
            // Wrap, not Row: 영어 문구("Don't have an account?" +
            // "Sign up")는 한국어보다 길어 좁은 폭에서 Row 가 넘쳤다.
            // 줄바꿈으로 흘려보내면 어느 언어에서도 잘리지 않는다. (#501)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  l.authNoAccount,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                AppButton(
                  label: l.authSignUp,
                  onPressed: _loading ? null : _onSignUp,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                ),
              ],
            ),
          // 로그인 없이 들어가는 경로는 기본으로 감춰 둔다 — 되돌릴
          // 여지를 남겨야 해서 지우는 대신 플래그로 막았다. (#1526)
          if (ref.watch(appConfigProvider).showDemoEntry)
            Center(
              child: AppButton(
                key: const Key('demoEnterButton'),
                label: l.authBrowseDemo,
                onPressed: _loading ? null : _enterDemo,
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
              ),
            ),
        ],
      ),
    );
  }
}

/// "— 또는 —" separator between the email login and social buttons.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: AppDivider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
          child: Text(
            AppLocalizations.of(context).authOr,
            style: context.oncare
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
        const Expanded(child: AppDivider()),
      ],
    );
  }
}

/// Provider-branded social sign-in button (kakao / google). [onTap] drives
/// the demo-token social exchange.
///
/// 카카오는 외부 브랜드 색(예외 토큰)을 입어야 해서 [AppButton] 으로는 그릴 수
/// 없다. 두 버튼이 한 모양이도록 구글도 같은 틀에 흰 바탕 + 테두리로 그린다.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
  });

  factory _SocialButton.kakao({
    required String label,
    required VoidCallback? onTap,
  }) => _SocialButton(
    label: label,
    icon: Icons.chat_bubble_rounded,
    background: OnCareColors.kakaoYellow,
    foreground: OnCareColors.kakaoLabel,
    onTap: onTap,
  );

  factory _SocialButton.google({
    required String label,
    required VoidCallback? onTap,
  }) => _SocialButton(
    label: label,
    icon: Icons.g_mobiledata_rounded,
    background: OnCareColors.surfaceCard,
    foreground: OnCareColors.textPrimary,
    border: OnCareColors.lineStrong,
    onTap: onTap,
  );

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: OnCareRadius.mdAll,
        side: border == null ? BorderSide.none : BorderSide(color: border!),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: tokens.density.buttonLarge,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: foreground, size: OnCareSize.iconLarge),
              const SizedBox(width: OnCareSpacing.s8),
              // 버튼 폭은 400 으로 고정인데 라벨은 로케일·글자 배율을 따라
              // 길어진다. `Continue with Google` 은 배율 1.3 에서 그대로 넘쳤다
              // (#849). 잘라내지 않고 줄여서 그린다 — `Continue with Goo…` 가
              // 되면 어느 계정으로 들어가는지가 사라진다.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: tokens
                        .text(OnCareTypography.buttonLarge)
                        .copyWith(color: foreground),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
