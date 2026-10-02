/// 예약 슬롯 시트의 목록 조회 실패. (#2891)
///
/// 예전에는 이유 없이 `다시 불러오기` 버튼 하나만 가운데 떠, 트레이너는 슬롯이
/// 없는 것인지 불러오지 못한 것인지 알 수 없었다. 다른 화면처럼 이유 문구와
/// 재시도를 함께 보인다.
library;


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/active_polling_stream.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';

import '../../helpers/pump_app.dart';

/// 목록 조회가 [fail] 인 동안 실패하는 슬롯 저장소.
class _FlakySlotRepository implements ReservationSlotRepository {
  bool fail = true;
  int listCalls = 0;

  @override
  Future<List<ReservationSlot>> list() async {
    listCalls++;
    if (fail) throw const NetworkError();
    return const <ReservationSlot>[];
  }

  @override
  Stream<List<ReservationSlot>> watch() =>
      activePollingStream<List<ReservationSlot>>(
        load: list,
        interval: null,
        keepPollingWhileInactive: true,
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
  void dispose() {}
}

void main() {
  late _FlakySlotRepository repo;

  Future<void> openSheet(
    WidgetTester tester, {
    Locale locale = const Locale('ko'),
  }) async {
    repo = _FlakySlotRepository();
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.schedule,
      locale: locale,
      extraOverrides: <Override>[
        reservationSlotRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.tap(find.byKey(const ValueKey<String>('schedule-open-slots')));
    await settle(tester);
  }

  testWidgets('조회 실패는 이유 문구와 재시도를 함께 보인다', (tester) async {
    await openSheet(tester);

    expect(
      find.byKey(const ValueKey<String>('slot-load-error')),
      findsOneWidget,
    );
    expect(find.text('예약 슬롯을 불러오지 못했어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('slot-load-retry')),
      findsOneWidget,
    );
    // 빈 상태와 헷갈리지 않는다.
    expect(find.text('열린 예약 슬롯이 없습니다.'), findsNothing);
  });

  testWidgets('다시 시도하면 목록을 새로 읽는다', (tester) async {
    await openSheet(tester);
    final int before = repo.listCalls;
    repo.fail = false;

    final Finder retry = find.byKey(const ValueKey<String>('slot-load-retry'));
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await settle(tester);

    expect(repo.listCalls, greaterThan(before));
    expect(find.byKey(const ValueKey<String>('slot-load-error')), findsNothing);
    expect(find.text('열린 예약 슬롯이 없습니다.'), findsOneWidget);
  });

  testWidgets('영어 화면은 영어 문구다', (tester) async {
    await openSheet(tester, locale: const Locale('en'));

    expect(find.text("Couldn't load reservation slots"), findsOneWidget);
  });
}
