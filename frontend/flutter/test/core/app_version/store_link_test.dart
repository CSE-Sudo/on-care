/// 업데이트 버튼이 여는 스토어 주소(#3045).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/app_version/store_link.dart';

void main() {
  test('안드로이드는 Play 스토어 앱, 그다음 웹 페이지', () {
    expect(
      storeUrisFor(platform: TargetPlatform.android).map((Uri u) => '$u'),
      <String>[
        'market://details?id=com.csesudo.oncare',
        'https://play.google.com/store/apps/details?id=com.csesudo.oncare',
      ],
    );
  });

  test('iOS 는 App Store 앱 페이지', () {
    expect(
      storeUrisFor(
        platform: TargetPlatform.iOS,
        iosAppStoreId: '1234567890',
      ).map((Uri u) => '$u'),
      <String>['https://apps.apple.com/app/id1234567890'],
    );
  });

  test('iOS 앱 ID 가 없거나 숫자가 아니면 열 주소가 없다', () {
    expect(storeUrisFor(platform: TargetPlatform.iOS), isEmpty);
    expect(
      storeUrisFor(platform: TargetPlatform.iOS, iosAppStoreId: ''),
      isEmpty,
    );
    expect(
      storeUrisFor(platform: TargetPlatform.iOS, iosAppStoreId: 'id123'),
      isEmpty,
    );
  });

  test('모바일이 아니면 열 주소가 없다', () {
    for (final TargetPlatform p in <TargetPlatform>[
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(storeUrisFor(platform: p, iosAppStoreId: '1'), isEmpty);
    }
  });

  test('패키지 이름은 안드로이드 applicationId 와 같다', () {
    expect(kAndroidPackageName, 'com.csesudo.oncare');
  });
}
