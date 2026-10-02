import 'package:oncare/features/auth/domain/password_reset_code.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart';

/// 데모 빌드의 비밀번호 변경·재설정(#2824).
///
/// - **변경**: 데모 계정에는 바꿀 서버 비밀번호가 없다. 바뀐 척하면 다음 로그인에서
///   새 비밀번호가 안 먹어 더 헷갈리므로, [supportsPasswordChange] 를 꺼 화면이
///   "데모에서는 바꿀 수 없음" 을 말하게 한다.
/// - **재설정**: 메일이 실제로 가지 않으니 요청은 늘 받아 주고, 코드 칸을 채울
///   [demoCode] 를 돌려준다. 확인은 모양이 맞는 코드면 성공으로 둔다 — 데모 계정의
///   비밀번호는 그대로다.
class MockPasswordRepository implements PasswordRepository {
  const MockPasswordRepository();

  /// 데모 재설정 코드. 실 코드와 같은 글자·모양이다.
  static const String demoCode = 'DEMQ-RSET-CDE2-2824';

  /// 데모 코드의 유효 시간 — 서버 기본값과 같다.
  static const int demoExpiresInMinutes = 30;

  @override
  bool get supportsPasswordChange => false;

  @override
  Future<ReissuedTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    throw const PasswordChangeError(PasswordChangeFailure.unavailable);
  }

  @override
  Future<PasswordResetRequested> requestReset({required String email}) async {
    return const PasswordResetRequested(
      expiresInMinutes: demoExpiresInMinutes,
      demoCode: demoCode,
    );
  }

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
