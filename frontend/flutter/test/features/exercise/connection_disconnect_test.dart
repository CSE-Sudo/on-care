/// 연결 삭제가 상세 화면으로 옮겨 간 뒤의 흐름 (#1057).
///
/// MY 탭 카드에서 가장 누르기 쉬운 자리가 되돌릴 수 없는 삭제였다. 그 자리는
/// 상세로 가는 길이 되고, 삭제는 상세 하단으로 내려왔다. 옮기면서 사라지면
/// 연결을 끊을 방법이 화면에서 없어지므로 여기서 지킨다.
library;

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
import 'package:oncare_ui/oncare_ui.dart';

const Gym _myGym = Gym(
  id: 'gym-mine',
  name: '온케어짐 신촌점',
  address: '서울시 서대문구',
  distanceKm: 0.4,
  rating: 4.9,
  tags: <String>['PT'],
);

const Gym _otherGym = Gym(
  id: 'gym-other',
  name: '다른 헬스장',
  address: '서울시 마포구',
  distanceKm: 2.1,
  rating: 4.1,
  tags: <String>[],
);

const Trainer _myTrainer = Trainer(
  id: 'trainer-mine',
  gymId: 'gym-mine',
  name: '김트레이너',
  role: '퍼스널 트레이너',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  Future<MockGymRepository> pumpDetail(
    WidgetTester tester, {
    required String location,
    Gym? myGym = _myGym,
    Trainer? myTrainer = _myTrainer,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final MockGymRepository repository = MockGymRepository();
    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.gyms);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          gymRepositoryProvider.overrideWithValue(repository),
          gymFinderResultsProvider.overrideWith(
            (ref) async => const <Gym>[_myGym, _otherGym],
          ),
          nearbyGymsProvider.overrideWith(
            (ref) async => const <Gym>[_myGym, _otherGym],
          ),
          myGymProvider.overrideWith((ref) async => myGym),
          myTrainerProvider.overrideWith((ref) async => myTrainer),
          recommendedTrainersProvider.overrideWith(
            (ref) async => const <Trainer>[_myTrainer],
          ),
          gymTrainersProvider(
            _myGym.id,
          ).overrideWith((ref) async => const <Trainer>[_myTrainer]),
          gymTrainersProvider(
            _otherGym.id,
          ).overrideWith((ref) async => const <Trainer>[]),
          trainerProvider(
            _myTrainer.id,
          ).overrideWith((ref) async => _myTrainer),
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
    // 상세는 카카오 지도 위젯 등 늘 도는 애니메이션을 품을 수 있어
    // pumpAndSettle 이 멈추지 않는다 — 정해진 만큼만 흘린다.
    await tester.pump(const Duration(milliseconds: 300));

    // 목록에서 눌러 들어간 것과 같은 상태로 둔다 — 상세만 띄우면 돌아갈 곳이
    // 없어, 삭제 뒤 화면을 벗어나는지 볼 수 없다.
    router.push(location);
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    return repository;
  }

  /// 대역은 실제 지연을 흉내 내는데, 위젯 테스트의 가짜 시계에서는 그 지연이
  /// 스스로 깨어나지 않는다 — 저장소 상태는 `runAsync` 로 읽는다.
  Future<void> tapDisconnect(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('connection-disconnect-button')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('connection-disconnect-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('내 헬스장 상세에만 삭제 버튼이 있다', (WidgetTester tester) async {
    await pumpDetail(tester, location: AppRoutes.gymDetailPath(_myGym.id));
    expect(
      find.byKey(const Key('connection-disconnect-button')),
      findsOneWidget,
    );

    await pumpDetail(tester, location: AppRoutes.gymDetailPath(_otherGym.id));
    // 연결한 적 없는 헬스장에는 끊을 것이 없다.
    expect(find.byKey(const Key('connection-disconnect-button')), findsNothing);
  });

  testWidgets('헬스장 삭제는 트레이너도 함께 해제된다고 알린다', (WidgetTester tester) async {
    await pumpDetail(tester, location: AppRoutes.gymDetailPath(_myGym.id));
    await tapDisconnect(tester);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.textContaining('온케어짐 신촌점'), findsWidgets);
    expect(find.textContaining('김트레이너 연결도 함께 해제됩니다'), findsOneWidget);
  });

  testWidgets('취소하면 연결이 유지된다', (WidgetTester tester) async {
    final MockGymRepository repository = await pumpDetail(
      tester,
      location: AppRoutes.gymDetailPath(_myGym.id),
    );
    await tapDisconnect(tester);

    await tester.tap(find.text('취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppDialog), findsNothing);
    expect(await tester.runAsync(repository.fetchMyGym), isNotNull);
  });

  testWidgets('삭제하면 연결이 끊기고 상세를 벗어난다', (WidgetTester tester) async {
    final MockGymRepository repository = await pumpDetail(
      tester,
      location: AppRoutes.gymDetailPath(_myGym.id),
    );
    await tapDisconnect(tester);

    await tester.tap(find.text('삭제'));
    // 다이얼로그 닫힘 → 대역의 지연 → 화면 되돌아가기까지 몇 프레임 걸린다.
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // 지운 대상의 상세에 그대로 남아 있으면 방금 무엇을 했는지 알 수 없다.
    expect(find.text('헬스장 상세'), findsNothing);
    expect(await tester.runAsync(repository.fetchMyGym), isNull);
  });

  testWidgets('트레이너 상세에서는 담당 연결만 끊는다', (WidgetTester tester) async {
    final MockGymRepository repository = await pumpDetail(
      tester,
      location: AppRoutes.trainerDetailPath(_myTrainer.id),
    );
    await tapDisconnect(tester);

    expect(find.textContaining('김트레이너'), findsWidgets);
    await tester.tap(find.text('삭제'));
    // 다이얼로그 닫힘 → 대역의 지연 → 화면 되돌아가기까지 몇 프레임 걸린다.
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(await tester.runAsync(repository.fetchMyTrainer), isNull);
    // 헬스장은 그대로다.
    expect(await tester.runAsync(repository.fetchMyGym), isNotNull);
  });
}
