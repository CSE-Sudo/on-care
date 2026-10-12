import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/trainer_sync_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 담당 요청 목록은 데모 설정에서 한 번만 받는다 — 시트가 다시 받게 했는지
/// 주기 폴링과 섞이지 않고 볼 수 있다.
const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const MemberCoach _kim = MemberCoach(
  trainerId: 'trainer-kim',
  name: '김도윤',
  specialty: '',
  career: '',
  intro: '',
  gymName: '온케어짐 신촌점',
  goal: '',
);

const MemberCoach _lee = MemberCoach(
  trainerId: 'trainer-lee',
  name: '이서준',
  specialty: '',
  career: '',
  intro: '',
  gymName: '온케어짐 신촌점',
  goal: '',
);

const CoachInvite _invite = CoachInvite(
  id: 'invite-1',
  trainerId: 'trainer-kim',
  trainerName: '김도윤',
);

class _FakeTrainerSyncRepository implements TrainerSyncRepository {
  _FakeTrainerSyncRepository({this.expiresInSeconds = 300});

  final int expiresInSeconds;
  int issued = 0;
  int revoked = 0;

  @override
  Future<PairingCode> issue() async {
    issued += 1;
    return PairingCode(code: '979030', expiresInSeconds: expiresInSeconds);
  }

  @override
  Future<void> revoke() async {
    revoked += 1;
  }
}

/// 서버의 담당 상태 대역 — 테스트가 [coach]·[invites] 를 바꿔 "트레이너가 코드를
/// 입력함" 을 재현한다.
class _LinkRepository extends MockMemberCoachRepository {
  MemberCoach? coach;
  List<CoachInvite> invites = const <CoachInvite>[];
  bool failCoach = false;
  bool failInvites = false;
  int coachReads = 0;
  int inviteReads = 0;

  @override
  Future<MemberCoach?> fetchCoach() async {
    coachReads += 1;
    if (failCoach) throw StateError('offline');
    return coach;
  }

  @override
  Future<List<CoachInvite>> fetchInvites() async {
    inviteReads += 1;
    if (failInvites) throw StateError('offline');
    return invites;
  }
}

/// 연결 카드가 다시 읽히는지 세는 헬스장 저장소.
class _CountingGymRepository extends MockGymRepository {
  int trainerReads = 0;
  int gymReads = 0;

  @override
  Future<Trainer?> fetchMyTrainer() {
    trainerReads += 1;
    return super.fetchMyTrainer();
  }

  @override
  Future<Gym?> fetchMyGym() {
    gymReads += 1;
    return super.fetchMyGym();
  }
}

const ValueKey<String> _agreeKey = ValueKey<String>('trainer-sync-agree');
const ValueKey<String> _connectedKey = ValueKey<String>(
  'trainer-sync-connected',
);
const ValueKey<String> _doneKey = ValueKey<String>('trainer-sync-done');

// 연결 코드 시트는 떠 있는 동안 연결됐는지 스스로 확인한다. (#3342)
//
// 트레이너가 웹에 코드를 넣는 순간 서버에서는 연결이 끝난다. 예전 시트는 코드를
// 한 번 받아 남은 시간만 세서, 회원은 닫고 알림을 보기 전까지 연결됐는지 알 수
// 없었다.
void main() {
  late _FakeTrainerSyncRepository sync;
  late _LinkRepository link;
  late _CountingGymRepository gym;

  setUp(() {
    sync = _FakeTrainerSyncRepository();
    link = _LinkRepository();
    gym = _CountingGymRepository();
  });

  Future<ProviderContainer> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 앞선 테스트가 앱을 뒤로 보낸 채 끝나도 다음 테스트는 앞에서 시작한다.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          trainerSyncRepositoryProvider.overrideWithValue(sync),
          memberCoachRepositoryProvider.overrideWithValue(link),
          gymRepositoryProvider.overrideWithValue(gym),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TextButton(
                  onPressed: () => showTrainerSyncSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('open')));
  }

  /// 시트를 열고 동의해 코드를 띄운다.
  Future<void> openAndAgree(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_agreeKey));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('sync-digit-0')), findsOneWidget);
  }

  /// 배경을 눌러 닫는다.
  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
  }

  testWidgets('동의하기 전에는 연결 상태를 묻지 않는다', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.pump(trainerSyncPollInterval * 3);

    expect(link.coachReads, 0);
    expect(link.inviteReads, 0);
  });

  testWidgets('트레이너가 코드를 입력하면 시트를 닫지 않아도 연결 완료가 보인다', (tester) async {
    await pumpHost(tester);
    await openAndAgree(tester);
    expect(find.byKey(_connectedKey), findsNothing);

    // 아직 아무도 입력하지 않았다 — 주기가 돌아도 코드 그대로다.
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();
    expect(find.byKey(_connectedKey), findsNothing);

    // 트레이너가 웹에 코드를 넣었다.
    link.coach = _kim;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();

    expect(find.byKey(_connectedKey), findsOneWidget);
    expect(find.text('김도윤 트레이너와 연결됐어요'), findsOneWidget);
    // 코드와 남은 시간은 치운다 — 이미 쓰인 코드다.
    expect(find.byKey(const ValueKey<String>('sync-digit-0')), findsNothing);
    expect(find.textContaining('뒤에 만료돼요'), findsNothing);
  });

  testWidgets('연결 완료의 확인을 누르면 시트가 닫히고, 쓰인 코드는 버리지 않는다', (tester) async {
    await pumpHost(tester);
    await openAndAgree(tester);
    link.coach = _kim;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();

    await tester.tap(find.byKey(_doneKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_connectedKey), findsNothing);
    expect(sync.revoked, 0);
  });

  testWidgets('연결이 확인되면 더 묻지 않는다', (tester) async {
    await pumpHost(tester);
    await openAndAgree(tester);
    link.coach = _kim;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();
    expect(find.byKey(_connectedKey), findsOneWidget);
    final int reads = link.coachReads;

    await tester.pump(trainerSyncPollInterval * 10);

    expect(link.coachReads, reads);
  });

  testWidgets('연결되면 담당·헬스장 연결 카드가 보는 값을 다시 읽는다', (tester) async {
    final ProviderContainer container = await pumpHost(tester);
    // MY·운동 탭·헤더가 보고 있는 것처럼 붙들어 둔다.
    final List<ProviderSubscription<Object?>> watching =
        <ProviderSubscription<Object?>>[
          container.listen(memberCoachProvider, (_, _) {}),
          container.listen(myTrainerProvider, (_, _) {}),
          container.listen(myGymProvider, (_, _) {}),
        ];
    addTearDown(() {
      for (final ProviderSubscription<Object?> s in watching) {
        s.close();
      }
    });
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(memberCoachProvider).valueOrNull, isNull);
    final int trainerReads = gym.trainerReads;
    final int gymReads = gym.gymReads;

    await openAndAgree(tester);
    link.coach = _kim;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(memberCoachProvider).valueOrNull?.name, '김도윤');
    expect(gym.trainerReads, greaterThan(trainerReads));
    expect(gym.gymReads, greaterThan(gymReads));
  });

  testWidgets('시트를 닫으면 추가 요청이 나가지 않는다', (tester) async {
    await pumpHost(tester);
    await openAndAgree(tester);
    await tester.pump(trainerSyncPollInterval);
    expect(link.coachReads, greaterThanOrEqualTo(2));

    await dismiss(tester);
    final int coachReads = link.coachReads;
    final int inviteReads = link.inviteReads;
    // 닫은 뒤 트레이너가 입력해도 사라진 시트는 묻지 않는다.
    link.coach = _kim;
    await tester.pump(trainerSyncPollInterval * 10);

    expect(link.coachReads, coachReads);
    expect(link.inviteReads, inviteReads);
    // 연결을 보지 못하고 닫았으니 코드는 버린다.
    expect(sync.revoked, 1);
  });

  testWidgets('앱이 뒤로 가면 멈추고, 돌아오면 바로 다시 묻는다', (tester) async {
    await pumpHost(tester);
    await openAndAgree(tester);
    await tester.pump(trainerSyncPollInterval);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final int reads = link.coachReads;
    await tester.pump(trainerSyncPollInterval * 10);
    expect(link.coachReads, reads);

    // 앱을 떠난 사이 트레이너가 입력했다.
    link.coach = _kim;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(link.coachReads, reads + 1);
    expect(find.byKey(_connectedKey), findsOneWidget);
  });

  testWidgets('이미 담당이 있던 회원은 시트를 열었다고 연결 완료를 보지 않는다', (tester) async {
    link.coach = _kim;
    await pumpHost(tester);
    await openAndAgree(tester);

    await tester.pump(trainerSyncPollInterval * 3);
    await tester.pump();
    expect(find.byKey(_connectedKey), findsNothing);

    // 다른 트레이너가 코드를 입력해 담당이 바뀌면 그때는 새 연결이다.
    link.coach = _lee;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();
    expect(find.text('이서준 트레이너와 연결됐어요'), findsOneWidget);
  });

  testWidgets('한 번 읽지 못해도 다음 주기에 연결을 확인한다', (tester) async {
    await pumpHost(tester);
    await openAndAgree(tester);

    link.failCoach = true;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();
    expect(find.byKey(_connectedKey), findsNothing);
    expect(find.byKey(const ValueKey<String>('sync-digit-0')), findsOneWidget);

    link
      ..failCoach = false
      ..coach = _kim;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();
    expect(find.byKey(_connectedKey), findsOneWidget);
  });

  testWidgets('요청 목록을 읽지 못해도 담당 확인은 이어진다', (tester) async {
    link.failInvites = true;
    await pumpHost(tester);
    await openAndAgree(tester);

    link.coach = _kim;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();

    expect(find.byKey(_connectedKey), findsOneWidget);
  });

  testWidgets('코드가 만료되면 지금처럼 만료 안내가 보이고, 새 코드를 받을 수 있다', (tester) async {
    sync = _FakeTrainerSyncRepository(expiresInSeconds: 2);
    await pumpHost(tester);
    await openAndAgree(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('코드가 만료됐어요.'), findsOneWidget);
    expect(find.byKey(_connectedKey), findsNothing);

    await tester.tap(find.text('새 코드 받기'));
    await tester.pump();
    await tester.pump();
    expect(sync.issued, 2);
    expect(find.text('코드가 만료됐어요.'), findsNothing);
  });

  testWidgets('코드 대신 담당 요청이 오면 담당 요청 창이 듣는 목록을 바로 다시 받는다', (tester) async {
    final ProviderContainer container = await pumpHost(tester);
    // 회원 셸의 담당 요청 창(`CoachInvitePrompter`)이 듣고 있는 자리다.
    final ProviderSubscription<AsyncValue<List<CoachInvite>>> prompter =
        container.listen(coachInvitesProvider, (_, _) {});
    addTearDown(prompter.close);
    await tester.pump();
    expect(container.read(coachInvitesProvider).valueOrNull, isEmpty);

    await openAndAgree(tester);
    // 트레이너가 코드를 쓰지 않고 담당 요청을 보냈다.
    link.invites = const <CoachInvite>[_invite];
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();
    await tester.pump();

    expect(
      container.read(coachInvitesProvider).valueOrNull?.single.id,
      'invite-1',
    );
    // 동의는 그 창이 받는다 — 시트는 연결 완료로 넘어가지 않는다.
    expect(find.byKey(_connectedKey), findsNothing);

    // 같은 요청으로 목록을 거듭 새로 받지 않는다.
    final int inviteReads = link.inviteReads;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();
    expect(link.inviteReads, inviteReads + 1);

    // 회원이 그 창에서 수락하면 이 시트도 연결 완료로 바뀐다.
    link
      ..invites = const <CoachInvite>[]
      ..coach = _kim;
    await tester.pump(trainerSyncPollInterval);
    await tester.pump();
    expect(find.byKey(_connectedKey), findsOneWidget);
  });

  testWidgets('담당 요청 창이 이미 받은 요청이면 목록을 다시 받지 않는다', (tester) async {
    link.invites = const <CoachInvite>[_invite];
    final ProviderContainer container = await pumpHost(tester);
    final ProviderSubscription<AsyncValue<List<CoachInvite>>> prompter =
        container.listen(coachInvitesProvider, (_, _) {});
    addTearDown(prompter.close);
    await tester.pump();
    expect(container.read(coachInvitesProvider).valueOrNull, hasLength(1));
    int reloads = 0;
    final ProviderSubscription<AsyncValue<List<CoachInvite>>> counter =
        container.listen(coachInvitesProvider, (_, next) {
          if (next.isLoading) reloads += 1;
        });
    addTearDown(counter.close);

    await openAndAgree(tester);
    await tester.pump(trainerSyncPollInterval * 2);
    await tester.pump();

    expect(reloads, 0);
  });

  test('연결 뒤 새로 읽는 목록은 담당 요청 수락과 같다', () {
    final List<ProviderOrFamily> invalidated = <ProviderOrFamily>[];

    refreshAfterCoachLinked(invalidated.add);

    expect(invalidated, <ProviderOrFamily>[
      memberCoachProvider,
      coachRoutinesProvider,
      coachSessionsProvider,
      myTrainerProvider,
      myGymProvider,
    ]);
  });
}
