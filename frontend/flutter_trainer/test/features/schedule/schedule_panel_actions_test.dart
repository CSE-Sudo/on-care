/// 상세 스케줄 카드의 동작 줄. (#1012)
///
/// 일곱 개가 같은 크기·같은 모양으로 늘어서 있었다. 버튼이 많아 보이는 것이
/// 아니라 실제로 많았고, 되돌릴 수 없는 `삭제` 가 자주 쓰는 `채팅` 과 나란히
/// 서 있었다. 여기서 재는 것은 "글씨는 자주 쓰는 것만, 나머지는 라벨 붙은
/// 아이콘" 이라는 계약이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_manage_row.dart';

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

  testWidgets('아이콘만 그리는 동작에도 툴팁과 시맨틱 라벨이 있다', (tester) async {
    await openSchedule(tester);
    await openSession(tester, '박성호');

    const keys = <String, String>{
      'session-edit-schedule-chip': '일정 수정',
      'session-edit-program-chip': '프로그램 수정',
      // 박성호 세션에는 아직 메모가 없다 — 그래서 `메모 수정` 이 아니다(#1011).
      'session-edit-note-chip': '메모 추가',
      'session-delete-chip': '삭제',
    };
    for (final entry in keys.entries) {
      final chip = find.byKey(ValueKey<String>(entry.key));
      expect(chip, findsOneWidget, reason: '${entry.value} 가 없다');
      // 아이콘만으로는 무엇인지 말하지 못한다.
      final Tooltip tip = tester.widget<Tooltip>(
        find.descendant(of: chip, matching: find.byType(Tooltip)).first,
      );
      expect(tip.message, entry.value);
    }
  });

  testWidgets('삭제는 마지막 자리에 채우지 않은 알약으로 선다', (tester) async {
    await openSchedule(tester);
    await openSession(tester, '박성호');

    final Rect delete = tester.getRect(
      find.byKey(const ValueKey<String>('session-delete-chip')),
    );
    final Rect note = tester.getRect(
      find.byKey(const ValueKey<String>('session-edit-note-chip')),
    );
    // 되돌릴 수 없는 동작을 자주 쓰는 것 앞에 두지 않는다.
    expect(delete.left, greaterThan(note.left));

    final Material fill = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('session-delete-chip')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(fill.color, Colors.transparent, reason: '다른 동작과 같은 무게로 채우지 않는다');
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
}
