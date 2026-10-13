// 헬스장 목록은 서버가 반경·개수로 잘라 준다. 목록에 없는 헬스장으로 들어온
// 상세·상담 신청은 그 헬스장 하나를 따로 읽어 연다. (#3356)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const Gym _listedGym = Gym(
  id: 'gym-listed',
  name: '목록 안 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.7,
  rating: 4.8,
  tags: <String>[],
);

/// 반경 밖이라 목록에는 없는 헬스장.
const Gym _farGym = Gym(
  id: 'gym-far',
  name: '목록 밖 헬스장',
  address: '부산시 테스트구',
  distanceKm: 325,
  rating: 0,
  tags: <String>[],
);

const Trainer _farTrainer = Trainer(
  id: 'trainer-far',
  gymId: 'gym-far',
  name: '박먼곳',
  role: '전담 트레이너',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  /// 단건 조회가 불린 헬스장 id.
  late List<String> singleCalls;

  setUp(() => singleCalls = <String>[]);

  Future<GoRouter> pumpRoute(
    WidgetTester tester, {
    required String location,
    Gym? myGym,
    Future<Gym?> Function(String gymId)? single,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(location);

    Future<Gym?> read(String gymId) {
      singleCalls.add(gymId);
      if (single != null) return single(gymId);
      return Future<Gym?>.value(gymId == _farGym.id ? _farGym : null);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          nearbyGymsProvider.overrideWith((ref) async => <Gym>[_listedGym]),
          gymFinderResultsProvider.overrideWith(
            (ref) async => <Gym>[_listedGym],
          ),
          myGymProvider.overrideWith((ref) async => myGym),
          myTrainerProvider.overrideWith((ref) async => null),
          for (final String id in <String>[
            _listedGym.id,
            _farGym.id,
            'gym-unknown',
          ])
            gymProvider(id).overrideWith((ref) => read(id)),
          for (final Gym gym in <Gym>[_listedGym, _farGym])
            gymTrainersProvider(gym.id).overrideWith(
              (ref) async => <Trainer>[if (gym.id == _farGym.id) _farTrainer],
            ),
          trainerProvider(
            _farTrainer.id,
          ).overrideWith((ref) async => _farTrainer),
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
    return router;
  }

  group('헬스장 상세', () {
    testWidgets('목록에 없는 헬스장은 단건 조회로 열린다', (WidgetTester tester) async {
      await pumpRoute(tester, location: AppRoutes.gymDetailPath(_farGym.id));

      expect(find.text(_farGym.name), findsWidgets);
      expect(find.text('헬스장 정보를 찾을 수 없어요.'), findsNothing);
      expect(singleCalls, <String>[_farGym.id]);
    });

    testWidgets('목록에 있는 헬스장은 단건 조회를 부르지 않는다', (WidgetTester tester) async {
      await pumpRoute(tester, location: AppRoutes.gymDetailPath(_listedGym.id));

      expect(find.text(_listedGym.name), findsWidgets);
      expect(singleCalls, isEmpty);
    });

    testWidgets('내 헬스장은 목록 밖이어도 단건 조회 없이 열린다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.gymDetailPath(_farGym.id),
        myGym: _farGym,
      );

      expect(find.text(_farGym.name), findsWidgets);
      expect(singleCalls, isEmpty);
    });

    testWidgets('단건 조회도 없다고 하면 찾을 수 없음을 보인다', (WidgetTester tester) async {
      await pumpRoute(tester, location: AppRoutes.gymDetailPath('gym-unknown'));

      expect(find.text('헬스장 정보를 찾을 수 없어요.'), findsOneWidget);
      expect(singleCalls, <String>['gym-unknown']);
    });

    testWidgets('단건 조회가 실패하면 오류 상태를 보인다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.gymDetailPath(_farGym.id),
        single: (String gymId) => Future<Gym?>.error(StateError('boom')),
      );

      expect(find.text(_farGym.name), findsNothing);
      expect(find.text('헬스장 정보를 찾을 수 없어요.'), findsNothing);
      expect(find.text('헬스장을 불러오지 못했어요.'), findsOneWidget);
    });
  });

  group('트레이너 상세', () {
    testWidgets('소속 헬스장이 목록에 없어도 헬스장 카드가 뜬다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_farTrainer.id),
      );

      expect(find.text('트레이너 상세'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(_farGym.name),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(_farGym.name), findsOneWidget);
      expect(singleCalls, <String>[_farGym.id]);
    });

    testWidgets('소속 헬스장 조회가 실패해도 트레이너 정보는 그대로 보인다', (
      WidgetTester tester,
    ) async {
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_farTrainer.id),
        single: (String gymId) => Future<Gym?>.error(StateError('boom')),
      );

      expect(find.textContaining(_farTrainer.name), findsWidgets);
      expect(find.text('트레이너 정보를 찾을 수 없어요.'), findsNothing);
      expect(find.text(_farGym.name), findsNothing);
    });
  });

  group('상담 신청', () {
    testWidgets('목록 밖 헬스장의 트레이너에게도 신청 화면이 열린다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.consultationRequestPath(
          gymId: _farGym.id,
          trainerId: _farTrainer.id,
        ),
      );

      expect(find.text('상담 대상 정보를 찾을 수 없어요.'), findsNothing);
      expect(find.textContaining(_farGym.name), findsWidgets);
      expect(singleCalls, <String>[_farGym.id]);
    });
  });

  group('목업 저장소', () {
    test('단건 조회는 목록과 같은 헬스장을 돌려준다', () async {
      final MockGymRepository repo = MockGymRepository();
      final List<Gym> gyms = await repo.fetchNearby();

      for (final Gym gym in gyms) {
        expect((await repo.fetchGym(gym.id))?.name, gym.name);
      }
      expect(await repo.fetchGym('gym-unknown'), isNull);
    });
  });
}
