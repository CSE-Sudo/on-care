/// 헬스장 찾기 검색 칸 — 띄어쓰기·단어 순서를 보지 않는다. (#3223)
///
/// 예전에는 검색어 전체를 이름·주소·태그에 `contains` 한 번으로 비교해,
/// `헬스메이트신촌`·`신촌 헬스메이트` 가 목록에 있는 `헬스메이트 신촌점` 을 걸러
/// 냈다. 트레이너 웹·서버와 같은 규칙(`oncare_core/search_match.dart`)을 쓴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare/features/place/domain/repositories/place_repository.dart';
import 'package:oncare/features/place/presentation/controllers/place_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const Gym _healthmate = Gym(
  id: 'gym-healthmate',
  name: '헬스메이트 신촌점',
  address: '서울 서대문구 신촌로 83',
  distanceKm: 1.2,
  rating: 4.5,
  tags: <String>['근력운동', '만성질환 관리'],
);

class _EmptyPlaceRepository implements PlaceRepository {
  const _EmptyPlaceRepository();

  @override
  Future<List<Place>> nearbyPlaces(PlaceQuery query) async => const <Place>[];
}

Future<void> _pumpFinder(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        placeRepositoryProvider.overrideWithValue(
          const _EmptyPlaceRepository(),
        ),
        gymRepositoryProvider.overrideWithValue(MockGymRepository()),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost',
            useMockApi: true,
          ),
        ),
      ],
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
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(AppSearchField),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
}

Finder _inResults(String text) => find.descendant(
  of: find.byKey(const Key('gym-result-list')),
  matching: find.text(text),
);

void main() {
  group('Gym.matchesQuery', () {
    test('저장된 이름을 그대로 치면 맞는다', () {
      expect(_healthmate.matchesQuery('헬스메이트 신촌점'), isTrue);
    });

    test('붙여 쓴 검색어도 맞는다', () {
      expect(_healthmate.matchesQuery('헬스메이트신촌'), isTrue);
    });

    test('단어 순서가 달라도 맞는다', () {
      expect(_healthmate.matchesQuery('신촌 헬스메이트'), isTrue);
    });

    test('주소·태그 단어와 섞어도 맞는다', () {
      expect(_healthmate.matchesQuery('신촌로 근력운동'), isTrue);
      expect(_healthmate.matchesQuery('만성질환관리'), isTrue);
    });

    test('단어 하나라도 없으면 맞지 않는다', () {
      expect(_healthmate.matchesQuery('헬스메이트 강남'), isFalse);
    });

    test('빈 검색어는 모두 맞는다', () {
      expect(_healthmate.matchesQuery(''), isTrue);
      expect(_healthmate.matchesQuery('   '), isTrue);
    });
  });

  group('헬스장 찾기 화면', () {
    testWidgets('붙여 쓴 이름으로 찾아도 그 헬스장이 남는다', (tester) async {
      await _pumpFinder(tester);
      await _search(tester, '헬스메이트신촌');

      expect(_inResults('헬스메이트 신촌점'), findsOneWidget);
      expect(_inResults('바디앤소울 피트니스'), findsNothing);
    });

    testWidgets('단어 순서를 바꿔 찾아도 그 헬스장이 남는다', (tester) async {
      await _pumpFinder(tester);
      await _search(tester, '피트니스 바디앤소울');

      expect(_inResults('바디앤소울 피트니스'), findsOneWidget);
      expect(_inResults('헬스메이트 신촌점'), findsNothing);
    });
  });
}
