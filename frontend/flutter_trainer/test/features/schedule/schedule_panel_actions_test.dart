/// 상세 스케줄 카드의 동작 줄. (#1012, #2178, #2231)
///
/// 일곱 개가 같은 크기·같은 모양으로 늘어서 있었다. 버튼이 많아 보이는 것이
/// 아니라 실제로 많았고, 되돌릴 수 없는 `삭제` 가 자주 쓰는 `채팅` 과 나란히
/// 서 있었다. 여기서 재는 것은 "카드에는 약속의 결말(`완료`·`취소 처리`)만
/// 글씨 버튼으로, 손보는 동작은 머리글 시각 오른쪽의 연필 버튼 하나의
/// 메뉴로" 라는 계약이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_manage_row.dart';

import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<void> openSchedule(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.schedule,
      seedClock: kMidWeekKst,
    );
  }

  Future<void> openSession(WidgetTester tester, String name) async {
    final block = find
        .descendant(
          of: find.byType(ScheduleWeekTimetable),
          matching: find.textContaining(name),
        )
        .first;
    await tester.ensureVisible(block);
    await tester.pump();
    await tester.tap(block);
    await settle(tester);
  }

  Future<void> openEditMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('session-edit-menu')));
    await settle(tester);
  }

  Finder inRow(Finder matching) =>
      find.descendant(of: find.byType(SessionManageRow), matching: matching);

  testWidgets('동작 줄의 글씨 버튼은 둘 이하다', (tester) async {
    await openSchedule(tester);
    await openSession(tester, '박성호');

    // 매 세션마다 누르는 것만 글씨를 지킨다.
    final labels = tester
        .widgetList<Text>(inRow(find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(
      labels.length,
      lessThanOrEqualTo(2),
      reason: '글씨가 셋 이상이면 다시 "버튼이 많은 줄" 이 된다: $labels',
    );
  });

  testWidgets('손보는 동작은 연필 버튼 하나의 메뉴로 묶인다 (#2178)', (tester) async {
    await openSchedule(tester);
    await openSession(tester, '박성호');

    const keys = <String, String>{
      'session-edit-schedule-chip': '일정 수정',
      'session-edit-program-chip': '프로그램 수정',
      // 박성호 세션에는 아직 메모가 없다 — 그래서 `메모 수정` 이 아니다(#1011).
      'session-edit-note-chip': '메모 추가',
      'session-delete-chip': '삭제',
    };
    // 메뉴를 열기 전에는 카드에 서 있지 않다 — 결말을 남기는 두 버튼만 있다.
    for (final key in keys.keys) {
      expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
    }
    expect(
      find.byKey(const ValueKey<String>('session-complete-chip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('session-cancel-chip')),
      findsOneWidget,
    );
    // 연필 버튼은 아이콘만 그리므로 툴팁이 이름을 말한다.
    final Tooltip tip = tester.widget<Tooltip>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('session-edit-menu')),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tip.message, '수정');

    await openEditMenu(tester);
    for (final entry in keys.entries) {
      final item = find.byKey(ValueKey<String>(entry.key));
      expect(item, findsOneWidget, reason: '${entry.value} 가 없다');
      // 메뉴 항목은 글씨로 무엇인지 말한다.
      expect(
        find.descendant(of: item, matching: find.text(entry.value)),
        findsOneWidget,
      );
    }

    // 연필 버튼을 다시 누르면 메뉴가 닫힌다.
    await openEditMenu(tester);
    expect(
      find.byKey(const ValueKey<String>('session-delete-chip')),
      findsNothing,
    );
  });

  testWidgets('삭제는 메뉴 마지막 자리에 빨간 글씨로 선다', (tester) async {
    await openSchedule(tester);
    await openSession(tester, '박성호');
    await openEditMenu(tester);

    final Finder delete = find.byKey(
      const ValueKey<String>('session-delete-chip'),
    );
    final Rect deleteRect = tester.getRect(delete);
    final Rect note = tester.getRect(
      find.byKey(const ValueKey<String>('session-edit-note-chip')),
    );
    // 되돌릴 수 없는 동작을 자주 쓰는 것 앞에 두지 않는다.
    expect(deleteRect.top, greaterThan(note.top));

    final MenuItemButton button = tester.widget<MenuItemButton>(delete);
    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{}),
      OnCareColors.danger,
      reason: '다른 동작과 같은 무게로 세우지 않는다',
    );
  });

  testWidgets('머리글 첫 줄이 상태·시각·종류를 함께 말한다', (tester) async {
    await openSchedule(tester);
    await openSession(tester, '김민수');

    final Rect status = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('week-detail')),
        matching: find.text('완료'),
      ),
    );
    final Rect name = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('week-detail')),
        matching: find.text('김민수'),
      ),
    );
    // 어떻게 됐나 · 언제 · 무엇인가가 먼저, 사람은 그 아래.
    expect(status.bottom, lessThanOrEqualTo(name.top));
    expect(
      find.descendant(
        of: find.byKey(const Key('week-detail')),
        matching: find.text('18:00\u201318:50'),
      ),
      findsOneWidget,
      reason: '시각은 자르지 않는다 — 소요 시간은 옆에 다시 적지 않는다',
    );
  });

  testWidgets('수정 버튼은 머리글 첫 줄, 시각 오른쪽에 선다 (#2231)', (tester) async {
    await openSchedule(tester);
    await openSession(tester, '박성호');

    final Finder detail = find.byKey(const Key('week-detail'));
    final Rect edit = tester.getRect(
      find.byKey(const ValueKey<String>('session-edit-menu')),
    );
    final Rect status = tester.getRect(
      find.descendant(of: detail, matching: find.byType(AppTag)).first,
    );
    final Rect name = tester.getRect(
      find.descendant(of: detail, matching: find.text('박성호')),
    );
    final Rect complete = tester.getRect(
      find.byKey(const ValueKey<String>('session-complete-chip')),
    );

    // 상태 칩과 같은 줄 — 사람 줄보다 위다.
    expect(edit.center.dy, closeTo(status.center.dy, 12));
    expect(edit.bottom, lessThanOrEqualTo(name.top));
    // 줄의 오른쪽 끝, 시각보다 오른쪽이다.
    expect(edit.left, greaterThan(status.right));
    // 결말을 남기는 버튼들은 여전히 카드 아래에 있다.
    expect(complete.top, greaterThan(name.bottom));
    // 아래 동작 줄에는 연필 버튼이 없다.
    expect(
      find.descendant(
        of: find.byType(SessionManageRow),
        matching: find.byKey(const ValueKey<String>('session-edit-menu')),
      ),
      findsNothing,
    );
  });

  testWidgets('끝난 세션은 빈 동작 줄을 남기지 않는다 (#2231)', (tester) async {
    await openSchedule(tester);
    await openSession(tester, '김민수');

    // 완료한 세션에는 `완료`·`취소 처리` 가 없다 — 수정만 머리글에 선다.
    expect(find.byType(SessionManageRow), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('session-edit-menu')),
      findsOneWidget,
    );
  });
}
