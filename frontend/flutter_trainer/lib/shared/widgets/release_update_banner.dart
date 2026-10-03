import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/release/release_update.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 새 버전 안내 배너(#3023) — 이 탭이 열린 뒤 새 릴리스가 배포됐을 때만 그린다.
///
/// 승인 대기 안내(`TrainerVerificationBanner`)와 같은 [AppBanner] 정보 톤이다.
/// `새로고침` 은 페이지를 다시 읽고, 닫기는 같은 배포에 대해 이 탭에서 다시 띄우지
/// 않는다. 작성 중인 폼은 새로고침 앞에서 브라우저 확인창이 지킨다(#2264).
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OnCareSpacing.s24,
        OnCareSpacing.s16,
        OnCareSpacing.s24,
        0,
      ),
      child: AppBanner(
        key: bannerKey,
        icon: AppIcons.refresh,
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
    );
  }
}
