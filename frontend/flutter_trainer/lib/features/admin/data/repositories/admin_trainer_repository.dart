import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/features/admin/data/dtos/admin_trainer_dtos.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_report.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';

/// 운영 화면 `신고·계정 관리` 의 서버 경로 (#3008).
///
/// 회원 신고 목록·처리, 트레이너 검색, 계정 정지·해제. 서버 `/admin/*` 경로를
/// 그대로 부른다. 권한은 서버가 `RequireAdmin` 으로 따로 확인한다 — 이 화면이
/// 운영자에게만 보이는 것은 편의일 뿐 차단이 아니다.
///
/// 데모 구현은 없다. 데모 프로필은 운영자가 아니라 사이드바에 메뉴가 없고, 주소로
/// 열어도 화면이 찾을 수 없음 안내로 끝난다.
abstract interface class AdminTrainerRepository {
  /// [filter] 상태의 신고. 서버 순서(최근 순)를 그대로 둔다.
  Future<List<AdminTrainerReport>> fetchReports(AdminReportFilter filter);

  /// 신고를 닫는다 — 조치함 또는 넘김. 계정 상태는 바꾸지 않는다.
  Future<AdminTrainerReport> closeReport(
    String reportId,
    AdminReportOutcome outcome,
  );

  /// 트레이너 목록. [query] 는 이름·이메일 부분 일치(빈 값이면 전체).
  Future<List<AdminTrainer>> fetchTrainers({
    String query = '',
    AdminTrainerState state = AdminTrainerState.all,
  });

  /// 계정을 정지한다 — 로그아웃·담당 해제까지 서버가 한다.
  Future<AdminUserStatus> suspend(String userId);

  /// 정지를 푼다 — 계정만 되살린다.
  Future<AdminUserStatus> unsuspend(String userId);
}

/// 실서버 구현.
class DioAdminTrainerRepository implements AdminTrainerRepository {
  /// Creates the repository on [_dio].
  const DioAdminTrainerRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<AdminTrainerReport>> fetchReports(
    AdminReportFilter filter,
  ) async {
    try {
      final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
        '/admin/trainer-reports',
        queryParameters: <String, String>{'status': filter.wire},
      );
      return (res.data ?? const <dynamic>[])
          .whereType<Map<String, Object?>>()
          .map(adminTrainerReportFromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<AdminTrainerReport> closeReport(
    String reportId,
    AdminReportOutcome outcome,
  ) async {
    try {
      final Response<Map<String, Object?>> res = await _dio
          .post<Map<String, Object?>>(
            '/admin/trainer-reports/$reportId/close',
            data: <String, Object?>{'outcome': outcome.wire},
          );
      final Map<String, Object?>? data = res.data;
      if (data == null) {
        throw const ServerError(message: 'empty admin report response');
      }
      return adminTrainerReportFromJson(data);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<AdminTrainer>> fetchTrainers({
    String query = '',
    AdminTrainerState state = AdminTrainerState.all,
  }) async {
    final String q = query.trim();
    try {
      final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
        '/admin/trainers',
        queryParameters: <String, String>{
          if (q.isNotEmpty) 'q': q,
          'state': state.wire,
        },
      );
      return (res.data ?? const <dynamic>[])
          .whereType<Map<String, Object?>>()
          .map(adminTrainerFromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<AdminUserStatus> suspend(String userId) =>
      _status('/admin/users/$userId/suspend');

  @override
  Future<AdminUserStatus> unsuspend(String userId) =>
      _status('/admin/users/$userId/unsuspend');

  Future<AdminUserStatus> _status(String path) async {
    try {
      final Response<Map<String, Object?>> res = await _dio
          .post<Map<String, Object?>>(path);
      final Map<String, Object?>? data = res.data;
      if (data == null) {
        throw const ServerError(message: 'empty admin user response');
      }
      return adminUserStatusFromJson(data);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

/// 운영 화면 저장소. 계정이 바뀌면 새로 만든다(#2285).
final adminTrainerRepositoryProvider = Provider<AdminTrainerRepository>((ref) {
  ref.watch(accountScopeProvider);
  return DioAdminTrainerRepository(ref.watch(dioProvider));
}, name: 'adminTrainerRepository');

/// 운영 화면의 두 갈래 — 신고와 트레이너.
enum AdminSection {
  /// 회원 신고(기본).
  reports,

  /// 트레이너 찾기·정지.
  trainers,
}

/// 지금 보는 갈래.
final adminSectionProvider = StateProvider.autoDispose<AdminSection>(
  (ref) => AdminSection.reports,
  name: 'adminSection',
);

/// 신고 목록의 상태 칩. 기본은 처리할 것이 있는 처리 전이다.
final adminReportFilterProvider = StateProvider.autoDispose<AdminReportFilter>(
  (ref) => AdminReportFilter.open,
  name: 'adminReportFilter',
);

/// 고른 칩의 신고 목록. 처리한 뒤에는 화면이 다시 읽는다.
final adminReportsProvider =
    FutureProvider.autoDispose<List<AdminTrainerReport>>((ref) {
      final AdminReportFilter filter = ref.watch(adminReportFilterProvider);
      return ref.watch(adminTrainerRepositoryProvider).fetchReports(filter);
    }, name: 'adminReports');

/// 트레이너 목록의 검색어 — 검색창에서 보내기(엔터)를 누를 때 바뀐다.
final adminTrainerQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
  name: 'adminTrainerQuery',
);

/// 트레이너 목록의 상태 칩.
final adminTrainerStateProvider = StateProvider.autoDispose<AdminTrainerState>(
  (ref) => AdminTrainerState.all,
  name: 'adminTrainerState',
);

/// 검색어·상태 칩에 맞는 트레이너 목록.
final adminTrainersProvider = FutureProvider.autoDispose<List<AdminTrainer>>((
  ref,
) {
  final String query = ref.watch(adminTrainerQueryProvider);
  final AdminTrainerState state = ref.watch(adminTrainerStateProvider);
  return ref
      .watch(adminTrainerRepositoryProvider)
      .fetchTrainers(query: query, state: state);
}, name: 'adminTrainers');
