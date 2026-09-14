import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';

/// 한 프로그램의 세션 수 상한 — 서버 `_PROGRAM_MAX_SESSIONS` 와 같다(#1583).
const int kProgramMaxSessions = 12;

/// 한 프로그램 전체의 운동 수 상한 — 서버 `_PROGRAM_MAX_TOTAL_EXERCISES` 와
/// 같다(#1583). 초안 저장·배정·일정 추가가 모두 이 크기까지만 받으므로, 편집기가
/// 같은 상한을 지켜야 배정은 되고 일정만 422 가 되는 경로가 없다.
const int kProgramMaxExercises = 30;

/// `일정 추가` 를 막는 초안 쪽 이유. 버튼 안내가 실제 검사와 같은 조건을
/// 말하게 한다(#1582) — 날짜·시간은 편집기 하단 값이라 여기 없다.
enum ProgramAssignmentBlocker { noExercises, invalidExerciseName, sizeExceeded }

/// Frontend-only draft for the Figma multi-session program editor.
///
/// This deliberately does not implement or extend [AssignedRoutine]: the
/// current backend routine contract is flat and cannot safely persist these
/// fields. A future Program DTO should map to this state explicitly.
class ProgramEditorState {
  const ProgramEditorState({
    required this.name,
    this.goal = '',
    this.period = '',
    this.memo = '',
    required this.sessions,
  });

  final String name;
  final String goal;
  final String period;
  final String memo;
  final List<ProgramSessionDraft> sessions;

  /// 프로그램 전체의 운동 수.
  int get exerciseCount => sessions.fold<int>(
    0,
    (count, session) => count + session.exercises.length,
  );

  /// 세션을 하나 더 추가할 수 있는가(#1583).
  bool get canAddSession => sessions.length < kProgramMaxSessions;

  /// 운동을 하나 더 추가할 수 있는가(#1583).
  bool get canAddExercise => exerciseCount < kProgramMaxExercises;

  /// 서버가 받는 크기를 넘었는가 — 템플릿·AI 제안을 합쳐 넘을 수 있다. 자르지
  /// 않고 트레이너가 직접 줄이게 둔다(#1583).
  bool get exceedsSizeLimit =>
      sessions.length > kProgramMaxSessions ||
      exerciseCount > kProgramMaxExercises;

  /// Whether this draft can be assigned to a member or put on the schedule.
  ///
  /// 세션 수·운동 수는 서버와 같은 상한 안이어야 한다(#1583). 숫자 칸은
  /// 스테퍼가 이미 범위 안으로 묶어 두므로(#1276) 그 밖에 볼 것은 이름이다.
  bool get supportsAssignment => assignmentBlocker == null;

  /// 일정 추가를 막는 첫 번째 이유. 보낼 수 있으면 null.
  ProgramAssignmentBlocker? get assignmentBlocker {
    if (exceedsSizeLimit) return ProgramAssignmentBlocker.sizeExceeded;
    final exercises = <ProgramExerciseDraft>[
      for (final session in sessions) ...session.exercises,
    ];
    if (exercises.isEmpty) return ProgramAssignmentBlocker.noExercises;
    final namesValid = exercises.every((ProgramExerciseDraft e) {
      final int length = e.name.trim().length;
      return length >= 1 && length <= 100;
    });
    return namesValid ? null : ProgramAssignmentBlocker.invalidExerciseName;
  }

  ProgramEditorState copyWith({
    String? name,
    String? goal,
    String? period,
    String? memo,
    List<ProgramSessionDraft>? sessions,
  }) => ProgramEditorState(
    name: name ?? this.name,
    goal: goal ?? this.goal,
    period: period ?? this.period,
    memo: memo ?? this.memo,
    sessions: sessions ?? this.sessions,
  );

  factory ProgramEditorState.initial({
    required String clientGoal,
    required String programName,
    required String sessionName,
  }) => ProgramEditorState(
    name: programName,
    goal: clientGoal,
    sessions: <ProgramSessionDraft>[
      ProgramSessionDraft(
        id: 'session-1',
        name: sessionName,
        exercises: const [],
      ),
    ],
  );
}

class ProgramSessionDraft {
  const ProgramSessionDraft({
    required this.id,
    required this.name,
    required this.exercises,
  });

  final String id;
  final String name;
  final List<ProgramExerciseDraft> exercises;

  ProgramSessionDraft copyWith({
    String? name,
    List<ProgramExerciseDraft>? exercises,
  }) => ProgramSessionDraft(
    id: id,
    name: name ?? this.name,
    exercises: exercises ?? this.exercises,
  );
}

/// 편집기의 운동 한 항목.
///
/// 회원 앱의 운동 추가 시트와 같은 칸을 받는다(#1276) — 날짜·종류·이름·
/// 시간(또는 세트·횟수·중량)·강도. 예전에는 세트·횟수·중량·시간·거리·휴식·
/// RPE 가 전부 자유 문자열이라 같은 운동이 화면마다 다른 모양으로 저장됐고,
/// 회원 기록과 나란히 집계할 수가 없었다. 통일 스펙에 없는 거리·휴식·RPE 는
/// 뺐다 — 강도가 RPE 자리를 대신한다. 횟수는 한때 같이 뺐다가 되살렸다
/// (#1310) — 세트·중량만으로는 근력 한 줄이 재현되지 않는다.
class ProgramExerciseDraft {
  const ProgramExerciseDraft({
    required this.id,
    required this.name,
    this.type = '근력',
    this.date,
    this.minutes = 30,
    this.sets = 3,
    this.reps = 10,
    this.weight = 20,
    this.intensity = 'moderate',
    this.memo = '',
    this.source = 'trainer',
    this.templateName,
  });

  final String id;
  final String name;
  final String type;

  /// 이 운동을 하는 날. 아직 정하지 않았으면 null.
  final DateTime? date;

  /// 유산소·스트레칭·기타의 운동 시간(분). 근력은 세트로 재므로 쓰지 않는다.
  final int minutes;

  /// 근력의 세트 수·한 세트당 횟수·중량(kg). 시간과 따로 들고 있어야 유형을
  /// 오갈 때 각자의 값이 남는다 — 하나로 쓰면 30분이 30세트가 되어 돌아온다.
  final int sets;
  final int reps;
  final double weight;

  /// 운동 강도 계약값('light'|'moderate'|'high').
  final String intensity;

  final String memo;

  /// 지금 고른 유형이 근력인가.
  bool get isStrength => type == '근력';

  /// 저장·칼로리 계산이 쓰는 분. 근력이면 세트에서 환산한 값이다 — 서버는
  /// 여전히 분을 요구하고 주간 운동 시간도 분으로 센다.
  int get effectiveMinutes => isStrength ? minutesFromSets(sets) : minutes;

  /// 예상 소모 칼로리 — 세 유형을 한 축에서 견주는 값이다. 운동 이름이 비어
  /// 있으면 null 이다(#1312).
  RoutineCalorieEstimate? get calories => estimateRoutineCalories(
    name: name,
    type: type,
    minutes: effectiveMinutes,
    intensity: intensity,
  );

  /// `ai` | `trainer` — 서버가 받는 계약값이다(`kProgramExerciseSources`).
  /// 화면 표시는 [templateName] 이 있으면 그쪽을 우선한다.
  final String source;

  /// 이 운동을 끌어온 템플릿 이름(#1029) — 있으면 출처 배지가 `트레이너
  /// 추가` 대신 `$templateName 템플릿 추가` 를 보여 준다. 화면 전용 값이라
  /// [source] 는 그대로 `trainer` 로 남고, 배정 payload
  /// (`programExerciseToJson`) 는 이 필드를 읽지 않는다 — 서버 계약을 넓히지
  /// 않는다.
  final String? templateName;

  ProgramExerciseDraft copyWith({
    String? name,
    String? type,
    DateTime? date,
    int? minutes,
    int? sets,
    int? reps,
    double? weight,
    String? intensity,
    String? memo,
    String? source,
    String? templateName,
  }) => ProgramExerciseDraft(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    date: date ?? this.date,
    minutes: minutes ?? this.minutes,
    sets: sets ?? this.sets,
    reps: reps ?? this.reps,
    weight: weight ?? this.weight,
    intensity: intensity ?? this.intensity,
    memo: memo ?? this.memo,
    source: source ?? this.source,
    templateName: templateName ?? this.templateName,
  );
}
