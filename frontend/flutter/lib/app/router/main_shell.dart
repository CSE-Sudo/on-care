import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_invite_prompter.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/coaching_sheet.dart';
import 'package:oncare/shared/widgets/member_bottom_nav.dart';
import 'package:oncare/shared/widgets/oni_fab.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Persistent `Scaffold` hosting the bottom navigation bar. Icons and
/// labels mirror the original React `BottomNav.tsx` (Home / 식단 /
/// 운동 / My).
/// AI 조언 플로팅 버튼을 회원 화면에 띄울지. (#862)
///
/// **기능을 지우지 않고 노출만 끈 상태다.** AI 조언 화면·라우트(`/ai-coach`)·
/// 시트(`showCoachingSheet`)·배지(`coachingBadgeCountProvider`)는 모두 그대로고,
/// 홈의 `AI 조언` 배너가 같은 시트를 여는 진입점으로 남아 있다.
///
/// 이 기능의 최종 위치와 역할이 정해지면 값을 `true` 로 되돌리는 것으로 복원된다.
/// 지우지 않고 상수 하나로 둔 까닭이 그것이다 — 방향이 바뀌었을 때 다시 만드는
/// 비용을 치르지 않기 위해서다. 설정 화면이나 feature flag 체계를 새로 들이지도
/// 않는다: 지금 필요한 것은 "잠시 감춘다" 하나뿐이다.
const bool kShowCoachingFab = false;

class MainShell extends ConsumerStatefulWidget {
  const MainShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  late int _lastIndex = widget.navigationShell.currentIndex;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int nextIndex = navigationShell.currentIndex;
    if (_lastIndex == nextIndex) return;
    _lastIndex = nextIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshBranch(nextIndex);
      _resetTransientUiState(nextIndex);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshMemberData();
  }

  void _refreshMemberData() {
    ref.invalidate(dashboardSummaryProvider);
    // 홈의 AI 추천 식단도 함께 되짚는다. 무효화되는 곳이 세션 초기화 하나뿐이라,
    // 앱을 켠 순간의 추천이 하루 종일 고정되고 첫 조회가 실패하면 기본 추천이
    // 앱 수명 내내 남았다(#1938).
    ref.invalidate(dietRecommendationsProvider);
    ref.invalidate(exerciseWeekProvider);
    ref.invalidate(coachRoutinesProvider);
    ref.invalidate(coachSessionsProvider);
  }

  void _refreshBranch(int index) {
    switch (index) {
      case 0:
        ref.invalidate(dashboardSummaryProvider);
        ref.invalidate(dietRecommendationsProvider);
        ref.invalidate(coachSessionsProvider);
        break;
      case 1:
        // 방금 저장한 끼니가 보이도록 그날 자료를 다시 읽는다 — 저장 전 캐시가
        // 남아 있으면 옮겨 온 탭이 빈 화면을 보여 준다(#1434).
        ref.invalidate(dietTodayProvider);
        ref.invalidate(dietByDateProvider(nowKst()));
        break;
      case 2:
        ref.invalidate(exerciseWeekProvider);
        ref.invalidate(coachRoutinesProvider);
        ref.invalidate(coachSessionsProvider);
        break;
      default:
        break;
    }
  }

  /// 하단 탭을 다시 들어올 때 임시 UI 상태만 기본값으로 되돌린다(#861). 실제
  /// 기록·서버 데이터·설정·트레이너 프로그램은 각 탭의 provider 가 따로 들고
  /// 있어 여기서 건드리지 않는다 — 탭마다 무엇을 되돌릴지는 그 탭의 페이지가
  /// 정의한 `resetXxxTransientUiState` 가 안다.
  void _resetTransientUiState(int index) {
    switch (index) {
      // 0(홈)도 일부러 아무 것도 하지 않는다. 예전에는 식단·영양 카드에서 고른
      // 지표(칼로리/나트륨/당류)를 기본값으로 되돌렸는데, 그래프가 칼로리
      // 하나로 고정된 뒤로는(#1879) 홈에 되돌릴 임시 선택이 없다.
      case 1:
        resetDietTransientUiState(ref);
        break;
      case 2:
        resetExerciseTransientUiState(ref);
        break;
      // 3(MY)은 일부러 아무 것도 하지 않는다 — MY 탭은 펼침/접힘·임시 선택·
      // 일회성 필터 같은 화면 전용 위젯 상태(`StatefulWidget`/`setState`)를
      // 두지 않는다(`my_health_page.dart` 점검 결과, #861). 보이는 값은 전부
      // `myHealthStateProvider` 가 들고 있는 실제 저장 데이터라 초기화 대상이
      // 아니다.
      default:
        break;
    }
  }

  /// 미읽음 알림 수가 늘면 내 상담 요청을 다시 받는다(#2067).
  ///
  /// 트레이너의 승인·거절과 요청 만료는 알림으로 먼저 온다. 상담 목록은 처음 한
  /// 번만 받아 와서, 이걸 듣지 않으면 알림은 "반려되었어요" 인데 화면은 "확인
  /// 대기" 로 남고 그 옛 표시가 같은 트레이너에게 다시 신청하는 것까지 막는다.
  /// 첫 값과 줄어들 때(읽음 처리)는 건너뛴다 — 새로 온 것이 없다.
  ///
  /// 상담 컨트롤러 provider 안이 아니라 여기서 듣는 이유: 세션 초기화
  /// (`session_feature_reset.dart`)가 두 provider 를 함께 무효화하는데, 한쪽이
  /// 다른 쪽을 들으면 riverpod 의존 검사에 걸린다.
  void _onUnreadChanged(AsyncValue<int>? previous, AsyncValue<int> next) {
    final int? before = previous?.valueOrNull;
    final int? after = next.valueOrNull;
    if (before == null || after == null || after <= before) return;
    unawaited(
      ref.read(consultationRequestControllerProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<int>>(notificationUnreadProvider, _onUnreadChanged);
    return Scaffold(
      // 페이지가 하단 바 뒤까지 이어지게 둔다 — 각 탭은 바 높이만큼 아래 여백을
      // 스스로 둔다.
      extendBody: true,
      // 받은 담당 요청은 어느 탭에 있든 가운데 창으로 뜬다(#1801). 탭 전체를
      // 감싸 두어 탭을 옮겨도 요청을 듣는 일이 끊기지 않는다.
      body: CoachInvitePrompter(child: navigationShell),
      // AI 조언 진입점이 이 자리에 있을지가 아직 정해지지 않아 **노출만** 끈다
      // (#862). 기능·라우트·provider 는 그대로라, 자리가 정해지면 이 상수를
      // 되돌리는 것으로 복원된다 — 아래 [kShowCoachingFab] 주석 참고.
      floatingActionButton: kShowCoachingFab
          ? OniFab(
              key: const Key('coachingFab'),
              // 배지는 시트가 실제로 보여 줄 카드 수를 따른다. 열어서 확인하면
              // 내려간다.
              badgeCount: ref.watch(coachingBadgeCountProvider),
              onTap: () => showCoachingSheet(context, ref: ref),
            )
          : null,
      // 하단 내비는 사용 가이드 화면과 **같은 위젯**이다(#1857) — 탭 이름·순서를
      // 고칠 때 한쪽만 바뀌지 않는다.
      bottomNavigationBar: MemberBottomNav(
        selectedIndex: navigationShell.currentIndex,
        onSelected: _onTap,
        onAdd: () => _showRecordAddSheet(context, onSaved: _goToRecordBranch),
      ),
    );
  }

  /// 방금 저장한 기록의 탭으로 옮긴다. (#1434)
  ///
  /// 이미 그 탭이면 아무것도 하지 않는다 — 다시 `goBranch` 하면 그 탭에서
  /// 추가한 사용자의 스크롤·선택 상태가 초기화된다.
  void _goToRecordBranch(int index) {
    if (!mounted) return;
    if (navigationShell.currentIndex == index) {
      // 그 자리에서 적었어도 방금 저장한 것이 보여야 한다 — 화면 상태는 두고
      // 데이터만 새로 읽는다.
      _refreshBranch(index);
      return;
    }
    _onTap(index);
  }

  void _onTap(int index) {
    // 다른 탭에서 넘어올 때만 "재진입"이다 — 이미 보고 있는 탭을 다시 누른
    // 것뿐이면 사용자가 탭을 떠난 적이 없으므로 임시 UI 상태를 그대로 둔다.
    final bool isReentry = index != navigationShell.currentIndex;
    _lastIndex = index;
    _refreshBranch(index);
    if (isReentry) _resetTransientUiState(index);
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// "새 기록 추가" chooser opened by the bottom-nav + button. Routes to the diet
/// or exercise add flow. Mirrors the Figma add sheet.
///
/// 저장에 성공하면 [onSaved] 를 그 기록의 탭 index 로 부른다 — 홈이나 MY 에서
/// 적고 나면 방금 저장한 것을 보러 사용자가 탭을 다시 찾아가야 했다(#1434).
/// 취소·권한 거부·분석 실패에서는 부르지 않는다.
///
/// 셸의 context 로 띄우므로 시트는 셸 바깥(루트) 내비게이터에 올라가, 하단 바와
/// `+` 버튼이 시트 위로 올라오지 않는다(#791).
Future<void> _showRecordAddSheet(
  BuildContext context, {
  required ValueChanged<int> onSaved,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (BuildContext ctx) => _RecordAddSheet(
      onDiet: () async {
        Navigator.of(ctx).pop();
        if (await showDietAddSheet(context)) onSaved(_dietBranch);
      },
      onExercise: () async {
        Navigator.of(ctx).pop();
        if (await showExerciseAddSheet(context)) onSaved(_exerciseBranch);
      },
    ),
  );
}

/// 하단 탭의 브랜치 index. 저장한 기록을 보러 갈 곳이라 이름을 준다.
const int _dietBranch = 1;
const int _exerciseBranch = 2;

class _RecordAddSheet extends StatelessWidget {
  const _RecordAddSheet({required this.onDiet, required this.onExercise});

  final VoidCallback onDiet;
  final VoidCallback onExercise;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppSheet(
      key: const Key('recordAddSheet'),
      title: l.navAddRecordTitle,
      subtitle: l.navAddRecordSubtitle,
      // 시트는 화면 끝까지 내려오므로, 홈 인디케이터가 있는 기기에서는 그만큼을
      // 더 띄워야 카드가 가리지 않는다(#1154). 인셋이 없으면 시트 안쪽 여백만 남는다.
      child: SafeArea(
        top: false,
        child: Row(
          key: const Key('recordOptions'),
          children: <Widget>[
            // 두 갈래 모두 브랜드 파랑이다 (#1154). 이 시트는 "무엇을 기록할까" 를
            // 고르는 자리라 색이 영역을 가르는 뜻으로 읽히지 않는다.
            Expanded(
              child: _RecordOption(
                icon: AppIcons.diet,
                title: l.navDiet,
                subtitle: l.navDietOptionSub,
                onTap: onDiet,
              ),
            ),
            const SizedBox(width: OnCareSpacing.cardGap),
            Expanded(
              child: _RecordOption(
                icon: AppIcons.exercise,
                title: l.navExercise,
                subtitle: l.navExerciseOptionSub,
                onTap: onExercise,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordOption extends StatelessWidget {
  const _RecordOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s12,
        vertical: OnCareSpacing.s20,
      ),
      child: Column(
        children: <Widget>[
          // 아이콘 배경은 두지 않는다 — 안쪽 여백만 남겨 칸 크기를 지킨다(#1781).
          Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s12),
            child: AppIcon(
              icon,
              size: OnCareSize.iconLarge,
              color: tokens.brand.primary,
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: tokens
                .text(OnCareTypography.titleSmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
