/// 추천 이유의 강조와 자리. (#1445)
///
/// 추천 이유는 트레이너를 고르는 근거다. 헬스장 찾기 카드에서만 흰 배경·회색
/// 글씨라 옆의 일반 설명과 위계가 같았고, 상세 화면에서는 `트레이너 소개`
/// 아래에 있어 추천 목록에서 들어온 흐름이 근거를 뒤늦게 만났다.
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

  /// 사유 배지 하나. 순번은 [_kim.reasons] 순서다.
  Finder badgeAt(int index) =>
      find.byKey(ValueKey<String>('gym-trainer-reason-$index'));

  BoxDecoration decorationOf(WidgetTester tester, Finder badge) =>
      tester
              .widget<Container>(
                find.descendant(of: badge, matching: find.byType(Container)),
              )
              .decoration!
          as BoxDecoration;

  testWidgets('헬스장 찾기 카드의 추천 이유 배지가 파란 윤곽선·글씨다', (tester) async {
    await pumpAt(tester, AppRoutes.exerciseGym);

    // 근거가 있는 만큼 배지가 선다 (#1881).
    expect(
      find.byKey(const ValueKey<String>('gym-trainer-reasons')),
      findsOneWidget,
    );
    for (int i = 0; i < _kim.reasons.length; i++) {
      expect(badgeAt(i), findsOneWidget, reason: '${i + 1}번째 배지가 없다');
    }
    expect(badgeAt(_kim.reasons.length), findsNothing, reason: '없는 사유까지 그렸다');

    // 강조는 배지마다 같다 — 첫 배지만 파랗고 나머지가 흐리면 위계가 갈린다.
    for (int i = 0; i < _kim.reasons.length; i++) {
      final BoxDecoration decoration = decorationOf(tester, badgeAt(i));
      expect(decoration.border, isNotNull, reason: '파란 윤곽선으로 강조한다');
      expect(
        (decoration.border! as Border).top.color,
        OnCareBrand.member.border,
      );
      // 줄 자체가 옅은 파랑이라 배지 배경은 흰색 그대로다 — 같은 색이면 배지가
      // 사라진다.
      expect(decoration.color, OnCareColors.surfaceCard);

      final Text text = tester.widget<Text>(
        find.descendant(of: badgeAt(i), matching: find.byType(Text)),
      );
      expect(text.style!.color, OnCareBrand.member.primary);
      // 두 줄 제한은 그대로다 — 긴 이유가 카드를 밀지 않는다.
      expect(text.maxLines, 2);

      // 배지 안에는 사유만 서있다 — `추천 이유:` 접두어를 떼어내야
      // 알약이 줄 끝까지 늘어지지 않고 배지로 읽힌다 (#1847).
      expect(text.data, _kim.reasons[i]);
    }
    expect(find.textContaining('추천 이유:'), findsNothing);
  });

  testWidgets('사유가 하나뿐인 트레이너는 배지도 하나다', (tester) async {
    await pumpAt(tester, AppRoutes.exerciseGym, trainer: _bare);

    expect(badgeAt(0), findsOneWidget);
    expect(badgeAt(1), findsNothing);
    expect(find.text(_bare.reasons.single), findsOneWidget);
  });

  testWidgets('사유가 없는 트레이너는 배지 자리가 통째로 없다', (tester) async {
    await pumpAt(tester, AppRoutes.exerciseGym, trainer: _noReason);

    expect(
      find.byKey(const ValueKey<String>('gym-trainer-reasons')),
      findsNothing,
    );
    expect(badgeAt(0), findsNothing);
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
      expect(badgeAt(i), findsOneWidget);
      // 배지 자체가 화면 밖으로 나가지 않는다. 카드의 다른 줄이 좁은 화면에서
      // 넘치는 것은 이 이슈의 범위가 아니라 전체 예외로 판정하지 않는다.
      expect(tester.getBottomRight(badgeAt(i)).dx, lessThanOrEqualTo(320));
      tops.add(tester.getTopLeft(badgeAt(i)).dy);
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
