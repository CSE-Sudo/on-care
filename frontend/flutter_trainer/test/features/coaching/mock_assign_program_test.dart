// 데모 저장소의 `개인운동만` 전송 (#2224).
//
// 데모에는 받을 회원 백엔드가 없지만, 보낸 것이 배정 목록에 남아야 한다.
// 아무것도 하지 않던 동안에는 화면이 `보냈어요` 라고 말해 놓고 전송 이력이
// 그대로여서, 같은 탭의 PT 등록(실제로 반영됨)과 두 경로가 다르게 움직였다.
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';

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
}
