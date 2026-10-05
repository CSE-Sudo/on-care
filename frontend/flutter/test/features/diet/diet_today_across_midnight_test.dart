/// 실행이 KST 자정을 걸쳐도 화면이 고른 '오늘'과 저장소의 '오늘'이 같다 (#2940).
///
/// `food_name_lookup_test` 가 자정을 걸친 CI 실행에서 깨졌다. 화면은 자정 전에
/// 오늘을 골랐는데, 가짜 저장소는 저장할 때 `nowKst()` 를 다시 읽어 다음 날을
/// 오늘로 판정했다 — 저장한 끼니가 오늘 목록에 안 보였다. 실행 고정이 걸리면
/// 두 번의 읽기가 같은 날을 본다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare_core/clock.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/kst_date_pin.dart';

String _wire(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 실행 고정의 실제 시계를 시작일 [hour]:[minute] 로 옮긴다. 반환값을 바꾸면
/// 실제 시각이 흘러간다.
_MovingSource _startAt(int hour, int minute) {
  final KstDatePin pin = runKstDatePin!;
  final DateTime start = pin.startDate;
  final _MovingSource source = _MovingSource(
    DateTime(start.year, start.month, start.day, hour, minute),
  );
  final DateTime Function() saved = pin.source;
  pin.source = source.call;
  addTearDown(() => pin.source = saved);
  return source;
}

class _MovingSource {
  _MovingSource(this.moment);

  DateTime moment;

  DateTime call() => moment;
}

const List<FoodItem> _foods = <FoodItem>[
  FoodItem(name: '닭가슴살 샐러드', calories: 320, sodiumMg: 410, proteinG: 28),
];

void main() {
  for (final int minutesAfter in <int>[0, 1, 30]) {
    test('23:59 에 고른 오늘에 저장하면 $minutesAfter분 뒤에도 오늘 목록에 있다', () async {
      final _MovingSource source = _startAt(23, 59);
      final FakeDietRepository repo = FakeDietRepository();

      // 화면이 '오늘'을 고른다 — 자정 전.
      final DateTime picked = todayKst();

      // 저장은 자정을 넘긴 뒤에 일어난다.
      source.moment = source.moment.add(Duration(minutes: 1 + minutesAfter));
      expect(source.moment.day, isNot(picked.day));

      final DietEntry saved = await repo.createEntry(
        date: _wire(picked),
        mealType: 'dinner',
        foods: _foods,
      );

      final DietDay today = await repo.fetchByDate(todayKst());
      expect(todayKst(), picked);
      expect(today.entries.map((DietEntry e) => e.id), contains(saved.id));
      expect(repo.movedEntries, isNot(contains(saved.id)));
    });
  }

  test('자정 직전에 읽은 오늘 목록과 직후에 읽은 오늘 목록이 같다', () async {
    final _MovingSource source = _startAt(23, 59);
    final FakeDietRepository repo = FakeDietRepository();

    final List<String?> before = (await repo.fetchByDate(
      todayKst(),
    )).entries.map((DietEntry e) => e.id).toList();
    source.moment = source.moment.add(const Duration(minutes: 2));
    final List<String?> after = (await repo.fetchByDate(
      todayKst(),
    )).entries.map((DietEntry e) => e.id).toList();

    expect(after, before);
    expect(after, isNotEmpty);
  });
}
