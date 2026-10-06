/// 담당 해제·조회 실패를 회원 앱이 알아채고 구분해 보여 준다. (#2843)
///
/// 담당 코치(`memberCoachProvider`)는 앱을 켤 때 한 번 읽은 값을 계속 썼다.
/// 그래서 앱을 떠난 사이 트레이너가 담당을 해제하면 돌아와도 트레이너 화면이
/// 남았고, 열려 있던 대화방은 안내 없이 비었다. 반대로 조회가 실패하면 홈
/// 트레이너 카드가 사라져 연결된 회원에게 트레이너가 없는 것처럼 보였다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const MemberCoach _coach = MemberCoach(
  trainerId: 'coach-1',
  name: '김트레이너',
  specialty: '체형 교정',
  career: '5년',
  intro: '',
  gymName: '신촌 짐',
  goal: '',
);

const AppConfig _real = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: false,
);

/// 담당 여부를 바꿀 수 있고, 다시 읽은 횟수를 센다.
class _SwitchableCoachRepository extends MockMemberCoachRepository {
  _SwitchableCoachRepository();

  bool assigned = true;
  bool failCoach = false;
  int coachLoads = 0;
  int sessionLoads = 0;

  @override
  Future<MemberCoach?> fetchCoach() async {
    coachLoads += 1;
    if (failCoach) throw Exception('offline');
    return assigned ? _coach : null;
  }

  @override
  Future<List<CoachSession>> fetchSessions() async {
    sessionLoads += 1;
    return const <CoachSession>[];
  }
}

void main() {
  group('invalidateCoachBoundData', () {
    test('연결 해제와 같은 묶음(배정 운동·PT 일정·대화·미읽음)을 비운다', () {
      final List<ProviderOrFamily> invalidated = <ProviderOrFamily>[];

      invalidateCoachBoundData(invalidated.add);

      expect(
        invalidated,
        unorderedEquals(<ProviderOrFamily>[
          coachRoutinesProvider,
          coachSessionsProvider,
          coachChatProvider,
          coachUnreadProvider,
        ]),
      );
    });
  });

  group('recheckMemberCoach', () {
    late _SwitchableCoachRepository repo;
    late ProviderContainer container;

    setUp(() async {
      repo = _SwitchableCoachRepository();
      container = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repo),
        ],
      );
      // 화면이 보고 있는 것처럼 붙잡아 둔다.
      container.listen(memberCoachProvider, (_, _) {});
      container.listen(coachSessionsProvider, (_, _) {});
      await container.read(memberCoachProvider.future);
      await container.read(coachSessionsProvider.future);
    });

    tearDown(() => container.dispose());

    test('해제됐으면 담당 코치가 비고 딸린 묶음도 다시 읽는다', () async {
      expect(repo.sessionLoads, 1);
      repo.assigned = false;

      await recheckMemberCoach(container);

      expect(container.read(memberCoachProvider).valueOrNull, isNull);
      expect(repo.coachLoads, 2);
      await container.read(coachSessionsProvider.future);
      expect(repo.sessionLoads, 2);
    });

    test('담당이 그대로면 담당만 다시 읽고 묶음은 건드리지 않는다', () async {
      await recheckMemberCoach(container);

      expect(repo.coachLoads, 2);
      expect(container.read(memberCoachProvider).valueOrNull, _coach);
      await container.read(coachSessionsProvider.future);
      expect(repo.sessionLoads, 1);
    });

    test('다시 읽다 실패하면 해제로 보지 않는다', () async {
      repo.failCoach = true;

      await recheckMemberCoach(container);

      expect(repo.coachLoads, 2);
      await container.read(coachSessionsProvider.future);
      expect(repo.sessionLoads, 1);
    });
  });

  group('해제된 대화방', () {
    Future<_SwitchableCoachRepository> pumpChat(
      WidgetTester tester, {
      Locale locale = const Locale('ko'),
    }) async {
      final _SwitchableCoachRepository repo = _SwitchableCoachRepository();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(_real),
            memberCoachRepositoryProvider.overrideWithValue(repo),
            coachChatProvider.overrideWith(
              (ref) => Stream<List<CoachMessage>>.error(
                const CoachUnassignedException(),
              ),
            ),
            coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
            sentReportNoticesProvider.overrideWith(
              (ref) async => const <SentReportNotice>[],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TrainerChatPage(trainerName: '김트레이너'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('빈 대화 대신 해제 안내를 띄우고 입력을 막는다', (WidgetTester tester) async {
      await pumpChat(tester);

      expect(
        find.byKey(const ValueKey<String>('coach-chat-unassigned')),
        findsOneWidget,
      );
      expect(find.text('담당이 해제되어 더 이상 메시지를 보낼 수 없어요'), findsOneWidget);
      // 일반 불러오기 실패 문구와는 다르다.
      expect(find.text('대화를 불러오지 못했어요'), findsNothing);

      final AppChatInputBar input = tester.widget<AppChatInputBar>(
        find.byType(AppChatInputBar),
      );
      expect(input.enabled, isFalse);
    });

    testWidgets('해제를 알게 되면 담당 코치도 다시 읽는다', (WidgetTester tester) async {
      final _SwitchableCoachRepository repo = await pumpChat(tester);

      // 대화방은 담당 코치를 보지 않는다 — 다시 읽은 것은 해제 신호 덕분이다.
      expect(repo.coachLoads, greaterThanOrEqualTo(1));
    });

    testWidgets('영어 안내도 해제를 말한다', (WidgetTester tester) async {
      await pumpChat(tester, locale: const Locale('en'));

      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.coachChatUnassigned), findsOneWidget);
      expect(en.coachChatUnassigned, isNot(en.coachChatLoadFailed));
    });
  });

  group('데모', () {
    test('트레이너를 끊으면 대화도 해제 신호를 준다', () async {
      final MockGymRepository gym = MockGymRepository();
      final MockMemberCoachRepository coach = MockMemberCoachRepository(
        linked: () => gym.hasTrainer,
      );
      expect(await coach.fetchChat(), isNotEmpty);

      await gym.disconnectMyTrainer();

      await expectLater(
        coach.fetchChat(),
        throwsA(isA<CoachUnassignedException>()),
      );
      await expectLater(
        coach.watchChat().first,
        throwsA(isA<CoachUnassignedException>()),
      );
    });

    test('해제된 뒤 받은 리포트 목록은 오류가 아니라 빈 목록이다', () async {
      final MockGymRepository gym = MockGymRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(linked: () => gym.hasTrainer),
          ),
        ],
      );
      addTearDown(container.dispose);
      await gym.disconnectMyTrainer();

      container.listen(sentReportNoticesProvider, (_, _) {});
      expect(await container.read(sentReportNoticesProvider.future), isEmpty);
    });
  });
}
