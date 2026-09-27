import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';

/// Account-level actions that change credentials.
///
/// Separate from the profile repository because the failure modes are
/// different: a wrong current password is a user error to show inline,
/// not a network error to retry.
abstract interface class TrainerAccountRepository {
  /// Whether this build can actually change the password.
  ///
  /// Demo/mock has no account behind it, so the UI disables the action
  /// and says why instead of pretending it worked.
  bool get supportsPasswordChange;

  /// Changes the password. Throws [AppError] on failure —
  /// [ValidationError] carries the server's reason (wrong current
  /// password, same as current) for inline display.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// 이 빌드에서 계정을 지울 수 있는가. 데모에는 지울 서버 계정이 없다.
  bool get supportsDeletion;

  /// 계정 탈퇴(`DELETE /trainer/me`). 담당 회원 링크·예약이 함께 정리되고
  /// 회원에게는 알림이 간다. 실패는 [AppError]. (#505)
  Future<void> deleteAccount();
}

/// Demo build: no server account to change.
class MockTrainerAccountRepository implements TrainerAccountRepository {
  /// Creates the demo no-op.
  const MockTrainerAccountRepository();

  @override
  bool get supportsPasswordChange => false;

  @override
  bool get supportsDeletion => false;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    // 문구는 화면이 붙인다 — 리포지토리에는 컨텍스트가 없어 로케일을 알 수
    // 없고, message 가 비면 호출부가 자기 로케일의 기본 문구로 채운다. (#501)
    throw const ValidationError();
  }

  @override
  Future<void> deleteAccount() async {
    throw const ValidationError(message: '데모 모드에는 지울 계정이 없어요');
  }
}

/// Real backend: `POST /v1/trainer/me/password`.
class DioTrainerAccountRepository implements TrainerAccountRepository {
  /// Creates the API-backed repository.
  const DioTrainerAccountRepository(this._dio);

  final Dio _dio;

  @override
  bool get supportsPasswordChange => true;

  @override
  bool get supportsDeletion => true;

  @override
  Future<void> deleteAccount() async {
    try {
      await _dio.delete<Map<String, dynamic>>('/trainer/me');
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/trainer/me/password',
        data: <String, String>{
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      // 400 carries the server's own reason ("현재 비밀번호가 일치하지
      // 않습니다."), which is exactly what the trainer needs to read.
      final status = e.response?.statusCode;
      if (status == 400 || status == 422) {
        // 서버가 준 사유가 있으면 그대로, 없으면 화면이 기본 문구를 붙인다.
        throw ValidationError(message: _detail(e));
      }
      throw AppError.fromDio(e);
    }
  }

  String? _detail(DioException e) {
    final data = e.response?.data;
    if (data is! Map) return null;
    final detail = data['detail'];
    return detail is String ? detail : null;
  }
}

/// Provides the account repository for the current mode.
final trainerAccountRepositoryProvider = Provider<TrainerAccountRepository>((
  ref,
) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return const MockTrainerAccountRepository();
  }
  return DioTrainerAccountRepository(ref.watch(dioProvider));
}, name: 'trainerAccountRepository');
