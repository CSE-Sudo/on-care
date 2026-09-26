/// ④ 운동 추세 — 유형별 주간 목표 달성률 도넛 셋과 지난 여덟 주. (#2232)
///
/// 유산소는 분, 근력은 세트, 스트레칭은 분이라 **서로 더할 수도 높이를 견줄
/// 수도 없다.** 셋을 각자의 목표에 대한 비율로 바꿔야 비로소 한 화면에 설 수
/// 있고, 그래서 이 카드에서 틀리면 안 되는 것은 그림이 아니라 **무엇을 무엇으로
/// 나누는가**다. 도넛 하나로는 `70%` 가 좋아진 70 인지 나빠진 70 인지 알 수
/// 없어, 여덟 주에서 읽은 흐름 한 줄이 옆에 선다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_trend_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_exercise_trend.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

final DateTime _week = DateTime(2026, 9, 14);

WeeklyReport _report({List<ReportDay> days = const <ReportDay>[]}) =>
    WeeklyReport(
      client: makeClient(name: '김민수'),
      weekStart: _week,
      sessionsBooked: 2,
      sessionsDone: 2,
      completionAvg: 86,
      sodiumOverDays: 0,
      sodiumAvg: 1700,
      isCurrentWeek: false,
      days: days,
    );

/// 한 주치 실적. 값은 주 합계다 — 도넛이 읽는 것은 날짜별 분포가 아니다.
ReportTrendWeek _w({
  int back = 0,
  int cardio = 0,
  int sets = 0,
  int stretching = 0,
  int cardioKcal = 0,
  int strengthKcal = 0,
  int stretchingKcal = 0,
}) => ReportTrendWeek(
  weekStart: DateTime(_week.year, _week.month, _week.day - back * 7),
  cardioMinutes: cardio,
  strengthSets: sets,
  stretchingMinutes: stretching,
  cardioCalories: cardioKcal,
  strengthCalories: strengthKcal,
  stretchingCalories: stretchingKcal,
);

ReportTrend _trend({
  List<ReportTrendWeek>? weeks,
  ExerciseBurnGoals goals = const ExerciseBurnGoals(),
}) => ReportTrend(weeks: weeks ?? <ReportTrendWeek>[_w()], goals: goals);

Future<void> _pump(
  WidgetTester tester, {
  ReportTrend? trend,
  WeeklyReport? report,
  bool empty = false,
  String locale = 'ko',
  Size size = const Size(1400, 1000),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        reportTrendProvider.overrideWith((ref, key) async {
          // 못 읽은 주 — 값이 없는 것이지 0 인 것이 아니다.
          if (empty) {
            return const ReportTrend(
              weeks: <ReportTrendWeek>[],
              goals: ExerciseBurnGoals(),
            );
          }
          return trend ?? _trend();
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s16),
            child: ReportExerciseTrend(report: report ?? _report()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 그 유형 칸 안의 글월 목록.
List<String> _cardTexts(WidgetTester tester, ExerciseKind kind) => <String>[
  for (final Element e
      in find
          .descendant(
            of: find.byKey(ValueKey<String>('report-trend-${kind.name}')),
            matching: find.byType(Text),
          )
          .evaluate())
    if ((e.widget as Text).data != null) (e.widget as Text).data!,
];

void main() {
  group('무엇을 무엇으로 나누는가', () {
    test('유형마다 자기 단위의 실적을 자기 목표로 나눈다', () {
      final ReportTrend trend = _trend(
        weeks: <ReportTrendWeek>[_w(cardio: 75, sets: 21, stretching: 30)],
      );
      final ReportTrendWeek week = trend.current!;

      expect(trend.ratioOf(ExerciseKind.cardio, week), closeTo(0.5, 1e-9));
      // 근력은 분이 아니라 세트다 — 분으로 재면 쉬는 시간이 실적이 된다.
      expect(trend.ratioOf(ExerciseKind.strength, week), closeTo(1, 1e-9));
      expect(
        trend.ratioOf(ExerciseKind.stretching, week),
        closeTo(30 / kWeeklyStretchingMinutes, 1e-9),
      );
    });

    test('회원이 정한 목표를 쓴다 — 코드 상수를 쓰면 회원 폰과 다른 그림이 된다', () {
      final ReportTrend trend = _trend(
        weeks: <ReportTrendWeek>[_w(cardio: 100)],
        goals: const ExerciseBurnGoals(weeklyCardioMinutes: 200),
      );

      expect(trend.ratioOf(ExerciseKind.cardio, trend.current!), 0.5);
    });

    test('목표가 0 이면 견줄 기준이 없어 비율이 없다', () {
      final ReportTrend trend = _trend(
        weeks: <ReportTrendWeek>[_w(cardio: 50)],
        goals: const ExerciseBurnGoals(weeklyCardioMinutes: 0),
      );

      expect(trend.ratioOf(ExerciseKind.cardio, trend.current!), isNull);
    });

    test('목표를 넘긴 주는 1 을 넘는 비율을 그대로 준다', () {
      final ReportTrend trend = _trend(
        weeks: <ReportTrendWeek>[_w(cardio: 300)],
      );

      expect(trend.ratioOf(ExerciseKind.cardio, trend.current!), 2);
    });

    test('달성률은 세 비율의 평균이고, 한 유형의 초과가 전체를 덮지 못한다', () {
      // 유산소만 두 배를 해도 나머지가 0 이면 잘된 주가 아니다.
      final ReportTrend trend = _trend(
        weeks: <ReportTrendWeek>[_w(cardio: 300)],
      );

      expect(trend.rateOf(trend.current!), closeTo(1 / 3, 1e-9));
    });
  });

  group('여덟 주가 말하는 것', () {
    test('내리 떨어진 주를 센다 — 한 주 내려간 것은 흐름이 아니다', () {
      final ReportTrend down = _trend(
        weeks: <ReportTrendWeek>[
          _w(back: 3, cardio: 150),
          _w(back: 2, cardio: 120),
          _w(back: 1, cardio: 90),
          _w(cardio: 60),
        ],
      );
      expect(down.fallingWeeks, 3);

      final ReportTrend blip = _trend(
        weeks: <ReportTrendWeek>[
          _w(back: 2, cardio: 90),
          _w(back: 1, cardio: 150),
          _w(cardio: 120),
        ],
      );
      expect(blip.fallingWeeks, 0);
    });

    test('유형의 흐름은 방향까지 말한다', () {
      final ReportTrend up = _trend(
        weeks: <ReportTrendWeek>[
          _w(back: 2, sets: 9),
          _w(back: 1, sets: 14),
          _w(sets: 21),
        ],
      );

      expect(up.runOf(ExerciseKind.strength), (weeks: 2, rising: true));
    });

    test('기록이 없는 주는 평균에서 빠진다 — 아직 오지 않은 주가 평균을 끌어내린다', () {
      final ReportTrend trend = _trend(
        weeks: <ReportTrendWeek>[
          _w(back: 1, cardio: 150, sets: 21, stretching: 60),
          _w(),
        ],
      );

      // 빈 주를 세면 평균이 절반이 된다.
      expect(trend.averageRate, closeTo(1, 1e-9));
    });

    test('지난 주가 0 이면 변화율을 말하지 않는다 — 없다가 생긴 것은 몇 %가 아니다', () {
      final ReportTrend trend = _trend(
        weeks: <ReportTrendWeek>[_w(back: 1), _w(cardio: 60)],
      );

      expect(trend.deltaOf(ExerciseKind.cardio), isNull);
    });
  });

  group('화면', () {
    testWidgets('칸 셋이 유산소 → 근력 → 스트레칭 순서로 선다', (tester) async {
      await _pump(tester);

      final List<double> xs = <double>[
        for (final ExerciseKind kind in ExerciseKind.values)
          tester
              .getCenter(
                find.byKey(ValueKey<String>('report-trend-${kind.name}')),
              )
              .dx,
      ];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
    });

    testWidgets('칸마다 이름·달성률·칼로리·자기 단위의 값·주간 목표를 적는다', (tester) async {
      await _pump(
        tester,
        trend: _trend(
          weeks: <ReportTrendWeek>[_w(cardio: 75, cardioKcal: 640)],
        ),
      );

      expect(
        _cardTexts(tester, ExerciseKind.cardio),
        containsAll(<String>[
          '유산소',
          '목표의',
          '50%',
          '640kcal',
          '75분',
          '주간 목표 150분',
        ]),
      );
    });

    testWidgets('근력은 세트로 적는다 — 유형마다 단위가 다르다', (tester) async {
      await _pump(
        tester,
        trend: _trend(weeks: <ReportTrendWeek>[_w(sets: 21)]),
      );

      expect(
        _cardTexts(tester, ExerciseKind.strength),
        containsAll(<String>['100%', '근력', '21세트']),
      );
    });

    testWidgets('목표가 없는 유형은 백분율 대신 목표 없음을 적는다', (tester) async {
      await _pump(
        tester,
        trend: _trend(
          weeks: <ReportTrendWeek>[_w(cardio: 60)],
          goals: const ExerciseBurnGoals(weeklyCardioMinutes: 0),
        ),
      );

      expect(_cardTexts(tester, ExerciseKind.cardio), contains('목표 없음'));
    });

    testWidgets('견줄 지난 주가 없으면 빈 줄 대신 그렇다고 적는다', (tester) async {
      await _pump(
        tester,
        trend: _trend(weeks: <ReportTrendWeek>[_w(cardio: 75)]),
      );

      expect(_cardTexts(tester, ExerciseKind.cardio), contains('견줄 지난 주가 없어요'));
    });

    testWidgets('내리막은 몇 주째인지로 적는다 — 이번 주 수치가 말하지 못하는 것이다', (tester) async {
      await _pump(
        tester,
        trend: _trend(
          weeks: <ReportTrendWeek>[
            _w(back: 3, cardio: 150),
            _w(back: 2, cardio: 120),
            _w(back: 1, cardio: 90),
            _w(cardio: 60),
          ],
        ),
      );

      expect(_cardTexts(tester, ExerciseKind.cardio), contains('▼ 3주 연속 감소'));
    });

    testWidgets('합계 줄이 이번 주 달성률과 여덟 주 평균을 나란히 말한다', (tester) async {
      await _pump(
        tester,
        trend: _trend(
          weeks: <ReportTrendWeek>[
            _w(back: 1, cardio: 150, sets: 21, stretching: 60),
            _w(cardio: 75, sets: 21, stretching: 60),
          ],
        ),
      );

      expect(find.text('주간 달성률'), findsOneWidget);
      expect(find.text('8주 평균'), findsOneWidget);
      // 이번 주 (0.5+1+1)/3, 평균은 지난 주 100% 와의 가운데.
      expect(find.text('83%'), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
    });

    testWidgets('달성률이 이어 떨어지면 합계 줄이 붉게 짚는다', (tester) async {
      await _pump(
        tester,
        trend: _trend(
          weeks: <ReportTrendWeek>[
            _w(back: 3, cardio: 150),
            _w(back: 2, cardio: 120),
            _w(back: 1, cardio: 90),
            _w(cardio: 60),
          ],
        ),
      );

      expect(find.text('▼ 달성률 3주 연속 하락'), findsOneWidget);
    });

    testWidgets('그 주에 가장 자주 한 종목이 딱지로 선다', (tester) async {
      await _pump(
        tester,
        report: _report(
          days: const <ReportDay>[
            ReportDay(completion: 100, exercises: <String>['스쿼트', '런지']),
            ReportDay(completion: 100, exercises: <String>['스쿼트']),
          ],
        ),
      );

      expect(find.text('추적 종목 2개 — 자동 선별됨'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('report-tracked-스쿼트')),
        findsOneWidget,
      );
      expect(find.text('스쿼트 · 2회'), findsOneWidget);
    });

    test('종목은 많이 한 순서로 셋까지만 고른다', () {
      final List<({String name, int count})> top = trackedExercises(
        _report(
          days: const <ReportDay>[
            ReportDay(
              completion: 100,
              exercises: <String>['런지', '스쿼트', '플랭크', '사이클'],
            ),
            ReportDay(completion: 100, exercises: <String>['스쿼트', '플랭크']),
            ReportDay(completion: 100, exercises: <String>['스쿼트']),
          ],
        ),
      );

      expect(
        top.map((({String name, int count}) e) => e.name).toList(),
        <String>[
          '스쿼트',
          '플랭크',
          // 같은 횟수면 이름 순 — 순서가 실행마다 바뀌면 안 된다.
          '런지',
        ],
      );
      expect(top.first.count, 3);
    });

    testWidgets('못 읽은 주는 0 으로 그리지 않고 까닭을 말한다', (tester) async {
      await _pump(tester, empty: true);

      expect(
        find.byKey(const ValueKey<String>('report-trend-empty')),
        findsOneWidget,
      );
      expect(find.text('이 주의 운동 기록을 불러오지 못했어요'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('report-trend-cardio')),
        findsNothing,
      );
    });

    testWidgets('세 칸이 폭을 똑같이 나눠 갖는다', (tester) async {
      await _pump(tester);

      final List<double> widths = <double>[
        for (final ExerciseKind kind in ExerciseKind.values)
          tester
              .getSize(
                find.byKey(ValueKey<String>('report-trend-${kind.name}')),
              )
              .width,
      ];
      expect(widths[0], closeTo(widths[1], 0.5));
      expect(widths[1], closeTo(widths[2], 0.5));
    });

    testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
      await _pump(
        tester,
        locale: 'en',
        trend: _trend(
          weeks: <ReportTrendWeek>[_w(cardio: 75, cardioKcal: 640)],
        ),
      );

      expect(
        _cardTexts(tester, ExerciseKind.cardio),
        containsAll(<String>[
          'Cardio',
          'of goal',
          '50%',
          '640kcal',
          '75 min',
          'Weekly goal 150 min',
        ]),
      );
      expect(find.text('Weekly goal rate'), findsOneWidget);
      expect(find.text('8-week average'), findsOneWidget);
    });

    testWidgets('영어 빈 상태도 번역되어 있다', (tester) async {
      await _pump(tester, locale: 'en', empty: true);

      expect(
        find.text("Couldn't load this week's workout records"),
        findsOneWidget,
      );
    });

    testWidgets('영어 화면에 한글이 남아 있지 않다', (tester) async {
      await _pump(
        tester,
        locale: 'en',
        report: _report(
          days: const <ReportDay>[
            ReportDay(completion: 100, exercises: <String>['Squat']),
          ],
        ),
      );

      final RegExp hangul = RegExp(r'[가-힣]');
      for (final Element e in find.byType(Text).evaluate()) {
        final String? data = (e.widget as Text).data;
        if (data == null) continue;
        expect(hangul.hasMatch(data), isFalse, reason: '번역되지 않은 글: $data');
      }
    });

    testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
      await _pump(tester, size: const Size(420, 900));

      expect(tester.takeException(), isNull);
    });
  });
}
