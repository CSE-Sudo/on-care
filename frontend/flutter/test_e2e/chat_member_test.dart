/// 회원↔담당 트레이너 텍스트 채팅 실 API E2E — 회원 앱 단계 (#639).
///
/// 트레이너 웹 단계와 번갈아 실행된다. 순서와 실행 방법은
/// `tool/run_chat_e2e.sh` 와 `docs/local_fullstack.md` 참고.
///
///  1. `member-send`    — 회원 UI 로 보낸 메시지가 서버에 **한 건** 남는다.
///  2. (트레이너) `trainer-thread`
///  3. `member-receive` — 트레이너 답장이 열린 회원 화면에 재진입 없이 나타난다.
///  4. `idempotency`    — 같은 키로 두 번 보내도 한 건이다.
///  5. `isolation`      — 다른 회원 스레드에 섞이지 않는다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installPluginFakes);

  testWidgets('회원 채팅 단계: $e2ePhase', (WidgetTester tester) async {
    final E2eApi api = await E2eApi.login(memberEmail);
    final E2eState state = E2eState.read();

    switch (e2ePhase) {
      case 'member-send':
        final String marker = state.require('marker');
        final String fromMember = '$marker 회원이 보냄';

        await bootSignedOut(tester);
        await loginAsMember(tester);
        await openTrainerChat(tester);

        await tester.enterText(
          find.byKey(const ValueKey<String>('member-chat-input')),
          fromMember,
        );
        // 전송 버튼은 공용 입력줄(`AppChatInputBar`) 안의 아이콘 버튼이다(#1702).
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey<String>('member-chat-input')),
            matching: find.byIcon(Icons.arrow_upward_rounded),
          ),
        );

        // 화면에 뜨는 것과 서버에 남는 것은 다른 주장이다. 둘 다 본다.
        await pumpUntil(tester, find.text(fromMember), step: '보낸 메시지 표시');

        List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[];
        final DateTime deadline = DateTime.now().add(
          const Duration(seconds: 20),
        );
        while (rows.isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
          rows = await api.coachChatWithBody(fromMember);
        }
        expect(
          rows,
          hasLength(1),
          reason: '회원 발신이 서버에 한 건으로 남아야 합니다(발견: ${rows.length}건).',
        );
        // 발신자는 **보는 쪽 관점**으로 내려온다 — 회원 API 는 자기 메시지를 'me' 로
        // 준다(`member_coach.my_chat`, viewer='member'). 백엔드 저장값은 'member' 다.
        expect(rows.single['sender'], 'me');

        E2eState.merge(<String, Object?>{'fromMember': fromMember});

      case 'member-receive':
        final String marker = state.require('marker');
        // 트레이너 단계가 UI 로 보낸 답장.
        final String fromTrainer = state.require('fromTrainer');

        // 읽지 않은 답장이 있으므로 회원 미읽음이 잡혀 있어야 한다.
        expect(
          await api.memberUnread(),
          greaterThan(0),
          reason: '트레이너 답장이 왔는데 회원 미읽음이 0 입니다.',
        );

        await bootSignedOut(tester);
        await loginAsMember(tester);
        await openTrainerChat(tester);
        await pumpUntil(tester, find.text(fromTrainer), step: '트레이너 답장 표시');

        // 채팅을 **연 채로** 도착한 메시지가 재진입 없이 나타나는가(polling).
        // 두 앱을 한 프로세스에 띄울 수 없어, 상대 발신은 API 가 대신한다.
        final E2eApi trainer = await E2eApi.login(trainerEmail);
        final String pushed = '$marker 열린 화면으로 도착';
        await trainer.sendAsTrainer(memberId, pushed);
        await pumpUntil(
          tester,
          find.text(pushed),
          step: '재진입 없이 polling 으로 표시',
          timeout: const Duration(seconds: 30),
        );

        // 화면을 열어 읽었으니 미읽음이 정리돼야 한다.
        int unread = -1;
        final DateTime readDeadline = DateTime.now().add(
          const Duration(seconds: 20),
        );
        while (unread != 0 && DateTime.now().isBefore(readDeadline)) {
          await tester.pump(const Duration(milliseconds: 300));
          unread = await api.memberUnread();
        }
        expect(unread, 0, reason: '채팅을 열었는데 미읽음이 남아 있습니다.');

        // 재시작·재로그인 후에도 순서가 유지되는가.
        await bootSignedOut(tester);
        await loginAsMember(tester);
        await openTrainerChat(tester);
        await pumpUntil(tester, find.text(pushed), step: '재로그인 후 대화 유지');

        final List<Map<String, dynamic>> all = await api.coachChat();
        final int memberAt = all.indexWhere(
          (Map<String, dynamic> r) => r['body'] == state.require('fromMember'),
        );
        final int trainerAt = all.indexWhere(
          (Map<String, dynamic> r) => r['body'] == fromTrainer,
        );
        final int pushedAt = all.indexWhere(
          (Map<String, dynamic> r) => r['body'] == pushed,
        );
        expect(memberAt, greaterThanOrEqualTo(0));
        expect(
          memberAt < trainerAt && trainerAt < pushedAt,
          isTrue,
          reason: '보낸 순서대로 정렬되지 않았습니다($memberAt, $trainerAt, $pushedAt).',
        );

        E2eState.merge(<String, Object?>{'pushedToMember': pushed});

      case 'idempotency':
        // 앱은 타임아웃 재시도에서 **같은 `client_request_id`** 를 다시 쓴다(#605).
        // 그 계약이 서버에서 실제로 한 건으로 접히는지 본다. UI 로는 네트워크
        // 타임아웃을 재현할 수 없어 여기서만 API 로 확인한다.
        final String marker = state.require('marker');
        final String retried = '$marker 재시도';
        const String requestId = 'e2e-639-retry';

        expect(
          (await api.sendAsMember(
            retried,
            clientRequestId: requestId,
          )).statusCode,
          201,
        );
        final Response<Object?> again = await api.sendAsMember(
          retried,
          clientRequestId: requestId,
        );
        expect(
          again.statusCode,
          anyOf(200, 201),
          reason: '재시도가 오류로 끝나면 앱이 실패를 표시하게 됩니다.',
        );
        expect(
          await api.coachChatWithBody(retried),
          hasLength(1),
          reason: '같은 키의 재시도가 두 건으로 저장됐습니다.',
        );

        // 트레이너 발신도 같은 계약을 따른다.
        final E2eApi trainer = await E2eApi.login(trainerEmail);
        final String trainerRetried = '$marker 트레이너 재시도';
        const String trainerRequestId = 'e2e-639-retry-trainer';
        await trainer.sendAsTrainer(
          memberId,
          trainerRetried,
          clientRequestId: trainerRequestId,
        );
        await trainer.sendAsTrainer(
          memberId,
          trainerRetried,
          clientRequestId: trainerRequestId,
        );
        expect(
          await api.coachChatWithBody(trainerRetried),
          hasLength(1),
          reason: '트레이너 재시도가 두 건으로 저장됐습니다.',
        );

      case 'isolation':
        // 이 실행이 만든 대화가 다른 회원의 스레드로 새지 않는가.
        final String marker = state.require('marker');
        final E2eApi trainer = await E2eApi.login(trainerEmail);

        final List<Map<String, dynamic>> otherThread = await trainer
            .trainerThread(otherMemberId);
        expect(
          otherThread.where(
            (Map<String, dynamic> r) =>
                (r['body'] as String? ?? '').contains(marker),
          ),
          isEmpty,
          reason: '다른 회원 스레드에 이번 실행의 메시지가 섞였습니다.',
        );

        // 다른 회원 계정으로는 이 대화가 보이지 않아야 한다.
        final E2eApi other = await E2eApi.login(otherMemberEmail);
        expect(
          (await other.coachChat()).where(
            (Map<String, dynamic> r) =>
                (r['body'] as String? ?? '').contains(marker),
          ),
          isEmpty,
          reason: '다른 회원이 남의 대화를 보고 있습니다.',
        );

      default:
        fail('알 수 없는 E2E_PHASE: "$e2ePhase"');
    }
  });
}
