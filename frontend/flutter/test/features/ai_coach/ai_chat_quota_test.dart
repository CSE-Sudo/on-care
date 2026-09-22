import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

AiChatQuota _quota({required int paidLeft, required int balance}) =>
    AiChatQuota(
      freeLimit: 10,
      freeLeft: 0,
      paidLimit: 10,
      paidLeft: paidLeft,
      cost: 50,
      balance: balance,
      next: paidLeft > 0 ? AiChatNext.paid : AiChatNext.exhausted,
    );

/// 오늘 무료를 다 쓴 회원 — 보내면 50P 가 나간다.
class _PaidRepository implements AiCoachRepository {
  _PaidRepository(this.quota);

  AiChatQuota quota;
  final List<bool> paid = <bool>[];

  @override
  Future<AiChatQuota> fetchQuota() async => quota;

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
    bool payWithPoints = false,
    String? clientRequestId,
  }) async {
    paid.add(payWithPoints);
    quota = _quota(paidLeft: quota.paidLeft - 1, balance: quota.balance - 50);
    return ChatMessage(
      role: ChatRole.coach,
      content: '물을 한 컵 더 드세요.',
      pointsSpent: 50,
      balanceAfter: quota.balance,
      replyQuota: quota,
    );
  }

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<List<ChatMessage>> fetchHistory() async => const <ChatMessage>[];

  @override
  Future<ChatInsightHistory> fetchInsights() async =>
      const ChatInsightHistory();

  @override
  Future<void> dismissInsight(String messageId) async {}
}

void main() {
  Future<void> pump(WidgetTester tester, _PaidRepository repo) async {
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
  }

  testWidgets('무료를 다 쓰면 한 번 묻고 50P 로 보낸 뒤 답변 아래에 차감을 적는다 (#2145)', (
    tester,
  ) async {
    final _PaidRepository repo = _PaidRepository(
      _quota(paidLeft: 10, balance: 200),
    );
    await pump(tester, repo);
    expect(find.text('다음 대화 50P · 오늘 구매 0/10 · 남은 포인트 200P'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '물 얼마나?');
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();
    // 확인창이 먼저 뜨고, 동의하기 전에는 보내지 않는다.
    expect(repo.paid, isEmpty);
    await tester.tap(find.text('포인트로 보내기'));
    await tester.pumpAndSettle();

    expect(repo.paid, <bool>[true]);
    expect(find.text('−50P · 남은 포인트 150P'), findsOneWidget);
    expect(find.text('다음 대화 50P · 오늘 구매 1/10 · 남은 포인트 150P'), findsOneWidget);

    // 그날은 다시 묻지 않는다.
    await tester.enterText(find.byType(TextField), '한 번 더');
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();
    expect(repo.paid, <bool>[true, true]);
  });

  testWidgets('오늘 다 쓰면 내일 다시 열린다고 알리고 트레이너 찾기를 건넨다', (tester) async {
    await pump(tester, _PaidRepository(_quota(paidLeft: 0, balance: 500)));

    expect(find.text('오늘 대화를 다 썼어요. 내일 다시 열려요'), findsOneWidget);
    expect(find.byKey(const Key('aiCoachFindTrainer')), findsOneWidget);
    // 눌러도 보낼 수 없는 빠른 질문은 띄우지 않는다.
    expect(find.text('이런 걸 물어보세요'), findsNothing);
  });
}
