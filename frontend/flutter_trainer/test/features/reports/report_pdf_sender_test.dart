/// 리포트 PDF 전송의 재시도 열쇠와 대기 한도. (#2773)
///
/// 예전에는 회원·주만으로 요청 id 를 골라, 첫 전송이 응답 대기 중에 끊긴 뒤
/// (서버에는 저장됨) 문구를 고쳐 다시 보내면 같은 id·다른 본문이라 409 가
/// 새로고침 전까지 반복됐다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_sender.dart';

/// 보낸 요청을 모으고, [failures] 에 쌓인 실패를 차례로 낸다.
class _PdfServer implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  /// 다음 요청들이 낼 실패. 비면 201 이다.
  final List<DioExceptionType> failures = <DioExceptionType>[];

  /// 다음 요청이 받을 상태 코드(실패가 없을 때).
  int status = 201;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failures.isNotEmpty) {
      throw DioException(requestOptions: options, type: failures.removeAt(0));
    }
    return ResponseBody.fromString(
      '{}',
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _field(RequestOptions options, String name) => (options.data as FormData)
    .fields
    .firstWhere((MapEntry<String, String> f) => f.key == name)
    .value;

void main() {
  final DateTime week = DateTime(2026, 8, 10);
  late _PdfServer server;
  late ReportPdfSender sender;

  setUp(() {
    server = _PdfServer();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://api.test'))
      ..httpClientAdapter = server;
    sender = ReportPdfSender(dio);
  });

  Future<void> send(String message) => sender.send(
    clientId: 'm1',
    weekStart: week,
    bytes: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
    fileName: 'weekly.pdf',
    message: message,
  );

  Future<void> sendFailing(String message) async {
    await expectLater(send(message), throwsA(isA<DioException>()));
  }

  String requestIdAt(int i) => _field(server.requests[i], 'client_request_id');

  group('요청 id', () {
    test('같은 문구 재시도는 같은 id 를 쓴다 — 서버가 중복 없이 처음 메시지를 돌려준다', () async {
      server.failures.add(DioExceptionType.receiveTimeout);
      await sendFailing('이번 주 리포트');
      await send('이번 주 리포트');

      expect(server.requests, hasLength(2));
      expect(requestIdAt(0), requestIdAt(1));
    });

    test('문구를 고치면 새 id 로 보낸다 — 409 가 반복되지 않는다', () async {
      server.failures.add(DioExceptionType.receiveTimeout);
      await sendFailing('처음 글');
      await send('고친 글');

      expect(requestIdAt(0), isNot(requestIdAt(1)));
      expect(_field(server.requests[1], 'message'), '고친 글');
    });

    test('고쳤다가 처음 문구로 되돌리면 처음 id 를 다시 쓴다', () async {
      server.failures
        ..add(DioExceptionType.receiveTimeout)
        ..add(DioExceptionType.receiveTimeout);
      await sendFailing('처음 글');
      await sendFailing('고친 글');
      await send('처음 글');

      expect(requestIdAt(2), requestIdAt(0));
      expect(requestIdAt(1), isNot(requestIdAt(0)));
    });

    test('앞뒤 공백만 다른 문구는 같은 전송이다 — 서버도 걷어서 견준다', () async {
      server.failures.add(DioExceptionType.connectionError);
      await sendFailing('이번 주 리포트');
      await send('  이번 주 리포트\n');

      expect(requestIdAt(0), requestIdAt(1));
    });

    test('성공하면 열쇠를 지워 다음 전송은 새 id 다', () async {
      await send('이번 주 리포트');
      expect(
        sender.pendingRequestId(
          clientId: 'm1',
          weekStart: week,
          message: '이번 주 리포트',
        ),
        isNull,
      );
      await send('이번 주 리포트');

      expect(requestIdAt(0), isNot(requestIdAt(1)));
    });

    test('실패하면 그 문구의 id 를 남겨 둔다', () async {
      server.failures.add(DioExceptionType.sendTimeout);
      await sendFailing('이번 주 리포트');

      expect(
        sender.pendingRequestId(
          clientId: 'm1',
          weekStart: week,
          message: '이번 주 리포트',
        ),
        requestIdAt(0),
      );
    });

    test('409 도 실패로 끝나고 다른 문구는 새 id 다', () async {
      server.status = 409;
      await sendFailing('처음 글');
      server.status = 201;
      await send('고친 글');

      expect(requestIdAt(0), isNot(requestIdAt(1)));
    });

    test('회원·주가 다르면 열쇠가 다르다', () {
      final String base = ReportPdfSender.requestKeyOf(
        clientId: 'm1',
        weekStart: week,
        message: '글',
      );
      expect(
        ReportPdfSender.requestKeyOf(
          clientId: 'm2',
          weekStart: week,
          message: '글',
        ),
        isNot(base),
      );
      expect(
        ReportPdfSender.requestKeyOf(
          clientId: 'm1',
          weekStart: week.subtract(const Duration(days: 7)),
          message: '글',
        ),
        isNot(base),
      );
    });
  });

  test('업로드와 응답 대기 모두 넉넉히 기다린다', () async {
    await send('이번 주 리포트');

    final RequestOptions options = server.requests.single;
    expect(options.sendTimeout, reportPdfTimeout);
    expect(options.receiveTimeout, reportPdfTimeout);
    expect(reportPdfTimeout, greaterThanOrEqualTo(const Duration(minutes: 1)));
  });

  test('보내는 칸 — 주·문구·요청 id·PDF', () async {
    await send('이번 주 리포트');

    final RequestOptions options = server.requests.single;
    expect(options.path, '/trainer/clients/m1/report/send-pdf');
    expect(_field(options, 'week_start'), '2026-08-10');
    expect(_field(options, 'message'), '이번 주 리포트');
    expect(requestIdAt(0), isNotEmpty);
    expect((options.data as FormData).files.single.key, 'pdf');
  });
}
