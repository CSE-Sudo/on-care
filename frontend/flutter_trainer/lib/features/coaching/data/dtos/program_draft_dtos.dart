import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/shared/exercise_limits.dart';

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
  'duration': exercise.isStrength ? null : exercise.minutes.clamp(0, 600),
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
      minutes: looseInt(json['duration']) ?? 30,
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
      'memo': _cap(draft.memo, 2000),
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
