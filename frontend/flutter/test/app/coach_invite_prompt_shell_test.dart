/// 받은 담당 요청은 어느 탭에 있든 가운데 창으로 뜬다. (#1801)
///
/// 요청은 원래 운동 탭 맨 아래 카드에서만 보였고, 목록도 운동 탭을 열 때 한 번만
/// 받았다. 다른 탭에 있으면 요청이 온 줄 모르고 지나쳤다. 셸 전체를 세워 탭마다
/// 창이 뜨는지, 운동 탭에는 카드가 남지 않았는지, 알림을 눌렀을 때 창이 뜨는지 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/main_shell.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/dashboard/data/repositories/mock_dashboard_repository.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/presentation/alert_navigation.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../helpers/fake_diet_repository.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const CoachInvite _invite = CoachInvite(
  id: 'tci-1',
  trainerId: 'trainer-1',
  trainerName: '김트레이너',
  gymName: '온케어짐 신촌점',
);

/// 데모 저장소에 받은 요청만 더한 대역. 나머지 코치 자료는 데모 그대로다.
class _InviteRepository extends MockMemberCoachRepository {
  _InviteRepository({List<CoachInvite> invites = const <CoachInvite>[]})
    : invites = List<CoachInvite>.of(invites);

  List<CoachInvite> invites;
  final List<String> rejected = <String>[];
  int fetchInviteCalls = 0;

  /// 답한 뒤에도 서버 목록에서 바로 빠지지 않는 상황을 흉내 낸다.
  bool keepAfterDecision = false;
  bool failFetch = false;

  @override
  Future<List<CoachInvite>> fetchInvites() async {
    fetchInviteCalls++;
    if (failFetch) throw Exception('offline');
    return List<CoachInvite>.of(invites);
  }

  @override
  Future<void> rejectInvite(String inviteId) async {
    rejected.add(inviteId);
    if (keepAfterDecision) return;
    invites = invites.where((CoachInvite i) => i.id != inviteId).toList();
  }
}

void main() {
  late GoRouter router;

  Future<void> pumpShell(
    WidgetTester tester,
    _InviteRepository repository, {
    String location = AppRoutes.dashboard,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(location);

    final FakeDietRepository diet = FakeDietRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          dietRepositoryProvider.overrideWithValue(diet as DietRepository),
          exerciseRepositoryProvider.overrideWithValue(
            MockExerciseRepository() as ExerciseRepository,
          ),
          dashboardRepositoryProvider.overrideWithValue(
            MockDashboardRepository(diet) as DashboardRepository,
          ),
          memberCoachRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  for (final (String path, String tab) in <(String, String)>[
    (AppRoutes.diet, '식단'),
    (AppRoutes.myHealth, 'MY'),
  ]) {
    testWidgets('$tab 탭에 있어도 담당 요청 창이 뜬다', (WidgetTester tester) async {
      await pumpShell(
        tester,
        _InviteRepository(invites: const <CoachInvite>[_invite]),
        location: path,
      );

      expect(location(), contains(path));
      expect(inviteDialog(), findsOneWidget);
      expect(find.text('김트레이너 트레이너'), findsOneWidget);
    });
  }

  testWidgets('운동 탭은 더 이상 담당 요청 카드를 그리지 않는다', (WidgetTester tester) async {
    // 서버 목록에 요청이 남아 있어도(갱신이 늦을 때) 운동 탭에 카드로 다시
    // 나타나지 않는다. 답한 요청이 창으로 다시 뜨지도 않는다.
    final _InviteRepository repository = _InviteRepository(
      invites: const <CoachInvite>[_invite],
    )..keepAfterDecision = true;
    await pumpShell(tester, repository, location: AppRoutes.exercise);
    expect(inviteDialog(), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('coach-invite-reject-tci-1')),
    );
    await tester.pumpAndSettle();

    expect(repository.rejected, <String>['tci-1']);
    expect(repository.fetchInviteCalls, greaterThan(1));
    expect(location(), contains(AppRoutes.exercise));
    expect(find.byType(AppDialog), findsNothing);
    expect(find.text('담당 요청이 왔어요'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('coach-invite-accept-tci-1')),
      findsNothing,
    );
  });

  Future<void> tapInviteAlert(
    WidgetTester tester, {
    String id = 'tci-1',
  }) async {
    final ref = tester
        .state<ConsumerState<MainShell>>(find.byType(MainShell))
        .ref;
    final future = openAlertTarget(
      tester.element(find.byType(MainShell)),
      ref,
      AlertItem(
        id: 'n-invite',
        title: '요청',
        body: '',
        timeAgo: '',
        category: AlertCategory.reminder,
        wireCategory: 'coach_invite',
        inviteId: id,
        action: const AlertAction(label: '요청 확인', target: AlertTarget.exercise),
      ),
    );
    await tester.pumpAndSettle();
    await future;
  }

  testWidgets('셸 없이 알림 화면에 진입해도 선택한 요청을 연다', (tester) async {
    final repository = _InviteRepository();
    await pumpShell(tester, repository, location: AppRoutes.notification);
    repository.invites = <CoachInvite>[
      const CoachInvite(id: 'tci-2', trainerId: 't2', trainerName: '다른코치'),
      _invite,
    ];
    final page = find.byType(NotificationPage);
    final ref = tester.state<ConsumerState>(page).ref;
    final future = openAlertTarget(
      tester.element(page),
      ref,
      const AlertItem(
        id: 'n',
        title: '요청',
        body: '',
        timeAgo: '',
        category: AlertCategory.reminder,
        wireCategory: 'coach_invite',
        inviteId: 'tci-1',
        action: AlertAction(label: '요청 확인', target: AlertTarget.exercise),
      ),
    );
    await tester.pumpAndSettle();
    await future;
    expect(inviteDialog(), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('coach-invite-tci-2')),
      findsNothing,
    );
  });

  testWidgets('여러 요청 중 알림의 ID와 일치하는 창을 하나만 연다', (tester) async {
    final repository = _InviteRepository();
    await pumpShell(tester, repository);
    repository.invites = <CoachInvite>[
      const CoachInvite(id: 'tci-2', trainerId: 't2', trainerName: '다른코치'),
      _invite,
    ];
    await tapInviteAlert(tester);
    expect(inviteDialog(), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('coach-invite-tci-2')),
      findsNothing,
    );
    await tapInviteAlert(tester);
    expect(inviteDialog(), findsOneWidget);
  });

  testWidgets('처리되거나 취소된 요청은 안내 후 운동으로 이동한다', (tester) async {
    await pumpShell(tester, _InviteRepository());
    await tapInviteAlert(tester);
    expect(location(), contains(AppRoutes.exercise));
    expect(find.text('이미 처리되었거나 취소된 요청이에요.'), findsOneWidget);
    expect(inviteDialog(), findsNothing);
  });

  testWidgets('조회 실패는 처리 완료로 간주하지 않고 다시 시도할 수 있다', (tester) async {
    final repository = _InviteRepository();
    await pumpShell(tester, repository);
    repository.failFetch = true;
    await tapInviteAlert(tester);
    expect(location(), contains(AppRoutes.dashboard));
    expect(find.text('이미 처리되었거나 취소된 요청이에요.'), findsNothing);
    repository.failFetch = false;
    repository.invites = <CoachInvite>[_invite];
    await tapInviteAlert(tester);
    expect(inviteDialog(), findsOneWidget);
  });

  testWidgets('운동으로 가는 알림을 누르면 대기 중인 담당 요청 창이 뜬다', (WidgetTester tester) async {
    // 데모처럼 목록을 한 번만 받는 동안 요청이 새로 온 상황. 알림을 누르면 목록을
    // 곧바로 다시 받아 창을 띄운다.
    final _InviteRepository repository = _InviteRepository();
    await pumpShell(tester, repository);
    expect(find.byType(AppDialog), findsNothing);

    repository.invites = <CoachInvite>[_invite];
    final WidgetRef ref = tester
        .state<ConsumerState<MainShell>>(find.byType(MainShell))
        .ref;
    await openAlertTarget(
      tester.element(find.byType(MainShell)),
      ref,
      const AlertItem(
        id: 'n-invite',
        title: '담당 요청이 도착했어요',
        body: '김트레이너 트레이너가 담당 코치가 되기를 요청했어요.',
        timeAgo: '방금',
        category: AlertCategory.system,
        action: AlertAction(label: '트레이너 보기', target: AlertTarget.exercise),
      ),
    );
    await tester.pumpAndSettle();

    expect(location(), contains(AppRoutes.exercise));
    expect(inviteDialog(), findsOneWidget);
  });
}

Finder inviteDialog() =>
    find.byKey(const ValueKey<String>('coach-invite-tci-1'));
