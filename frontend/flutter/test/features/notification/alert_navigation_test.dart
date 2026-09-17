/// 알림을 눌렀을 때 어디로 가고 무엇을 다시 받는지 — #636.
///
/// 이동만 하면 방금 알림이 알려 준 변화가 화면에 없을 수 있다. 트레이너가 배정한
/// 루틴을 보러 갔는데 앱이 들고 있던 옛 목록이 그대로면 알림이 거짓말을 한 것처럼
/// 보인다 — 그래서 대상 화면이 읽는 값을 함께 무효화한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/presentation/alert_navigation.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

AlertItem _alert({AlertAction? action}) => AlertItem(
  id: 'n1',
  title: '제목',
  body: '본문',
  timeAgo: '방금',
  category: AlertCategory.system,
  action: action,
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const MemberCoach _coach = MemberCoach(
  trainerId: 't1',
  name: '김트레이너',
  specialty: '체형 교정',
  career: '5년',
  intro: '반갑습니다',
  gymName: '신촌점',
  goal: '체중 감량',
);

/// 코치 정보를 **언제** 주는지 통제하려고 둔 가짜다. 화면이 들고 있던 값을 그냥
/// 읽는지, 새로 받아 오는지가 이 PR 의 쟁점이라 호출 횟수도 센다.
class _FakeCoachRepository implements MemberCoachRepository {
  _FakeCoachRepository({this.coach, this.throws = false});

  MemberCoach? coach;
  bool throws;
  int fetchCoachCalls = 0;
  int unreadCalls = 0;

  @override
  Future<MemberCoach?> fetchCoach() async {
    fetchCoachCalls++;
    if (throws) throw Exception('네트워크 실패');
    return coach;
  }

  @override
  Future<int> unreadCount() async {
    unreadCalls++;
    return 0;
  }

  @override
  Stream<List<CoachMessage>> watchChat() =>
      Stream<List<CoachMessage>>.value(const <CoachMessage>[]);

  @override
  Future<List<CoachMessage>> fetchChat() async => const <CoachMessage>[];

  @override
  Future<List<CoachRoutine>> fetchRoutines() async => const <CoachRoutine>[];

  @override
  Future<List<CoachSession>> fetchSessions() async => const <CoachSession>[];

  @override
  Future<List<CoachInvite>> fetchInvites() async => const <CoachInvite>[];

  @override
  Future<void> acceptInvite(
    String inviteId, {
    required bool dataSharingConsent,
  }) async {}

  @override
  Future<void> rejectInvite(String inviteId) async {}

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    required int minutes,
    String intensity = 'moderate',
  }) async => throw UnimplementedError();

  @override
  Future<CoachRoutine> uncompleteRoutine(String routineId) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteRoutine(String routineId) async {}

  @override
  Future<void> markRead() async {}

  @override
  Future<void> sendMessage(String text) async {}
}

void main() {
  group('AlertAction', () {
    test('앱이 아는 target 은 이동할 수 있다', () {
      const AlertAction action = AlertAction(
        label: '대화 보기',
        target: AlertTarget.coachChat,
      );

      expect(action.isNavigable, isTrue);
    });

    test('모르는 target 은 이동하지 않는다', () {
      // 서버가 새 종류를 추가했는데 앱이 모르는 경우. 목록에서 빼거나 엉뚱한 화면으로
      // 보내는 것보다, 읽음 처리만 하고 제자리에 두는 편이 낫다.
      const AlertAction action = AlertAction(
        label: '어딘가로',
        target: AlertTarget.unknown,
      );

      expect(action.isNavigable, isFalse);
    });

    test('action 이 없는 알림도 정상이다', () {
      expect(_alert().action, isNull);
    });
  });

  group('openAlertTarget', () {
    late BuildContext ctx;
    late WidgetRef wref;

    /// 진입 화면(`/home`)이 살아 있는 채로 각 목적지를 확인한다. 목적지 화면은
    /// 이름표만 둔다 — 여기서 볼 것은 "어디로 갔는가" 뿐이다.
    Future<void> pumpApp(WidgetTester tester, _FakeCoachRepository repo) async {
      final GoRouter router = GoRouter(
        initialLocation: '/home',
        routes: <RouteBase>[
          GoRoute(
            path: '/home',
            builder: (_, _) => Consumer(
              builder: (BuildContext c, WidgetRef r, _) {
                ctx = c;
                wref = r;
                // 무효화가 정말 다시 읽는지 보려면 누군가 듣고 있어야 한다.
                r.watch(coachUnreadProvider);
                return const Text('home');
              },
            ),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, _) => const Text('대시보드'),
          ),
          GoRoute(path: AppRoutes.diet, builder: (_, _) => const Text('식단')),
          GoRoute(
            path: AppRoutes.exercise,
            builder: (_, _) => const Text('운동'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(_config),
            memberCoachRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            // 대화 화면이 현지화 문자열을 읽는다 — 없으면 이동은 했는데 화면이
            // 못 그려져, 이동 실패처럼 보인다.
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 알림 화면과 **같은 방식으로** 부른다 — 기다리지 않는다. 대화 화면을 여는
    /// 경로는 `Navigator.push` 를 돌려주는데 그 Future 는 사용자가 창을 닫아야
    /// 끝나므로, 기다리면 이 함수는 영영 돌아오지 않는다.
    Future<void> tap(WidgetTester tester, AlertTarget target) async {
      unawaited(
        openAlertTarget(
          ctx,
          wref,
          _alert(
            action: AlertAction(label: '보기', target: target),
          ),
        ),
      );
      await tester.pump(); // 코치 정보를 새로 받는 구간
      await tester.pump(); // 이동 반영
      await tester.pump(const Duration(milliseconds: 400)); // 화면 전환
    }

    testWidgets('아는 목적지는 그 화면으로 보낸다', (WidgetTester tester) async {
      for (final (AlertTarget target, String label) in <(AlertTarget, String)>[
        (AlertTarget.dashboard, '대시보드'),
        (AlertTarget.diet, '식단'),
        (AlertTarget.exercise, '운동'),
        // 일정은 아직 전용 화면이 없어 대시보드로 보낸다.
      ]) {
        await pumpApp(tester, _FakeCoachRepository());
        await tap(tester, target);

        expect(find.text(label), findsOneWidget, reason: '$target');
      }
    });

    testWidgets('모르는 목적지는 아무 데도 가지 않는다', (WidgetTester tester) async {
      await pumpApp(tester, _FakeCoachRepository());
      await tap(tester, AlertTarget.unknown);

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('action 이 없으면 아무 데도 가지 않는다', (WidgetTester tester) async {
      await pumpApp(tester, _FakeCoachRepository());
      await openAlertTarget(ctx, wref, _alert());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('코치가 늦게 붙어도 대화를 연다', (WidgetTester tester) async {
      // 트레이너가 붙기 전에 받아 둔 `null` 이 남아 있는 상황. 들고 있는 값을 그냥
      // 읽으면 코치가 보낸 알림인데 코치를 모른다고 답하게 된다.
      final _FakeCoachRepository repo = _FakeCoachRepository();
      await pumpApp(tester, repo);
      expect(wref.read(memberCoachProvider).valueOrNull, isNull);

      repo.coach = _coach;
      await tap(tester, AlertTarget.coachChat);

      expect(find.text('김트레이너'), findsWidgets);
    });

    testWidgets('코치를 못 받으면 대화를 열지 않는다', (WidgetTester tester) async {
      final _FakeCoachRepository repo = _FakeCoachRepository(throws: true);
      await pumpApp(tester, repo);
      await tap(tester, AlertTarget.coachChat);

      // 이름 없는 빈 대화창을 여느니 알림 목록에 남는 편이 낫다.
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('대화로 갈 때 읽지 않은 수를 다시 읽는다', (WidgetTester tester) async {
      // 알림이 알려 준 변화가 화면에 없으면 알림이 거짓말을 한 것처럼 보인다.
      final _FakeCoachRepository repo = _FakeCoachRepository(coach: _coach);
      await pumpApp(tester, repo);
      final int before = repo.unreadCalls;

      await tap(tester, AlertTarget.coachChat);

      expect(repo.unreadCalls, greaterThan(before));
    });
  });

  group('AlertTarget', () {
    test('서버가 쓰는 목적지를 모두 안다', () {
      // 서버 `_ACTION_BY_CATEGORY` 가 내려주는 target 집합과 맞춘다. 한쪽만 늘어나면
      // 알림은 오는데 갈 곳이 없어진다.
      expect(
        AlertTarget.values.toSet(),
        containsAll(<AlertTarget>[
          AlertTarget.dashboard,
          AlertTarget.coachChat,
          AlertTarget.exercise,
          AlertTarget.diet,
          AlertTarget.unknown,
        ]),
      );
    });
  });
}
