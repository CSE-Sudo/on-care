/// 아이디(가입 이메일) 찾기(#3337).
///
/// 이름과 휴대폰 번호로 가입 계정을 찾는다. 번호의 주인을 확인할 수단이 없어
/// 서버는 **가려진 이메일**만 준다 — 전체 이메일은 어떤 경우에도 오지 않는다.
/// 규약은 `backend/API_CONTRACT.md` 의 "아이디(가입 이메일) 찾기" 절이다.
library;

/// 찾은 계정 하나.
class FoundEmailAccount {
  const FoundEmailAccount({
    this.maskedEmail,
    this.providers = const <String>[],
  });

  /// 가려진 이메일(`ab***@example.com`). 소셜 로그인 전용 계정이면 null.
  final String? maskedEmail;

  /// 연결된 소셜 가입 수단(`kakao`·`google`). 없으면 빈 목록.
  final List<String> providers;

  /// 이메일 없이 가입 수단만 안내할 계정인가.
  bool get isSocialOnly => maskedEmail == null;

  /// 응답의 계정 하나를 읽는다. 모양이 어긋난 항목은 null 이다.
  ///
  /// 가려지지 않은 값은 받지 않는다 — 서버가 실수로 전체 이메일을 실어도 화면에
  /// 그리지 않는다.
  static FoundEmailAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? email = json['masked_email'];
    final Object? linked = json['providers'];
    final List<String> providers = <String>[
      if (linked is List)
        for (final Object? p in linked)
          if (p is String && p.isNotEmpty) p,
    ];
    final String? masked = email is String && email.contains('*')
        ? email
        : null;
    if (masked == null && providers.isEmpty) return null;
    return FoundEmailAccount(maskedEmail: masked, providers: providers);
  }
}

/// 찾기가 막힌 이유. 찾지 못한 것은 실패가 아니다(빈 목록).
enum FindEmailFailure {
  /// 이름·번호가 서버 형식에 맞지 않는다(422). 화면이 보내기 전에 거르므로 드물다.
  invalidInput,

  /// 너무 자주 찾았다(429).
  tooMany,

  /// 연결 실패·서버 오류.
  temporary,
}

/// [FindEmailRepository.find] 가 던지는 실패.
class FindEmailError implements Exception {
  const FindEmailError(this.kind);

  final FindEmailFailure kind;

  @override
  String toString() => 'FindEmailError($kind)';
}

abstract interface class FindEmailRepository {
  /// `POST /auth/find-email`. 맞는 계정이 없으면 빈 목록이다. 실패는
  /// [FindEmailError].
  Future<List<FoundEmailAccount>> find({
    required String name,
    required String phone,
  });
}
