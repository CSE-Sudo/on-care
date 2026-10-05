/// 연결 삭제가 상세 화면으로 옮겨 간 뒤의 흐름 (#1057).
///
/// MY 탭 카드에서 가장 누르기 쉬운 자리가 되돌릴 수 없는 삭제였다. 그 자리는
/// 상세로 가는 길이 되고, 삭제는 상세 하단으로 내려왔다. 옮기면서 사라지면
/// 연결을 끊을 방법이 화면에서 없어지므로 여기서 지킨다.
library;

import 'package:dio/dio.dart';
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
import 'package:oncare/features/exercise/presentation/widgets/connection_disconnect.dart';
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

/// 해제 요청이 [error] 로 실패하는 대역. 조회는 데모 그대로다. (#2857)
class _FailingDisconnectRepository extends MockGymRepository {
  _FailingDisconnectRepository(this.error);

  final Object error;
  int disconnectCalls = 0;

  @override
  Future<void> disconnectMyGym() async {
    disconnectCalls++;
    throw error;
  }

  @override
  Future<void> disconnectMyTrainer() async {
    disconnectCalls++;
    throw error;
  }
}

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/me/coach'),
  response: Response<void>(
    requestOptions: RequestOptions(path: '/me/coach'),
    statusCode: code,
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  Future<MockGymRepository> pumpDetail(
    WidgetTester tester, {
    required String location,
    Gym? myGym = _myGym,
    Trainer? myTrainer = _myTrainer,
    MockGymRepository? repo,
    bool myTrainerFails = false,
    bool myGymFails = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final MockGymRepository repository = repo ?? MockGymRepository();
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
          myGymProvider.overrideWith(
            (ref) async => myGymFails ? throw StateError('offline') : myGym,
          ),
          myTrainerProvider.overrideWith(
            (ref) async =>
                myTrainerFails ? throw StateError('offline') : myTrainer,
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
    expect(find.textContaining('김트레이너 트레이너와의 연결도 함께 해제돼요'), findsOneWidget);
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

    await tester.tap(find.text('해제'));
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
    await tester.tap(find.text('해제'));
    // 다이얼로그 닫힘 → 대역의 지연 → 화면 되돌아가기까지 몇 프레임 걸린다.
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(await tester.runAsync(repository.fetchMyTrainer), isNull);
    // 헬스장은 그대로다.
    expect(await tester.runAsync(repository.fetchMyGym), isNotNull);
  });

  group('실패 처리 (#2857)', () {
    const String failedToast = '연결을 해제하지 못했어요. 다시 시도해 주세요.';

    Future<void> confirmDelete(WidgetTester tester) async {
      await tester.tap(find.text('해제'));
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    /// 실패 안내는 잠시 뒤 스스로 닫힌다 — 그 타이머가 남지 않게 흘려 보낸다.
    Future<void> drainToast(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('해제 요청이 실패하면 안내가 뜨고 상세가 그대로 남는다', (WidgetTester tester) async {
      final _FailingDisconnectRepository repository =
          _FailingDisconnectRepository(StateError('offline'));
      await pumpDetail(
        tester,
        location: AppRoutes.gymDetailPath(_myGym.id),
        repo: repository,
      );
      await tapDisconnect(tester);
      await confirmDelete(tester);

      expect(repository.disconnectCalls, 1);
      expect(find.text(failedToast), findsOneWidget);
      // 화면을 닫지 않는다 — 회원이 다시 시도할 수 있다.
      expect(
        find.byKey(const Key('connection-disconnect-button')),
        findsOneWidget,
      );
      await drainToast(tester);
    });

    testWidgets('트레이너 상세의 해제 실패도 안내하고 화면을 남긴다', (WidgetTester tester) async {
      final _FailingDisconnectRepository repository =
          _FailingDisconnectRepository(_status(500));
      await pumpDetail(
        tester,
        location: AppRoutes.trainerDetailPath(_myTrainer.id),
        repo: repository,
      );
      await tapDisconnect(tester);
      await confirmDelete(tester);

      expect(find.text(failedToast), findsOneWidget);
      expect(
        find.byKey(const Key('connection-disconnect-button')),
        findsOneWidget,
      );
      await drainToast(tester);
    });

    testWidgets('서버가 이미 연결이 없다(404)고 하면 성공처럼 닫는다', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        location: AppRoutes.gymDetailPath(_myGym.id),
        repo: _FailingDisconnectRepository(_status(404)),
      );
      await tapDisconnect(tester);
      await confirmDelete(tester);

      expect(find.text(failedToast), findsNothing);
      expect(find.text('헬스장 상세'), findsNothing);
    });

    testWidgets('담당 트레이너 조회가 실패해도 확인 창은 뜬다', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        location: AppRoutes.gymDetailPath(_myGym.id),
        myTrainerFails: true,
      );
      await tapDisconnect(tester);

      expect(find.byType(AppDialog), findsOneWidget);
      // 누가 함께 해제되는지 모르면 그 안내만 뺀다.
      expect(find.textContaining('연결도 함께 해제돼요'), findsNothing);
    });

    testWidgets('내 헬스장 조회가 실패해도 트레이너 해제 확인 창은 뜬다', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        location: AppRoutes.trainerDetailPath(_myTrainer.id),
        myGymFails: true,
      );
      await tapDisconnect(tester);

      expect(find.byType(AppDialog), findsOneWidget);
    });
  });

  group('규칙 (#2857)', () {
    test('404 만 이미 해제된 것으로 본다', () {
      expect(isAlreadyDisconnected(_status(404)), isTrue);
      expect(isAlreadyDisconnected(_status(500)), isFalse);
      expect(isAlreadyDisconnected(_status(409)), isFalse);
      expect(isAlreadyDisconnected(StateError('offline')), isFalse);
    });

    test('확인 창용 조회는 실패하면 null 이다', () async {
      expect(
        await readConnectionForConfirm(Future<Gym?>.value(_myGym)),
        _myGym,
      );
      expect(
        await readConnectionForConfirm(
          Future<Gym?>.error(StateError('offline')),
        ),
        isNull,
      );
    });
  });
}
