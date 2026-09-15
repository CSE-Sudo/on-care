/// 헬스장 카드의 트레이너 줄과 지도·목록 접기 (#1185 · #1186 · #1187).
///
///  * 찾기 목록의 헬스장 카드는 그곳 소속 트레이너를 전원 적는다 — 헬스장을
///    견주는 자리에서 누가 있는지가 카드 안에서 읽혀야 한다.
///  * 연결된 내 헬스장 카드는 담당 트레이너와 상세 이동을 한 줄로 적는다.
///  * 지도 위의 결과 시트는 세 자리(목록만·반반·지도만)를 오가고, 머리줄
///    화살표는 그 시트와 같은 자리를 가리킨다 (#1274).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/trainer_detail_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/kakao_map/kakao_map_view.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const Gym _gym = Gym(
  id: 'gym-trainer-line',
  name: '트레이너 줄 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.4,
  rating: 4.8,
  tags: <String>['다이어트', '재활운동'],
);

const Trainer _kim = Trainer(
  id: 'trainer-kim',
  gymId: 'gym-trainer-line',
  name: '김트레이너',
  role: '퍼스널 트레이너',
  reason: '혈압 관리와 운동 병행 지도',
);

const Trainer _park = Trainer(
  id: 'trainer-park',
  gymId: 'gym-trainer-line',
  name: '박트레이너',
  role: '재활 트레이너',
  reason: '무릎·허리 통증 관리 다수 경험',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

void main() {
  late GoRouter router;

  Future<void> pumpGymTab(
    WidgetTester tester, {
    bool hasMyGym = true,
    Trainer? myTrainer = _kim,
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.exerciseGym);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          myGymProvider.overrideWith((ref) async => hasMyGym ? _gym : null),
          nearbyGymsProvider.overrideWith((ref) async => const <Gym>[_gym]),
          gymFinderResultsProvider.overrideWith(
            (ref) async => const <Gym>[_gym],
          ),
          myTrainerProvider.overrideWith((ref) async => myTrainer),
          trainerProvider(_kim.id).overrideWith((ref) async => _kim),
          gymTrainersProvider(
            _gym.id,
          ).overrideWith((ref) async => const <Trainer>[_kim, _park]),
          recommendedTrainersProvider.overrideWith(
            (ref) async => const <Trainer>[],
          ),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
          memberCoachProvider.overrideWith((ref) async => null),
          myReservationsProvider.overrideWith((ref) async => const []),
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
  }

  group('내 헬스장 카드의 담당 트레이너 줄 (#1187)', () {
    testWidgets('이름·직함과 함께 상세 이동 화살표가 붙는다', (WidgetTester tester) async {
      await pumpGymTab(tester);

      expect(find.byKey(const Key('gym-trainer-line-mine')), findsOneWidget);
      expect(find.text('김트레이너'), findsWidgets);
      expect(find.text('퍼스널 트레이너'), findsWidgets);
      // 연결 상태는 카드 머리에서 한 번만 말한다.
      expect(find.text('연결됨'), findsOneWidget);
      expect(find.textContaining('상세보기'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('gymTrainerDetailButton')),
          matching: find.byIcon(AppIcons.chevronRight),
        ),
        findsOneWidget,
      );
      // 이미 함께 하는 사람에게 고를 이유를 다시 적지 않는다.
      expect(find.textContaining('추천 이유'), findsNothing);
    });

    testWidgets('상세 이동 화살표는 트레이너 줄 오른쪽 끝에 선다', (WidgetTester tester) async {
      await pumpGymTab(tester);

      final Finder line = find.byKey(const Key('gym-trainer-line-mine'));
      final Finder name = find.descendant(
        of: line,
        matching: find.text('김트레이너'),
      );
      final Finder detail = find.descendant(
        of: line,
        matching: find.byKey(const Key('gymTrainerDetailButton')),
      );

      expect(
        tester.getTopLeft(detail).dx,
        greaterThan(tester.getTopRight(name).dx),
      );
      expect(
        tester.getBottomRight(line).dx - tester.getBottomRight(detail).dx,
        lessThan(16),
      );
    });

    testWidgets('상세 이동 화살표를 누르면 트레이너 상세로 간다', (WidgetTester tester) async {
      await pumpGymTab(tester);

      await tester.tap(find.byKey(const Key('gymTrainerDetailButton')));
      await tester.pumpAndSettle();

      expect(find.byType(TrainerDetailPage), findsOneWidget);
    });

    testWidgets('담당 트레이너가 없으면 줄 자체가 없다', (WidgetTester tester) async {
      await pumpGymTab(tester, myTrainer: null);

      expect(find.byKey(const Key('gym-trainer-line-mine')), findsNothing);
      expect(find.byKey(const Key('gymTrainerDetailButton')), findsNothing);
    });
  });

  group('헬스장 찾기 목록의 소속 트레이너 (#1185)', () {
    testWidgets('카드마다 그 헬스장 트레이너를 전원 적는다', (WidgetTester tester) async {
      await pumpGymTab(tester, hasMyGym: false);

      expect(find.byKey(const Key('gym-trainer-trainer-kim')), findsOneWidget);
      expect(find.byKey(const Key('gym-trainer-trainer-park')), findsOneWidget);
      expect(find.text('퍼스널 트레이너'), findsOneWidget);
      expect(find.text('재활 트레이너'), findsOneWidget);
      expect(find.text('추천 이유: 혈압 관리와 운동 병행 지도'), findsOneWidget);
      // 아직 아무와도 연결되지 않았다 — 배지는 뜨지 않는다.
      expect(find.text('연결됨'), findsNothing);
    });
  });

  group('지도·목록 두 자리 (#1186 · #1274 · #1370)', () {
    final Finder sheet = find.byKey(const Key('gym-result-sheet'));
    final Finder mapSlot = find.byKey(const Key('gym-map-slot'));
    final Finder toggle = find.byKey(const ValueKey<String>('gym-list-toggle'));

    /// 지도의 윗변. 자리를 어떻게 바꾸든 이 값은 그대로여야 한다.
    double mapTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(KakaoMapView).first).dy;

    IconData? arrow(WidgetTester tester) => tester
        .widget<Icon>(find.descendant(of: toggle, matching: find.byType(Icon)))
        .icon;

    testWidgets('처음에는 지도와 목록이 함께 보인다', (WidgetTester tester) async {
      await pumpGymTab(tester, hasMyGym: false);

      expect(toggle, findsOneWidget);
      expect(find.text(_gym.name), findsWidgets);
      expect(find.text('1개 결과'), findsOneWidget);
      expect(find.byType(KakaoMapView), findsOneWidget);
      // 지도는 위에 가로로 길게 눕고, 목록이 그 아래를 잇는다.
      expect(tester.getSize(mapSlot).height, greaterThan(0));
      expect(tester.getTopLeft(sheet).dy, tester.getBottomLeft(mapSlot).dy);
      expect(arrow(tester), AppIcons.expandLess);
    });

    testWidgets('화살표로 목록만 보고 다시 지도를 부른다', (WidgetTester tester) async {
      await pumpGymTab(tester, hasMyGym: false);
      final double sheetTop = tester.getTopLeft(sheet).dy;

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      // 목록만 — 지도 자리가 통째로 사라지고 목록이 그 자리를 받는다 (#1382).
      expect(mapSlot, findsNothing);
      expect(find.byType(KakaoMapView), findsNothing);
      expect(tester.getTopLeft(sheet).dy, lessThan(sheetTop));
      // 다시 부를 머리줄은 남아 있고, 화살표가 방향을 뒤집는다.
      expect(find.text('주변 헬스장'), findsOneWidget);
      expect(arrow(tester), AppIcons.expandMore);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(KakaoMapView), findsOneWidget);
      expect(tester.getTopLeft(sheet).dy, sheetTop);
    });

    testWidgets('끌어서는 자리가 바뀌지 않는다 (#1370)', (WidgetTester tester) async {
      await pumpGymTab(tester, hasMyGym: false);
      final double sheetTop = tester.getTopLeft(sheet).dy;
      final double before = mapTop(tester);

      // 자리를 바꾸는 길은 화살표뿐이다 — 끄는 손짓은 목록 스크롤의 것이라,
      // 시트가 그 손짓을 가져가면 목록이 넘어가지 않는다.
      await tester.drag(sheet, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(sheet).dy, sheetTop);
      expect(mapTop(tester), before);

      await tester.drag(sheet, const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(sheet).dy, sheetTop);
      expect(mapTop(tester), before);
    });
  });
}
