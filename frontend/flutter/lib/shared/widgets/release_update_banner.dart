import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/release/release_update.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 새 버전 안내 배너(#3023) — 회원 웹 탭이 열린 뒤 새 릴리스가 배포됐을 때만
/// 그린다. 모바일 앱 빌드는 확인 자체가 꺼져 있어 그리지 않는다.
///
/// 트레이너 웹과 같은 [AppBanner] 정보 톤이다. `새로고침` 은 페이지를 다시 읽고,
/// 닫기는 같은 배포에 대해 이 탭에서 다시 띄우지 않는다.
class ReleaseUpdateBanner extends ConsumerWidget {
  /// Creates the banner.
  const ReleaseUpdateBanner({super.key});

  /// 배너의 Key — 테스트와 트리 탐색용.
  static const Key bannerKey = ValueKey<String>('release-update-banner');

  /// 닫기 버튼의 Key.
  static const Key dismissKey = ValueKey<String>('release-update-dismiss');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool show = ref.watch(
      releaseUpdateProvider.select((ReleaseUpdateState s) => s.showBanner),
    );
    if (!show) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final ReleaseUpdateController controller = ref.read(
      releaseUpdateProvider.notifier,
    );
    // 상태 표시줄 아래에 선다. 아래 탭 화면은 이 배너 밑에서 시작하므로 위쪽
    // 안전 영역을 다시 두지 않는다(MainShell 이 지운다).
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OnCareSpacing.s16,
          OnCareSpacing.s8,
          OnCareSpacing.s16,
          0,
        ),
        child: AppBanner(
          key: bannerKey,
          icon: AppIcons.sync,
          title: l.releaseUpdateTitle,
          message: l.releaseUpdateMessage,
          actionLabel: l.releaseUpdateReload,
          onAction: controller.reload,
          trailing: AppIconButton(
            key: dismissKey,
            icon: AppIcons.close,
            tooltip: l.releaseUpdateDismiss,
            size: AppIconButtonSize.small,
            onPressed: controller.dismiss,
          ),
        ),
      ),
    );
  }
}
