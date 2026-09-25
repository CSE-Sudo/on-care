import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_exercise_status_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
import 'package:oncare_trainer/shared/widgets/activity_charts.dart';
import 'package:oncare_trainer/shared/widgets/period_range_label.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너 웹 회원 운동 현황을 회원 앱 운동 탭 기준으로 맞춘다 (#2157).
///
/// 회원 앱은 목표를 MY 프로필에서 읽고(#1139), `기타` 만 한 날을 유산소로 세지
/// 않으며, `전체` 를 월요일부터 35주로 그리고 머리줄에 유형별 주 평균을 적는다
/// (#2061). 트레이너 화면이 이 중 하나라도 다르면 같은 회원의 같은 주를 두
/// 화면이 다른 숫자로 말한다.

/// 목표를 모두 기본값과 다르게 둔 회원 프로필.
const MemberHealthProfile _customProfile = MemberHealthProfile(
  memberId: 'c1',
  memberName: '김민수',
  dailyBurnKcal: 400,
  weeklyCardioMinutes: 200,
  weeklyStrengthSets: 30,
  weeklyFlexibilityMinutes: 90,
);

/// 목표 칸을 하나도 채우지 않은 회원 프로필.
const MemberHealthProfile _emptyProfile = MemberHealthProfile(
  memberId: 'c1',
  memberName: '김민수',
);

/// 매주 월요일에만 같은 운동을 한 기간 — 어느 구간을 보든 주 평균이 같다.
/// 유산소 60분 · 근력 30분(10세트) · 스트레칭 20분 · 기타 15분.
ClientExercisePeriod _mondayOnly(ClientPeriodKey key) {
  final ClientDateRange range = clientRangeFor(
    key.period,
    key.day,
    exercise: true,
  );
  return ClientExercisePeriod(
    range: range,
    days: <ClientExerciseDay>[
      for (final DateTime d in clientRangeDates(range))
        d.weekday == DateTime.monday
            ? ClientExerciseDay(
                date: d,
                minutes: 125,
                calories: 600,
                cardioMinutes: 60,
                strengthMinutes: 30,
                stretchingMinutes: 20,
                otherMinutes: 15,
                strengthSets: 10,
              )
            : ClientExerciseDay(date: d),
    ],
  );
}

/// 날마다 `기타` 30분만 한 기간. 유형 분해 셋은 0 이다.
ClientExercisePeriod _otherOnly(ClientPeriodKey key) {
  final ClientDateRange range = clientRangeFor(
    key.period,
    key.day,
    exercise: true,
  );
  return ClientExercisePeriod(
    range: range,
    days: <ClientExerciseDay>[
      for (final DateTime d in clientRangeDates(range))
        ClientExerciseDay(
          date: d,
          minutes: 30,
          calories: 150,
          otherMinutes: 30,
          otherCalories: 150,
        ),
    ],
  );
}

Widget _app(ClientPeriod period, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ClientExerciseStatusCard(clientId: 'c1', period: period),
        ),
      ),
    ),
  ),
);

List<Override> _overrides({
  ClientExercisePeriod Function(ClientPeriodKey key) data = _mondayOnly,
  MemberHealthProfile? profile = _customProfile,
  bool profileFails = false,
}) => <Override>[
  clientExercisePeriodProvider.overrideWith((ref, key) async => data(key)),
  memberHealthProfileProvider.overrideWith((ref, clientId) async {
    if (profileFails) throw StateError('profile down');
    return profile!;
  }),
];

Future<void> _pump(
  WidgetTester tester,
  ClientPeriod period,
  List<Override> overrides,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(period, overrides));
  await tester.pumpAndSettle();
}

void main() {
  group('목표는 회원 프로필에서 읽는다', () {
    testWidgets('오늘 도넛은 프로필의 하루 소모 목표를 채운다', (tester) async {
      // 오늘은 요일마다 기록이 있어야 도넛이 선다 — 날마다 기록한 기간을 쓴다.
      await _pump(tester, ClientPeriod.today, _overrides(data: _otherOnly));
      expect(tester.widget<BurnDonut>(find.byType(BurnDonut)).goal, 400);
    });

    testWidgets('이번 주 링은 프로필의 유형별 주간 목표를 쓴다', (tester) async {
      await _pump(tester, ClientPeriod.week, _overrides());
      final BurnGoalRings rings = tester.widget<BurnGoalRings>(
        find.byType(BurnGoalRings),
      );
      expect(rings.goals.weeklyBurnKcal, 2800);
      final List<String?> goals = tester
          .widgetList<ActivityValueRow>(find.byType(ActivityValueRow))
          .map((ActivityValueRow r) => r.goal)
          .take(3)
          .toList();
      expect(goals, <String>['/200분', '/30세트', '/90분']);
      // 머리줄의 주간 소모 목표도 프로필 × 7 이다.
      expect(find.textContaining('/2,800'), findsOneWidget);
    });

    testWidgets('전체 목표선은 주간 소모 목표이고 단위를 붙이지 않는다', (tester) async {
      await _pump(tester, ClientPeriod.month, _overrides());
      expect(
        tester.widget<BurnBarChart>(find.byType(BurnBarChart)).goalKcal,
        2800,
      );
      // 회원 앱 `전체` 와 같은 `목표\n2800` 이다 — `kcal` 이 붙지 않는다.
      expect(
        tester
            .widget<PeriodScrollChart>(find.byType(PeriodScrollChart))
            .goalLabel,
        '목표\n2800',
      );
    });

    testWidgets('비어 있는 칸은 회원 앱과 같은 기본값이다', (tester) async {
      await _pump(
        tester,
        ClientPeriod.week,
        _overrides(profile: _emptyProfile),
      );
      final BurnGoalRings rings = tester.widget<BurnGoalRings>(
        find.byType(BurnGoalRings),
      );
      expect(rings.goals.dailyBurnKcal, 300);
      expect(rings.goals.weeklyGoalOf(ExerciseKind.cardio), 150);
      expect(rings.goals.weeklyGoalOf(ExerciseKind.strength), 21);
      expect(rings.goals.weeklyGoalOf(ExerciseKind.stretching), 60);
    });

    testWidgets('프로필을 못 읽어도 기본값으로 그래프를 그린다', (tester) async {
      await _pump(
        tester,
        ClientPeriod.today,
        _overrides(data: _otherOnly, profileFails: true),
      );
      expect(tester.takeException(), isNull);
      expect(tester.widget<BurnDonut>(find.byType(BurnDonut)).goal, 300);
    });

    test('프로필 칸을 하나씩 기본값으로 메운다', () {
      const MemberHealthProfile partial = MemberHealthProfile(
        memberId: 'c1',
        memberName: '김민수',
        weeklyStrengthSets: 12,
      );
      final ExerciseBurnGoals g = ExerciseBurnGoals.fromProfile(partial);
      expect(g.dailyBurnKcal, kDailyBurnKcal);
      expect(g.weeklyBurnKcal, kWeeklyBurnKcal);
      expect(g.weeklyCardioMinutes, kWeeklyCardioMinutes);
      expect(g.weeklyStrengthSets, 12);
      expect(g.weeklyStretchingMinutes, kWeeklyStretchingMinutes);
      expect(
        identical(
          ExerciseBurnGoals.fromProfile(null),
          kDefaultExerciseBurnGoals,
        ),
        isTrue,
      );
    });
  });

  group('기타만 기록한 날은 두 번 세지 않는다', () {
    test('기타도 유형 분해의 한 칸이다', () {
      final ClientExerciseDay day = ClientExerciseDay(
        date: DateTime(2026, 9, 21),
        minutes: 30,
        otherMinutes: 30,
      );
      expect(day.hasTypeSplit, isTrue);
      // 분해가 아예 없는 옛 기록은 여전히 유산소로 본다.
      expect(
        ClientExerciseDay(
          date: DateTime(2026, 9, 21),
          minutes: 30,
        ).hasTypeSplit,
        isFalse,
      );
    });

    testWidgets('오늘 — 유산소 0분 + 기타 30분', (tester) async {
      await _pump(tester, ClientPeriod.today, _overrides(data: _otherOnly));
      final ActivitySplit split = tester
          .widget<BurnDonut>(find.byType(BurnDonut))
          .split;
      expect(split.cardioMinutes, 0);
      expect(split.otherMinutes, 30);
    });

    testWidgets('이번 주 — 유산소 링이 기타 분으로 차지 않는다', (tester) async {
      await _pump(tester, ClientPeriod.week, _overrides(data: _otherOnly));
      final ActivitySplit split = tester
          .widget<BurnGoalRings>(find.byType(BurnGoalRings))
          .split;
      expect(split.cardioMinutes, 0);
      expect(split.otherMinutes, 30 * 7);
    });

    testWidgets('전체 — 막대 툴팁에 유산소가 없다', (tester) async {
      await _pump(tester, ClientPeriod.month, _overrides(data: _otherOnly));
      final String tip = tester
          .widget<Tooltip>(find.byKey(const Key('client-exercise-bar-0')))
          .richMessage!
          .toPlainText();
      expect(tip, contains('기타'));
      expect(tip, isNot(contains('유산소')));
    });
  });

  group('전체 범위는 월요일부터 35주다', () {
    test('어느 요일에 열어도 첫날이 월요일이고 정확히 35칸이다', () {
      // 한 주의 일곱 요일을 모두 돈다 — 요일마다 깨지는 테스트가 되지 않게.
      for (int i = 0; i < 7; i++) {
        final DateTime today = DateTime(2026, 9, 21 + i);
        final ClientDateRange range = clientRangeFor(
          ClientPeriod.month,
          today,
          exercise: true,
        );
        expect(range.from.weekday, DateTime.monday, reason: '$today');
        expect(range.to, today, reason: '$today');
        expect(clientRangeWeekStarts(range).length, 35, reason: '$today');
        // 이번 주 월요일에서 34주를 거슬러 간 날이다 — 회원 앱과 같다.
        expect(range.from, DateTime(2026, 9, 21 - 34 * 7), reason: '$today');
      }
    });

    test('식단 전체는 그대로 84일이다', () {
      final DateTime today = DateTime(2026, 9, 23);
      final ClientDateRange range = clientRangeFor(ClientPeriod.month, today);
      expect(clientRangeDates(range).length, kClientAllPeriodDays);
      expect(range.to, today);
    });

    testWidgets('막대는 35개다', (tester) async {
      await _pump(tester, ClientPeriod.month, _overrides());
      final int bars = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .where(
            (Tooltip t) =>
                (t.key as ValueKey<String>?)?.value.startsWith(
                  'client-exercise-bar-',
                ) ??
                false,
          )
          .length;
      expect(bars, 35);
    });
  });

  group('머리줄·제목·기간은 회원 앱 규칙이다', () {
    testWidgets('전체 머리줄은 기간 아래에 유형별 주 평균을 적는다', (tester) async {
      await _pump(tester, ClientPeriod.month, _overrides());
      final Finder average = find.byKey(
        const ValueKey<String>('client-exercise-all-average'),
      );
      expect(average, findsOneWidget);
      expect(
        find.descendant(
          of: average,
          matching: find.byKey(
            const ValueKey<String>('client-exercise-all-range'),
          ),
        ),
        findsOneWidget,
      );
      String lines() => tester
          .widgetList<RichText>(
            find.descendant(of: average, matching: find.byType(RichText)),
          )
          .map((RichText t) => t.text.toPlainText())
          .join('\n');
      // 매주 같은 기록이라 어느 구간을 보든 주 평균이 같다.
      expect(lines(), contains('유산소 60분'));
      expect(lines(), contains('근력 10세트'));
      expect(lines(), contains('스트레칭 20분'));
      expect(lines(), contains('기타 15분'));
      // 이름은 위, 숫자는 아래로 쌓는다.
      expect(
        tester
            .widget<ActivityHeadlineLine>(find.byType(ActivityHeadlineLine))
            .stacked,
        isTrue,
      );
    });

    testWidgets('주를 고르면 제목이 `…주차 소모` 이고 회색 바탕이 깔린다', (tester) async {
      await _pump(tester, ClientPeriod.month, _overrides());
      await tester.tap(find.byKey(const Key('client-exercise-bar-34')));
      await tester.pumpAndSettle();

      final ActivityHeadlineLine head = tester.widget<ActivityHeadlineLine>(
        find.byType(ActivityHeadlineLine),
      );
      expect(head.caption, endsWith('주차 소모'));
      expect(
        tester
            .widget<PeriodChartHeadline>(find.byType(PeriodChartHeadline))
            .selected,
        isTrue,
      );
      // 평균 칸은 고른 주의 내역으로 바뀐다.
      expect(
        find.byKey(const ValueKey<String>('client-exercise-all-average')),
        findsNothing,
      );
    });

    testWidgets('이번 주 머리줄에 그 주의 월~일을 적는다', (tester) async {
      await _pump(tester, ClientPeriod.week, _overrides());
      final ClientDateRange week = clientRangeFor(
        ClientPeriod.week,
        todayKst(),
      );
      final PeriodRangeLabel label = tester.widget<PeriodRangeLabel>(
        find.byKey(const Key('client-exercise-week-range')),
      );
      expect(label.text, periodRangeText('ko', week.from, week.to));
    });
  });

  test('목표의 정확한 배수에서만 끝 표시를 생략한다 (회원 앱 #1462)', () {
    expect(isAtRingMultiple(0), isFalse);
    expect(isAtRingMultiple(0.5), isFalse);
    expect(isAtRingMultiple(1), isTrue);
    expect(isAtRingMultiple(2.0000000001), isTrue);
    expect(isAtRingMultiple(1.37), isFalse);
    expect(isAtRingMultiple(double.nan), isFalse);
  });
}
