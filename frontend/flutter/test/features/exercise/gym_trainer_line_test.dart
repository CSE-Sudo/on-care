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
import 'package:oncare/features/exercise/presentation/pages/gym_detail_page.dart';
import 'package:oncare/features/exercise/presentation/pages/trainer_detail_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/kakao_map/kakao_map_view.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

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
  reasons: <String>['혈압 관리', '체중 감량', '식습관 개선'],
);

const Trainer _park = Trainer(
  id: 'trainer-park',
  gymId: 'gym-trainer-line',
  name: '박트레이너',
  role: '재활 트레이너',
  reasons: <String>['무릎·허리 재활'],
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

  /// 트레이너 줄 바깥 상자의 꾸밈 — 줄의 뿌리가 그 Container 다.
  BoxDecoration lineOf(WidgetTester tester, Key key) =>
      tester
              .widget<Container>(
                find
                    .descendant(
                      of: find.byKey(key),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;

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

    testWidgets('헬스장 줄과 트레이너 줄의 화살표가 같은 자리에 선다 (#1881)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester);

      // 한 카드 안에서 같은 뜻의 화살표가 서로 다른 자리에 서면 카드가
      // 삐뚤어 보인다. 위가 헬스장 줄, 아래가 트레이너 줄이다.
      final Finder arrows = find.descendant(
        of: find.byKey(const Key('my-gym-info-card')),
        matching: find.byIcon(AppIcons.chevronRight),
      );
      expect(arrows, findsNWidgets(2));
      expect(
        tester.getBottomRight(arrows.at(1)).dx,
        tester.getBottomRight(arrows.at(0)).dx,
      );
    });

    testWidgets('트레이너 줄이 위 헬스장 줄과 한 격자에 선다 (#2038)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester);

      // 같은 카드의 두 줄이다 — 사람 아이콘은 덤벨 아이콘과 같은 세로 중심에,
      // 트레이너 이름은 헬스장 이름과 같은 세로선에 선다. 예전에는 아이콘 칸
      // 24 · 간격 8 이라 헬스장 줄(40 · 12)보다 20 만큼 왼쪽에서 시작했다.
      final Finder card = find.byKey(const Key('my-gym-info-card'));
      final Finder line = find.byKey(const Key('gym-trainer-line-mine'));

      final double gymIconX = tester
          .getCenter(find.byKey(const Key('connectedGymIcon')))
          .dx;
      final double trainerIconX = tester
          .getCenter(
            find.descendant(of: line, matching: find.byIcon(AppIcons.person)),
          )
          .dx;
      expect(trainerIconX, moreOrLessEquals(gymIconX, epsilon: 0.5));

      final double gymNameX = tester
          .getTopLeft(find.descendant(of: card, matching: find.text(_gym.name)))
          .dx;
      final double trainerNameX = tester
          .getTopLeft(find.descendant(of: line, matching: find.text('김트레이너')))
          .dx;
      expect(trainerNameX, moreOrLessEquals(gymNameX, epsilon: 0.5));
      final Finder gymName = find.descendant(
        of: card,
        matching: find.text(_gym.name),
      );
      final Finder trainerName = find.descendant(
        of: line,
        matching: find.text(_kim.name),
      );
      expect(
        tester.widget<Text>(trainerName).style,
        tester.widget<Text>(gymName).style,
      );
      final Finder role = find.descendant(
        of: line,
        matching: find.text(_kim.role!),
      );
      final Finder address = find.descendant(
        of: card,
        matching: find.textContaining(_gym.address),
      );
      expect(
        tester.widget<Text>(role).style,
        tester.widget<Text>(address).style,
      );
      expect(
        tester.getSize(line).height,
        tester.getSize(find.byKey(const Key('connectedGymRow'))).height + 8,
      );
      final Finder person = find.descendant(
        of: line,
        matching: find.byIcon(AppIcons.person),
      );
      final Finder gymIcon = find.descendant(
        of: card,
        matching: find.byIcon(AppIcons.gym),
      );
      expect(tester.getSize(person), tester.getSize(gymIcon));
      final Finder divider = find.descendant(
        of: card,
        matching: find.byType(AppDivider),
      );
      expect(divider, findsOneWidget);
      expect(
        tester.getCenter(divider).dy,
        greaterThan(tester.getBottomLeft(gymName).dy),
      );
      expect(
        tester.getCenter(divider).dy,
        lessThan(tester.getTopLeft(line).dy),
      );
    });

    testWidgets('사람 아이콘을 그대로 둔다 (#2154)', (WidgetTester tester) async {
      await pumpGymTab(tester);

      // 성씨 프로필은 헬스장 찾기·헬스장 상세에서만 쓴다 — 여기는 위 헬스장
      // 줄의 덤벨 아이콘과 한 격자에 서는 아이콘 자리다.
      final Finder line = find.byKey(const Key('gym-trainer-line-mine'));
      expect(
        find.descendant(of: line, matching: find.byIcon(AppIcons.person)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.byType(AppAvatar)),
        findsNothing,
      );
    });

    testWidgets('한 명뿐이라 줄을 두르지 않는다 (#1881)', (WidgetTester tester) async {
      await pumpGymTab(tester);

      // 가를 상대가 없는데 두르면 카드 안에 상자가 하나 더 생긴다.
      final BoxDecoration mine = lineOf(
        tester,
        const Key('gym-trainer-line-mine'),
      );
      expect(mine.color, OnCareColors.surfaceCard);
      expect(mine.border, isNull);
    });

    testWidgets('담당 트레이너가 없으면 안내와 구분선을 표시한다 (#2072)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester, myTrainer: null);

      expect(find.byKey(const Key('gym-trainer-line-mine')), findsNothing);
      expect(find.byKey(const Key('gymTrainerDetailButton')), findsNothing);
      expect(
        find.text(
          AppLocalizations.of(
            tester.element(find.byKey(const Key('my-gym-info-card'))),
          ).myNoTrainer,
        ),
        findsOneWidget,
      );
      expect(find.text('트레이너 찾기'), findsNothing);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byKey(const Key('my-gym-info-card'))),
      );
      final Uri beforeTap = router.routerDelegate.currentConfiguration.uri;
      await tester.tap(find.text(l.myNoTrainer));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri, beforeTap);
      expect(find.byType(TrainerDetailPage), findsNothing);
      expect(find.byType(GymDetailPage), findsNothing);

      expect(
        find.descendant(
          of: find.byKey(const Key('my-gym-info-card')),
          matching: find.byType(AppDivider),
        ),
        findsOneWidget,
      );
    });
  });

  group('헬스장 찾기 목록의 소속 트레이너 (#1185)', () {
    testWidgets('카드마다 그 헬스장 트레이너를 전원 적는다', (WidgetTester tester) async {
      await pumpGymTab(tester, hasMyGym: false);

      expect(find.byKey(const Key('gym-trainer-trainer-kim')), findsOneWidget);
      expect(find.byKey(const Key('gym-trainer-trainer-park')), findsOneWidget);
      expect(find.text('퍼스널 트레이너'), findsOneWidget);
      expect(find.text('재활 트레이너'), findsOneWidget);
      // 사유만 적는다 — `추천 이유:` 접두어는 붙지 않는다 (#1847). 근거가 여럿인
      // 트레이너는 있는 만큼 배지가 서고, 하나뿐인 트레이너는 하나만 선다 (#1881).
      for (final String reason in _kim.reasons) {
        expect(find.text(reason), findsOneWidget);
      }
      expect(find.text(_park.reasons.single), findsOneWidget);
      expect(find.textContaining('추천 이유:'), findsNothing);
      // 아직 아무와도 연결되지 않았다 — 배지는 뜨지 않는다.
      expect(find.text('연결됨'), findsNothing);
    });

    testWidgets('트레이너마다 성씨 프로필로 선다 (#2154)', (WidgetTester tester) async {
      await pumpGymTab(tester, hasMyGym: false);

      // 트레이너 상세·채팅과 같은 얼굴이라, 눌러 들어가도 같은 사람으로 읽힌다.
      for (final Trainer trainer in <Trainer>[_kim, _park]) {
        final Finder line = find.byKey(Key('gym-trainer-${trainer.id}'));
        final Finder avatar = find.descendant(
          of: line,
          matching: find.byType(AppAvatar),
        );
        expect(avatar, findsOneWidget);
        expect(tester.widget<AppAvatar>(avatar).name, trainer.name);
        expect(tester.widget<AppAvatar>(avatar).size, AppAvatarSize.small);
        expect(
          find.descendant(of: avatar, matching: find.text(trainer.name[0])),
          findsOneWidget,
        );
        expect(
          find.descendant(of: line, matching: find.byIcon(AppIcons.person)),
          findsNothing,
        );
      }
    });

    testWidgets('잇달아 서는 줄은 회색 실선으로 서로를 가른다 (#1881)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester, hasMyGym: false);

      // 바탕이 카드와 같은 흰색이라, 실선이 없으면 한 카드에 쌓인 여러 명이
      // 어디서 갈리는지 흐려진다.
      final BoxDecoration listed = lineOf(
        tester,
        const Key('gym-trainer-trainer-kim'),
      );
      expect(listed.color, OnCareColors.surfaceCard);
      expect((listed.border! as Border).top.color, OnCareColors.lineSubtle);
    });

    testWidgets('트레이너 줄을 누르면 그 트레이너 상세로 간다 (#2038)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester, hasMyGym: false);

      // 예전에는 읽기만 하는 줄이라 탭이 바깥 카드로 흘러 헬스장 상세가
      // 열렸다 — 트레이너를 눌렀는데 헬스장에 도착했다.
      await tester.tap(find.byKey(const Key('gym-trainer-trainer-kim')));
      await tester.pumpAndSettle();

      // `context.push` 는 경로를 쌓는다 — 라우터의 기준 위치는 그대로라
      // 도착한 화면으로 본다(위 `상세 이동 화살표` 테스트와 같은 방식).
      expect(find.byType(TrainerDetailPage), findsOneWidget);
      expect(find.byType(GymDetailPage), findsNothing);
    });

    testWidgets('트레이너 줄 밖을 누르면 지금처럼 헬스장 상세로 간다 (#2038)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester, hasMyGym: false);

      // 헬스장 이름은 지도 핀에도 적혀 있어 여럿이 잡힌다 — 목록 카드 안의
      // 것을 누른다.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const Key('gym-result-sheet')),
              matching: find.text(_gym.name),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.byType(GymDetailPage), findsOneWidget);
      expect(find.byType(TrainerDetailPage), findsNothing);
    });

    testWidgets('화살표를 붙여도 이름·직함은 한 줄에 둔다 (#2038)', (WidgetTester tester) async {
      await pumpGymTab(tester, hasMyGym: false);

      // 쌓으면 트레이너가 여럿인 카드가 사람마다 한 줄씩 길어진다 — 이전
      // 모양 그대로 직함이 이름 옆에 선다.
      final Finder line = find.byKey(const Key('gym-trainer-trainer-kim'));
      final Finder name = find.descendant(
        of: line,
        matching: find.text('김트레이너'),
      );
      final Finder role = find.descendant(
        of: line,
        matching: find.text('퍼스널 트레이너'),
      );
      expect(
        tester.getCenter(role).dy,
        moreOrLessEquals(tester.getCenter(name).dy, epsilon: 2),
      );
      expect(
        tester.getTopLeft(role).dx,
        greaterThan(tester.getTopRight(name).dx),
      );
    });

    testWidgets('추천 이유 배지는 이름과 같은 세로선에서 시작한다 (#2038)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester, hasMyGym: false);

      // 같은 카드 위 헬스장 블록이 태그를 이름 아래 글자 칸에 두듯, 트레이너
      // 배지도 사람 아이콘 오른쪽 — 이름이 시작하는 자리 — 에서 시작한다.
      // 들이지 않으면 배지가 아이콘보다도 왼쪽에 붙어 누구의 근거인지 흐려진다.
      for (final Trainer trainer in <Trainer>[_kim, _park]) {
        final Finder line = find.byKey(Key('gym-trainer-${trainer.id}'));
        final double nameX = tester
            .getTopLeft(
              find.descendant(of: line, matching: find.text(trainer.name)),
            )
            .dx;
        final double badgeX = tester
            .getTopLeft(
              find.descendant(
                of: line,
                matching: find.byKey(
                  const ValueKey<String>('gym-trainer-reason-0'),
                ),
              ),
            )
            .dx;
        expect(badgeX, moreOrLessEquals(nameX, epsilon: 0.5));
      }
    });

    testWidgets('내 헬스장 카드도 이름·직함을 한 줄에 둔다 (#2038)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester);

      // 이름과 짧은 속성은 한 줄에 읽힌다 — 두 줄은 기능을 풀어 쓰는 `제목 +
      // 설명` 줄의 몫이다. 예전에 쌓았던 까닭(`연결됨` 배지·`상세보기` 버튼이
      // 함께 서서 직함이 잘렸다, #1187)은 둘이 카드 머리와 화살표로 옮겨
      // 없어졌다. 찾기 목록과 같은 한 줄이다.
      final Finder line = find.byKey(const Key('gym-trainer-line-mine'));
      final Finder name = find.descendant(
        of: line,
        matching: find.text('김트레이너'),
      );
      final Finder role = find.descendant(
        of: line,
        matching: find.text('퍼스널 트레이너'),
      );
      expect(
        tester.getCenter(role).dy,
        moreOrLessEquals(tester.getCenter(name).dy, epsilon: 2),
      );
      expect(
        tester.getTopLeft(role).dx,
        greaterThan(tester.getTopRight(name).dx),
      );
    });

    testWidgets('트레이너 줄이 내 헬스장 카드와 같은 화살표를 단다 (#2038)', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester, hasMyGym: false);

      // 같은 줄이 화면마다 다른 곳으로 가지 않는다 — 누를 수 있다는 표시도
      // 같아야 한다.
      for (final Trainer trainer in <Trainer>[_kim, _park]) {
        expect(
          find.descendant(
            of: find.byKey(Key('gym-trainer-${trainer.id}')),
            matching: find.byKey(const Key('gymTrainerDetailButton')),
          ),
          findsOneWidget,
        );
      }
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
