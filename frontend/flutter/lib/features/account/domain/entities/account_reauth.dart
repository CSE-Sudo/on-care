/// 민감한 계정 작업 앞의 본인 확인(#3039).
///
/// 이메일 변경과 탈퇴는 로그인 토큰만으로 하지 않는다 — 토큰이 새어 나가거나
/// 잠기지 않은 폰을 누가 잠깐 집어 들면, 이메일을 바꿔 비밀번호 재설정으로
/// 계정을 가져가거나 기록 전체를 지울 수 있다. 그래서 비밀번호 계정은 현재
/// 비밀번호를, 비밀번호 없는 소셜 전용 계정은 그 provider 로 다시 로그인해 받은
/// 토큰을 함께 보낸다.
class AccountReauth {
  /// 비밀번호 계정 — 현재 비밀번호.
  const AccountReauth.password(String this.currentPassword)
    : socialProvider = null,
      socialToken = null;

  /// 소셜 전용 계정 — 방금 다시 로그인해 받은 provider 토큰.
  const AccountReauth.social({required String provider, required String token})
    : socialProvider = provider,
      socialToken = token,
      currentPassword = null;

  final String? currentPassword;
  final String? socialProvider;
  final String? socialToken;

  /// 요청 본문에 얹을 칸. 쓰지 않는 칸은 넣지 않는다.
  Map<String, Object?> toJson() => <String, Object?>{
    'current_password': ?currentPassword,
    'social_provider': ?socialProvider,
    'social_token': ?socialToken,
  };
}

/// 본인 확인이 막힌 이유. 화면은 이 값으로 자기 로케일의 문구를 고른다 —
/// 서버 문장은 한국어 하나뿐이다.
enum AccountReauthFailure {
  /// 확인 값을 보내지 않았다 — 400 `reauth_required`.
  required,

  /// 현재 비밀번호가 맞지 않는다 — 400 `invalid_current_password`.
  wrongPassword,

  /// 소셜 계정 확인에 실패했다 — 400 `invalid_reauth`.
  invalidSocial,

  /// 너무 자주 틀렸다 — 429.
  tooMany,
}

/// 서버가 본인 확인을 받아 주지 않았다(#3039).
///
/// **세션은 그대로다.** 401 이 아니라 400 이므로 앱은 로그아웃하지 않고, 창
/// 안에서 다시 입력하게 한다.
class AccountReauthRejected implements Exception {
  const AccountReauthRejected(this.kind);

  final AccountReauthFailure kind;

  /// 응답(상태 코드·본문)을 이유로. 본인 확인 거절이 아니면 null.
  static AccountReauthRejected? fromResponse(int? status, Object? body) {
    if (status == 429) {
      return const AccountReauthRejected(AccountReauthFailure.tooMany);
    }
    if (status != 400) return null;
    final Object? detail = body is Map ? body['detail'] : null;
    final Object? code = detail is Map ? detail['code'] : null;
    return switch (code) {
      'reauth_required' => const AccountReauthRejected(
        AccountReauthFailure.required,
      ),
      'invalid_current_password' => const AccountReauthRejected(
        AccountReauthFailure.wrongPassword,
      ),
      'invalid_reauth' => const AccountReauthRejected(
        AccountReauthFailure.invalidSocial,
      ),
      _ => null,
    };
  }

  @override
  String toString() => 'AccountReauthRejected(${kind.name})';
}
