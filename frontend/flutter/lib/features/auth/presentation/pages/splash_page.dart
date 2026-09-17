import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 시작 화면 — 저장된 세션을 되살리는 동안 머무는 자리. (#1944)
///
/// 예전에는 복구 중인 상태([SessionStatus.unknown])를 로그아웃과 똑같이 라우팅해
/// **완전히 눌리는 로그인 폼**이 떴다. 돌아온 회원에게는 세 가지가 어긋났다.
///  * 느린 망에서 이메일을 치던 중에 복구가 끝나면 화면이 홈으로 튄다.
///  * 먼저 로그인 버튼을 누르면 진행 중이던 복구가 버려진다.
///  * 복구가 비-401 실패(오프라인·500·타임아웃)로 끝나면 아무 안내 없이 로그인
///    화면에 남는다 — 저장된 세션은 멀쩡한데 재시도는 "다음 실행" 뿐이었다.
///
/// 그래서 복구가 끝날 때까지 여기 머물고, 일시적 실패는 **그 자리에서** 다시
/// 시도하게 한다. 기다리기 싫은 회원에게는 로그인 화면으로 가는 길을 함께 둔다.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  /// 로그인 화면과 같은 로고 크기 — 두 화면이 이어져 보여야 한다.
  static const double _logoSize = 128;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final SessionState session = ref.watch(sessionControllerProvider);
    final SessionController controller = ref.read(
      sessionControllerProvider.notifier,
    );
    return AppAuthLayout(
      logo: Image.asset(
        'assets/images/oncare-logo.png',
        width: _logoSize,
        height: _logoSize,
        fit: BoxFit.contain,
      ),
      title: 'On - Care',
      subtitle: session.restoreFailed ? null : l.authRestoring,
      child: session.restoreFailed
          ? Column(
              key: const ValueKey<String>('splash-restore-failed'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l.authRestoreFailed,
                  textAlign: TextAlign.center,
                  style: context.oncare
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                const SizedBox(height: OnCareSpacing.s16),
                AppButton(
                  key: const ValueKey<String>('splash-retry'),
                  label: l.authRestoreRetry,
                  fullWidth: true,
                  onPressed: controller.retryRestore,
                ),
                const SizedBox(height: OnCareSpacing.s8),
                AppButton(
                  key: const ValueKey<String>('splash-sign-in'),
                  label: l.authRestoreSignIn,
                  variant: AppButtonVariant.text,
                  fullWidth: true,
                  onPressed: controller.dismissRestore,
                ),
              ],
            )
          : const Padding(
              key: ValueKey<String>('splash-restoring'),
              padding: EdgeInsets.only(top: OnCareSpacing.s8),
              child: AppLoading(),
            ),
    );
  }
}
