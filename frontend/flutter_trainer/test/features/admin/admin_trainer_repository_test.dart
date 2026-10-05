import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/admin/data/repositories/admin_trainer_repository.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_report.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(String path, T data) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: data,
);

Map<String, Object?> _reportJson({String status = 'open'}) => <String, Object?>{
  'id': 'report-1',
  'trainer_id': 'trainer-1',
  'trainer_name': '김코치',
  'trainer_email': 'coach@oncare.com',
  'trainer_is_active': true,
  'reason': 'impersonation',
  'memo': '',
  'status': status,
  'created_at': '2026-10-01T01:00:00Z',
  'resolved_at': null,
};

/// 운영 화면 저장소의 서버 경로 계약 (#3008).
void main() {
  late _MockDio dio;
  late DioAdminTrainerRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioAdminTrainerRepository(dio);
  });

  test('신고 목록은 status 쿼리로 거른다', () async {
    when(
      () => dio.get<List<dynamic>>(
        '/admin/trainer-reports',
        queryParameters: <String, String>{'status': 'closed'},
      ),
    ).thenAnswer(
      (_) async => _ok<List<dynamic>>('/admin/trainer-reports', <dynamic>[
        _reportJson(status: 'resolved'),
        'not a row',
      ]),
    );

    final List<AdminTrainerReport> rows = await repo.fetchReports(
      AdminReportFilter.closed,
    );

    expect(rows.single.status, AdminReportStatus.resolved);
  });

  test('신고 처리는 outcome 을 본문으로 보낸다', () async {
    const String path = '/admin/trainer-reports/report-1/close';
    when(
      () => dio.post<Map<String, Object?>>(
        path,
        data: <String, Object?>{'outcome': 'dismissed'},
      ),
    ).thenAnswer(
      (_) async =>
          _ok<Map<String, Object?>>(path, _reportJson(status: 'dismissed')),
    );

    final AdminTrainerReport r = await repo.closeReport(
      'report-1',
      AdminReportOutcome.dismissed,
    );

    expect(r.status, AdminReportStatus.dismissed);
  });

  test('트레이너 검색은 다듬은 q 와 state 를 보내고 빈 q 는 뺀다', () async {
    when(
      () => dio.get<List<dynamic>>(
        '/admin/trainers',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok<List<dynamic>>('/admin/trainers', <dynamic>[]),
    );

    await repo.fetchTrainers(query: ' 김코치 ', state: AdminTrainerState.active);
    await repo.fetchTrainers(query: '   ');

    final List<dynamic> sent = verify(
      () => dio.get<List<dynamic>>(
        '/admin/trainers',
        queryParameters: captureAny(named: 'queryParameters'),
      ),
    ).captured;
    expect(sent, <Object?>[
      <String, String>{'q': '김코치', 'state': 'active'},
      <String, String>{'state': 'all'},
    ]);
  });

  test('정지·해제 경로', () async {
    when(
      () => dio.post<Map<String, Object?>>('/admin/users/trainer-1/suspend'),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(
        '/admin/users/trainer-1/suspend',
        <String, Object?>{
          'user_id': 'trainer-1',
          'is_active': false,
          'released_clients': 1,
        },
      ),
    );
    when(
      () => dio.post<Map<String, Object?>>('/admin/users/trainer-1/unsuspend'),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(
        '/admin/users/trainer-1/unsuspend',
        <String, Object?>{'user_id': 'trainer-1', 'is_active': true},
      ),
    );

    expect((await repo.suspend('trainer-1')).releasedClients, 1);
    expect((await repo.unsuspend('trainer-1')).isActive, isTrue);
  });

  test('서버 오류는 AppError 로 바꾼다', () async {
    when(
      () => dio.get<List<dynamic>>(
        '/admin/trainer-reports',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/admin/trainer-reports'),
        response: Response<Object?>(
          requestOptions: RequestOptions(path: '/admin/trainer-reports'),
          statusCode: 403,
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    expect(
      () => repo.fetchReports(AdminReportFilter.open),
      throwsA(isA<AppError>()),
    );
  });
}
