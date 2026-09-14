import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const Gym _gym = Gym(
  id: 'gym-mine',
  name: '내 헬스장',
  address: '서울시 서대문구 신촌로 1',
  distanceKm: 0.4,
  rating: 4.6,
  tags: <String>['PT'],
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  testWidgets('담당 트레이너가 없으면 그 헬스장의 소속 트레이너로 보낸다 (#793)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.myHealth);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // 라우터를 세우면 MainShell 도 함께 그려진다. 그 안의 Oni 배지가
          // appConfigProvider 를 읽으므로 여기서 넘겨야 한다 — 없으면
          // 'must be overridden in ProviderScope' 로 화면이 아예 뜨지 않는다(#805).
          appConfigProvider.overrideWithValue(_config),
          // 헬스장은 연결돼 있고 담당 트레이너만 없는 상태 — 이 버튼이 뜨는 조건.
          myGymProvider.overrideWith((ref) async => _gym),
          myTrainerProvider.overrideWith((ref) async => null),
          gymTrainersProvider(
            _gym.id,
          ).overrideWith((ref) async => const <Trainer>[]),
          myHealthRepositoryProvider.overrideWithValue(
            const MockMyHealthRepository(),
          ),
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

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    final Finder findTrainer = find.text(l.exFindTrainer);
    await tester.scrollUntilVisible(
      findTrainer,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(findTrainer);
    await tester.pumpAndSettle();

    // 예전에는 라벨이 '트레이너 찾기'인데 헬스장을 찾는 운동 탭으로 갔다.
    //
    // `currentConfiguration.uri` 가 아니라 마지막 match 를 본다 — 셸 브랜치 위에
    // push 하면 uri 는 브랜치 위치(`/my-health`)로 남고, 실제로 올라간 화면은
    // match 목록의 끝에 있다.
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      AppRoutes.gymDetailPath(_gym.id),
    );
  });
}
