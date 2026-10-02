import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/coaching_workspace_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_options_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/coaching_workspace_draft.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/trainer_program_draft.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';

const String _member = 'member-1';

RoutineOptions _options() => routineOptionsFromJson(<String, Object?>{
  'analysis': <String, Object?>{
    'goal': '혈압 관리',
    'sodium_today_mg': 2100,
    'sodium_over_target': true,
    'avg_completion_rate': 55,
    'latest_routine': '걷기',
    'note': '무릎 주의',
    'frequent_exercises': <Object?>['걷기'],
    'suggested_available_minutes': 40,
  },
  'plan_a': <String, Object?>{
    'key': 'A',
    'label': '회복·지속 중심',
    'total_minutes': 21,
    'intensity': '낮음',
    'exercises': <Object?>[
      <String, Object?>{'name': '저강도 걷기', 'minutes': 13, 'type': '유산소'},
    ],
    'reason': '지속 중심',
    'rationale': '오늘 나트륨 2100mg',
  },
  'plan_b': <String, Object?>{
    'key': 'B',
    'label': '강도·운동량 중심',
    'total_minutes': 30,
    'intensity': '높음',
    'exercises': <Object?>[
      <String, Object?>{'name': '인터벌 러닝', 'minutes': 30, 'type': '유산소'},
    ],
    'reason': '강도 상향',
    'rationale': '목표 기준',
  },
  'generated_by': 'ai',
});

const RoutineExercise _squat = RoutineExercise(
  name: '스쿼트',
  minutes: 10,
  type: '근력',
  durationSeconds: 600,
  sets: 4,
  reps: 12,
  weight: 20.5,
  source: 'ai',
  effect: '하체 근력',
);

const RoutineExercise _plank = RoutineExercise(
  name: '플랭크',
  minutes: 1,
  type: '근력',
  sets: 3,
  holdSeconds: 45,
  isHold: true,
  reason: '코어',
  suggestionId: 'sugg-1',
);

AiRoutineWizardSnapshot _wizard() => AiRoutineWizardSnapshot(
  stage: 2,
  maxReachedStage: 3,
  routineOnly: false,
  selectedKey: 'B',
  edited: const <RoutineExercise>[_squat],
  personal: const <RoutineExercise>[_plank],
  personalSeeded: true,
  options: _options(),
  prompt: '하체 부담 적게',
  trainerMemo: '무릎 상태 확인',
  minutes: 40,
  intensity: 'high',
  minutesTouched: true,
  intensityTouched: true,
  measureChosen: const <int>{0},
  personalMeasureChosen: const <int>{0, 2},
);

ProgramEditorState _editor() => const ProgramEditorState(
  name: '하체 프로그램',
  goal: '근력',
  memo: '회원에게 보낼 메모',
  sessions: <ProgramSessionDraft>[
    ProgramSessionDraft(
      id: 'session-1',
      name: '근력 세션',
      exercises: <ProgramExerciseDraft>[
        ProgramExerciseDraft(id: 'exercise-1', name: '레그프레스', sets: 5),
      ],
    ),
  ],
);

/// 저장소를 한 번 지난 모양 — 브라우저 저장소·서버 모두 JSON 으로 돌아온다.
TrainerProgramDraft _stored(
  Map<String, Object?> payload, {
  String? memberId = _member,
}) {
  final Map<String, Object?> json =
      (jsonDecode(
                jsonEncode(<String, Object?>{
                  ...payload,
                  'id': 'pgm-1',
                  'member_id': memberId,
                  'updated_at': '2026-10-02T09:00:00Z',
                }),
              )
              as Map<Object?, Object?>)
          .cast<String, Object?>();
  return TrainerProgramDraft.fromJson(json);
}

/// 코칭 화면 작성 상태의 저장 형식 (#2873).
///
/// 새로 고침 뒤 `이어서 쓰기` 가 같은 단계·같은 후보·같은 입력을 세우려면,
/// 화면이 들고 있던 값이 저장소를 한 번 지나도 하나도 빠지지 않아야 한다.
void main() {
  test('편집기·위저드·개인운동이 저장소를 지나도 그대로 돌아온다', () {
    final CoachingWorkspaceDraft draft = CoachingWorkspaceDraft(
      memberId: _member,
      phase: CoachingWorkspacePhase.editor,
      editor: _editor(),
      wizard: _wizard(),
      personalRoutines: const <RoutineExercise>[_plank],
      routineOnly: true,
      routineOnlyStart: DateTime(2026, 10, 5),
    );

    final CoachingWorkspaceDraft? back = coachingWorkspaceFromDraft(
      _stored(coachingDraftPayload(draft, fallbackName: '기본 이름')),
      fallbackSessionName: '세션',
    );

    expect(back, isNotNull);
    expect(back!.memberId, _member);
    expect(back.phase, CoachingWorkspacePhase.editor);
    expect(back.routineOnly, isTrue);
    expect(back.routineOnlyStart, DateTime(2026, 10, 5));
    expect(back.hasContent, isTrue);

    final ProgramEditorState editor = back.editor!;
    expect(editor.name, '하체 프로그램');
    expect(editor.memo, '회원에게 보낼 메모');
    expect(editor.sessions.single.name, '근력 세션');
    expect(editor.sessions.single.exercises.single.name, '레그프레스');
    expect(editor.sessions.single.exercises.single.sets, 5);

    final RoutineExercise personal = back.personalRoutines.single;
    expect(personal.name, '플랭크');
    expect(personal.isHold, isTrue);
    expect(personal.holdSeconds, 45);
    expect(personal.suggestionId, 'sugg-1');
  });

  test('위저드의 단계·후보·입력이 그대로 돌아온다', () {
    final CoachingWorkspaceDraft? back = coachingWorkspaceFromDraft(
      _stored(
        coachingDraftPayload(
          CoachingWorkspaceDraft(
            memberId: _member,
            phase: CoachingWorkspacePhase.wizard,
            wizard: _wizard(),
          ),
          fallbackName: '기본 이름',
        ),
      ),
      fallbackSessionName: '세션',
    );

    final AiRoutineWizardSnapshot w = back!.wizard!;
    expect(back.phase, CoachingWorkspacePhase.wizard);
    expect(w.stage, 2);
    expect(w.maxReachedStage, 3);
    expect(w.selectedKey, 'B');
    expect(w.personalSeeded, isTrue);
    expect(w.prompt, '하체 부담 적게');
    expect(w.trainerMemo, '무릎 상태 확인');
    expect(w.minutes, 40);
    expect(w.intensity, 'high');
    expect(w.minutesTouched, isTrue);
    expect(w.intensityTouched, isTrue);
    expect(w.measureChosen, <int>{0});
    expect(w.personalMeasureChosen, <int>{0, 2});

    final RoutineExercise edited = w.edited.single;
    expect(edited.name, '스쿼트');
    expect(edited.durationSeconds, 600);
    expect(edited.sets, 4);
    expect(edited.reps, 12);
    expect(edited.weight, 20.5);
    expect(edited.source, 'ai');
    expect(edited.effect, '하체 근력');

    // 받은 후보는 다시 부르지 않고 그대로 선다.
    final RoutineOptions options = w.options!;
    expect(options.analysis.goal, '혈압 관리');
    expect(options.analysis.frequentExercises, <String>['걷기']);
    expect(options.analysis.suggestedAvailableMinutes, 40);
    expect(options.planA.exercises.single.name, '저강도 걷기');
    expect(options.planB.totalMinutes, 30);
    expect(options.generatedBy, 'ai');
  });

  test('편집기에 가기 전이면 빈 세션과 기본 이름을 싣고 편집기는 되살리지 않는다', () {
    final Map<String, Object?> payload = coachingDraftPayload(
      CoachingWorkspaceDraft(
        memberId: _member,
        phase: CoachingWorkspacePhase.wizard,
        wizard: _wizard(),
      ),
      fallbackName: '체중 감량 프로그램',
    );

    // 서버는 이름 없는 초안을 받지 않는다.
    expect(payload['name'], '체중 감량 프로그램');
    expect(payload['sessions'], isEmpty);
    // 회원은 처음 만들 때 저장소가 붙인다 — 수정 본문에는 싣지 않는다.
    expect(payload.containsKey('member_id'), isFalse);

    final CoachingWorkspaceDraft? back = coachingWorkspaceFromDraft(
      _stored(payload),
      fallbackSessionName: '세션',
    );
    expect(back!.editor, isNull);
  });

  test('편집기의 이름을 비웠으면 기본 이름으로 싣는다', () {
    final Map<String, Object?> payload = coachingDraftPayload(
      const CoachingWorkspaceDraft(
        memberId: _member,
        phase: CoachingWorkspacePhase.editor,
        editor: ProgramEditorState(
          name: '',
          sessions: <ProgramSessionDraft>[
            ProgramSessionDraft(
              id: 'session-1',
              name: '세션 A',
              exercises: <ProgramExerciseDraft>[],
            ),
          ],
        ),
      ),
      fallbackName: '기본 이름',
    );

    expect(payload['name'], '기본 이름');
  });

  test('회원 없는 초안·모르는 판·망가진 작성 상태는 읽지 않는다', () {
    final Map<String, Object?> payload = coachingDraftPayload(
      CoachingWorkspaceDraft(
        memberId: _member,
        phase: CoachingWorkspacePhase.wizard,
        wizard: _wizard(),
      ),
      fallbackName: '기본 이름',
    );

    expect(
      coachingWorkspaceFromDraft(
        _stored(payload, memberId: null),
        fallbackSessionName: '세션',
      ),
      isNull,
    );

    final Map<String, Object?> workspace =
        payload['workspace']! as Map<String, Object?>;
    expect(
      coachingWorkspaceFromDraft(
        _stored(<String, Object?>{
          ...payload,
          'workspace': <String, Object?>{
            ...workspace,
            'version': kCoachingWorkspaceVersion + 1,
          },
        }),
        fallbackSessionName: '세션',
      ),
      isNull,
    );

    // 후보 모양이 깨졌으면 화면을 멈추지 않고 없는 것으로 본다.
    expect(
      coachingWorkspaceFromDraft(
        _stored(<String, Object?>{
          ...payload,
          'workspace': <String, Object?>{
            ...workspace,
            'wizard': <String, Object?>{
              'stage': 1,
              'options': <String, Object?>{'plan_a': 'broken'},
            },
          },
        }),
        fallbackSessionName: '세션',
      ),
      isNull,
    );
  });

  test('되살릴 것이 없으면 내용 없음으로 본다', () {
    const CoachingWorkspaceDraft empty = CoachingWorkspaceDraft(
      memberId: _member,
      phase: CoachingWorkspacePhase.wizard,
      wizard: AiRoutineWizardSnapshot(
        stage: 0,
        maxReachedStage: 0,
        routineOnly: false,
        selectedKey: 'A',
        edited: <RoutineExercise>[],
        personal: <RoutineExercise>[],
        personalSeeded: false,
        prompt: '조건 칸만 만졌다',
      ),
    );

    expect(empty.hasContent, isFalse);
  });
}
