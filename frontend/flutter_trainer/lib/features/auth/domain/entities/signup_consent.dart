/// 트레이너 가입·재동의 화면의 동의 항목. (#2819)
///
/// 철자는 서버(`backend/app/services/signup_consent.py` 의 `kind`)와 같다.
/// 트레이너는 회원과 달리 건강정보 처리 동의가 없다 — 자기 건강정보를 이 앱에
/// 기록하지 않는다. 어떤 항목이 필수인지는 서버의 트레이너 기준과 같아야 한다.
abstract final class TrainerSignupConsent {
  static const String terms = 'terms';
  static const String privacy = 'privacy';

  /// 만 14세 이상 확인.
  static const String age14 = 'age14';
  static const String marketing = 'marketing';

  /// 화면에 그리는 순서.
  static const List<String> kinds = <String>[terms, privacy, age14, marketing];

  /// 체크해야만 다음으로 갈 수 있는 항목.
  static const Set<String> required = <String>{terms, privacy, age14};

  static bool hasAllRequired(Set<String> checked) =>
      checked.containsAll(required);

  /// 서버에 보낼 목록 — 화면 순서대로, 모르는 값은 뺀다.
  static List<String> toPayload(Set<String> checked) => <String>[
    for (final String kind in kinds)
      if (checked.contains(kind)) kind,
  ];
}
