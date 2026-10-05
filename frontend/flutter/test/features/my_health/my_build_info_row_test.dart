/// MY 탭 설정 카드의 `버전 정보` 줄(#3226).
///
/// 지금 떠 있는 빌드가 어느 배포인지 화면에서 바로 읽혀야 한다 — 버전(빌드 번호)과 KST
/// 배포 일시. 빌드 번호가 없는 빌드는 개발 빌드로 보인다. 누르는 줄이 아니므로 화살표가
/// 없고, 설정 목록 끝(로그아웃 위)에 선다. 기존 설정 줄과 로그아웃 버튼은 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/release/build_info.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/build_info.dart';
import 'package:oncare_ui/oncare_ui.dart';

final BuildInfo _released = BuildInfo.fromDefines(
  version: '0.4.0',
  buildNumber: '7032',
  releaseDate: '2026-10-05T05:30:00Z',
);

void main() {
  Future<void> pumpMyTab(
    WidgetTester tester, {
    BuildInfo? info,
    Locale locale = const Locale('ko'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
          myHealthRepositoryProvider.overrideWithValue(
            const MockMyHealthRepository(),
          ),
          if (info != null) buildInfoProvider.overrideWithValue(info),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MyHealthPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row() => find.byKey(const ValueKey<String>('my-build-info'));

  AppListRow rowWidget(WidgetTester tester) => tester.widget<AppListRow>(row());

  testWidgets('배포 빌드는 버전(빌드 번호)과 KST 배포 일시를 보인다', (WidgetTester tester) async {
    await pumpMyTab(tester, info: _released);

    expect(row(), findsOneWidget);
    expect(rowWidget(tester).title, '버전 정보');
    expect(
      rowWidget(tester).subtitle,
      '0.4.0 (7032) · 2026년 10월 5일 14:30 KST 배포',
    );
    expect(
      find.descendant(
        of: row(),
        matching: find.text('0.4.0 (7032) · 2026년 10월 5일 14:30 KST 배포'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('영어 화면은 영어 문구와 날짜 형식이다', (WidgetTester tester) async {
    await pumpMyTab(tester, info: _released, locale: const Locale('en'));

    expect(rowWidget(tester).title, 'Version');
    expect(
      rowWidget(tester).subtitle,
      '0.4.0 (7032) · Deployed Oct 5, 2026 14:30 KST',
    );
  });

  testWidgets('빌드 번호가 없으면 pubspec 버전과 개발 빌드', (WidgetTester tester) async {
    await pumpMyTab(tester, info: BuildInfo.fromDefines(version: '0.4.0'));

    expect(rowWidget(tester).subtitle, '0.4.0 · 개발 빌드');
  });

  testWidgets('define 이 없는 테스트 빌드 그대로 띄워도 깨지지 않고 개발 빌드다', (
    WidgetTester tester,
  ) async {
    // provider 를 덮지 않는다 — 실제 define(빈 값)과 버전 읽기 실패 경로 그대로다.
    await pumpMyTab(tester);

    expect(tester.takeException(), isNull);
    expect(row(), findsOneWidget);
    expect(rowWidget(tester).subtitle, endsWith('개발 빌드'));
  });

  testWidgets('누르는 줄이 아니라 화살표가 없고 정보 아이콘이다', (WidgetTester tester) async {
    await pumpMyTab(tester, info: _released);

    final AppListRow widget = rowWidget(tester);
    expect(widget.onTap, isNull);
    expect(widget.trailing, isNull);
    expect(
      find.descendant(of: row(), matching: find.byIcon(AppIcons.chevronRight)),
      findsNothing,
    );
    expect(
      find.descendant(of: row(), matching: find.byIcon(AppIcons.info)),
      findsOneWidget,
    );
  });

  testWidgets('설정 목록 끝, 로그아웃 바로 위에 선다', (WidgetTester tester) async {
    await pumpMyTab(tester, info: _released);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(MyHealthPage)),
    );
    final double support = tester
        .getCenter(find.text(l.mySupportTitle).first)
        .dy;
    final double info = tester.getCenter(row()).dy;
    final double logout = tester
        .getCenter(find.byKey(const ValueKey<String>('my-logout-button')))
        .dy;
    expect(info, greaterThan(support));
    expect(logout, greaterThan(info));
  });
}
