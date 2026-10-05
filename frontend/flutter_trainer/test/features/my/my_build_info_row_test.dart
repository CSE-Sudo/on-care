/// 트레이너 설정 메뉴의 `버전 정보` 줄(#3226).
///
/// 지금 떠 있는 웹 빌드가 어느 배포인지 화면에서 바로 읽혀야 한다 — 회원 앱과 같은
/// 버전(빌드 번호)과 KST 배포 일시. 빌드 번호가 없는 빌드는 개발 빌드로 보인다. 누르는
/// 줄이 아니라 화살표가 없고, 메뉴 맨 끝(로그아웃 아래)에 선다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/build_info.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/my/data/build_info.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

final BuildInfo _released = BuildInfo.fromDefines(
  version: '0.2.0',
  buildNumber: '7032',
  releaseDate: '2026-10-05T05:30:00Z',
);

Future<void> _openSettings(
  WidgetTester tester, {
  BuildInfo? info,
  Locale locale = const Locale('ko'),
}) {
  return pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.mySection('settings'),
    locale: locale,
    extraOverrides: <Override>[
      if (info != null) buildInfoProvider.overrideWithValue(info),
    ],
  );
}

Finder _row() => find.byKey(const ValueKey<String>('my-build-info'));

AppListRow _rowWidget(WidgetTester tester) => tester.widget<AppListRow>(_row());

void main() {
  testWidgets('배포 빌드는 버전(빌드 번호)과 KST 배포 일시를 보인다', (tester) async {
    await _openSettings(tester, info: _released);

    expect(_row(), findsOneWidget);
    expect(_rowWidget(tester).title, '버전 정보');
    expect(
      _rowWidget(tester).subtitle,
      '0.2.0 (7032) · 2026년 10월 5일 14:30 KST 배포',
    );
    expect(
      find.descendant(
        of: _row(),
        matching: find.text('0.2.0 (7032) · 2026년 10월 5일 14:30 KST 배포'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('영어 화면은 영어 문구와 날짜 형식이다', (tester) async {
    await _openSettings(tester, info: _released, locale: const Locale('en'));

    expect(_rowWidget(tester).title, 'Version');
    expect(
      _rowWidget(tester).subtitle,
      '0.2.0 (7032) · Deployed Oct 5, 2026 14:30 KST',
    );
  });

  testWidgets('빌드 번호가 없으면 pubspec 버전과 개발 빌드', (tester) async {
    await _openSettings(tester, info: BuildInfo.fromDefines(version: '0.2.0'));

    expect(_rowWidget(tester).subtitle, '0.2.0 · 개발 빌드');
  });

  testWidgets('define 이 없는 테스트 빌드 그대로 띄우면 빌드 버전과 개발 빌드다', (tester) async {
    // provider 를 덮지 않는다 — 실제 define(빈 값)과 빌드 정보 읽기 경로 그대로다.
    await _openSettings(tester);

    expect(tester.takeException(), isNull);
    expect(_rowWidget(tester).subtitle, '$kTestBuildVersion · 개발 빌드');
  });

  testWidgets('누르는 줄이 아니라 화살표가 없고 정보 아이콘이다', (tester) async {
    await _openSettings(tester, info: _released);

    final AppListRow widget = _rowWidget(tester);
    expect(widget.onTap, isNull);
    expect(widget.trailing, isNull);
    expect(
      find.descendant(of: _row(), matching: find.byIcon(AppIcons.chevronRight)),
      findsNothing,
    );
    expect(
      find.descendant(of: _row(), matching: find.byIcon(AppIcons.info)),
      findsOneWidget,
    );
  });

  testWidgets('메뉴 맨 끝, 로그아웃 아래에 선다', (tester) async {
    await _openSettings(tester, info: _released);

    final double support = tester
        .getCenter(find.byKey(const ValueKey<String>('my-support-entry')))
        .dy;
    final double logout = tester
        .getCenter(find.byKey(const ValueKey<String>('my-logout-button')))
        .dy;
    final double info = tester.getCenter(_row()).dy;
    expect(logout, greaterThan(support));
    expect(info, greaterThan(logout));
  });
}
