/// 회원이 한 주를 끝내며 남기는 세 문항. (#2232)
///
/// 수치만 보면 같은 한 주가 `게으름` 으로도 `과부하·일정 문제` 로도 읽힌다.
/// 이행률 32%, 화·금 미수행, 식단 사흘 결측 — 여기까지는 둘 다 똑같이 생겼다.
/// 그런데 그 둘은 다음 주 처방이 **정반대**다. 앞쪽이면 강도를 유지하고 알림을
/// 늘리고, 뒤쪽이면 강도를 내리고 일정을 옮긴다. 갈림길을 정하는 것은 수치를
/// 더 모으는 일이 아니라 회원 본인에게 묻는 일이다.
///
/// 그래서 문항은 셋뿐이다 — 컨디션·강도·통증. 30초 안에 끝나지 않으면 매주
/// 돌아오지 않고, 돌아오지 않는 문항은 없는 것과 같다.
library;

/// 한 주 컨디션. 좋은 쪽에서 나쁜 쪽 순서다 — 화면이 이 순서대로 줄을 세운다.
enum WeekCondition {
  great,
  good,
  ok,
  tired,
  bad;

  /// 서버·DB 가 쓰는 값. 이름을 그대로 쓴다.
  String get wire => name;

  /// 저장값에서 되읽는다. 모르는 값은 null — 조용히 `보통` 으로 접으면
  /// 트레이너가 회원이 하지 않은 말을 읽는다.
  static WeekCondition? parse(String? value) {
    for (final WeekCondition v in values) {
      if (v.name == value) return v;
    }
    return null;
  }

  /// 걱정해야 하는 답인가. `지쳤다`·`나빴다` 는 다음 주 강도를 내리는 근거다.
  bool get needsAttention => this == tired || this == bad;
}

/// 운동 강도 체감. 양쪽 끝이 모두 있어야 한다 — `힘들었나` 만 물으면 너무
/// 쉬웠던 주가 `괜찮음` 으로 접혀, 다음 주에도 같은 무게가 나간다.
enum WeekIntensity {
  tooEasy,
  right,
  hard,
  tooHard;

  /// 서버·DB 가 쓰는 snake_case 값.
  String get wire => switch (this) {
    WeekIntensity.tooEasy => 'too_easy',
    WeekIntensity.right => 'right',
    WeekIntensity.hard => 'hard',
    WeekIntensity.tooHard => 'too_hard',
  };

  /// 저장값에서 되읽는다. 모르는 값은 null.
  static WeekIntensity? parse(String? value) {
    for (final WeekIntensity v in values) {
      if (v.wire == value) return v;
    }
    return null;
  }

  /// 다음 주 처방을 바꿔야 하는 답인가 — 양쪽 끝이다.
  bool get needsAttention => this == tooEasy || this == tooHard;
}

/// 회원이 낸 한 주치 답.
class MemberWeeklyFeedback {
  /// Creates a feedback.
  const MemberWeeklyFeedback({
    required this.weekStart,
    required this.condition,
    required this.intensity,
    this.painArea = '',
    this.painOn,
    this.note = '',
  });

  /// 저장된 값에서 만든다. 컨디션과 강도가 둘 다 읽히지 않으면 **답이 아니다** —
  /// 한쪽만 있는 답을 반쯤 그리면 트레이너가 나머지를 짐작하게 된다.
  static MemberWeeklyFeedback? fromWire({
    required DateTime weekStart,
    String? condition,
    String? intensity,
    String painArea = '',
    String painOn = '',
    String note = '',
  }) {
    final WeekCondition? c = WeekCondition.parse(condition);
    final WeekIntensity? i = WeekIntensity.parse(intensity);
    if (c == null || i == null) return null;
    final String area = painArea.trim();
    return MemberWeeklyFeedback(
      weekStart: weekStart,
      condition: c,
      intensity: i,
      painArea: area,
      // 아픈 곳을 적지 않았으면 날짜도 버린다 — 화면이 "(빈칸) 이 아팠다" 를
      // 그리지 않게. 서버도 같은 규칙으로 저장한다.
      painOn: area.isEmpty ? null : DateTime.tryParse(painOn),
      note: note.trim(),
    );
  }

  /// 이 답이 가리키는 주의 월요일.
  final DateTime weekStart;

  final WeekCondition condition;
  final WeekIntensity intensity;

  /// 아픈 곳. 없으면 빈 문자열.
  final String painArea;

  /// 아팠던 날. [painArea] 가 비면 언제나 null.
  final DateTime? painOn;

  /// 한 줄 자유 서술.
  final String note;

  /// 통증을 보고했는가.
  bool get hasPain => painArea.isNotEmpty;

  /// 다음 주 처방을 바꿔야 할 답인가 — 셋 중 하나라도 걸리면 그렇다.
  ///
  /// 이 값이 참이면 ① 의 판정 문장이 수치가 아니라 이 답을 근거로 삼는다.
  bool get needsAttention =>
      condition.needsAttention || intensity.needsAttention || hasPain;

  /// 이 답을 낸 날 — 그 주의 일요일이다.
  ///
  /// 문항은 **주가 끝나고** 받는다. 저장 시각을 그대로 쓰지 않는 까닭은, 늦게
  /// 낸 답이 "다음 주에 한 말" 처럼 보이면 트레이너가 어느 주 이야기인지를
  /// 다시 맞춰 봐야 하기 때문이다. 어느 주의 답인지가 이 날짜의 뜻이다.
  DateTime get submittedOn =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + 6);
}
