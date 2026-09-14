/// 회원↔담당 트레이너 텍스트 채팅 실 API E2E — 트레이너 웹 단계 (#639).
///
/// 회원 앱 단계와 번갈아 실행된다. 순서와 실행 방법은 `tool/run_chat_e2e.sh` 참고.
///
///  1. (회원) `member-send`
///  2. `trainer-thread` — 회원 메시지를 받고, 열린 화면에 polling 으로 도착하는 것을
///     확인하고, 읽음 처리 후 UI 로 답장한다.
///  3. (회원) `member-receive`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/messages/presentation/pages/messages_page.dart';

import 'support/e2e_harness.dart';

/// 사이드바 → 메시지 → 담당 회원 스레드.
///
/// 트레이너 웹 Figma 정렬(#665, #676) 이후 채팅은 고객 상세의 버튼이 아니라 **메시지
/// 화면**에 있다. 브라우저 스위트(`integration_test/trainer_web_core_flows_test.dart`)
/// 도 같은 경로를 쓴다(#692).
Future<void> _openClientChat(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('sidebar-${AppRoutes.messages}')),
  );
  await pumpUntil(tester, find.byType(MessagesPage), step: '메시지 화면');
  final Finder conversation = find.byKey(
    const ValueKey<String>('messages-conversation-$memberId'),
  );
  await pumpUntil(tester, conversation, step: '담당 회원 스레드');
  await tester.tap(conversation);
  await pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('messages-thread-$memberId')),
    step: '채팅 화면',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installPluginFakes);

  testWidgets('트레이너 채팅 단계: $e2ePhase', (WidgetTester tester) async {
    final E2eApi api = await E2eApi.login(trainerEmail);
    final E2eState state = E2eState.read();

    switch (e2ePhase) {
      case 'trainer-thread':
        final String marker = state.require('marker');
        final String fromMember = state.require('fromMember');

        // 회원이 보냈고 트레이너는 아직 열지 않았다 — 미읽음이 잡혀 있어야 한다.
        expect(
          await api.unreadFor(memberId),
          greaterThan(0),
          reason: '회원 메시지가 왔는데 트레이너 미읽음이 0 입니다.',
        );

        await bootSignedOut(tester);
        await loginAsTrainer(tester);
        await _openClientChat(tester);
        await pumpUntil(tester, find.text(fromMember), step: '회원 메시지 표시');

        // 채팅을 **연 채로** 도착한 메시지가 재진입 없이 나타나는가(polling).
        // 두 앱을 한 프로세스에 띄울 수 없어, 회원 발신은 API 가 대신한다.
        final String pushed = '$marker 열린 트레이너 화면으로 도착';
        await api.sendAsMember(pushed);
        await pumpUntil(
          tester,
          find.text(pushed),
          step: '재진입 없이 polling 으로 표시',
          timeout: const Duration(seconds: 30),
        );

        // 스레드를 열어 읽었으니 미읽음이 정리돼야 한다.
        int unread = -1;
        final DateTime deadline = DateTime.now().add(
          const Duration(seconds: 20),
        );
        while (unread != 0 && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 300));
          unread = await api.unreadFor(memberId);
        }
        expect(unread, 0, reason: '스레드를 열었는데 트레이너 미읽음이 남아 있습니다.');

        // 트레이너 UI 답장이 서버에 한 건으로 남는가.
        final String fromTrainer = '$marker 트레이너가 보냄';
        await tester.enterText(
          find.byKey(const ValueKey<String>('client-chat-input')),
          fromTrainer,
        );
        // 전송 버튼은 공용 입력줄(`AppChatInputBar`) 안의 아이콘 버튼이다(#1704).
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey<String>('client-chat-input')),
            matching: find.byIcon(Icons.arrow_upward_rounded),
          ),
        );
        await pumpUntil(tester, find.text(fromTrainer), step: '보낸 답장 표시');

        List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[];
        final DateTime saveDeadline = DateTime.now().add(
          const Duration(seconds: 20),
        );
        while (rows.isEmpty && DateTime.now().isBefore(saveDeadline)) {
          await tester.pump(const Duration(milliseconds: 200));
          rows = await api.threadWithBody(memberId, fromTrainer);
        }
        expect(
          rows,
          hasLength(1),
          reason: '트레이너 발신이 서버에 한 건으로 남아야 합니다(발견: ${rows.length}건).',
        );
        // 트레이너 API 는 회원 메시지를 'client' 로 바꿔 주지만 자기 것은 저장값
        // 'trainer' 그대로 준다(회원 API 가 자기 것을 'me' 로 주는 것과 다르다).
        expect(rows.single['sender'], 'trainer');

        E2eState.merge(<String, Object?>{
          'fromTrainer': fromTrainer,
          'pushedToTrainer': pushed,
        });

      default:
        fail('알 수 없는 E2E_PHASE: "$e2ePhase"');
    }
  });
}
