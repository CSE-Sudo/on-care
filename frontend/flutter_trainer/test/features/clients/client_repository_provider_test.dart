import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
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
  bool get supportsRosterMutations => false;
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
  Future<RoutineHistoryEntry> updateHistoryFeedback(
    String clientId,
    String historyId,
    String feedback,
  ) async => throw UnsupportedError('not used');
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
  Future<String> fetchDietAdvice(String clientId, ClientPeriod period) async =>
      '';

  @override
  Future<String> fetchExerciseAdvice(
    String clientId,
    ClientPeriod period,
  ) async => '';

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
  Future<bool> clientNameExists(String name) async => false;
  @override
  Future<bool> addClient({required String name, required String goal}) async =>
      false;
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
        'goals': '체지방 감량',
      });
      final fetchedAgain = await repository.fetchHealthProfile('seed-client-1');

      expect(updated.weightKg, 68.4);
      expect(updated.weeklyWorkoutGoal, 0);
      expect(fetchedAgain.weightKg, 68.4);
      expect(fetchedAgain.weeklyWorkoutGoal, 0);
      expect(fetchedAgain.goals, '체지방 감량');
      expect(fetchedAgain.heightCm, before.heightCm);
    },
  );

  test('an untouched health profile agrees with the roster identity', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedIfEmpty(db);
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
