/// 주 이동 화살표. (#1009, #2536)
///
/// 대시보드 할 일 진행률의 주 이동과 같은 **배경 없는 브랜드색** 화살표다.
/// 두 화살표 사이는 고정 폭이고 `오늘` 은 그 안쪽 고정 자리에 앉는다 —
/// 날짜 길이나 `오늘` 표시 여부와 무관하게 화살표가 움직이지 않는다는 것이
/// 여기서 재는 계약이다(`WeekRangeNav`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_date_nav_bar.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

void main() {
  Future<void> openSchedule(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.schedule,
    );
  }

  Finder arrow(IconData icon) => find.descendant(
    of: find.byType(ScheduleDateNavBar),
    matching: find.widgetWithIcon(AppIconButton, icon),
  );

  testWidgets('화살표가 배경 없는 브랜드색 아이콘으로 그려진다 (#2536)', (tester) async {
    await openSchedule(tester);

    for (final icon in <IconData>[
      AppIcons.chevronLeft,
      AppIcons.chevronRight,
    ]) {
      final AppIconButton button = tester.widget<AppIconButton>(arrow(icon));
      expect(
        button.variant,
        AppIconButtonVariant.plain,
        reason: '대시보드 주 이동처럼 배경 상자 없이 화살표만',
      );
      expect(button.color, OnCareBrand.trainer.primary);
    }

    // 두 버튼의 크기가 같다 — 한쪽만 커 보이면 두 방향의 무게가 달라 보인다.
    expect(
      tester.getSize(arrow(AppIcons.chevronLeft)),
      tester.getSize(arrow(AppIcons.chevronRight)),
    );
  });

  testWidgets('눌러서 지난 주·다음 주로 오간다', (tester) async {
    await openSchedule(tester);
    expect(find.text('김민수'), findsWidgets); // 오늘이 보이는 주

    await tester.tap(arrow(AppIcons.chevronRight));
    await settle(tester);
    expect(find.text('김민수'), findsNothing, reason: '다음 주에는 시드가 없다');

    await tester.tap(arrow(AppIcons.chevronLeft));
    await settle(tester);
    expect(find.text('김민수'), findsWidgets);
  });

  testWidgets('`오늘` 이 생겨도 화살표가 자리를 지킨다 (#1009)', (tester) async {
    await openSchedule(tester);
    // 오늘을 보고 있으면 `오늘` 은 뜨지 않는다.
    expect(find.text('오늘'), findsNothing);
    final Rect left = tester.getRect(arrow(AppIcons.chevronLeft));
    final Rect right = tester.getRect(arrow(AppIcons.chevronRight));
    final Finder dateLabel = find.descendant(
      of: find.byType(ScheduleDateNavBar),
      matching: find.textContaining('월'),
    );
    final Rect date = tester.getRect(dateLabel);

    // 같은 주의 다른 날로 옮기면 `오늘` 이 나타난다.
    final today = todayKst();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final other = monday == today
        ? monday.add(const Duration(days: 1))
        : monday;
    await tester.tap(
      find.byKey(ValueKey<String>('schedule-day-${ymd(other)}')),
    );
    await settle(tester);
    expect(find.text('오늘'), findsOneWidget);

    // 버튼이 생겼는데도 화살표와 날짜가 그대로다 — 같은 버튼을 누르려고 매번
    // 다른 자리를 겨누게 만들지 않는다.
    expect(tester.getRect(arrow(AppIcons.chevronLeft)), left);
    expect(tester.getRect(arrow(AppIcons.chevronRight)), right);
    expect(tester.getRect(dateLabel), date);

    // 그리고 그 자리는 두 화살표 사이의 **한가운데**다. `오늘` 자리를 날짜
    // 오른쪽에만 비워 두면 날짜가 그만큼 왼쪽으로 치우친다.
    expect(
      tester.getRect(dateLabel).center.dx,
      closeTo(
        (tester.getRect(arrow(AppIcons.chevronLeft)).center.dx +
                tester.getRect(arrow(AppIcons.chevronRight)).center.dx) /
            2,
        1,
      ),
      reason: '날짜는 화살표 사이 한가운데에 선다',
    );
  });

  testWidgets('주를 넘겨 날짜 길이가 바뀌어도 화살표가 자리를 지킨다 (#2536)', (tester) async {
    await openSchedule(tester);
    final Rect left = tester.getRect(arrow(AppIcons.chevronLeft));
    final Rect right = tester.getRect(arrow(AppIcons.chevronRight));

    // 여섯 주를 넘기는 동안 날짜 문구의 길이가 여러 번 바뀐다
    // (`9월 1일 ~ 9월 7일` ↔ `9월 28일 ~ 10월 4일`). 넘기면 `오늘` 도 나타난다.
    for (var i = 0; i < 6; i++) {
      await tester.tap(arrow(AppIcons.chevronRight));
      await settle(tester);
      expect(tester.getRect(arrow(AppIcons.chevronLeft)), left);
      expect(tester.getRect(arrow(AppIcons.chevronRight)), right);
    }
  });

  testWidgets('`오늘` 이 없을 때도 날짜가 화살표 사이 한가운데다 (#1009)', (tester) async {
    await openSchedule(tester);
    expect(find.text('오늘'), findsNothing);

    final Rect left = tester.getRect(arrow(AppIcons.chevronLeft));
    final Rect right = tester.getRect(arrow(AppIcons.chevronRight));
    final Rect date = tester.getRect(
      find.descendant(
        of: find.byType(ScheduleDateNavBar),
        matching: find.textContaining('월'),
      ),
    );
    expect(date.center.dx, closeTo((left.center.dx + right.center.dx) / 2, 1));
  });

  testWidgets('좁은 폭과 큰 글자 배율에서도 날짜 행이 넘치지 않는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await openSchedule(tester, size: const Size(360, 720));

    expect(arrow(AppIcons.chevronLeft), findsOneWidget);
    expect(arrow(AppIcons.chevronRight), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
