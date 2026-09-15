import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';

import '../../helpers/fake_diet_repository.dart';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

class _FakeAiCoachRepository implements AiCoachRepository {
  @override
  Future<AiCoachState> fetchState() async {
    return const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);
  }

  @override
  Future<ChatInsightHistory> fetchInsights() async =>
      const ChatInsightHistory();

  @override
  Future<List<ChatMessage>> fetchHistory() async => const <ChatMessage>[];

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
  }) async {
    return const ChatMessage(role: ChatRole.coach, content: '확인했어요');
  }
}

/// 조회 횟수를 세는 식단 저장소 대역.
///
/// 세션 리셋이 식단 화면의 provider 를 실제로 무효화하는지 확인한다. 저장소
/// 인스턴스가 다시 만들어지는지로는 더 이상 확인할 수 없다 — 지금 저장소는
/// 상태를 들지 않으므로 리셋해도 같은 인스턴스가 그대로 쓰인다(#616).
class _CountingDietRepository extends FakeDietRepository {
  int fetchTodayCalls = 0;

  @override
  Future<DietDay> fetchToday() {
    fetchTodayCalls++;
    return super.fetchToday();
  }
}

void main() {
  // 리셋이 훑는 provider 중 일부가 drift 를 타므로(#616 이후 식단 계열 포함)
  // 바인딩과 인메모리 DB 가 필요하다. 파일 DB 를 열면 기기 저장소에 의존한다.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'session reset clears mutable account state and recreates mock roots',
    () async {
      var accountId = 'account-a';
      final _CountingDietRepository diet = _CountingDietRepository();
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_mockConfig),
          dietRepositoryProvider.overrideWithValue(diet),
          appDatabaseProvider.overrideWithValue(db),
          aiCoachRepositoryProvider.overrideWith(
            (ref) => _FakeAiCoachRepository(),
          ),
          coachSessionsProvider.overrideWith((ref) async {
            return <CoachSession>[
              CoachSession(
                id: '$accountId-session',
                date: DateTime(2026, 8, 10),
                time: '18:00',
                type: '1:1 PT',
                durationMinutes: 50,
                status: '완료',
              ),
            ];
          }),
          // 식단 저장소가 Dio 를 타면서 로거가 필요해졌다(#616).
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          sessionFeatureResetOverride(),
        ],
      );
      addTearDown(container.dispose);

      await container.read(chatControllerProvider.notifier).send('A 사용자 메시지');
      await container
          .read(notificationControllerProvider.notifier)
          .markAllRead();
      container.read(exerciseRoutineDoneProvider.notifier).state = <bool>[
        true,
        false,
      ];

      final MemberCoachRepository memberCoachBefore = container.read(
        memberCoachRepositoryProvider,
      );
      expect(
        (await container.read(coachSessionsProvider.future)).single.id,
        'account-a-session',
      );
      await memberCoachBefore.sendMessage('A 사용자 트레이너 메시지');

      await container.read(dietTodayProvider.future);
      expect(diet.fetchTodayCalls, 1);

      final Object exerciseRepositoryBefore = container.read(
        exerciseRepositoryProvider,
      );
      final Object gymRepositoryBefore = container.read(gymRepositoryProvider);

      expect(
        container
            .read(chatControllerProvider)
            .messages
            .any((ChatMessage message) => message.content == 'A 사용자 메시지'),
        isTrue,
      );
      expect(container.read(notificationControllerProvider).unreadCount, 0);
      // 시드 15개 + 방금 보낸 1개. 개수를 상수로 적으면 시드가 늘 때마다
      // 여기가 깨지므로, 시드 길이는 새 리포지토리에서 읽어 비교한다.
      final int seedLength =
          (await MockMemberCoachRepository().fetchChat()).length;
      expect(await memberCoachBefore.fetchChat(), hasLength(seedLength + 1));

      // 리셋 직전 호출 수를 잡아 둔다. 홈 요약도 같은 저장소를 읽으므로 절대
      // 횟수를 못 박으면 무관한 provider 가 늘 때마다 여기가 깨진다. 확인하려는
      // 성질은 "리셋 뒤 다시 조회한다" 하나다.
      final int dietFetchesBeforeReset = diet.fetchTodayCalls;

      accountId = 'account-b';
      container.read(sessionFeatureResetProvider)();

      expect(
        container
            .read(chatControllerProvider)
            .messages
            .any((ChatMessage message) => message.content == 'A 사용자 메시지'),
        isFalse,
      );
      expect(
        container.read(notificationControllerProvider).unreadCount,
        greaterThan(0),
      );
      expect(container.read(exerciseRoutineDoneProvider), <bool>[false, false]);
      expect(
        (await container.read(coachSessionsProvider.future)).single.id,
        'account-b-session',
      );

      final MemberCoachRepository memberCoachAfter = container.read(
        memberCoachRepositoryProvider,
      );
      expect(identical(memberCoachAfter, memberCoachBefore), isFalse);
      expect(await memberCoachAfter.fetchChat(), hasLength(seedLength));
      // 식단은 저장소 인스턴스가 아니라 **다시 조회하는지**로 확인한다. 저장소가
      // 상태를 들지 않게 되면서(#616) 리셋해도 같은 인스턴스가 그대로 쓰이므로,
      // 인스턴스 비교로는 리셋이 동작하는지 알 수 없다.
      await container.read(dietTodayProvider.future);
      expect(diet.fetchTodayCalls, greaterThan(dietFetchesBeforeReset));
      expect(
        identical(
          container.read(exerciseRepositoryProvider),
          exerciseRepositoryBefore,
        ),
        isFalse,
      );
      expect(
        identical(container.read(gymRepositoryProvider), gymRepositoryBefore),
        isFalse,
      );
    },
  );
}
