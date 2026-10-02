/// 회원 가입·재동의 화면의 동의 항목. (#2819)
///
/// 철자는 서버(`backend/app/services/signup_consent.py` 의 `kind`)와 같다 —
/// 이 값을 그대로 `consents` 목록으로 보낸다. 어떤 항목이 필수인지도 서버의
/// 회원 기준과 같아야 한다. 화면이 더 느슨하면 버튼은 켜지는데 서버가 422 로
/// 막고, 더 엄격하면 서버가 받는 가입을 화면이 막는다.
abstract final class SignupConsent {
  static const String terms = 'terms';
  static const String privacy = 'privacy';

  /// 건강정보(민감정보) 처리. 다른 개인정보와 **구분한 별도 동의**라 따로 둔다.
  static const String health = 'health';

  /// 만 14세 이상 확인. 그 미만은 법정대리인 동의 절차가 없어 가입을 막는다.
  static const String age14 = 'age14';
  static const String marketing = 'marketing';

  /// 화면에 그리는 순서.
  static const List<String> memberKinds = <String>[
    terms,
    privacy,
    health,
    age14,
    marketing,
  ];

  /// 회원이 체크해야만 다음으로 갈 수 있는 항목.
  static const Set<String> memberRequired = <String>{
    terms,
    privacy,
    health,
    age14,
  };

  static bool isRequired(String kind) => memberRequired.contains(kind);

  /// 필수 항목이 모두 [checked] 에 있는가.
  static bool hasAllRequired(Set<String> checked) =>
      checked.containsAll(memberRequired);

  /// 서버에 보낼 목록 — 화면 순서대로, 모르는 값은 뺀다.
  static List<String> toPayload(Set<String> checked) => <String>[
    for (final String kind in memberKinds)
      if (checked.contains(kind)) kind,
  ];
}
