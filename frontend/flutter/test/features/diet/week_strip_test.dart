/// 주간 달력은 월요일에서 시작해 일요일로 끝난다 (#1059).
///
/// 오늘을 가운데 두면 한 줄에 지난주 끝과 이번 주 앞이 섞여, `이번 주` 그래프가
/// 세는 주와 달력이 보여 주는 주가 서로 어긋났다.
///
/// 줄 위의 라벨도 바뀐다. `n월 n주차` 의 주차 번호는 세는 방법에 따라 달라져
/// 어느 날을 보고 있는지 오히려 흐렸다 — 고른 날을 그대로 적는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

void main() {
  // 월요일에는 다른 평일이 모두 미래라 선택할 수 없다.
  // 과거 기록을 고르는 시나리오는 주 중간으로 고정한다.
  setUp(() => useFixedKstDate());

  Future<void> pumpDiet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
          accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
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
  }

  /// 스트립에 그려진 날짜 칸의 일(日) 숫자들.
  List<int> stripDays(WidgetTester tester) {
    final DateTime today = DateUtils.dateOnly(nowKst());
    final DateTime monday = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    return <int>[for (int i = 0; i < 7; i++) monday.add(Duration(days: i)).day];
  }

  testWidgets('스트립은 월요일에서 시작해 일요일로 끝난다', (WidgetTester tester) async {
    await pumpDiet(tester);

    for (final int day in stripDays(tester)) {
      expect(find.text('$day'), findsWidgets, reason: '$day 일');
    }

    // 이번 주 월요일의 앞날(지난주 일요일)은 줄에 없다.
    final DateTime today = DateUtils.dateOnly(nowKst());
    final DateTime monday = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final DateTime beforeMonday = monday.subtract(const Duration(days: 1));
    if (beforeMonday.month != monday.month || beforeMonday.day > 7) {
      expect(find.text('${beforeMonday.day}'), findsNothing);
    }
  });

  testWidgets('주차 번호 대신 고른 날을 적는다', (WidgetTester tester) async {
    await pumpDiet(tester);

    // 처음에는 오늘이 골라져 있다.
    expect(find.textContaining('주차'), findsNothing);
    expect(find.text('오늘'), findsWidgets);

    // 다른 날을 고르면 그 날짜가 적힌다.
    final DateTime today = DateUtils.dateOnly(nowKst());
    final DateTime monday = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final DateTime other = monday == today
        ? monday.add(const Duration(days: 1))
        : monday;
    await tester.tap(find.text('${other.day}').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('${other.month}월 ${other.day}일'), findsWidgets);
  });
}
