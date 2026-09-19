/// 상담 요청·처리 실 API E2E — 트레이너 웹 단계 (#640).
///
/// 회원 앱 단계와 번갈아 실행된다. 전체 순서는 `tool/run_consultation_e2e.sh` 참고.
///
///  1. (회원) `member-request`
///  2. `trainer-accept`  — 인박스에서 요청 내용을 확인하고 승인한다. 일정은 회원이
///                         고른 자리에 생긴다.
///  3. (회원) `member-after-accept`
///  4. `trainer-reject`  — 다른 요청을 사유와 함께 거절한다.
///  5. (회원) `member-after-reject`
///
/// 승인은 상담 상태와 담당 연결, 그리고 회원이 고른 자리의 일정을 함께 남긴다
/// (#1873). 승인할 때 시각을 따로 받지 않는다 — 시각은 트레이너가 연 자리가 이미
/// 정해 두었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';

import 'support/e2e_harness.dart';

const String _rejectNote = 'E2E 거절 사유 — 이번 주는 일정이 가득 찼습니다.';

/// 사이드바 → 일정 → 상담 인박스.
Future<void> _openInbox(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('sidebar-${AppRoutes.schedule}')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  final Finder entry = find.byKey(const Key('consult-inbox-entry'));
  await pumpUntil(tester, entry, step: '상담 인박스 진입점');
  await tester.tap(entry);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// 인박스에서 그 회원의 요청 카드를 찾는다. 목록이 길면 스크롤해서 만들어 낸다.
Future<Finder> _requestCard(WidgetTester tester, String consultationId) async {
  final Finder card = find.byKey(
    ValueKey<String>('consultation-$consultationId'),
  );
  // `pumpUntil` 은 `finder.evaluate()` 로 기다린다. 여기에 `.first` 를 넘기면 대상이
  // 아직 없을 때 빈 목록에서 `first` 를 불러 `Bad state: No element` 로 즉사한다 —
  // 타임아웃 메시지도 못 보고 원인이 가려진다. 기다릴 때는 맨 파인더를 쓴다.
  await pumpUntil(tester, card, step: '인박스 카드');
  if (card.evaluate().isEmpty) {
    await tester.scrollUntilVisible(card, 200, maxScrolls: 40);
  }
  await tester.ensureVisible(card);
  await tester.pump();
  return card;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installPluginFakes);

  testWidgets('트레이너 단계: $e2ePhase', (WidgetTester tester) async {
    final E2eState state = E2eState.read();
    final E2eApi api = await E2eApi.login(trainerEmail);

    switch (e2ePhase) {
      case 'trainer-accept':
        final String consultationId = state.require('acceptConsultationId');
        final String memberId = state.require('acceptId');

        // 회원이 UI 로 낸 요청이 트레이너에게 **같은 내용으로** 도착했는가.
        final List<Map<String, dynamic>> inbox = await api.consultations();
        final Map<String, dynamic> row = inbox.firstWhere(
          (Map<String, dynamic> r) => r['id'] == consultationId,
          orElse: () => <String, dynamic>{},
        );
        expect(row, isNotEmpty, reason: '회원의 요청이 트레이너 인박스에 없습니다.');
        expect(row['member_id'], memberId);
        expect(row['exercise_goal'], 'strength');
        // 운동 목표에서 자동 매핑된 값이다(#1112) — strength → general.
        expect(row['health_purpose_type'], 'general');
        // 회원 단계에서 고른 자리가 그대로 도착한다(#1873) — 자리의 시각이
        // 희망 시각 칸에 옮겨 적힌다.
        expect(row['slot_id'], state.require('acceptSlotId'));
        expect(row['preferred_time_slot'], consultStartTime);
        expect(row['status'], 'pending');

        await bootSignedOut(tester);
        await loginAsTrainer(tester);
        await _openInbox(tester);

        // 카드에 회원 이름과 메시지가 보여야 한다 — id 만 보면 누구인지 모른다.
        final Finder card = await _requestCard(tester, consultationId);
        expect(
          find.descendant(of: card, matching: find.textContaining('E2E 승인 회원')),
          findsWidgets,
          reason: '카드에 회원 이름이 없습니다.',
        );

        final Finder accept = find.descendant(
          of: card,
          matching: find.byKey(
            ValueKey<String>('consultation-accept-$consultationId'),
          ),
        );
        await tester.tap(accept);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // 상태와 담당 연결이 함께 남았는가. 하나라도 빠지면 부분 성공이다.
        final Map<String, dynamic> after = await _waitForStatus(
          api,
          consultationId,
          'accepted',
        );
        expect(after['status'], 'accepted');
        expect(
          await api.isClientOf(memberId),
          isTrue,
          reason: '승인했는데 담당 연결이 생기지 않았습니다.',
        );

        // 승인은 회원이 고른 자리에 일정까지 만든다(#1873). 담당만 생기고
        // 일정이 없으면 트레이너가 스케줄 탭에서 다시 잡아야 하는 예전 상태로
        // 돌아간 것이다.
        final List<Map<String, dynamic>> sessions = await api.scheduleFor(
          memberId,
        );
        final Map<String, dynamic> session = sessions.firstWhere(
          (Map<String, dynamic> s) =>
              s['date'] == row['preferred_date'] &&
              s['time'] == consultStartTime,
          orElse: () => <String, dynamic>{},
        );
        expect(
          session,
          isNotEmpty,
          reason:
              '승인이 ${row['preferred_date']} $consultStartTime 상담 일정을 만들지 않았습니다.',
        );
        // 종류와 길이는 자리의 것이다 — 코드 상수(상담 30분)로 만들면 트레이너가
        // 연 자리와 달력이 어긋난다.
        expect(session['type'], '1:1 PT');
        expect(session['duration_minutes'], row['slot_duration_minutes']);
        // 정리 단계가 지울 수 있게 남긴다 — 회원 계정을 지워도
        // `trainer_schedule.member_id` 는 SET NULL 이라 일정은 그대로 남는다.
        E2eState.merge(<String, Object?>{'sessionId': session['id']});

      case 'trainer-reject':
        final String consultationId = state.require('rejectConsultationId');
        final String memberId = state.require('rejectId');

        await bootSignedOut(tester);
        await loginAsTrainer(tester);
        await _openInbox(tester);

        final Finder card = await _requestCard(tester, consultationId);
        final Finder reject = find.descendant(
          of: card,
          matching: find.byKey(
            ValueKey<String>('consultation-reject-$consultationId'),
          ),
        );
        await tester.tap(reject);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final Finder reason = find.byKey(
          const Key('consultation-reject-reason'),
        );
        await pumpUntil(tester, reason, step: '거절 사유 입력창');
        await tester.enterText(reason, _rejectNote);
        await tester.pump();
        await tester.tap(find.byKey(const Key('consultation-reject-confirm')));
        await tester.pump();

        final Map<String, dynamic> after = await _waitForStatus(
          api,
          consultationId,
          'rejected',
        );
        expect(after['decision_note'], _rejectNote);
        // 거절은 담당을 만들지 않는다.
        expect(
          await api.isClientOf(memberId),
          isFalse,
          reason: '거절했는데 담당 연결이 생겼습니다.',
        );
        E2eState.merge(<String, Object?>{'rejectNote': _rejectNote});

      case 'empty-inbox':
        // 처리를 끝내면 대기 목록이 비어야 한다 — 처리한 요청이 계속 보이면
        // 트레이너는 같은 요청을 다시 누른다.
        await bootSignedOut(tester);
        await loginAsTrainer(tester);
        await _openInbox(tester);
        final String acceptId = state.require('acceptConsultationId');
        final String rejectId = state.require('rejectConsultationId');
        for (final String id in <String>[acceptId, rejectId]) {
          expect(
            find.byKey(ValueKey<String>('consultation-$id')),
            findsNothing,
            reason: '처리한 요청이 대기 목록에 남아 있습니다.',
          );
        }

      default:
        fail('알 수 없는 단계: $e2ePhase');
    }
  });
}

/// UI 조작 뒤 서버 반영을 기다린다. 곧바로 조회하면 아직 이전 상태일 수 있다 —
/// 그것을 실패로 단정하면 **되는 기능을 깨졌다고** 보고한다.
Future<Map<String, dynamic>> _waitForStatus(
  E2eApi api,
  String consultationId,
  String status,
) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
  Map<String, dynamic> last = <String, dynamic>{};
  while (DateTime.now().isBefore(deadline)) {
    for (final Map<String, dynamic> row in await api.consultations(all: true)) {
      if (row['id'] != consultationId) continue;
      last = row;
      if (row['status'] == status) return row;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('[$e2ePhase] 상담 $consultationId 가 $status 가 되지 않았습니다: $last');
}
