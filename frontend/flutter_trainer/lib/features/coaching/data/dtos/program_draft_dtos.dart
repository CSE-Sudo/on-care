import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_effects.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/shared/exercise_limits.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Wire values the backend accepts for an exercise's origin.
const List<String> kProgramExerciseSources = <String>['ai', 'trainer'];

const int _kMemoMax = 300;
const int _kNameMax = 100;

String _cap(String value, int max) {
  final trimmed = value.trim();
  return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
}

/// 세션 이름을 서버가 받는 길이로 맞춘다.
///
/// 배정(`ProgramDraftSession.name`)과 일정(`ProgramItem.session`)이 같은 상한을
/// 쓰므로 두 경로가 같은 함수를 지나야 한다 — 한쪽만 자르면 긴 세션 이름으로
/// 배정은 되고 일정 등록만 422 가 된다.
String capSessionName(String value) => _cap(value, _kNameMax);

/// [ProgramExerciseDraft] → `ProgramDraftExercise` JSON.
///
/// Clamps to the server's validators so a draft never fails to save over a
/// value the editor happily accepted — losing the trainer's work to a 422 is
/// worse than storing a shortened note.
Map<String, Object?> programExerciseToJson(
  ProgramExerciseDraft exercise,
) => <String, Object?>{
  'id': _cap(exercise.id, 64),
  // The backend requires a name; a blank row would reject the draft.
  'name': exercise.name.trim().isEmpty ? '-' : _cap(exercise.name, _kNameMax),
  'type': kRoutineTypes.contains(exercise.type) ? exercise.type : '근력',
  'date': exercise.date == null ? null : ymd(exercise.date!),
  // 근력은 세트·횟수·중량으로만 재고 시간을 싣지 않는다 — 두 편집기와 회원
  // 기록이 같은 규칙을 쓴다 (#1276, #1310).
  // 초가 기준이고 분은 거기서 반올림한 값이다(#2221) — 분은 예전 서버와 분을
  // 더하는 집계를 위해 함께 싣는다.
  'duration': exercise.isStrength
      ? null
      : minutesFromSeconds(
          exercise.durationSeconds.clamp(0, kMaxExerciseSeconds),
        ),
  'duration_seconds': exercise.isStrength
      ? null
      : exercise.durationSeconds.clamp(0, kMaxExerciseSeconds),
  'sets': exercise.isStrength ? exercise.sets.clamp(0, 99) : null,
  // 한 세트는 회로든 초로든 한 번만 잰다 — 고르지 않은 쪽은 비운다(#1969).
  'reps': exercise.isStrength && !exercise.isHold
      ? exercise.reps.clamp(0, 999)
      : null,
  'hold_seconds': exercise.isStrength && exercise.isHold
      ? exercise.holdSeconds.clamp(1, kMaxExerciseHoldSeconds)
      : null,
  'weight': exercise.isStrength ? exercise.weight.clamp(0, 1000) : null,
  'intensity': normaliseRoutineIntensity(exercise.intensity),
  'memo': _cap(exercise.memo, _kMemoMax),
  'source': kProgramExerciseSources.contains(exercise.source)
      ? exercise.source
      : 'trainer',
};

/// `ProgramDraftExercise` JSON → [ProgramExerciseDraft].
///
/// 세트·횟수·중량·시간은 예전에 자유 문자열("10회"·"20kg")로 저장됐다 —
/// 숫자만 되짚어 읽고, 없으면 기본값으로 연다.
ProgramExerciseDraft programExerciseFromJson(Map<String, Object?> json) =>
    ProgramExerciseDraft(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '근력',
      date: DateTime.tryParse(json['date'] as String? ?? ''),
      // 초 키가 없던 예전 초안은 분 × 60 으로 열린다(#2221).
      durationSeconds:
          looseInt(json['duration_seconds']) ??
          (looseInt(json['duration']) ?? 30) * 60,
      sets: looseInt(json['sets']) ?? 3,
      reps: looseInt(json['reps']) ?? 10,
      holdSeconds: looseInt(json['hold_seconds']) ?? 60,
      // 저장된 행이 든 칸이 곧 이 운동을 재는 단위다. (#1969)
      isHold: looseInt(json['hold_seconds']) != null,
      weight: looseDouble(json['weight']) ?? 20,
      intensity: normaliseRoutineIntensity(json['intensity'] as String?),
      memo: json['memo'] as String? ?? '',
      source: json['source'] as String? ?? 'trainer',
    );

/// [ProgramSessionDraft] → `ProgramDraftSession` JSON.
Map<String, Object?> programSessionToJson(
  ProgramSessionDraft session,
) => <String, Object?>{
  'id': _cap(session.id, 64),
  'name': _cap(session.name, _kNameMax),
  'exercises': <Map<String, Object?>>[
    for (final exercise in session.exercises) programExerciseToJson(exercise),
  ],
};

/// `ProgramDraftSession` JSON → [ProgramSessionDraft].
ProgramSessionDraft programSessionFromJson(
  Map<String, Object?> json, {
  required int index,
}) => ProgramSessionDraft(
  id: json['id'] as String? ?? 'session-${index + 1}',
  name: json['name'] as String? ?? '',
  exercises: ((json['exercises'] as List<Object?>?) ?? const <Object?>[])
      .map(
        (item) => programExerciseFromJson(
          (item! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
      )
      .toList(),
);

/// [ProgramEditorState] → create/update payload.
///
/// Every session goes to the server in editor order (#709) — session order is
/// array order on both sides, so nothing has to be re-sorted on the way back.
Map<String, Object?> programDraftToJson(ProgramEditorState draft) =>
    <String, Object?>{
      'name': _cap(draft.name, _kNameMax),
      'goal': _cap(draft.goal, 200),
      'period': _cap(draft.period, _kNameMax),
      'memo': _cap(draft.memo, AppTextLimits.entry),
      'sessions': <Map<String, Object?>>[
        for (final session in draft.sessions) programSessionToJson(session),
      ],
    };

/// [ProgramEditorState] → `ProgramAssignRequest` JSON.
///
/// [clientRequestId] makes the whole program idempotent for one send attempt:
/// retrying with the same value does not assign the sessions twice (#581).
Map<String, Object?> programAssignToJson(
  ProgramEditorState draft, {
  String? clientRequestId,
}) => <String, Object?>{
  'name': _cap(draft.name, _kNameMax),
  'sessions': <Map<String, Object?>>[
    for (final session in draft.sessions) programSessionToJson(session),
  ],
  'client_request_id': ?clientRequestId,
};

/// 개인운동 목록 → `ProgramScheduleRequest.personal_routines` JSON. (#2223)
///
/// 배정 입력과 같은 규칙으로, 유형에 맞지 않는 칸은 싣지 않는다 — 세트·횟수·
/// 중량은 근력에만, 한 세트는 회로든 초로든 한 번만 잰다(#1969). 서버가 다시
/// 거르지만, 보내지 않는 편이 "무엇을 정했는지"가 그대로 남는다.
///
/// **AI 추천 사유(`reason`)는 싣지 않는다.** 그 글은 트레이너가 이 제안을
/// 그대로 둘지 판단하는 재료이지 회원이 읽을 문구가 아니다 — 회원 화면에는
/// 운동 이름·유형·양만 선다. 회원이 읽을 한 줄은 따로 `effect` 로 싣는다
/// (#2570) — 트레이너가 적은 것만 싣고, 비면 서버가 문구표로 채운다.
/// `RoutineOut` JSON → 붙어 있는 개인운동 한 줄. (#2224)
///
/// 일정 상세와 완료 확인창이 "무엇이 함께 가는지" 를 보여 주는 데 쓴다.
/// 회원에게 나가지 않는 `reason` 은 트레이너 화면에서만 읽으므로 그대로
/// 싣는다 — 왜 이 운동이 올라왔는지는 보낼지 판단하는 재료다.
RoutineExercise scheduledRoutineFromJson(Map<String, dynamic> json) {
  final int holdSeconds = (json['hold_seconds'] as num?)?.toInt() ?? 0;
  return RoutineExercise(
    name: (json['name'] as String?) ?? '',
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    type: normaliseRoutineType((json['type'] as String?) ?? ''),
    // 초 칸이 생기기 전의 배정·근력은 비어 온다 — 그때는 분으로 읽는다(#2221).
    durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
    sets: (json['sets'] as num?)?.toInt() ?? 0,
    reps: (json['reps'] as num?)?.toInt() ?? 0,
    holdSeconds: holdSeconds,
    isHold: holdSeconds > 0,
    weight: (json['weight'] as num?)?.toDouble() ?? 0,
    reason: (json['reason'] as String?) ?? '',
    source: (json['source'] as String?) ?? 'trainer',
    effect: (json['effect'] as String?) ?? '',
  );
}

List<Map<String, Object?>> personalRoutinesToJson(
  List<RoutineExercise> routines,
) {
  return <Map<String, Object?>>[
    for (final e in routines)
      <String, Object?>{
        'name': _cap(e.name, _kNameMax),
        // 초가 기준이고 분은 거기서 반올림한 값이다(#2221). 분은 예전 서버와
        // 분을 더하는 집계를 위해 함께 싣는다.
        'minutes': e.type == '근력' ? 0 : minutesFromSeconds(e.seconds),
        if (e.type != '근력') 'duration_seconds': e.seconds,
        'type': e.type,
        if (e.type == '근력' && e.sets > 0) 'sets': e.sets,
        if (e.type == '근력' && !e.isHold && e.reps > 0) 'reps': e.reps,
        if (e.type == '근력' && e.isHold && e.holdSeconds > 0)
          'hold_seconds': e.holdSeconds,
        if (e.type == '근력') 'weight': e.weight,
        'source': kProgramExerciseSources.contains(e.source)
            ? e.source
            : 'trainer',
        if (e.effect.trim().isNotEmpty)
          'effect': _cap(e.effect.trim(), kRoutineEffectMaxLength),
      },
  ];
}

/// 이미 있는 PT 에 붙은 개인운동을 고치거나 처음 붙이는 본문
/// (`PUT /trainer/schedule/{id}/routines`, #2224·#2280).
///
/// 그 개인운동을 채운 대기 중 AI 제안 id 도 싣는다(#2747) — 서버가 같은
/// 트랜잭션에서 닫는다. 일정 상세에서 고친 줄처럼 제안에서 오지 않았으면
/// 키를 싣지 않아 옛 본문과 같다.
Map<String, Object?> scheduledRoutinesUpdateToJson(
  List<RoutineExercise> items,
) {
  final List<String> suggestionIds = suggestionIdsOf(items);
  return <String, Object?>{
    'personal_routines': personalRoutinesToJson(items),
    if (suggestionIds.isNotEmpty) 'suggestion_ids': suggestionIds,
  };
}

/// `개인운동만` 전송 본문 — 운동 하나가 세션 하나다. (#2223)
///
/// 운동별로 나누는 이유는 회원이 `걷기는 했고 플랭크는 안 했다` 를 하나씩
/// 표시할 수 있어야 하기 때문이다 — 한 덩어리로 보내면 체크도 한 번뿐이다.
/// 개인운동이 하나뿐이면 배정도 한 건이라 프로그램 이름이 곧 회원이 보는
/// 제목이 되므로, 그때는 그 운동 이름을 이름으로 쓴다.
Map<String, Object?> routineOnlyAssignToJson(
  List<RoutineExercise> routines, {
  required String programName,
  required String startDate,
  required int activeDays,
  String? clientRequestId,
}) {
  final List<Map<String, Object?>> items = personalRoutinesToJson(routines);
  final List<String> suggestionIds = suggestionIdsOf(routines);
  return <String, Object?>{
    'name': routines.length == 1 ? routines.single.name : programName,
    'sessions': <Map<String, Object?>>[
      for (var index = 0; index < routines.length; index++)
        <String, Object?>{
          'id': 'routine-only-$index',
          'name': routines[index].name,
          'exercises': <Map<String, Object?>>[
            _sessionExercise(items[index], index),
          ],
        },
    ],
    'delivery_kind': 'routine_only',
    'start_date': startDate,
    'active_days': activeDays,
    'client_request_id': ?clientRequestId,
    // 개인운동을 채운 대기 중 AI 제안 — 서버가 배정과 같은 트랜잭션에서
    // 닫는다(#2747). 없으면 싣지 않아 옛 서버에도 같은 본문이 간다.
    if (suggestionIds.isNotEmpty) 'suggestion_ids': suggestionIds,
  };
}

/// 배정 항목([personalRoutinesToJson])을 세션의 운동 항목 모양으로 옮긴다.
///
/// 세션은 유형에 맞지 않는 칸도 0 으로 받는다(`ProgramDraftExercise`) — 배정
/// 입력처럼 빼 버리면 세션 요약이 값을 못 찾는다.
Map<String, Object?> _sessionExercise(Map<String, Object?> item, int index) {
  final bool strength = item['type'] == '근력';
  return <String, Object?>{
    'id': 'personal-$index',
    'name': item['name'],
    'type': item['type'],
    'duration': strength ? 0 : item['minutes'],
    'duration_seconds': strength ? null : item['duration_seconds'],
    'sets': item['sets'] ?? 0,
    'reps': item['reps'] ?? 0,
    'hold_seconds': item['hold_seconds'] ?? 0,
    'weight': item['weight'] ?? 0,
    'source': item['source'],
    'effect': ?item['effect'],
  };
}
