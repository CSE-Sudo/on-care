/// 헬스장 찾기 지도를 띄우지 못했을 때의 자리 표시(#3043).
///
/// 실사용자 경로는 좌표와 무관한 핀·"내 위치" 점을 그리지 않고 "지도를 불러오지
/// 못했어요" 한 줄만 둔다. 데모 세션(목업 빌드·실서버 데모)은 데모 화면을 바꾸지
/// 않으려 예전 그림 지도를 그대로 쓴다.
///
/// 테스트는 `KAKAO_JS_KEY` 없이 돌아 지도는 언제나 폴백으로 떨어진다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare/features/place/domain/repositories/place_repository.dart';
import 'package:oncare/features/place/presentation/controllers/place_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_kakao_map/oncare_kakao_map.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 카카오가 준 주변 헬스장(좌표 있음).
class _PlaceRepository implements PlaceRepository {
  const _PlaceRepository();

  @override
  Future<List<Place>> nearbyPlaces(PlaceQuery query) async {
    return const <Place>[
      Place(
        id: 'kakao-1',
        name: '신촌 스퀘어 피트니스',
        category: PlaceCategory.fitness,
        address: '서울 마포구',
        distanceMeters: 400,
        lat: 37.556,
        lng: 126.937,
      ),
      Place(
        id: 'kakao-2',
        name: '연세로 짐',
        category: PlaceCategory.fitness,
        address: '서울 서대문구',
        distanceMeters: 900,
        lat: 37.559,
        lng: 126.941,
      ),
    ];
  }
}

const Key _unavailable = ValueKey<String>('gym-map-unavailable');

/// 지도 자리 안의 핀(그림 지도의 큰 위치 아이콘).
Finder _pins() => find.descendant(
  of: find.byType(KakaoMapView),
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w is AppIcon && w.icon == AppIcons.location && (w.size ?? 0) > 24,
  ),
);

/// 지도 자리 안의 "내 위치" 점(둥근 점).
Finder _myLocationDot() => find.descendant(
  of: find.byType(KakaoMapView),
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).shape == BoxShape.circle,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required bool demo,
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        placeRepositoryProvider.overrideWithValue(const _PlaceRepository()),
        gymRepositoryProvider.overrideWithValue(MockGymRepository()),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost',
            useMockApi: true,
          ),
        ),
        // 목업 저장소로 그리되, 실사용자 경로인지 데모 세션인지는 여기서 정한다.
        // 판별 자체는 아래 `데모 판별` 묶음이 따로 본다.
        gymMapDemoFallbackProvider.overrideWithValue(demo),
      ],
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
}

void main() {
  final AppLocalizationsKo ko = AppLocalizationsKo();

  group('실사용자 경로', () {
    testWidgets('지도를 못 띄우면 핀 없이 안내 한 줄만 둔다', (WidgetTester tester) async {
      await _pump(tester, demo: false);

      expect(find.byKey(_unavailable), findsOneWidget);
      expect(find.text(ko.exGymMapUnavailable), findsOneWidget);
      expect(_pins(), findsNothing, reason: '좌표와 무관한 핀을 그리면 안 된다');
      expect(_myLocationDot(), findsNothing, reason: '회원 위치가 아닌 점을 그리면 안 된다');
      // 예전 그림 지도의 이름표도 없다 — 자리 표시는 지도처럼 보이지 않는다.
      expect(find.text(ko.exNearbyGymsMapLabel), findsNothing);
    });

    testWidgets('목록은 그대로 고를 수 있다', (WidgetTester tester) async {
      await _pump(tester, demo: false);

      expect(find.text('신촌 스퀘어 피트니스'), findsOneWidget);
      expect(find.byKey(const Key('gym-result-list')), findsOneWidget);
    });

    testWidgets('영어로도 안내가 보인다', (WidgetTester tester) async {
      await _pump(tester, demo: false, locale: const Locale('en'));

      expect(
        find.text(AppLocalizationsEn().exGymMapUnavailable),
        findsOneWidget,
      );
    });

    testWidgets('지도와 같은 자리를 차지한다 (#1362)', (WidgetTester tester) async {
      await _pump(tester, demo: false);

      final Size slot = tester.getSize(find.byKey(const Key('gym-map-slot')));
      final Size placeholder = tester.getSize(find.byKey(_unavailable));
      expect(placeholder.width, slot.width);
      expect(placeholder.height, slot.height);
    });
  });

  group('데모 세션은 예전 그대로', () {
    testWidgets('그림 지도와 핀·내 위치 점을 그대로 그린다', (WidgetTester tester) async {
      await _pump(tester, demo: true);

      expect(find.byKey(_unavailable), findsNothing);
      expect(find.text(ko.exGymMapUnavailable), findsNothing);
      expect(_pins(), findsWidgets);
      expect(_myLocationDot(), findsOneWidget);
      expect(find.text(ko.exNearbyGymsMapLabel), findsOneWidget);
    });
  });

  group('데모 판별', () {
    ProviderContainer container({required bool mock}) {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1'));
      addTearDown(dio.close);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://example.test/v1',
              useMockApi: mock,
            ),
          ),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('목업 빌드는 데모다', () {
      expect(container(mock: true).read(gymMapDemoFallbackProvider), isTrue);
    });

    test('실서버에서 로그인 전·로그인한 회원은 데모가 아니다', () {
      expect(container(mock: false).read(gymMapDemoFallbackProvider), isFalse);
    });

    test('실서버에서 데모로 들어오면 데모다', () {
      final ProviderContainer c = container(mock: false);
      expect(c.read(gymMapDemoFallbackProvider), isFalse);

      c.read(sessionControllerProvider.notifier).enterDemo();

      expect(c.read(gymMapDemoFallbackProvider), isTrue);
    });
  });
}
