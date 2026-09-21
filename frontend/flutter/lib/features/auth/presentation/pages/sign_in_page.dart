import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/presentation/first_run_route.dart';
import 'package:oncare/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/sign_in_failure.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 로그인 화면 로고의 한 변. 인증 틀 안에서 가장 먼저 눈에 드는 그림이다.
const double _kLogoSize = 128;

/// 로그인 화면에서 형식을 검사하는 칸.
enum _Field { email, password }

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

  /// 칸 아래 오류 문구. 첫 제출 전에는 숨기고, 오류를 보인 칸은 입력하는 대로
  /// 다시 검사한다(#1784).
  late final AppFieldErrors<_Field> _errors = AppFieldErrors<_Field>(_check);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 칸의 지금 값에 대한 오류 문구. 비밀번호는 비었는지만 본다 — 가입 규칙을
  /// 여기서도 걸면 규칙 이전에 만든 계정이 로그인에서 막힌다(#1784).
  String? _check(_Field field) =>
      authInputErrorText(AppLocalizations.of(context), switch (field) {
        _Field.email => AppInputRules.email(_email.text),
        _Field.password => AppInputRules.signInPassword(_password.text),
      });

  /// 오류를 보인 칸이 있을 때만 입력마다 다시 그려 문구가 값을 따라가게 한다.
  void _onEdited(String _) {
    if (_errors.isWatching) setState(() {});
  }

  void _enterDemo() {
    ref.read(sessionControllerProvider.notifier).enterDemo();
    context.go(AppRoutes.dashboard);
  }

  Future<void> _login() async {
    if (_loading) return;
    final AppLocalizations l = AppLocalizations.of(context);
    // 틀린 칸이 하나라도 있으면 요청을 보내지 않고 칸 아래에 알린다.
    if (!_errors.validate(_Field.values)) {
      setState(() {});
      return;
    }
    final email = _email.text.trim();
    final password = _password.text;
    // 로그인에 성공하면 라우터의 세션 가드가 이 화면을 그 자리에서 대시보드로
    // 갈아 치운다. 그 뒤에도 갈 곳을 정하고 옮길 수 있도록, 위젯에 매인 것이
    // 아닌 라우터·컨테이너를 먼저 붙들어 둔다(#1927).
    // 라우터가 없는 자리(위젯 하나만 띄우는 테스트)에서는 옮길 곳도 없다.
    final GoRouter? router = GoRouter.maybeOf(context);
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    setState(() => _loading = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .login(email: email, password: password);
      // 첫 설정을 아직 안 한 회원**만** 옮긴다(#1927). 로그인에 성공하면 라우터의
      // 세션 가드가 이미 홈으로 보내 두었으므로, 홈으로 한 번 더 `go` 하면
      // 탭 껍데기(`StatefulShellRoute`)가 다시 세워지며 열려 있던 탭이 초기화된다.
      final String next = await firstRouteAfterSignIn(container);
      if (next != AppRoutes.dashboard) router?.go(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // 비밀번호 탓은 서버가 자격 증명을 거절했을 때만 한다(#1940).
      showAppToast(
        context,
        signInFailureText(l, signInFailureOf(e)),
        type: AppToastType.error,
      );
    }
  }

  Future<void> _social(String provider) async {
    final AppLocalizations l = AppLocalizations.of(context);
    if (_loading) return;
    // 이메일 로그인과 같은 이유로 먼저 붙들어 둔다(#1927).
    // 라우터가 없는 자리(위젯 하나만 띄우는 테스트)에서는 옮길 곳도 없다.
    final GoRouter? router = GoRouter.maybeOf(context);
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    setState(() => _loading = true);
    try {
      // #330: 실제 SDK 연동 시 이 분기를 provider 토큰 교환으로 교체한다.
      final session = ref.read(sessionControllerProvider.notifier);
      if (ref.read(appConfigProvider).usesMockSocialLogin) {
        await session.socialLogin(
          provider: provider,
          token: 'demo-$provider-token',
        );
      } else {
        await session.login(email: 'minsu@oncare.com', password: 'oncare123');
      }
      final String next = await firstRouteAfterSignIn(container);
      if (next != AppRoutes.dashboard) router?.go(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(context, l.authSocialSignInFailed, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
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
            errorText: _errors.of(_Field.email),
            prefixIcon: AppIcons.mail,
            size: AppFieldSize.large,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: _onEdited,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('member-login-password'),
            controller: _password,
            hint: l.authPasswordHint,
            errorText: _errors.of(_Field.password),
            prefixIcon: AppIcons.lock,
            size: AppFieldSize.large,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onChanged: _onEdited,
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
          ...<Widget>[
            AppLabeledDivider(label: l.authSocialDivider),
            const SizedBox(height: OnCareSpacing.s16),
            // 전체 폭 버튼이면 로그인 버튼과 무게가 같고 화면이 길어진다 —
            // 원형 아이콘 버튼으로 가운데에 나란히 둔다(#1783).
            AppSocialLoginRow(
              children: <Widget>[
                AppSocialLoginButton(
                  key: const ValueKey<String>('member-login-kakao'),
                  provider: AppSocialProvider.kakao,
                  label: l.authKakaoAction,
                  onPressed: _loading ? null : () => _social('kakao'),
                ),
                AppSocialLoginButton(
                  key: const ValueKey<String>('member-login-google'),
                  provider: AppSocialProvider.google,
                  label: l.authGoogleAction,
                  onPressed: _loading ? null : () => _social('google'),
                ),
              ],
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
