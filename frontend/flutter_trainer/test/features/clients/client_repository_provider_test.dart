import 'dart:async';
import 'dart:ui' show Locale;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/record_span.dart';

class _MockDio extends Mock implements Dio {}

TrainerClient _client(String id, {required int sodiumMg}) => TrainerClient(
  id: id,
  name: id,
  avatar: id.substring(0, 1),
  goal: '',
  lastMessage: '',
  lastTime: '',
  active: true,
  calories: 0,
  sodiumMg: sodiumMg,
  sugarG: 0,
  lastRoutine: '',
  weekCompletion: const <int>[],
  sodiumWeek: const <int>[],
);

/// A [ClientRepository] whose `watchClients()` is a controllable
/// multi-emission stream, so tests can push more than one roster update
/// through the same provider instance (unlike the real Dio source, which
/// is one-shot) — used to prove [prioritizedClientsProvider] keeps up with
/// every emission, not just the first.
class _StreamingClientRepository implements ClientRepository {
  @override
  Future<void> restoreClient(String id) async {}
  _StreamingClientRepository(this._controller);
  final StreamController<List<TrainerClient>> _controller;

  @override
  Stream<List<TrainerClient>> watchClients() => _controller.stream;
  @override
  Stream<Map<String, DateTime>> watchLastChatAt() =>
      Stream<Map<String, DateTime>>.value(const <String, DateTime>{});
  @override
  Stream<List<ClientDietEntry>> watchDiet(String clientId) =>
      const Stream<List<ClientDietEntry>>.empty();
  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) =>
      const Stream<List<RoutineHistoryEntry>>.empty();
  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) async =>
      MemberHealthProfile(memberId: clientId, memberName: '회원');
  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> values,
  ) => fetchHealthProfile(clientId);
  @override
  Future<List<ClientExercisePeriodWeek>> fetchExercisePeriod(
    String clientId,
    ClientDateRange range,
  ) async => <ClientExercisePeriodWeek>[
    for (final DateTime monday in clientRangeWeekStarts(range))
      (
        weekStart: monday,
        week: await fetchExerciseWeek(clientId, weekStart: monday),
      ),
  ];

  @override
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  }) async => const ClientExerciseWeek(
    dayLabels: <String>[],
    dailyMinutes: <int>[],
    dailyCalories: <int>[],
    totalMinutes: 0,
    totalCalories: 0,
  );

  @override
  Future<ClientDietAnalysis> fetchDietAdvice(
    String clientId,
    ClientPeriod period, {
    required Locale locale,
  }) async => ClientDietAnalysis.empty;

  @override
  Future<ClientDietRecommendations> fetchDietRecommendations(
    String clientId, {
    required Locale locale,
  }) async => const ClientDietRecommendations();

  @override
  Future<ClientDietRecommendations> confirmDietRecommendation(
    String clientId, {
    required String slot,
    required String name,
    required Locale locale,
  }) async => const ClientDietRecommendations();

  @override
  Future<List<ClientDietEntry>> fetchDietOn(
    String clientId,
    DateTime date,
  ) async => const <ClientDietEntry>[];

  @override
  Future<List<ClientExerciseItem>> fetchExercisesOn(
    String clientId,
    DateTime date,
  ) async => <ClientExerciseItem>[];

  @override
  Future<ClientRecordSpan> fetchRecordSpan(String clientId) async =>
      testClientRecordSpan();

  @override
  Future<ClientDietPeriod> fetchDietPeriod(
    String clientId,
    ClientDateRange range,
  ) async => ClientDietPeriod(range: range, days: const <ClientDietDay>[]);
  @override
  Future<void> setClientActive(String id, bool active) async {}

  @override
  Future<void> removeClient(String id) async {}
}

ProviderContainer _containerFor({
  required bool useMockApi,
  List<Override> extraOverrides = const <Override>[],
}) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'http://localhost/v1',
          useMockApi: useMockApi,
        ),
      ),
      appDatabaseProvider.overrideWithValue(db),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 길이가 **서로 같지만 7보다 짧은** 유형 배열을 돌려주는 저장소.
///
/// `ClientExerciseWeek.hasTypeSplit` 은 셋의 길이가 서로 같은지만 본다. 기간
/// provider 의 루프는 언제나 7일을 도므로, 이런 응답을 분해로 인정해 버리면
/// `d == 2` 에서 범위를 넘어 화면이 통째로 죽는다(리뷰 #946).
class _ShortSplitRepository extends _StreamingClientRepository {
  _ShortSplitRepository()
    : super(StreamController<List<TrainerClient>>.broadcast());

  @override
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  }) async => const ClientExerciseWeek(
    dayLabels: <String>['월', '화'],
    dailyMinutes: <int>[30, 20],
    dailyCalories: <int>[180, 120],
    cardioMinutes: <int>[20, 10],
    strengthMinutes: <int>[10, 5],
    stretchingMinutes: <int>[0, 5],
    totalMinutes: 50,
    totalCalories: 300,
  );
}

/// 시드가 넣은 신체·목표를 걷어 낸다(#2597) — 저장한 적 없는 회원을 저장소가
/// 어떻게 읽는지 보려면 시드 값이 없어야 한다.
Future<void> _clearSeededHealthProfiles(AppDatabase db) => (db.delete(
  db.appKeyValues,
)..where((t) => t.key.like('member_health_profile:%'))).go();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves the drift repository when USE_MOCK_API=true', () {
    final container = _containerFor(useMockApi: true);
    expect(
      container.read(clientRepositoryProvider),
      isA<DriftClientRepository>(),
    );
  });

  test('resolves the Dio repository when USE_MOCK_API=false', () {
    final container = _containerFor(useMockApi: false);
    expect(
      container.read(clientRepositoryProvider),
      isA<DioClientRepository>(),
    );
  });

  test(
    'demo health-profile updates persist and preserve omitted fields',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await seedIfEmpty(db);
      final repository = DriftClientRepository(db);

      final before = await repository.fetchHealthProfile('seed-client-1');
      final updated = await repository.updateHealthProfile('seed-client-1', {
        'weight_kg': 68.4,
        'weekly_workout_goal': 0,
      });
      final fetchedAgain = await repository.fetchHealthProfile('seed-client-1');

      expect(updated.weightKg, 68.4);
      expect(updated.weeklyWorkoutGoal, 0);
      expect(fetchedAgain.weightKg, 68.4);
      expect(fetchedAgain.weeklyWorkoutGoal, 0);
      expect(fetchedAgain.heightCm, before.heightCm);
    },
  );

  test('demo keeps the member-app goals a trainer saves (#2331)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedIfEmpty(db);
    await _clearSeededHealthProfiles(db);
    final repository = DriftClientRepository(db);

    // 저장한 적이 없으면 비어 있다 — 화면이 회원 앱 기본값을 흐리게 보여 준다.
    final before = await repository.fetchHealthProfile('seed-client-1');
    expect(before.dailyCalories, isNull);
    expect(before.weeklyFlexibilityMinutes, isNull);

    const Map<String, int> goals = <String, int>{
      'daily_calories': 1800,
      'daily_sodium_mg': 1500,
      'daily_sugar_g': 40,
      'daily_carbs_g': 220,
      'daily_protein_g': 110,
      'daily_fat_g': 50,
      'daily_burn_kcal': 350,
      'weekly_cardio_minutes': 180,
      'weekly_strength_sets': 28,
      'weekly_flexibility_minutes': 70,
    };
    await repository.updateHealthProfile('seed-client-1', goals);
    // 예전에는 여기서 버려져 창을 다시 열면 빈칸이었다.
    final saved = await repository.fetchHealthProfile('seed-client-1');
    expect(<String, int?>{
      'daily_calories': saved.dailyCalories,
      'daily_sodium_mg': saved.dailySodiumMg,
      'daily_sugar_g': saved.dailySugarG,
      'daily_carbs_g': saved.dailyCarbsG,
      'daily_protein_g': saved.dailyProteinG,
      'daily_fat_g': saved.dailyFatG,
      'daily_burn_kcal': saved.dailyBurnKcal,
      'weekly_cardio_minutes': saved.weeklyCardioMinutes,
      'weekly_strength_sets': saved.weeklyStrengthSets,
      'weekly_flexibility_minutes': saved.weeklyFlexibilityMinutes,
    }, goals);

    // 다른 칸만 고친 저장이 목표를 지우지 않는다.
    await repository.updateHealthProfile('seed-client-1', <String, Object?>{
      'weight_kg': 70.0,
    });
    final again = await repository.fetchHealthProfile('seed-client-1');
    expect(again.dailyCalories, 1800);
    // 비우면(null) 지운다 — 서버와 같은 규칙이다.
    await repository.updateHealthProfile('seed-client-1', <String, Object?>{
      'daily_calories': null,
    });
    expect(
      (await repository.fetchHealthProfile('seed-client-1')).dailyCalories,
      isNull,
    );
  });

  test('an untouched health profile agrees with the roster identity', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedIfEmpty(db);
    await _clearSeededHealthProfiles(db);
    final repository = DriftClientRepository(db);
    final clients = await repository.watchClients().first;

    for (final client in clients) {
      final profile = await repository.fetchHealthProfile(client.id);
      // 헤더가 '여성'이라고 말하는 회원의 대화상자가 '남성'으로 열리면 안 된다.
      // 예전에는 모두에게 고정 'male' 을 돌려줬다(#818).
      expect(profile.gender, client.rosterGender, reason: client.name);
      // 재본 적 없는 키·체중은 지어내지 않는다 — 트레이너가 입력한 값과
      // 구분되지 않으면 그대로 저장돼 남의 신체 정보로 굳는다.
      expect(profile.heightCm, isNull, reason: client.name);
      expect(profile.weightKg, isNull, reason: client.name);
    }

    // 저장한 값은 그대로 돌아온다.
    final first = clients.first;
    await repository.updateHealthProfile(first.id, <String, Object?>{
      'gender': 'other',
      'height_cm': 171.0,
    });
    final saved = await repository.fetchHealthProfile(first.id);
    expect(saved.gender, 'other');
    expect(saved.heightCm, 171.0);
  });

  test('watching clientsProvider + prioritizedClientsProvider together issues '
      'exactly one GET /trainer/clients in real-API mode (review: the two '
      'providers used to each fetch independently)', () async {
    final dio = _MockDio();
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/clients',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/trainer/clients'),
        statusCode: 200,
        data: <dynamic>[
          <String, Object?>{'id': 'a', 'name': 'A', 'sodium_mg': 2500},
          <String, Object?>{'id': 'b', 'name': 'B', 'sodium_mg': 500},
        ],
      ),
    );
    final container = _containerFor(
      useMockApi: false,
      extraOverrides: <Override>[dioProvider.overrideWithValue(dio)],
    );

    final clients = await container.read(clientsProvider.future);
    // Derived synchronously from the roster — no second fetch, and no
    // future to await.
    final prioritized = container.read(prioritizedClientsProvider).valueOrNull;

    verify(
      () => dio.get<List<dynamic>>(
        '/trainer/clients',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).called(1);
    expect(clients.map((c) => c.id), <String>['a', 'b']);
    expect(prioritized!.map((c) => c.id), <String>['a', 'b']); // a is over
  });

  test('prioritizedClientsProvider re-derives on every clientsProvider '
      'emission, not just the first (review: watching `.future` would freeze '
      'on the first value since it only ever resolves once)', () async {
    final controller = StreamController<List<TrainerClient>>();
    addTearDown(controller.close);
    final container = _containerFor(
      useMockApi: false,
      extraOverrides: <Override>[
        clientRepositoryProvider.overrideWithValue(
          _StreamingClientRepository(controller),
        ),
      ],
    );

    // Each addition needs a couple of real event-loop ticks to travel
    // clientsProvider's stream -> its AsyncValue -> the rebuilt
    // Stream.value(...) -> prioritizedClientsProvider's own AsyncValue ->
    // this listener. Rather than guess how long that takes (a fixed
    // delay is flaky on a slow CI runner), wait on a Completer that the
    // listener itself completes the moment each emission actually
    // arrives (review).
    final emissions = <List<String>>[];
    final gotFirst = Completer<void>();
    final gotSecond = Completer<void>();
    final sub = container.listen(prioritizedClientsProvider, (_, next) {
      next.whenData((clients) {
        emissions.add(clients.map((c) => c.id).toList());
        if (emissions.length == 1) {
          gotFirst.complete();
        } else if (emissions.length == 2) {
          gotSecond.complete();
        }
      });
    });
    addTearDown(sub.close);

    controller.add(<TrainerClient>[_client('a', sodiumMg: 100)]);
    await gotFirst.future.timeout(const Duration(seconds: 5));
    // A second emission on the SAME provider instance (no invalidation) —
    // an over-target client now leads the roster.
    controller.add(<TrainerClient>[
      _client('over', sodiumMg: 2500),
      _client('a', sodiumMg: 100),
    ]);
    await gotSecond.future.timeout(const Duration(seconds: 5));

    expect(emissions, <List<String>>[
      <String>['a'],
      <String>['over', 'a'], // proves the second emission was reflected
    ]);
  });

  test('실서버 메시지 탭은 로스터가 갱신되면 새 대화를 맨 위로 올린다 (#3011)', () async {
    // 실서버 저장소는 채팅 시각 맵을 비워 둔다(`watchLastChatAt` 빈 맵).
    // 차례는 로스터의 `last_message_at` 이 정한다 — 회원이 새 메시지를 보낸
    // 뒤 로스터가 다시 읽히면 그 회원이 위로 와야 한다.
    final controller = StreamController<List<TrainerClient>>();
    addTearDown(controller.close);
    final container = _containerFor(
      useMockApi: false,
      extraOverrides: <Override>[
        clientRepositoryProvider.overrideWithValue(
          _StreamingClientRepository(controller),
        ),
      ],
    );
    TrainerClient talked(String id, DateTime at) => TrainerClient(
      id: id,
      name: id,
      avatar: id.substring(0, 1),
      goal: '',
      lastMessage: '',
      lastTime: '',
      lastMessageAt: at,
      active: true,
      calories: 0,
      sodiumMg: 0,
      sugarG: 0,
      lastRoutine: '',
      weekCompletion: const <int>[],
      sodiumWeek: const <int>[],
    );
    final DateTime nine = DateTime.utc(2026, 10, 3);
    final DateTime ten = DateTime.utc(2026, 10, 3, 1);
    final DateTime eleven = DateTime.utc(2026, 10, 3, 2);

    final emissions = <List<String>>[];
    final gotFirst = Completer<void>();
    final gotSecond = Completer<void>();
    final sub = container.listen(recentlyMessagedClientsProvider, (_, next) {
      next.whenData((clients) {
        emissions.add(clients.map((c) => c.id).toList());
        if (emissions.length == 1) {
          gotFirst.complete();
        } else if (emissions.length == 2) {
          gotSecond.complete();
        }
      });
    });
    addTearDown(sub.close);

    // 서버 차례(a, b)와 달리 b 가 더 최근에 말했다.
    controller.add(<TrainerClient>[talked('a', nine), talked('b', ten)]);
    await gotFirst.future.timeout(const Duration(seconds: 5));
    // a 가 새 메시지를 보냈다 — 다음 로스터에서 a 의 시각이 가장 새롭다.
    controller.add(<TrainerClient>[talked('a', eleven), talked('b', ten)]);
    await gotSecond.future.timeout(const Duration(seconds: 5));

    expect(emissions, <List<String>>[
      <String>['b', 'a'],
      <String>['a', 'b'],
    ]);
  });

  test('길이가 짧은 유형 배열이 와도 기간 집계가 죽지 않는다 (리뷰 #946)', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        clientRepositoryProvider.overrideWithValue(_ShortSplitRepository()),
      ],
    );
    addTearDown(container.dispose);

    final ClientExercisePeriod period = await container.read(
      clientExercisePeriodProvider((
        clientId: 'c1',
        period: ClientPeriod.week,
        day: DateTime(2026, 8, 19),
      )).future,
    );

    // 실려 온 두 칸만 값이 있고, 나머지는 0 이다 — 지어내지 않는다.
    expect(period.days, hasLength(7));
    expect(period.days[0].cardioMinutes, 20);
    expect(period.days[1].strengthMinutes, 5);
    expect(period.days[2].minutes, 0);
    expect(period.days[2].cardioMinutes, 0);
    expect(period.totalMinutes, 50);
  });
}
