/// 실행 동안 '오늘'이 실행 시작일로 묶이는지 (#2940).
///
/// 실행이 KST 자정을 걸치면 같은 테스트 안에서 읽은 두 '오늘'이 하루 어긋났다.
/// 실제 시계를 자정 직전·직후로 옮겨 가며 고정이 걸리는지 본다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';

import '../../helpers/kst_date_pin.dart';

final DateTime _beforeMidnight = DateTime(2026, 10, 1, 23, 59, 30);
final DateTime _afterMidnight = DateTime(2026, 10, 2, 0, 0, 30);
final DateTime _nextMorning = DateTime(2026, 10, 2, 9, 15);

/// 옮겨 가며 읽히는 실제 시계 대역.
class _MovingSource {
  _MovingSource(this.moment);

  DateTime moment;

  DateTime call() => moment;
}

/// 실행 고정의 실제 시계를 [source] 로 바꾸고, 테스트가 끝나면 되돌린다.
void _driveRunPin(_MovingSource source) {
  final KstDatePin pin = runKstDatePin!;
  final DateTime Function() saved = pin.source;
  pin.source = source.call;
  addTearDown(() => pin.source = saved);
}

void main() {
  group('KstDatePin', () {
    test('시작일은 실제 시계의 날짜(0시)다', () {
      final KstDatePin pin = KstDatePin(source: () => _beforeMidnight);

      final DateTime start = pin.startDate;
      expect(<int>[start.year, start.month, start.day], <int>[2026, 10, 1]);
      expect(start.hour, 0);
    });

    test('시작일 안에서는 실제 시각을 그대로 돌려준다', () {
      final KstDatePin pin = KstDatePin(source: () => _beforeMidnight);

      expect(pin.now(), _beforeMidnight);
    });

    test('자정을 넘겨도 날짜는 시작일이고 시각은 흐른다', () {
      final _MovingSource source = _MovingSource(_beforeMidnight);
      final KstDatePin pin = KstDatePin(source: source.call);

      source.moment = _afterMidnight;
      final DateTime pinned = pin.now();

      expect(<int>[pinned.year, pinned.month, pinned.day], <int>[2026, 10, 1]);
      expect(<int>[pinned.hour, pinned.minute, pinned.second], <int>[0, 0, 30]);
    });

    test('다음 날 아침이 돼도 시각만 따라간다', () {
      final _MovingSource source = _MovingSource(_beforeMidnight);
      final KstDatePin pin = KstDatePin(source: source.call);

      source.moment = _nextMorning;

      expect(pin.now(), DateTime(2026, 10, 1, 9, 15));
    });

    test('자정 직후에 시작한 실행은 그날을 계속 쓴다', () {
      final _MovingSource source = _MovingSource(_afterMidnight);
      final KstDatePin pin = KstDatePin(source: source.call);

      source.moment = DateTime(2026, 10, 3, 0, 1);

      expect(pin.now(), DateTime(2026, 10, 2, 0, 1));
    });
  });

  group('실행 고정 (flutter_test_config)', () {
    test('모든 테스트 앞에 실행 고정이 걸려 있다', () {
      expect(runKstDatePin, isNotNull);
      expect(debugNowKstOverride, isNotNull);
      expect(todayKst(), runKstDatePin!.startDate);
    });

    test('nowKst·todayKst 가 자정 직전·직후에 같은 날을 본다', () {
      final DateTime start = runKstDatePin!.startDate;
      final _MovingSource source = _MovingSource(
        DateTime(start.year, start.month, start.day, 23, 59, 30),
      );
      _driveRunPin(source);

      final DateTime before = todayKst();
      source.moment = source.moment.add(const Duration(minutes: 1));
      final DateTime after = todayKst();

      expect(source.moment.day, isNot(start.day));
      expect(before, start);
      expect(after, start);
      expect(nowKst().hour, 0);
      expect(nowKst().minute, 0);
    });

    test('자기 시각을 넣는 테스트는 그 값이 우선한다', () {
      final DateTime fixed = DateTime(2001, 1, 2, 0, 30);
      debugNowKstOverride = () => fixed;
      addTearDown(() => debugNowKstOverride = null);

      expect(nowKst(), fixed);
      expect(todayKst(), DateTime(2001, 1, 2));
    });

    test('앞 테스트가 null 로 되돌려도 다음 테스트에는 고정이 다시 걸린다', () {
      expect(debugNowKstOverride, isNotNull);
      expect(todayKst(), runKstDatePin!.startDate);
    });
  });
}
