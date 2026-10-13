import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';

/// 코칭 화면에서 한 회원에게 짜던 작성 내용 — 자동 보관과 `이어서 쓰기` 의
/// 단위다. (#2873)
///
/// 편집기 구성([editor])은 프로그램 초안의 원래 칸(이름·목표·기간·메모·세션)에
/// 그대로 담기고, 나머지(어느 화면에 있었는지·위저드·개인운동)는 초안의
/// `workspace` 객체에 담긴다. 화면이 쓰고 화면이 읽는 값이라 서버는 해석하지
/// 않는다.
class CoachingWorkspaceDraft {
  const CoachingWorkspaceDraft({
    required this.memberId,
    required this.phase,
    this.editor,
    this.wizard,
    this.personalRoutines = const <RoutineExercise>[],
    this.routineOnly = false,
    this.routineOnlyStart,
    this.scheduleNote = '',
  });

  final String memberId;

  /// 떠날 때 보고 있던 자리 — 위저드인지 편집기인지.
  final CoachingWorkspacePhase phase;

  /// 편집기 구성. 위저드에서 반영하기 전이면 없다.
  final ProgramEditorState? editor;

  /// 위저드의 단계·후보·입력. 후보를 받기 전이면 없다.
  final AiRoutineWizardSnapshot? wizard;

  /// 위저드의 개인운동 단계에서 정한, 함께 보낼 개인운동.
  final List<RoutineExercise> personalRoutines;

  /// `개인운동만` 으로 짜던 회원인가.
  final bool routineOnly;

  /// `개인운동만` 의 시작일.
  final DateTime? routineOnlyStart;

  /// 편집기 하단에 쓴, 이 PT 의 트레이너 피드백(#2374). `일정 추가` 가 일정의
  /// `note` 로 함께 보낸다.
  final String scheduleNote;

  /// 되살릴 것이 있는가 — 비어 있는 초안은 묻지 않고 지운다.
  bool get hasContent =>
      editor != null ||
      (wizard?.hasWork ?? false) ||
      personalRoutines.isNotEmpty;
}

/// 코칭 화면의 두 자리. (#2873)
enum CoachingWorkspacePhase {
  /// AI 1~4 단계.
  wizard,

  /// 프로그램 편집기(또는 `개인운동만` 박스).
  editor,
}

/// AI 루틴 위저드의 작성 상태. (#2873)
///
/// 새로 고침 뒤 `이어서 쓰기` 로 같은 단계·같은 후보·같은 입력으로 다시 연다.
/// 후보를 새로 만들지 않는다 — 다시 부르면 다른 후보가 오고, 트레이너가 고친
/// 것이 사라진다.
class AiRoutineWizardSnapshot {
  const AiRoutineWizardSnapshot({
    required this.stage,
    required this.maxReachedStage,
    required this.routineOnly,
    required this.selectedKey,
    required this.edited,
    required this.personal,
    required this.personalSeeded,
    this.options,
    this.prompt = '',
    this.minutes = 30,
    this.intensity = 'moderate',
    this.minutesTouched = false,
    this.intensityTouched = false,
    this.measureChosen = const <int>{},
    this.personalMeasureChosen = const <int>{},
  });

  /// 단계 번호(위저드의 단계 표시줄 순서).
  final int stage;
  final int maxReachedStage;

  /// `개인운동만 짜기` 를 골랐는가.
  final bool routineOnly;

  /// 고른 후보(`A`·`B`·기존 추천).
  final String selectedKey;

  /// 고르고 고친 PT 프로그램 후보.
  final List<RoutineExercise> edited;

  /// 개인운동 단계의 목록. 줄마다 채운 AI 제안 id 가 따라간다.
  final List<RoutineExercise> personal;

  /// AI 제안을 개인운동 목록에 이미 채웠는가 — 되살린 뒤 다시 채우면 트레이너가
  /// 뺀 제안이 돌아온다.
  final bool personalSeeded;

  /// 받은 A/B 후보와 분석. 받기 전이면 없다.
  final RoutineOptions? options;

  /// 조건 설정의 자연어 요청.
  ///
  /// 회원에게 전할 피드백은 위저드에 없다 — 편집기 하단에서 `일정 추가` 와 함께
  /// 쓴다(#2374, [CoachingWorkspaceDraft.scheduleNote]).
  final String prompt;

  final int minutes;
  final String intensity;
  final bool minutesTouched;
  final bool intensityTouched;

  /// 회↔초를 직접 고른 줄 번호.
  final Set<int> measureChosen;
  final Set<int> personalMeasureChosen;

  /// 보관할 만한 작성 내용인가 — 후보를 받았거나, `개인운동만` 으로 개인운동을
  /// 짜고 있다. 조건 칸만 만진 상태는 다시 누르면 되므로 보관하지 않는다.
  bool get hasWork => options != null || (routineOnly && personal.isNotEmpty);
}
