/// 추천 이유의 강조와 자리. (#1445 · #1881)
///
/// 추천 이유는 트레이너를 고르는 근거다. 헬스장 찾기 카드에서만 흰 배경·회색
/// 글씨라 옆의 일반 설명과 위계가 같았고, 상세 화면에서는 `트레이너 소개`
/// 아래에 있어 추천 목록에서 들어온 흐름이 근거를 뒤늦게 만났다.
///
/// 지금은 세 화면(헬스장 찾기 줄·트레이너 목록 카드·트레이너 상세)이 근거를
/// **헬스장 키워드와 같은 부품**(`AppTag`, 브랜드 톤)으로 적는다. 강조가 어떤
/// 색인지는 `oncare_ui` 가 정하므로 여기서는 색을 다시 세지 않고, 세 화면이
/// 같은 부품·같은 톤을 쓰는지와 줄 바탕이 그 태그를 삼키지 않는지를 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const Gym _gym = Gym(
  id: 'gym-reason',
  name: '추천 이유 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.4,
  rating: 4.8,
  tags: <String>['다이어트'],
);

const Trainer _kim = Trainer(
  id: 'trainer-kim',
  gymId: 'gym-reason',
  name: '김트레이너',
  role: '퍼스널 트레이너',
  reasons: <String>['혈압 관리', '체중 감량', '식습관 개선'],
  intro: '만성질환 회원과 함께 운동해 왔어요.',
  career: '8년',
  certifications: <String>['생활스포츠지도사 2급'],
);

/// 소개가 아예 없는 트레이너 — 소개 박스가 없어도 순서가 흔들리지 않아야 한다.
const Trainer _bare = Trainer(
  id: 'trainer-bare',
  gymId: 'gym-reason',
  name: '박트레이너',
  role: '재활 트레이너',
  reasons: <String>['무릎·허리 재활'],
);

/// 추천 사유가 아예 없는 트레이너 — 배지 자리가 통째로 비어야 한다.
const Trainer _noReason = Trainer(
  id: 'trainer-no-reason',
  gymId: 'gym-reason',
  name: '정트레이너',
  role: '퍼스널 트레이너',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

void main() {
  late GoRouter router;

  Future<void> pumpAt(
    WidgetTester tester,
    String location, {
    Trainer trainer = _kim,
    Size size = const Size(390, 900),
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(location);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          myGymProvider.overrideWith((ref) async => null),
          nearbyGymsProvider.overrideWith((ref) async => const <Gym>[_gym]),
          gymFinderResultsProvider.overrideWith(
            (ref) async => const <Gym>[_gym],
          ),
          myTrainerProvider.overrideWith((ref) async => null),
          trainerProvider(trainer.id).overrideWith((ref) async => trainer),
          gymTrainersProvider(
            _gym.id,
          ).overrideWith((ref) async => <Trainer>[trainer]),
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

  /// 사유 배지 하나. [prefix] 는 화면별 키 접두어, 순번은 사유 순서다.
  Finder badgeAt(String prefix, int index) =>
      find.byKey(ValueKey<String>('$prefix-reason-$index'));

  /// 한 화면이 [trainer] 의 근거를 **헬스장 키워드와 같은 태그**로 있는 만큼
  /// 적었는지. 세 화면이 같은 값을 같은 모양으로 말해야 목록에서 본 것을 상세
  /// 에서 다시 찾지 않는다 (#1881).
  void expectBrandPills(
    WidgetTester tester,
    String prefix, {
    Trainer trainer = _kim,
  }) {
    expect(find.byKey(ValueKey<String>('$prefix-reasons')), findsOneWidget);
    expect(
      badgeAt(prefix, trainer.reasons.length),
      findsNothing,
      reason: '없는 사유까지 그렸다',
    );

    for (int i = 0; i < trainer.reasons.length; i++) {
      final Finder badge = badgeAt(prefix, i);
      expect(badge, findsOneWidget, reason: '${i + 1}번째 배지가 없다');

      final AppTag tag = tester.widget<AppTag>(badge);
      // 강조는 배지마다 같다 — 첫 배지만 브랜드 톤이고 나머지가 회색이면
      // 위계가 갈린다.
      expect(tag.tone, AppTagTone.brand, reason: '$prefix ${i + 1}번째 톤');
      // 태그 안에는 사유만 서있다 — `추천 이유:` 접두어를 떼어내야 알약이 줄
      // 끝까지 늘어지지 않고 배지로 읽힌다 (#1847).
      expect(tag.label, trainer.reasons[i]);
    }
    expect(find.textContaining('추천 이유:'), findsNothing);
  }

  testWidgets('헬스장 찾기 카드의 추천 이유가 헬스장 키워드와 같은 태그다', (tester) async {
    await pumpAt(tester, AppRoutes.exerciseGym);

    // 근거가 있는 만큼 배지가 선다 (#1881).
    expectBrandPills(tester, 'gym-trainer');

    // 줄 바탕이 태그 채움색과 같으면 태그가 바탕에 묻힌다 — #1445 가 배지를
    // 따로 만들게 했던 그 문제다. 바탕을 비워 뒀는지 여기서 지킨다.
    final BoxDecoration line =
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: badgeAt('gym-trainer', 0),
                        matching: find.byType(Container),
                      )
                      .last,
                )
                .decoration!
            as BoxDecoration;
    expect(line.color, isNot(OnCareBrand.member.surface));
    expect(line.color, OnCareColors.surfaceCard);
  });

  testWidgets('트레이너 상세도 같은 알약으로 근거를 적는다', (tester) async {
    await pumpAt(tester, AppRoutes.trainerDetailPath(_kim.id));

    expectBrandPills(tester, 'trainer-detail');
  });

  testWidgets('헬스장 상세의 소속 트레이너 줄에도 근거가 붙는다', (tester) async {
    await pumpAt(tester, AppRoutes.gymDetailPath(_gym.id));

    // 여기가 상담할 트레이너를 고르는 자리다 — 찾기에서 본 근거가 사라지면
    // 정작 고를 때 다시 찾아야 한다 (#1881).
    expectBrandPills(tester, 'gym-detail-trainer-${_kim.id}');
    // 이름·직함 아래에 선다.
    expect(
      tester.getTopLeft(badgeAt('gym-detail-trainer-${_kim.id}', 0)).dy,
      greaterThan(tester.getTopLeft(find.text(_kim.name)).dy),
    );
  });

  testWidgets('근거가 없는 트레이너는 헬스장 상세에서도 줄만 선다', (tester) async {
    await pumpAt(tester, AppRoutes.gymDetailPath(_gym.id), trainer: _noReason);

    expect(find.text(_noReason.name), findsWidgets);
    expect(
      find.byKey(
        ValueKey<String>('gym-detail-trainer-${_noReason.id}-reasons'),
      ),
      findsNothing,
    );
  });

  testWidgets('사유가 하나뿐인 트레이너는 세 화면 모두 배지도 하나다', (tester) async {
    for (final (String location, String prefix) in <(String, String)>[
      (AppRoutes.exerciseGym, 'gym-trainer'),
      (AppRoutes.gymDetailPath(_gym.id), 'gym-detail-trainer-${_bare.id}'),
      (AppRoutes.trainerDetailPath(_bare.id), 'trainer-detail'),
    ]) {
      await pumpAt(tester, location, trainer: _bare);

      expectBrandPills(tester, prefix, trainer: _bare);
      expect(badgeAt(prefix, 1), findsNothing, reason: prefix);
    }
  });

  testWidgets('사유가 없는 트레이너는 헬스장 찾기 줄에서 배지 자리가 통째로 없다', (tester) async {
    await pumpAt(tester, AppRoutes.exerciseGym, trainer: _noReason);

    expect(
      find.byKey(const ValueKey<String>('gym-trainer-reasons')),
      findsNothing,
    );
    expect(badgeAt('gym-trainer', 0), findsNothing);
  });

  testWidgets('사유가 없으면 상세는 기본 문구를 문장으로 둔다', (tester) async {
    await pumpAt(
      tester,
      AppRoutes.trainerDetailPath(_noReason.id),
      trainer: _noReason,
    );

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    // 한 문장을 알약에 넣으면 카드 끝까지 늘어져 배지로 읽히지 않는다.
    expect(
      find.byKey(const ValueKey<String>('trainer-detail-reasons')),
      findsNothing,
    );
    expect(find.text(l.exTrainerRecommendationReason), findsOneWidget);
    // 근거 박스 자체는 남는다 — 소속·상담 CTA 와의 순서가 흔들리지 않게.
    expect(find.byKey(const Key('trainer-detail-reason')), findsOneWidget);
  });

  testWidgets('좁은 화면·큰 배율에서도 배지가 화면 안에 있다', (tester) async {
    await pumpAt(
      tester,
      AppRoutes.exerciseGym,
      size: const Size(320, 900),
      textScale: 1.3,
    );

    final List<double> tops = <double>[];
    for (int i = 0; i < _kim.reasons.length; i++) {
      final Finder badge = badgeAt('gym-trainer', i);
      expect(badge, findsOneWidget);
      // 배지 자체가 화면 밖으로 나가지 않는다. 카드의 다른 줄이 좁은 화면에서
      // 넘치는 것은 이 이슈의 범위가 아니라 전체 예외로 판정하지 않는다.
      expect(tester.getBottomRight(badge).dx, lessThanOrEqualTo(320));
      tops.add(tester.getTopLeft(badge).dy);
    }
    // 한 줄에 다 못 서면 다음 줄로 흘러 내려간다 — 옆으로 밀려 잘리지 않는다.
    expect(tops.toSet().length, greaterThan(1), reason: '배지가 줄바꿈되지 않았다');
    expect(tester.takeException(), isNull);
  });

  testWidgets('상세 화면에서 추천 이유가 트레이너 소개보다 위에 선다', (tester) async {
    await pumpAt(tester, AppRoutes.trainerDetailPath(_kim.id));

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    final Finder reason = find.byKey(const Key('trainer-detail-reason'));
    expect(reason, findsOneWidget);
    expect(
      tester.getTopLeft(reason).dy,
      lessThan(tester.getTopLeft(find.text(l.exTrainerIntroSection)).dy),
    );
  });

  testWidgets('소개가 없는 트레이너도 추천 이유 박스는 그대로다', (tester) async {
    await pumpAt(tester, AppRoutes.trainerDetailPath(_bare.id), trainer: _bare);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.byKey(const Key('trainer-detail-reason')), findsOneWidget);
    expect(find.text(l.exTrainerIntroSection), findsNothing);
    // 상담 요청 CTA 는 그대로 남는다.
    expect(find.byKey(const Key('consult-start')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
