/// 실서버 리포트가 그 주에 적용돼 있던 목표를 함께 읽는가. (#2287)
///
/// 트레이너가 리포트를 보낼 때 고른 다음 주 목표는 `PUT …/report/goals` 로
/// 저장되는데, 실서버 저장소가 `GET …/report/goals` 를 부르지 않아 다음 주
/// 리포트의 `weekGoals` 는 언제나 비어 있었다(데모에서만 채워졌다).
///
/// 이 파일이 지키는 것:
///  * 본문과 **나란히** 부르고, 보고 있는 주를 그대로 묻는다(주 경계는 서버가
///    한 곳에서 계산한다).
///  * 목표가 있으면 순서 그대로 [WeeklyReport.weekGoals] 에 실린다.
///  * 목표가 없거나 이 요청만 실패하면 빈 목록이고 리포트는 그대로 뜬다.
///  * 회원 피드백과 목표가 서로의 실패에 끌려가지 않는다.
///  * 본문이 실패하면 목표가 멀쩡해도 리포트는 오류다.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

import '../../helpers/client_factory.dart';

class _MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> _ok(Map<String, dynamic>? body, String path) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body,
    );

DioException _httpError(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
  ),
);

const String _reportPath = '/trainer/clients/m1/report';
const String _feedbackPath = '/trainer/clients/m1/report/member-feedback';
const String _goalsPath = '/trainer/clients/m1/report/goals';

const Map<String, dynamic> _reportBody = <String, dynamic>{
  'week_start': '2026-09-14',
  'sessions_booked': 2,
  'sessions_done': 1,
  'completion_avg': 32,
};

/// 지난 주 리포트를 보낼 때 고른 목표 두 줄.
const Map<String, dynamic> _picked = <String, dynamic>{
  'week_start': '2026-09-14',
  'goals': <String>['주 2회 하체 추가', '저녁 단백질 30g 이상'],
};

const Map<String, dynamic> _answered = <String, dynamic>{
  'week_start': '2026-09-14',
  'submitted': true,
  'condition': 'tired',
  'intensity': 'too_hard',
  'pain_area': '',
  'pain_on': '',
  'note': '',
};

void main() {
  late _MockDio dio;
  late DioReportRepository repo;
  final client = makeClient(id: 'm1', name: '김민수');
  final weekStart = DateTime(2026, 9, 14);

  void stub(
    String path,
    Future<Response<Map<String, dynamic>>> Function() answer,
  ) {
    when(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) => answer());
  }

  void stubReport() =>
      stub(_reportPath, () async => _ok(_reportBody, _reportPath));

  void stubFeedback() =>
      stub(_feedbackPath, () async => _ok(_answered, _feedbackPath));

  Future<WeeklyReport> load() =>
      repo.watch(client: client, weekStart: weekStart).first;

  setUp(() {
    dio = _MockDio();
    repo = DioReportRepository(dio);
  });

  group('요청', () {
    test('보고 있는 주를 그대로 묻는다 — 한 주를 빼지 않는다', () async {
      stubReport();
      stubFeedback();
      stub(_goalsPath, () async => _ok(_picked, _goalsPath));

      await load();

      final Map<String, dynamic> query =
          verify(
                () => dio.get<Map<String, dynamic>>(
                  _goalsPath,
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(query, <String, String>{'week_start': '2026-09-14'});
    });

    test('리포트 한 번에 한 번만 묻는다', () async {
      stubReport();
      stubFeedback();
      stub(_goalsPath, () async => _ok(_picked, _goalsPath));

      await load();

      verify(
        () => dio.get<Map<String, dynamic>>(
          _goalsPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);
    });

    test('본문 응답을 기다리지 않고 나란히 부른다', () async {
      final Completer<Response<Map<String, dynamic>>> report =
          Completer<Response<Map<String, dynamic>>>();
      stub(_reportPath, () => report.future);
      stubFeedback();
      stub(_goalsPath, () async => _ok(_picked, _goalsPath));

      final Future<WeeklyReport> pending = load();
      await Future<void>.delayed(Duration.zero);

      verify(
        () => dio.get<Map<String, dynamic>>(
          _goalsPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);

      report.complete(_ok(_reportBody, _reportPath));
      expect((await pending).weekGoals, hasLength(2));
    });

    test('목표 응답이 늦으면 리포트가 그 응답을 기다린다', () async {
      // 먼저 온 본문으로 리포트를 내보내면 ③ 이 비어 있다가 사라지지 않는다 —
      // 이 저장소는 한 번만 내보내므로, 늦은 목표를 놓치면 그 주 내내 빈 칸이다.
      final Completer<Response<Map<String, dynamic>>> goals =
          Completer<Response<Map<String, dynamic>>>();
      stubReport();
      stubFeedback();
      stub(_goalsPath, () => goals.future);

      bool done = false;
      final Future<WeeklyReport> pending = load()..then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      goals.complete(_ok(_picked, _goalsPath));
      expect((await pending).weekGoals, _picked['goals']);
    });

    test('회원 id 는 경로에 넣기 전에 인코딩한다', () async {
      const String oddId = 'user/jisu kim';
      final String encoded =
          '/trainer/clients/${Uri.encodeComponent(oddId)}/report';
      when(
        () => dio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((inv) async {
        final String p = inv.positionalArguments.first as String;
        if (p.endsWith('/goals')) return _ok(_picked, p);
        if (p.endsWith('/member-feedback')) return _ok(_answered, p);
        return _ok(_reportBody, p);
      });

      final WeeklyReport report = await repo
          .watch(
            client: makeClient(id: oddId, name: '김지수'),
            weekStart: weekStart,
          )
          .first;

      verify(
        () => dio.get<Map<String, dynamic>>(
          '$encoded/goals',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);
      expect(report.weekGoals, _picked['goals']);
    });
  });

  group('목표가 있는 주', () {
    test('순서 그대로 weekGoals 에 실리고 본문도 함께 온다', () async {
      stubReport();
      stubFeedback();
      stub(_goalsPath, () async => _ok(_picked, _goalsPath));

      final WeeklyReport report = await load();

      expect(report.weekGoals, <String>['주 2회 하체 추가', '저녁 단백질 30g 이상']);
      expect(report.sessionsBooked, 2);
      expect(report.completionAvg, 32);
      // 나란히 온 회원 피드백도 잃지 않는다.
      expect(report.memberFeedback?.condition, WeekCondition.tired);
    });

    test('영어로 적은 목표도 그대로 실린다', () async {
      stubReport();
      stubFeedback();
      stub(
        _goalsPath,
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'goals': <String>['Protein at dinner', 'Two leg days'],
        }, _goalsPath),
      );

      expect((await load()).weekGoals, <String>[
        'Protein at dinner',
        'Two leg days',
      ]);
    });

    test('문자열이 아니거나 빈 줄은 버린다', () async {
      stubReport();
      stubFeedback();
      stub(
        _goalsPath,
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'goals': <Object?>['물 2L', '', '   ', 3, null, true, '계단 이용'],
        }, _goalsPath),
      );

      expect((await load()).weekGoals, <String>['물 2L', '계단 이용']);
    });
  });

  group('목표가 없거나 읽을 수 없는 주 — 빈 목록이고 리포트는 뜬다', () {
    Future<void> expectNoGoals(
      Future<Response<Map<String, dynamic>>> Function() goals,
    ) async {
      stubReport();
      stubFeedback();
      stub(_goalsPath, goals);

      final WeeklyReport report = await load();

      expect(report.weekGoals, isEmpty);
      expect(report.sessionsBooked, 2);
      // 목표만 실패했다 — 회원 피드백까지 비우지 않는다.
      expect(report.memberFeedback, isNotNull);
    }

    test('지난 주에 고른 목표가 없다', () async {
      await expectNoGoals(
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'goals': <String>[],
        }, _goalsPath),
      );
    });

    test('goals 가 빠진 응답', () async {
      await expectNoGoals(
        () async =>
            _ok(<String, dynamic>{'week_start': '2026-09-14'}, _goalsPath),
      );
    });

    test('goals 가 목록이 아니다', () async {
      await expectNoGoals(
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'goals': '주 2회 하체 추가',
        }, _goalsPath),
      );
    });

    test('빈 본문', () async {
      await expectNoGoals(() async => _ok(null, _goalsPath));
    });

    test('404 — 옛 서버에 엔드포인트가 없다', () async {
      await expectNoGoals(() async => throw _httpError(404, _goalsPath));
    });

    test('403 — 이 회원을 볼 권한이 없다', () async {
      await expectNoGoals(() async => throw _httpError(403, _goalsPath));
    });

    test('422 — 서버가 그 주를 거부했다', () async {
      await expectNoGoals(() async => throw _httpError(422, _goalsPath));
    });

    test('500', () async {
      await expectNoGoals(() async => throw _httpError(500, _goalsPath));
    });

    test('연결이 끊김', () async {
      await expectNoGoals(
        () async => throw DioException(
          requestOptions: RequestOptions(path: _goalsPath),
          type: DioExceptionType.connectionError,
        ),
      );
    });

    test('응답 모양 자체가 다르다', () async {
      await expectNoGoals(() async => throw TypeError());
    });
  });

  group('나란히 부른 두 칸은 서로의 실패에 끌려가지 않는다', () {
    test('회원 피드백만 실패해도 목표는 실린다', () async {
      stubReport();
      stub(_feedbackPath, () async => throw _httpError(500, _feedbackPath));
      stub(_goalsPath, () async => _ok(_picked, _goalsPath));

      final WeeklyReport report = await load();

      expect(report.memberFeedback, isNull);
      expect(report.weekGoals, hasLength(2));
    });

    test('둘 다 실패해도 리포트는 뜬다', () async {
      stubReport();
      stub(_feedbackPath, () async => throw _httpError(500, _feedbackPath));
      stub(_goalsPath, () async => throw _httpError(500, _goalsPath));

      final WeeklyReport report = await load();

      expect(report.memberFeedback, isNull);
      expect(report.weekGoals, isEmpty);
      expect(report.sessionsDone, 1);
    });
  });

  group('본문이 실패하면', () {
    test('목표가 멀쩡해도 리포트는 오류다', () async {
      stub(_reportPath, () async => throw _httpError(500, _reportPath));
      stubFeedback();
      stub(_goalsPath, () async => _ok(_picked, _goalsPath));

      await expectLater(load(), throwsA(isA<ServerError>()));
    });

    test('셋 다 실패해도 본문의 오류가 올라온다', () async {
      stub(_reportPath, () async => throw _httpError(404, _reportPath));
      stub(_feedbackPath, () async => throw _httpError(500, _feedbackPath));
      stub(_goalsPath, () async => throw _httpError(500, _goalsPath));

      await expectLater(load(), throwsA(isA<NotFoundError>()));
    });

    test('빈 본문은 목표가 있어도 오류다', () async {
      stub(_reportPath, () async => _ok(null, _reportPath));
      stubFeedback();
      stub(_goalsPath, () async => _ok(_picked, _goalsPath));

      await expectLater(load(), throwsA(isA<ServerError>()));
    });
  });

  group('reportGoalsFromJson', () {
    test('목록을 순서대로 읽는다', () {
      expect(reportGoalsFromJson(_picked), _picked['goals']);
    });

    test('앞뒤 공백은 그대로 둔다 — 서버가 저장할 때 이미 다듬었다', () {
      expect(
        reportGoalsFromJson(<String, dynamic>{
          'goals': <String>[' 물 2L '],
        }),
        <String>[' 물 2L '],
      );
    });

    test('목록이 아니거나 없으면 빈 목록', () {
      for (final Object? goals in <Object?>[
        null,
        '',
        'A',
        3,
        <String, int>{},
      ]) {
        expect(
          reportGoalsFromJson(<String, dynamic>{'goals': goals}),
          isEmpty,
          reason: '$goals',
        );
      }
      expect(reportGoalsFromJson(const <String, dynamic>{}), isEmpty);
    });
  });

  group('weeklyReportFromJson', () {
    test('목표를 넘기지 않으면 빈 목록이다', () {
      expect(weeklyReportFromJson(_reportBody, client).weekGoals, isEmpty);
    });

    test('넘긴 목표가 그대로 실린다', () {
      expect(
        weeklyReportFromJson(
          _reportBody,
          client,
          weekGoals: const <String>['계단 이용'],
        ).weekGoals,
        <String>['계단 이용'],
      );
    });
  });
}
