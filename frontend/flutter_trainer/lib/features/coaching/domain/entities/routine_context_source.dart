/// AI 추천이 참고할 수 있는 트레이너 쪽 자료(#2587).
///
/// 서버 `RoutineContextSource` 와 같은 값이다 — [wire] 가 요청의 `sources`
/// 목록에 그대로 들어간다. 순서는 위저드의 체크 목록 순서다.
enum RoutineContextSource {
  /// 회원과의 최근 대화 원문. 최근 14일 · 최대 10건. (#2794)
  ///
  /// 예전에는 고르는 목록에 없어 늘 AI 에 실렸다 — 민감한 대화가 섞일 수 있어
  /// 트레이너가 뺄 수 있게 한다. 끄면 규칙형의 통증 판단에도 쓰이지 않고,
  /// `참고한 최근 대화` 도 보이지 않는다.
  recentChat('recent_chat', defaultOn: true),

  /// 완료한 PT 일정의 글(트레이너 피드백). 최근 14일 · 최대 5건.
  ptFeedback('pt_feedback', defaultOn: true),

  /// 상담 일정의 글(상담 메모). 최근 30일 · 최대 3건.
  ///
  /// 등록 상담처럼 운동과 무관하거나 민감한 내용이 섞이는 자리라 기본으로
  /// 꺼 둔다 — 넣을지는 트레이너가 켠다.
  consultMemo('consult_memo', defaultOn: false),

  /// 회원 상세에서 직접 쓴 메모. 최근 14일 · 최대 5건.
  trainerMemo('trainer_memo', defaultOn: true),

  /// 채팅 감지에서 남긴 메모. 최근 7일 · 최대 10건.
  chatInsight('chat_insight', defaultOn: true),

  /// 회원이 남긴 주간 피드백. 이번 주와 지난주.
  weeklyFeedback('weekly_feedback', defaultOn: true);

  const RoutineContextSource(this.wire, {required this.defaultOn});

  /// 서버 계약값.
  final String wire;

  /// 트레이너가 아직 고른 적이 없을 때 켜져 있는가. 서버 기본값과 같다.
  final bool defaultOn;

  /// 고른 적이 없을 때의 선택.
  static Set<RoutineContextSource> get defaults => <RoutineContextSource>{
    for (final RoutineContextSource source in values)
      if (source.defaultOn) source,
  };

  /// [recentChat] 이 생기기 전(#2794)부터 있던 자료. 그때 저장한 선택은 이
  /// 다섯 가지만 보고 고른 것이라, 새 자료는 기본값으로 더한다.
  static const Set<RoutineContextSource> legacy = <RoutineContextSource>{
    ptFeedback,
    consultMemo,
    trainerMemo,
    chatInsight,
    weeklyFeedback,
  };

  /// [wire] → 값. 모르는 값(다른 버전이 저장한 것)은 `null` 이다.
  static RoutineContextSource? fromWire(String wire) {
    for (final RoutineContextSource source in values) {
      if (source.wire == wire) return source;
    }
    return null;
  }
}
