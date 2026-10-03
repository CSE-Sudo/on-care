/// 헬스장 찾기의 위치 기준(#3044).
///
/// 이미 허용된 권한이면 화면을 열 때 권한 창 없이 위치를 얻는다. 얻지 못했으면
/// "신촌 주변 결과" 안내와 [위치 사용] 버튼을 두고, 카드의 거리를 감추고, 거리순을
/// 고를 수 없게 한다. 데모(목업)도 같은 규칙이다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare/features/place/domain/repositories/place_repository.dart';
import 'package:oncare/features/place/presentation/controllers/place_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

class _EmptyPlaceRepository implements PlaceRepository {
  const _EmptyPlaceRepository();

  @override
  Future<List<Place>> nearbyPlaces(PlaceQuery query) async => const <Place>[];
}

/// 권한·위치를 대본대로 돌려주는 위치 서비스.
class _FakeLocationService extends GymLocationService {
  _FakeLocationService({
    this.access = GymLocationAccess.undetermined,
    this.locateFailure,
  });

  GymLocationAccess access;
  GymLocationFailure? locateFailure;
  int checks = 0;
  int locates = 0;
  final List<GymLocationAccess> openedSettings = <GymLocationAccess>[];

  @override
  Future<GymLocationAccess> checkAccess() async {
    checks++;
    return access;
  }

  @override
  Future<PlaceQuery> locate() async {
    locates++;
    final GymLocationFailure? failure = locateFailure;
    if (failure != null) throw failure;
    return const PlaceQuery(
      lat: 35.1,
      lng: 129.1,
      category: PlaceCategory.fitness,
    );
  }

  @override
  Future<bool> openSettingsFor(GymLocationAccess access) async {
    openedSettings.add(access);
    return true;
  }
}

final AppLocalizationsKo _ko = AppLocalizationsKo();

const Key _notice = Key('gym-default-area-notice');
const Key _useLocation = Key('gym-use-location');
const Key _firstDistance = Key('gym-distance-gym-oncare-sinchon');

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeLocationService service, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      placeRepositoryProvider.overrideWithValue(const _EmptyPlaceRepository()),
      gymRepositoryProvider.overrideWithValue(MockGymRepository()),
      gymLocationServiceProvider.overrideWithValue(service),
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'http://localhost',
          useMockApi: true,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GymListPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openSort(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('gym-sort-menu')));
  await tester.pumpAndSettle();
}

Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(OnCareMotion.toastActionVisible);
  await tester.pumpAndSettle();
}

void main() {
  group('이미 허용된 권한', () {
    testWidgets('열자마자 권한 창 없이 위치를 얻고 안내가 없다', (WidgetTester tester) async {
      final _FakeLocationService service = _FakeLocationService(
        access: GymLocationAccess.granted,
      );
      final ProviderContainer c = await _pump(tester, service);

      expect(service.checks, 1);
      expect(service.locates, 1);
      expect(c.read(gymSearchAreaProvider).isUserLocation, isTrue);
      expect(c.read(gymSearchAreaProvider).lat, 35.1);
      expect(find.byKey(_notice), findsNothing);
      // 회원 위치 기준이라 거리를 그린다.
      expect(find.byKey(_firstDistance), findsOneWidget);
      expect(find.text('0.8km'), findsOneWidget);
    });

    testWidgets('조용한 위치 획득이 실패해도 토스트를 띄우지 않는다', (WidgetTester tester) async {
      final _FakeLocationService service = _FakeLocationService(
        access: GymLocationAccess.granted,
        locateFailure: GymLocationFailure.unavailable,
      );
      await _pump(tester, service);

      expect(service.locates, 1);
      expect(find.text(_ko.gymLocationUnavailable), findsNothing);
      expect(find.byKey(_notice), findsOneWidget);
    });
  });

  group('위치를 얻기 전', () {
    testWidgets('묻지 않은 상태면 권한 창을 띄우지 않고 안내를 둔다', (WidgetTester tester) async {
      final _FakeLocationService service = _FakeLocationService();
      final ProviderContainer c = await _pump(tester, service);

      expect(service.checks, 1);
      expect(service.locates, 0, reason: '회원이 누르기 전에는 위치를 청하지 않는다');
      expect(c.read(gymSearchAreaProvider).isUserLocation, isFalse);
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.text(_ko.gymDefaultAreaTitle), findsOneWidget);
      expect(find.text(_ko.gymDefaultAreaMessage), findsOneWidget);
      expect(find.text(_ko.gymUseLocation), findsOneWidget);
    });

    testWidgets('카드에 거리가 없다', (WidgetTester tester) async {
      await _pump(tester, _FakeLocationService());

      expect(find.byKey(_firstDistance), findsNothing);
      expect(find.textContaining('km'), findsNothing);
      // 평점은 그대로다 — 회원 위치와 무관한 값이다.
      expect(find.text('4.7'), findsWidgets);
    });

    testWidgets('거리순을 고르면 정렬하지 않고 위치 사용을 권한다', (WidgetTester tester) async {
      await _pump(tester, _FakeLocationService());

      await _openSort(tester);
      await tester.tap(find.byKey(const ValueKey<String>('gym-sort-distance')));
      await tester.pumpAndSettle();

      expect(find.text(_ko.gymDistanceSortNeedsLocation), findsOneWidget);
      // 정렬 버튼은 여전히 추천순이다.
      final AppButton sort = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('gym-sort-menu')),
      );
      expect(sort.label, _ko.exSortRecommended);
      await _drainToast(tester);
    });

    testWidgets('[위치 사용] 을 누르면 위치를 청하고, 얻으면 안내가 사라진다', (
      WidgetTester tester,
    ) async {
      final _FakeLocationService service = _FakeLocationService();
      final ProviderContainer c = await _pump(tester, service);

      await tester.tap(find.byKey(_useLocation));
      await tester.pumpAndSettle();

      expect(service.locates, 1);
      expect(c.read(gymSearchAreaProvider).isUserLocation, isTrue);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_firstDistance), findsOneWidget);
    });

    testWidgets('위치를 얻은 뒤에는 거리순이 동작한다', (WidgetTester tester) async {
      final _FakeLocationService service = _FakeLocationService();
      await _pump(tester, service);
      await tester.tap(find.byKey(_useLocation));
      await tester.pumpAndSettle();

      await _openSort(tester);
      await tester.tap(find.byKey(const ValueKey<String>('gym-sort-distance')));
      await tester.pumpAndSettle();

      final AppButton sort = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('gym-sort-menu')),
      );
      expect(sort.label, _ko.exSortDistance);
      expect(find.text(_ko.gymDistanceSortNeedsLocation), findsNothing);
    });

    testWidgets('거부하면 토스트로 알리고 안내는 남는다', (WidgetTester tester) async {
      final _FakeLocationService service = _FakeLocationService(
        locateFailure: GymLocationFailure.denied,
      );
      await _pump(tester, service);

      await tester.tap(find.byKey(_useLocation));
      await tester.pump();
      await tester.pump();

      expect(find.text(_ko.gymLocationDenied), findsOneWidget);
      await _drainToast(tester);
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.byKey(_firstDistance), findsNothing);
    });
  });

  group('설정에서 풀어야 하는 상태', () {
    testWidgets('영구 거부면 버튼이 앱 설정을 연다', (WidgetTester tester) async {
      final _FakeLocationService service = _FakeLocationService(
        access: GymLocationAccess.blocked,
      );
      await _pump(tester, service);

      expect(find.text(_ko.gymLocationSettings), findsOneWidget);
      await tester.tap(find.byKey(_useLocation));
      await tester.pumpAndSettle();

      expect(service.openedSettings, <GymLocationAccess>[
        GymLocationAccess.blocked,
      ]);
      expect(service.locates, 0);
    });

    testWidgets('위치 서비스가 꺼져 있으면 위치 설정을 연다', (WidgetTester tester) async {
      final _FakeLocationService service = _FakeLocationService(
        access: GymLocationAccess.disabled,
      );
      await _pump(tester, service);

      await tester.tap(find.byKey(_useLocation));
      await tester.pumpAndSettle();

      expect(service.openedSettings, <GymLocationAccess>[
        GymLocationAccess.disabled,
      ]);
    });

    testWidgets('설정에서 허용하고 돌아오면 다시 보고 위치를 얻는다', (WidgetTester tester) async {
      final _FakeLocationService service = _FakeLocationService(
        access: GymLocationAccess.blocked,
      );
      final ProviderContainer c = await _pump(tester, service);
      expect(service.locates, 0);

      service.access = GymLocationAccess.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(service.locates, 1);
      expect(c.read(gymSearchAreaProvider).isUserLocation, isTrue);
      expect(find.byKey(_notice), findsNothing);
    });
  });

  testWidgets('이미 회원 위치가 있으면 다시 묻지 않는다', (WidgetTester tester) async {
    final _FakeLocationService service = _FakeLocationService(
      access: GymLocationAccess.granted,
    );
    final ProviderContainer c = await _pump(tester, service);
    expect(service.checks, 1);

    // 다른 탭에 갔다 돌아온 것처럼 화면을 다시 세운다.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GymListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.checks, 1);
    expect(service.locates, 1);
    expect(find.byKey(_notice), findsNothing);
  });

  testWidgets('영어로도 안내가 보인다', (WidgetTester tester) async {
    final AppLocalizationsEn en = AppLocalizationsEn();
    await _pump(tester, _FakeLocationService(), locale: const Locale('en'));

    expect(find.text(en.gymDefaultAreaTitle), findsOneWidget);
    expect(find.text(en.gymDefaultAreaMessage), findsOneWidget);
    expect(find.text(en.gymUseLocation), findsOneWidget);
  });

  testWidgets('위치를 얻는 중에는 [위치 사용] 을 다시 누를 수 없다', (WidgetTester tester) async {
    final Completer<PlaceQuery> pending = Completer<PlaceQuery>();
    final _SlowLocationService service = _SlowLocationService(pending.future);
    await _pump(tester, service);

    await tester.tap(find.byKey(_useLocation));
    await tester.pump();
    final AppButton button = tester.widget<AppButton>(find.byKey(_useLocation));
    expect(button.onPressed, isNull);

    pending.complete(
      const PlaceQuery(lat: 35.1, lng: 129.1, category: PlaceCategory.fitness),
    );
    await tester.pumpAndSettle();
    expect(service.locates, 1);
    expect(find.byKey(_notice), findsNothing);
  });

  test('기본 영역 상수는 신촌이다', () {
    expect(kGymDefaultAreaLat, closeTo(37.5559, 1e-9));
    expect(kGymDefaultAreaLng, closeTo(126.9368, 1e-9));
  });
}

class _SlowLocationService extends _FakeLocationService {
  _SlowLocationService(this._result);

  final Future<PlaceQuery> _result;

  @override
  Future<PlaceQuery> locate() {
    locates++;
    return _result;
  }
}
