/// 리포트 작업대 요약 — 실서버 저장소와 응답 변환. (#2863)
///
/// `GET /trainer/reports/queue?week_start=` 가 작업대의 원본이다. 이 파일이
/// 지키는 것:
///  * 회원 수와 무관하게 요청 **하나**만 보낸다 — 회원별 리포트·피드백 경로를
///    부르지 않는다.
///  * 주를 월요일 YYYY-MM-DD 로 보낸다.
///  * 응답을 [ReportQueueSummary] 로 옮긴다 — 기록 없는 평균은 null, 깨진 줄은
///    버린다.
///  * 실패를 빈 큐로 삼키지 않는다.
///  * 주간 리포트 응답의 `calorie_baseline` 을 읽는다(칼로리 `평소`).
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/trainer/reports/queue';

Response<Map<String, dynamic>> _ok(Map<String, dynamic>? body) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: _path),
      statusCode: 200,
      data: body,
    );

DioException _httpError(int status) => DioException(
  requestOptions: RequestOptions(path: _path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: _path),
    statusCode: status,
  ),
);

Map<String, dynamic> _item(
  String id, {
  int booked = 2,
  int done = 1,
  Object? avg = 80,
  List<Object?> week = const <Object?>[100, 60, 0, 0, 0, 0, 0],
}) => <String, dynamic>{
  'member_id': id,
  'sessions_booked': booked,
  'sessions_done': done,
  'completion_avg': avg,
  'week_completion': week,
};

void main() {
  group('reportQueueFromJson', () {
    test('한 줄의 모든 값을 옮긴다', () {
      final List<ReportQueueSummary> items = reportQueueFromJson(
        <String, dynamic>{
          'week_start': '2026-08-10',
          'items': <Object?>[_item('m1', booked: 3, done: 2, avg: 67)],
        },
      );
      expect(items, <ReportQueueSummary>[
        const ReportQueueSummary(
          clientId: 'm1',
          sessionsBooked: 3,
          sessionsDone: 2,
          completionAvg: 67,
          weekCompletion: <int>[100, 60, 0, 0, 0, 0, 0],
        ),
      ]);
    });

    test('기록이 없는 회원의 평균은 0 이 아니라 null 이다', () {
      final ReportQueueSummary item = reportQueueFromJson(<String, dynamic>{
        'items': <Object?>[_item('m1', avg: null, week: const <Object?>[])],
      }).single;
      expect(item.completionAvg, isNull);
      expect(item.weekCompletion, isEmpty);
    });

    test('회원 id 를 읽지 못한 줄은 버리고 나머지는 순서대로 둔다', () {
      final List<ReportQueueSummary> items = reportQueueFromJson(
        <String, dynamic>{
          'items': <Object?>[
            _item('m1'),
            <String, dynamic>{'sessions_booked': 1},
            <String, dynamic>{'member_id': ''},
            'not-a-map',
            _item('m2'),
          ],
        },
      );
      expect(items.map((ReportQueueSummary s) => s.clientId), <String>[
        'm1',
        'm2',
      ]);
    });

    test('items 가 없거나 깨졌으면 빈 큐다', () {
      expect(reportQueueFromJson(<String, dynamic>{}), isEmpty);
      expect(reportQueueFromJson(<String, dynamic>{'items': 'x'}), isEmpty);
    });

    test('음수·숫자 아닌 세션 수는 0, 숫자 아닌 이행률 칸은 빈칸으로 읽는다', () {
      final ReportQueueSummary item = reportQueueFromJson(<String, dynamic>{
        'items': <Object?>[
          <String, dynamic>{
            'member_id': 'm1',
            'sessions_booked': -1,
            'sessions_done': 'two',
            'week_completion': <Object?>[50, 'x', 70.4],
          },
        ],
      }).single;
      expect(item.sessionsBooked, 0);
      expect(item.sessionsDone, 0);
      // 숫자가 아닌 칸은 null 로 자리를 지킨다 — 요일이 당겨지지 않는다.
      expect(item.weekCompletion, <int?>[50, null, 70]);
    });
  });

  group('DioReportRepository.watchQueue', () {
    late _MockDio dio;
    late DioReportRepository repo;
    final List<TrainerClient> roster = <TrainerClient>[
      for (int i = 0; i < 12; i++) makeClient(id: 'm$i', name: '회원$i'),
    ];

    setUpAll(() => registerFallbackValue(<String, String>{}));

    setUp(() {
      dio = _MockDio();
      repo = DioReportRepository(dio);
    });

    void answer(Future<Response<Map<String, dynamic>>> Function() reply) {
      when(
        () => dio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) => reply());
    }

    test('회원이 몇 명이든 요약 경로 하나만 부른다', () async {
      answer(
        () async => _ok(<String, dynamic>{
          'week_start': '2026-08-10',
          'items': <Object?>[for (final TrainerClient c in roster) _item(c.id)],
        }),
      );

      final List<ReportQueueSummary> items = await repo
          .watchQueue(clients: roster, weekStart: DateTime(2026, 8, 10))
          .first;

      expect(items, hasLength(roster.length));
      final List<dynamic> paths = verify(
        () => dio.get<Map<String, dynamic>>(
          captureAny(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).captured;
      expect(paths, <String>[_path]);
    });

    test('주는 월요일 YYYY-MM-DD 로 보낸다', () async {
      answer(() async => _ok(<String, dynamic>{'items': <Object?>[]}));

      // 목요일을 넘겨도 그 주 월요일을 묻는다.
      await repo
          .watchQueue(clients: roster, weekStart: DateTime(2026, 8, 13))
          .first;

      final List<dynamic> captured = verify(
        () => dio.get<Map<String, dynamic>>(
          _path,
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, <String, String>{'week_start': '2026-08-10'});
    });

    test('서버 오류를 빈 큐로 삼키지 않는다', () async {
      answer(() async => throw _httpError(500));

      await expectLater(
        repo
            .watchQueue(clients: roster, weekStart: DateTime(2026, 8, 10))
            .first,
        throwsA(isA<AppError>()),
      );
    });

    test('빈 응답은 서버 오류다', () async {
      answer(() async => _ok(null));

      await expectLater(
        repo
            .watchQueue(clients: roster, weekStart: DateTime(2026, 8, 10))
            .first,
        throwsA(isA<ServerError>()),
      );
    });
  });

  group('weeklyReportFromJson — calorie_baseline', () {
    final TrainerClient client = makeClient(id: 'm1', name: '김민수');

    test('직전 4주 평균을 그대로 싣는다', () {
      final WeeklyReport report = weeklyReportFromJson(<String, dynamic>{
        'week_start': '2026-08-10',
        'calorie_baseline': 1875.5,
      }, client);
      expect(report.calorieBaseline, 1875.5);
    });

    test('정수로 와도 읽는다', () {
      final WeeklyReport report = weeklyReportFromJson(<String, dynamic>{
        'week_start': '2026-08-10',
        'calorie_baseline': 2000,
      }, client);
      expect(report.calorieBaseline, 2000);
    });

    test('없거나 null 이면 null 이다 — 비교 줄을 그리지 않는다', () {
      expect(
        weeklyReportFromJson(<String, dynamic>{
          'week_start': '2026-08-10',
        }, client).calorieBaseline,
        isNull,
      );
      expect(
        weeklyReportFromJson(<String, dynamic>{
          'week_start': '2026-08-10',
          'calorie_baseline': null,
        }, client).calorieBaseline,
        isNull,
      );
    });
  });
}
