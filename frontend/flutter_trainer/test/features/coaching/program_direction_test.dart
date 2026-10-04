import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/coaching/domain/program_direction.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

// 목표 2000mg 기준으로 넘는 날·넘지 않는 날.
const int _over = 2600;
const int _under = 1500;

TrainerClient _client({
  List<int?> weekCompletion = const <int?>[],
  List<int> sodiumWeek = const <int>[],
}) => TrainerClient(
  id: 'm1',
  name: '김민수',
  avatar: '김',
  goal: '체중 감량',
  lastMessage: '',
  lastTime: '',
  active: true,
  calories: 1800,
  sodiumMg: 0,
  sugarG: 0,
  lastRoutine: '',
  weekCompletion: weekCompletion,
  sodiumWeek: sodiumWeek,
);

void main() {
  group('programDirectionFor (#2373)', () {
    test('완료율도 식단 기록도 없으면 판단하지 않는다', () {
      expect(programDirectionFor(_client()), ProgramDirection.noData);
      // null 은 걸린 것이 없던 날이다(#2513) — 기록이 있는 것으로 치지 않는다.
      // 0 은 걸렸는데 안 한 날이라 기록이다.
      expect(
        programDirectionFor(
          _client(
            weekCompletion: <int?>[null, null, null],
            sodiumWeek: <int>[0, 0, 0],
          ),
        ),
        ProgramDirection.noData,
      );
    });

    test('완료율이 60% 미만이면 강도를 낮춘다', () {
      expect(
        programDirectionFor(_client(weekCompletion: <int>[50, 0, 40])),
        ProgramDirection.lowerIntensity,
      );
    });

    test('60% 는 낮음이 아니다 — 주의 배지·리포트와 같은 선', () {
      expect(
        programDirectionFor(_client(weekCompletion: <int>[60])),
        ProgramDirection.keep,
      );
    });

    test('나트륨 초과가 사흘 이상이면 유산소 비중을 늘린다', () {
      expect(
        programDirectionFor(
          _client(
            weekCompletion: <int>[90],
            sodiumWeek: <int>[_over, _over, _over, _under],
          ),
        ),
        ProgramDirection.moreCardio,
      );
    });

    test('나트륨 초과 이틀은 패턴이 아니다 — 리포트 식단 주의와 같은 선', () {
      expect(
        programDirectionFor(
          _client(
            weekCompletion: <int>[90],
            sodiumWeek: <int>[_over, _over, _under, _under],
          ),
        ),
        ProgramDirection.keep,
      );
    });

    test('두 신호가 함께면 둘 다 말한다', () {
      expect(
        programDirectionFor(
          _client(
            weekCompletion: <int>[40],
            sodiumWeek: <int>[_over, _over, _over],
          ),
        ),
        ProgramDirection.lowerIntensityMoreCardio,
      );
    });

    test('식단 기록만 있어도 판단한다', () {
      expect(
        programDirectionFor(_client(sodiumWeek: <int>[_under, _under])),
        ProgramDirection.keep,
      );
    });
  });
}
