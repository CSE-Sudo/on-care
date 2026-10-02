/// 식단 탭을 연 채 자정을 넘기면 새 오늘로 옮긴다. (#2882)
///
/// 탭은 셸 안에 살아 있어 고른 날짜가 처음 연 날로 남았다. 자정 뒤 앱으로
/// 돌아오면 어제 식단과 `오늘로` 버튼이 보이고, 아침에 저장한 끼니가 보이지
/// 않았다. 회원이 일부러 지난 날짜를 보던 중이면 그대로 둔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/record_span.dart';

/// 2026-08-19(수) 23:50 KST 에 연다.
final DateTime _beforeMidnight = DateTime(2026, 8, 19, 23, 50);

/// 자정을 넘긴 2026-08-20(목) 00:10 KST.
final DateTime _afterMidnight = DateTime(2026, 8, 20, 0, 10);

Finder _card(String id) => find.byKey(ValueKey<String>('mealCard-$id'));

/// 탭을 띄우고, 시계를 바꿀 수 있게 돌려준다.
Future<void Function(DateTime)> _pump(WidgetTester tester) async {
  DateTime now = _beforeMidnight;
  debugNowKstOverride = () => now;
  addTearDown(() => debugNowKstOverride = null);
  await tester.binding.setSurfaceSize(const Size(900, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
        testRecordSpanOverride(),
        sessionFeatureResetOverride(),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DietRecordPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (DateTime next) {
    now = next;
    // 셸이 앱 복귀·탭 전환 때 하는 일 — 오늘 식단을 다시 읽는다.
    ProviderScope.containerOf(
      tester.element(find.byType(DietRecordPage)),
    ).invalidate(dietTodayProvider);
  };
}

/// 다시 읽기를 끝까지 기다린다. 새로 읽는 동안에도 앞 목록을 그대로 그려
/// 프레임이 서지 않으므로, `pumpAndSettle` 만으로는 대역의 응답 지연 타이머가
/// 남은 채 테스트가 끝난다.
Future<void> _settleRefetch(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

AppWeekStrip _strip(WidgetTester tester) =>
    tester.widget<AppWeekStrip>(find.byType(AppWeekStrip));

void main() {
  testWidgets('오늘을 보던 중 자정을 넘기면 새 오늘의 식단이 보인다', (WidgetTester tester) async {
    final void Function(DateTime) advance = await _pump(tester);
    expect(_card('mock-breakfast'), findsOneWidget);

    advance(_afterMidnight);
    await _settleRefetch(tester);

    // 어제(19일) 목록이 아니라 새 오늘의 목록이다.
    expect(_card('mock-breakfast'), findsOneWidget);
    expect(_card('mock-yesterday-breakfast'), findsNothing);
    expect(_strip(tester).selected, DateTime(2026, 8, 20));
    expect(_strip(tester).onToday, isNull);
  });

  testWidgets('지난 날짜를 골라 보던 중이면 자정 뒤에도 그 날짜에 머문다', (WidgetTester tester) async {
    final void Function(DateTime) advance = await _pump(tester);
    // 18일(화)을 고른다 — 19일 기준 어제다.
    await tester.tap(find.text('18').first);
    await tester.pumpAndSettle();
    expect(_card('mock-yesterday-breakfast'), findsOneWidget);

    advance(_afterMidnight);
    await _settleRefetch(tester);

    // 회원이 고른 18일에 그대로 있고, `오늘` 알약으로 돌아갈 수 있다.
    expect(_strip(tester).selected, DateTime(2026, 8, 18));
    expect(_strip(tester).onToday, isNotNull);
  });
}
