import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/shared/widgets/action_button.dart';

import '../../helpers/pump_app.dart';

/// 검토 호출을 기록하는 가짜 저장소. 지연을 둘 수 있어 '처리 중 두 번 클릭'을
/// 재현한다.
class _FakeSuggestionRepository implements TrainerRoutineSuggestionRepository {
  _FakeSuggestionRepository({
    required this.byMember,
    this.delay = Duration.zero,
    this.alreadyReviewed = false,
  });

  /// 회원별 검토 대기 목록. 검토한 것은 여기서 지운다.
  final Map<String, List<RoutineSuggestion>> byMember;

  /// 검토 호출을 붙잡아 두는 시간. 0 이면 곧바로 끝난다.
  final Duration delay;

  /// true 면 모든 검토가 409(이미 검토됨)로 끝난다.
  final bool alreadyReviewed;

  final List<String> approvals = <String>[];
  final List<Map<String, Object?>> approvalEdits = <Map<String, Object?>>[];
  final List<String> dismissals = <String>[];
  final List<String> reads = <String>[];

  @override
  Future<List<RoutineSuggestion>> pending(String memberId) async {
    reads.add(memberId);
    return byMember[memberId] ?? const <RoutineSuggestion>[];
  }

  @override
  Future<void> approve(
    String suggestionId, {
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    double? weight,
    String? reason,
  }) async {
    approvals.add(suggestionId);
    approvalEdits.add(<String, Object?>{
      'name': name,
      'minutes': minutes,
      'type': type,
      'sets': sets,
      'reps': reps,
      'weight': weight,
      'reason': reason,
    });
    await Future<void>.delayed(delay);
    if (alreadyReviewed) throw RoutineSuggestionAlreadyReviewed(suggestionId);
    _remove(suggestionId);
  }

  @override
  Future<void> dismiss(String suggestionId) async {
    dismissals.add(suggestionId);
    await Future<void>.delayed(delay);
    if (alreadyReviewed) throw RoutineSuggestionAlreadyReviewed(suggestionId);
    _remove(suggestionId);
  }

  void _remove(String suggestionId) {
    for (final list in byMember.values) {
      list.removeWhere((s) => s.id == suggestionId);
    }
  }
}

// 검토 대기 후보의 이름은 **이미 배정된 개인 운동과 겹치지 않아야** 한다
// (#1170). 같은 화면 위쪽의 `배정된 개인 운동` 목록에도 같은 이름이 있으면
// `find.text` 가 둘을 잡아, 이 테스트가 무엇을 보고 있는지 알 수 없다.
const RoutineSuggestion _shoulder = RoutineSuggestion(
  id: 's-shoulder',
  name: '흉추 회전 스트레칭',
  minutes: 8,
  type: '스트레칭',
  reason: '회전근개와 어깨 안정화를 돕는 스트레칭이에요',
  evidence: <String>['최근 PT 피드백 반영'],
);

const RoutineSuggestion _walking = RoutineSuggestion(
  id: 's-walking',
  name: '회복 목적 걷기',
  minutes: 20,
  type: '유산소',
  reason: '대화할 수 있는 속도로 걸어 보세요',
  evidence: <String>['혈압 관리 목표'],
);

/// 근력 제안 — 시간이 아니라 세트·횟수·중량으로 재는 것 (#1321).
const RoutineSuggestion _bridge = RoutineSuggestion(
  id: 's-bridge',
  name: '힙 브리지',
  minutes: 12,
  type: '근력',
  sets: 3,
  reps: 15,
  weight: 0,
  reason: '허리가 아프면 범위를 줄이세요',
  evidence: <String>['최근 근력운동 비중 높음'],
);

void main() {
  /// 첫 시드 회원과 그 다음 회원 — 회원 전환 테스트가 두 명을 쓴다.
  const String firstClient = 'seed-client-1';
  const String secondClient = 'seed-client-2';

  Future<_FakeSuggestionRepository> openProgramTab(
    WidgetTester tester, {
    Map<String, List<RoutineSuggestion>>? byMember,
    Duration delay = Duration.zero,
    bool alreadyReviewed = false,
  }) async {
    final repo = _FakeSuggestionRepository(
      byMember:
          byMember ??
          <String, List<RoutineSuggestion>>{
            firstClient: <RoutineSuggestion>[_shoulder, _walking],
          },
      delay: delay,
      alreadyReviewed: alreadyReviewed,
    );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.coaching,
      extraOverrides: <Override>[
        trainerRoutineSuggestionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();
    return repo;
  }

  Finder approveButton(RoutineSuggestion s) =>
      find.byKey(ValueKey<String>('routine-suggestion-approve-${s.id}'));

  /// 추천은 최종 검토 dialog 를 지나야 나간다 (#1028) — `회원에게 추천` 을 누르면
  /// 나갈 내용이 먼저 뜨고, 거기서 확인해야 실제 mutation 이 일어난다.
  Future<void> confirmApprove(
    WidgetTester tester,
    RoutineSuggestion s, {
    bool settle = true,
  }) async {
    // AI 개인운동 제안 카드는 오른쪽 회원 데이터 열 안에 있어(#1028 후속)
    // 좁은 뷰포트에서는 스크롤해야 보인다.
    await tester.ensureVisible(approveButton(s));
    await tester.pump();
    await tester.tap(approveButton(s));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('suggestion-confirm-submit')),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Finder dismissButton(RoutineSuggestion s) =>
      find.byKey(ValueKey<String>('routine-suggestion-dismiss-${s.id}'));
  Finder editButton(RoutineSuggestion s) =>
      find.byKey(ValueKey<String>('routine-suggestion-edit-${s.id}'));

  group('동작 버튼의 생김새와 자리 (#939)', () {
    testWidgets('수정·거절은 이름 줄 오른쪽 끝의 아이콘 버튼이다', (tester) async {
      await openProgramTab(tester);

      // 판단이 아니라 보조 동작이다. 아래 줄에 세워 두면 `회원에게 추천` 과
      // 함께 판단처럼 읽힌다.
      final IconButton edit = tester.widget<IconButton>(editButton(_shoulder));
      expect((edit.icon as Icon).icon, Icons.edit_outlined);
      expect(edit.color, AppColors.primary);

      final IconButton dismiss = tester.widget<IconButton>(
        dismissButton(_shoulder),
      );
      expect((dismiss.icon as Icon).icon, Icons.delete_outline);
      expect(dismiss.color, AppColors.mutedForeground);

      // 손볼 대상(운동 이름·시간) 옆에 있다 — 아래 판단 줄이 아니다.
      final Rect editRect = tester.getRect(editButton(_shoulder));
      final Rect dismissRect = tester.getRect(dismissButton(_shoulder));
      final Rect nameRect = tester.getRect(find.textContaining(_shoulder.name));
      final Rect approveRect = tester.getRect(approveButton(_shoulder));
      expect(editRect.left, greaterThan(nameRect.right));
      expect(dismissRect.left, greaterThan(editRect.right));
      expect(editRect.center.dy, lessThan(approveRect.top));
      expect(dismissRect.center.dy, lessThan(approveRect.top));
    });

    testWidgets('아래 줄에는 판단 하나만 남는다', (tester) async {
      await openProgramTab(tester);

      // 카드 하나에 결정 하나 — 회원에게 추천. 거절은 위의 휴지통으로 옮겼다.
      expect(find.text('추천 안 함'), findsNothing);
      expect(find.text('회원에게 추천'), findsNWidgets(2));
      // `고객` 은 이 화면의 다른 문구(`회원 관리` 등)와 어긋난다.
      expect(find.text('고객에게 추천'), findsNothing);
    });

    testWidgets('검토 중에는 세 동작이 모두 잠긴다', (tester) async {
      await openProgramTab(tester, delay: const Duration(milliseconds: 300));

      await confirmApprove(tester, _shoulder, settle: false);

      expect(
        tester.widget<IconButton>(editButton(_shoulder)).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(dismissButton(_shoulder)).onPressed,
        isNull,
      );
      expect(
        tester.widget<ActionButton>(approveButton(_shoulder)).onPressed,
        isNull,
      );
      await tester.pumpAndSettle();
    });
  });

  testWidgets('pending suggestions show what they are and why', (tester) async {
    await openProgramTab(tester);

    expect(find.text('AI 개인운동 제안'), findsOneWidget);
    expect(find.textContaining(_shoulder.name), findsOneWidget);
    expect(find.textContaining('8분'), findsWidgets);
    expect(find.text(_shoulder.reason), findsOneWidget);
    // 근거가 함께 있어야 트레이너가 승인 여부를 판단할 수 있다.
    expect(find.text('최근 PT 피드백 반영'), findsOneWidget);
    // 검토 필요 건수.
    expect(find.text('검토 필요 2'), findsOneWidget);

    final surface = tester.widget<Container>(
      find.byKey(
        const ValueKey<String>('routine-suggestion-surface-s-shoulder'),
      ),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.card);
    expect((decoration.border! as Border).top.color, AppColors.borderStrong);
  });

  testWidgets(
    'the review area sits in the right client-data column, separate from '
    'the program editor (#1028 후속)',
    (tester) async {
      await openProgramTab(tester);

      final manual = find.byKey(const ValueKey<String>('ai-manual-create'));
      await tester.ensureVisible(manual);
      await tester.pump();
      await tester.tap(manual);
      await tester.pumpAndSettle();

      final review = tester.getTopLeft(
        find.byKey(const ValueKey<String>('routine-suggestion-review-card')),
      );
      final editor = tester.getTopLeft(find.byType(ProgramEditorWorkspace));

      // 정규 프로그램과 개인운동은 목적이 다르다 — 편집기 열에 섞이지 않고
      // 오른쪽 회원 데이터 열의 작은 카드로 따로 선다.
      expect(review.dx, greaterThan(editor.dx));
    },
  );

  testWidgets('approving sends it to the member and clears the card', (
    tester,
  ) async {
    final repo = await openProgramTab(tester);

    await confirmApprove(tester, _shoulder);

    expect(repo.approvals, <String>[_shoulder.id]);
    // 그대로 승인이므로 고친 값은 없다.
    expect(repo.approvalEdits.single.values.every((v) => v == null), isTrue);
    expect(find.text(_shoulder.name), findsNothing);
    expect(find.textContaining('추천했어요'), findsOneWidget);
    expect(find.text('검토 필요 1'), findsOneWidget);
  });

  testWidgets('dismissing keeps it away from the member', (tester) async {
    final repo = await openProgramTab(tester);

    await tester.ensureVisible(dismissButton(_walking));
    await tester.pump();
    await tester.tap(dismissButton(_walking));
    await tester.pumpAndSettle();

    expect(repo.dismissals, <String>[_walking.id]);
    expect(repo.approvals, isEmpty);
    expect(find.text(_walking.name), findsNothing);
    expect(find.textContaining('추천하지 않아요'), findsOneWidget);
  });

  testWidgets('editing then recommending sends the edited values', (
    tester,
  ) async {
    final repo = await openProgramTab(tester);

    await tester.ensureVisible(editButton(_shoulder));
    await tester.pump();
    await tester.tap(editButton(_shoulder));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('suggestion-edit-name')),
      '어깨 회복 스트레칭',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('suggestion-edit-memo')),
      '오른쪽 어깨에 통증이 생기면 중단하세요',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('suggestion-edit-type-스트레칭')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('suggestion-edit-submit')),
    );
    await tester.pumpAndSettle();

    expect(repo.approvals, <String>[_shoulder.id]);
    final edit = repo.approvalEdits.single;
    expect(edit['name'], '어깨 회복 스트레칭');
    expect(edit['reason'], '오른쪽 어깨에 통증이 생기면 중단하세요');
    expect(edit['type'], '스트레칭');
    expect(edit['minutes'], _shoulder.minutes);
  });

  testWidgets('근력 제안은 시간 대신 세트·횟수·중량을 묻는다 (#1321)', (tester) async {
    final repo = await openProgramTab(
      tester,
      byMember: <String, List<RoutineSuggestion>>{
        firstClient: <RoutineSuggestion>[_bridge],
      },
    );

    await tester.ensureVisible(editButton(_bridge));
    await tester.pump();
    await tester.tap(editButton(_bridge));
    await tester.pumpAndSettle();

    expect(find.text('세트 수'), findsOneWidget);
    expect(find.text('횟수'), findsOneWidget);
    expect(find.text('중량'), findsOneWidget);
    expect(find.text('운동 시간'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('suggestion-edit-submit')),
    );
    await tester.pumpAndSettle();

    final edit = repo.approvalEdits.single;
    expect(edit['type'], '근력');
    expect(edit['sets'], _bridge.sets);
    expect(edit['reps'], _bridge.reps);
    expect(edit['weight'], _bridge.weight);
  });

  testWidgets('유형을 근력이 아닌 것으로 바꾸면 세 값을 싣지 않는다 (#1321)', (tester) async {
    final repo = await openProgramTab(
      tester,
      byMember: <String, List<RoutineSuggestion>>{
        firstClient: <RoutineSuggestion>[_bridge],
      },
    );

    await tester.ensureVisible(editButton(_bridge));
    await tester.pump();
    await tester.tap(editButton(_bridge));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('suggestion-edit-type-유산소')),
    );
    await tester.pumpAndSettle();

    // 유산소는 시간으로 잰다 — 칸이 바뀐다.
    expect(find.text('운동 시간'), findsOneWidget);
    expect(find.text('세트 수'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('suggestion-edit-submit')),
    );
    await tester.pumpAndSettle();

    final edit = repo.approvalEdits.single;
    expect(edit['type'], '유산소');
    expect(edit['sets'], isNull);
    expect(edit['reps'], isNull);
    expect(edit['weight'], isNull);
  });

  testWidgets('검토 카드와 최종 검토가 근력을 세트·횟수로 적는다 (#1321)', (tester) async {
    await openProgramTab(
      tester,
      byMember: <String, List<RoutineSuggestion>>{
        firstClient: <RoutineSuggestion>[_bridge],
      },
    );

    // 목록 카드부터 세트·횟수로 읽힌다 — 근력을 시간으로 말하는 자리가 없다.
    expect(find.textContaining('3세트'), findsOneWidget);
    expect(find.textContaining('12분'), findsNothing);

    await tester.ensureVisible(approveButton(_bridge));
    await tester.pump();
    await tester.tap(approveButton(_bridge));
    await tester.pumpAndSettle();

    // 수정 창이 물은 것과 같은 칸으로 적혀야 확인한 내용과 나갈 값이 같다.
    // 카드와 dialog 가 함께 떠 있으므로 둘이 같은 문구를 말한다.
    expect(find.textContaining('3세트'), findsNWidgets(2));
    expect(find.textContaining('15회'), findsNWidgets(2));
    expect(find.textContaining('12분'), findsNothing);
  });

  testWidgets('cancelling the edit does not recommend anything', (
    tester,
  ) async {
    final repo = await openProgramTab(tester);

    await tester.ensureVisible(editButton(_shoulder));
    await tester.pump();
    await tester.tap(editButton(_shoulder));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('suggestion-edit-cancel')),
    );
    await tester.pumpAndSettle();

    expect(repo.approvals, isEmpty);
    expect(find.textContaining(_shoulder.name), findsOneWidget);
  });

  testWidgets('a double tap approves once', (tester) async {
    final repo = await openProgramTab(
      tester,
      delay: const Duration(milliseconds: 300),
    );

    await confirmApprove(tester, _shoulder, settle: false);
    // 첫 호출이 아직 진행 중이다 — 두 번째 탭이 같은 제안을 또 보내면 안 된다.
    await tester.tap(approveButton(_shoulder), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(repo.approvals, <String>[_shoulder.id]);
  });

  testWidgets('an already-reviewed suggestion says so instead of failing', (
    tester,
  ) async {
    await openProgramTab(tester, alreadyReviewed: true);

    await confirmApprove(tester, _shoulder);

    expect(find.textContaining('이미 검토한 제안'), findsOneWidget);
  });

  testWidgets('최종 검토를 취소하면 회원에게 아무것도 나가지 않는다 (#1028)', (tester) async {
    final repo = await openProgramTab(tester);

    // 목록의 `회원에게 추천` 한 번으로는 mutation 이 일어나지 않는다 — 예전에는
    // 이 탭 하나가 곧바로 승인이었다.
    await tester.ensureVisible(approveButton(_shoulder));
    await tester.pump();
    await tester.tap(approveButton(_shoulder));
    await tester.pumpAndSettle();
    expect(repo.approvals, isEmpty);

    // 나갈 내용이 그대로 보인다 — 확인한 것과 payload 가 같다.
    expect(
      find.byKey(const ValueKey<String>('routine-suggestion-confirm')),
      findsOneWidget,
    );
    expect(find.textContaining(_shoulder.name), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('suggestion-confirm-cancel')),
    );
    await tester.pumpAndSettle();
    expect(repo.approvals, isEmpty);

    // 확인하면 그때 나간다.
    await confirmApprove(tester, _shoulder);
    expect(repo.approvals, <String>[_shoulder.id]);
  });

  testWidgets('switching clients loads that client\'s suggestions', (
    tester,
  ) async {
    final repo = await openProgramTab(
      tester,
      byMember: <String, List<RoutineSuggestion>>{
        firstClient: <RoutineSuggestion>[_shoulder],
        secondClient: <RoutineSuggestion>[_walking],
      },
    );

    expect(find.textContaining(_shoulder.name), findsOneWidget);
    expect(find.textContaining(_walking.name), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('program-client-$secondClient')),
    );
    await tester.pumpAndSettle();

    expect(repo.reads, contains(secondClient));
    expect(find.textContaining(_walking.name), findsOneWidget);
    expect(find.textContaining(_shoulder.name), findsNothing);
  });

  testWidgets('no suggestions leaves a quiet one-line empty state', (
    tester,
  ) async {
    await openProgramTab(
      tester,
      byMember: <String, List<RoutineSuggestion>>{
        firstClient: <RoutineSuggestion>[],
      },
    );

    expect(
      find.byKey(const ValueKey<String>('routine-suggestion-empty')),
      findsOneWidget,
    );
    // 검토할 것이 없는 날에는 건수 배지도 없다.
    expect(
      find.byKey(const ValueKey<String>('routine-suggestion-badge')),
      findsNothing,
    );
  });
}
