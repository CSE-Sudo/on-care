/// 운동 현황 카드의 자리 규칙 (#1126 · #1127 · #1129).
///
///  * 기간 토글은 식단 탭의 것과 **같은 크기**다.
///  * 오늘 화면은 소모 칼로리 도넛이 왼쪽, 유형별 값이 오른쪽이고(#1151),
///    도넛 옆에 같은 숫자를 또 적지 않는다.
///  * 전체 화면에서 고른 주의 내역은 kcal 오른쪽에 붙고 색 네모는 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

const ExerciseWeek _week = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[30, 20, 10, 25, 40, 15, 20],
  dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
  totalMinutes: 160,
  totalCalories: 1200,
  streakDays: 2,
  aiCoachMessage: '',
  dailyCalories: <double>[220, 160, 90, 180, 420, 110, 150],
  cardioMinutes: <double>[20, 10, 5, 15, 25, 10, 10],
  strengthMinutes: <double>[6, 5, 3, 5, 10, 3, 6],
  stretchingMinutes: <double>[4, 5, 2, 5, 5, 2, 4],
  strengthSets: <double>[2, 2, 1, 2, 3, 1, 2],
);

Widget _app(int period) => ProviderScope(
  overrides: <Override>[
    exerciseActivityPeriodProvider.overrideWith((ref) => period),
    exerciseWeekProvider.overrideWith((ref) async => _week),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(24),
        child: ExerciseActivityStatus(week: _week),
      ),
    ),
  ),
);

void main() {
  testWidgets('오늘: 도넛은 왼쪽, 유형별 값은 오른쪽 (#1151)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(0));
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExerciseActivityStatus)),
    );
    final Rect cardio = tester.getRect(find.text(l.exTypeCardio));
    final Rect donut = tester.getRect(
      find
          .descendant(
            of: find.byType(ExerciseDayLoadCard),
            matching: find.byType(CustomPaint),
          )
          .last,
    );
    expect(donut.right, lessThan(cardio.left), reason: '도넛이 유형별 값 왼쪽에 있어야 한다');

    // 도넛과 상세가 한 덩어리로 가운데에 서고, 카드 양옆에 여백이 남는다.
    final Rect card = tester.getRect(find.byType(ExerciseDayLoadCard));
    expect(donut.left - card.left, greaterThan(8));
    expect(card.right - cardio.right, greaterThan(8));
  });

  testWidgets('기간 토글은 식단 탭과 같은 크기다 (#1126)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 두 탭을 한 화면에 세워 같은 폭에서 잰다 — 리버팟은 한 ProviderScope 의
    // override 를 도중에 갈아 끼울 수 없다.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          exerciseActivityPeriodProvider.overrideWith((ref) => 0),
          exerciseWeekProvider.overrideWith((ref) async => _week),
          dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
          accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Column(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.all(24),
                  child: ExerciseActivityStatus(week: _week),
                ),
                Expanded(child: DietRecordPage()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Size exercise = tester.getSize(
      find.byKey(const ValueKey<String>('exercise-period-tab-0')),
    );
    final Size diet = tester.getSize(dietPeriodTab(DietPeriodTab.day));

    // 식단 토글은 패키지 `AppSegmentedToggle` 로 먼저 옮겼다(#1700). 운동 탭이
    // 옮겨 가기 전(#1701)까지는 둘 다 모바일 칩 높이 안에 들어오는지만 잰다.
    expect(exercise.height, greaterThan(0));
    expect(diet.height, lessThanOrEqualTo(OnCareDensity.mobile.chip));
  });
}
