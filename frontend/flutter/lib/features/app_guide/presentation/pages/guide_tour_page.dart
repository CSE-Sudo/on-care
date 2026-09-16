import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/app_guide/domain/guide_sample_data.dart';
import 'package:oncare/features/app_guide/domain/guide_step.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/features/app_guide/presentation/widgets/app_guide_overlay.dart';
import 'package:oncare/features/dashboard/presentation/widgets/dashboard_content.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/shared/widgets/member_bottom_nav.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 온보딩 끝에 한 번 보는 사용 가이드 — **진짜 화면들 위에서** 진행한다. (#1857)
///
/// 탭을 옮겨 가며 그 탭의 화면을 그린다(홈 → 식단 → 운동 → MY). 한 화면에
/// 머물면서 다른 탭 이야기를 하면, 정작 그 탭에 갔을 때 무엇을 봐야 할지
/// 모른다.
///
/// 화면은 앱이 쓰는 그 위젯이다. 비슷하게 흉내 낸 화면을 따로 그리면 앱이 바뀔
/// 때마다 안내만 옛 모습으로 남는다. 다른 것은 **값**뿐이다 — 가입 직후의 앱은
/// 기록이 하나도 없어 빈 카드를 짚게 되므로, 기록이 쌓인 모습
/// ([guideSampleOverrides])으로 채워 그 위에서 짚고 `예시 화면` 이라고 밝힌다.
///
/// 이 화면의 카드·버튼은 눌리지 않는다. 안내 도중 다른 화면으로 새지 않게 하려는
/// 것이고, 진짜 기능은 가이드가 끝난 뒤에 만난다.
class GuideTourPage extends ConsumerStatefulWidget {
  const GuideTourPage({super.key});

  @override
  ConsumerState<GuideTourPage> createState() => _GuideTourPageState();
}

class _GuideTourPageState extends ConsumerState<GuideTourPage> {
  /// 예시 값은 가이드가 열려 있는 동안 **한 벌**이다. build 마다 다시 만들면
  /// 탭을 옮길 때마다 화면이 처음부터 자료를 받아 오는 것처럼 깜빡인다.
  late final List<Override> _overrides = guideSampleOverrides();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AppGuideController controller = ref.read(
        appGuideControllerProvider.notifier,
      );
      controller.start();
      // 이미 본 회원이면 가이드가 켜지지 않는다 — 그대로 홈으로 보낸다.
      if (!ref.read(appGuideControllerProvider).active) _goHome();
    });
  }

  void _goHome() {
    if (!mounted) return;
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    // 마지막까지 봤든 건너뛰었든, 가이드가 끝나면 홈으로 간다.
    ref.listen<AppGuideState>(appGuideControllerProvider, (
      AppGuideState? before,
      AppGuideState after,
    ) {
      if ((before?.active ?? false) && !after.active) _goHome();
    });

    final AppGuideState guide = ref.watch(appGuideControllerProvider);
    final GuideAnchors anchors = ref.watch(guideAnchorsProvider);
    return Scaffold(
      backgroundColor: context.oncare.pageBackground,
      body: ProviderScope(
        overrides: _overrides,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _SampleTab(step: guide.step, anchors: anchors),
            ),
            const Positioned.fill(child: AppGuideOverlay()),
          ],
        ),
      ),
    );
  }
}

/// 예시 값으로 채운 **그 탭의 화면 그대로**. 가이드가 짚을 자리에 열쇠를 단다.
class _SampleTab extends StatelessWidget {
  const _SampleTab({required this.step, required this.anchors});

  final GuideStepId? step;
  final GuideAnchors anchors;

  @override
  Widget build(BuildContext context) {
    final GuideTab tab = step == null ? GuideTab.home : guideTabOf(step!);
    return IgnorePointer(
      child: Column(
        children: <Widget>[
          Expanded(child: _page(tab)),
          MemberBottomNav(
            selectedIndex: tab.index,
            onSelected: (_) {},
            onAdd: () {},
            addAnchorKey: anchors.quickAdd,
          ),
        ],
      ),
    );
  }

  Widget _page(GuideTab tab) => switch (tab) {
    GuideTab.home => DashboardContent(adviceAnchorKey: anchors.homeAdvice),
    GuideTab.diet => DietRecordPage(
      nutritionAnchorKey: anchors.dietNutrition,
    ),
    // 운동 탭은 `운동 기록`·`헬스장` 두 갈래다. 짚는 자리에 맞는 갈래를 펴
    // 두어야 한다 — 열쇠는 그 갈래가 그려질 때만 화면에 있다. 갈래가 바뀌면
    // 페이지를 새로 세운다(`ValueKey`).
    GuideTab.exercise => ExercisePage(
      key: ValueKey<bool>(step == GuideStepId.gym),
      initialSubTab: step == GuideStepId.gym ? 1 : 0,
      statusAnchorKey: anchors.exerciseStatus,
      gymAnchorKey: anchors.gym,
    ),
    GuideTab.my => MyHealthPage(
      settingsAnchorKey: anchors.mySettings,
      pointsAnchorKey: anchors.points,
    ),
  };
}
