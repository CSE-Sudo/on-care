/// 회원 앱 결과지가 읽는 자료 (#2652).
///
/// 결과지는 트레이너 웹과 같은 한 장이라, 자료도 트레이너 웹이 같은 회원을 두고
/// 읽는 것과 같아야 한다. 여기서는 실서버 경로가 **어느 엔드포인트에서 무엇을**
/// 읽는지, 곁가지(답·추이·직전 주)를 못 읽을 때 결과지가 어떻게 서는지, 데모
/// 경로가 트레이너 웹 데모와 같은 규칙을 쓰는지를 본다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/member_report_sheet_repository.dart';
import 'package:oncare_report/oncare_report.dart';

class _MockExercise extends Mock implements ExerciseRepository {}

final DateTime _monday = DateTime(2026, 9, 14);

/// 지난 주를 보는 기준 시각 — 그 주는 이미 끝났다.
final DateTime _later = DateTime(2026, 9, 24, 21);

Map<String, dynamic> _report({
  String weekStart = '2026-09-14',
  String name = '김민수',
  int booked = 2,
  int done = 1,
  int? completion = 80,
}) => <String, dynamic>{
  'member_id': 'user-7d4e9a2c5f18',
  'member_name': name,
  'week_start': weekStart,
  'week_end': '2026-09-20',
  'sessions_booked': booked,
  'sessions_done': done,
  'completion_avg': completion,
  'sodium_over_days': 2,
  'sodium_avg': 2100,
  'week_completion': <int>[80, 0, 90, 0, 70, 0, 0],
  'sodium_week': <int>[2100, 0, 2300, 0, 1900, 0, 0],
  'calories_week': <int>[1800, 0, 2000, 0, 1900, 0, 0],
  'sugar_week': <double>[20, 0, 30, 0, 25, 0, 0],
  'carbs_week': <double>[200, 0, 210, 0, 190, 0, 0],
  'protein_week': <double>[90, 0, 95, 0, 100, 0, 0],
  'fat_week': <double>[50, 0, 55, 0, 45, 0, 0],
  'calorie_target': 1900,
  'days': <Map<String, dynamic>>[
    <String, dynamic>{
      'completion': 80,
      'exercises': <String>['스쿼트', '플랭크 ✗'],
    },
  ],
  'message': '',
};

Map<String, dynamic> _feedback({bool submitted = true}) => <String, dynamic>{
  'week_start': '2026-09-14',
  'submitted': submitted,
  'condition': submitted ? 'tired' : '',
  'intensity': submitted ? 'hard' : '',
  'pain_area': submitted ? '왼쪽 무릎' : '',
  'pain_on': submitted ? '2026-09-16' : '',
  'note': submitted ? '야근이 겹쳤어요' : '',
  'submitted_at': null,
};

/// 경로·질의로 답하는 가짜 서버. 답이 int 면 그 상태 코드로 실패한다.
class _Server {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Object Function(RequestOptions)> routes =
      <String, Object Function(RequestOptions)>{};

  Dio dio() {
    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions o, RequestInterceptorHandler handler) {
          requests.add(o);
          final Object Function(RequestOptions)? route = routes[o.path];
          final Object answer = route == null ? 404 : route(o);
          if (answer is int) {
            handler.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.badResponse,
                response: Response<Object?>(
                  requestOptions: o,
                  statusCode: answer,
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<Object?>(requestOptions: o, statusCode: 200, data: answer),
          );
        },
      ),
    );
    return dio;
  }

  List<String> weeksAsked(String path) => <String>[
    for (final RequestOptions o in requests)
      if (o.path == path) o.queryParameters['week_start'] as String,
  ];
}

ExerciseWeek _exerciseWeek({
  List<double> cardio = const <double>[],
  List<double> sets = const <double>[],
  List<double> stretching = const <double>[],
}) => ExerciseWeek(
  sessions: const <ExerciseSession>[],
  dailyMinutes: const <double>[],
  dayLabels: const <String>[],
  totalMinutes: 0,
  totalCalories: 0,
  streakDays: 0,
  aiCoachMessage: '',
  cardioMinutes: cardio,
  strengthSets: sets,
  stretchingMinutes: stretching,
);

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2000)));

  late _Server server;
  late _MockExercise exercise;

  setUp(() {
    server = _Server();
    server.routes['/me/coach/weekly-report'] = (RequestOptions o) =>
        _report(weekStart: o.queryParameters['week_start'] as String);
    server.routes['/me/coach/weekly-feedback'] = (_) => _feedback();
    exercise = _MockExercise();
    when(
      () => exercise.fetchPeriod(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async => const <ExercisePeriodWeek>[]);
  });

  DioMemberReportSheetRepository repository({DateTime? now}) =>
      DioMemberReportSheetRepository(
        server.dio(),
        exercise: exercise,
        now: () => now ?? _later,
      );

  group('실서버 — 그 주', () {
    test('회원 본인 리포트 엔드포인트에서 그 주 월요일로 읽는다', () async {
      final ReportSheetInputs inputs = await repository().fetch(
        weekStart: DateTime(2026, 9, 17),
        languageCode: 'ko',
      );

      expect(
        server.weeksAsked('/me/coach/weekly-report'),
        contains('2026-09-14'),
      );
      expect(inputs.week.weekStart, _monday);
      expect(inputs.week.memberName, '김민수');
    });

    test('트레이너 리포트와 같은 필드를 그대로 싣는다', () async {
      final ReportSheetWeek week = (await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      )).week;

      expect(week.sessionsBooked, 2);
      expect(week.sessionsDone, 1);
      expect(week.attendanceRate, 50);
      expect(week.completionAvg, 80);
      expect(week.sodiumAvg, 2100);
      expect(week.calorieTarget, 1900);
      expect(week.caloriesWeek, <int>[1800, 0, 2000, 0, 1900, 0, 0]);
      expect(week.days.single.exercises, <String>['스쿼트', '플랭크 ✗']);
      expect(week.isCurrentWeek, isFalse);
    });

    test('지나는 중인 주는 이번 주로 읽는다', () async {
      final ReportSheetWeek week = (await repository(
        now: DateTime(2026, 9, 16, 9),
      ).fetch(weekStart: _monday, languageCode: 'ko')).week;
      expect(week.isCurrentWeek, isTrue);
    });

    test('그 주를 못 읽으면 던진다 — 빈 결과지를 그리지 않는다', () async {
      server.routes['/me/coach/weekly-report'] = (_) => 500;
      await expectLater(
        repository().fetch(weekStart: _monday, languageCode: 'ko'),
        throwsA(isA<AppError>()),
      );
    });

    test('그 주를 못 읽어도 곁가지 오류가 떠돌지 않는다', () async {
      server.routes['/me/coach/weekly-report'] = (_) => 500;
      server.routes['/me/coach/weekly-feedback'] = (_) => 500;
      when(
        () => exercise.fetchPeriod(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenThrow(StateError('offline'));
      await expectLater(
        repository().fetch(weekStart: _monday, languageCode: 'ko'),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('실서버 — 회원의 답', () {
    test('낸 답은 결과지 ② 칸에 실린다', () async {
      final ReportSheetAnswers? answers = (await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      )).week.answers;

      expect(answers, isNotNull);
      expect(answers!.conditionWire, 'tired');
      expect(answers.intensityWire, 'hard');
      expect(answers.painArea, '왼쪽 무릎');
      expect(answers.painOn, DateTime(2026, 9, 16));
      expect(answers.note, '야근이 겹쳤어요');
      expect(server.weeksAsked('/me/coach/weekly-feedback'), <String>[
        '2026-09-14',
      ]);
    });

    test('안 낸 주는 미응답이다', () async {
      server.routes['/me/coach/weekly-feedback'] = (_) =>
          _feedback(submitted: false);
      final ReportSheetWeek week = (await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      )).week;
      expect(week.answers, isNull);
    });

    test('담당 트레이너가 없어(404) 답이 없어도 결과지는 선다', () async {
      server.routes['/me/coach/weekly-feedback'] = (_) => 404;
      final ReportSheetInputs inputs = await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      );
      expect(inputs.week.answers, isNull);
      expect(inputs.week.memberName, '김민수');
    });

    test('답을 읽다 실패해도 결과지는 선다', () async {
      server.routes['/me/coach/weekly-feedback'] = (_) => 500;
      final ReportSheetInputs inputs = await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      );
      expect(inputs.week.answers, isNull);
    });
  });

  group('실서버 — 직전 넉 주', () {
    test('4주 평균 대비에 쓸 직전 넉 주를 최근 주부터 읽는다', () async {
      final ReportSheetInputs inputs = await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      );
      expect(
        server.weeksAsked('/me/coach/weekly-report'),
        unorderedEquals(<String>[
          '2026-09-14',
          '2026-09-07',
          '2026-08-31',
          '2026-08-24',
          '2026-08-17',
        ]),
      );
      expect(
        inputs.history.map((ReportSheetWeek w) => w.weekStart).toList(),
        <DateTime>[
          DateTime(2026, 9, 7),
          DateTime(2026, 8, 31),
          DateTime(2026, 8, 24),
          DateTime(2026, 8, 17),
        ],
      );
    });

    test('읽지 못한 직전 주는 빼고 나머지로 견준다', () async {
      server.routes['/me/coach/weekly-report'] = (RequestOptions o) {
        final String week = o.queryParameters['week_start'] as String;
        return week == '2026-08-31' ? 500 : _report(weekStart: week);
      };
      final ReportSheetInputs inputs = await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      );
      expect(inputs.history, hasLength(3));
      expect(
        inputs.history.map((ReportSheetWeek w) => w.weekStart),
        isNot(contains(DateTime(2026, 8, 31))),
      );
    });
  });

  group('실서버 — 여덟 주 운동 추이', () {
    test('기간 조회 한 번으로 여덟 주를 읽는다', () async {
      await repository().fetch(weekStart: _monday, languageCode: 'ko');
      verify(
        () => exercise.fetchPeriod(
          from: DateTime(2026, 7, 27),
          to: DateTime(2026, 9, 20),
        ),
      ).called(1);
    });

    test('지나는 중인 주는 오늘까지만 묻는다', () async {
      await repository(
        now: DateTime(2026, 9, 16, 9),
      ).fetch(weekStart: _monday, languageCode: 'ko');
      verify(
        () => exercise.fetchPeriod(
          from: DateTime(2026, 7, 27),
          to: DateTime(2026, 9, 16),
        ),
      ).called(1);
    });

    test('유형별로 더해 그 유형의 단위로 싣는다', () async {
      when(
        () => exercise.fetchPeriod(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => <ExercisePeriodWeek>[
          (
            weekStart: _monday,
            week: _exerciseWeek(
              cardio: const <double>[30, 0, 40.4, 0, 0, 0, 0],
              sets: const <double>[3, 3, 0, 3, 0, 0, 0],
              stretching: const <double>[10, 0, 0, 0, 10, 0, 0],
            ),
          ),
        ],
      );
      final ReportSheetTrend trend = (await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      )).trend!;

      expect(trend.weeks, hasLength(kReportSheetTrendWeeks));
      final ReportSheetTrendWeek last = trend.currentWeek!;
      expect(last.weekStart, _monday);
      expect(last.valueOf(ExerciseKind.cardio), 70);
      expect(last.valueOf(ExerciseKind.strength), 9);
      expect(last.valueOf(ExerciseKind.stretching), 20);
    });

    test('회원이 정한 목표로 견준다', () async {
      final ReportSheetTrend trend = (await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
        goals: const ReportSheetGoals(
          weeklyCardioMinutes: 200,
          weeklyStrengthSets: 12,
          weeklyStretchingMinutes: 30,
        ),
      )).trend!;
      expect(trend.goalOf(ExerciseKind.cardio), 200);
      expect(trend.goalOf(ExerciseKind.strength), 12);
      expect(trend.goalOf(ExerciseKind.stretching), 30);
    });

    test('추이를 못 읽으면 그 칸만 불러올 수 없음으로 선다', () async {
      when(
        () => exercise.fetchPeriod(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenThrow(StateError('offline'));
      final ReportSheetInputs inputs = await repository().fetch(
        weekStart: _monday,
        languageCode: 'ko',
      );
      expect(inputs.trend, isNull);
      expect(inputs.week.memberName, '김민수');
    });
  });

  group('추이 주 만들기', () {
    test('여덟 개의 월요일이 오래된 주부터 그 주까지 선다', () {
      final List<DateTime> mondays = reportSheetTrendMondays(_monday);
      expect(mondays, hasLength(kReportSheetTrendWeeks));
      expect(mondays.first, DateTime(2026, 7, 27));
      expect(mondays.last, _monday);
      for (final DateTime m in mondays) {
        expect(m.weekday, DateTime.monday);
      }
    });

    test('응답에 없는 주는 0 으로 채워 자리를 지킨다', () {
      final List<DateTime> mondays = reportSheetTrendMondays(_monday);
      final List<ReportSheetTrendWeek> weeks = reportSheetTrendWeeksOf(
        mondays,
        <ExercisePeriodWeek>[
          (
            weekStart: DateTime(2026, 8, 31),
            week: _exerciseWeek(cardio: const <double>[50]),
          ),
        ],
      );
      expect(weeks, hasLength(mondays.length));
      expect(
        weeks.map((ReportSheetTrendWeek w) => w.weekStart).toList(),
        mondays,
      );
      expect(weeks[5].valueOf(ExerciseKind.cardio), 50);
      expect(weeks[4].isEmpty, isTrue);
      expect(weeks[6].isEmpty, isTrue);
    });

    test('응답의 주 시작이 월요일이 아니어도 그 주 자리에 앉는다', () {
      final List<ReportSheetTrendWeek> weeks = reportSheetTrendWeeksOf(
        <DateTime>[_monday],
        <ExercisePeriodWeek>[
          (
            weekStart: DateTime(2026, 9, 16),
            week: _exerciseWeek(sets: const <double>[4]),
          ),
        ],
      );
      expect(weeks.single.valueOf(ExerciseKind.strength), 4);
    });
  });

  group('데모', () {
    final DemoFixture fixture = DemoFixture.load();
    final DateTime now = DateTime(2026, 9, 17, 20);
    final DateTime lastMonday = DateTime(2026, 9, 7);

    test('트레이너 웹 데모와 같은 규칙으로 김민수의 한 주를 세운다', () async {
      final ReportSheetInputs mine = await DemoMemberReportSheetRepository(
        fixture: fixture,
        now: () => now,
      ).fetch(weekStart: DateTime(2026, 9, 10), languageCode: 'ko');
      final ReportSheetInputs trainer = demoReportSheetInputs(
        fixture: fixture,
        weekStart: lastMonday,
        now: now,
      );

      expect(mine.week.memberName, trainer.week.memberName);
      expect(mine.week.weekStart, lastMonday);
      expect(mine.week.sessionsBooked, trainer.week.sessionsBooked);
      expect(mine.week.sessionsDone, trainer.week.sessionsDone);
      expect(mine.week.completionAvg, trainer.week.completionAvg);
      expect(mine.week.sodiumAvg, trainer.week.sodiumAvg);
      expect(mine.week.caloriesWeek, trainer.week.caloriesWeek);
      expect(mine.week.weekCompletion, trainer.week.weekCompletion);
      expect(mine.history, hasLength(trainer.history.length));
      expect(mine.trend!.weeks, hasLength(trainer.trend!.weeks.length));
    });

    test('회원 앱 목표를 넘겨도 데모는 트레이너 웹 데모의 목표로 견준다', () async {
      final ReportSheetInputs mine =
          await DemoMemberReportSheetRepository(
            fixture: fixture,
            now: () => now,
          ).fetch(
            weekStart: lastMonday,
            languageCode: 'ko',
            goals: const ReportSheetGoals(weeklyCardioMinutes: 999),
          );
      expect(
        mine.trend!.goalOf(ExerciseKind.cardio),
        kDemoReportGoals.weeklyCardioMinutes,
      );
    });

    test('영어 화면이면 회원 답도 영어다', () async {
      final ReportSheetInputs ko = await DemoMemberReportSheetRepository(
        fixture: fixture,
        now: () => now,
      ).fetch(weekStart: lastMonday, languageCode: 'ko');
      final ReportSheetInputs en = await DemoMemberReportSheetRepository(
        fixture: fixture,
        now: () => now,
      ).fetch(weekStart: lastMonday, languageCode: 'en');
      final ReportSheetAnswers? koAnswers = ko.week.answers;
      final ReportSheetAnswers? enAnswers = en.week.answers;
      expect(koAnswers?.conditionWire, enAnswers?.conditionWire);
      if (koAnswers != null && koAnswers.note.isNotEmpty) {
        expect(enAnswers!.note, isNot(koAnswers.note));
      }
    });
  });
}
