// 데모 저장소의 `개인운동만` 전송 (#2224).
//
// 데모에는 받을 회원 백엔드가 없지만, 보낸 것이 배정 목록에 남아야 한다.
// 아무것도 하지 않던 동안에는 화면이 `보냈어요` 라고 말해 놓고 전송 이력이
// 그대로여서, 같은 탭의 PT 등록(실제로 반영됨)과 두 경로가 다르게 움직였다.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';

/// `개인운동만` 본문 — 버피 45초(유산소)와 플랭크 3세트 60초(근력). (#2755)
///
/// 트레이너 웹이 `routineOnlyAssignToJson` 으로 만드는 모양 그대로다: 분은 초를
/// 반올림한 값이고 초가 `duration_seconds` 에 함께 실린다.
Map<String, Object?> _secondsPayload() => <String, Object?>{
  'name': '이번 주 개인운동',
  'delivery_kind': 'routine_only',
  'start_date': '2026-09-30',
  'active_days': 7,
  'sessions': <Object?>[
    <String, Object?>{
      'id': 'routine-only-0',
      'name': '버피',
      'exercises': <Object?>[
        <String, Object?>{
          'id': 'personal-0',
          'name': '버피',
          'type': '유산소',
          'duration': 1,
          'duration_seconds': 45,
          'source': 'ai',
        },
      ],
    },
    <String, Object?>{
      'id': 'routine-only-1',
      'name': '플랭크',
      'exercises': <Object?>[
        <String, Object?>{
          'id': 'personal-1',
          'name': '플랭크',
          'type': '근력',
          'duration': 0,
          'duration_seconds': null,
          'sets': 3,
          'reps': 0,
          'hold_seconds': 60,
          'source': 'trainer',
        },
      ],
    },
  ],
};

void main() {
  test('보낸 개인운동이 배정 목록 맨 앞에 남는다', () async {
    final repo = MockTrainerRoutineRepository();
    const memberId = 'seed-client-1';
    final before = await repo.watchAssignedRoutines(memberId).first;

    await repo.assignProgram(memberId, <String, Object?>{
      'name': '개인운동',
      'start_date': '2026-08-24',
      'sessions': <Object?>[
        <String, Object?>{
          'id': 's1',
          'name': '',
          'exercises': <Object?>[
            <String, Object?>{
              'id': 'e1',
              'name': '실내 자전거',
              'type': '유산소',
              'duration': 20,
              'source': 'trainer',
            },
          ],
        },
      ],
    });

    final after = await repo.watchAssignedRoutines(memberId).first;
    expect(after.length, before.length + 1);
    expect(after.first.name, '실내 자전거');
    expect(after.first.type, '유산소');
    expect(after.first.minutes, 20);
    expect(after.first.date, DateTime.parse('2026-08-24'));
  });

  test('개인운동만 을 다시 보내면 이전에 보낸 것만 내려간다 (#2514)', () async {
    final repo = MockTrainerRoutineRepository();
    const memberId = 'seed-client-1';
    final seeded = await repo.watchAssignedRoutines(memberId).first;

    Map<String, Object?> send(String name) => <String, Object?>{
      'name': '개인운동',
      'delivery_kind': 'routine_only',
      'active_days': 7,
      'sessions': <Object?>[
        <String, Object?>{
          'id': 's1',
          'name': '',
          'exercises': <Object?>[
            <String, Object?>{'id': 'e1', 'name': name, 'duration': 20},
          ],
        },
      ],
    };

    await repo.assignProgram(memberId, send('지난주 걷기'));
    await repo.assignProgram(memberId, send('이번 주 걷기'));

    final after = await repo.watchAssignedRoutines(memberId).first;
    final List<String> names = <String>[for (final r in after) r.name];
    expect(names.first, '이번 주 걷기');
    expect(names, isNot(contains('지난주 걷기')));
    // 씨앗 배정은 기한 없는 배정이라 그대로 남는다.
    expect(after.length, seeded.length + 1);
  });

  test('운동이 없으면 목록을 건드리지 않는다', () async {
    final repo = MockTrainerRoutineRepository();
    const memberId = 'seed-client-1';
    final before = await repo.watchAssignedRoutines(memberId).first;
    await repo.assignProgram(memberId, <String, Object?>{
      'sessions': <Object?>[],
    });
    final after = await repo.watchAssignedRoutines(memberId).first;
    expect(after.length, before.length);
  });

  group('초 단위 운동 시간 (#2755)', () {
    test('유산소 45초는 분으로 접히지 않고 초로 남는다', () async {
      final repo = MockTrainerRoutineRepository();
      await repo.assignProgram('m-2755', _secondsPayload());

      final rows = await repo.watchAssignedRoutines('m-2755').first;
      final burpee = rows.firstWhere((r) => r.name == '버피');
      expect(burpee.durationSeconds, 45);
      expect(burpee.seconds, 45);
      expect(burpee.minutes, 1);
    });

    test('근력은 초를 비우고 세트·버티기로 남는다', () async {
      final repo = MockTrainerRoutineRepository();
      await repo.assignProgram('m-2755', _secondsPayload());

      final rows = await repo.watchAssignedRoutines('m-2755').first;
      final plank = rows.firstWhere((r) => r.name == '플랭크');
      expect(plank.durationSeconds, isNull);
      expect(plank.sets, 3);
      expect(plank.holdSeconds, 60);
    });

    test('직전 전송도 초를 들고 있다 — 이력 카드가 45초로 읽는다', () async {
      final repo = MockTrainerRoutineRepository();
      await repo.assignProgram('m-2755', _secondsPayload());

      final delivery = await repo.fetchLatestDelivery('m-2755');
      expect(delivery, isNotNull);
      final burpee = delivery!.routines.firstWhere((r) => r.name == '버피');
      expect(burpee.durationSeconds, 45);
    });

    test('데모 DB 에 남긴 배정과 직전 전송이 다시 열어도 초를 유지한다', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await MockTrainerRoutineRepository(
        db: db,
      ).assignProgram('m-2755', _secondsPayload());

      // 새로고침 — 같은 DB 를 새 저장소가 읽는다.
      final reopened = MockTrainerRoutineRepository(db: db);
      final rows = await reopened.watchAssignedRoutines('m-2755').first;
      expect(rows.firstWhere((r) => r.name == '버피').durationSeconds, 45);
      expect(rows.firstWhere((r) => r.name == '플랭크').durationSeconds, isNull);

      final delivery = await reopened.fetchLatestDelivery('m-2755');
      expect(
        delivery!.routines.firstWhere((r) => r.name == '버피').durationSeconds,
        45,
      );
    });
  });
}
