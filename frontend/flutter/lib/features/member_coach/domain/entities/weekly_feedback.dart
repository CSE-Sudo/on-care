/// 회원이 한 주를 끝내며 담당 트레이너에게 남기는 세 문항. (#2232)
///
/// 트레이너 쪽 리포트 작업대의 `회원 주간 피드백` 칸이 읽는 바로 그 값이다.
/// 수치만 보면 같은 한 주가 `게으름` 으로도 `과부하·일정 문제` 로도 읽히는데,
/// 그 둘은 다음 주 처방이 정반대다. 갈림길을 정하는 것은 수치를 더 모으는 일이
/// 아니라 회원 본인에게 묻는 일이다.
///
/// 문항이 셋뿐인 까닭 — 30초 안에 끝나지 않으면 매주 돌아오지 않고, 돌아오지
/// 않는 문항은 없는 것과 같다.
///
/// **담당 트레이너가 있는 회원의 기능이다.** 트레이너 없이 보는 주간 리포트
/// (포인트 교환, #2022)와는 다른 길이라 그 경로와 섞지 않는다.
library;

import 'package:oncare/core/utils/clock.dart';

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

  /// 답 옆에 붙는 얼굴. 글자만 있으면 다섯 칸이 모두 같은 모양이라, 회원이
  /// 좋은 쪽이 어느 끝인지를 읽고 나서야 고를 수 있다 — 얼굴은 읽기 전에
  /// 보인다. 트레이너 화면도 같은 얼굴을 쓴다.
  String get emoji => switch (this) {
    great => '😄',
    good => '🙂',
    ok => '😐',
    tired => '😩',
    bad => '😣',
  };
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

/// 한 주치 답 — 아직 내지 않은 주도 이 값으로 온다([submitted] 가 false).
///
/// 답이 없는 것을 오류로 만들지 않는 까닭: 안 낸 주가 정상이고, 화면은 그때
/// "아직 보내지 않았어요" 를 적어야 한다. 비어 있음을 오류로 만들면 그 칸이
/// 통째로 사라진다.
class MemberWeeklyFeedback {
  /// Creates a feedback.
  const MemberWeeklyFeedback({
    required this.weekStart,
    this.submitted = false,
    this.condition,
    this.intensity,
    this.painArea = '',
    this.painOn,
    this.note = '',
    this.submittedAt,
  });

  /// 아직 답하지 않은 주.
  factory MemberWeeklyFeedback.empty(DateTime weekStart) =>
      MemberWeeklyFeedback(weekStart: weekStart);

  /// 이 답이 가리키는 주의 월요일.
  final DateTime weekStart;

  /// 회원이 이 주에 답을 냈는가.
  final bool submitted;

  /// 컨디션. 아직 안 냈으면 null.
  final WeekCondition? condition;

  /// 강도 체감. 아직 안 냈으면 null.
  final WeekIntensity? intensity;

  /// 아픈 곳. 없으면 빈 문자열.
  final String painArea;

  /// 아팠던 날. [painArea] 가 비면 언제나 null.
  final DateTime? painOn;

  /// 한 줄 자유 서술.
  final String note;

  /// 낸 시각. 아직 안 냈으면 null.
  final DateTime? submittedAt;

  /// 통증을 보고했는가.
  bool get hasPain => painArea.isNotEmpty;

  /// 트레이너가 눈여겨봐야 할 답인가 — 셋 중 하나라도 걸리면 그렇다.
  ///
  /// 안 낸 주는 언제나 false 다. 답하지 않은 것은 `괜찮다` 도 `나쁘다` 도 아니다.
  bool get needsAttention =>
      submitted &&
      ((condition?.needsAttention ?? false) ||
          (intensity?.needsAttention ?? false) ||
          hasPain);

  /// 보낼 수 있는 답인가 — 두 문항을 모두 골랐을 때만.
  ///
  /// 한쪽만 있는 답을 받으면 트레이너 화면이 나머지를 짐작하게 된다. 서버도
  /// 같은 규칙이라(두 값 모두 필수), 여기서 막지 않으면 422 로 돌아온다.
  bool get isComplete => condition != null && intensity != null;

  /// 화면이 고른 값 하나만 바꿔 다시 들고 있는다.
  ///
  /// `painOn` 을 지우는 일은 `clearPainOn` 으로 한다 — null 을 `안 바꿈` 으로
  /// 읽는 자리에서 `비움` 을 표현할 방법이 달리 없다.
  MemberWeeklyFeedback copyWith({
    bool? submitted,
    WeekCondition? condition,
    WeekIntensity? intensity,
    String? painArea,
    DateTime? painOn,
    bool clearPainOn = false,
    String? note,
    DateTime? submittedAt,
  }) => MemberWeeklyFeedback(
    weekStart: weekStart,
    submitted: submitted ?? this.submitted,
    condition: condition ?? this.condition,
    intensity: intensity ?? this.intensity,
    painArea: painArea ?? this.painArea,
    painOn: clearPainOn ? null : (painOn ?? this.painOn),
    note: note ?? this.note,
    submittedAt: submittedAt ?? this.submittedAt,
  );
}

/// 이번에 물어볼 주 — 없으면 묻지 않는다. (#2232)
///
/// 피드백은 끝난 한 주를 돌아보며 적는 것이라 **일요일**에 묻는다. 그런데
/// 일요일 하루만 물으면, 그날 앱을 안 켠 회원의 한 주는 영영 비어 있고
/// 트레이너는 월요일 아침에 쓸 근거를 잃는다. 그래서 월요일까지 한 번 더
/// 묻되, 그때는 **끝난 지난 주**를 묻는다.
///
/// * 일요일 → 그날로 끝나는 이번 주(월요일 기준).
/// * 월요일 → 어제 끝난 지난 주.
/// * 그 밖의 요일 → null. 회원이 직접 `지금 피드백 보내기` 로 들어올 수는 있다.
///
/// 이미 답한 주는 다시 묻지 않는다 — 그 판정은 [askableWeek] 가 돌려준 주의
/// `submitted` 로 화면이 한다.
DateTime? askableWeek([DateTime? today]) {
  final DateTime day = _dateOnly(today ?? todayKst());
  return switch (day.weekday) {
    DateTime.sunday => _monday(day),
    // 월요일에는 어제 끝난 주다 — 오늘이 속한 주는 아직 하루도 지나지 않았다.
    DateTime.monday => _monday(day.subtract(const Duration(days: 1))),
    _ => null,
  };
}

/// 회원이 직접 열었을 때 물을 주 — 방금 끝난 주다. (#2232)
///
/// 주중에 `지금 피드백 보내기` 를 누르면 이번 주를 묻는 것이 자연스러워 보이지만,
/// 그러면 수요일에 `한 주 컨디션` 을 묻게 된다. 아직 오지 않은 나흘에 대한 답을
/// 받아 트레이너에게 넘길 수는 없다.
///
/// 일요일만은 예외다 — 오늘로 끝나는 주가 곧 방금 끝난 주다.
DateTime manualFeedbackWeek([DateTime? today]) {
  final DateTime day = _dateOnly(today ?? todayKst());
  if (day.weekday == DateTime.sunday) return _monday(day);
  return _monday(day).subtract(const Duration(days: 7));
}

DateTime _dateOnly(DateTime v) => DateTime(v.year, v.month, v.day);

DateTime _monday(DateTime day) =>
    _dateOnly(day).subtract(Duration(days: day.weekday - DateTime.monday));
