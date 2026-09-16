import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/app_guide/domain/guide_sample_home.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/features/app_guide/presentation/widgets/app_guide_overlay.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/dashboard/presentation/widgets/dashboard_content.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/shared/widgets/member_bottom_nav.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 온보딩 끝에 한 번 보는 사용 가이드 — **진짜 홈 화면 위에서** 진행한다. (#1857)
///
/// 화면은 홈과 같은 위젯이다([DashboardContent] 와 [MemberBottomNav]). 비슷하게
/// 흉내 낸 화면을 따로 그리면 홈이 바뀔 때마다 안내만 옛 모습으로 남는다.
///
/// 다른 것은 **값**뿐이다. 가입 직후의 홈은 기록이 하나도 없어 빈 카드를 짚게
/// 되므로, 기록이 쌓인 모습([kGuideSampleSummary])으로 채워 그 위에서 짚는다.
/// 예시라는 것은 덮개 위쪽에 그대로 적는다.
///
/// 이 화면의 카드·버튼은 눌리지 않는다. 안내 도중 다른 화면으로 새지 않게 하려는
/// 것이고, 진짜 기능은 가이드가 끝난 뒤 홈에서 만난다.
class GuideTourPage extends ConsumerStatefulWidget {
  const GuideTourPage({super.key});

  @override
  ConsumerState<GuideTourPage> createState() => _GuideTourPageState();
}

class _GuideTourPageState extends ConsumerState<GuideTourPage> {
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

    final GuideAnchors anchors = ref.watch(guideAnchorsProvider);
    return Scaffold(
      backgroundColor: context.oncare.pageBackground,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _SampleHome(anchors: anchors)),
          const Positioned.fill(child: AppGuideOverlay()),
        ],
      ),
    );
  }
}

/// 예시 자료로 채운 **홈 화면 그대로**. 가이드가 짚을 자리에 열쇠를 단다.
class _SampleHome extends StatelessWidget {
  const _SampleHome({required this.anchors});

  final GuideAnchors anchors;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      // 이 화면 안에서만 값이 예시로 바뀐다 — 홈을 그리는 코드는 그대로다.
      //
      // 홈이 **직접 읽는** provider 만 갈아 끼운다. 그 아래 단계(저장소나
      // `exerciseWeek`)를 덮으면, 그것을 읽는 provider 가 여기 없어 바깥 값을
      // 읽으려다 Riverpod 이 막는다.
      overrides: <Override>[
        dashboardSummaryProvider.overrideWith(
          (ref) async => kGuideSampleSummary,
        ),
        exerciseWeekViewProvider.overrideWithValue(
          const AsyncData<ExerciseWeek>(kGuideSampleWeek),
        ),
        // 가입 직후에는 담당 트레이너가 없다 — 머리 오른쪽은 AI 챗봇 입구다(#1823).
        memberCoachProvider.overrideWith((ref) async => null),
        coachUnreadProvider.overrideWith((ref) async => 0),
        coachSessionsProvider.overrideWith(
          (ref) async => const <CoachSession>[],
        ),
        // 알림을 짚는 단계가 있으니 새 알림이 와 있는 모습으로 둔다.
        notificationUnreadProvider.overrideWith((ref) => Stream<int>.value(1)),
      ],
      child: IgnorePointer(
        child: Column(
          children: <Widget>[
            Expanded(
              child: DashboardContent(
                summaryAnchorKey: anchors.homeSummary,
                bellAnchorKey: anchors.alerts,
              ),
            ),
            MemberBottomNav(
              selectedIndex: 0,
              onSelected: (_) {},
              onAdd: () {},
              dietAnchorKey: anchors.diet,
              exerciseAnchorKey: anchors.exercise,
              myAnchorKey: anchors.points,
              addAnchorKey: anchors.quickAdd,
            ),
          ],
        ),
      ),
    );
  }
}
