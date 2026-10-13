/// 시간표와 상세 패널의 그리드 정렬. (#1008)
///
/// 날짜 행이 시간표 열 안에만 있던 때에는 왼쪽이 그 높이만큼 내려가고 오른쪽은
/// 맨 위에서 시작해, 두 열의 머리가 어긋났다. 가로로 훑을 때 눈이 한 번 더
/// 움직인다. 여기서 재는 것은 "두 열이 같은 줄에서 시작한다" 는 계약이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

void main() {
  Future<void> openSchedule(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.schedule,
    );
  }

  testWidgets('넓은 화면에서 상세 일정 제목이 시간표와 같은 높이에서 시작한다', (tester) async {
    await openSchedule(tester, const Size(1440, 1200));

    final Rect grid = tester.getRect(find.byType(ScheduleWeekTimetable));
    final Rect title = tester.getRect(find.text('상세 일정'));
    final Rect panel = tester.getRect(find.byKey(const Key('week-detail')));

    // 날짜 행 오른쪽 칸에 예약 슬롯·상담 요청이 서고, 제목은 그 아래 시간표
    // 머리와 같은 높이로 내려왔다(#2628).
    expect(title.top, closeTo(grid.top, 1.0));
    expect(
      panel.bottom,
      closeTo(grid.bottom, 1.0),
      reason: '두 열이 같은 높이에서 끝나야 한다',
    );
  });

  testWidgets('예약 슬롯이 날짜 행과 한 줄에 선다 (#2628)', (tester) async {
    await openSchedule(tester, const Size(1440, 1200));

    final Rect slots = tester.getRect(
      find.byKey(const ValueKey<String>('schedule-open-slots')),
    );
    final Rect dateRow = tester.getRect(
      find.byIcon(AppIcons.chevronLeft).first,
    );
    final Rect title = tester.getRect(find.text('상세 일정'));

    expect(slots.bottom, greaterThan(dateRow.top));
    expect(slots.top, lessThan(dateRow.bottom));
    expect(title.top, greaterThan(slots.bottom));
  });

  testWidgets('패널 제목이 페이지 제목과 다른 말을 쓴다', (tester) async {
    await openSchedule(tester, const Size(1440, 1200));

    // `스케줄` 은 페이지 제목이라, 그 자리가 무엇인지 말하지 못했다.
    expect(find.text('상세 일정'), findsOneWidget);
  });

  testWidgets('좁은 화면에서는 패널이 아래로 쌓이고 제목을 함께 지닌다', (tester) async {
    await openSchedule(tester, const Size(900, 900));

    final Rect grid = tester.getRect(find.byType(ScheduleWeekTimetable));
    final Rect panel = tester.getRect(find.byKey(const Key('week-detail')));

    expect(panel.top, greaterThan(grid.bottom - 1));
    expect(find.text('상세 일정'), findsOneWidget);
  });

  // 380 으로 못 박혀 있던 때에는 1024 창에서 요일 칸이 67 이라 회원 이름이 한
  // 글자로 잘렸다(#3316).
  testWidgets('1024 창에서는 패널이 줄어 시간표에 폭을 내준다', (tester) async {
    await openSchedule(tester, const Size(1024, 768));

    final Rect grid = tester.getRect(find.byType(ScheduleWeekTimetable));
    final Rect panel = tester.getRect(find.byKey(const Key('week-detail')));

    expect(panel.left, greaterThan(grid.right - 1), reason: '좌우로 나뉜다');
    expect(panel.width, lessThan(OnCareLayout.splitListWidth));
    expect(grid.width, greaterThan(580));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1024 창에서도 날짜 행과 새 일정이 한 줄이다', (tester) async {
    await openSchedule(tester, const Size(1024, 768));

    final Rect arrow = tester.getRect(find.byIcon(AppIcons.chevronLeft).first);
    final Rect add = tester.getRect(find.text('새 일정'));

    expect(add.center.dy, closeTo(arrow.center.dy, 12));
  });

  testWidgets('낮은 창에서 쌓이면 시간표가 화면을 쓰고 상세는 아래로 잇는다', (tester) async {
    await openSchedule(tester, const Size(900, 620));

    expect(find.byKey(const Key('schedule-stacked-scroll')), findsOneWidget);
    final Rect grid = tester.getRect(find.byType(ScheduleWeekTimetable));
    expect(grid.height, greaterThan(280));
    expect(tester.takeException(), isNull);
  });
}
