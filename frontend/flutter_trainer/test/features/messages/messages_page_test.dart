import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/design_system/tokens/layout.dart';
import 'package:oncare_trainer/design_system/tokens/radius.dart';
import 'package:oncare_trainer/design_system/tokens/spacing.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('messages route renders the two-pane conversation workspace', (
    tester,
  ) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');
      await goTo(tester, AppRoutes.messagesFor('seed-client-1'));

      expect(find.text('대화'), findsNothing);
      expect(find.textContaining('읽지 않음'), findsOneWidget);
      final detail = find.byKey(
        const ValueKey<String>('messages-client-detail-button'),
      );
      expect(
        find.descendant(of: detail, matching: find.text('회원 상세')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsWidgets);

      final selectedTile = find.byKey(
        const ValueKey<String>('messages-conversation-seed-client-1'),
      );
      final avatar = tester.widget<ClientAvatar>(
        find.descendant(of: selectedTile, matching: find.byType(ClientAvatar)),
      );
      expect(avatar.showStatus, isFalse);
      expect(avatar.size, 36);
      final surface = tester.widget<Material>(
        find
            .descendant(of: selectedTile, matching: find.byType(Material))
            .first,
      );
      expect(surface.color, AppColors.accentSurface);
      final tappable = tester.widget<InkWell>(
        find.descendant(of: selectedTile, matching: find.byType(InkWell)),
      );
      expect(tappable.borderRadius, const BorderRadius.all(AppRadius.card));
      final cardBody = tester.widget<Container>(
        find
            .descendant(of: selectedTile, matching: find.byType(Container))
            .first,
      );
      expect(cardBody.padding, const EdgeInsets.all(AppSpacing.lg));
      expect(cardBody.constraints?.minHeight, 88);

      final listColumn = tester.widget<SizedBox>(
        find.ancestor(
          of: selectedTile,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox && widget.width == AppLayout.splitListWidth,
          ),
        ),
      );
      expect(listColumn.width, AppLayout.splitListWidth);
    });
  });

  testWidgets('conversation list keeps unread and status information', (
    tester,
  ) async {
    // 목록이 최신순이라 박성호는 아래쪽에 선다. 기본 높이로는 지연 생성
    // 목록이 그를 만들지 않아, `findsNothing` 단언이 화면 밖이라는 이유로
    // 통과해 버린다 - 목록 전체가 한 화면에 들어오는 높이로 띄운다.
    await withWideSurface(tester, size: const Size(1440, 2200), () async {
      // 박성호의 배지는 요일에 따라 뒤집힌다. 시드가 주간 계열을 오늘까지만
      // 채우므로, 화요일에는 그 주에 기록된 날이 33% 하루뿐이라 이행률 저조가
      // 나트륨 초과보다 급한 신호가 된다. 주가 끝난 일요일로 고정해 어느 날
      // 돌려도 같은 상태를 본다.
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        seedClock: DateTime(2026, 8, 16), // 일요일
      );
      await goTo(tester, AppRoutes.messages);

      final conversation = find.byKey(
        const ValueKey<String>('messages-conversation-seed-client-3'),
      );
      expect(conversation, findsOneWidget);
      // 미리보기는 스레드의 **마지막** 메시지다 — 회원이 보낸 옛 메시지가
      // 아니라, 트레이너가 마지막으로 보낸 답장이 뜬다.
      expect(
        find.descendant(
          of: conversation,
          matching: find.textContaining('이해해요! 대신 AI 식단 분석'),
        ),
        findsOneWidget,
      );
      // 박성호는 트레이너가 마지막으로 답장해 두었다 — 기다리는 것이
      // 없으므로 안읽음 배지도 없다. 배지는 회원이 마지막으로 말한
      // 스레드에만 붙는다.
      expect(
        find.byKey(const ValueKey<String>('messages-unread-seed-client-3')),
        findsNothing,
      );
      final unreadBadge = find.byKey(
        const ValueKey<String>('messages-unread-seed-client-8'),
      );
      expect(unreadBadge, findsOneWidget);
      // 세로로 긴 알약처럼 깨졌던 적이 있다 (#1380) — 정원인지 폭·높이로 잡는다.
      final Size badgeSize = tester.getSize(unreadBadge);
      expect(badgeSize.width, badgeSize.height);
      // 목록은 어느 대화를 열까를 정하는 자리다 — 이름 · 시각 · 마지막
      // 말 · 안읽음뿐이고, 목표도 상태도 없다.
      expect(
        find.descendant(of: conversation, matching: find.text('근력 향상')),
        findsNothing,
      );
      expect(
        find.descendant(of: conversation, matching: find.text('나트륨 초과')),
        findsNothing,
      );
      // 목표 자리를 미리보기가 가져갔다 — 두 줄이면 뒤에 무엇이 붙는지까지
      // 읽히고, 열어 볼 대화인지 목록에서 판단할 수 있다.
      final preview = tester.widget<Text>(
        find.descendant(
          of: conversation,
          matching: find.textContaining('이해해요! 대신 AI 식단 분석'),
        ),
      );
      expect(preview.maxLines, 2);
    });
  });

  testWidgets(
    '안읽음 배지 숫자는 글자 배율이 커도 원을 벗어나지 않는다 (#1380)',
    (tester) async {
      await withWideSurface(tester, size: const Size(1440, 2200), () async {
        // 기기 접근성 배율이 앱 기본 바닥값(1.10)보다 큰 경우를 흉내낸다.
        // Container는 자식을 자르지 않으므로, 숫자가 원(20x20)보다 크게
        // 그려지면 위아래로 삐져나와 타원처럼 보인다 — FittedBox로 줄여야
        // 원 안에 남는다.
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token-existing',
          seedClock: DateTime(2026, 8, 16), // 일요일
        );
        await goTo(tester, AppRoutes.messages);

        final unreadBadge = find.byKey(
          const ValueKey<String>('messages-unread-seed-client-8'),
        );
        expect(unreadBadge, findsOneWidget);
        final Size badgeSize = tester.getSize(unreadBadge);
        expect(badgeSize.width, badgeSize.height);

        final numberText = find.descendant(
          of: unreadBadge,
          matching: find.byType(Text),
        );
        final Size textSize = tester.getSize(numberText);
        expect(textSize.height, lessThanOrEqualTo(20));
        expect(textSize.width, lessThanOrEqualTo(20));
      });
    },
  );

  testWidgets('conversation without a thread still shows a preview line', (
    tester,
  ) async {
    await withWideSurface(tester, () async {
      // 실 API 는 대화가 없는 회원의 `last_message` 를 빈 문자열로 준다.
      // 그대로 그리면 미리보기 줄이 통째로 사라져 타일 높이가 회원마다
      // 달라졌다 — 빈 값도 뜻을 갖고 한 줄을 지켜야 한다.
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        extraOverrides: <Override>[
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
              const TrainerClient(
                id: 'quiet-client',
                name: '한조용',
                avatar: '한',
                goal: '목표 설정 전',
                lastMessage: '',
                lastTime: '-',
                active: true,
                calories: 0,
                sodiumMg: 0,
                sugarG: 0,
                lastRoutine: '-',
                weekCompletion: <int>[],
                sodiumWeek: <int>[],
              ),
            ]),
          ),
        ],
      );
      await goTo(tester, AppRoutes.messages);

      final conversation = find.byKey(
        const ValueKey<String>('messages-conversation-quiet-client'),
      );
      expect(conversation, findsOneWidget);
      expect(
        find.descendant(of: conversation, matching: find.text('아직 대화가 없어요')),
        findsOneWidget,
      );
    });
  });

  testWidgets(
    'narrowest desktop split keeps message and time without overflow',
    (tester) async {
      await withWideSurface(tester, size: const Size(1024, 760), () async {
        await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');
        await goTo(tester, AppRoutes.messagesFor('seed-client-1'));

        final conversation = find.byKey(
          const ValueKey<String>('messages-conversation-seed-client-1'),
        );
        expect(
          find.descendant(
            of: conversation,
            matching: find.textContaining('확인했어요.'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: conversation, matching: find.text('18:18')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets('thread header is the detailed side: status and every alert', (
    tester,
  ) async {
    await withWideSurface(tester, () async {
      // 배지 우선순위는 요일에 따라 뒤집힌다 — 주가 끝난 일요일로 고정한다.
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        seedClock: DateTime(2026, 8, 16), // 일요일
      );
      await goTo(tester, AppRoutes.messagesFor('seed-client-3'));

      final identity = find.byKey(
        const ValueKey<String>('messages-thread-identity'),
      );
      expect(identity, findsOneWidget);
      // 활성/휴면은 메시지 탭 어디에도 없다 — 이 사람과 지금 이야기하는
      // 데 쓰이지 않는 값이고, 바꿀 수 있는 자리도 회원 탭이다.
      expect(
        find.byKey(const ValueKey<String>('messages-thread-status')),
        findsNothing,
      );
      expect(find.text('휴면'), findsNothing);
      expect(find.text('활성'), findsNothing);
      // 주의 배지는 **전부** 선다 — 나트륨이 넘쳤다는 사실은 지금 이
      // 대화에서 할 말을 바꾼다.
      expect(
        find.descendant(of: identity, matching: find.text('나트륨 초과')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: identity, matching: find.text('당류 초과')),
        findsOneWidget,
      );
      // 대화 화면은 대화만 한다 — 운동 데이터는 회원 탭이 보여 준다.
      expect(find.textContaining('최근 운동'), findsNothing);
      expect(find.textContaining('주간 이행률'), findsNothing);
    });
  });

  testWidgets('a long message never fills the whole thread width', (
    tester,
  ) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');
      await goTo(tester, AppRoutes.messagesFor('seed-client-3'));

      // 상한이 없으면 긴 메시지가 대화 창을 가로로 다 채운다. 그러면 누가
      // 한 말인지를 말해 주던 "어느 쪽으로 붙어 있는가" 가 사라진다.
      final thread = find.byKey(
        const ValueKey<String>('messages-thread-seed-client-3'),
      );
      // 같은 문장이 목록 미리보기에도 있다 — 대화 쪽 말풍선만 잰다.
      final message = find.descendant(
        of: thread,
        matching: find.textContaining('이해해요! 대신 AI 식단 분석'),
      );
      expect(message, findsOneWidget);
      final threadWidth = tester.getSize(thread).width;
      final bubbleWidth = tester.getSize(message).width;

      expect(bubbleWidth, lessThan(threadWidth * 0.75));
      // 그렇다고 쓸데없이 좁지도 않다 — 넓은 화면에서는 상한까지 쓴다.
      expect(bubbleWidth, greaterThan(threadWidth * 0.5));
    });
  });

  testWidgets('전체는 마지막 말이 새로운 순, 관리 필요만 주의 우선', (tester) async {
    // 두 대화의 세로 자리를 재는 단언이라 둘 다 그려져 있어야 한다 -
    // 지연 생성 목록이 화면 밖 대화를 만들지 않으므로 목록 전체가 들어오는
    // 높이로 띄운다.
    await withWideSurface(tester, size: const Size(1440, 2200), () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        seedClock: DateTime(2026, 8, 16), // 일요일 — 배지 우선순위 고정
      );

      double topOf(String id) => tester
          .getTopLeft(find.byKey(ValueKey<String>('messages-conversation-$id')))
          .dy;

      // `전체` 는 대화 목록이다 — 방금 말이 오간 순서로 선다. 노태강은
      // 오늘, 박성호는 사흘 전에 마지막 말이 오갔다. 예전에는 어느
      // 필터에서든 나트륨이 넘친 박성호가 위로 올라와, 방금 답장이 온
      // 회원이 목록 아래에 묻혔다.
      await goTo(tester, AppRoutes.messages);
      expect(topOf('seed-client-13'), lessThan(topOf('seed-client-3')));

      // 같은 날 안에서도 화면 시각 그대로 서야 한다(#1087). 강서연(6,
      // '16:48')·하윤(4, '14:31')·유나(10, '13:25')·태경(13, '11:49')은
      // 모두 오늘이고, 넷 다 대화의 마지막 메시지가 "3개 중 세 번째"라
      // 시드가 배열 인덱스를 그대로 시각으로 썼을 때는 넷의 순서가
      // 시드에 적힌 순서로 뒤섞였다.
      expect(topOf('seed-client-6'), lessThan(topOf('seed-client-4')));
      expect(topOf('seed-client-4'), lessThan(topOf('seed-client-10')));
      expect(topOf('seed-client-10'), lessThan(topOf('seed-client-13')));

      // 여러 날에 걸친 스레드가 같은 날짜 스레드를 부당하게 앞서면 안
      // 된다(#1104). 김민수(1, '18:18', 다일 스레드)는 이지수(2,
      // '20:10', 단일 날짜)보다 이른 시각이니 아래에 서야 한다.
      expect(topOf('seed-client-2'), lessThan(topOf('seed-client-1')));

      // `관리 필요` 는 챙길 사람을 고르는 자리다 — 주의 신호가 앞선다.
      // 노태강은 신호가 없어 목록에서 아예 빠진다.
      await goTo(tester, AppRoutes.messagesFor(null, filter: 'attention'));
      expect(
        find.byKey(
          const ValueKey<String>('messages-conversation-seed-client-13'),
        ),
        findsNothing,
      );
      // 나트륨이 넘친 박성호는 이행률만 낮은 회원보다 위다 — 사흘 전
      // 대화인데도. 최신순이었다면 반대로 섰다.
      expect(topOf('seed-client-3'), lessThan(topOf('seed-client-12')));
    });
  });

  testWidgets('client query keeps the selected member in the thread', (
    tester,
  ) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');
      await goTo(tester, AppRoutes.messagesFor('seed-client-2'));

      expect(
        find.byKey(const ValueKey<String>('messages-thread-seed-client-2')),
        findsOneWidget,
      );
    });
  });

  testWidgets('new workspace labels render in English locale', (tester) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        locale: const Locale('en'),
      );
      await goTo(tester, AppRoutes.messagesFor('seed-client-1'));

      expect(find.text('Messages'), findsWidgets);
      expect(find.text('Conversations'), findsNothing);
      expect(find.textContaining('Unread'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('messages-client-detail-button'),
          ),
          matching: find.text('Member details'),
        ),
        findsOneWidget,
      );
      expect(find.text('프로그램'), findsNothing);
    });
  });

  testWidgets('mobile back keeps the active conversation filter', (
    tester,
  ) async {
    await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');
    await goTo(
      tester,
      AppRoutes.messagesFor('seed-client-1', filter: 'unread'),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);

    final context = tester.element(find.byType(Navigator).first);
    expect(
      GoRouter.of(context)
          .routerDelegate
          .currentConfiguration
          .uri
          .queryParameters['f'],
      'unread',
    );
  });

  testWidgets('detected discomfort can be persisted as a trainer memo', (
    tester,
  ) async {
    await withWideSurface(tester, () async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
      );
      await goTo(tester, AppRoutes.messagesFor('seed-client-1'));

      expect(find.text('무릎 불편 표현 감지'), findsOneWidget);
      final addButton = find.byKey(
        const ValueKey<String>('chat-insight-add-seed-chat-1-16:discomfort'),
      );
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await settle(tester);

      expect(find.text('메모 추가됨'), findsOneWidget);
      // 옮겨 적은 뒤에는 바탕만 비운다 — 붉은 바탕은 "아직 볼 것이 있다"
      // 는 신호라, 처리한 배너와 안 한 배너가 똑같이 붉으면 안 된다.
      // 윤곽선과 버튼의 붉은색은 무슨 일이 있었는지를 남긴다.
      final banner = tester.widget<Container>(
        find.byKey(
          const ValueKey<String>('chat-insight-banner-seed-chat-1-16'),
        ),
      );
      final decoration = banner.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.card);
      expect(
        (decoration.border! as Border).top.color,
        AppColors.warning.withValues(alpha: 0.28),
      );
      expect(
        tester.widget<Text>(find.text('메모 추가됨')).style?.color,
        AppColors.warning,
      );
      // 채팅에서 저장한 메모는 회원 상세가 읽는 것과 **같은** 메모 목록에 들어간다.
      final memos = await container
          .read(trainerMemoRepositoryProvider)
          .fetch('seed-client-1');
      expect(memos, hasLength(1));
      // 원문이 아니라 감지 요약이 남는다 — 프로그램 탭이 이 메모를 그대로
      // 참고 자료로 읽으므로, 그날의 말투가 아니라 조치할 내용이어야 한다.
      expect(memos.single.body, '무릎 불편 감지');
      expect(memos.single.source, TrainerMemoSource.chatInsight);
    });
  });
}
