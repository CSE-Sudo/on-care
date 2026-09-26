import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';

import '../../helpers/client_factory.dart';

class _MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> _ok(Map<String, dynamic> body, String path) =>
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

void main() {
  late _MockDio dio;
  late DioReportRepository repo;
  final client = makeClient(id: 'm1', name: '김민수');
  final weekStart = DateTime(2026, 8, 3);
  const path = '/trainer/clients/m1/report';

  setUpAll(() {
    registerFallbackValue(<String, String>{});
    registerFallbackValue(FormData());
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = _MockDio();
    repo = DioReportRepository(dio);
  });

  test('sends the week as a YYYY-MM-DD query parameter', () async {
    when(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok(<String, dynamic>{'week_start': '2026-08-03'}, path),
    );

    await repo.watch(client: client, weekStart: weekStart).first;

    final captured =
        verify(
              () => dio.get<Map<String, dynamic>>(
                path,
                queryParameters: captureAny(named: 'queryParameters'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(captured['week_start'], '2026-08-03');
  });

  test('parses the aggregated figures', () async {
    when(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok(<String, dynamic>{
        'week_start': '2026-08-03',
        'sessions_booked': 3,
        'sessions_done': 2,
        'completion_avg': 74,
        'sodium_over_days': 2,
        'sodium_avg': 2150,
      }, path),
    );

    final report = await repo.watch(client: client, weekStart: weekStart).first;

    expect(report.sessionsBooked, 3);
    expect(report.sessionsDone, 2);
    expect(report.completionAvg, 74);
    expect(report.sodiumOverDays, 2);
    expect(report.sodiumAvg, 2150);
    expect(report.attendanceRate, 67);
    // The chart series stay on the client — the report endpoint doesn't
    // repeat what the roster already delivered.
    expect(report.client.weekCompletion, client.weekCompletion);
  });

  test('탄·단·지 계열도 같은 응답에서 읽는다 (#1177)', () async {
    // 비교 그래프가 칼로리를 탄·단·지로 쌓는다. 백엔드는 이미 같은 응답에
    // 실어 보내는데 앱이 버리고 있었다.
    when(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok(<String, dynamic>{
        'week_start': '2026-08-03',
        'sessions_booked': 0,
        'sessions_done': 0,
        'completion_avg': 80,
        'sodium_over_days': 0,
        'sodium_avg': 1500,
        'calories_week': <int>[1800, 1900, 0, 0, 0, 0, 0],
        'carbs_week': <double>[200.5, 210, 0, 0, 0, 0, 0],
        'protein_week': <double>[88.4, 90, 0, 0, 0, 0, 0],
        'fat_week': <double>[62.1, 60, 0, 0, 0, 0, 0],
      }, path),
    );

    final report = await repo.watch(client: client, weekStart: weekStart).first;

    expect(report.caloriesWeek.take(2), <int>[1800, 1900]);
    expect(report.carbsWeek.take(2), <double>[200.5, 210]);
    expect(report.proteinWeek.take(2), <double>[88.4, 90]);
    expect(report.fatWeek.take(2), <double>[62.1, 60]);
  });

  test('a null completion stays null rather than collapsing to 0%', () async {
    when(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok(<String, dynamic>{
        'week_start': '2026-08-03',
        'completion_avg': null,
        'sodium_avg': null,
      }, path),
    );

    final report = await repo.watch(client: client, weekStart: weekStart).first;

    expect(report.completionAvg, isNull);
    expect(report.sodiumAvg, isNull);
  });

  test('JSON numbers that decode as double survive (web)', () async {
    // On web every JSON number is a double; `as int` would throw.
    when(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok(<String, dynamic>{
        'week_start': '2026-08-03',
        'sessions_booked': 3.0,
        'sodium_avg': 2150.0,
      }, path),
    );

    final report = await repo.watch(client: client, weekStart: weekStart).first;

    expect(report.sessionsBooked, 3);
    expect(report.sodiumAvg, 2150);
  });

  test('an HTTP failure surfaces as a typed AppError', () async {
    when(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenThrow(_httpError(404, path));

    expect(
      () => repo.watch(client: client, weekStart: weekStart).first,
      throwsA(isA<NotFoundError>()),
    );
  });

  test('send posts the week and the body the trainer saw', () async {
    const sendPath = '/trainer/clients/m1/report/send';
    when(
      () => dio.post<Map<String, dynamic>>(sendPath, data: any(named: 'data')),
    ).thenAnswer((_) async => _ok(<String, dynamic>{}, sendPath));

    await repo.send(
      clientId: 'm1',
      weekStart: weekStart,
      message: '이번 주 잘하셨어요',
    );

    final body =
        verify(
              () => dio.post<Map<String, dynamic>>(
                sendPath,
                data: captureAny(named: 'data'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(body['week_start'], '2026-08-03');
    // The sent text must be what was previewed, not a server rebuild.
    expect(body['message'], '이번 주 잘하셨어요');
  });

  test('a failed send throws instead of reporting success', () async {
    const sendPath = '/trainer/clients/m1/report/send';
    when(
      () => dio.post<Map<String, dynamic>>(sendPath, data: any(named: 'data')),
    ).thenThrow(_httpError(500, sendPath));

    expect(
      () => repo.send(clientId: 'm1', weekStart: weekStart, message: 'x'),
      throwsA(isA<ServerError>()),
    );
  });

  test(
    'sendPdf posts the week, message and pdf bytes as multipart (#1378)',
    () async {
      const sendPdfPath = '/trainer/clients/m1/report/send-pdf';
      when(
        () => dio.post<Map<String, Object?>>(
          sendPdfPath,
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _ok(<String, dynamic>{}, sendPdfPath));

      await repo.sendPdf(
        clientId: 'm1',
        weekStart: weekStart,
        bytes: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
        fileName: '김민수_2026-08-03_주간리포트.pdf',
        message: '이번 주 잘하셨어요',
      );

      final captured =
          verify(
                () => dio.post<Map<String, Object?>>(
                  sendPdfPath,
                  data: captureAny(named: 'data'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as FormData;
      final fields = <String, String>{
        for (final entry in captured.fields) entry.key: entry.value,
      };
      expect(fields['week_start'], '2026-08-03');
      // 전송되는 것은 화면에서 트레이너가 본 문구 그대로다.
      expect(fields['message'], '이번 주 잘하셨어요');
      expect(captured.files.single.value.filename, '김민수_2026-08-03_주간리포트.pdf');
    },
  );

  test('a failed sendPdf throws instead of reporting success', () async {
    const sendPdfPath = '/trainer/clients/m1/report/send-pdf';
    when(
      () => dio.post<Map<String, Object?>>(
        sendPdfPath,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(_httpError(500, sendPdfPath));

    expect(
      () => repo.sendPdf(
        clientId: 'm1',
        weekStart: weekStart,
        bytes: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
        fileName: 'report.pdf',
        message: 'x',
      ),
      throwsA(isA<ServerError>()),
    );
  });
}
