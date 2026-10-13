import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_options_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/coaching_workspace_draft.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/trainer_program_draft.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';

/// 자동 보관 작성 상태(`workspace`)의 형식 판. 모양을 바꾸면 올리고, 모르는 판은
/// 읽지 않는다 — 다른 판의 값을 억지로 읽어 엉뚱한 화면을 세우느니 묻지 않는 편이
/// 낫다. (#2873)
const int kCoachingWorkspaceVersion = 1;

/// [CoachingWorkspaceDraft] → 프로그램 초안 저장 본문. (#2873)
///
/// 편집기 구성은 초안의 원래 칸에 [programDraftToJson] 그대로 싣는다 — 같은
/// 상한·같은 정리를 지난다. 편집기가 아직 없으면(위저드에서 떠났으면) 빈 세션과
/// [fallbackName] 을 싣는다: 서버는 이름 없는 초안을 받지 않는다.
///
/// `member_id` 는 이 본문에 넣지 않는다. 처음 만들 때만 저장소가 붙인다 — 수정
/// 본문은 회원을 받지 않는다.
Map<String, Object?> coachingDraftPayload(
  CoachingWorkspaceDraft draft, {
  required String fallbackName,
}) {
  final ProgramEditorState? editor = draft.editor;
  final Map<String, Object?> base = editor == null
      ? <String, Object?>{
          'name': fallbackName,
          'goal': '',
          'period': '',
          'memo': '',
          'sessions': const <Object?>[],
        }
      : programDraftToJson(editor);
  final Object? name = base['name'];
  return <String, Object?>{
    ...base,
    if (name is! String || name.isEmpty) 'name': fallbackName,
    'workspace': coachingWorkspaceToJson(draft),
  };
}

/// [CoachingWorkspaceDraft] 의 편집기 밖 상태 → `workspace` 객체.
Map<String, Object?> coachingWorkspaceToJson(CoachingWorkspaceDraft draft) =>
    <String, Object?>{
      'version': kCoachingWorkspaceVersion,
      'phase': draft.phase.name,
      'has_editor': draft.editor != null,
      'routine_only': draft.routineOnly,
      if (draft.routineOnlyStart != null)
        'routine_only_start': ymd(draft.routineOnlyStart!),
      'personal_routines': <Map<String, Object?>>[
        for (final RoutineExercise e in draft.personalRoutines)
          routineExerciseStateToJson(e),
      ],
      if (draft.wizard != null) 'wizard': wizardSnapshotToJson(draft.wizard!),
      if (draft.scheduleNote.isNotEmpty) 'schedule_note': draft.scheduleNote,
    };

/// 저장된 초안 → [CoachingWorkspaceDraft]. 읽을 수 없는 판이거나 회원 초안이
/// 아니면 `null` 이다.
///
/// 편집기 구성은 `has_editor` 일 때만 되살린다 — 위저드에서 떠난 초안의 빈
/// 세션을 편집기로 열면, 트레이너는 손대지 않은 빈 편집기를 본다.
CoachingWorkspaceDraft? coachingWorkspaceFromDraft(
  TrainerProgramDraft draft, {
  required String fallbackSessionName,
}) {
  final String? memberId = draft.memberId;
  if (memberId == null) return null;
  final Map<String, Object?> ws = draft.workspace;
  if (ws['version'] != kCoachingWorkspaceVersion) return null;
  try {
    return CoachingWorkspaceDraft(
      memberId: memberId,
      phase: ws['phase'] == CoachingWorkspacePhase.editor.name
          ? CoachingWorkspacePhase.editor
          : CoachingWorkspacePhase.wizard,
      editor: ws['has_editor'] == true
          ? draft.toEditorState(fallbackSessionName: fallbackSessionName)
          : null,
      routineOnly: ws['routine_only'] == true,
      routineOnlyStart: DateTime.tryParse(
        ws['routine_only_start'] as String? ?? '',
      ),
      personalRoutines: _exercises(ws['personal_routines']),
      scheduleNote: ws['schedule_note'] as String? ?? '',
      wizard: switch (ws['wizard']) {
        final Map<Object?, Object?> map => wizardSnapshotFromJson(
          map.cast<String, Object?>(),
        ),
        _ => null,
      },
    );
  } on Object {
    // 손상된 작성 상태 하나로 코칭 화면이 멈추면 안 된다 — 없는 것으로 본다.
    return null;
  }
}

/// [AiRoutineWizardSnapshot] → JSON.
Map<String, Object?> wizardSnapshotToJson(
  AiRoutineWizardSnapshot s,
) => <String, Object?>{
  'stage': s.stage,
  'max_reached_stage': s.maxReachedStage,
  'routine_only': s.routineOnly,
  'selected_key': s.selectedKey,
  'edited': <Map<String, Object?>>[
    for (final RoutineExercise e in s.edited) routineExerciseStateToJson(e),
  ],
  'personal': <Map<String, Object?>>[
    for (final RoutineExercise e in s.personal) routineExerciseStateToJson(e),
  ],
  'personal_seeded': s.personalSeeded,
  if (s.options != null) 'options': routineOptionsToJson(s.options!),
  'prompt': s.prompt,
  'minutes': s.minutes,
  'intensity': s.intensity,
  'minutes_touched': s.minutesTouched,
  'intensity_touched': s.intensityTouched,
  'measure_chosen': (s.measureChosen.toList()..sort()),
  'personal_measure_chosen': (s.personalMeasureChosen.toList()..sort()),
};

/// JSON → [AiRoutineWizardSnapshot]. 형식이 어긋나면 [FormatException] 이다.
AiRoutineWizardSnapshot wizardSnapshotFromJson(Map<String, Object?> json) {
  final Object? options = json['options'];
  return AiRoutineWizardSnapshot(
    stage: _int(json['stage']),
    maxReachedStage: _int(json['max_reached_stage']),
    routineOnly: json['routine_only'] == true,
    selectedKey: json['selected_key'] as String? ?? 'A',
    edited: _exercises(json['edited']),
    personal: _exercises(json['personal']),
    personalSeeded: json['personal_seeded'] == true,
    options: options is Map<Object?, Object?>
        ? routineOptionsFromJson(options.cast<String, Object?>())
        : null,
    prompt: json['prompt'] as String? ?? '',
    minutes: _int(json['minutes'], fallback: 30),
    intensity: json['intensity'] as String? ?? 'moderate',
    minutesTouched: json['minutes_touched'] == true,
    intensityTouched: json['intensity_touched'] == true,
    measureChosen: _ints(json['measure_chosen']),
    personalMeasureChosen: _ints(json['personal_measure_chosen']),
  );
}

/// 위저드·개인운동 한 줄 → JSON. 화면이 들고 있는 값을 빠짐없이 싣는다 —
/// 회↔초 선택, 출처, 효과 문구, 채운 AI 제안 id 까지(#2747).
Map<String, Object?> routineExerciseStateToJson(RoutineExercise e) =>
    <String, Object?>{
      'name': e.name,
      'minutes': e.minutes,
      'type': e.type,
      'duration_seconds': e.durationSeconds,
      'sets': e.sets,
      'reps': e.reps,
      'hold_seconds': e.holdSeconds,
      'is_hold': e.isHold,
      'weight': e.weight,
      'reason': e.reason,
      'source': e.source,
      'effect': e.effect,
      'suggestion_id': e.suggestionId,
    };

/// JSON → 위저드·개인운동 한 줄.
RoutineExercise routineExerciseStateFromJson(Map<String, Object?> json) =>
    RoutineExercise(
      name: json['name'] as String? ?? '',
      minutes: _int(json['minutes']),
      type: json['type'] as String? ?? '근력',
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      sets: _int(json['sets']),
      reps: _int(json['reps']),
      holdSeconds: _int(json['hold_seconds']),
      isHold: json['is_hold'] == true,
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
      reason: json['reason'] as String? ?? '',
      source: json['source'] as String? ?? 'trainer',
      effect: json['effect'] as String? ?? '',
      suggestionId: json['suggestion_id'] as String?,
    );

List<RoutineExercise> _exercises(Object? value) => <RoutineExercise>[
  if (value is List<Object?>)
    for (final Object? item in value)
      if (item is Map<Object?, Object?>)
        routineExerciseStateFromJson(item.cast<String, Object?>()),
];

int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

Set<int> _ints(Object? value) => <int>{
  if (value is List<Object?>)
    for (final Object? item in value)
      if (item is num) item.toInt(),
};
