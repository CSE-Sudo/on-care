/// The generated A/B routine options for a member — the `RoutineOptionsOut`
/// shape from `POST /trainer/clients/{id}/routine-options`. Generated, not
/// assigned: the trainer picks/edits one, then sends it via the routine
/// assign API.
library;

/// The member-state summary the generation was grounded on (step 1).
class MemberAnalysis {
  const MemberAnalysis({
    required this.goal,
    required this.sodiumTodayMg,
    required this.sodiumOverTarget,
    required this.avgCompletionRate,
    required this.latestRoutine,
    required this.note,
    this.recentMessages = const <String>[],
    this.recommendationStatus = RecommendationStatus.template,
    this.historySessionCount = 0,
    this.analysisPeriodDays = 0,
    this.frequentExercises = const <String>[],
    this.suggestedAvailableMinutes,
    this.suggestedIntensity,
  });

  final String goal;
  final int sodiumTodayMg;
  final bool sodiumOverTarget;
  final int avgCompletionRate;
  final String latestRoutine;
  final String note;

  /// Recent trainer↔member chat the generation was grounded on, oldest first
  /// and already speaker-labelled by the server ("회원: …" / "트레이너: …").
  ///
  /// Shown to the trainer so they can check WHICH utterance the AI acted on —
  /// a routine that silently drops a knee-pain complaint is worse than one
  /// that never saw it. Empty when the thread has no recent messages.
  final List<String> recentMessages;

  /// How much of this generation is grounded in the member's own history
  /// (#776) — the server decides this with an explicit rule, not the UI.
  final RecommendationStatus recommendationStatus;

  /// Completed sessions found within [analysisPeriodDays].
  final int historySessionCount;

  /// The lookback window (days) [historySessionCount] and
  /// [frequentExercises] were computed over.
  final int analysisPeriodDays;

  /// Exercise names repeated across recent sessions, most frequent first.
  /// Empty when there isn't enough history to call anything "frequent".
  final List<String> frequentExercises;

  /// Conditions the server derived from recent history — shown pre-filled
  /// in step 1 so the trainer edits rather than starts from scratch. Null
  /// when history is too thin to suggest anything.
  final int? suggestedAvailableMinutes;
  final String? suggestedIntensity;
}

/// How much of a [MemberAnalysis] reflects the member's own recorded
/// history, from a fresh member (no signal) to a settled pattern (#776).
enum RecommendationStatus {
  /// Not enough history to analyze — falls back to a goal-based default.
  template,

  /// Some recent activity, but not yet a pattern worth trusting fully.
  learning,

  /// A repeated pattern was found across several weeks of history.
  personalized;

  static RecommendationStatus fromWire(String value) => switch (value) {
    'learning' => RecommendationStatus.learning,
    'personalized' => RecommendationStatus.personalized,
    _ => RecommendationStatus.template,
  };
}

/// One exercise line in a plan.
class RoutineExercise {
  const RoutineExercise({
    required this.name,
    required this.minutes,
    required this.type,
    this.sets = 0,
    this.reps = 0,
    this.holdSeconds = 0,
    this.isHold = false,
    this.weight = 0,
    this.reason = '',
    this.source = 'trainer',
  });

  final String name;
  final int minutes;
  final String type;

  /// AI 가 이 운동을 고른 이유. **트레이너만 보는 글이다** — 회원에게는
  /// 보내지 않고, 이 제안을 그대로 둘지 판단하는 재료로만 쓴다(#2223).
  /// PT 프로그램 후보는 비어 있고, 개인운동 단계가 AI 제안에서 받아 온
  /// 항목만 값이 있다.
  final String reason;

  /// 이 항목이 어디서 왔나 — 'ai' 는 AI 제안을 그대로 둔 것, 'trainer' 는
  /// 트레이너가 직접 넣은 것. 개인운동을 보낼 때 출처로 나간다. (#2223)
  final String source;

  /// 근력 운동에서만 쓴다(#1029, #1310) — 세트 수·한 세트당 횟수·중량(kg).
  /// 서버가 주는 A/B 후보는 아직 이 값을 모르니 0 으로 시작하고, 트레이너가
  /// 이 화면에서 직접 채운다. `ProgramExerciseDraft` 로 넘어갈 때 그대로
  /// 옮겨진다 — 셋 중 하나라도 빠지면 프로그램 편집기에서 다시 물어야 한다.
  final int sets;
  final int reps;

  /// 버티는 운동이면 한 세트를 버티는 시간(초). [reps] 와 한 자리를 나눠
  /// 쓰지만 값은 따로 들고 있어야, 회↔초를 오갈 때 각자의 값이 남는다.
  /// 0 이 "적지 않음" 이다. (#1969)
  final int holdSeconds;

  /// 지금 이 운동을 초로 재는가 — 어느 칸을 보이고 어느 칸을 실을지를 정한다.
  final bool isHold;

  final double weight;

  RoutineExercise copyWith({
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    bool? isHold,
    double? weight,
    String? reason,
    String? source,
  }) => RoutineExercise(
    name: name ?? this.name,
    minutes: minutes ?? this.minutes,
    type: type ?? this.type,
    sets: sets ?? this.sets,
    reps: reps ?? this.reps,
    holdSeconds: holdSeconds ?? this.holdSeconds,
    isHold: isHold ?? this.isHold,
    weight: weight ?? this.weight,
    reason: reason ?? this.reason,
    source: source ?? this.source,
  );
}

/// One generated plan (A recovery/sustainable or B intensity/volume).
class RoutinePlan {
  const RoutinePlan({
    required this.key,
    required this.label,
    required this.totalMinutes,
    required this.intensity,
    required this.exercises,
    required this.reason,
    required this.rationale,
  });

  /// "A" or "B".
  final String key;
  final String label;
  final int totalMinutes;
  final String intensity;
  final List<RoutineExercise> exercises;
  final String reason;

  /// Data-grounded rationale citing the member's numbers.
  final String rationale;
}

/// The full A/B options response.
class RoutineOptions {
  const RoutineOptions({
    required this.analysis,
    required this.planA,
    required this.planB,
    required this.generatedBy,
  });

  final MemberAnalysis analysis;
  final RoutinePlan planA;
  final RoutinePlan planB;

  /// "ai" (LLM) or "rule" (deterministic fallback).
  final String generatedBy;
}
