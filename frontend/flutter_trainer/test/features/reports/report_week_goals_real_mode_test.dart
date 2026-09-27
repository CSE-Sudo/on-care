/// 실서버 모드의 리포트 화면이 지난 주에 고른 목표를 읽어 쓰는가. (#2287)
///
/// 저장소 단위 테스트는 목표가 [WeeklyReport.weekGoals] 에 실리는지까지만
/// 본다. 이 파일은 그 목록이 리포트 화면까지 가서 **한·영 두 로케일로** 쓰이는지를
/// 본다 — 확인 단계의 탄단지 막대는 크게 모자란 영양소가 지난 주 목표 하나를
/// 떨어뜨렸으면 그 목표를 근거로 이어 적는데, 예전에는 실서버에서 목표가 언제나
/// 비어 있어 이 줄이 한 번도 서지 않았다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

import '../../helpers/pump_app.dart';

class _MockDio extends Mock implements Dio {}

/// 경로별로 실서버처럼 답하는 Dio.
///
/// 리포트 본문은 단백질이 하루 목표 120g 의 절반에 그친 주다. [goals] 가
/// null 이면 목표 요청만 500 으로 실패한다.
_MockDio _server({required List<String>? goals, List<String>? goalsAsked}) {
  final _MockDio dio = _MockDio();
  when(
    () => dio.get<Map<String, dynamic>>(
      any(),
      queryParameters: any(named: 'queryParameters'),
    ),
  ).thenAnswer((inv) async {
    final String path = inv.positionalArguments.first as String;
    final Map<String, dynamic> query =
        inv.namedArguments[#queryParameters] as Map<String, dynamic>;
    if (path.endsWith('/report/goals')) {
      goalsAsked?.add(query['week_start'] as String);
      if (goals == null) {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: path),
            statusCode: 500,
          ),
        );
      }
      return _ok(<String, dynamic>{
        'week_start': query['week_start'],
        'goals': goals,
      }, path);
    }
    if (path.endsWith('/report/member-feedback')) {
      return _ok(<String, dynamic>{
        'week_start': query['week_start'],
        'submitted': false,
      }, path);
    }
    if (path.endsWith('/report/summary')) {
      return _ok(<String, dynamic>{
        'headline': '',
        'points': <String>[],
        'generated_by': 'rule',
      }, path);
    }
    if (path.endsWith('/report/feedback')) {
      return _ok(<String, dynamic>{'body': '', 'updated_at': null}, path);
    }
    // 리포트 본문 — 주변 주(비교·추세 카드)도 같은 경로로 묻는다.
    return _ok(<String, dynamic>{
      'week_start': query['week_start'],
      'sessions_booked': 2,
      'sessions_done': 1,
      'completion_avg': 60,
      'calories_week': <int>[1800, 1850, 1900, 1820, 1880, 1790, 1860],
      'carbs_week': <double>[250, 245, 255, 248, 250, 242, 251],
      'protein_week': <double>[60, 60, 60, 60, 60, 60, 60],
      'fat_week': <double>[60, 58, 61, 59, 60, 60, 60],
      'carbs_target': 250,
      'protein_target': 120,
      'fat_target': 60,
    }, path);
  });
  return dio;
}

Response<Map<String, dynamic>> _ok(Map<String, dynamic> body, String path) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body,
    );

void main() {
  // 리포트는 아직 오지 않은 주를 열 수 없다 — 지난 주를 본다.
  final DateTime lastWeek = weekStartOf(
    nowKst(),
  ).subtract(const Duration(days: 7));

  Future<void> openReport(
    WidgetTester tester, {
    required _MockDio dio,
    Locale locale = const Locale('ko'),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      locale: locale,
      at: AppRoutes.reportFor('seed-client-1', weekStart: lastWeek),
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(DioReportRepository(dio)),
      ],
    );
    await settle(tester);
  }

  testWidgets('한국어 — 지난 주 목표가 모자람의 근거로 이어 적힌다', (tester) async {
    await openReport(
      tester,
      dio: _server(goals: <String>['주 3회 기록', '저녁 단백질 챙기기']),
    );

    expect(find.textContaining('단백질이(가) 목표에 많이 모자라요'), findsOneWidget);
    expect(
      find.textContaining('지난 주 목표 “저녁 단백질 챙기기”이 미이행으로 판정된 근거예요'),
      findsOneWidget,
    );
  });

  testWidgets("English — last week's goal is cited as the evidence", (
    tester,
  ) async {
    await openReport(
      tester,
      locale: const Locale('en'),
      dio: _server(goals: <String>['Log 3 days', 'Protein at every dinner']),
    );

    expect(find.textContaining('Protein is well under target'), findsOneWidget);
    expect(
      find.textContaining(
        "This is the evidence last week's goal “Protein at every dinner” "
        'was judged unmet',
      ),
      findsOneWidget,
    );
  });

  testWidgets('보고 있는 주의 목표를 묻는다', (tester) async {
    final List<String> asked = <String>[];
    await openReport(
      tester,
      dio: _server(goals: <String>['저녁 단백질 챙기기'], goalsAsked: asked),
    );

    expect(asked, contains(ymd(lastWeek)));
  });

  testWidgets('지난 주에 고른 목표가 없으면 근거 줄 없이 모자람만 짚는다', (tester) async {
    await openReport(tester, dio: _server(goals: const <String>[]));

    expect(find.textContaining('단백질이(가) 목표에 많이 모자라요'), findsOneWidget);
    expect(find.textContaining('미이행으로 판정된 근거예요'), findsNothing);
  });

  testWidgets('다른 영양소에 관한 목표는 근거로 잇지 않는다', (tester) async {
    await openReport(tester, dio: _server(goals: <String>['주 3회 하체 운동']));

    expect(find.textContaining('단백질이(가) 목표에 많이 모자라요'), findsOneWidget);
    expect(find.textContaining('미이행으로 판정된 근거예요'), findsNothing);
  });

  testWidgets('목표 요청만 실패하면 근거 줄만 빠지고 리포트는 뜬다', (tester) async {
    await openReport(tester, dio: _server(goals: null));

    expect(
      find.byKey(const ValueKey<String>('reports-weekly-retry')),
      findsNothing,
    );
    expect(find.textContaining('단백질이(가) 목표에 많이 모자라요'), findsOneWidget);
    expect(find.textContaining('미이행으로 판정된 근거예요'), findsNothing);
  });

  testWidgets('Goal request failure keeps the English report on screen', (
    tester,
  ) async {
    await openReport(
      tester,
      locale: const Locale('en'),
      dio: _server(goals: null),
    );

    expect(
      find.byKey(const ValueKey<String>('reports-weekly-retry')),
      findsNothing,
    );
    expect(find.textContaining('Protein is well under target'), findsOneWidget);
    expect(find.textContaining('was judged unmet'), findsNothing);
  });
}
