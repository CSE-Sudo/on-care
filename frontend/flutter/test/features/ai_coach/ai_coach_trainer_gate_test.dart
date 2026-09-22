import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/coaching_sheet.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'free_quota.dart';

/// 담당 트레이너가 있는 회원은 AI 챗봇을 쓰지 않는다. 대화는 30일만 남고, 머리의
/// 초록 점은 없다(#1823).

const MemberCoach _coach = MemberCoach(
  trainerId: 'coach-1',
  name: '김트레이너',
  specialty: '체형 교정',
  career: '5년',
  intro: '',
  gymName: '신촌 짐',
  goal: '',
);

class _CountingRepository implements AiCoachRepository {
  int historyCalls = 0;
  int insightCalls = 0;

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<void> dismissInsight(String messageId) async {}

  @override
  Future<AiChatQuota> fetchQuota() async => kFreeQuota;

  @override
  Future<ChatInsightHistory> fetchInsights() async {
    insightCalls += 1;
    return const ChatInsightHistory();
  }

  @override
  Future<List<ChatMessage>> fetchHistory() async {
    historyCalls += 1;
    return const <ChatMessage>[];
  }

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
    bool payWithPoints = false,
    String? clientRequestId,
  }) async => const ChatMessage(role: ChatRole.coach, content: '네');
}

final AppLocalizations _l = lookupAppLocalizations(const Locale('ko'));

Future<void> _pumpPage(
  WidgetTester tester, {
  required _CountingRepository repo,
  required MemberCoach? coach,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        aiCoachRepositoryProvider.overrideWithValue(repo),
        memberCoachProvider.overrideWith((ref) => coach),
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

void main() {
  group('AI 챗봇 화면', () {
    testWidgets('담당 트레이너가 있으면 대화 대신 트레이너 채팅을 안내하고 대화를 불러오지 않는다', (
      WidgetTester tester,
    ) async {
      final _CountingRepository repo = _CountingRepository();
      await _pumpPage(tester, repo: repo, coach: _coach);

      expect(find.byKey(const Key('aiCoachTrainerConnected')), findsOneWidget);
      expect(find.text(_l.aicTrainerConnectedTitle), findsOneWidget);
      expect(find.text(_l.aicTrainerConnectedBody('김트레이너')), findsOneWidget);
      expect(find.text(_l.coachChatWithTrainer), findsOneWidget);
      expect(find.byType(AppChatInputBar), findsNothing);
      // 실서버는 이 회원의 대화·감지 기록 조회를 거절한다 — 부르지도 않는다.
      expect(repo.historyCalls, 0);
      expect(
        find.byKey(const Key('aiCoachInsightHistoryButton')).hitTestable(),
        findsNothing,
      );
    });

    testWidgets('담당 트레이너가 없으면 대화를 열고 30일 보관 안내를 보여 준다', (
      WidgetTester tester,
    ) async {
      final _CountingRepository repo = _CountingRepository();
      await _pumpPage(tester, repo: repo, coach: null);

      expect(find.byKey(const Key('aiCoachTrainerConnected')), findsNothing);
      expect(find.byType(AppChatInputBar), findsOneWidget);
      expect(repo.historyCalls, 1);
      expect(
        find.text(_l.aicRetentionNotice(kAiChatRetentionDays)),
        findsOneWidget,
      );
      expect(find.text('AI 챗봇 대화는 최근 30일 동안만 보관돼요'), findsOneWidget);
      expect(
        find.byKey(const Key('aiCoachInsightHistoryButton')).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('머리의 AI 캐릭터 옆에 초록 점을 그리지 않는다', (WidgetTester tester) async {
      await _pumpPage(tester, repo: _CountingRepository(), coach: null);

      // 늘 켜져 있는 초록 점은 트레이너 온라인 표시와 같은 모양이라, AI 가 사람처럼
      // 접속해 있다는 뜻으로 읽혔다.
      expect(find.byType(AppStatusDot), findsNothing);
    });

    testWidgets('영어에서도 보관 안내가 기간을 말한다', (WidgetTester tester) async {
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      expect(
        en.aicRetentionNotice(kAiChatRetentionDays),
        'AI chat history is kept for the last 30 days',
      );
    });
  });

  group('AI 건강 도우미 시트 버튼', () {
    Future<void> pumpSheet(WidgetTester tester, {MemberCoach? coach}) async {
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showCoachingSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.aiCoach,
            builder: (_, _) => const Scaffold(body: Text('ai-coach-route')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(
              const AppConfig(
                environment: Environment.dev,
                apiBaseUrl: 'http://localhost',
                useMockApi: true,
              ),
            ),
            memberCoachProvider.overrideWith((ref) => coach),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder ctaLabel(String label) => find.descendant(
      of: find.byKey(const Key('coachingSheetCta')),
      matching: find.text(label),
    );

    testWidgets('담당 트레이너가 있으면 트레이너 채팅 버튼이다', (WidgetTester tester) async {
      await pumpSheet(tester, coach: _coach);

      expect(ctaLabel(_l.coachChatWithTrainer), findsOneWidget);
      expect(ctaLabel(_l.coachCtaChat), findsNothing);
    });

    testWidgets('담당 트레이너가 없으면 AI 챗봇으로 간다', (WidgetTester tester) async {
      await pumpSheet(tester);

      expect(ctaLabel(_l.coachCtaChat), findsOneWidget);
      await tester.tap(ctaLabel(_l.coachCtaChat));
      await tester.pumpAndSettle();

      expect(find.text('ai-coach-route'), findsOneWidget);
    });
  });
}
