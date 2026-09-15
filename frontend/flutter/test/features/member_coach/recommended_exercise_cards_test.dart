import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/chat_pdf_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 코칭 포인트 — 운동 주간 데이터의 `aiCoachMessage` 자리에 들어가는 값.

const MemberCoach _trainer = MemberCoach(
  trainerId: 'trainer-1',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '건강한 운동을 돕습니다.',
  gymName: '온케어짐',
  goal: '건강 관리',
);

const CoachRoutine _trainerRoutine = CoachRoutine(
  id: 'trainer-routine',
  name: '코어 스트레칭',
  minutes: 10,
  type: '스트레칭',
  reason: '허리 부담 완화',
  source: 'trainer',
);

const CoachRoutine _aiRoutine = CoachRoutine(
  id: 'ai-routine',
  name: '어깨 관절 보호 스트레칭',
  minutes: 8,
  type: '스트레칭',
  reason: 'PT 피드백 반영 · 오른쪽 어깨 보호',
  source: 'ai',
);

const Trainer _assignedTrainer = Trainer(
  id: 'trainer-assigned',
  gymId: 'trainer-gym',
  name: '김트레이너',
  role: '퍼스널 트레이너',
);

class _ReadFailingMemberCoachRepository extends MockMemberCoachRepository {
  @override
  Future<void> markRead() async {
    throw StateError('읽음 처리 실패');
  }
}

class _SendFailingMemberCoachRepository extends MockMemberCoachRepository {
  @override
  Future<void> sendMessage(String text) async {
    throw StateError('메시지 전송 실패');
  }
}

class _ReadTrackingMemberCoachRepository extends MockMemberCoachRepository {
  int unreadCalls = 0;
  int markReadCalls = 0;
  bool _read = false;

  @override
  Future<int> unreadCount() async {
    unreadCalls += 1;
    return _read ? 0 : 1;
  }

  @override
  Future<void> markRead() async {
    markReadCalls += 1;
    _read = true;
  }
}

class _PdfMemberCoachRepository extends MockMemberCoachRepository {
  static final List<CoachMessage> _messages = <CoachMessage>[
    CoachMessage(
      id: 'pdf-message',
      sender: CoachSender.trainer,
      body: '이번 주 리포트입니다.',
      timeLabel: '18:20',
      createdAt: DateTime(2026, 8, 16, 18, 20),
      attachment: const CoachAttachment(
        kind: CoachAttachmentKind.pdf,
        fileName: '김고객_2026-08-10_주간리포트.pdf',
        fileId: 'pdf-file',
        fileSize: 2048,
        downloadPath: '/chat/attachments/pdf-file',
      ),
    ),
  ];

  @override
  Future<List<CoachMessage>> fetchChat() async => _messages;

  @override
  Stream<List<CoachMessage>> watchChat() => Stream.value(_messages);
}

/// 데모(목업) 설정 — 채팅 화면이 `appConfigProvider` 를 읽어 안내 배너 노출을
/// 가른다. 이 provider 는 기본값 없이 던지므로 테스트마다 넣어 줘야 한다.
const AppConfig _demoConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

/// 채팅 화면 문구는 l10n 에서 온다 — 델리게이트 없이 띄우면 빌드가 실패한다.
Widget _chatApp(Widget home) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('ko'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  Future<void> pumpRecommendationCards(
    WidgetTester tester,
    List<CoachRoutine> routines, {
    MemberCoach? coach = _trainer,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachProvider.overrideWith((ref) async => coach),
          coachRoutinesProvider.overrideWith((ref) async => routines),
          coachUnreadProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: AiCoachingCard(),
                  ),
                  CoachCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('완료한 추천 운동은 글자가 흐려진다 (#1196)', (WidgetTester tester) async {
    const CoachRoutine done = CoachRoutine(
      id: 'done-routine',
      name: '코어 스트레칭',
      minutes: 10,
      type: '스트레칭',
      reason: '허리 부담 완화',
      source: 'trainer',
      completed: true,
    );

    await pumpRecommendationCards(tester, const <CoachRoutine>[
      _aiRoutine,
      done,
    ]);

    Color colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;

    // 남은 줄은 검정 그대로 — 다음에 할 것이 먼저 읽혀야 한다.
    expect(colorOf(_aiRoutine.name), OnCareColors.textPrimary);
    expect(colorOf(done.name), isNot(OnCareColors.textPrimary));
    expect(colorOf(done.reason), isNot(colorOf(_aiRoutine.reason)));
  });

  testWidgets('추천 개인운동 카드가 한 영역에 트레이너·AI 추천을 함께 담는다 (#782)', (
    WidgetTester tester,
  ) async {
    await pumpRecommendationCards(tester, const <CoachRoutine>[
      _trainerRoutine,
      _aiRoutine,
    ]);

    final Finder coaching = find.byType(AiCoachingCard);

    // 예전에는 조언(맨 위)과 추천 운동(맨 아래)이 멀리 떨어져 있었다.
    // 카드 제목은 `AI 코칭` 이 아니라 내용 그대로 `추천 개인운동` 이다 (#1130).
    expect(find.text('추천 개인운동'), findsOneWidget);
    expect(find.text('AI 코칭'), findsNothing);
    // `PT 와 다음 PT 사이…` 안내 문구도 뺐다.
    expect(find.textContaining('다음 PT'), findsNothing);
    // 코칭 포인트는 화면 위쪽의 AI 맞춤 조언 카드로 옮겼다 — 같은 말이 한
    // 화면에 두 번 있으면 안 된다. (#1021)
    expect(
      find.descendant(of: coaching, matching: find.text('이번 코칭 포인트')),
      findsNothing,
    );
    // 트레이너 추천과 AI 추천이 같은 목록에 있다 — 회원에게는 한 가지 질문이다.
    expect(
      find.descendant(of: coaching, matching: find.text(_trainerRoutine.name)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: coaching, matching: find.text(_aiRoutine.name)),
      findsOneWidget,
    );
  });

  testWidgets('추천 운동이 같은 화면에 두 번 나오지 않는다 (#782)', (WidgetTester tester) async {
    await pumpRecommendationCards(tester, const <CoachRoutine>[
      _trainerRoutine,
      _aiRoutine,
    ]);

    // 예전에는 트레이너 추천이 CoachCard 에, AI 추천이 별도 카드에 있었다.
    // 한 곳으로 모았으므로 각 운동은 화면에 한 번만 나와야 한다.
    expect(find.text(_trainerRoutine.name), findsOneWidget);
    expect(find.text(_aiRoutine.name), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CoachCard),
        matching: find.text(_trainerRoutine.name),
      ),
      findsNothing,
    );
  });

  testWidgets('담당 트레이너가 있으면 AI 추천에 확인한 사람을 밝힌다 (#782)', (
    WidgetTester tester,
  ) async {
    await pumpRecommendationCards(tester, const <CoachRoutine>[
      _trainerRoutine,
      _aiRoutine,
    ]);

    // 담당 트레이너가 있으면 AI 추천은 승인된 것만 내려온다(#790).
    expect(find.text('AI 추천 · 김트레이너 확인'), findsOneWidget);
    expect(find.text('트레이너 직접 추천'), findsOneWidget);
    expect(find.text('AI 자동 추천'), findsNothing);
  });

  testWidgets('담당 트레이너가 없으면 AI 자동 추천으로 표시한다 (#782)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachProvider.overrideWith((ref) async => null),
          coachRoutinesProvider.overrideWith(
            (ref) async => const <CoachRoutine>[_aiRoutine],
          ),
          coachUnreadProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AiCoachingCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 자동 추천'), findsOneWidget);
    expect(find.textContaining('확인'), findsNothing);
  });

  testWidgets('추천 운동이 없으면 카드를 그리지 않는다 (#782, #1021)', (
    WidgetTester tester,
  ) async {
    await pumpRecommendationCards(tester, const <CoachRoutine>[]);

    // 코칭 포인트가 이 카드를 떠난 뒤로, 추천이 없으면 카드에 남는 말이 없다.
    expect(find.text('AI 코칭'), findsNothing);
    // 빈 추천 카드를 만들지 않는다 — AI 가 매번 운동을 지어낼 이유가 없다.
    expect(find.text('추천 개인운동'), findsNothing);
    expect(find.text('현재 추천할 수 있는 AI 맞춤 운동이 없어요'), findsNothing);
  });

  testWidgets('담당 트레이너 카드는 관계와 소통만 남긴다 (#782)', (WidgetTester tester) async {
    await pumpRecommendationCards(tester, const <CoachRoutine>[
      _trainerRoutine,
    ]);

    // 프로필 이동과 채팅은 그대로 남는다.
    expect(find.byKey(const Key('assignedTrainerProfile')), findsOneWidget);
    expect(find.text('트레이너와 채팅'), findsOneWidget);
    // 추천 운동 목록은 AI 코칭으로 옮겼다.
    expect(find.text('트레이너 추천 추가 개인운동'), findsNothing);
  });

  testWidgets('여러 세션짜리 프로그램은 프로그램 이름과 세션 구분을 함께 보여 준다 (#709)', (
    WidgetTester tester,
  ) async {
    await pumpRecommendationCards(tester, const <CoachRoutine>[
      CoachRoutine(
        id: 'session-a',
        name: '세션 A · 하체',
        minutes: 30,
        type: '근력',
        reason: '레그프레스, 스쿼트',
        source: 'trainer',
        programName: '주 2회 분할',
        sessionName: '세션 A · 하체',
        exercises: <CoachRoutineExercise>[
          CoachRoutineExercise(
            name: '레그프레스',
            sets: '4',
            reps: '12회',
            weight: '60kg',
          ),
        ],
      ),
      CoachRoutine(
        id: 'session-b',
        name: '세션 B · 유산소',
        minutes: 20,
        type: '유산소',
        reason: '인터벌 러닝',
        source: 'trainer',
        programName: '주 2회 분할',
        sessionName: '세션 B · 유산소',
        sessionOrder: 1,
        exercises: <CoachRoutineExercise>[
          CoachRoutineExercise(name: '인터벌 러닝', duration: '20'),
        ],
      ),
    ]);

    final Finder trainerCard = find.byType(AiCoachingCard);
    // 프로그램 이름은 묶음마다 한 번만 — 세션마다 반복하면 목록이 이름으로 찬다.
    expect(
      find.descendant(of: trainerCard, matching: find.text('주 2회 분할')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trainerCard, matching: find.text('세션 A · 하체')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trainerCard, matching: find.text('세션 B · 유산소')),
      findsOneWidget,
    );
    // 운동 구성이 세트·횟수·중량까지 그대로 보인다.
    expect(
      find.descendant(
        of: trainerCard,
        matching: find.text('레그프레스 · 4세트 × 12회 · 60kg'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trainerCard, matching: find.text('인터벌 러닝 · 20분')),
      findsOneWidget,
    );
  });

  testWidgets('단일 배정은 프로그램 이름표 없이 예전과 같이 보인다 (#709)', (
    WidgetTester tester,
  ) async {
    await pumpRecommendationCards(tester, const <CoachRoutine>[
      _trainerRoutine,
    ]);

    final Finder coaching = find.byType(AiCoachingCard);
    expect(
      find.descendant(of: coaching, matching: find.byIcon(AppIcons.routine)),
      findsNothing,
    );
    expect(
      find.descendant(of: coaching, matching: find.text('허리 부담 완화')),
      findsOneWidget,
    );
  });

  testWidgets('배정 루틴 완료를 기록하고 완료 상태를 갱신한다', (WidgetTester tester) async {
    final MockMemberCoachRepository repository = MockMemberCoachRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repository),
          myTrainerProvider.overrideWith((ref) async => _assignedTrainer),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AiCoachingCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('completeRoutine-seed-routine-user-7d4e9a2c5f18-1')));
    await tester.pumpAndSettle();
    // 화면에서 부르는 이름을 `개인운동` 으로 통일했다(#1457).
    expect(find.text('개인운동 수행 완료'), findsOneWidget);
    // 회원이 운동의 세부 내용을 지정하는 자리는 없다 — 실제 수행 시간 입력은
    // 내려갔고, 남긴 값은 강도와 피드백뿐이다 (#1360).
    expect(find.byKey(const Key('routineCompletionMinutes')), findsNothing);
    final TextField feedback = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('routineCompletionNote')),
        matching: find.byType(TextField),
      ),
    );
    expect(feedback.maxLength, 100);
    await tester.enterText(
      find.byKey(const Key('routineCompletionNote')),
      '허리는 편안했어요',
    );
    await tester.tap(find.text('높음'));
    await tester.tap(find.byKey(const Key('confirmRoutineCompletion')));
    await tester.pumpAndSettle();

    final CoachRoutine completed = (await repository.fetchRoutines())
        .firstWhere((CoachRoutine routine) => routine.id == 'seed-routine-user-7d4e9a2c5f18-1');
    expect(find.text('운동 기록에 반영했어요'), findsOneWidget);
    expect(find.text('내 피드백: 허리는 편안했어요'), findsOneWidget);
    // 체크 박스는 그대로 있고 체크된 채로 남는다 — 한 일이 화면에서 사라지면
    // 무엇을 했는지 다시 확인할 데가 없다. (#1021) 다시 누르면 되묻고 되돌릴
    // 수 있으므로 잠기지 않는다 (#1131).
    final Checkbox box = tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(const Key('completeRoutine-seed-routine-user-7d4e9a2c5f18-1')),
        matching: find.byType(Checkbox),
      ),
    );
    expect(box.value, isTrue);
    expect(box.onChanged, isNotNull);
    expect(completed.completedIntensity, 'high');
    // 기록에 남는 시간은 배정된 값 그대로다 (#1360).
    expect(completed.completedMinutes, 15);
  });

  testWidgets('완료한 루틴에 트레이너 피드백을 표시한다', (WidgetTester tester) async {
    await pumpRecommendationCards(tester, const <CoachRoutine>[
      CoachRoutine(
        id: 'done',
        name: '완료 루틴',
        minutes: 20,
        type: '근력',
        reason: '',
        source: 'trainer',
        completed: true,
        trainerFeedback: '자세가 좋았어요',
      ),
    ]);

    expect(find.text('트레이너 피드백: 자세가 좋았어요'), findsOneWidget);
    expect(find.byKey(const Key('routineFeedback-done')), findsOneWidget);
  });

  testWidgets('담당 트레이너 프로필은 트레이너 상세 경로로 이동한다', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: CoachCard()),
        ),
        GoRoute(
          path: AppRoutes.trainerDetail,
          builder: (_, GoRouterState state) => Scaffold(
            body: Text('trainer:${state.pathParameters['trainerId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachProvider.overrideWith((ref) async => _trainer),
          coachRoutinesProvider.overrideWith(
            (ref) async => const <CoachRoutine>[],
          ),
          coachUnreadProvider.overrideWith((ref) async => 0),
          myTrainerProvider.overrideWith((ref) async => _assignedTrainer),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assignedTrainerProfile')));
    await tester.pumpAndSettle();

    expect(find.text('trainer:${_assignedTrainer.id}'), findsOneWidget);
  });

  testWidgets('트레이너 채팅은 말풍선 가장자리 시간과 입력창을 표시하고 메시지를 전송한다', (
    WidgetTester tester,
  ) async {
    final repository = MockMemberCoachRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repository),
          appConfigProvider.overrideWithValue(_demoConfig),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              floatingActionButton: const FloatingActionButton(
                key: Key('underlyingFloatingButton'),
                onPressed: null,
              ),
              body: Center(
                child: ElevatedButton(
                  key: const Key('openTrainerChat'),
                  onPressed: () =>
                      openTrainerChatPage(context, trainerName: '김트레이너'),
                  child: const Text('채팅 열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openTrainerChat')));
    await tester.pumpAndSettle();

    expect(find.byType(TrainerChatPage), findsOneWidget);
    expect(find.byKey(const Key('underlyingFloatingButton')), findsNothing);
    expect(find.text('김트레이너'), findsOneWidget);
    expect(find.text('담당 트레이너 · 상담 가능'), findsOneWidget);
    // 말풍선 검사는 **마지막** 트레이너 메시지로 한다. 대화가 3일치로 늘면서
    // 화면은 맨 아래에서 열리므로, 첫 메시지는 뷰포트 밖이라 좌표를 잴 수 없다.
    expect(find.text('김트레이너 · 18:18'), findsNothing);
    expect(find.text('18:18'), findsOneWidget);
    final Finder trainerBubble = find.byKey(
      const Key('coach-message-bubble-seed-m18'),
    );
    final Finder trainerAvatar = find.byKey(
      const Key('coach-message-avatar-seed-m18'),
    );
    // 시간은 규격 말풍선(AppChatBubble)이 옆에 붙이는 AppChatTimestamp 다.
    final Finder trainerTime = find.descendant(
      of: find.byKey(const ValueKey<String>('coach-message-seed-m18')),
      matching: find.byType(AppChatTimestamp),
    );
    expect(
      tester.getTopLeft(trainerTime).dx,
      greaterThan(tester.getTopRight(trainerBubble).dx),
    );
    expect(
      tester.getBottomLeft(trainerAvatar).dy,
      closeTo(tester.getBottomLeft(trainerTime).dy, 0.1),
    );
    // 받은 말풍선 = 흰 카드, 보낸 쪽(왼쪽) 아래 모서리만 작다.
    final BoxDecoration trainerBubbleDecoration =
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: trainerBubble,
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(trainerBubbleDecoration.color, OnCareColors.surfaceCard);
    expect(
      trainerBubbleDecoration.borderRadius,
      const BorderRadius.only(
        topLeft: OnCareRadius.lg,
        topRight: OnCareRadius.lg,
        bottomLeft: OnCareRadius.xs,
        bottomRight: OnCareRadius.lg,
      ),
    );
    expect(find.text('트레이너에게 메시지 보내기...'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '운동 후 확인할게요');
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    expect(find.text('운동 후 확인할게요'), findsOneWidget);
    expect(find.textContaining('나 ·'), findsNothing);
    final Finder sentBubble = find
        .ancestor(of: find.text('운동 후 확인할게요'), matching: find.byType(Container))
        .first;
    final BoxDecoration sentBubbleDecoration =
        tester.widget<Container>(sentBubble).decoration! as BoxDecoration;
    expect(sentBubbleDecoration.color, OnCareBrand.member.primary);
    expect(
      sentBubbleDecoration.borderRadius,
      const BorderRadius.only(
        topLeft: OnCareRadius.lg,
        topRight: OnCareRadius.lg,
        bottomLeft: OnCareRadius.lg,
        bottomRight: OnCareRadius.xs,
      ),
    );

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();

    expect(find.byType(TrainerChatPage), findsNothing);
    expect(find.byKey(const Key('underlyingFloatingButton')), findsOneWidget);
  });

  testWidgets('읽음 처리가 실패해도 대화 목록을 표시한다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(
            _ReadFailingMemberCoachRepository(),
          ),
          appConfigProvider.overrideWithValue(_demoConfig),
        ],
        child: _chatApp(const TrainerChatPage(trainerName: '김트레이너')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('확인했어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('읽음 처리 후 unread count를 갱신한다', (WidgetTester tester) async {
    final repository = _ReadTrackingMemberCoachRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repository),
          appConfigProvider.overrideWithValue(_demoConfig),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              ref.watch(coachUnreadProvider);
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      openTrainerChatPage(context, trainerName: '김트레이너'),
                  child: const Text('채팅 열기'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.unreadCalls, 1);

    await tester.tap(find.text('채팅 열기'));
    await tester.pumpAndSettle();

    expect(repository.markReadCalls, 1);
    expect(repository.unreadCalls, 2);
  });

  testWidgets('메시지 전송이 실패하면 입력 내용을 유지한다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(
            _SendFailingMemberCoachRepository(),
          ),
          appConfigProvider.overrideWithValue(_demoConfig),
        ],
        child: _chatApp(const TrainerChatPage(trainerName: '김트레이너')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '다시 보낼 메시지');
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    final TextField input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, '다시 보낼 메시지');
    expect(find.text('메시지 전송에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
  });

  testWidgets('PDF attachment를 파일명과 크기가 있는 카드로 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(
            _PdfMemberCoachRepository(),
          ),
          appConfigProvider.overrideWithValue(_demoConfig),
        ],
        child: _chatApp(const TrainerChatPage(trainerName: '김트레이너')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coach-pdf-pdf-file')), findsOneWidget);
    expect(find.text('김고객_2026-08-10_주간리포트.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.byIcon(AppIcons.file), findsOneWidget);
  });

  // 카드를 눌렀을 때 정말 그 첨부의 경로로 내려받는지, 실패하면 회원이 이유를
  // 보는지까지 확인한다. 성공 경로의 미리보기(PdfPreview)는 printing 플러그인의
  // 플랫폼 채널을 타므로 위젯 테스트에서 띄우지 않는다 — 실패 경로가 탭→다운로드
  // 호출과 안내 문구를 함께 덮는다.
  testWidgets('PDF 카드를 누르면 그 첨부 경로로 내려받고, 실패하면 안내 문구를 띄운다', (tester) async {
    final _FailingChatPdfRepository repository = _FailingChatPdfRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(
            _PdfMemberCoachRepository(),
          ),
          chatPdfRepositoryProvider.overrideWithValue(repository),
          appConfigProvider.overrideWithValue(_demoConfig),
        ],
        child: _chatApp(const TrainerChatPage(trainerName: '김트레이너')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coach-pdf-pdf-file')));
    await tester.pumpAndSettle();

    expect(repository.paths, <String>['/chat/attachments/pdf-file']);
    expect(find.text('PDF를 열지 못했어요. 다시 시도해 주세요'), findsOneWidget);
  });

  testWidgets('담당 트레이너가 없으면 개인 운동을 스스로 취소할 수 있다 (#1020)', (
    WidgetTester tester,
  ) async {
    await pumpRecommendationCards(
      tester,
      <CoachRoutine>[_aiRoutine],
      coach: null,
    );

    expect(find.byKey(Key('cancelRoutine-${_aiRoutine.id}')), findsOneWidget);
  });

  testWidgets('담당 트레이너가 있으면 취소는 트레이너의 일이다 (#1020)', (
    WidgetTester tester,
  ) async {
    await pumpRecommendationCards(tester, <CoachRoutine>[_aiRoutine]);

    // 담당이 배정한 것을 회원이 조용히 없애면 다음 상담에서 둘이 서로 다른
    // 기록을 본다 — 버튼 자체를 그리지 않는다(서버도 403 으로 막는다).
    expect(find.byKey(Key('cancelRoutine-${_aiRoutine.id}')), findsNothing);
  });

}

/// 내려받기가 항상 실패하는 저장소. 요청된 경로를 기록해 둔다.
class _FailingChatPdfRepository extends ChatPdfRepository {
  _FailingChatPdfRepository() : super(Dio());

  final List<String> paths = <String>[];

  @override
  Future<Uint8List> download(String path) async {
    paths.add(path);
    throw Exception('download failed');
  }
}
