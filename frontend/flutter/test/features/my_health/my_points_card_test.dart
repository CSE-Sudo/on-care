/// MY 포인트 카드 위치와 적립 안내 (i) 버튼 자리. (#1785)
///
/// 포인트 카드는 `내 헬스장 · 트레이너` 섹션 아래에 선다. 적립 안내 (i) 는
/// 잔액 숫자 옆이 아니라 `포인트 사용처` 화면 헤더 오른쪽 끝에 있다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../benefits/fake_benefits_repository.dart';

void main() {
  const Size surface = Size(390, 1600);

  Future<void> pumpHome(WidgetTester tester, Widget home) async {
    // 목록 끝까지 한 번에 그려지도록 세로를 넉넉히 둔다.
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
          // 잔액 문구를 데모 시작 잔액과 떼어 둔다.
          myHealthRepositoryProvider.overrideWithValue(
            MockMyHealthRepository(
              points: DemoPointsLedger(openingBalance: 1240),
            ),
          ),
          // 사용처 화면은 교환 목록을 읽는다(#1787) — 가짜 저장소로 채운다.
          benefitsRepositoryProvider.overrideWithValue(FakeBenefitsRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder banner() => find.byKey(const Key('pointsBanner'));

  testWidgets('포인트 카드는 내 헬스장 · 트레이너 섹션 아래, 설정 위에 선다', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, const MyHealthPage());

    final double trainerGymTop = tester
        .getTopLeft(find.text('내 헬스장 · 트레이너'))
        .dy;
    final double gymCardBottom = tester
        .getBottomLeft(find.byKey(const Key('my-gym-info-card')))
        .dy;
    final double bannerTop = tester.getTopLeft(banner()).dy;
    final double bannerBottom = tester.getBottomLeft(banner()).dy;
    final double settingsTop = tester.getTopLeft(find.text('설정')).dy;

    expect(trainerGymTop, lessThan(bannerTop));
    expect(bannerTop, lessThan(settingsTop));
    // 섹션 사이 간격은 모두 같은 섹션 간격이다.
    expect(bannerTop - gymCardBottom, OnCareSpacing.sectionGap);
    expect(
      settingsTop - bannerBottom,
      greaterThanOrEqualTo(OnCareSpacing.sectionGap),
    );
    // 프로필 카드 바로 아래에는 트레이너 · 헬스장 섹션이 온다.
    final double profileBottom = tester
        .getBottomLeft(find.byType(AppCard).first)
        .dy;
    expect(
      tester.getTopLeft(find.byType(AppSectionHeader).first).dy - profileBottom,
      OnCareSpacing.sectionGap,
    );
  });

  testWidgets('MY 포인트 카드에는 적립 안내 (i) 버튼이 없다', (WidgetTester tester) async {
    await pumpHome(tester, const MyHealthPage());

    expect(banner(), findsOneWidget);
    expect(
      find.descendant(of: banner(), matching: find.byType(AppIconButton)),
      findsNothing,
    );
    expect(find.byTooltip('포인트 적립 안내'), findsNothing);
    expect(find.byIcon(AppIcons.info), findsNothing);
    // 카드 구성은 별 아이콘·잔액·화살표다.
    expect(
      find.descendant(of: banner(), matching: find.byIcon(AppIcons.star)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner(), matching: find.text('1,240P')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: banner(),
        matching: find.byIcon(AppIcons.chevronRight),
      ),
      findsOneWidget,
    );
  });

  testWidgets('포인트 카드는 파란 바탕·노란 별·흰 숫자와 화살표를 쓴다', (WidgetTester tester) async {
    await pumpHome(tester, const MyHealthPage());

    final Material material = tester.widget<Material>(
      find.descendant(of: banner(), matching: find.byType(Material)).first,
    );
    expect(material.color, OnCareBrand.member.pointsCard);

    final Iterable<AppIcon> icons = tester.widgetList<AppIcon>(
      find.descendant(of: banner(), matching: find.byType(AppIcon)),
    );
    final AppIcon star = icons.singleWhere(
      (AppIcon icon) => icon.icon == AppIcons.star,
    );
    expect(star.color, OnCareColors.overlayReward);

    final Text balance = tester.widget<Text>(
      find.descendant(of: banner(), matching: find.text('1,240P')),
    );
    expect(balance.style?.color, OnCareColors.textOnFill);

    final AppIcon arrow = icons.singleWhere(
      (AppIcon icon) => icon.icon == AppIcons.chevronRight,
    );
    expect(arrow.color, OnCareColors.textOnFill);
  });

  testWidgets('포인트 사용처 헤더 오른쪽 끝의 (i) 가 적립 안내 창을 연다', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, const PointsBenefitsPage(points: 1240));

    final Finder info = find.descendant(
      of: find.byType(AppTopBar),
      matching: find.byType(AppIconButton),
    );
    expect(info, findsOneWidget);
    final AppIconButton button = tester.widget<AppIconButton>(info);
    // 채운 글리프, 배경 없는 버튼, 접근성 이름은 창 제목과 같다.
    expect(button.icon, AppIcons.info);
    expect(button.variant, AppIconButtonVariant.plain);
    expect(button.tooltip, '포인트 적립 안내');
    // 헤더 제목보다 오른쪽, 앱바 끝 여백만큼 떨어진 오른쪽 끝에 선다.
    expect(
      tester.getTopLeft(info).dx,
      greaterThan(tester.getTopRight(find.text('포인트 사용처')).dx),
    );
    expect(tester.getTopRight(info).dx, surface.width - OnCareSpacing.s8);

    await tester.tap(info);
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.text('포인트 적립 안내'),
      ),
      findsOneWidget,
    );
    expect(find.text('+50P'), findsNWidgets(2));
    expect(find.text('+20P'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byKey(const Key('pointsBenefitsPage')), findsOneWidget);
  });
}
