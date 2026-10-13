import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/data/repositories/dio_trainer_report_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_trainer_report_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/trainer_report_repository.dart';

/// 요청을 적어 두고 정해 둔 상태 코드·본문을 돌려주는 어댑터.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.status, this.body});

  final int status;
  final Object? body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioTrainerReportRepository _repo(_StubAdapter adapter) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
    ..httpClientAdapter = adapter;
  return DioTrainerReportRepository(dio);
}

const Map<String, Object?> _created = <String, Object?>{
  'id': 'report-1',
  'status': 'open',
  'created_at': '2026-10-03T09:00:00Z',
};

void main() {
  group('사유 계약값 (#3008)', () {
    test('서버 ReportReason 과 같은 값이다', () {
      expect(
        TrainerReportReason.values.map((TrainerReportReason r) => r.wire),
        <String>['impersonation', 'inappropriate_message', 'other'],
      );
    });

    test('기타만 메모가 있어야 한다', () {
      expect(TrainerReportReason.other.needsMemo, isTrue);
      expect(TrainerReportReason.impersonation.needsMemo, isFalse);
      expect(TrainerReportReason.inappropriateMessage.needsMemo, isFalse);
    });

    test('메모 상한은 서버 TEXT_LINE_MAX 와 같은 200 이다', () {
      expect(kTrainerReportMemoMax, 200);
    });
  });

  group('DioTrainerReportRepository', () {
    test('POST /trainers/{id}/reports 로 사유와 다듬은 메모를 보낸다', () async {
      final _StubAdapter adapter = _StubAdapter(status: 201, body: _created);

      await _repo(adapter).report(
        'trainer-1',
        reason: TrainerReportReason.inappropriateMessage,
        memo: '  밤늦게 광고 메시지를 보냈어요  ',
      );

      expect(adapter.requests, hasLength(1));
      final RequestOptions sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/trainers/trainer-1/reports');
      expect(sent.data, <String, Object?>{
        'reason': 'inappropriate_message',
        'memo': '밤늦게 광고 메시지를 보냈어요',
      });
    });

    test('메모 없이도 보낼 수 있다 — 빈 문자열로 간다', () async {
      final _StubAdapter adapter = _StubAdapter(status: 201, body: _created);

      await _repo(
        adapter,
      ).report('trainer-1', reason: TrainerReportReason.impersonation);

      expect(adapter.requests.single.data, <String, Object?>{
        'reason': 'impersonation',
        'memo': '',
      });
    });

    test('트레이너 id 는 경로 조각으로 인코딩한다', () async {
      final _StubAdapter adapter = _StubAdapter(status: 201, body: _created);

      await _repo(
        adapter,
      ).report('a/b c', reason: TrainerReportReason.impersonation);

      expect(adapter.requests.single.path, '/trainers/a%2Fb%20c/reports');
    });

    test('409 report_already_open 은 TrainerReportAlreadyOpen 이다', () {
      final DioTrainerReportRepository repository = _repo(
        _StubAdapter(
          status: 409,
          body: <String, Object?>{
            'detail': <String, Object?>{
              'code': 'report_already_open',
              'message': '이미 접수된 신고가 처리 중입니다.',
            },
          },
        ),
      );

      expect(
        () => repository.report(
          'trainer-1',
          reason: TrainerReportReason.impersonation,
        ),
        throwsA(isA<TrainerReportAlreadyOpen>()),
      );
    });

    test('코드가 다른 409 는 그대로 DioException 으로 올린다', () {
      final DioTrainerReportRepository repository = _repo(
        _StubAdapter(status: 409, body: <String, Object?>{'detail': '다른 충돌'}),
      );

      expect(
        () => repository.report(
          'trainer-1',
          reason: TrainerReportReason.impersonation,
        ),
        throwsA(isA<DioException>()),
      );
    });

    test('404 는 DioException 으로 올린다', () {
      final DioTrainerReportRepository repository = _repo(
        _StubAdapter(
          status: 404,
          body: <String, Object?>{'detail': '트레이너를 찾을 수 없어요.'},
        ),
      );

      expect(
        () => repository.report(
          'missing',
          reason: TrainerReportReason.impersonation,
        ),
        throwsA(
          isA<DioException>().having(
            (DioException e) => e.response?.statusCode,
            'status',
            404,
          ),
        ),
      );
    });
  });

  group('MockTrainerReportRepository (데모)', () {
    test('접수한 신고를 메모리에 남긴다', () async {
      final MockTrainerReportRepository repository =
          MockTrainerReportRepository();

      await repository.report(
        'trainer-kim',
        reason: TrainerReportReason.other,
        memo: '  소속이 달라요 ',
      );

      expect(repository.openReports, hasLength(1));
      expect(
        repository.openReports['trainer-kim']?.reason,
        TrainerReportReason.other,
      );
      expect(repository.openReports['trainer-kim']?.memo, '소속이 달라요');
    });

    test('처리 전에 같은 트레이너를 다시 신고하면 거절한다', () async {
      final MockTrainerReportRepository repository =
          MockTrainerReportRepository();
      await repository.report(
        'trainer-kim',
        reason: TrainerReportReason.impersonation,
      );

      expect(
        () => repository.report(
          'trainer-kim',
          reason: TrainerReportReason.inappropriateMessage,
        ),
        throwsA(isA<TrainerReportAlreadyOpen>()),
      );
      expect(repository.openReports, hasLength(1));
    });

    test('다른 트레이너는 따로 신고할 수 있다', () async {
      final MockTrainerReportRepository repository =
          MockTrainerReportRepository();
      await repository.report(
        'trainer-kim',
        reason: TrainerReportReason.impersonation,
      );
      await repository.report(
        'trainer-lee',
        reason: TrainerReportReason.impersonation,
      );

      expect(repository.openReports.keys, <String>[
        'trainer-kim',
        'trainer-lee',
      ]);
    });

    test('기타 사유에 메모가 비면 서버처럼 거절한다', () {
      final MockTrainerReportRepository repository =
          MockTrainerReportRepository();

      expect(
        () => repository.report(
          'trainer-kim',
          reason: TrainerReportReason.other,
          memo: '   ',
        ),
        throwsArgumentError,
      );
      expect(repository.openReports, isEmpty);
    });
  });
}
