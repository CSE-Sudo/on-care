import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원 앱 하단 내비 — 홈·식단·(+)·운동·MY. (#1742)
///
/// 셸(`MainShell`)과 사용 가이드가 **같은 위젯**을 쓴다(#1857). 가이드가 자기
/// 화면에 내비를 따로 그리면, 탭 이름이나 순서를 고칠 때 한쪽만 바뀌어 안내가
/// 실제 화면과 어긋난다.
///
/// `anchorKey` 들은 가이드가 각 칸의 자리를 재는 손잡이다. 셸은 주지 않는다.
class MemberBottomNav extends StatelessWidget {
  const MemberBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onAdd,
    this.dietAnchorKey,
    this.exerciseAnchorKey,
    this.myAnchorKey,
    this.addAnchorKey,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd;

  final GlobalKey? dietAnchorKey;
  final GlobalKey? exerciseAnchorKey;
  final GlobalKey? myAnchorKey;
  final GlobalKey? addAnchorKey;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 바 높이·라벨 아래 여백은 공용 하단 내비가 정한다. 안전영역이 0 인 웹에서도
    // 라벨 아래 여백이 남는다(#1664, #840).
    return AppBottomNav(
      selectedIndex: selectedIndex,
      onSelected: onSelected,
      destinations: <AppNavDestination>[
        AppNavDestination(
          key: const ValueKey<String>('nav-dashboard'),
          icon: AppIcons.home,
          selectedIcon: AppIcons.home,
          label: l.navDashboard,
        ),
        AppNavDestination(
          key: const ValueKey<String>('nav-diet'),
          anchorKey: dietAnchorKey,
          icon: AppIcons.diet,
          selectedIcon: AppIcons.diet,
          label: l.navDiet,
        ),
        AppNavDestination(
          key: const ValueKey<String>('nav-exercise'),
          anchorKey: exerciseAnchorKey,
          icon: AppIcons.exercise,
          selectedIcon: AppIcons.exercise,
          label: l.navExercise,
        ),
        // 운동 칸과 같이 열쇠를 준다 — 사람 아이콘은 이제 헬스장 카드의
        // 트레이너 줄에도 있어서(#1185), 아이콘만으로는 이 칸을 지목할 수 없다.
        AppNavDestination(
          key: const ValueKey<String>('nav-my'),
          anchorKey: myAnchorKey,
          icon: AppIcons.my,
          selectedIcon: AppIcons.my,
          label: l.navMyHealth,
        ),
      ],
      // 식단과 운동 사이의 `+` — "새 기록 추가" 시트를 연다. 바 위로 튀어나온
      // 원형 버튼이다(#1742).
      centerAction: KeyedSubtree(
        key: addAnchorKey,
        child: AppNavAddButton(
          key: const Key('recordAddButton'),
          // 아이콘 하나뿐이라 무엇을 여는 자리인지 툴팁이 말한다(#972).
          tooltip: l.navAddRecordTitle,
          onPressed: onAdd,
        ),
      ),
    );
  }
}
