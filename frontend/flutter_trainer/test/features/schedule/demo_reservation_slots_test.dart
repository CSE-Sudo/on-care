import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/data/demo_reservation_slots.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

import '../../helpers/pump_app.dart';

/// 목업 데모의 예약 자리 — 회원 앱 목업(`trainer-kim`)과 같은 자리다.
void main() {
  // 월요일 아침. 요일마다 데모 스케줄이 달라 일곱 요일을 모두 돌린다.
  final DateTime monday = DateTime(2026, 9, 28, 6);

  group('demoReservationSlots', () {
    test('id 가 겹치지 않고, 여러 날에 걸쳐 두 종류와 예약된 자리가 섞인다', () {
      final List<ReservationSlot> slots = demoReservationSlots(now: monday);

      expect(slots.map((s) => s.id).toSet(), hasLength(slots.length));
      // 날짜별 묶음(#2182)이 보이려면 여러 날이어야 한다.
      expect(slots.map((s) => ymd(s.startsAt)).toSet().length, greaterThan(3));
      expect(slots.map((s) => s.sessionType).toSet(), <String>{
        SessionType.personalTraining,
        SessionType.consultation,
      });
      expect(slots.where((s) => s.booked), isNotEmpty);
      expect(slots.where((s) => !s.booked), isNotEmpty);
      expect(slots.every((s) => !s.isClosed), isTrue);
    });

    test('모든 자리가 오늘 이후에 있다 — 지난 날 자리는 만들지 않는다', () {
      final DateTime today = DateTime(monday.year, monday.month, monday.day);
      for (final ReservationSlot slot in demoReservationSlots(now: monday)) {
        expect(slot.startsAt.isBefore(today), isFalse, reason: slot.id);
      }
    });

    test('자리끼리 시간이 겹치지 않는다', () {
      final List<ReservationSlot> slots = demoReservationSlots(now: monday)
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      for (int i = 1; i < slots.length; i++) {
        final DateTime prevEnd = slots[i - 1].startsAt.add(
          Duration(minutes: slots[i - 1].durationMinutes),
        );
        expect(
          slots[i].startsAt.isBefore(prevEnd),
          isFalse,
          reason: '${slots[i - 1].id} 와 ${slots[i].id}',
        );
      }
    });

    for (int offset = 0; offset < 7; offset++) {
      final DateTime now = monday.add(Duration(days: offset));
      test('데모 스케줄과 시간이 겹치지 않는다 (요일 ${now.weekday})', () async {
        final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await seedIfEmpty(db, clock: now);
        final rows = await db.select(db.trainerScheduleEntries).get();

        for (final ReservationSlot slot in demoReservationSlots(now: now)) {
          final DateTime slotEnd = slot.startsAt.add(
            Duration(minutes: slot.durationMinutes),
          );
          for (final row in rows) {
            if (row.status == ScheduleStatus.gap) continue;
            if (row.date != ymd(slot.startsAt)) continue;
            final List<String> hm = row.time.split(':');
            final DateTime start = DateTime(
              slot.startsAt.year,
              slot.startsAt.month,
              slot.startsAt.day,
              int.parse(hm[0]),
              int.parse(hm[1]),
            );
            final DateTime end = start.add(
              Duration(minutes: row.durationMinutes),
            );
            expect(
              start.isBefore(slotEnd) && slot.startsAt.isBefore(end),
              isFalse,
              reason: '${slot.id} 가 ${row.date} ${row.time} 일정과 겹침',
            );
          }
        }
      });
    }
  });

  test('목업 저장소는 넣어 준 자리로 시작하고, 기본은 빈 목록이다', () async {
    expect(await MockReservationSlotRepository().list(), isEmpty);

    final DateTime now = nowKst();
    final List<ReservationSlot> seeded = await MockReservationSlotRepository(
      seed: demoReservationSlots(now: now),
    ).list();
    // 지난 자리(오늘 저녁 자리를 밤에 열었을 때 등)는 목록에서 빠진다.
    expect(
      seeded.map((s) => s.id),
      demoReservationSlots(
        now: now,
      ).where((s) => s.startsAt.isAfter(now)).map((s) => s.id),
    );
  });

  testWidgets('데모 앱의 예약 슬롯 창에 미리 열어 둔 자리가 보인다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.schedule,
    );
    await tester.tap(find.byKey(const ValueKey<String>('schedule-open-slots')));
    await settle(tester);

    // 내일 이후 자리는 실행 시각과 상관없이 늘 앞으로의 자리다.
    for (final String id in <String>[
      'slot-kim-1',
      'slot-kim-2',
      'slot-kim-3',
    ]) {
      expect(
        find.byKey(ValueKey<String>('slot-row-$id')),
        findsOneWidget,
        reason: id,
      );
    }
  });

  group('상담 대기 신청이 잡은 자리 (#2797)', () {
    final DateTime now = DateTime(2026, 9, 28, 6);
    ReservationSlot slotOf(String id) =>
        demoReservationSlots(now: now).firstWhere((s) => s.id == id);

    test('시드 요청은 모두 데모 상담 자리를 고르고, 그 자리는 빈 상담 자리와 다르다', () {
      for (final MapEntry<String, ({String requestId, String memberName})> e
          in demoPendingRequestSlots.entries) {
        expect(slotOf(e.key).sessionType, SessionType.consultation);
      }
      // 회원 앱 데모 사용자가 신청해 볼 빈 상담 자리가 남는다.
      expect(
        demoReservationSlots(now: now).where(
          (s) =>
              s.sessionType == SessionType.consultation &&
              !demoPendingRequestSlots.containsKey(s.id),
        ),
        isNotEmpty,
      );
    });

    test('결정 전에는 신청자 이름으로 예약된 자리다', () {
      final ReservationSlot held = holdDemoRequestSlot(
        slotOf('slot-kim-6'),
        const <String, String>{},
      );
      expect(held.booked, isTrue);
      expect(held.bookedByName, '김하늘');
    });

    test('거절·수락으로 결정되면 신청이 자리를 놓는다', () {
      for (final String status in <String>['rejected', 'accepted']) {
        final ReservationSlot slot = holdDemoRequestSlot(
          slotOf('slot-kim-7'),
          <String, String>{'demo-consultation-2': status},
        );
        // 수락한 신청의 자리는 그 시각의 상담 일정이 잡는다([judgeDemoSlot]).
        expect(slot.booked, isFalse, reason: status);
      }
    });

    test('신청이 고르지 않은 자리는 그대로다', () {
      final ReservationSlot slot = slotOf('slot-kim-3');
      expect(
        holdDemoRequestSlot(slot, const <String, String>{}).booked,
        slot.booked,
      );
    });
  });
}
