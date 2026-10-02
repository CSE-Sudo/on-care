import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';

/// A saved program draft, as listed in the program tab.
///
/// The list deliberately carries no exercises — it answers "what did I save",
/// and the editor reads the detail when the trainer opens one.
class TrainerProgramDraftSummary {
  const TrainerProgramDraftSummary({
    required this.id,
    required this.name,
    required this.goal,
    required this.period,
    required this.sessionCount,
    required this.exerciseCount,
    required this.updatedAt,
    this.memberId,
  });

  final String id;
  final String name;
  final String goal;
  final String period;
  final int sessionCount;
  final int exerciseCount;
  final DateTime updatedAt;

  /// 코칭 화면이 자동 보관한 회원(#2873). 회원 없는 초안(#708)은 비어 있다.
  final String? memberId;

  factory TrainerProgramDraftSummary.fromJson(Map<String, Object?> json) =>
      TrainerProgramDraftSummary(
        id: json['id']! as String,
        name: json['name'] as String? ?? '',
        goal: json['goal'] as String? ?? '',
        period: json['period'] as String? ?? '',
        sessionCount: (json['session_count'] as num?)?.toInt() ?? 0,
        exerciseCount: (json['exercise_count'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(json['updated_at']! as String),
        memberId: json['member_id'] as String?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'goal': goal,
    'period': period,
    'session_count': sessionCount,
    'exercise_count': exerciseCount,
    'updated_at': updatedAt.toIso8601String(),
    'member_id': memberId,
  };
}

/// A saved program draft with every session and its exercises.
///
/// Session order is array order on both sides (#709), so a reopened draft
/// renders in the order it was saved without re-sorting.
class TrainerProgramDraft {
  const TrainerProgramDraft({
    required this.id,
    required this.name,
    required this.goal,
    required this.period,
    required this.memo,
    required this.sessions,
    required this.updatedAt,
    this.memberId,
    this.workspace = const <String, Object?>{},
  });

  final String id;
  final String name;
  final String goal;
  final String period;
  final String memo;
  final List<ProgramSessionDraft> sessions;
  final DateTime updatedAt;

  /// 코칭 화면이 자동 보관한 회원(#2873). 회원 없는 초안(#708)은 비어 있다.
  final String? memberId;

  /// 편집기 밖의 작성 상태 — 위저드 단계·후보·개인운동(#2873). 서버는 해석하지
  /// 않고 그대로 돌려준다. 읽는 쪽은 `coachingWorkspaceFromJson` 이다.
  final Map<String, Object?> workspace;

  factory TrainerProgramDraft.fromJson(Map<String, Object?> json) =>
      TrainerProgramDraft(
        id: json['id']! as String,
        name: json['name'] as String? ?? '',
        goal: json['goal'] as String? ?? '',
        period: json['period'] as String? ?? '',
        memo: json['memo'] as String? ?? '',
        sessions: <ProgramSessionDraft>[
          for (final (index, item)
              in ((json['sessions'] as List<Object?>?) ?? const <Object?>[])
                  .indexed)
            programSessionFromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
              index: index,
            ),
        ],
        updatedAt: DateTime.parse(
          json['updated_at'] as String? ?? json['created_at']! as String,
        ),
        memberId: json['member_id'] as String?,
        workspace: switch (json['workspace']) {
          final Map<Object?, Object?> map => map.cast<String, Object?>(),
          _ => const <String, Object?>{},
        },
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'goal': goal,
    'period': period,
    'memo': memo,
    'sessions': sessions.map(programSessionToJson).toList(),
    'updated_at': updatedAt.toIso8601String(),
    'member_id': memberId,
    'workspace': workspace,
  };

  /// Rebuilds the editor state so a reopened draft renders exactly as it was
  /// saved — session order, session names, and which items came from the AI.
  ///
  /// A draft saved with no sessions at all still opens with one empty session:
  /// the editor has no representation for "no sessions" and would crash on
  /// `sessions.first`.
  ProgramEditorState toEditorState({required String fallbackSessionName}) =>
      ProgramEditorState(
        name: name,
        goal: goal,
        period: period,
        memo: memo,
        sessions: sessions.isEmpty
            ? <ProgramSessionDraft>[
                ProgramSessionDraft(
                  id: 'session-1',
                  name: fallbackSessionName,
                  exercises: const <ProgramExerciseDraft>[],
                ),
              ]
            : <ProgramSessionDraft>[
                for (final (index, session) in sessions.indexed)
                  ProgramSessionDraft(
                    id: session.id,
                    name: session.name.isEmpty
                        ? '$fallbackSessionName ${index + 1}'
                        : session.name,
                    exercises: session.exercises,
                  ),
              ],
      );
}
