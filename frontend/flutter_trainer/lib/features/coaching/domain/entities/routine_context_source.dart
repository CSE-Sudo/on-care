/// AI 추천이 참고할 수 있는 트레이너 쪽 자료(#2587).
///
/// 서버 `RoutineContextSource` 와 같은 값이다 — [wire] 가 요청의 `sources`
/// 목록에 그대로 들어간다. 순서는 위저드의 체크 목록 순서다.
enum RoutineContextSource {
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

  /// [wire] → 값. 모르는 값(다른 버전이 저장한 것)은 `null` 이다.
  static RoutineContextSource? fromWire(String wire) {
    for (final RoutineContextSource source in values) {
      if (source.wire == wire) return source;
    }
    return null;
  }
}
