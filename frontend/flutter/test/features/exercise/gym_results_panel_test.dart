/// 헬스장 찾기 화면의 지도와 결과 목록. (#865 → #1135 → #1274 → #1362 → #1370)
///
/// 지도는 위에 **가로로 길게 고정**되고, 자리는 둘뿐이다 — 반반 / 목록만.
/// 오가는 길은 머리줄의 화살표 하나이고, 목록은 제 자리 안에서 구른다. 목록을
/// 굴려도 지도는 움직이지 않는다 — 예전에 지도까지 함께 밀려 올라가던 것이 이
/// 화면에서 가장 다루기 나빴던 부분이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/kakao_map/kakao_map_view.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare/features/place/domain/repositories/place_repository.dart';
import 'package:oncare/features/place/presentation/controllers/place_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 카카오가 아무 결과도 주지 않아도 제휴 목록만으로 화면이 선다(#329).
class _EmptyPlaceRepository implements PlaceRepository {
  const _EmptyPlaceRepository();

  @override
  Future<List<Place>> nearbyPlaces(PlaceQuery query) async => const <Place>[];
}

Future<void> _pumpFinder(WidgetTester tester, {Size? size}) async {
  await tester.binding.setSurfaceSize(size ?? const Size(390, 844));
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

/// 지도의 윗변. 목록을 밀어도 이 값은 그대로여야 한다.
double _mapTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(KakaoMapView).first).dy;

void main() {
  testWidgets('지도와 결과가 함께 보인다', (tester) async {
    await _pumpFinder(tester);

    expect(find.byType(KakaoMapView), findsOneWidget);
    // 결과 개수와 정렬 줄, 그리고 카드가 함께 읽힌다.
    expect(find.textContaining('개'), findsWidgets);
    expect(find.text('주변 헬스장'), findsOneWidget);
    // 처음 자리는 반반이다 — 지도와 목록이 함께 읽힌다 (#1274, #1370).
    expect(
      tester.getSize(find.byKey(const Key('gym-map-slot'))).height,
      greaterThan(0),
    );
  });

  testWidgets('목록은 제 자리에서 구르고 지도는 그대로다 (#1135, #1370)', (tester) async {
    await _pumpFinder(tester);
    final double before = _mapTop(tester);
    final Finder list = find.byKey(const Key('gym-result-list'));
    final double listTop = tester.getTopLeft(list).dy;

    // 목록을 민다. 카드가 넘어가야 하고(스크롤 위치가 움직인다), 지도와 목록
    // 자리는 그대로여야 한다.
    await tester.drag(list, const Offset(0, -200));
    await tester.pumpAndSettle();

    final ScrollPosition position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.pixels, greaterThan(0), reason: '목록이 구르지 않았다');
    expect(_mapTop(tester), before, reason: '목록을 밀었더니 지도까지 따라 올라갔다');
    expect(tester.getTopLeft(list).dy, listTop, reason: '목록 자리가 함께 움직였다');
  });

  testWidgets('화살표로 반반 ↔ 목록만 두 자리를 오간다 (#1370)', (tester) async {
    await _pumpFinder(tester);

    // 처음은 반반 — 지도가 위에 **가로로 긴 띠**로 눕는다. 높이는 고정값이라
    // 큰 화면에서도 머리줄·탭 줄을 밀어내지 않는다 (#1382).
    final double half = tester
        .getSize(find.byKey(const Key('gym-map-slot')))
        .height;
    expect(half, 200);

    await tester.tap(find.byKey(const ValueKey<String>('gym-list-toggle')));
    await tester.pumpAndSettle();
    // 목록만 — 지도 자리가 통째로 사라진다 (#1382).
    expect(find.byKey(const Key('gym-map-slot')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('gym-list-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('gym-map-slot'))).height, half);
  });

  testWidgets('시트는 화면 가로를 다 쓰고 지도와 겹치지 않는다 (#1362)', (tester) async {
    await _pumpFinder(tester);

    // `주변 헬스장` 은 화면 아래에 붙는 창이라 지도 폭에 맞춰 들여쓰지 않는다.
    final Finder sheet = find.byKey(const Key('gym-result-sheet'));
    expect(tester.getSize(sheet).width, 390);

    // 지도와 시트가 겹치는 자리가 있으면, 웹에서 시트 위의 터치가 아래 지도
    // (플랫폼 뷰)로 새어 나가 시트를 끌 수도 목록을 밀 수도 없게 된다.
    Rect map() => tester.getRect(find.byType(KakaoMapView).first);
    expect(map().bottom, lessThanOrEqualTo(tester.getTopLeft(sheet).dy + 0.5));

    // 목록만 보는 자리로 옮긴 뒤에도 겹치지 않는다.
    await tester.tap(find.byKey(const ValueKey<String>('gym-list-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(KakaoMapView), findsNothing);
  });

  testWidgets('검색 결과가 없으면 빈 문구가 그 자리에 뜬다', (tester) async {
    await _pumpFinder(tester);

    await tester.enterText(find.byType(TextField).first, '없는이름123');
    await tester.pumpAndSettle();

    expect(find.text('검색 결과가 없어요.'), findsOneWidget);
    // 지도는 그대로 남는다 — 결과가 없다고 화면이 비지 않는다.
    expect(find.byType(KakaoMapView), findsOneWidget);
  });

  testWidgets('작은 화면에서도 넘치지 않는다', (tester) async {
    await _pumpFinder(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
