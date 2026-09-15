/// 토스트의 포인트 적립 표시(★ +50P). (#1786)
///
/// 저장 알림 옆에 받은 포인트가 붙어 한 번 톡 튀며 반짝인다. 받은 것이 없으면
/// 표시 없이 저장 알림만 뜨고, 움직임 줄이기에서는 움직이지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<BuildContext> _pump(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      // 토스트는 루트 오버레이에 그려지므로 내비게이터 바깥에서 설정을 건다.
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return captured;
}

final Finder _badge = find.byKey(const ValueKey<String>('appToastReward'));

double _badgeScale(WidgetTester tester) => tester
    .widgetList<ScaleTransition>(
      find.ancestor(of: _badge, matching: find.byType(ScaleTransition)),
    )
    .first
    .scale
    .value;

Future<void> _dismissToast(WidgetTester tester) async {
  await tester.pump(OnCareMotion.toastVisible);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('적립 글자를 주면 저장 알림 옆에 ★ 과 함께 붙어 톡 튄다', (tester) async {
    final BuildContext context = await _pump(tester);
    showAppToast(
      context,
      '식단이 저장되었어요',
      type: AppToastType.success,
      rewardLabel: '+50P',
    );
    await tester.pump(OnCareMotion.toastEnter);

    expect(find.text('식단이 저장되었어요'), findsOneWidget);
    expect(_badge, findsOneWidget);
    expect(
      find.descendant(of: _badge, matching: find.text('+50P')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _badge, matching: find.byIcon(Icons.star_rounded)),
      findsOneWidget,
    );
    // 표시는 메시지 오른쪽에 선다.
    expect(
      tester.getTopLeft(_badge).dx,
      greaterThan(tester.getTopRight(find.text('식단이 저장되었어요')).dx),
    );

    // 토스트가 내려앉은 뒤 반짝임이 시작되고, 앞부분에서 커졌다가 돌아온다.
    double peak = 1;
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final double scale = _badgeScale(tester);
      if (scale > peak) peak = scale;
    }
    expect(peak, greaterThan(1.1));
    await tester.pump(OnCareMotion.rewardSparkle);
    expect(_badgeScale(tester), 1);

    await _dismissToast(tester);
    expect(_badge, findsNothing);
  });

  testWidgets('적립 글자가 없으면 표시 없이 저장 알림만 뜬다', (tester) async {
    final BuildContext context = await _pump(tester);
    showAppToast(context, '운동이 기록됐어요', type: AppToastType.success);
    await tester.pump(OnCareMotion.toastEnter);

    expect(find.text('운동이 기록됐어요'), findsOneWidget);
    expect(_badge, findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);

    await _dismissToast(tester);
  });

  testWidgets('토스트 손잡이로 띄워도 적립 표시가 붙는다', (tester) async {
    final BuildContext context = await _pump(tester);
    AppToastHost.of(
      context,
    ).show('운동이 기록됐어요', type: AppToastType.success, rewardLabel: '+20P');
    await tester.pump(OnCareMotion.toastEnter);

    expect(
      find.descendant(of: _badge, matching: find.text('+20P')),
      findsOneWidget,
    );

    await _dismissToast(tester);
  });

  testWidgets('움직임 줄이기에서는 표시만 두고 튀지 않는다', (tester) async {
    final BuildContext context = await _pump(tester, disableAnimations: true);
    showAppToast(
      context,
      '식단이 저장되었어요',
      type: AppToastType.success,
      rewardLabel: '+50P',
    );
    await tester.pump(OnCareMotion.toastEnter);
    expect(_badge, findsOneWidget);

    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_badgeScale(tester), 1);
    }

    await _dismissToast(tester);
  });
}
