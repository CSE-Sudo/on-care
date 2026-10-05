import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 로그인 화면에서 형식을 검사하는 칸.
enum _Field { email, password }

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
  static const double _logoSize = 128;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  /// 칸 아래 오류 문구. 첫 제출 전에는 숨기고, 오류를 보인 칸은 입력하는 대로
  /// 다시 검사한다(#1784).
  late final AppFieldErrors<_Field> _errors = AppFieldErrors<_Field>(_check);

  @override
  void initState() {
    super.initState();
    // 실행 중 세션이 만료되어 이 화면으로 왔다면 한 번 알린다(#1546). 알리지
    // 않으면 쓰던 화면이 이유 없이 로그인 폼으로 바뀐 것처럼 보인다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final StateController<bool> notice = ref.read(
        sessionExpiredNoticeProvider.notifier,
      );
      if (!notice.state) return;
      notice.state = false;
      showAppToast(context, AppLocalizations.of(context).authSessionExpired);
    });
  }

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

  /// 로그인 뒤에 갈 자리. 딥링크로 들어와 로그인 화면을 거친 경우 인증 게이트가
  /// 목적지를 `?from=` 에 실어 두었으므로, 대시보드가 아니라 그 자리로 잇는다.
  /// 그냥 로그인하러 온 경우에는 없으니 대시보드다. (#701)
  String get _destination =>
      AppRoutes.resumeTarget(GoRouterState.of(context).uri.toString()) ??
      AppRoutes.dashboard;

  /// 데모는 늘 대시보드에서 시작한다(#2765). 이어 갈 자리(`?from=`)는 실서버
  /// 계정의 주소라(회원 id 포함) 데모 데이터에는 없다 — 이어 가면 '찾을 수 없음'
  /// 이 뜨고, 이전 사용자의 위치를 다음 사람에게 보여 주는 셈이 된다.
  void _enterDemo() {
    ref.read(sessionControllerProvider.notifier).enterDemo();
    context.go(AppRoutes.dashboard);
  }

  void _onSignUp() => context.push(AppRoutes.signUp);

  /// 이 빌드에서 소셜 로그인을 쓸 수 있는가(#2769).
  ///
  /// 실제 카카오·구글 연동(#330) 전이라 데모(목업) 빌드에서만 연다. 전에는 실서버
  /// 빌드에서 이 버튼이 고정된 계정으로 바로 로그인해, 배포 주소에 들어온 누구나
  /// 그 계정의 담당 회원 정보를 볼 수 있었다. 연동이 끝나면 여기서 다시 연다.
  bool get _socialAvailable => ref.read(appConfigProvider).useMockApi;

  Future<void> _social(String provider) async {
    if (_loading || !_socialAvailable) return;
    final destination = _destination;
    setState(() => _loading = true);
    try {
      // #330: 실제 SDK 연동 시 provider 토큰 교환으로 바꾼다. 그 전에는 데모
      // 빌드의 목업 저장소만 이 길을 탄다(실서버 빌드는 버튼이 꺼져 있다).
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
        AppLocalizations.of(context).authSocialSignInFailed,
        type: AppToastType.error,
      );
    }
  }

  Future<void> _login() async {
    if (_loading) return;
    // 틀린 칸이 하나라도 있으면 요청을 보내지 않고 칸 아래에 알린다. 서버가
    // 돌려준 실패(인증 실패·네트워크)만 아래에서 토스트로 알린다.
    if (!_errors.validate(_Field.values)) {
      setState(() {});
      return;
    }
    final destination = _destination;
    final email = _email.text.trim();
    final password = _password.text;
    setState(() => _loading = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .login(email: email, password: password);
      // 서버가 받아 준 자격 증명만 브라우저 비밀번호 저장으로 넘긴다(#2295).
      // 성공하면 라우터 가드가 곧 이 화면을 걷어 내므로 `mounted` 를 보기
      // 전에 알린다 — 실패한 경로는 여기를 지나지 않는다.
      TextInput.finishAutofillContext();
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
    // 트레이너 계정을 만든다(#475). 전에는 회원용
    // `/auth/register` 로 나가 role='member' 계정이 생겼고, 그 계정은
    // `/trainer/me` 에서 403 이라 가입해도 아무것도 할 수 없었다.
    const signUpEnabled = true;
    final bool socialAvailable = ref.watch(appConfigProvider).useMockApi;
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
      // 이메일·비밀번호를 한 묶음으로 알려 브라우저가 함께 채우고 저장하게 한다
      // (#2295). 화면을 그냥 떠날 때는 저장하지 않는다 — 기본값(commit)이면
      // 틀린 비밀번호를 남기고 뒤로 가도 저장 제안이 뜬다.
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppTextField(
              key: const ValueKey<String>('trainer-login-email'),
              controller: _email,
              hint: l.authEmailHint,
              errorText: _errors.of(_Field.email),
              prefixIcon: AppIcon.setOf(context).mail,
              size: AppFieldSize.large,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              // 로그인 아이디가 이메일이다 — 비밀번호 관리자는 username 을 보고
              // 비밀번호 칸과 짝을 짓는다(#2295).
              autofillHints: const <String>[
                AutofillHints.username,
                AutofillHints.email,
              ],
              onChanged: _onEdited,
            ),
            const SizedBox(height: OnCareSpacing.s12),
            AppTextField(
              key: const ValueKey<String>('trainer-login-password'),
              controller: _password,
              hint: l.authPasswordHint,
              errorText: _errors.of(_Field.password),
              prefixIcon: AppIcon.setOf(context).lock,
              size: AppFieldSize.large,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.password],
              onChanged: _onEdited,
              onSubmitted: (_) => _login(),
              // 회원 앱 로그인과 같은 부품이다(#2226).
              suffix: AppPasswordToggle(
                obscure: _obscure,
                showLabel: l.a11yShowPassword,
                hideLabel: l.a11yHidePassword,
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            // 비밀번호를 잊은 트레이너가 메일로 되찾는 입구(#2824). 회원 앱
            // 로그인과 같은 자리 — 비밀번호 칸 바로 아래 오른쪽이다.
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                key: const ValueKey<String>('trainer-login-forgot-password'),
                label: l.authForgotPassword,
                onPressed: _loading
                    ? null
                    : () => context.push(AppRoutes.passwordReset),
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
              ),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            AppButton(
              key: const ValueKey<String>('trainer-login-submit'),
              label: l.authSignInAction,
              onPressed: _login,
              size: OnCareButtonSize.large,
              loading: _loading,
              fullWidth: true,
            ),
            const SizedBox(height: OnCareSpacing.s16),
            AppLabeledDivider(label: l.authSocialDivider),
            const SizedBox(height: OnCareSpacing.s16),
            // 회원앱 로그인과 같은 모양 — 가운데에 나란히 놓인 원형 아이콘
            // 버튼이다(#1783).
            //
            // 실서버 빌드에서는 자리를 지킨 채 꺼 두고 아래에 '준비 중' 안내를
            // 단다 — 숨기면 화면 배치가 바뀐다(#2769).
            AppSocialLoginRow(
              children: <Widget>[
                AppSocialLoginButton(
                  key: const ValueKey<String>('trainer-login-kakao'),
                  provider: AppSocialProvider.kakao,
                  label: l.authKakaoAction,
                  onPressed: _loading || !socialAvailable
                      ? null
                      : () => _social('kakao'),
                ),
                AppSocialLoginButton(
                  key: const ValueKey<String>('trainer-login-google'),
                  provider: AppSocialProvider.google,
                  label: l.authGoogleAction,
                  onPressed: _loading || !socialAvailable
                      ? null
                      : () => _social('google'),
                ),
                AppSocialLoginButton(
                  key: const ValueKey<String>('trainer-login-naver'),
                  provider: AppSocialProvider.naver,
                  label: l.authNaverAction,
                  onPressed: _loading || !socialAvailable
                      ? null
                      : () => _social('naver'),
                ),
                AppSocialLoginButton(
                  key: const ValueKey<String>('trainer-login-apple'),
                  provider: AppSocialProvider.apple,
                  label: l.authAppleAction,
                  onPressed: _loading || !socialAvailable
                      ? null
                      : () => _social('apple'),
                ),
              ],
            ),
            if (!socialAvailable) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              Text(
                l.authSocialComingSoon,
                key: const ValueKey<String>('trainer-login-social-soon'),
                textAlign: TextAlign.center,
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ],
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
                    l.authNoAccountQuestion,
                    style: tokens
                        .text(OnCareTypography.bodySmall)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                  AppButton(
                    label: l.authSignUpAction,
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
                  label: l.authDemoAction,
                  onPressed: _loading ? null : _enterDemo,
                  variant: AppButtonVariant.text,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
