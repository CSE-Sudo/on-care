/// 시간표와 상세 패널의 그리드 정렬. (#1008)
///
/// 날짜 행이 시간표 열 안에만 있던 때에는 왼쪽이 그 높이만큼 내려가고 오른쪽은
/// 맨 위에서 시작해, 두 열의 머리가 어긋났다. 가로로 훑을 때 눈이 한 번 더
/// 움직인다. 여기서 재는 것은 "두 열이 같은 줄에서 시작한다" 는 계약이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';

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

  testWidgets('넓은 화면에서 시간표와 상세 패널이 같은 줄에서 시작한다', (tester) async {
    await openSchedule(tester, const Size(1440, 1200));

    final Rect grid = tester.getRect(find.byType(ScheduleWeekTimetable));
    final Rect panel = tester.getRect(find.byKey(const Key('week-detail')));

    expect(
      panel.top,
      closeTo(grid.top, 1.0),
      reason: '두 열의 몸이 같은 높이에서 시작해야 한다',
    );
    expect(
      panel.bottom,
      closeTo(grid.bottom, 1.0),
      reason: '두 열이 같은 높이에서 끝나야 한다',
    );
  });

  testWidgets('패널 머리글이 날짜 행과 한 줄에 선다', (tester) async {
    await openSchedule(tester, const Size(1440, 1200));

    final Rect title = tester.getRect(find.text('상세 일정'));
    final Rect dateRow = tester.getRect(
      find.byIcon(Icons.chevron_left_rounded).first,
    );

    // 같은 `Row` 에 있으므로 세로로 겹친다 — 어느 한쪽 높이를 상수로 베끼면
    // 그 값이 바뀌는 순간 조용히 어긋난다.
    expect(title.bottom, greaterThan(dateRow.top));
    expect(title.top, lessThan(dateRow.bottom));
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
}
