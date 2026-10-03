import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/auth/domain/password_reset_code.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/password_reset_repository.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppInputRules;

/// 실 서버 비밀번호 재설정(#2824). 규약은 `backend/API_CONTRACT.md` 의
/// "비밀번호 재설정" 절이다.
class DioPasswordResetRepository implements PasswordResetRepository {
  const DioPasswordResetRepository(this._dio);

  final Dio _dio;

  @override
  Future<PasswordResetRequested> requestReset({required String email}) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        '/auth/password-reset/request',
        data: <String, String>{'email': email},
      );
    } on DioException catch (e) {
      throw passwordResetErrorOf(e);
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
      await _dio.post<Map<String, dynamic>>(
        '/auth/password-reset/confirm',
        data: <String, String>{
          'token': PasswordResetCode.normalize(code),
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      throw passwordResetErrorOf(e);
    }
  }
}

/// 재설정 요청·확인의 실패를 화면이 고를 이유로.
PasswordResetError passwordResetErrorOf(DioException e) {
  final int? status = e.response?.statusCode;
  final Object? body = e.response?.data;
  return switch (status) {
    400 => const PasswordResetError(PasswordResetFailure.invalidCode),
    422 when AppInputRules.serverPasswordError(body) != null =>
      PasswordResetError(
        PasswordResetFailure.newRejected,
        reason: AppInputRules.serverPasswordError(body),
      ),
    429 => const PasswordResetError(PasswordResetFailure.tooMany),
    503 => const PasswordResetError(PasswordResetFailure.unavailable),
    _ => const PasswordResetError(PasswordResetFailure.temporary),
  };
}

/// 데모 빌드의 재설정(#2824). 메일이 실제로 가지 않으니 요청은 늘 받아 주고,
/// 코드 칸을 채울 [demoCode] 를 돌려준다. 확인은 모양이 맞는 코드면 성공으로
/// 둔다 — 데모 계정의 비밀번호는 그대로다.
class MockPasswordResetRepository implements PasswordResetRepository {
  const MockPasswordResetRepository();

  /// 데모 재설정 코드. 실 코드와 같은 글자·모양이다.
  static const String demoCode = 'DEMQ-RSET-CDE2-2824';

  /// 데모 코드의 유효 시간 — 서버 기본값과 같다.
  static const int demoExpiresInMinutes = 30;

  @override
  Future<PasswordResetRequested> requestReset({required String email}) async =>
      const PasswordResetRequested(
        expiresInMinutes: demoExpiresInMinutes,
        demoCode: demoCode,
      );

  @override
  Future<void> confirmReset({
    required String code,
    required String newPassword,
  }) async {
    if (!PasswordResetCode.isWellFormed(code)) {
      throw const PasswordResetError(PasswordResetFailure.invalidCode);
    }
  }
}

/// 지금 빌드의 재설정 리포지토리 — 데모면 목업, 아니면 실 서버.
final passwordResetRepositoryProvider = Provider<PasswordResetRepository>((
  ref,
) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return const MockPasswordResetRepository();
  }
  return DioPasswordResetRepository(ref.watch(dioProvider));
}, name: 'passwordResetRepository');
