import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 답을 붙잡아 두는 저장소 — 대기 중 말풍선을 검사할 때 쓴다.
class _SlowRepository implements AiCoachRepository {
  _SlowRepository();

  final Completer<ChatMessage> reply = Completer<ChatMessage>();

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<List<ChatMessage>> fetchHistory() async => const <ChatMessage>[];

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
  }) => reply.future;
}

/// 화면만 그리면 되므로 대화는 비워 둔다.
class _QuietRepository implements AiCoachRepository {
  const _QuietRepository();

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<List<ChatMessage>> fetchHistory() async => const <ChatMessage>[];

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
  }) async => const ChatMessage(role: ChatRole.coach, content: '네');
}

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          aiCoachRepositoryProvider.overrideWithValue(const _QuietRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AICoachPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 두 아이콘 모두 예전에는 눌리는 것처럼 보이면서 아무 동작이 없었다(#783).
  // 다시 그려 넣는다면 그때는 실제 동작을 달아야 하므로, 아이콘이 있다는 것
  // 자체를 실패로 잡는다.
  testWidgets('헤더에 동작 없는 더보기 버튼을 그리지 않는다', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.byIcon(Symbols.more_horiz_rounded), findsNothing);
  });

  testWidgets('입력창에 동작 없는 추가 버튼을 그리지 않는다', (WidgetTester tester) async {
    await pumpPage(tester);

    // 보내기 버튼을 함께 확인한다 — 입력창이 그려지지도 않았는데 findsNothing
    // 이라 통과하는 빈 검사가 되지 않도록.
    expect(find.byIcon(AppIcons.send), findsOneWidget);
    expect(find.byIcon(AppIcons.add), findsNothing);
  });

  // 점 세 개만 깜빡이면 무엇을 기다리는지 알 수 없다(#1180).
  testWidgets('답을 기다리는 동안 생성 중 문구를 보여 준다', (WidgetTester tester) async {
    final _SlowRepository repo = _SlowRepository();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          aiCoachRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AICoachPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
    expect(find.text(l.aicGeneratingReply), findsNothing);

    await tester.tap(find.text(l.aicQuickReply1));
    await tester.pump();
    expect(find.text(l.aicGeneratingReply), findsOneWidget);

    repo.reply.complete(
      const ChatMessage(role: ChatRole.coach, content: '닭가슴살 채소구이를 추천해요'),
    );
    await tester.pumpAndSettle();
    expect(find.text(l.aicGeneratingReply), findsNothing);
    expect(find.text('닭가슴살 채소구이를 추천해요'), findsOneWidget);
  });

  testWidgets('살아 있는 버튼은 그대로 남는다', (WidgetTester tester) async {
    await pumpPage(tester);

    // 죽은 버튼을 지우면서 뒤로 가기까지 함께 지우는 실수를 막는다.
    expect(find.byIcon(AppIcons.back), findsOneWidget);
  });
}
