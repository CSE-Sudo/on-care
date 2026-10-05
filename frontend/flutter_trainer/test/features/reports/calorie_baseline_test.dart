/// ① 칼로리 줄의 `지난 4주 평균` — 지난 리포트에서도 서는가. (#2453, #2863)
///
/// 지난 리포트의 칼로리 줄은 그 주 앞 4주를 평소로 삼는다. 이 파일이 지키는 것:
///  * 데모에서 오래 PT 를 받아 온 회원은 리포트 이력의 **가장 오래된 주**까지
///    기준이 선다 — 시드가 이력 창보다 짧으면 오래된 주만 `이번 주 평균` 이다.
///  * 앞선 주가 넷이 다 없어도 있는 주만으로 평균을 낸다.
///  * 앞선 주에 기록이 하나도 없을 때만 null 이다.
///  * 기준은 그 주 리포트가 싣고 온다 — 직전 4주 리포트를 다시 읽지 않는다
///    (#2863). 값은 예전처럼 직전 4주 리포트의 칼로리로 낸 평균과 같다.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
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

/// 시드 없는 DB 에 손으로 기록을 넣는 회원.
final TrainerClient _manual = makeClient(id: 'baseline-client', name: '기준회원');

LocalReportRepository _localRepository(AppDatabase db) => LocalReportRepository(
  DriftScheduleRepository(db),
  DriftChatRepository(db),
  db,
);

/// 기준을 읽는다 — 그 주 리포트가 도착한 뒤의 값.
Future<double?> _baseline(
  ProviderContainer container,
  TrainerClient client,
  DateTime weekStart,
) async {
  final ReportKey key = ReportKey(client: client, weekStart: weekStart);
  container.listen<double?>(calorieBaselineProvider(key), (_, _) {});
  await container.read(weeklyReportProvider(key).future);
  return container.read(calorieBaselineProvider(key));
}

/// 예전 화면의 계산 — 직전 4주 리포트의 칼로리 중 기록한 날의 평균.
Future<double?> _legacyBaseline(
  ReportRepository repository,
  TrainerClient client,
  DateTime weekStart,
) async {
  final List<int> recorded = <int>[];
  for (int back = 1; back <= kCalorieBaselineWeeks; back++) {
    final WeeklyReport past = await repository
        .watch(client: client, weekStart: shiftWeeks(weekStart, -back))
        .first;
    recorded.addAll(past.caloriesWeek.where((int kcal) => kcal > 0));
  }
  if (recorded.isEmpty) return null;
  return recorded.fold<int>(0, (int a, int b) => a + b) / recorded.length;
}

void main() {
  final DateTime thisMonday = weekStartOf(kMidWeekKst);

  group('데모 저장소 — 시드', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      useFixedKstDate(kMidWeekKst);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: kMidWeekKst);
      container = ProviderContainer(
        overrides: [
          reportRepositoryProvider.overrideWithValue(_localRepository(db)),
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

    test('리포트가 싣고 온 기준은 직전 4주 리포트로 낸 예전 평균과 같다 (#2863)', () async {
      final LocalReportRepository repository = _localRepository(db);
      for (int back = 0; back < demoReportHistoryWeeks; back++) {
        final DateTime week = shiftWeeks(thisMonday, -back);
        final WeeklyReport report = await repository
            .watch(client: _steady, weekStart: week)
            .first;
        expect(
          report.calorieBaseline,
          await _legacyBaseline(repository, _steady, week),
          reason: '$back 주 전',
        );
      }
    });
  });

  group('데모 저장소 — 기준 계산', () {
    late AppDatabase db;
    final DateTime week = DateTime(2026, 8, 10);

    setUp(() {
      useFixedKstDate(kMidWeekKst);
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    Future<void> record(DateTime day, int kcal) => db
        .into(db.clientDailyMetrics)
        .insert(
          ClientDailyMetricsCompanion.insert(
            clientId: _manual.id,
            date: ymd(day),
            calories: Value<int>(kcal),
          ),
        );

    Future<double?> baselineOf(DateTime weekStart) async =>
        (await _localRepository(
          db,
        ).watch(client: _manual, weekStart: weekStart).first).calorieBaseline;

    test('앞선 주가 하나뿐이면 그 주의 기록한 날로만 평균을 낸다', () async {
      final DateTime prev = shiftWeeks(week, -1);
      await record(prev, 2000);
      await record(DateTime(prev.year, prev.month, prev.day + 2), 1800);
      await record(DateTime(prev.year, prev.month, prev.day + 6), 2200);
      // 0kcal 인 날은 기록하지 않은 날이다 — 평균을 끌어내리지 않는다.
      await record(DateTime(prev.year, prev.month, prev.day + 3), 0);

      expect(await baselineOf(week), 2000);
    });

    test('넷 주를 모두 기록했으면 넷 주의 기록한 날을 함께 평균한다', () async {
      for (int back = 1; back <= kCalorieBaselineWeeks; back++) {
        await record(shiftWeeks(week, -back), 1000 + back * 100);
      }

      // 1100·1200·1300·1400 의 평균.
      expect(await baselineOf(week), 1250);
    });

    test('그 주와 다섯 주 전 기록은 기준에 들어가지 않는다', () async {
      // 그 주 자신 — 기준은 "평소" 라 이번 주를 섞지 않는다.
      await record(week, 3000);
      // 직전 4주의 첫날 하루 앞 — 다섯 주 전 일요일.
      await record(
        DateTime(
          week.year,
          week.month,
          week.day - 7 * kCalorieBaselineWeeks - 1,
        ),
        2000,
      );

      expect(await baselineOf(week), isNull);
    });

    test('직전 4주의 첫날·마지막 날은 기준에 들어간다', () async {
      await record(
        DateTime(week.year, week.month, week.day - 7 * kCalorieBaselineWeeks),
        1000,
      );
      await record(DateTime(week.year, week.month, week.day - 1), 3000);

      expect(await baselineOf(week), 2000);
    });

    test('서머타임이 시작한 주를 건너도 직전 28일을 그대로 센다 (#2774)', () async {
      // 2026-03-08(일) 은 미국 서머타임이 시작한 날이다. `Duration` 으로 빼면
      // 시간대에 따라 하루가 어긋난다 — 날짜는 연·월·일로 센다.
      final DateTime afterDst = DateTime(2026, 3, 23);
      await record(DateTime(2026, 2, 23), 1000); // 직전 4주의 첫날
      await record(DateTime(2026, 3, 8), 2000); // 서머타임 시작일
      await record(DateTime(2026, 3, 22), 3000); // 직전 4주의 마지막 날
      await record(DateTime(2026, 2, 22), 9000); // 하루 앞 — 빠져야 한다

      expect(await baselineOf(afterDst), 2000);
    });

    test('앞선 넷 주 모두 기록이 없으면 null 이다', () async {
      expect(await baselineOf(week), isNull);
    });
  });

  group('provider (#2863)', () {
    final DateTime week = DateTime(2026, 8, 10);

    test('그 주 리포트 하나만 읽는다 — 직전 4주 리포트를 다시 부르지 않는다', () async {
      final List<DateTime> asked = <DateTime>[];
      final ProviderContainer container = ProviderContainer(
        overrides: [
          weeklyReportProvider.overrideWith((ref, key) {
            asked.add(key.weekStart);
            return Stream<WeeklyReport>.value(
              buildWeeklyReport(
                client: key.client,
                sessions: const [],
                weekStart: key.weekStart,
                calorieBaseline: 1875,
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(await _baseline(container, _steady, week), 1875);
      expect(asked, <DateTime>[week]);
    });

    test('리포트에 기준이 없으면 null 이다', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          weeklyReportProvider.overrideWith(
            (ref, key) => Stream<WeeklyReport>.value(
              buildWeeklyReport(
                client: key.client,
                sessions: const [],
                weekStart: key.weekStart,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await _baseline(container, _steady, week), isNull);
    });

    test('리포트가 아직 오지 않았으면 null 이다', () {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          weeklyReportProvider.overrideWith(
            (ref, key) => const Stream<WeeklyReport>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(
          calorieBaselineProvider(ReportKey(client: _steady, weekStart: week)),
        ),
        isNull,
      );
    });
  });
}
