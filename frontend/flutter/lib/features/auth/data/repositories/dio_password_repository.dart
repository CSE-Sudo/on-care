import 'package:dio/dio.dart';
import 'package:oncare/features/auth/domain/password_reset_code.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppInputError, AppInputRules;

/// 실 서버 비밀번호 변경·재설정(#2824). 규약은 `backend/API_CONTRACT.md` 의
/// "회원 비밀번호 변경"·"비밀번호 재설정" 절이다.
class DioPasswordRepository implements PasswordRepository {
  const DioPasswordRepository(this._dio);

  final Dio _dio;

  @override
  bool get supportsPasswordChange => true;

  @override
  Future<ReissuedTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final Response<Map<String, Object?>> res;
    try {
      res = await _dio.post<Map<String, Object?>>(
        '/users/me/password',
        data: <String, String>{
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      throw _changeError(e);
    }
    return ReissuedTokens.fromJson(res.data);
  }

  @override
  Future<PasswordResetRequested> requestReset({required String email}) async {
    final Response<Map<String, Object?>> res;
    try {
      res = await _dio.post<Map<String, Object?>>(
        '/auth/password-reset/request',
        data: <String, String>{'email': email},
      );
    } on DioException catch (e) {
      throw _resetError(e);
    }
    final Object? minutes = res.data?['expires_in_minutes'];
    return PasswordResetRequested(
      expiresInMinutes: minutes is num ? minutes.toInt() : 0,
    );
  }

  @override
  Future<void> confirmReset({
    required String code,
    required String newPassword,
  }) async {
    try {
      await _dio.post<Map<String, Object?>>(
        '/auth/password-reset/confirm',
        data: <String, String>{
          'token': PasswordResetCode.normalize(code),
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      throw _resetError(e);
    }
  }
}

/// `POST /users/me/password` 의 실패를 화면이 고를 이유로.
///
/// 400 은 현재 비밀번호 불일치다(같은 비밀번호도 400 이지만 화면이 보내기 전에
/// 거른다). 401 이 아니므로 세션 인터셉터가 로그아웃으로 오인하지 않는다.
PasswordChangeError _changeError(DioException e) {
  final int? status = e.response?.statusCode;
  return switch (status) {
    400 => const PasswordChangeError(PasswordChangeFailure.wrongCurrent),
    409 => const PasswordChangeError(PasswordChangeFailure.noPassword),
    422 => PasswordChangeError(
      PasswordChangeFailure.newRejected,
      reason: _newPasswordReason(e.response?.data),
    ),
    429 => const PasswordChangeError(PasswordChangeFailure.tooMany),
    _ => const PasswordChangeError(PasswordChangeFailure.temporary),
  };
}

/// 재설정 요청·확인의 실패를 화면이 고를 이유로.
PasswordResetError _resetError(DioException e) {
  final int? status = e.response?.statusCode;
  return switch (status) {
    400 => const PasswordResetError(PasswordResetFailure.invalidCode),
    422 when AppInputRules.serverPasswordError(e.response?.data) != null =>
      PasswordResetError(
        PasswordResetFailure.newRejected,
        reason: AppInputRules.serverPasswordError(e.response?.data),
      ),
    429 => const PasswordResetError(PasswordResetFailure.tooMany),
    503 => const PasswordResetError(PasswordResetFailure.unavailable),
    _ => const PasswordResetError(PasswordResetFailure.temporary),
  };
}

/// 422 본문에서 새 비밀번호가 어긋난 이유. 모르는 모양이면 약한 비밀번호로 본다
/// — 422 는 이 요청에서 새 비밀번호 칸 말고는 날 곳이 없다.
AppInputError _newPasswordReason(Object? body) =>
    AppInputRules.serverPasswordError(body) ?? AppInputError.passwordWeak;
