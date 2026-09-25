/// `전체` 는 **모든 기록**을 그린다 — 고정 창(12주·35주)을 걷어냈다. (#2079)
///
/// 시작점은 첫 기록일(`GET /me/records/span`)이다. 가입일로 두면 기록을 남기기
/// 전 기간이 빈 칸으로 먼저 보이고, 고정 창으로 두면 그보다 오래된 기록이
/// 회원이 남겼는데도 그래프에서 사라진다.
///
/// 기간 집계는 `GET /diet/days?from=&to=` **한 번**이다(#2236). 하루에 한 번씩
/// 부르던 길로는 해가 바뀐 회원에게 수백 번의 왕복이 된다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

import '../../helpers/fake_diet_repository.dart';

/// 몇 번 불렸는지와 어떤 구간을 물었는지 적어 두는 대역.
class _RecordingDietRepository extends FakeDietRepository {
  final List<({DateTime? from, DateTime? to})> periodCalls =
      <({DateTime? from, DateTime? to})>[];

  @override
  Future<DietPeriod> fetchPeriod({DateTime? from, DateTime? to}) {
    periodCalls.add((from: from, to: to));
    return super.fetchPeriod(from: from, to: to);
  }
}

void main() {
  group('식단 `전체` 범위', () {
    test('첫 기록일부터 오늘까지 — 1년을 넘겨도 자른 데가 없다', () {
      final DietDateRange r = dietRangeForTab(
        DietPeriodTab.month,
        DateTime(2026, 12, 15),
        firstRecord: DateTime(2024, 5, 1),
      );

      expect(r.from, DateTime(2024, 5, 1));
      expect(r.to, DateTime(2026, 12, 15));
    });

    test('이번 주는 그대로 월~일이다 — 첫 기록일과 무관하다', () {
      final DietDateRange r = dietRangeForTab(
        DietPeriodTab.week,
        DateTime(2026, 12, 15),
        firstRecord: DateTime(2024, 5, 1),
      );

      expect(r.from, DateTime(2026, 12, 14));
      expect(r.to, DateTime(2026, 12, 20));
    });
  });

  group('식단 기간 집계', () {
    test('구간 전체를 한 번에 묻는다 — 날짜 수만큼 부르지 않는다', () async {
      final _RecordingDietRepository repo = _RecordingDietRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[dietRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(
        dietPeriodProvider((
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 30),
        )).future,
      );

      expect(repo.periodCalls, hasLength(1));
      expect(repo.periodCalls.single.from, DateTime(2026, 9, 1));
      expect(repo.periodCalls.single.to, DateTime(2026, 9, 30));
    });
  });

  group('운동 `전체` 주 수', () {
    test('첫 기록 주부터 이번 주까지 센다', () {
      // 2026-09-17(목)이 속한 주의 월요일은 9/14. 그 8주 전(7/20)에 처음 기록했다.
      expect(
        exerciseAllPeriodWeeks(DateTime(2026, 7, 22), DateTime(2026, 9, 17)),
        9,
      );
    });

    test('주 한가운데에서 시작한 기록도 그 주가 통째로 한 칸이다', () {
      expect(
        exerciseAllPeriodWeeks(DateTime(2026, 9, 10), DateTime(2026, 9, 17)),
        2,
      );
    });

    test('첫 기록일이 없으면 이번 주 하나다', () {
      expect(exerciseAllPeriodWeeks(null, DateTime(2026, 9, 17)), 1);
    });

    test('이번 주에 처음 기록했으면 이번 주 하나다', () {
      expect(
        exerciseAllPeriodWeeks(DateTime(2026, 9, 15), DateTime(2026, 9, 17)),
        1,
      );
    });
  });
}
