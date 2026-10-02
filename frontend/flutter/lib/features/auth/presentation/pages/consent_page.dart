import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/account/presentation/first_run_route.dart';
import 'package:oncare/features/auth/domain/signup_consent.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/widgets/signup_consent_block.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 로그인 뒤 동의 화면. (#2819)
///
/// 동의가 남은 계정 — 동의 절차가 생기기 전에 가입한 계정, 소셜 로그인으로
/// 처음 들어온 계정, 문서 버전이 올라간 계정 — 이 다른 화면보다 먼저 거친다.
/// 라우터 가드가 동의가 끝날 때까지 이 화면에 붙든다. 가입 화면과 같은 동의
/// 묶음을 쓴다.
///
/// 동의하지 않을 길도 둔다 — 로그아웃. 그 밖의 화면으로는 갈 수 없다.
class ConsentPage extends ConsumerStatefulWidget {
  const ConsentPage({super.key});

  @override
  ConsumerState<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends ConsumerState<ConsentPage> {
  Set<String> _checked = <String>{};
  bool _saving = false;

  bool get _ready => SignupConsent.hasAllRequired(_checked);

  Future<void> _submit() async {
    if (_saving || !_ready) return;
    final AppLocalizations l = AppLocalizations.of(context);
    // 동의가 남으면 가드가 이 화면을 곧장 걷어 낸다 — 그 뒤에 쓸 것을 미리
    // 잡아 둔다(로그인 화면과 같은 이유).
    final GoRouter? router = GoRouter.maybeOf(context);
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .submitConsents(SignupConsent.toPayload(_checked));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, l.consentPageFailed, type: AppToastType.error);
      return;
    }
    // 가드는 홈으로 보낸다. 첫 설정이 남은 계정(소셜 첫 가입 등)은 그리로 옮긴다.
    try {
      final String next = await firstRouteAfterSignIn(container);
      if (next != AppRoutes.dashboard) router?.go(next);
    } catch (_) {
      // 판단에 실패해도 홈에 있다 — 첫 설정은 다음 복구 때 다시 묻는다.
    }
  }

  Future<void> _signOut() async {
    if (_saving) return;
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppAuthLayout(
      title: l.consentPageTitle,
      subtitle: l.consentPageSubtitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SignupConsentBlock(
            checked: _checked,
            enabled: !_saving,
            onChanged: (Set<String> next) => setState(() => _checked = next),
          ),
          const SizedBox(height: OnCareSpacing.s20),
          AppButton(
            key: const ValueKey<String>('consent-submit'),
            label: l.consentPageAction,
            onPressed: _ready ? _submit : null,
            loading: _saving,
            size: OnCareButtonSize.large,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Center(
            child: AppButton(
              key: const ValueKey<String>('consent-sign-out'),
              label: l.myLogout,
              onPressed: _saving ? null : _signOut,
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
            ),
          ),
        ],
      ),
    );
  }
}
