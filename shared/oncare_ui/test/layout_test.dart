import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

ThemeData _theme(OnCareDensity density) => OnCareTheme.light(
  brand: density.isWeb ? OnCareBrand.trainer : OnCareBrand.member,
  density: density,
);

void main() {
  testWidgets('모바일 페이지·탭 헤더·하단 내비가 그려진다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(OnCareDensity.mobile),
        home: Scaffold(
          body: AppPage(
            header: AppTabHeader(
              title: 'On-Care',
              actions: <Widget>[
                AppIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: '알림',
                  onPressed: () {},
                  variant: AppIconButtonVariant.tonal,
                ),
              ],
            ),
            children: const <Widget>[AppCard(child: Text('카드'))],
          ),
          bottomNavigationBar: AppBottomNav(
            destinations: const <AppNavDestination>[
              AppNavDestination(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: '홈',
              ),
              AppNavDestination(
                icon: Icons.restaurant_outlined,
                selectedIcon: Icons.restaurant_rounded,
                label: '식단',
              ),
              AppNavDestination(
                icon: Icons.fitness_center_outlined,
                selectedIcon: Icons.fitness_center_rounded,
                label: '운동',
              ),
              AppNavDestination(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'MY',
              ),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // 안전영역이 0 이어도 라벨 아래 최소 여백이 남는다(#1664).
    expect(
      tester.getSize(find.byType(AppBottomNav)).height,
      AppBottomNav.barHeight + AppBottomNav.minBottomPadding,
    );
  });

  testWidgets('가운데 + 버튼은 바 위로 튀어나온 56 원형이다(#1742)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            destinations: const <AppNavDestination>[
              AppNavDestination(
                icon: Icons.home_rounded,
                selectedIcon: Icons.home_rounded,
                label: '홈',
              ),
              AppNavDestination(
                icon: Icons.person_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'MY',
              ),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
            centerAction: AppNavAddButton(tooltip: '기록 추가', onPressed: () {}),
          ),
        ),
      ),
    );
    final Rect nav = tester.getRect(find.byType(AppBottomNav));
    final Rect add = tester.getRect(find.byType(AppNavAddButton));
    expect(add.size, const Size.square(AppBottomNav.centerActionSize));
    expect(
      nav.height,
      AppBottomNav.centerActionLift +
          AppBottomNav.barHeight +
          AppBottomNav.minBottomPadding,
    );
    // 버튼 윗부분이 흰 바 윗선보다 위에 있다.
    expect(
      add.top,
      lessThan(
        nav.bottom - AppBottomNav.barHeight - AppBottomNav.minBottomPadding,
      ),
    );
  });

  testWidgets('웹 분할 레이아웃은 목록 380 + 간격 16 이다', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(OnCareDensity.web),
        home: const Scaffold(
          body: AppWebPage(
            title: '고객',
            subtitle: '담당 회원',
            body: AppSplitView(
              list: ColoredBox(key: Key('list'), color: Colors.white),
              detail: ColoredBox(key: Key('detail'), color: Colors.white),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('list'))).width, 380);
    expect(
      tester.getTopLeft(find.byKey(const Key('detail'))).dx -
          tester.getTopRight(find.byKey(const Key('list'))).dx,
      16,
    );
  });

  testWidgets('사이드바 항목 높이는 44 다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(OnCareDensity.web),
        home: Scaffold(
          body: AppSidebarItem(
            icon: Icons.dashboard_rounded,
            label: '대시보드',
            selected: true,
            onTap: () {},
            badgeCount: 3,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppSidebarItem)).height, 44);
  });
}
