import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 회원 앱을 대신하는 슬롯 저장소 — 콘솔 밖에서 자리가 채워지는 상황을
/// [publish] 로 만든다(#1590).
class _ExternalSlotRepository implements ReservationSlotRepository {
  _ExternalSlotRepository(this._slots);

  List<ReservationSlot> _slots;
  final StreamController<void> _revisions = StreamController<void>.broadcast();

  /// 목록을 몇 번 읽었는가 — 모달을 다시 열 때 새로 읽는지 보는 자리다.
  int listCalls = 0;

  /// 회원 앱이 예약(또는 취소)해 서버 목록이 바뀐 상황.
  void publish(List<ReservationSlot> next) {
    _slots = next;
    _revisions.add(null);
  }

  @override
  Future<List<ReservationSlot>> list() async {
    listCalls += 1;
    return _slots;
  }

  @override
  Stream<List<ReservationSlot>> watch() =>
      activePollingStream<List<ReservationSlot>>(
        load: list,
        interval: null,
        refreshes: _revisions.stream,
      );

  @override
  Future<ReservationSlot> create({
    required DateTime startsAt,
    int durationMinutes = 60,
    required String sessionType,
  }) => throw UnimplementedError();

  @override
  Future<ReservationSlot> update(
    String id, {
    DateTime? startsAt,
    int? durationMinutes,
    String? sessionType,
  }) => throw UnimplementedError();

  @override
  Future<ReservationSlot> close(String id) => throw UnimplementedError();

  @override
  void dispose() => unawaited(_revisions.close());
}

ReservationSlot _slot({required bool booked, String? bookedByName}) {
  final DateTime today = todayKst();
  return ReservationSlot(
    id: 'slot-1',
    startsAt: DateTime(today.year, today.month, today.day, 14),
    booked: booked,
    isClosed: false,
    sessionType: SessionType.personalTraining,
    bookedByName: bookedByName,
  );
}

void main() {
  group('ReservationSlotsSheet', () {
    Future<void> openSheet(
      WidgetTester tester, {
      List<Override> extraOverrides = const <Override>[],
    }) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        extraOverrides: extraOverrides,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('schedule-open-slots')),
      );
      await settle(tester);
    }

    testWidgets('opens on the currently selected day by default', (
      tester,
    ) async {
      await openSheet(tester);

      final today = todayKst();
      expect(
        find.text('${today.month}월 ${today.day}일'),
        findsWidgets, // 안내 문구와 날짜 버튼 둘 다 같은 표기를 쓴다.
      );
    });

    testWidgets('날짜 버튼을 누르면 과거로는 못 가는 날짜 선택창이 뜬다 (#1090)', (tester) async {
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey<String>('slot-date')));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('시간 범위는 한 필드에 보이고 시 선택 뒤 단계 화살표가 나타난다', (tester) async {
      await openSheet(tester);

      expect(find.textContaining('10:00 – 11:00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('slot-time-range')));
      await settle(tester);

      expect(
        find.byKey(const ValueKey<String>('session-time-range-start-input')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-time-range-end-input')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('time-range-back')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey<String>('clock-value-10')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('time-range-back')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('time-range-next')),
        findsOneWidget,
      );
    });

    testWidgets('회원이 잡아 간 자리가 열려 있는 목록에 바로 반영된다 (#1590)', (tester) async {
      final repository = _ExternalSlotRepository(<ReservationSlot>[
        _slot(booked: false),
      ]);
      addTearDown(repository.dispose);
      await openSheet(
        tester,
        extraOverrides: <Override>[
          reservationSlotRepositoryProvider.overrideWithValue(repository),
        ],
      );

      // 아직 비어 있는 자리 — 지울 수 있고 예약자 이름은 없다. 뒤에 깔린
      // 스케줄 화면에도 삭제 아이콘이 있으므로 그 줄 안에서만 찾는다.
      final Finder deleteInRow = find.descendant(
        of: find.byKey(const ValueKey<String>('slot-row-slot-1')),
        matching: find.byIcon(Icons.delete_outline_rounded),
      );
      expect(deleteInRow, findsOneWidget);
      expect(find.text('김하늘'), findsNothing);

      // 회원 앱에서 이 시간을 예약했다. 트레이너는 아무것도 누르지 않는다.
      repository.publish(<ReservationSlot>[
        _slot(booked: true, bookedByName: '김하늘'),
      ]);
      await settle(tester);

      expect(find.text('김하늘'), findsOneWidget);
      expect(deleteInRow, findsNothing);
    });

    testWidgets('모달을 다시 열면 목록을 새로 읽는다 (#1590)', (tester) async {
      final repository = _ExternalSlotRepository(<ReservationSlot>[
        _slot(booked: false),
      ]);
      addTearDown(repository.dispose);
      await openSheet(
        tester,
        extraOverrides: <Override>[
          reservationSlotRepositoryProvider.overrideWithValue(repository),
        ],
      );
      expect(repository.listCalls, 1);

      // 닫혀 있는 동안 회원이 예약한다 — 캐시를 그대로 쓰면 다시 열어도
      // 빈 자리로 보인다.
      await tester.tap(find.byType(AppCloseButton));
      await settle(tester);
      repository.publish(<ReservationSlot>[
        _slot(booked: true, bookedByName: '김하늘'),
      ]);

      await tester.tap(
        find.byKey(const ValueKey<String>('schedule-open-slots')),
      );
      await settle(tester);

      expect(repository.listCalls, greaterThan(1));
      expect(find.text('김하늘'), findsOneWidget);
    });

    testWidgets('포인트 체험 허용을 켜면 종류는 포인트 체험, 시간은 20분으로 고정된다 (#1790)', (
      tester,
    ) async {
      await openSheet(tester);
      expect(find.textContaining('10:00 – 11:00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('slot-points-trial')));
      await settle(tester);

      expect(find.textContaining('10:00 – 10:20'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('slot-session-type')),
          matching: find.text('포인트 체험'),
        ),
        findsOneWidget,
      );
      expect(find.text('포인트 체험 허용'), findsOneWidget);

      // 다시 끄면 고른 종류로 돌아간다.
      await tester.tap(find.byKey(const ValueKey<String>('slot-points-trial')));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('slot-session-type')),
          matching: find.text('1:1 PT'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('체험 자리는 목록에 포인트 체험 태그와 20분으로 보인다 (#1790)', (tester) async {
      final DateTime today = todayKst();
      final repository = _ExternalSlotRepository(<ReservationSlot>[
        ReservationSlot(
          id: 'slot-trial',
          startsAt: DateTime(today.year, today.month, today.day, 15),
          durationMinutes: SessionType.pointsTrialMinutes,
          booked: false,
          isClosed: false,
          sessionType: SessionType.pointsTrial,
        ),
      ]);
      addTearDown(repository.dispose);
      await openSheet(
        tester,
        extraOverrides: <Override>[
          reservationSlotRepositoryProvider.overrideWithValue(repository),
        ],
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('slot-type-slot-trial')),
          matching: find.text('포인트 체험'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('15:00 – 15:20'), findsOneWidget);
    });
  });

  group('MockReservationSlotRepository 포인트 체험 (#1790)', () {
    test('체험 자리는 보낸 시간과 상관없이 20분이고, 끄면 기본 시간으로 돌아간다', () async {
      final repository = MockReservationSlotRepository();
      addTearDown(repository.dispose);
      final DateTime startsAt = nowKst().add(const Duration(days: 1));

      final ReservationSlot slot = await repository.create(
        startsAt: startsAt,
        durationMinutes: 45,
        sessionType: SessionType.pointsTrial,
      );
      expect(slot.isPointsTrial, isTrue);
      expect(slot.durationMinutes, SessionType.pointsTrialMinutes);

      final ReservationSlot kept = await repository.update(
        slot.id,
        durationMinutes: 45,
      );
      expect(kept.durationMinutes, SessionType.pointsTrialMinutes);

      final ReservationSlot regular = await repository.update(
        slot.id,
        sessionType: SessionType.personalTraining,
      );
      expect(regular.isPointsTrial, isFalse);
      expect(regular.durationMinutes, 60);
    });
  });
}
