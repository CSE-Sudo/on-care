// 회원마다 다른 수의 개인운동 기간(운동 탭 `전체` 링) 데모 시드. (#2508)
//
// 백엔드 `tests/test_roster_ring_seed.py` 와 같은 날짜·같은 기대값이다 — 데모와
// 실서버가 같은 회원에게 같은 링을 그려야 해, 한쪽 표만 고치면 둘 중 하나가 깨진다.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/repositories/routine_days_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_days.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_routine_status.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';

import '../../helpers/fixed_clock.dart';

/// [kMidWeekKst](2026-08-20 목)에 회원마다 그려지는 링 수 — 백엔드
/// `EXPECTED_RINGS` 와 같은 표다.
const Map<int, int> _expectedRings = <int, int>{
  1: 0, // 김민수 — 공유 픽스처, 건드리지 않는다
  2: 0,
  3: 0,
  4: 15,
  5: 7,
  6: 4,
  7: 1, // 임도현 — 오늘 처음 보낸 한 벌(#3003)
  8: 7,
  9: 3,
  10: 1,
  11: 15,
  12: 2,
  13: 4,
  14: 15,
  15: 1,
};

void main() {
  late AppDatabase db;
  final DateTime today = DateTime(2026, 8, 20);

  setUp(() async {
    useFixedKstDate();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db);
  });
  tearDown(() => db.close());

  Future<List<RoutineGroupAdherence>> rings(int n) async =>
      routineGroupAdherence(
        await MockRoutineDaysRepository(db).fetch('seed-client-$n', to: today),
        today,
      );

  test('회원마다 받은 개인운동 기간 수가 다르다', () async {
    final Map<int, int> counts = <int, int>{
      for (final int n in _expectedRings.keys) n: (await rings(n)).length,
    };
    expect(counts, _expectedRings);
  });

  test('배준혁은 지난주 것을 목요일에 바꿨다 — 7일을 못 채운 묶음이 하나 더', () async {
    expect(
      <(DateTime, DateTime?)>[
        for (final RoutineGroupAdherence r in await rings(9))
          (r.group.activeFrom, r.group.lastDay),
      ],
      <(DateTime, DateTime?)>[
        (DateTime(2026, 8, 10), DateTime(2026, 8, 12)),
        (DateTime(2026, 8, 13), DateTime(2026, 8, 14)),
        (DateTime(2026, 8, 17), DateTime(2026, 8, 21)),
      ],
    );
  });

  test('오세라는 받을수록 링 완료율이 떨어진다', () async {
    final List<int> percents = <int>[
      for (final RoutineGroupAdherence r in await rings(8))
        if (!r.ongoing) r.percent!,
    ];
    expect(percents.first, greaterThan(percents.last));
  });

  test('최우진은 다음 주 것을 어제 보냈다 — 아직 목록에 뜨지 않는다(#2656)', () async {
    final DemoRoutineStore store = DemoRoutineStore(db);
    final List<AssignedRoutine> all = await store.assigned('seed-client-5');
    final List<AssignedRoutine> upcoming = <AssignedRoutine>[
      for (final AssignedRoutine r in all)
        if (r.date == DateTime(2026, 8, 24)) r,
    ];
    expect(upcoming, hasLength(3));
    final Map<String, DateTime> sent = await store.readSentOn('seed-client-5');
    expect(
      <DateTime?>{for (final AssignedRoutine r in upcoming) sent[r.id]},
      <DateTime>{DateTime(2026, 8, 19)},
    );
    final RoutineDays days = await MockRoutineDaysRepository(
      db,
    ).fetch('seed-client-5', to: today);
    expect(
      days.routines.map((RoutineDayRoutine r) => r.id),
      isNot(contains(upcoming.first.id)),
    );
  });
}
