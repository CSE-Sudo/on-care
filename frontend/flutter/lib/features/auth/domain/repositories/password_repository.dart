import 'package:oncare_ui/oncare_ui.dart' show AppInputError;

/// 비밀번호 변경이 막힌 이유(#2824). 화면은 이 값으로 자기 로케일의 문구를
/// 고른다 — 서버 문장은 한국어 하나뿐이라 그대로 보여 줄 수 없다.
enum PasswordChangeFailure {
  /// 현재 비밀번호가 맞지 않는다(400). 세션은 그대로다.
  wrongCurrent,

  /// 새 비밀번호가 가입 규칙에 맞지 않는다(422). [PasswordChangeError.reason].
  newRejected,

  /// 소셜 로그인 전용 계정이라 바꿀 비밀번호가 없다(409).
  noPassword,

  /// 이 빌드(데모)에는 바꿀 서버 계정이 없다.
  unavailable,

  /// 너무 자주 시도했다(429).
  tooMany,

  /// 연결 실패·서버 오류 — 다시 해 보면 된다.
  temporary,
}

/// [PasswordRepository.changePassword] 가 던지는 실패.
class PasswordChangeError implements Exception {
  const PasswordChangeError(this.kind, {this.reason});

  final PasswordChangeFailure kind;

  /// [PasswordChangeFailure.newRejected] 일 때 무엇이 규칙에 어긋났는지.
  final AppInputError? reason;

  @override
  String toString() => 'PasswordChangeError($kind, $reason)';
}

/// 비밀번호 재설정이 막힌 이유(#2824).
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

/// [PasswordRepository] 의 재설정 메서드가 던지는 실패.
class PasswordResetError implements Exception {
  const PasswordResetError(this.kind, {this.reason});

  final PasswordResetFailure kind;

  /// [PasswordResetFailure.newRejected] 일 때 무엇이 규칙에 어긋났는지.
  final AppInputError? reason;

  @override
  String toString() => 'PasswordResetError($kind, $reason)';
}

/// 비밀번호를 바꾼 뒤 서버가 새로 준 토큰 한 쌍(#2766).
class ReissuedTokens {
  const ReissuedTokens({required this.access, required this.refresh});

  final String access;
  final String refresh;

  /// 응답 본문에서 꺼낸다. 접근 토큰이 없으면 null.
  ///
  /// 변경은 이미 서버에 반영됐다 — 응답 모양이 어긋났다고 던지면 화면이 "실패"
  /// 로 보여 주는데 비밀번호는 바뀐 상태가 된다. 그래서 null 을 돌려주고, 이
  /// 기기는 다음 요청의 401 에서 만료 안내와 함께 다시 로그인한다.
  static ReissuedTokens? fromJson(Object? body) {
    if (body is! Map) return null;
    final Object? access = body['access_token'];
    if (access is! String || access.isEmpty) return null;
    final Object? refresh = body['refresh_token'];
    return ReissuedTokens(
      access: access,
      refresh: refresh is String ? refresh : '',
    );
  }
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

/// 회원 비밀번호 변경·재설정(#2824).
///
/// 변경은 로그인한 회원이 MY 에서, 재설정은 로그아웃 상태에서 메일로 받은
/// 코드로 한다. 둘 다 성공하면 서버가 토큰 세대를 올려 그 전 세션을 모든
/// 기기에서 끊는다(#2766).
abstract interface class PasswordRepository {
  /// 이 빌드에서 비밀번호를 실제로 바꿀 수 있는가. 데모에는 서버 계정이 없어
  /// 화면이 버튼을 끄고 이유를 말한다.
  bool get supportsPasswordChange;

  /// `POST /users/me/password`. 성공하면 서버가 새로 준 토큰 한 쌍(응답에
  /// 없으면 null). 실패는 [PasswordChangeError].
  Future<ReissuedTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// `POST /auth/password-reset/request`. 가입되지 않은 이메일도 같은 응답이다.
  /// 실패는 [PasswordResetError].
  Future<PasswordResetRequested> requestReset({required String email});

  /// `POST /auth/password-reset/confirm`. 토큰은 주지 않는다 — 새 비밀번호로
  /// 다시 로그인한다. 실패는 [PasswordResetError].
  Future<void> confirmReset({
    required String code,
    required String newPassword,
  });
}
