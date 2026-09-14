import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const Gym _gymWithTrainer = Gym(
  id: 'gym-test',
  name: '테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.7,
  rating: 4.8,
  tags: <String>['근력운동'],
  weekdayHours: '06:00 - 23:00',
  weekendHours: '08:00 - 20:00',
  phone: '02-0000-0000',
);

const Gym _gymWithoutTrainer = Gym(
  id: 'gym-no-trainer',
  name: '트레이너 없는 헬스장',
  address: '서울시 테스트구',
  distanceKm: 1.2,
  rating: 4.2,
  tags: <String>[],
);

const Trainer _trainer = Trainer(
  id: 'trainer-test',
  gymId: 'gym-test',
  name: '김테스트',
  role: '전담 트레이너',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  Future<GoRouter> pumpRoute(
    WidgetTester tester, {
    required String location,
    List<Gym> gyms = const <Gym>[_gymWithTrainer, _gymWithoutTrainer],
    List<Trainer> trainers = const <Trainer>[_trainer],
    Gym? myGym,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(location);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          nearbyGymsProvider.overrideWith((ref) async => gyms),
          // 헬스장 상세·찾기는 제휴 + 카카오를 합친 provider 를 본다(#329).
          // gymRepositoryProvider 가 mock/실 API 를 이 값으로 고른다(#324).
          appConfigProvider.overrideWithValue(_config),
          gymFinderResultsProvider.overrideWith((ref) async => gyms),
          myGymProvider.overrideWith((ref) async => myGym),
          myTrainerProvider.overrideWith((ref) async => null),
          allTrainersProvider.overrideWith((ref) async => trainers),
          recommendedTrainersProvider.overrideWith((ref) async => trainers),
          for (final Gym gym in gyms)
            gymTrainersProvider(gym.id).overrideWith(
              (ref) async => trainers
                  .where((Trainer t) => t.gymId == gym.id)
                  .toList(growable: false),
            ),
          for (final Trainer trainer in trainers)
            trainerProvider(trainer.id).overrideWith((ref) async => trainer),
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

  testWidgets('gym and trainer list rows open their detail routes', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await pumpRoute(tester, location: AppRoutes.gyms);

    await tester.tap(find.text(_gymWithTrainer.name));
    await tester.pumpAndSettle();
    expect(find.text('헬스장 상세'), findsOneWidget);

    router.go(AppRoutes.trainers);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_trainer.name));
    await tester.pumpAndSettle();
    expect(find.text('트레이너 상세'), findsOneWidget);
  });

  testWidgets('detail pages link between the gym and its trainer', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath(_gymWithTrainer.id),
    );

    await tester.scrollUntilVisible(
      find.text(_trainer.name),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(_trainer.name));
    await tester.pumpAndSettle();
    expect(find.text('트레이너 상세'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(_gymWithTrainer.name),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(_gymWithTrainer.name));
    await tester.pumpAndSettle();
    expect(find.text('헬스장 상세'), findsOneWidget);
  });

  testWidgets('missing gym or trainer data shows a safe empty state', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath('missing'),
      gyms: const <Gym>[_gymWithoutTrainer],
      trainers: const <Trainer>[],
    );
    expect(find.text('헬스장 정보를 찾을 수 없어요.'), findsOneWidget);

    router.go(AppRoutes.trainerDetailPath('missing-trainer'));
    await tester.pumpAndSettle();
    expect(find.text('트레이너 정보를 찾을 수 없어요.'), findsOneWidget);
  });

  testWidgets('assigned trainer detail hides the consultation request action', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      location: AppRoutes.trainerDetailPath(_gymWithTrainer.id),
      myGym: _gymWithTrainer,
    );

    expect(find.text('트레이너 상세'), findsOneWidget);
    expect(find.text('트레이너 상담 요청하기'), findsNothing);
  });

  testWidgets('connected gym detail hides the consultation request action', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath(_gymWithTrainer.id),
      myGym: _gymWithTrainer,
    );

    expect(find.text('헬스장 상세'), findsOneWidget);
    expect(find.text('헬스장 상담 요청하기'), findsNothing);
  });
}
