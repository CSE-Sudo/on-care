/// 실서버 리포트가 목표 API 를 더 부르지 않는가. (#2400)
///
/// 편집기에서 `다음 주 목표` 고르기와 `지난 주 목표 달성` 카드가 빠지면서
/// 앱은 `…/report/goals` 를 읽지도(GET) 남기지도(PUT) 않는다. 백엔드
/// 엔드포인트는 그대로 두므로, 앱이 조용히 다시 부르기 시작하면 쓰지 않는 값을
/// 매 리포트마다 한 번씩 더 기다리게 된다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

import '../../helpers/client_factory.dart';

class _MockDio extends Mock implements Dio {}

const String _reportPath = '/trainer/clients/m1/report';
const String _feedbackPath = '/trainer/clients/m1/report/member-feedback';
const String _goalsPath = '/trainer/clients/m1/report/goals';

const Map<String, dynamic> _reportBody = <String, dynamic>{
  'week_start': '2026-09-14',
  'sessions_booked': 2,
  'sessions_done': 1,
  'completion_avg': 32,
};

Response<Map<String, dynamic>> _ok(Map<String, dynamic>? body, String path) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body,
    );

void main() {
  late _MockDio dio;
  late DioReportRepository repo;
  final client = makeClient(id: 'm1', name: '김민수');
  final weekStart = DateTime(2026, 9, 14);

  setUp(() {
    dio = _MockDio();
    repo = DioReportRepository(dio);
    when(
      () => dio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((inv) async {
      final String path = inv.positionalArguments.first as String;
      return _ok(path == _reportPath ? _reportBody : null, path);
    });
  });

  test('리포트를 읽을 때 본문과 회원 피드백만 묻는다', () async {
    await repo.watch(client: client, weekStart: weekStart).first;

    final List<Object?> paths = verify(
      () => dio.get<Map<String, dynamic>>(
        captureAny(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).captured;
    expect(paths, unorderedEquals(<String>[_reportPath, _feedbackPath]));
  });

  test('목표 경로는 읽지 않는다', () async {
    await repo.watch(client: client, weekStart: weekStart).first;

    verifyNever(
      () => dio.get<Map<String, dynamic>>(
        _goalsPath,
        queryParameters: any(named: 'queryParameters'),
      ),
    );
  });

  test('리포트를 읽는 동안 아무것도 남기지 않는다 — 목표 PUT 이 없다', () async {
    await repo.watch(client: client, weekStart: weekStart).first;

    verifyNever(
      () => dio.put<Map<String, dynamic>>(any(), data: any(named: 'data')),
    );
  });

  test('본문만으로 리포트가 선다 — 목표 응답을 기다리지 않는다', () async {
    final WeeklyReport report = await repo
        .watch(client: client, weekStart: weekStart)
        .first;

    expect(report.client.id, 'm1');
    expect(report.sessionsBooked, 2);
    expect(report.sessionsDone, 1);
    expect(report.completionAvg, 32);
  });

  test('회원 피드백이 없어도 리포트는 그대로다', () async {
    final WeeklyReport report = await repo
        .watch(client: client, weekStart: weekStart)
        .first;

    expect(report.memberFeedback, isNull);
  });
}
