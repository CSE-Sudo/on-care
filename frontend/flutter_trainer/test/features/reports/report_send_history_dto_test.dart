/// 리포트 전송 이력의 응답 해석과 실서버 요청. (#2288)
///
/// 작업대의 `전송 완료` 열은 이제 `GET /trainer/reports/sent` 가 세운다. 이
/// 파일이 지키는 것:
///  * 응답의 줄이 [ReportSendRecord] 로 그대로 옮겨진다 — 시각은 KST 벽시계로.
///  * 누구에게 언제 갔는지 모르는 줄은 버린다(없는 전송을 그리지 않는다).
///  * 보고 있는 주를 그대로 묻고, 실패는 삼키지 않고 [AppError] 로 올린다 —
///    빈 목록으로 삼키면 보낸 회원이 미전송으로 서서 다시 보내게 된다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/trainer/reports/sent';

Map<String, dynamic> _send({
  String memberId = 'm1',
  String? week = '2026-09-14',
  String? sentAt = '2026-09-15T01:30:00+00:00',
  Object? message = '이번 주 리포트입니다.',
  Object? read = false,
  Object? hasPdf = true,
  Object? sendCount = 1,
}) => <String, dynamic>{
  'member_id': memberId,
  'week_start': ?week,
  'sent_at': ?sentAt,
  'message': message,
  'read': read,
  'has_pdf': hasPdf,
  'send_count': sendCount,
};

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

void main() {
  final DateTime week = DateTime(2026, 9, 14);

  group('reportSendsFromJson', () {
    test('한 줄이 기록 하나로 그대로 옮겨진다', () {
      final List<ReportSendRecord> records = reportSendsFromJson(
        <String, dynamic>{
          'week_start': '2026-09-14',
          'sends': <Object?>[
            _send(read: true, sendCount: 2, message: '다시 보낸 글'),
          ],
        },
        week,
      );

      final ReportSendRecord r = records.single;
      expect(r.clientId, 'm1');
      expect(r.weekStart, DateTime(2026, 9, 14));
      expect(r.message, '다시 보낸 글');
      expect(r.read, isTrue);
      expect(r.sendCount, 2);
    });

    test('서버의 UTC 시각을 KST 벽시계로 옮긴다', () {
      final ReportSendRecord r = reportSendsFromJson(<String, dynamic>{
        'sends': <Object?>[_send(sentAt: '2026-09-15T14:30:00+00:00')],
      }, week).single;

      // UTC 14:30 은 서울 다음 날 23:30 이다.
      expect(r.sentAt, DateTime(2026, 9, 15, 23, 30));
      expect(r.sentAt.isUtc, isFalse);
    });

    test('오프셋 없는 시각은 이미 벽시계로 보고 그대로 둔다', () {
      final ReportSendRecord r = reportSendsFromJson(<String, dynamic>{
        'sends': <Object?>[_send(sentAt: '2026-09-15T09:05:00')],
      }, week).single;

      expect(r.sentAt, DateTime(2026, 9, 15, 9, 5));
    });

    test('줄에 주가 없으면 응답의 주, 그것도 없으면 요청한 주의 월요일이다', () {
      final ReportSendRecord fromEnvelope = reportSendsFromJson(
        <String, dynamic>{
          'week_start': '2026-09-07',
          'sends': <Object?>[_send(week: null)],
        },
        week,
      ).single;
      expect(fromEnvelope.weekStart, DateTime(2026, 9, 7));

      final ReportSendRecord fromRequest = reportSendsFromJson(
        <String, dynamic>{
          'sends': <Object?>[_send(week: null)],
        },
        DateTime(2026, 9, 17), // 목요일
      ).single;
      expect(fromRequest.weekStart, DateTime(2026, 9, 14));
    });

    test('주 중간 날짜로 와도 그 주 월요일로 접힌다', () {
      final ReportSendRecord r = reportSendsFromJson(<String, dynamic>{
        'sends': <Object?>[_send(week: '2026-09-16')],
      }, week).single;

      expect(r.weekStart, DateTime(2026, 9, 14));
    });

    test('회원 id·보낸 시각을 읽지 못한 줄은 버린다', () {
      final List<ReportSendRecord> records = reportSendsFromJson(
        <String, dynamic>{
          'sends': <Object?>[
            _send(memberId: ''),
            _send(sentAt: null),
            _send(sentAt: '어제'),
            <String, dynamic>{'sent_at': '2026-09-15T01:30:00+00:00'},
            'm1',
            null,
            _send(memberId: 'ok'),
          ],
        },
        week,
      );

      expect(records.map((r) => r.clientId), <String>['ok']);
    });

    test('모양이 다른 값은 안전한 기본값으로 읽는다', () {
      final ReportSendRecord r = reportSendsFromJson(<String, dynamic>{
        'sends': <Object?>[_send(message: 3, read: 'yes', sendCount: 0)],
      }, week).single;

      expect(r.message, '');
      expect(r.read, isFalse);
      expect(r.sendCount, 1);
    });

    test('sends 가 목록이 아니면 빈 목록이다', () {
      expect(
        reportSendsFromJson(<String, dynamic>{'sends': null}, week),
        isEmpty,
      );
      expect(
        reportSendsFromJson(<String, dynamic>{'sends': '없음'}, week),
        isEmpty,
      );
      expect(reportSendsFromJson(<String, dynamic>{}, week), isEmpty);
    });

    test('여러 회원의 줄이 순서대로 나온다', () {
      final List<ReportSendRecord> records = reportSendsFromJson(
        <String, dynamic>{
          'sends': <Object?>[_send(memberId: 'b'), _send(memberId: 'a')],
        },
        week,
      );

      expect(records.map((r) => r.clientId), <String>['b', 'a']);
    });
  });

  group('DioReportRepository.sentReports', () {
    late _MockDio dio;
    late DioReportRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioReportRepository(dio);
    });

    void stub(Future<Response<Map<String, dynamic>>> Function() answer) {
      when(
        () => dio.get<Map<String, dynamic>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) => answer());
    }

    test('보고 있는 주를 그대로 묻는다', () async {
      stub(
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'sends': <Object?>[],
        }),
      );

      await repo.sentReports(weekStart: week);

      final Map<String, dynamic> query =
          verify(
                () => dio.get<Map<String, dynamic>>(
                  _path,
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(query, <String, String>{'week_start': '2026-09-14'});
    });

    test('응답의 기록을 돌려준다', () async {
      stub(
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'sends': <Object?>[_send(), _send(memberId: 'm2', read: true)],
        }),
      );

      final List<ReportSendRecord> records = await repo.sentReports(
        weekStart: week,
      );

      expect(records.map((r) => r.clientId), <String>['m1', 'm2']);
      expect(records.last.read, isTrue);
    });

    test('보낸 적이 없는 주는 빈 목록이다', () async {
      stub(
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'sends': <Object?>[],
        }),
      );

      expect(await repo.sentReports(weekStart: week), isEmpty);
    });

    test('서버 오류는 삼키지 않고 AppError 로 올린다', () async {
      stub(() async => throw _httpError(500));

      await expectLater(
        repo.sentReports(weekStart: week),
        throwsA(isA<AppError>()),
      );
    });

    test('권한 거부(403)도 빈 목록이 아니라 오류다', () async {
      stub(() async => throw _httpError(403));

      await expectLater(
        repo.sentReports(weekStart: week),
        throwsA(isA<AppError>()),
      );
    });

    test('본문이 비어 오면 오류다', () async {
      stub(() async => _ok(null));

      await expectLater(
        repo.sentReports(weekStart: week),
        throwsA(isA<AppError>()),
      );
    });
  });
}
