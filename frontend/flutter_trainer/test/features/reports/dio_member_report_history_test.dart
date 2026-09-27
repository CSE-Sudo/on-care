/// 회원별 지난 리포트 — 실서버 저장소와 응답 변환. (#2393, #2394)
///
/// `GET /trainer/clients/{member_id}/reports/sent?limit=&before=` 가 이 화면의
/// 원본이다. 이 파일이 지키는 것:
///  * 경로·쿼리(`limit`, 월요일로 맞춘 `before`)를 계약대로 보낸다.
///  * 응답을 줄([MemberReportHistoryItem])과 다음 쪽 커서로 옮긴다 — UTC 시각은
///    KST 벽시계로, 깨진 줄은 버리고, 최신 주부터.
///  * 실패를 빈 이력으로 삼키지 않는다 — `보낸 적 없음` 과 `못 읽음` 은 다르다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';

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

Map<String, dynamic> _send({
  String week = '2026-08-10',
  String sentAt = '2026-08-16T11:30:00Z',
  bool read = true,
  int sendCount = 1,
  String messageId = 'msg-1',
  bool hasPdf = true,
  String preview = '이번 주도 수고 많으셨어요.',
}) => <String, dynamic>{
  'week_start': week,
  'sent_at': sentAt,
  'read': read,
  'send_count': sendCount,
  'message_id': messageId,
  'has_pdf': hasPdf,
  'feedback_preview': preview,
};

void main() {
  group('memberReportHistoryFromJson', () {
    test('한 줄의 모든 값을 옮긴다', () {
      final MemberReportHistoryPage page = memberReportHistoryFromJson(
        <String, dynamic>{
          'member_id': 'm1',
          'sends': <Object?>[
            _send(read: false, sendCount: 2, messageId: 'msg-9'),
          ],
          'next_before': null,
        },
      );
      final MemberReportHistoryItem item = page.items.single;
      expect(item.weekStart, DateTime(2026, 8, 10));
      expect(item.read, isFalse);
      expect(item.sendCount, 2);
      expect(item.messageId, 'msg-9');
      expect(item.hasPdf, isTrue);
      expect(item.feedbackPreview, '이번 주도 수고 많으셨어요.');
      expect(page.hasMore, isFalse);
    });

    test('UTC 전송 시각을 서울 벽시계로 옮긴다', () {
      final MemberReportHistoryItem item = memberReportHistoryFromJson(
        <String, dynamic>{
          'sends': <Object?>[_send(sentAt: '2026-08-16T15:30:00Z')],
        },
      ).items.single;
      // 15:30 UTC = 다음 날 00:30 KST.
      expect(item.sentAt, DateTime(2026, 8, 17, 0, 30));
      expect(item.sentAt.isUtc, isFalse);
    });

    test('다음 쪽 커서를 월요일로 읽는다', () {
      final MemberReportHistoryPage page = memberReportHistoryFromJson(
        <String, dynamic>{
          'sends': <Object?>[_send()],
          'next_before': '2026-08-12',
        },
      );
      expect(page.nextBefore, DateTime(2026, 8, 10));
      expect(page.hasMore, isTrue);
    });

    test('깨진 커서는 더 없는 것으로 읽는다', () {
      expect(
        memberReportHistoryFromJson(<String, dynamic>{
          'sends': <Object?>[],
          'next_before': 'not-a-date',
        }).hasMore,
        isFalse,
      );
      expect(
        memberReportHistoryFromJson(<String, dynamic>{
          'sends': <Object?>[],
          'next_before': 42,
        }).hasMore,
        isFalse,
      );
    });

    test('주나 전송 시각을 읽지 못한 줄은 버린다', () {
      final MemberReportHistoryPage page = memberReportHistoryFromJson(
        <String, dynamic>{
          'sends': <Object?>[
            _send(),
            <String, dynamic>{..._send(week: '2026-08-03'), 'week_start': null},
            <String, dynamic>{..._send(week: '2026-07-27'), 'sent_at': 'x'},
            'not-a-map',
            null,
          ],
        },
      );
      expect(page.items.map((i) => i.weekStart), <DateTime>[
        DateTime(2026, 8, 10),
      ]);
    });

    test('줄을 최신 주부터 다시 세운다', () {
      final MemberReportHistoryPage page = memberReportHistoryFromJson(
        <String, dynamic>{
          'sends': <Object?>[
            _send(week: '2026-07-27'),
            _send(),
            _send(week: '2026-08-03'),
          ],
        },
      );
      expect(page.items.map((i) => i.weekStart), <DateTime>[
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 3),
        DateTime(2026, 7, 27),
      ]);
    });

    test('주 중간 날짜는 그 주 월요일로 접는다', () {
      expect(
        memberReportHistoryFromJson(<String, dynamic>{
          'sends': <Object?>[_send(week: '2026-08-13')],
        }).items.single.weekStart,
        DateTime(2026, 8, 10),
      );
    });

    test('빠진 값은 안전한 기본값이다', () {
      final MemberReportHistoryItem item = memberReportHistoryFromJson(
        <String, dynamic>{
          'sends': <Object?>[
            <String, dynamic>{
              'week_start': '2026-08-10',
              'sent_at': '2026-08-16T11:30:00Z',
            },
          ],
        },
      ).items.single;
      expect(item.read, isFalse);
      expect(item.sendCount, 1);
      expect(item.messageId, isNull);
      expect(item.hasPdf, isFalse);
      expect(item.feedbackPreview, isEmpty);
    });

    test('0 이하·숫자 아닌 전송 횟수는 1 로 읽는다', () {
      for (final Object? count in <Object?>[0, -2, 'two']) {
        final MemberReportHistoryItem item = memberReportHistoryFromJson(
          <String, dynamic>{
            'sends': <Object?>[
              <String, dynamic>{..._send(), 'send_count': count},
            ],
          },
        ).items.single;
        expect(item.sendCount, 1, reason: '$count');
      }
    });

    test('빈 메시지 id 는 없는 것으로 읽는다', () {
      expect(
        memberReportHistoryFromJson(<String, dynamic>{
          'sends': <Object?>[_send(messageId: '')],
        }).items.single.messageId,
        isNull,
      );
    });

    test('sends 가 목록이 아니면 빈 쪽이다', () {
      final MemberReportHistoryPage page = memberReportHistoryFromJson(
        <String, dynamic>{'sends': 'oops'},
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('DioReportRepository.memberReportHistory', () {
    late _MockDio dio;
    late DioReportRepository repo;
    const String path = '/trainer/clients/m1/reports/sent';

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

    Map<String, dynamic> lastQuery() =>
        verify(
              () => dio.get<Map<String, dynamic>>(
                any(),
                queryParameters: captureAny(named: 'queryParameters'),
              ),
            ).captured.last
            as Map<String, dynamic>;

    test('첫 쪽은 기본 쪽 크기로 묻고 before 를 싣지 않는다', () async {
      answer(
        () async => _ok(<String, dynamic>{
          'member_id': 'm1',
          'sends': <Object?>[_send()],
          'next_before': null,
        }, path),
      );

      final MemberReportHistoryPage page = await repo.memberReportHistory(
        clientId: 'm1',
      );

      final List<dynamic> captured = verify(
        () => dio.get<Map<String, dynamic>>(
          path,
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, <String, String>{
        'limit': '$memberReportHistoryPageSize',
      });
      expect(page.items, hasLength(1));
    });

    test('다음 쪽은 before 를 월요일 YYYY-MM-DD 로 보낸다', () async {
      answer(() async => _ok(<String, dynamic>{'sends': <Object?>[]}, path));

      await repo.memberReportHistory(
        clientId: 'm1',
        before: DateTime(2026, 8, 13),
        limit: 5,
      );

      expect(lastQuery(), <String, String>{
        'limit': '5',
        'before': '2026-08-10',
      });
    });

    test('회원 id 는 경로에 맞게 인코딩한다', () async {
      answer(() async => _ok(<String, dynamic>{'sends': <Object?>[]}, path));

      await repo.memberReportHistory(clientId: 'a b/c');

      verify(
        () => dio.get<Map<String, dynamic>>(
          '/trainer/clients/a%20b%2Fc/reports/sent',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);
    });

    test('담당이 아닌 회원(404)은 NotFoundError 로 올린다', () async {
      answer(() async => throw _httpError(404, path));

      await expectLater(
        repo.memberReportHistory(clientId: 'm1'),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('서버 오류를 빈 이력으로 삼키지 않는다', () async {
      answer(() async => throw _httpError(500, path));

      await expectLater(
        repo.memberReportHistory(clientId: 'm1'),
        throwsA(isA<AppError>()),
      );
    });

    test('빈 응답 본문은 ServerError 다', () async {
      answer(() async => _ok(null, path));

      await expectLater(
        repo.memberReportHistory(clientId: 'm1'),
        throwsA(isA<ServerError>()),
      );
    });
  });
}
