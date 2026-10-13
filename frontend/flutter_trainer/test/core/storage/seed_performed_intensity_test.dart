/// 처방과 다른 강도로 한 개인운동이 데모 시드에 하루 있다. (#3263)
///
/// #3249 로 트레이너 화면은 회원이 처방과 다르게 한 날 줄에 `수행 높음` 같은
/// 태그를 붙인다. 시드의 수행 강도가 모두 처방과 같으면 시연에서 그 태그를 보일
/// 날이 없다. 이지수(seed-client-2)의 스쿼트(처방 보통)를 그 운동을 한 가장 최근
/// 지난 날 `high` 로 남긴다 — 백엔드 `seed_workouts.PERFORMED_OFF` 와 같은 날·같은
/// 강도다.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';

import '../../helpers/fixed_clock.dart';

const String _jisu = 'seed-client-2';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed(DateTime now) async {
    useFixedKstDate(now);
    await seedIfEmpty(db, clock: now);
  }

  /// 그날 하루 운동 기록의 개인운동 줄.
  Future<List<Map<String, Object?>>> personalRows(String date) async {
    final ClientDailyMetricRow row =
        await (db.select(db.clientDailyMetrics)
              ..where((t) => t.clientId.equals(_jisu) & t.date.equals(date)))
            .getSingle();
    return <Map<String, Object?>>[
      for (final Object? e in jsonDecode(row.exercisesJson) as List<Object?>)
        if (e is Map<String, Object?> && e['source'] == 'assigned_routine') e,
    ];
  }

  /// 그날 `개인운동` 카드의 한 줄들.
  Future<List<Map<String, Object?>>> cardLines(String date) async {
    final ClientRoutineHistoryRow row = await (db.select(
      db.clientRoutineHistory,
    )..where((t) => t.id.equals('seed-personal-2-$date'))).getSingle();
    return <Map<String, Object?>>[
      for (final Object? e in jsonDecode(row.exercisesJson) as List<Object?>)
        e! as Map<String, Object?>,
    ];
  }

  Map<String, Object?> squat(List<Map<String, Object?>> rows) =>
      rows.firstWhere((Map<String, Object?> e) => e['name'] == '스쿼트');

  test('목요일이면 어제(수) 스쿼트를 처방(보통)보다 세게 했다', () async {
    await seed(kMidWeekKst); // 2026-08-20(목)

    final Map<String, Object?> line = squat(await cardLines('2026-08-19'));
    expect(line['intensity'], 'high');
    expect(line['prescribed_intensity'], 'moderate');
    expect(squat(await personalRows('2026-08-19'))['intensity'], 'high');
  });

  test('처방과 다르게 한 것은 그날 그 운동 하나뿐이다', () async {
    await seed(kMidWeekKst);

    // 같은 날 다른 개인운동은 처방 그대로다.
    for (final Map<String, Object?> e in await cardLines('2026-08-19')) {
      if (e['name'] == '스쿼트') continue;
      expect(e['intensity'], e['prescribed_intensity'], reason: '${e['name']}');
    }
    // 그 전날의 스쿼트도 처방 그대로다.
    final Map<String, Object?> before = squat(await cardLines('2026-08-18'));
    expect(before['intensity'], 'moderate');
    expect(before['prescribed_intensity'], 'moderate');
    expect(squat(await personalRows('2026-08-18'))['intensity'], 'moderate');
  });

  test('월요일이면 개인운동을 쉰 주말을 건너 지난 금요일이다', () async {
    final DateTime monday = DateTime(2026, 8, 17, 10);
    await seed(monday);

    expect(squat(await cardLines('2026-08-14'))['intensity'], 'high');
    expect(squat(await cardLines('2026-08-13'))['intensity'], 'moderate');
  });

  test('오늘은 회원이 직접 체크하는 날이라 들지 않는다', () async {
    await seed(kMidWeekKst);

    final String today = ymd(kMidWeekKst);
    final ClientRoutineHistoryRow? card = await (db.select(
      db.clientRoutineHistory,
    )..where((t) => t.id.equals('seed-personal-2-$today'))).getSingleOrNull();
    expect(card, isNull);
  });
}
