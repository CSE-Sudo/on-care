import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';

/// One exercise inside a [ProgramTemplate].
class TemplateExercise {
  /// Creates a template exercise.
  ///
  /// 시간은 [durationSeconds] 로 준다. 분만 아는 자리(시작 구성)는 [minutes]
  /// 를 주면 × 60 으로 채운다.
  const TemplateExercise({
    required this.name,
    required this.type,
    int minutes = 0,
    int? durationSeconds,
    this.sets = 0,
    this.reps = 0,
    this.holdSeconds = 0,
    this.weight = 0,
  }) : durationSeconds = durationSeconds ?? minutes * 60;

  /// Exercise name.
  final String name;

  /// 운동 시간(초). 편집기에서 시·분·초로 적은 그대로다 — 분으로만 담던
  /// 동안에는 `버피 45초` 가 템플릿에 `1분` 으로 남았다. (#2521)
  final int durationSeconds;

  /// [durationSeconds] 를 분으로 접은 값 — 0 이 아니면 최소 1분. 분만 받는
  /// 예전 서버를 위해 함께 싣는다.
  int get minutes => minutesFromSeconds(durationSeconds);

  /// 서버 `RoutineType` 계약값(유산소·근력·스트레칭·기타). 화면 문구는
  /// `routineTypeLabel` 이 붙인다 — 번역하면 서버가 422 를 돌려준다.
  final String type;

  /// 근력 운동에서만 쓴다(#1029, #1276, #1310) — `ProgramItem`/
  /// `ProgramExerciseDraft` 와 같은 계약(세트 수·한 세트당 횟수·중량 kg).
  /// 비근력 운동은 0 이고 [durationSeconds] 만 쓴다.
  final int sets;
  final int reps;

  /// 버티는 운동이면 한 세트를 버티는 시간(초). [reps] 와 한 자리를 나눠
  /// 쓴다 — 있으면 횟수가 0 이고, 없으면 반대다. 0 이 "적지 않음" 이다.
  /// (#1969)
  final int holdSeconds;

  final double weight;

  /// `ProgramTemplateExercise` 한 줄.
  factory TemplateExercise.fromJson(Map<String, Object?> json) =>
      TemplateExercise(
        name: json['name'] as String? ?? '',
        // 초가 없으면(칸이 생기기 전의 서버) 분 × 60 으로 읽는다.
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        type: json['type'] as String? ?? '근력',
        sets: (json['sets'] as num?)?.toInt() ?? 0,
        reps: (json['reps'] as num?)?.toInt() ?? 0,
        holdSeconds: (json['hold_seconds'] as num?)?.toInt() ?? 0,
        weight: (json['weight'] as num?)?.toDouble() ?? 0,
      );

  /// 저장 요청에 실리는 형태.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'minutes': minutes,
    'duration_seconds': durationSeconds,
    'type': type,
    'sets': sets,
    'reps': reps,
    'hold_seconds': holdSeconds,
    'weight': weight,
  };
}

/// A reusable block of exercises the trainer can drop into a routine.
///
/// The AI proposes from the client's data; templates carry the
/// trainer's own repeated patterns ("혈압 관리 기본", "하체 근력 A"). Both
/// end up in the same composed routine — applying a template appends to
/// the AI's suggestions rather than replacing them.
class ProgramTemplate {
  /// Creates a template.
  const ProgramTemplate({
    required this.id,
    required this.name,
    required this.goal,
    required this.exercises,
  });

  /// Stable id.
  final String id;

  /// Display name.
  final String name;

  /// Who it's for (e.g. 혈압 관리 · 초급).
  final String goal;

  /// The block's exercises.
  final List<TemplateExercise> exercises;

  /// 저장된 내 템플릿이 아니라 **서버가 주는 시작 구성**인가. (#920)
  ///
  /// 저장해 둔 템플릿이 하나도 없을 때만 내려온다. 고치거나 지울 대상이 아니라
  /// 화면이 그 두 동작을 내밀지 않는다 — 대신 편집하면 내 첫 템플릿으로 새로
  /// 저장된다.
  bool get isStarter => id.startsWith('starter:');

  /// 운동 시간 합(초). 목록 요약이 `45초`·`1시간 30분` 으로 읽는다. (#2521)
  int get totalSeconds =>
      exercises.fold<int>(0, (sum, e) => sum + e.durationSeconds);

  /// `TrainerProgramTemplateOut` 한 건.
  factory ProgramTemplate.fromJson(Map<String, Object?> json) =>
      ProgramTemplate(
        id: json['id']! as String,
        name: json['name'] as String? ?? '',
        goal: json['goal'] as String? ?? '',
        exercises: <TemplateExercise>[
          for (final item in (json['exercises'] as List<dynamic>? ?? const []))
            if (item is Map<String, Object?>) TemplateExercise.fromJson(item),
        ],
      );
}
