/// `운동 현황` 의 세 기간이 모두 제 기간을 카드 안에서 말한다 (#2007).
///
/// `전체` 는 이미 머리줄 오른쪽에 `4. 20. ~ 9. 20.` 으로 보이는 구간을 적고
/// 있었는데 `이번 주` 만 비어 있었다. 위쪽 날짜 스트립은 **고른 하루**를
/// 가리키는 것이라, 카드가 집계한 한 주를 대신 말해 주지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/period_range_label.dart';

import '../../helpers/fixed_clock.dart';

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
  Future<void> pump(WidgetTester tester, int period) async {
    // 기간의 양끝이 오늘에 매여 있다 — 고정하지 않으면 기대값이 달력을 탄다.
    useFixedKstDate();
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(period));
    await tester.pumpAndSettle();
  }

  testWidgets('이번 주 카드가 그 주의 월~일을 카드 안에 적는다', (WidgetTester tester) async {
    await pump(tester, 1);

    final Finder range = find.byKey(const Key('exercise-week-range'));
    expect(range, findsOneWidget, reason: '이번 주 카드에 날짜 기간이 없다');

    // 2026-08-20(목)을 오늘로 고정했으므로 그 주는 8/17(월) ~ 8/23(일)이다.
    final DateFormat fmt = DateFormat.Md('ko');
    expect(
      tester
          .widget<Text>(find.descendant(of: range, matching: find.byType(Text)))
          .data,
      '${fmt.format(DateTime(2026, 8, 17))} ~ ${fmt.format(DateTime(2026, 8, 23))}',
    );

    // 카드 **안**이다 — 바깥에 뜬 줄이 아니다.
    final Rect card = tester.getRect(
      find.byKey(const Key('exerciseActivityCard')),
    );
    final Rect label = tester.getRect(range);
    expect(card.contains(label.topLeft), isTrue);
    expect(card.contains(label.bottomRight), isTrue);
    // 오른쪽 상단 — 카드 가운데선보다 오른쪽, 위쪽 절반 안.
    expect(label.center.dx, greaterThan(card.center.dx));
    expect(label.center.dy, lessThan(card.center.dy));
  });

  testWidgets('이번 주가 전체와 같은 함수로 기간을 적는다', (WidgetTester tester) async {
    // 형식이 갈리면 같은 토글 안의 두 카드가 서로 다른 말투로 말한다. 두
    // 카드가 `periodRangeText` 하나를 함께 쓰는 것이 그 보장이라, 카드가 적은
    // 글이 그 함수의 결과와 **같은지**를 본다. `전체` 쪽은 아래 단위 테스트가
    // 같은 함수를 직접 확인한다.
    await pump(tester, 1);

    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('exercise-week-range')),
              matching: find.byType(Text),
            ),
          )
          .data,
      periodRangeText('ko', DateTime(2026, 8, 17), DateTime(2026, 8, 23)),
    );
  });

  test('periodRangeText 는 월·일만 적고 가운데를 ` ~ ` 로 잇는다', () {
    // `전체` 머리줄도 이 함수로 적는다 — 한쪽만 고치면 형식이 갈린다.
    expect(
      periodRangeText('ko', DateTime(2026, 4, 20), DateTime(2026, 9, 20)),
      '${DateFormat.Md('ko').format(DateTime(2026, 4, 20))}'
      ' ~ '
      '${DateFormat.Md('ko').format(DateTime(2026, 9, 20))}',
    );
    // 연도는 적지 않는다 — 한 줄에 들어가야 한다.
    expect(
      periodRangeText('ko', DateTime(2026, 4, 20), DateTime(2026, 9, 20)),
      isNot(contains('2026')),
    );
  });

  test('1년을 넘는 기간은 연도까지 적는다 (#2079)', () {
    // `전체` 가 모든 기록을 그리게 되면서 1년을 넘는 기간이 생겼다. 월·일만
    // 적으면 `8. 20.` 이 어느 해인지 갈리지 않는다.
    expect(
      periodRangeText('ko', DateTime(2025, 11, 3), DateTime(2026, 12, 15)),
      contains('2025'),
    );
    expect(
      periodRangeText('ko', DateTime(2025, 11, 3), DateTime(2026, 12, 15)),
      contains('2026'),
    );
    // 해가 바뀌는 구간도 월·일만으로 읽힌다.
    expect(
      periodRangeText('ko', DateTime(2026, 12, 16), DateTime(2027, 1, 5)),
      '${DateFormat.Md('ko').format(DateTime(2026, 12, 16))}'
      ' ~ '
      '${DateFormat.Md('ko').format(DateTime(2027, 1, 5))}',
    );
  });

  testWidgets('기간 한 줄이 들어와도 세 카드 높이가 그대로다', (WidgetTester tester) async {
    final List<double> heights = <double>[];
    for (final int period in <int>[0, 1, 2]) {
      await pump(tester, period);
      heights.add(
        tester.getSize(find.byKey(const Key('exerciseActivityCard'))).height,
      );
    }
    expect(heights[1], heights[0], reason: '이번 주 카드 높이가 오늘과 다르다');
    expect(heights[2], heights[0], reason: '전체 카드 높이가 오늘과 다르다');
    expect(tester.takeException(), isNull);
  });
}
