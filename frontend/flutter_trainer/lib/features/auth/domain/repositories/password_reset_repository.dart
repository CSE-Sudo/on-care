import 'package:oncare_ui/oncare_ui.dart' show AppInputError;

/// 비밀번호 재설정이 막힌 이유(#2824). 화면은 이 값으로 자기 로케일의 문구를
/// 고른다.
enum PasswordResetFailure {
  /// 코드가 틀렸거나, 만료됐거나, 이미 쓰였다(400). 어느 쪽인지 서버도 밝히지
  /// 않는다 — 다시 요청하면 된다.
  invalidCode,

  /// 새 비밀번호가 가입 규칙에 맞지 않는다(422).
  newRejected,

  /// 서버가 지금 메일을 보낼 수 없다(503, 발송 설정 없음).
  unavailable,

  /// 너무 자주 요청했다(429).
  tooMany,

  /// 연결 실패·서버 오류.
  temporary,
}

/// [PasswordResetRepository] 가 던지는 실패.
class PasswordResetError implements Exception {
  const PasswordResetError(this.kind, {this.reason});

  final PasswordResetFailure kind;

  /// [PasswordResetFailure.newRejected] 일 때 무엇이 규칙에 어긋났는지.
  final AppInputError? reason;

  @override
  String toString() => 'PasswordResetError($kind, $reason)';
}

/// 재설정 요청을 받았다는 응답.
class PasswordResetRequested {
  const PasswordResetRequested({required this.expiresInMinutes, this.demoCode});

  /// 코드가 살아 있는 시간(분). 계정이 있든 없든 같은 값이다.
  final int expiresInMinutes;

  /// 데모 빌드에서만 채운다 — 메일이 실제로 가지 않으니 화면이 코드 칸을 미리
  /// 채워 흐름을 끝까지 볼 수 있게 한다. 실 서버는 늘 null.
  final String? demoCode;
}

/// 로그아웃 상태에서 메일로 받은 코드로 비밀번호를 다시 정한다(#2824).
///
/// 회원과 같은 엔드포인트다 — 서버가 이메일로 계정을 찾고, 트레이너 계정이면
/// 트레이너 웹 주소로 링크를 만든다. 성공하면 토큰 세대가 올라 모든 기기의
/// 세션이 끝난다(#2766). 로그인 중 비밀번호 변경은 MY 의 기존 경로다.
abstract interface class PasswordResetRepository {
  /// `POST /auth/password-reset/request`. 가입되지 않은 이메일도 같은 응답이다.
  Future<PasswordResetRequested> requestReset({required String email});

  /// `POST /auth/password-reset/confirm`. 토큰은 주지 않는다 — 새 비밀번호로
  /// 다시 로그인한다.
  Future<void> confirmReset({
    required String code,
    required String newPassword,
  });
}
