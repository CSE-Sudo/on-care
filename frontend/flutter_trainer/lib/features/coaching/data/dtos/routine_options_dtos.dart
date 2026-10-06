import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';

/// `RoutineOptionsOut` JSON → [RoutineOptions]. Kept separate from the Dio
/// repository so the DTO ↔ domain mapping is unit-testable.
RoutineOptions routineOptionsFromJson(Map<String, Object?> json) {
  final options = RoutineOptions(
    analysis: _analysis(json['analysis']),
    planA: _plan(json['plan_a']),
    planB: _plan(json['plan_b']),
    generatedBy: _requiredString(json, 'generated_by'),
    findings: _findings(json['findings']),
  );
  if (options.planA.key != 'A' || options.planB.key != 'B') {
    throw const FormatException('routine-options must contain A and B plans.');
  }
  if (options.generatedBy != 'ai' && options.generatedBy != 'rule') {
    throw const FormatException('Invalid routine-options generator.');
  }
  return options;
}

/// [RoutineOptions] → `RoutineOptionsOut` JSON — [routineOptionsFromJson] 의
/// 반대 방향이다.
///
/// 받은 후보를 코칭 화면의 자동 보관(#2873)에 그대로 담아 두었다가, 새로 고침
/// 뒤 같은 후보로 위저드를 다시 연다. 같은 읽기 함수를 지나므로 형식이 하나다.
Map<String, Object?> routineOptionsToJson(RoutineOptions options) =>
    <String, Object?>{
      'analysis': _analysisToJson(options.analysis),
      'plan_a': _planToJson(options.planA),
      'plan_b': _planToJson(options.planB),
      'generated_by': options.generatedBy,
      'findings': <Map<String, Object?>>[
        for (final RoutineFinding f in options.findings)
          <String, Object?>{
            'kind': f.kind,
            'finding': f.finding,
            'source': f.source,
            'action': f.action,
          },
      ],
    };

Map<String, Object?> _analysisToJson(MemberAnalysis a) => <String, Object?>{
  'goal': a.goal,
  'sodium_today_mg': a.sodiumTodayMg,
  'sodium_over_target': a.sodiumOverTarget,
  'avg_completion_rate': a.avgCompletionRate,
  'latest_routine': a.latestRoutine,
  'note': a.note,
  'recent_messages': a.recentMessages,
  'recommendation_status': a.recommendationStatus.name,
  'history_session_count': a.historySessionCount,
  'analysis_period_days': a.analysisPeriodDays,
  'frequent_exercises': a.frequentExercises,
  'suggested_available_minutes': a.suggestedAvailableMinutes,
  'suggested_intensity': a.suggestedIntensity,
};

Map<String, Object?> _planToJson(RoutinePlan plan) => <String, Object?>{
  'key': plan.key,
  'label': plan.label,
  'total_minutes': plan.totalMinutes,
  'intensity': plan.intensity,
  'exercises': <Map<String, Object?>>[
    for (final RoutineExercise e in plan.exercises)
      <String, Object?>{'name': e.name, 'minutes': e.minutes, 'type': e.type},
  ],
  'reason': plan.reason,
  'rationale': plan.rationale,
};

MemberAnalysis _analysis(Object? v) {
  final m = _requiredMap(v, 'analysis');
  return MemberAnalysis(
    goal: _requiredString(m, 'goal'),
    sodiumTodayMg: _requiredInt(m, 'sodium_today_mg'),
    sodiumOverTarget: _requiredBool(m, 'sodium_over_target'),
    avgCompletionRate: _requiredInt(m, 'avg_completion_rate'),
    latestRoutine: _requiredString(m, 'latest_routine'),
    note: _requiredString(m, 'note'),
    recentMessages: _stringList(m, 'recent_messages'),
    // #776 — absent on an older server means "no analysis yet", so these all
    // default to the thin-history shape rather than throwing.
    recommendationStatus: RecommendationStatus.fromWire(
      m['recommendation_status'] is String
          ? m['recommendation_status']! as String
          : '',
    ),
    historySessionCount: _optionalInt(m, 'history_session_count') ?? 0,
    analysisPeriodDays: _optionalInt(m, 'analysis_period_days') ?? 0,
    frequentExercises: _stringList(m, 'frequent_exercises'),
    suggestedAvailableMinutes: _optionalInt(m, 'suggested_available_minutes'),
    suggestedIntensity: m['suggested_intensity'] is String
        ? m['suggested_intensity']! as String
        : null,
  );
}

/// Optional string list. Absent or malformed → empty, never a throw: the chat
/// evidence is supporting context, and a server that predates #580 (or a
/// member with no thread) must still produce usable routine options.
List<String> _stringList(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! List) return const <String>[];
  return <String>[
    for (final Object? item in value)
      if (item is String && item.trim().isNotEmpty) item,
  ];
}

/// 판단 결과(#3280). 보조 근거라 없거나 모양이 틀린 줄은 건너뛴다 — #3280
/// 이전 서버나 자동 보관(#2873)된 옛 후보도 그대로 열려야 한다.
List<RoutineFinding> _findings(Object? value) {
  if (value is! List) return const <RoutineFinding>[];
  return <RoutineFinding>[
    for (final Object? item in value)
      if (item case {
        'kind': final String kind,
        'finding': final String finding,
        'source': final String source,
        'action': final String action,
      })
        RoutineFinding(
          kind: kind,
          finding: finding,
          source: source,
          action: action,
        ),
  ];
}

RoutinePlan _plan(Object? v) {
  final m = _requiredMap(v, 'plan');
  final ex = m['exercises'];
  if (ex is! List) {
    throw const FormatException('Invalid routine plan exercises.');
  }
  return RoutinePlan(
    key: _requiredString(m, 'key'),
    label: _requiredString(m, 'label'),
    totalMinutes: _requiredInt(m, 'total_minutes'),
    intensity: _requiredString(m, 'intensity'),
    exercises: ex
        .map((item) {
          final exercise = _requiredMap(item, 'exercise');
          return RoutineExercise(
            name: _requiredString(exercise, 'name'),
            minutes: _requiredInt(exercise, 'minutes'),
            type: _requiredString(exercise, 'type'),
          );
        })
        .toList(growable: false),
    reason: _requiredString(m, 'reason'),
    rationale: _requiredString(m, 'rationale'),
  );
}

Map<String, Object?> _requiredMap(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('Invalid routine-options $field.');
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) return value;
  throw FormatException('Invalid routine-options $field.');
}

int _requiredInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is num) return value.toInt();
  throw FormatException('Invalid routine-options $field.');
}

/// Absent/null → not enough history to suggest a value, not a parse error.
int? _optionalInt(Map<String, Object?> json, String field) {
  final value = json[field];
  return value is num ? value.toInt() : null;
}

bool _requiredBool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is bool) return value;
  throw FormatException('Invalid routine-options $field.');
}
