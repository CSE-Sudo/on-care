/// 회원 앱 주간 리포트 결과지가 읽는 자료. (#2652)
///
/// 결과지는 트레이너 웹과 **같은 한 장**이다(`package:oncare_report`). 그래서 자료도
/// 트레이너 웹이 같은 회원을 두고 읽는 것과 같아야 한다.
///
/// - 실서버: 트레이너 리포트와 같은 계산을 쓰는 `GET /me/coach/weekly-report` 에서
///   그 주와 직전 넉 주를, 회원이 낸 답은 `GET /me/coach/weekly-feedback` 에서,
///   여덟 주 운동 추이는 `GET /exercise/weeks` 한 번으로 읽는다.
/// - 데모: 서버가 없다. 트레이너 웹 데모가 김민수를 그리는 것과 같은 픽스처·같은
///   규칙(`demoReportSheetInputs`)으로 세운다 — 두 앱을 나란히 놓고 시연하므로
///   각자 세우면 같은 주의 점수가 어긋난다.
///
/// 트레이너만 보는 것(다른 회원·트레이너 메모·자동 초안)은 두 경로 모두 싣지 않는다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:dio/dio.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 결과지 한 장의 자료를 읽는 곳.
abstract interface class MemberReportSheetRepository {
  /// [weekStart] 가 든 주의 결과지 자료.
  ///
  /// [languageCode] 는 데모 자료의 회원 답(한 줄 피드백)을 고르는 데 쓴다 — 실서버
  /// 자료는 회원이 적은 그대로라 언어와 무관하다. [goals] 는 회원이 MY 에서 정한
  /// 주간 운동 목표다.
  ///
  /// 그 주 자체를 읽지 못하면 던진다. 답·추이·직전 주는 못 읽어도 던지지 않고
  /// 그 칸만 `미응답`·`불러올 수 없음`·`미집계` 로 선다 — 트레이너 웹과 같다.
  Future<ReportSheetInputs> fetch({
    required DateTime weekStart,
    required String languageCode,
    ReportSheetGoals goals,
  });
}

/// 실서버 경로.
class DioMemberReportSheetRepository implements MemberReportSheetRepository {
  /// Creates the repository.
  DioMemberReportSheetRepository(
    this._dio, {
    required ExerciseRepository exercise,
    DateTime Function() now = nowKst,
  }) : _exercise = exercise,
       _now = now;

  final Dio _dio;
  final ExerciseRepository _exercise;
  final DateTime Function() _now;

  @override
  Future<ReportSheetInputs> fetch({
    required DateTime weekStart,
    required String languageCode,
    ReportSheetGoals goals = const ReportSheetGoals(),
  }) async {
    final DateTime monday = reportWeekStartOf(weekStart);
    final DateTime today = _now();
    // 한꺼번에 부른다 — 하나씩 기다리면 왕복이 줄줄이 이어져 미리보기가 늦게 선다.
    // 곁가지는 스스로 실패를 null 로 삼킨다: 그 주를 읽지 못해 던질 때 남은
    // Future 의 오류가 떠돌지 않게 한다.
    final Future<ReportSheetAnswers?> answers = _answers(monday);
    final Future<ReportSheetTrend?> trend = _trend(monday, today, goals);
    final Future<List<ReportSheetWeek?>> history =
        Future.wait<ReportSheetWeek?>(<Future<ReportSheetWeek?>>[
          for (int back = 1; back <= kReportSheetHistoryWeeks; back++)
            _week(
              DateTime(monday.year, monday.month, monday.day - back * 7),
              today,
            ).then<ReportSheetWeek?>(
              (ReportSheetWeekData w) => w,
              onError: (Object _) => null,
            ),
        ]);
    final ReportSheetWeekData week = await _week(monday, today);
    return ReportSheetInputs(
      week: week.withAnswers(await answers),
      trend: await trend,
      history: <ReportSheetWeek>[
        for (final ReportSheetWeek? w in await history) ?w,
      ],
    );
  }

  Future<ReportSheetWeekData> _week(DateTime monday, DateTime today) async {
    try {
      final Response<Map<String, dynamic>> res = await _dio
          .get<Map<String, dynamic>>(
            '/me/coach/weekly-report',
            queryParameters: <String, Object?>{'week_start': wireDate(monday)},
          );
      final Map<String, dynamic>? data = res.data;
      if (data == null) throw const FormatException('Missing weekly report.');
      return reportSheetWeekFromJson(data, today: today);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// 회원이 그 주에 낸 답. 담당 트레이너가 없으면(404) 답도 없다.
  Future<ReportSheetAnswers?> _answers(DateTime monday) async {
    try {
      final Response<Map<String, dynamic>> res = await _dio
          .get<Map<String, dynamic>>(
            '/me/coach/weekly-feedback',
            queryParameters: <String, Object?>{'week_start': wireDate(monday)},
          );
      final Map<String, dynamic>? data = res.data;
      return data == null ? null : reportSheetAnswersFromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// [monday] 로 끝나는 여덟 주의 유형별 운동 실적. 기록이 없는 주는 0 이다.
  Future<ReportSheetTrend?> _trend(
    DateTime monday,
    DateTime today,
    ReportSheetGoals goals,
  ) async {
    try {
      final List<DateTime> mondays = reportSheetTrendMondays(monday);
      final DateTime sunday = DateTime(
        monday.year,
        monday.month,
        monday.day + 6,
      );
      final DateTime day = DateTime(today.year, today.month, today.day);
      final List<ExercisePeriodWeek> period = await _exercise.fetchPeriod(
        from: mondays.first,
        // 아직 오지 않은 날까지 묻지 않는다.
        to: sunday.isAfter(day) ? day : sunday,
      );
      return ReportSheetTrendData(
        weeks: reportSheetTrendWeeksOf(mondays, period),
        goals: goals,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 데모 경로 — 트레이너 웹 데모와 같은 픽스처·같은 규칙.
class DemoMemberReportSheetRepository implements MemberReportSheetRepository {
  /// Creates the repository.
  DemoMemberReportSheetRepository({
    DemoFixture? fixture,
    DateTime Function() now = nowKst,
  }) : _fixture = fixture,
       _now = now;

  final DemoFixture? _fixture;
  final DateTime Function() _now;

  @override
  Future<ReportSheetInputs> fetch({
    required DateTime weekStart,
    required String languageCode,
    // 데모 목표는 트레이너 웹 데모의 김민수 목표(`kDemoReportGoals`)다. 회원
    // 앱 MY 의 목표로 바꾸면 두 앱의 달성률이 어긋난다.
    ReportSheetGoals goals = const ReportSheetGoals(),
  }) async => demoReportSheetInputs(
    fixture: _fixture ?? DemoFixture.load(),
    weekStart: reportWeekStartOf(weekStart),
    now: _now(),
    languageCode: languageCode,
  );
}

/// [monday] 로 끝나는 [kReportSheetTrendWeeks] 개의 월요일(오래된 주 → 그 주).
List<DateTime> reportSheetTrendMondays(DateTime monday) => <DateTime>[
  for (int back = kReportSheetTrendWeeks - 1; back >= 0; back--)
    DateTime(monday.year, monday.month, monday.day - back * 7),
];

/// 기간 응답을 추이의 주들로 옮긴다. 응답에 없는 주는 0 으로 채운다 — 빠진 주를
/// 건너뛰면 막대가 한 칸씩 당겨져 날짜와 어긋난다.
List<ReportSheetTrendWeek> reportSheetTrendWeeksOf(
  List<DateTime> mondays,
  List<ExercisePeriodWeek> period,
) {
  final Map<DateTime, ExerciseWeek> byMonday = <DateTime, ExerciseWeek>{
    for (final ExercisePeriodWeek entry in period)
      reportWeekStartOf(entry.weekStart): entry.week,
  };
  int sum(List<double> xs) =>
      xs.fold<double>(0, (double a, double b) => a + b).round();
  return <ReportSheetTrendWeek>[
    for (final DateTime monday in mondays)
      if (byMonday[monday] case final ExerciseWeek week)
        ReportSheetTrendWeekData(
          weekStart: monday,
          cardioMinutes: sum(week.cardioMinutes),
          strengthSets: sum(week.strengthSets),
          stretchingMinutes: sum(week.stretchingMinutes),
        )
      else
        ReportSheetTrendWeekData(
          weekStart: monday,
          cardioMinutes: 0,
          strengthSets: 0,
          stretchingMinutes: 0,
        ),
  ];
}
