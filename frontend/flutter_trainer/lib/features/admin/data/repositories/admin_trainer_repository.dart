import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/features/admin/data/dtos/admin_trainer_dtos.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';

/// 반려 사유 최대 길이 — 서버 `TrainerRejectIn.reason` 의 `max_length` 와 같다.
const int kTrainerRejectReasonMaxLength = 300;

/// 운영 화면의 트레이너 승인·반려·계정 정지 (#3008·#3009).
///
/// 서버 `/admin/*` 경로를 그대로 부른다. 권한은 서버가 `RequireAdmin` 으로 따로
/// 확인한다 — 이 화면이 운영자에게만 보이는 것은 편의일 뿐 차단이 아니다.
///
/// 데모 구현은 없다. 데모 프로필은 운영자가 아니라 사이드바에 메뉴가 없고, 주소로
/// 열어도 화면이 찾을 수 없음 안내로 끝난다.
abstract interface class AdminTrainerRepository {
  /// [filter] 상태의 트레이너. 서버 순서(가입 순)를 그대로 둔다.
  Future<List<AdminTrainer>> fetch(AdminTrainerFilter filter);

  /// 승인한다. 이미 승인이면 그대로다.
  Future<AdminTrainer> approve(String trainerId);

  /// 반려한다. [reason] 은 트레이너 웹에 그대로 보인다(빈 값 가능).
  Future<AdminTrainer> reject(String trainerId, {String reason = ''});

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
  Future<List<AdminTrainer>> fetch(AdminTrainerFilter filter) async {
    try {
      final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
        '/admin/trainers',
        queryParameters: <String, String>{'status': filter.wire},
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
  Future<AdminTrainer> approve(String trainerId) =>
      _decide('/admin/trainers/$trainerId/approve');

  @override
  Future<AdminTrainer> reject(String trainerId, {String reason = ''}) =>
      _decide(
        '/admin/trainers/$trainerId/reject',
        body: <String, Object?>{'reason': reason.trim()},
      );

  Future<AdminTrainer> _decide(String path, {Object? body}) async {
    try {
      final Response<Map<String, Object?>> res = await _dio
          .post<Map<String, Object?>>(path, data: body);
      final Map<String, Object?>? data = res.data;
      if (data == null) {
        throw const ServerError(message: 'empty admin trainer response');
      }
      return adminTrainerFromJson(data);
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

/// 운영 화면의 상태 칩. 기본은 처리할 것이 있는 승인 대기다.
final adminTrainerFilterProvider =
    StateProvider.autoDispose<AdminTrainerFilter>(
      (ref) => AdminTrainerFilter.pending,
      name: 'adminTrainerFilter',
    );

/// 고른 칩의 트레이너 목록. 처리한 뒤에는 화면이 다시 읽는다.
final adminTrainersProvider = FutureProvider.autoDispose<List<AdminTrainer>>((
  ref,
) {
  final AdminTrainerFilter filter = ref.watch(adminTrainerFilterProvider);
  return ref.watch(adminTrainerRepositoryProvider).fetch(filter);
}, name: 'adminTrainers');
