/// ① 칼로리 줄의 `지난 4주 평균` — 지난 리포트에서도 서는가. (#2453)
///
/// 지난 리포트의 칼로리 줄은 그 주 앞 4주를 평소로 삼는다. 이 파일이 지키는 것:
///  * 데모에서 오래 PT 를 받아 온 회원은 리포트 이력의 **가장 오래된 주**까지
///    기준이 선다 — 시드가 이력 창보다 짧으면 오래된 주만 `이번 주 평균` 이다.
///  * 앞선 주가 넷이 다 없어도 있는 주만으로 평균을 낸다.
///  * 앞선 주에 기록이 하나도 없을 때만 null 이다.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';

/// 최우진 — 매주 빠짐없이 적고 받는 대조군.
final TrainerClient _steady = makeClient(id: 'seed-client-5', name: '최우진');

/// 임도현 — 이번 주에 붙은 신규 회원. 기록이 없다.
final TrainerClient _newcomer = makeClient(id: 'seed-client-7', name: '임도현');

WeeklyReport _report(
  TrainerClient client,
  DateTime weekStart,
  List<int> caloriesWeek,
) => WeeklyReport(
  client: client,
  weekStart: weekStart,
  sessionsBooked: 0,
  sessionsDone: 0,
  completionAvg: 0,
  sodiumOverDays: 0,
  sodiumAvg: 0,
  isCurrentWeek: false,
  mealCounts: const <int>[0, 0, 0, 0, 0, 0, 0],
  caloriesWeek: caloriesWeek,
);

/// 기준을 읽는다 — 앞선 넷 주가 다 읽힐 때까지 기다린 뒤의 값.
Future<double?> _baseline(
  ProviderContainer container,
  TrainerClient client,
  DateTime weekStart,
) async {
  final ReportKey key = ReportKey(client: client, weekStart: weekStart);
  container.listen<double?>(calorieBaselineProvider(key), (_, _) {});
  for (int back = 1; back <= kCalorieBaselineWeeks; back++) {
    await container.read(
      weeklyReportProvider(
        ReportKey(
          client: client,
          weekStart: weekStart.subtract(Duration(days: 7 * back)),
        ),
      ).future,
    );
  }
  return container.read(calorieBaselineProvider(key));
}

void main() {
  final DateTime thisMonday = weekStartOf(kMidWeekKst);

  group('데모 저장소', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      useFixedKstDate(kMidWeekKst);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: kMidWeekKst);
      container = ProviderContainer(
        overrides: [
          reportRepositoryProvider.overrideWithValue(
            LocalReportRepository(
              DriftScheduleRepository(db),
              DriftChatRepository(db),
              db,
            ),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('오래 받아 온 회원은 리포트 이력의 가장 오래된 주에도 기준이 선다', () async {
      final DateTime oldest = thisMonday.subtract(
        const Duration(days: 7 * (demoReportHistoryWeeks - 1)),
      );

      final double? baseline = await _baseline(container, _steady, oldest);

      expect(baseline, isNotNull);
      expect(baseline, greaterThan(0));
    });

    test('리포트 이력의 지난 주마다 기준이 선다', () async {
      for (int back = 1; back < demoReportHistoryWeeks; back++) {
        final DateTime week = thisMonday.subtract(Duration(days: 7 * back));
        expect(
          await _baseline(container, _steady, week),
          isNotNull,
          reason: '$back 주 전',
        );
      }
    });

    test('앞선 주에 기록이 하나도 없는 회원은 null 이다', () async {
      expect(await _baseline(container, _newcomer, thisMonday), isNull);
    });
  });

  group('기준 계산', () {
    final DateTime week = DateTime(2026, 8, 10);

    ProviderContainer containerWith(Map<DateTime, List<int>> byWeek) =>
        ProviderContainer(
          overrides: [
            weeklyReportProvider.overrideWith(
              (ref, key) => Stream<WeeklyReport>.value(
                _report(
                  key.client,
                  key.weekStart,
                  byWeek[key.weekStart] ?? const <int>[0, 0, 0, 0, 0, 0, 0],
                ),
              ),
            ),
          ],
        );

    test('앞선 주가 하나뿐이면 그 주의 기록한 날로만 평균을 낸다', () async {
      // 회원이 붙은 지 한 주 된 주 — 넷 중 한 주만 기록이 있다.
      final ProviderContainer container = containerWith(<DateTime, List<int>>{
        week.subtract(const Duration(days: 7)): <int>[
          2000,
          0,
          1800,
          0,
          0,
          0,
          2200,
        ],
      });
      addTearDown(container.dispose);

      expect(await _baseline(container, _steady, week), 2000);
    });

    test('넷 주를 모두 기록했으면 넷 주의 기록한 날을 함께 평균한다', () async {
      final ProviderContainer container = containerWith(<DateTime, List<int>>{
        for (int back = 1; back <= kCalorieBaselineWeeks; back++)
          week.subtract(Duration(days: 7 * back)): <int>[
            1000 + back * 100,
            0,
            0,
            0,
            0,
            0,
            0,
          ],
      });
      addTearDown(container.dispose);

      // 1100·1200·1300·1400 의 평균.
      expect(await _baseline(container, _steady, week), 1250);
    });

    test('다섯 주 전 기록은 기준에 들어가지 않는다', () async {
      final ProviderContainer container = containerWith(<DateTime, List<int>>{
        week.subtract(const Duration(days: 7 * (kCalorieBaselineWeeks + 1))):
            <int>[2000, 2000, 2000, 2000, 2000, 2000, 2000],
      });
      addTearDown(container.dispose);

      expect(await _baseline(container, _steady, week), isNull);
    });

    test('앞선 넷 주 모두 기록이 없으면 null 이다', () async {
      final ProviderContainer container = containerWith(
        <DateTime, List<int>>{},
      );
      addTearDown(container.dispose);

      expect(await _baseline(container, _steady, week), isNull);
    });
  });
}
