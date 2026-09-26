import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_recurrence.dart';

import '../../helpers/pump_app.dart';

/// 반복 PT 일정 — 회차 계산, 충돌로 인한 전무(全無), 화면의 미리보기. (#870)
void main() {
  group('seriesOccurrences', () {
    // 요일 계산이 실행 날짜에 흔들리지 않도록 고정 날짜를 쓴다.
    final tuesday = DateTime(2026, 8, 18); // 화요일

    test('시작일이 고른 요일이면 그 날이 첫 회차다', () {
      final dates = seriesOccurrences(
        tuesday,
        const WeeklyRecurrence(weekdays: <int>{2}, count: 4),
      );
      expect(dates.first, tuesday);
      expect(dates.length, 4);
      expect(dates.last, DateTime(2026, 9, 8));
    });

    test('주 2회는 고른 두 요일을 번갈아 만든다', () {
      final dates = seriesOccurrences(
        tuesday,
        const WeeklyRecurrence(weekdays: <int>{1, 4}, count: 4),
      );
      expect(dates.map((d) => d.weekday).toList(), <int>[4, 1, 4, 1]);
    });

    test('종료일 기준은 그 날짜를 포함하고 넘지 않는다', () {
      final dates = seriesOccurrences(
        tuesday,
        WeeklyRecurrence(weekdays: const <int>{2}, until: DateTime(2026, 9, 8)),
      );
      // 주 단위로 더한 값과 같아야 한다 — 달을 넘어가도 요일이 유지된다.
      expect(dates, <DateTime>[
        for (var week = 0; week < 4; week++)
          tuesday.add(Duration(days: 7 * week)),
      ]);
    });

    test('요일이 없거나 종료 기준이 둘이면 아무것도 만들지 않는다', () {
      expect(
        seriesOccurrences(
          tuesday,
          const WeeklyRecurrence(weekdays: <int>{}, count: 4),
        ),
        isEmpty,
      );
      expect(
        seriesOccurrences(
          tuesday,
          WeeklyRecurrence(
            weekdays: const <int>{2},
            count: 4,
            until: DateTime(2026, 9, 8),
          ),
        ),
        isEmpty,
      );
    });

    test('먼 종료일도 상한을 넘지 않는다 — 연도 오입력을 막는다', () {
      final dates = seriesOccurrences(
        tuesday,
        WeeklyRecurrence(
          weekdays: const <int>{1, 2, 3, 4, 5},
          until: DateTime(2030, 1, 7),
        ),
      );
      expect(dates.length, maxSeriesOccurrences);
    });
  });

  group('DriftScheduleRepository 반복 생성', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });

    tearDown(() => db.close());

    /// 시드 일정과 겹치지 않는 다음 주 월요일.
    DateTime nextMonday() {
      final today = todayKst();
      return today.add(Duration(days: 8 - today.weekday));
    }

    test('한 번의 설정이 모든 회차를 만든다', () async {
      final repo = DriftScheduleRepository(db);
      final start = nextMonday();

      await repo.addRecurringSessions(
        start: start,
        time: '19:00',
        rule: WeeklyRecurrence(weekdays: <int>{start.weekday}, count: 4),
        clientName: '이지수',
        type: '1:1 PT',
        durationMinutes: 60,
      );

      final made = await repo
          .watchRange(ymd(start), ymd(start.add(const Duration(days: 28))))
          .first;
      final mine = made.where((s) => s.time == '19:00').toList();
      expect(mine.length, 4);
      expect(mine.every((s) => s.isUpcoming), isTrue);
    });

    test('겹치는 회차가 있으면 하나도 만들지 않는다', () async {
      final repo = DriftScheduleRepository(db);
      final start = nextMonday();
      // 두 번째 주에 미리 일정을 하나 둔다.
      await repo.addSession(
        date: ymd(start.add(const Duration(days: 7))),
        clientName: '박성호',
        time: '19:30',
        type: '1:1 PT',
        durationMinutes: 60,
      );

      await expectLater(
        repo.addRecurringSessions(
          start: start,
          time: '19:30',
          rule: WeeklyRecurrence(weekdays: <int>{start.weekday}, count: 4),
          clientName: '이지수',
          type: '1:1 PT',
          durationMinutes: 60,
        ),
        throwsA(isA<ScheduleSeriesConflictError>()),
      );

      final made = await repo
          .watchRange(ymd(start), ymd(start.add(const Duration(days: 28))))
          .first;
      // 겹친 것만 빼고 나머지를 만들면 트레이너는 몇 회차가 생겼는지 세어 봐야 안다.
      expect(made.where((s) => s.time == '19:30').length, 1);
    });

    test('취소된 자리는 겹침이 아니다', () async {
      final repo = DriftScheduleRepository(db);
      final start = nextMonday();
      await repo.addSession(
        date: ymd(start),
        clientName: '박성호',
        time: '19:45',
        type: '1:1 PT',
        durationMinutes: 60,
      );
      final booked = (await repo.watchDate(ymd(start)).first).firstWhere(
        (s) => s.time == '19:45',
      );
      await repo.cancelSession(booked.id, source: 'member');

      final preview = await repo.previewRecurring(
        start: start,
        time: '19:45',
        rule: WeeklyRecurrence(weekdays: <int>{start.weekday}, count: 2),
      );
      expect(preview.conflicts, isEmpty);
    });
  });

  group('일정 시트', () {
    testWidgets('반복을 켜면 만들어질 회차를 저장 전에 보여 준다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
      );

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await settle(tester);

      // 기본은 반복 없음 — 지금까지의 동작 그대로다.
      expect(
        find.byKey(const ValueKey<String>('repeat-preview')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey<String>('repeat-weekly')));
      await settle(tester);

      final preview = find.byKey(const ValueKey<String>('repeat-preview'));
      expect(preview, findsOneWidget);

      // 회차 수는 **시작~종료일 기간에서 나오는 값**이다. 여기에 숫자를 따로 적어
      // 두면 기본 종료일이 바뀔 때 이 단언만 홀로 틀린다 — 실제로 그랬다(#1647).
      // 미리보기가 말한 기간을 그대로 되짚어 견준다.
      final String summary = tester
          .widget<Text>(
            find.descendant(of: preview, matching: find.byType(Text)),
          )
          .data!;
      final RegExpMatch? shown = RegExp(
        r'(\d+).*?(\d{4}-\d{2}-\d{2}).*?(\d{4}-\d{2}-\d{2})',
      ).firstMatch(summary);
      expect(shown, isNotNull, reason: '미리보기 문구: $summary');

      final DateTime first = DateTime.parse(shown!.group(2)!);
      final DateTime last = DateTime.parse(shown.group(3)!);
      // 주 1회 반복이라 첫 회차와 마지막 회차는 같은 요일이다.
      expect(last.weekday, first.weekday);
      expect(
        int.parse(shown.group(1)!),
        last.difference(first).inDays ~/ 7 + 1,
      );

      // 다시 끄면 미리보기도 사라진다 — `매주` 는 토글이라 한 번 더 누르면
      // `반복 없음`(지금까지의 동작)으로 돌아간다.
      await tester.tap(find.byKey(const ValueKey<String>('repeat-weekly')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('repeat-preview')),
        findsNothing,
      );
    });
  });
}
