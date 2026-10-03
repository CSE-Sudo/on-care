import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/app_version/app_version_gate.dart';
import 'package:oncare/core/app_version/store_link.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 스토어 주소 하나를 연다. 열었으면 `true`. 테스트는 이 provider 를 덮는다.
final storeLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
  name: 'storeLauncher',
);

/// 업데이트 필요 화면(#3045).
///
/// 이 빌드가 서버의 최소 지원 버전보다 낮을 때 라우터 가드가 어느 주소에서든
/// 이리 보낸다. 닫기·뒤로가기가 없다 — 옛 빌드는 바뀐 응답을 읽다가 화면마다
/// 오류를 내거나 틀린 값을 보이기 때문이다. 회원 앱의 원래 모양대로 흰 바탕
/// 가운데에 안내(`AppEmptyState`)를 두고, 버튼은 스토어의 On-Care 페이지를 연다.
class UpdateRequiredPage extends ConsumerWidget {
  const UpdateRequiredPage({super.key});

  /// 화면 본문의 Key.
  static const Key bodyKey = ValueKey<String>('update-required-page');

  /// 업데이트 버튼의 Key.
  static const Key actionKey = ValueKey<String>('update-required-action');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AppVersionGateState gate = ref.watch(appVersionGateProvider);
    final List<Uri> uris = storeUrisFor(
      platform: defaultTargetPlatform,
      iosAppStoreId: _iosAppStoreId(ref),
    );
    final String? current = gate.currentVersion;
    final String? min = gate.minVersion;
    final String message = <String>[
      l.updateRequiredMessage,
      if (current != null && min != null)
        l.updateRequiredVersions(current, min),
      if (uris.isEmpty) l.updateRequiredStoreHint,
    ].join('\n');
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: OnCareColors.surfaceCard,
        body: SafeArea(
          child: Center(
            key: bodyKey,
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OnCareLayout.mobileContentMaxWidth,
                ),
                child: AppEmptyState(
                  icon: AppIcons.appUpdate,
                  title: l.updateRequiredTitle,
                  message: message,
                  actionLabel: uris.isEmpty ? null : l.updateRequiredAction,
                  actionKey: actionKey,
                  onAction: uris.isEmpty
                      ? null
                      : () => _openStore(context, ref, uris),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _iosAppStoreId(WidgetRef ref) {
    try {
      return ref.read(appConfigProvider).iosAppStoreId;
    } on Object {
      return null;
    }
  }

  /// 주소를 차례로 열어 본다. 모두 실패하면 알린다 — 조용히 아무 일도 일어나지
  /// 않으면 회원은 앱이 고장 난 것으로 읽는다.
  static Future<void> _openStore(
    BuildContext context,
    WidgetRef ref,
    List<Uri> uris,
  ) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final Future<bool> Function(Uri) launch = ref.read(storeLauncherProvider);
    for (final Uri uri in uris) {
      try {
        if (await launch(uri)) return;
      } on Object {
        // 다음 주소로 넘어간다(예: Play 스토어 앱이 없는 기기).
      }
    }
    toast.show(l.updateRequiredOpenFailed, type: AppToastType.error);
  }
}
