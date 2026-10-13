// 헬스장 찾기의 검색창은 서버에 이름으로 묻는다. (#3355)
//
// 예전에는 받아 둔 주변 목록만 걸러, 목록 밖의 헬스장은 이름을 정확히 쳐도
// "검색 결과 없음" 이었다. 이제 입력이 멈추면 검색 경로로 묻고, 검색 중·결과
// 없음·오류를 그 요청 기준으로 그린다. 검색어를 지우면 주변 목록으로 돌아온다.
import 'dart:async';

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
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare/features/place/domain/repositories/place_repository.dart';
import 'package:oncare/features/place/presentation/controllers/place_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 주변 목록에 있는 헬스장.
const Gym _nearGym = Gym(
  id: 'gym-near',
  name: '신촌 가까운짐',
  address: '서울 서대문구',
  distanceKm: 0.4,
  rating: 4.6,
  tags: <String>[],
);

/// 주변 목록에는 없고 이름 검색으로만 나오는 등록 헬스장.
const Gym _farGym = Gym(
  id: 'gym-far',
  name: '해운대 먼짐',
  address: '부산 해운대구',
  distanceKm: 325,
  rating: 4.1,
  tags: <String>[],
);

/// 외부 장소 검색에서만 찾은 헬스장 — 서버에 등록돼 있지 않다.
const Gym _externalGym = Gym(
  id: '328969863',
  name: '광안리 바다짐',
  address: '부산 수영구',
  distanceKm: 320,
  rating: 0,
  tags: <String>[],
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

class _EmptyPlaceRepository implements PlaceRepository {
  const _EmptyPlaceRepository();

  @override
  Future<List<Place>> nearbyPlaces(PlaceQuery query) async => const <Place>[];
}

/// 주변 목록은 [_nearGym] 하나, 이름 검색은 테스트가 정한 대로 답하는 저장소.
class _SearchRepository extends MockGymRepository {
  /// 검색어별 결과. 없는 검색어는 빈 목록이다.
  final Map<String, List<Gym>> results = <String, List<Gym>>{};

  /// 받은 검색어 — 요청 순서대로.
  final List<String> queries = <String>[];

  /// `true` 인 동안 검색이 오류로 끝난다.
  bool fail = false;

  /// 주면 검색이 이것이 끝날 때까지 답하지 않는다.
  Completer<void>? gate;

  @override
  Future<List<Gym>> fetchNearby() async => const <Gym>[_nearGym];

  @override
  Future<Gym?> fetchMyGym() async => null;

  @override
  Future<Trainer?> fetchMyTrainer() async => null;

  @override
  Future<List<Trainer>> fetchTrainersByGym(String gymId) async =>
      const <Trainer>[];

  @override
  Future<List<Gym>> searchGyms(String query) async {
    queries.add(query);
    await gate?.future;
    if (fail) throw StateError('search down');
    return results[query] ?? const <Gym>[];
  }
}

List<Override> _overrides(_SearchRepository repo) => <Override>[
  appConfigProvider.overrideWithValue(_config),
  gymRepositoryProvider.overrideWithValue(repo),
  placeRepositoryProvider.overrideWithValue(const _EmptyPlaceRepository()),
];

Future<void> _pumpFinder(
  WidgetTester tester,
  _SearchRepository repo, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(repo),
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

Finder get _field => find.descendant(
  of: find.byType(AppSearchField),
  matching: find.byType(TextField),
);

/// 검색 칸에 글을 넣는다. 입력 지연은 흘려보내지 않는다.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump();
}

/// 글을 넣고 입력 지연과 응답까지 기다린다.
Future<void> _search(WidgetTester tester, String text) async {
  await _type(tester, text);
  await tester.pump(kGymSearchDebounce);
  await tester.pumpAndSettle();
}

Finder _card(Gym gym) => find.byKey(Key('gym-card-${gym.id}'));

const Key _loading = Key('gym-results-loading');

void main() {
  group('입력 지연', () {
    testWidgets('입력이 멈추기 전에는 서버에 묻지 않는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _type(tester, '해운대');
      await tester.pump(kGymSearchDebounce - const Duration(milliseconds: 1));
      expect(repo.queries, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(repo.queries, <String>['해운대']);
    });

    testWidgets('이어서 치면 마지막 검색어로 한 번만 묻는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      for (final String typed in <String>['해', '해운', '해운대']) {
        await _type(tester, typed);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(repo.queries, isEmpty);

      await tester.pump(kGymSearchDebounce);
      await tester.pumpAndSettle();
      expect(repo.queries, <String>['해운대']);
    });

    testWidgets('키보드의 검색 버튼은 기다리지 않고 묻는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _type(tester, '해운대');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(repo.queries, <String>['해운대']);

      // 남아 있던 입력 지연이 같은 검색어로 한 번 더 묻지 않는다.
      await tester.pump(kGymSearchDebounce);
      await tester.pumpAndSettle();
      expect(repo.queries, <String>['해운대']);
    });

    testWidgets('앞뒤 공백만 달라진 검색어는 다시 묻지 않는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym];
      await _pumpFinder(tester, repo);
      await _search(tester, '해운대');

      await _search(tester, '해운대 ');

      expect(repo.queries, <String>['해운대']);
      expect(_card(_farGym), findsOneWidget);
    });

    testWidgets('공백뿐인 입력은 검색이 아니다 — 주변 목록 그대로다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _search(tester, '   ');

      expect(repo.queries, isEmpty);
      expect(_card(_nearGym), findsOneWidget);
      expect(find.text('주변 헬스장'), findsOneWidget);
    });

    testWidgets('상한을 넘는 검색어는 잘라서 보낸다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _search(tester, '가' * (kGymSearchQueryMaxLength + 30));

      expect(repo.queries, <String>['가' * kGymSearchQueryMaxLength]);
    });

    testWidgets('입력 지연 중에 화면을 떠나도 묻지 않고 오류도 없다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _type(tester, '해운대');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(kGymSearchDebounce * 2);

      expect(repo.queries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('검색 결과', () {
    testWidgets('주변 목록에 없는 헬스장도 이름으로 찾는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym];
      await _pumpFinder(tester, repo);
      expect(_card(_farGym), findsNothing);

      await _search(tester, '해운대');

      expect(_card(_farGym), findsOneWidget);
      expect(find.text('해운대 먼짐'), findsOneWidget);
    });

    testWidgets('주변 목록을 거르지 않는다 — 서버가 준 결과만 보인다', (WidgetTester tester) async {
      // 주변 목록의 헬스장 이름에도 "신촌" 이 있지만 서버는 다른 곳을 줬다.
      final _SearchRepository repo = _SearchRepository()
        ..results['신촌'] = const <Gym>[_farGym];
      await _pumpFinder(tester, repo);

      await _search(tester, '신촌');

      expect(_card(_farGym), findsOneWidget);
      expect(_card(_nearGym), findsNothing);
    });

    testWidgets('서버가 준 순서 그대로 늘어선다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['부산'] = const <Gym>[_farGym, _externalGym];
      await _pumpFinder(tester, repo);

      await _search(tester, '부산');

      // 더 먼 곳이 앞이어도 앱이 다시 늘어세우지 않는다.
      expect(
        tester.getTopLeft(_card(_farGym)).dy,
        lessThan(tester.getTopLeft(_card(_externalGym)).dy),
      );
    });

    testWidgets('머리줄이 검색 결과로 바뀌고 건수는 검색 결과 수다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['부산'] = const <Gym>[_externalGym, _farGym];
      await _pumpFinder(tester, repo);
      expect(find.text('주변 헬스장'), findsOneWidget);
      expect(find.text('1개 결과'), findsOneWidget);

      await _search(tester, '부산');

      expect(find.text('검색 결과'), findsOneWidget);
      expect(find.text('주변 헬스장'), findsNothing);
      expect(find.text('2개 결과'), findsOneWidget);
    });

    testWidgets('영문에서도 머리줄이 검색 결과로 바뀐다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['busan'] = const <Gym>[_farGym];
      await _pumpFinder(tester, repo, locale: const Locale('en'));
      expect(find.text('Nearby gyms'), findsOneWidget);

      await _search(tester, 'busan');

      expect(find.text('Search results'), findsOneWidget);
      expect(find.text('Nearby gyms'), findsNothing);
    });
  });

  group('검색 중', () {
    testWidgets('입력하자마자 주변 목록 대신 로딩을 보인다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _type(tester, '해운대');

      expect(find.byKey(_loading), findsOneWidget);
      expect(_card(_nearGym), findsNothing);

      await tester.pump(kGymSearchDebounce);
      await tester.pumpAndSettle();
    });

    testWidgets('응답을 기다리는 동안 로딩이 남는다', (WidgetTester tester) async {
      final Completer<void> gate = Completer<void>();
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym]
        ..gate = gate;
      await _pumpFinder(tester, repo);

      await _type(tester, '해운대');
      await tester.pump(kGymSearchDebounce);
      await tester.pump();

      expect(repo.queries, <String>['해운대']);
      expect(find.byKey(_loading), findsOneWidget);
      expect(_card(_farGym), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_loading), findsNothing);
      expect(_card(_farGym), findsOneWidget);
    });

    testWidgets('검색어를 바꾸면 앞 검색의 결과를 남기지 않는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym]
        ..results['광안리'] = const <Gym>[_externalGym];
      await _pumpFinder(tester, repo);
      await _search(tester, '해운대');
      expect(_card(_farGym), findsOneWidget);

      await _type(tester, '광안리');

      // 아직 묻기 전이다 — 앞 검색어의 결과를 지금 검색어의 결과처럼 두지 않는다.
      expect(_card(_farGym), findsNothing);
      expect(find.byKey(_loading), findsOneWidget);

      await tester.pump(kGymSearchDebounce);
      await tester.pumpAndSettle();
      expect(_card(_externalGym), findsOneWidget);
      expect(repo.queries, <String>['해운대', '광안리']);
    });
  });

  group('결과 없음', () {
    testWidgets('서버가 빈 목록을 주면 빈 문구가 뜬다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _search(tester, '어디에도없는이름');

      expect(find.text('검색 결과가 없어요.'), findsOneWidget);
      expect(find.text('0개 결과'), findsOneWidget);
      expect(repo.queries, <String>['어디에도없는이름']);
    });

    testWidgets('주변 목록에 이름이 맞는 곳이 있어도 서버가 없다고 하면 없다', (
      WidgetTester tester,
    ) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _search(tester, '가까운짐');

      expect(find.text('검색 결과가 없어요.'), findsOneWidget);
      expect(_card(_nearGym), findsNothing);
    });
  });

  group('검색 오류', () {
    testWidgets('검색이 실패하면 검색 오류와 다시 시도를 보인다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()..fail = true;
      await _pumpFinder(tester, repo);

      await _search(tester, '해운대');

      expect(find.text('헬스장을 검색하지 못했어요.'), findsOneWidget);
      expect(find.text('헬스장을 불러오지 못했어요.'), findsNothing);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('검색 결과가 없어요.'), findsNothing);
    });

    testWidgets('다시 시도하면 같은 검색어로 다시 묻는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym]
        ..fail = true;
      await _pumpFinder(tester, repo);
      await _search(tester, '해운대');

      repo.fail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.queries, <String>['해운대', '해운대']);
      expect(_card(_farGym), findsOneWidget);
      expect(find.text('헬스장을 검색하지 못했어요.'), findsNothing);
    });

    testWidgets('검색이 실패해도 검색어를 지우면 주변 목록이 보인다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()..fail = true;
      await _pumpFinder(tester, repo);
      await _search(tester, '해운대');

      await _type(tester, '');
      await tester.pumpAndSettle();

      expect(find.text('헬스장을 검색하지 못했어요.'), findsNothing);
      expect(_card(_nearGym), findsOneWidget);
    });
  });

  group('검색어 지우기', () {
    testWidgets('지우면 기다리지 않고 주변 목록으로 돌아온다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym];
      await _pumpFinder(tester, repo);
      await _search(tester, '해운대');

      await _type(tester, '');

      expect(_card(_nearGym), findsOneWidget);
      expect(_card(_farGym), findsNothing);
      expect(find.text('주변 헬스장'), findsOneWidget);
      expect(find.byKey(_loading), findsNothing);
    });

    testWidgets('지우기 버튼도 주변 목록으로 돌린다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym];
      await _pumpFinder(tester, repo);
      await _search(tester, '해운대');

      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pumpAndSettle();

      expect(_card(_nearGym), findsOneWidget);
      expect(_card(_farGym), findsNothing);
    });

    testWidgets('입력 지연 중에 지우면 그 검색은 보내지 않는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository();
      await _pumpFinder(tester, repo);

      await _type(tester, '해운대');
      await _type(tester, '');
      await tester.pump(kGymSearchDebounce * 2);
      await tester.pumpAndSettle();

      expect(repo.queries, isEmpty);
      expect(_card(_nearGym), findsOneWidget);
    });

    testWidgets('지운 뒤 같은 검색어를 다시 치면 다시 묻는다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym];
      await _pumpFinder(tester, repo);
      await _search(tester, '해운대');
      await _type(tester, '');
      await tester.pumpAndSettle();

      await _search(tester, '해운대');

      expect(repo.queries, <String>['해운대', '해운대']);
      expect(_card(_farGym), findsOneWidget);
    });
  });

  group('검색 결과에서 상세로', () {
    /// 단건 조회가 불린 헬스장 id.
    late List<String> singleCalls;

    setUp(() => singleCalls = <String>[]);

    Future<GoRouter> pumpApp(
      WidgetTester tester,
      _SearchRepository repo, {
      String location = AppRoutes.gyms,
      Object? extra,
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final GoRouter router = buildAppRouter(config: _config);
      addTearDown(router.dispose);
      router.go(location, extra: extra);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ..._overrides(repo),
            for (final Gym gym in <Gym>[_nearGym, _farGym, _externalGym])
              gymProvider(gym.id).overrideWith((ref) async {
                singleCalls.add(gym.id);
                // 외부 검색에서만 찾은 헬스장은 서버에 없다.
                return gym.id == _externalGym.id ? null : gym;
              }),
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

    testWidgets('외부 검색에서만 찾은 헬스장도 상세가 열린다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['광안리'] = const <Gym>[_externalGym];
      await pumpApp(tester, repo);
      await _search(tester, '광안리');

      await tester.tap(_card(_externalGym));
      await tester.pumpAndSettle();

      expect(find.text('헬스장 상세'), findsOneWidget);
      expect(find.text('광안리 바다짐'), findsWidgets);
      expect(find.text('헬스장 정보를 찾을 수 없어요.'), findsNothing);
      // 받아 온 결과로 그린다 — 읽어도 404 인 단건 조회를 부르지 않는다.
      expect(singleCalls, isEmpty);
    });

    testWidgets('목록 밖의 등록 헬스장도 검색 결과로 바로 열린다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym];
      await pumpApp(tester, repo);
      await _search(tester, '해운대');

      await tester.tap(_card(_farGym));
      await tester.pumpAndSettle();

      expect(find.text('해운대 먼짐'), findsWidgets);
      expect(singleCalls, isEmpty);
    });

    testWidgets('상세에서 돌아오면 검색 결과가 그대로다', (WidgetTester tester) async {
      final _SearchRepository repo = _SearchRepository()
        ..results['해운대'] = const <Gym>[_farGym];
      final GoRouter router = await pumpApp(tester, repo);
      await _search(tester, '해운대');
      await tester.tap(_card(_farGym));
      await tester.pumpAndSettle();

      router.pop();
      await tester.pumpAndSettle();

      expect(_card(_farGym), findsOneWidget);
      expect(find.text('검색 결과'), findsOneWidget);
      expect(repo.queries, <String>['해운대']);
    });

    testWidgets('넘겨받은 헬스장이 없으면 id 로 읽는 경로를 탄다', (WidgetTester tester) async {
      // 새로고침·딥링크 — `extra` 가 없다.
      await pumpApp(
        tester,
        _SearchRepository(),
        location: AppRoutes.gymDetailPath(_farGym.id),
      );

      expect(find.text('해운대 먼짐'), findsWidgets);
      expect(singleCalls, <String>[_farGym.id]);
    });

    testWidgets('다른 헬스장을 넘겨받으면 쓰지 않는다', (WidgetTester tester) async {
      await pumpApp(
        tester,
        _SearchRepository(),
        location: AppRoutes.gymDetailPath(_farGym.id),
        extra: _externalGym,
      );

      expect(find.text('광안리 바다짐'), findsNothing);
      expect(find.text('해운대 먼짐'), findsWidgets);
      expect(singleCalls, <String>[_farGym.id]);
    });

    testWidgets('주변 목록에 있는 헬스장은 받아 둔 목록의 값으로 그린다', (WidgetTester tester) async {
      // 넘겨받은 값보다 목록이 먼저다 — 검색 결과에는 없는 정보가 목록에 있을 수 있다.
      const Gym stale = Gym(
        id: 'gym-near',
        name: '옛 이름',
        address: '서울 서대문구',
        distanceKm: 0,
        rating: 0,
        tags: <String>[],
      );
      await pumpApp(
        tester,
        _SearchRepository(),
        location: AppRoutes.gymDetailPath(_nearGym.id),
        extra: stale,
      );

      expect(find.text('신촌 가까운짐'), findsWidgets);
      expect(find.text('옛 이름'), findsNothing);
      expect(singleCalls, isEmpty);
    });
  });
}
