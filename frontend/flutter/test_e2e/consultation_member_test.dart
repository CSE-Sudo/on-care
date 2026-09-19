/// 상담 요청·처리 실 API E2E — 회원 앱 단계 (#640).
///
/// 트레이너 웹 단계와 번갈아 실행된다. 순서와 실행 방법은
/// `tool/run_consultation_e2e.sh` 와 `docs/local_fullstack.md` 참고.
///
///  1. `member-request`      — 트레이너가 연 자리를 새 회원 둘이 UI 폼으로 골라
///                              상담을 신청한다.
///  2. (트레이너) `trainer-accept`
///  3. `member-after-accept` — 승인 결과·담당·일정이 회원에게 돌아온다.
///  4. (트레이너) `trainer-reject`
///  5. `member-after-reject` — 거절 사유가 그대로 보이고 다시 신청할 수 있다.
///  6. `edge-cases`          — 중복 제출·남의 상담 조회.
///  7. `cleanup`             — 승인이 만든 일정과 이번 실행이 연 자리를 닫고 계정
///                              둘을 지운다.
///
/// ## 왜 계정을 새로 만드는가
///
/// 시드 회원 셋은 이미 `trainer-demo` 담당이다. 그 회원으로는 **승인이 담당 연결을
/// 만든다** 를 검증할 수 없고(이미 연결돼 있다), 한 번 승인해 버리면 다음 실행이 같은
/// 상태에서 시작하지 못한다. 그래서 실행마다 새로 만들고 끝나면 지운다.
///
/// 승인 사이클과 거절 사이클이 서로를 막으므로(승인 뒤에는 담당이 생겨 재신청이
/// 막힌다) 계정을 둘 쓴다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_harness.dart';

/// 폼에서 고를 자리. 서버 계약 enum 과 순서가 같다(화면 enum → wire 는 index 매핑).
///
/// 건강관리 목적은 더는 따로 고르지 않는다(#1112) — 운동 목표에서 자동
/// 매핑된다. `strength` 는 `general` 로 매핑된다.
const int _goalStrength = 1; // ExerciseGoal.strength

const String _acceptMessage = 'E2E 승인 시나리오 문의입니다.';
const String _rejectMessage = 'E2E 거절 시나리오 문의입니다.';

/// 이 회원의 대기 중 상담 한 건. 없으면 null.
Map<String, dynamic>? _pendingOf(List<Map<String, dynamic>> rows) {
  for (final Map<String, dynamic> row in rows) {
    if (row['status'] == 'pending') return row;
  }
  return null;
}

Future<void> _requestAs(
  WidgetTester tester, {
  required String email,
  required String slotId,
  required String message,
}) async {
  await bootSignedOut(tester);
  await loginAsMember(tester, email: email);
  await openConsultationForm(tester, trainerId);
  await submitConsultation(
    tester,
    goalIndex: _goalStrength,
    slotId: slotId,
    message: message,
  );
}

/// 상담이 고를 자리를 트레이너 계정으로 연다. (#1873)
///
/// 상담 시각은 이제 트레이너가 열어 둔 `1:1 PT` 자리 중에서만 고른다. 회원마다
/// 자리를 하나씩 쓴다 — 신청이 자리를 잠그므로 둘이 같은 자리를 고를 수 없다.
/// 날짜를 하루씩 벌려 둔다: 같은 시각이면 폼에 두 칩이 같은 시각으로 나란히 선다.
Future<(String, DateTime)> _openSlot(E2eApi trainer, int daysAhead) async {
  final DateTime startsAt = consultSlotStartsAt(daysAhead);
  final Map<String, dynamic> slot = await trainer.createSlotAsTrainer(
    startsAt: startsAt,
  );
  return (slot['id']! as String, startsAt);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installPluginFakes);

  testWidgets('회원 단계: $e2ePhase', (WidgetTester tester) async {
    final E2eState state = E2eState.read();

    switch (e2ePhase) {
      case 'member-request':
        final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
        final String acceptEmail = 'e2e-640-a-$stamp@oncare.test';
        final String rejectEmail = 'e2e-640-r-$stamp@oncare.test';
        final String acceptId = await E2eApi.register(
          acceptEmail,
          name: 'E2E 승인 회원',
        );
        final String rejectId = await E2eApi.register(
          rejectEmail,
          name: 'E2E 거절 회원',
        );
        E2eState.merge(<String, Object?>{
          'acceptEmail': acceptEmail,
          'acceptId': acceptId,
          'rejectEmail': rejectEmail,
          'rejectId': rejectId,
        });

        // 자리를 열자마자 id 를 남긴다 — 이 단계가 중간에 죽어도 정리가 닫는다.
        final E2eApi trainerApi = await E2eApi.login(trainerEmail);
        final (String acceptSlotId, DateTime acceptStartsAt) = await _openSlot(
          trainerApi,
          2,
        );
        final (String rejectSlotId, _) = await _openSlot(trainerApi, 3);
        E2eState.merge(<String, Object?>{
          'acceptSlotId': acceptSlotId,
          'rejectSlotId': rejectSlotId,
        });

        // 새 회원에게는 담당이 없다. 승인이 담당을 **만드는지** 보려면 여기서
        // 비어 있어야 한다.
        final E2eApi acceptApi = await E2eApi.login(acceptEmail);
        expect(
          await acceptApi.myCoach(),
          isNull,
          reason: '새 회원에게 이미 담당 트레이너가 있습니다.',
        );

        await _requestAs(
          tester,
          email: acceptEmail,
          slotId: acceptSlotId,
          message: _acceptMessage,
        );

        // 화면이 아니라 서버에 남았는지 본다. 그리고 **입력한 값 그대로** 인지.
        final Map<String, dynamic>? saved = await _waitForPending(acceptApi);
        expect(saved, isNotNull, reason: 'UI 제출이 서버에 상담을 남기지 않았습니다.');
        expect(saved!['trainer_id'], trainerId);
        // `target_type` 은 단언하지 않는다. #727 이 헬스장 대상 갈래를 없애면서 응답
        // 필드에서 뺐다 — 값이 `trainer` 하나뿐이라 실어 보낼 이유가 없어졌다.
        // 대상이 트레이너라는 것은 위의 `trainer_id` 가 이미 증명한다.
        expect(saved['exercise_goal'], 'strength');
        // 운동 목표에서 자동 매핑된 값이다(#1112) — strength → general.
        expect(saved['health_purpose_type'], 'general');
        // 회원이 고른 자리가 그대로 남고, 그 자리의 시각이 옮겨 적힌다(#1873).
        expect(saved['slot_id'], acceptSlotId);
        expect(
          DateTime.parse(saved['slot_starts_at'] as String).toUtc(),
          acceptStartsAt,
        );
        expect(saved['preferred_date'], seoulDate(acceptStartsAt));
        expect(saved['preferred_time_slot'], consultStartTime);
        expect(saved['message'], _acceptMessage);
        E2eState.merge(<String, Object?>{'acceptConsultationId': saved['id']});

        // 거절 사이클용 요청도 UI 로 낸다.
        await _requestAs(
          tester,
          email: rejectEmail,
          slotId: rejectSlotId,
          message: _rejectMessage,
        );
        final E2eApi rejectApi = await E2eApi.login(rejectEmail);
        final Map<String, dynamic>? rejectSaved = await _waitForPending(
          rejectApi,
        );
        expect(rejectSaved, isNotNull);
        expect(rejectSaved!['message'], _rejectMessage);
        expect(rejectSaved['slot_id'], rejectSlotId);
        E2eState.merge(<String, Object?>{
          'rejectConsultationId': rejectSaved['id'],
        });

      case 'member-after-accept':
        final String email = state.require('acceptEmail');
        final E2eApi api = await E2eApi.login(email);

        // 승인은 상담 상태와 담당 연결을 함께 남긴다. 승인이 만드는 상담
        // 일정은 트레이너의 달력이라 `trainer-accept` 단계가 확인한다(#1587).
        final List<Map<String, dynamic>> rows = await api.myConsultations();
        expect(rows.single['status'], 'accepted');
        final Map<String, dynamic>? coach = await api.myCoach();
        expect(coach, isNotNull, reason: '승인했는데 담당 트레이너가 생기지 않았습니다.');
        expect(coach!['trainer_id'], trainerId);

        // 화면에도 돌아오는가. 재로그인 뒤에도 남는가 — 앱이 들고 있던 값이
        // 아니라 서버가 답한 값이어야 한다.
        await bootSignedOut(tester);
        await loginAsMember(tester, email: email);
        await openGymTab(tester);
        // 승인 결과 요약은 운동 탭 본문에서 제거됐다(#1287). 승인이 만든 실제
        // 연결 상태와 담당 트레이너 진입점으로 화면 반영을 검증한다.
        await pumpUntil(
          tester,
          find.byKey(const Key('my-gym-info-card')),
          step: '연결된 내 헬스장',
        );
        await pumpUntil(
          tester,
          find.byKey(const Key('trainerChatHeaderButton')),
          step: '담당 트레이너 채팅 진입점',
        );

      case 'member-after-reject':
        final String email = state.require('rejectEmail');
        final String note = state.require('rejectNote');
        final E2eApi api = await E2eApi.login(email);

        final List<Map<String, dynamic>> rows = await api.myConsultations();
        expect(rows.single['status'], 'rejected');
        expect(
          rows.single['decision_note'],
          note,
          reason: '트레이너가 적은 사유와 회원이 받는 사유가 다릅니다.',
        );
        // 거절은 담당을 만들지 않는다.
        expect(await api.myCoach(), isNull);

        await bootSignedOut(tester);
        await loginAsMember(tester, email: email);
        await openGymTab(tester);
        // 미연결 상태의 상담 내역은 헬스장 검색 옆 아이콘이 유일한 진입점이다
        // (#1287). 본문에 제거된 결과 카드를 직접 기다리지 않는다.
        await pumpUntil(
          tester,
          find.byKey(const Key('consult-history-shortcut')),
          step: '상담 내역 진입점',
        );
        await tester.tap(find.byKey(const Key('consult-history-shortcut')));
        await tester.pumpAndSettle();
        await pumpUntil(
          tester,
          find.byKey(const Key('consult-outcome-rejected')),
          step: '거절 안내',
        );
        // 사유가 문구 그대로 보여야 한다 — 배지만 있으면 다시 신청해도 되는지
        // 판단할 근거가 없다.
        expect(find.textContaining(note), findsWidgets);

      case 'edge-cases':
        final String rejectEmail = state.require('rejectEmail');
        final String acceptConsultationId = state.require(
          'acceptConsultationId',
        );
        final String rejectSlotId = state.require('rejectSlotId');
        final E2eApi rejected = await E2eApi.login(rejectEmail);

        // 거절당한 회원은 **다시 신청할 수 있다.** 거절이 자리를 되돌리므로 같은
        // 자리를 다시 고를 수 있다(#1873) — 되돌리지 않으면 여기서 409 가 난다.
        final Map<String, dynamic> again = await rejected.createConsultation(
          trainerId: trainerId,
          slotId: rejectSlotId,
        );
        expect(again['status'], 'pending');

        // 대기 중인데 또 내면 막힌다. 자리를 놓친 409(`slot_unavailable`)가 아니라
        // 대기 중복 409 여야 한다 — 서버는 중복을 자리보다 먼저 본다.
        final Response<Object?> duplicate = await rejected
            .createConsultationRaw(trainerId: trainerId, slotId: rejectSlotId);
        expect(
          duplicate.statusCode,
          409,
          reason: '대기 중 상담이 있는데 중복 제출이 통과했습니다.',
        );
        expect(
          (duplicate.data! as Map<String, dynamic>)['detail'],
          isA<String>(),
          reason: '대기 중복이 아니라 다른 이유로 막혔습니다: ${duplicate.data}',
        );

        // 남의 상담은 보이지 않는다.
        expect(
          await rejected.consultationStatusCode(acceptConsultationId),
          404,
          reason: '다른 회원의 상담을 조회할 수 있습니다.',
        );

        // 이미 처리한 상담은 다시 처리할 수 없다. 막지 않으면 트레이너가 같은
        // 요청을 두 번 승인해 담당 연결과 일정이 중복으로 쌓인다.
        final E2eApi trainerApi = await E2eApi.login(trainerEmail);
        for (final String action in <String>['accept', 'reject']) {
          expect(
            await trainerApi.decideStatus(acceptConsultationId, action),
            409,
            reason: '이미 승인된 상담을 $action 로 다시 처리할 수 있습니다.',
          );
        }
        final String rejectConsultationId = state.require(
          'rejectConsultationId',
        );
        expect(
          await trainerApi.decideStatus(rejectConsultationId, 'accept'),
          409,
          reason: '이미 거절된 상담을 다시 승인할 수 있습니다.',
        );

      case 'cleanup':
        // 일정을 먼저 지운다. `trainer_schedule.member_id` 는 SET NULL 이라 계정을
        // 먼저 지우면 주인 없는 상담 일정이 트레이너 달력에 영영 남는다.
        //
        // 이번 실행이 연 자리도 닫는다(#1873). 두지 않으면 다음 실행과 예약
        // 스위트가 보는 트레이너 자리 목록에 쌓인다.
        final String? sessionId = state.values['sessionId'] as String?;
        final List<String> slotIds = <String>[
          for (final String key in <String>['acceptSlotId', 'rejectSlotId'])
            if (state.values[key] case final String id) id,
        ];
        if (sessionId != null || slotIds.isNotEmpty) {
          final E2eApi trainerApi = await E2eApi.login(trainerEmail);
          if (sessionId != null) {
            await trainerApi.deleteTrainerSession(sessionId);
          }
          for (final String id in slotIds) {
            await trainerApi.closeSlotAsTrainer(id);
          }
        }
        for (final String key in <String>['acceptEmail', 'rejectEmail']) {
          final String? email = state.values[key] as String?;
          if (email == null) continue;
          final E2eApi api = await E2eApi.login(email);
          await api.deleteMe();
        }

      default:
        fail('알 수 없는 단계: $e2ePhase');
    }
  });
}

/// 제출 직후의 서버 반영을 기다린다. UI 제출은 비동기라 곧바로 조회하면 아직
/// 없을 수 있다 — 없다고 단정하면 **되는 기능을 실패로** 보고한다.
Future<Map<String, dynamic>?> _waitForPending(E2eApi api) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final Map<String, dynamic>? row = _pendingOf(await api.myConsultations());
    if (row != null) return row;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return null;
}
