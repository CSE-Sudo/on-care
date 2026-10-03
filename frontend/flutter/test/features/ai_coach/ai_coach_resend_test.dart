/// 온이 채팅의 보내지 못한 메시지 — 화면에 남고, `다시 보내기` 로 같은 키를 다시
/// 보내며, 길게 누르면 입력칸으로 돌아온다. (#2846)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show keepWords;

import 'free_quota.dart';

class _FlakyRepository implements AiCoachRepository {
  bool fail = true;
  final List<String?> keys = <String?>[];

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<void> dismissInsight(String messageId) async {}

  @override
  Future<AiChatQuota> fetchQuota() async => kFreeQuota;

  @override
  Future<ChatInsightHistory> fetchInsights() async =>
      const ChatInsightHistory();

  @override
  Future<List<ChatMessage>> fetchHistory() async => const <ChatMessage>[];

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
    bool payWithPoints = false,
    String? clientRequestId,
  }) async {
    keys.add(clientRequestId);
    if (fail) throw const NetworkError();
    return const ChatMessage(role: ChatRole.coach, content: '도착한 답');
  }
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _FlakyRepository repo,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[aiCoachRepositoryProvider.overrideWithValue(repo)],
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
  return AppLocalizations.of(tester.element(find.byType(AICoachPage)));
}

Future<void> _type(WidgetTester tester, String text, AppLocalizations l) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip(l.a11ySendMessage));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('전송이 실패해도 보낸 글이 남고 보내지 못함과 다시 보내기가 보인다', (
    WidgetTester tester,
  ) async {
    final _FlakyRepository repo = _FlakyRepository();
    final AppLocalizations l = await _pump(tester, repo);

    await _type(tester, '아주 긴 질문', l);

    expect(find.text('아주 긴 질문'), findsOneWidget);
    expect(find.byKey(const Key('aiCoachFailedLabel')), findsOneWidget);
    expect(find.text(l.aicSendFailedMine), findsOneWidget);
    expect(find.byKey(const Key('aiCoachResend')), findsOneWidget);
    // 입력칸은 비어 있다 — 새로 쓰면 새 키라 두 번 세질 수 있다.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('다시 보내기를 누르면 같은 키로 가고 답이 실패 안내를 대신한다', (
    WidgetTester tester,
  ) async {
    final _FlakyRepository repo = _FlakyRepository();
    final AppLocalizations l = await _pump(tester, repo);
    await _type(tester, '질문', l);

    repo.fail = false;
    await tester.tap(find.byKey(const Key('aiCoachResend')));
    await tester.pumpAndSettle();

    expect(repo.keys, hasLength(2));
    expect(repo.keys.first, repo.keys.last);
    expect(find.text(keepWords('도착한 답')), findsOneWidget);
    expect(find.byKey(const Key('aiCoachFailedLabel')), findsNothing);
    expect(find.byKey(const Key('aiCoachResend')), findsNothing);
    expect(find.text(l.aiCoachFailure), findsNothing);
  });

  testWidgets('보내지 못한 글을 길게 누르면 입력칸으로 돌아온다', (WidgetTester tester) async {
    final _FlakyRepository repo = _FlakyRepository();
    final AppLocalizations l = await _pump(tester, repo);
    await _type(tester, '고칠 질문', l);

    await tester.longPress(find.text('고칠 질문'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '고칠 질문',
    );
    expect(find.byKey(const Key('aiCoachFailedMessage')), findsNothing);
  });
}
