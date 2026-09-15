import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 로그인 화면 로고의 한 변. 인증 틀 안에서 가장 먼저 눈에 드는 그림이다.
const double _kLogoSize = 128;

/// 로그인 화면 — 이메일/비밀번호 로그인 + 소셜 로그인.
///
/// "로그인 없이 데모 둘러보기" 진입은 화면에서 내렸다. 코드는 지우지 않고
/// [AppConfig.showDemoEntry] 로 감춰 두었으므로, 다시 열려면
/// `--dart-define=SHOW_DEMO_ENTRY=true` 로 빌드한다. (#1526)
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
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

  void _enterDemo() {
    ref.read(sessionControllerProvider.notifier).enterDemo();
    context.go(AppRoutes.dashboard);
  }

  Future<void> _login() async {
    if (_loading) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      showAppToast(context, l.authMissingCredentials, type: AppToastType.error);
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).login(
        email: email,
        password: password,
      );
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(context, l.authSignInFailed, type: AppToastType.error);
    }
  }

  Future<void> _social(String provider) async {
    final AppLocalizations l = AppLocalizations.of(context);
    if (_loading) return;
    // 목업이 받아 주지 않는 설정에서는 고정 토큰을 내보내지 않는다. 버튼을
    // 감추는 것과 별개로 이 경로 자체를 한 번 더 막는다(#1553).
    if (!ref.read(appConfigProvider).socialDemoLoginEnabled) return;
    setState(() => _loading = true);
    try {
      // 실 SDK(kakao/google) 연동 전까지는 데모 토큰을 보낸다. 받아 주는 것은
      // 기기 안 목업뿐이라 [AppConfig.socialDemoLoginEnabled] 일 때만 온다.
      await ref
          .read(sessionControllerProvider.notifier)
          .socialLogin(provider: provider, token: 'demo-$provider-token');
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(
        context,
        l.authSocialSignInFailed,
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool socialEnabled = ref
        .watch(appConfigProvider)
        .socialDemoLoginEnabled;
    return AppAuthLayout(
      // 브랜드 — On-Care 로고 (테두리 없이 크게)
      logo: Image.asset(
        'assets/images/oncare-logo.png',
        width: _kLogoSize,
        height: _kLogoSize,
        fit: BoxFit.contain,
      ),
      title: 'On - Care',
      subtitle: l.authTagline,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: const ValueKey<String>('member-login-email'),
            controller: _email,
            hint: l.authEmailHint,
            prefixIcon: AppIcons.mail,
            size: AppFieldSize.large,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('member-login-password'),
            controller: _password,
            hint: l.authPasswordHint,
            prefixIcon: AppIcons.lock,
            size: AppFieldSize.large,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            suffix: _PasswordToggle(
              obscure: _obscure,
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s24),
          AppButton(
            key: const ValueKey<String>('member-login-submit'),
            label: l.authSignInAction,
            onPressed: _login,
            loading: _loading,
            size: OnCareButtonSize.large,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s16),
          // 소셜 버튼은 고정 데모 토큰을 보내므로 목업이 받아 주는
          // 설정에서만 보인다 — 실서버에서는 눌러도 거절된다(#1553).
          if (socialEnabled) ...<Widget>[
            const _OrDivider(),
            const SizedBox(height: OnCareSpacing.s16),
            _KakaoButton(
              label: l.authKakaoAction,
              onTap: _loading ? null : () => _social('kakao'),
            ),
            const SizedBox(height: OnCareSpacing.s8),
            AppButton(
              label: l.authGoogleAction,
              leadingIcon: AppIcons.google,
              onPressed: _loading ? null : () => _social('google'),
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.large,
              fullWidth: true,
            ),
            const SizedBox(height: OnCareSpacing.s12),
          ],
          // Wrap 인 이유: 로케일에 따라 이 줄의 길이가 크게 달라진다.
          // Row 로 두면 영어에서 화면 밖으로 넘친다(폭 400 기준 실측).
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                l.authNoAccountQuestion,
                style: context.oncare
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
              AppButton(
                label: l.authSignUpAction,
                onPressed: () => context.push(AppRoutes.signUp),
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
                label: l.authDemoAction,
                onPressed: _enterDemo,
                variant: AppButtonVariant.text,
              ),
            ),
        ],
      ),
    );
  }
}

/// 비밀번호 보이기/감추기. 아이콘만 있는 버튼이라 무엇을 켜고 끄는지 말할 데가
/// 툴팁뿐이다(#972).
class _PasswordToggle extends StatelessWidget {
  const _PasswordToggle({required this.obscure, required this.onPressed});

  final bool obscure;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppIconButton(
      icon: obscure ? AppIcons.visibilityOff : AppIcons.visibility,
      tooltip: obscure ? l.a11yShowPassword : l.a11yHidePassword,
      color: OnCareColors.textTertiary,
      onPressed: onPressed,
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
            AppLocalizations.of(context).authOrDivider,
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
        const Expanded(child: AppDivider()),
      ],
    );
  }
}

/// 카카오 로그인 버튼 — 카카오 노랑은 외부 브랜드색이라 예외 토큰을 쓴다(#1690).
/// 높이·반경·라벨은 큰 버튼 규격과 같다. Real SDK token acquisition is
/// deferred; the [onTap] currently drives a demo-token exchange.
class _KakaoButton extends StatelessWidget {
  const _KakaoButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Material(
      color: OnCareColors.kakaoYellow,
      borderRadius: OnCareRadius.mdAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: tokens.density.buttonLarge,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const AppIcon(
                  AppIcons.chat,
                  color: OnCareColors.kakaoLabel,
                  size: OnCareSize.iconMedium,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                // 글씨가 커지거나 영어 라벨("Continue with Kakao")이 오면 아이콘과
                // 문구가 버튼 폭을 넘는다. 줄어들 수 있게 두고 넘치면 줄인다. (#995)
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.buttonLarge)
                        .copyWith(color: OnCareColors.kakaoLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
