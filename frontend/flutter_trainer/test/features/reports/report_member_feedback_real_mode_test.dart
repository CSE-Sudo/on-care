/// 실서버 모드의 리포트 화면이 회원 주간 피드백을 그리는가. (#2286)
///
/// 저장소 단위 테스트는 값이 [WeeklyReport] 에 실리는지까지만 본다. 이 파일은
/// 그 값이 리포트 편집기의 첫 카드까지 가서 **한·영 두 로케일로** 서는지를
/// 본다 — 예전에는 실서버에서 언제나 "아직 받지 못함" 이었다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

import '../../helpers/pump_app.dart';

class _MockDio extends Mock implements Dio {}

/// 경로별로 실서버처럼 답하는 Dio. [feedback] 이 null 이면 피드백 요청만
/// 500 으로 실패한다.
_MockDio _server({required Map<String, dynamic>? feedback}) {
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
    if (path.endsWith('/report/member-feedback')) {
      if (feedback == null) {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: path),
            statusCode: 500,
          ),
        );
      }
      return _ok(feedback, path);
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
      'completion_avg': 32,
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
  final DateTime painDay = lastWeek.add(const Duration(days: 3));
  final DateTime submittedOn = lastWeek.add(const Duration(days: 6));

  Map<String, dynamic> answered(String painArea, String note) =>
      <String, dynamic>{
        'week_start': ymd(lastWeek),
        'submitted': true,
        'condition': 'tired',
        'intensity': 'too_hard',
        'pain_area': painArea,
        'pain_on': ymd(painDay),
        'note': note,
        'submitted_at': null,
      };

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

  String answer(WidgetTester tester, String key) {
    final Text t = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byType(Text),
          )
          .last,
    );
    return t.data!;
  }

  testWidgets('한국어 — 회원이 낸 답이 첫 카드에 선다', (tester) async {
    await openReport(
      tester,
      dio: _server(feedback: answered('오른 무릎', '3일차부터 힘들었어요')),
    );

    expect(
      find.byKey(const ValueKey<String>('report-feedback-empty')),
      findsNothing,
    );
    expect(answer(tester, 'report-feedback-condition'), '😩 지쳤어요');
    expect(answer(tester, 'report-feedback-intensity'), '너무 힘들었어요');
    expect(
      answer(tester, 'report-feedback-pain'),
      '오른 무릎 (${painDay.month}월 ${painDay.day}일)',
    );
    expect(find.text('3일차부터 힘들었어요'), findsOneWidget);
    expect(
      find.text('· 주 1회 · ${submittedOn.month}월 ${submittedOn.day}일 제출'),
      findsOneWidget,
    );
    expect(find.text('확인 필요'), findsOneWidget);
  });

  testWidgets('English — the member answer renders in the first card', (
    tester,
  ) async {
    await openReport(
      tester,
      locale: const Locale('en'),
      dio: _server(feedback: answered('Right knee', 'Tough from day 3')),
    );

    expect(
      find.byKey(const ValueKey<String>('report-feedback-empty')),
      findsNothing,
    );
    expect(answer(tester, 'report-feedback-condition'), '😩 Worn out');
    expect(answer(tester, 'report-feedback-intensity'), 'Too hard');
    expect(
      answer(tester, 'report-feedback-pain'),
      'Right knee (${painDay.month}/${painDay.day})',
    );
    expect(find.text('Tough from day 3'), findsOneWidget);
    expect(
      find.text('· Weekly · submitted ${submittedOn.month}/${submittedOn.day}'),
      findsOneWidget,
    );
    expect(find.text('Needs attention'), findsOneWidget);
  });

  testWidgets('답하지 않은 주는 "아직 받지 못함" 을 그린다', (tester) async {
    await openReport(
      tester,
      dio: _server(
        feedback: <String, dynamic>{
          'week_start': ymd(lastWeek),
          'submitted': false,
          'condition': '',
          'intensity': '',
          'pain_area': '',
          'pain_on': '',
          'note': '',
        },
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('report-feedback-empty')),
      findsOneWidget,
    );
    // 제목 줄 곁말로 선다(#2450) — 머리가 `· ` 를 앞에 붙인다.
    expect(find.text('· 아직 받지 못했어요'), findsOneWidget);
  });

  testWidgets('Not submitted yet reads naturally in English', (tester) async {
    await openReport(
      tester,
      locale: const Locale('en'),
      dio: _server(
        feedback: <String, dynamic>{
          'week_start': ymd(lastWeek),
          'submitted': false,
        },
      ),
    );

    // 제목 줄 곁말로 선다(#2450) — 머리가 `· ` 를 앞에 붙인다.
    expect(find.text('· Not received yet'), findsOneWidget);
  });

  testWidgets('피드백 요청만 실패하면 그 칸만 비고 리포트는 뜬다', (tester) async {
    await openReport(tester, dio: _server(feedback: null));

    // 읽지 못한 것을 `아직 받지 못했어요` 로 그리지 않는다(#3246).
    expect(
      find.byKey(const ValueKey<String>('report-feedback-failed')),
      findsOneWidget,
    );
    expect(find.text('· 아직 받지 못했어요'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reports-weekly-retry')),
      findsNothing,
    );
  });
}
