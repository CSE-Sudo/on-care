/// 트레이너 웹에서 앱 버전은 고객 지원 하단 한 곳에만 보인다(#3226).
///
/// 빌드 번호·배포 일시는 고객 지원 하단의 기존 버전 줄(#2264, #3047)에 합쳤다. 설정
/// 메뉴에는 따로 버전 줄을 두지 않는다 — 같은 버전이 두 곳에 보이지 않게.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/build_info.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/my/data/build_info.dart';

import '../../helpers/pump_app.dart';

final BuildInfo _released = BuildInfo.fromDefines(
  version: '0.2.0',
  buildNumber: '7032',
  releaseDate: '2026-10-05T05:30:00Z',
);

Future<void> _open(
  WidgetTester tester,
  String section, {
  BuildInfo? info,
  Locale locale = const Locale('ko'),
}) {
  return pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.mySection(section),
    locale: locale,
    extraOverrides: <Override>[
      if (info != null) buildInfoProvider.overrideWithValue(info),
    ],
  );
}

Finder _line() => find.byKey(const ValueKey<String>('support-app-version'));

void main() {
  testWidgets('설정 메뉴에는 버전 줄이 없다', (tester) async {
    await _open(tester, 'settings', info: _released);

    expect(find.textContaining('0.2.0'), findsNothing);
    expect(find.textContaining('7032'), findsNothing);
    expect(find.byKey(const ValueKey<String>('my-build-info')), findsNothing);
  });

  testWidgets('고객 지원에는 버전 줄이 정확히 하나다', (tester) async {
    await _open(tester, 'support', info: _released);

    expect(_line(), findsOneWidget);
    expect(find.textContaining('0.2.0'), findsOneWidget);
    expect(
      find.text('On-Care 트레이너 · 버전 0.2.0 (7032) · 2026년 10월 5일 14:30 KST 배포'),
      findsOneWidget,
    );
  });

  testWidgets('영어 화면은 영어 문구와 날짜 형식이다', (tester) async {
    await _open(tester, 'support', info: _released, locale: const Locale('en'));

    expect(
      find.text(
        'On-Care Trainer · Version 0.2.0 (7032) · Deployed Oct 5, 2026 14:30 KST',
      ),
      findsOneWidget,
    );
  });

  testWidgets('define 이 없는 테스트 빌드는 빌드 버전과 개발 빌드다', (tester) async {
    // provider 를 덮지 않는다 — 실제 define(빈 값)과 버전 읽기 경로 그대로다.
    await _open(tester, 'support');

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(_line()).data,
      'On-Care 트레이너 · 버전 $kTestBuildVersion · 개발 빌드',
    );
    expect(find.textContaining(kTestBuildVersion), findsOneWidget);
  });
}
