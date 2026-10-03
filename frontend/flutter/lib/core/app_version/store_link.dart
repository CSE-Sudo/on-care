import 'package:flutter/foundation.dart';

/// 회원 앱 패키지 이름(Play 스토어 주소). `android/app/build.gradle.kts` 의
/// `applicationId` 와 같다(docs/mobile_release.md 4절).
const String kAndroidPackageName = 'com.csesudo.oncare';

/// 업데이트 버튼이 차례로 열어 볼 스토어 주소(#3045). 앞의 것이 열리지 않으면
/// 다음 것을 연다. 비었으면 열 주소가 없다 — 화면은 안내 문구만 보인다.
///
/// * 안드로이드: Play 스토어 앱(`market://`) → 브라우저의 Play 스토어 페이지.
/// * iOS: App Store 의 앱 페이지. 앱 ID 는 등록 뒤에 정해져 [iosAppStoreId] 로
///   받는다(`--dart-define=IOS_APP_STORE_ID`). 없으면 비운다.
/// * 그 밖(웹·데스크톱)은 비운다 — 웹은 버전 검사를 하지 않는다.
List<Uri> storeUrisFor({
  required TargetPlatform platform,
  String? iosAppStoreId,
}) {
  switch (platform) {
    case TargetPlatform.android:
      return <Uri>[
        Uri.parse('market://details?id=$kAndroidPackageName'),
        Uri.parse(
          'https://play.google.com/store/apps/details?id=$kAndroidPackageName',
        ),
      ];
    case TargetPlatform.iOS:
      final String id = iosAppStoreId?.trim() ?? '';
      if (id.isEmpty || !RegExp(r'^\d+$').hasMatch(id)) return const <Uri>[];
      return <Uri>[Uri.parse('https://apps.apple.com/app/id$id')];
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return const <Uri>[];
  }
}
