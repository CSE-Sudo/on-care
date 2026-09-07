import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';

void main() {
  test(
    'v12 to v17 adds the daily macro·완료 날짜 columns and preserves rows',
    () async {
      // v3~v5 에서 올라오는 경로는 v7 의 `createTable` 이 **현재 정의**로 표를
      // 만들어 버려, `from >= 7 && from < 13` 갈래를 지나가지 않는다. 이미
      // v12 인 DB 를 직접 세워야 그 갈래가 검증된다(리뷰 #952).
      final executor = NativeDatabase.memory(
        setup: (database) {
          database.execute('''
          CREATE TABLE client_daily_metrics (
            client_id TEXT NOT NULL,
            date TEXT NOT NULL,
            completion INTEGER NOT NULL DEFAULT 0,
            calories INTEGER NOT NULL DEFAULT 0,
            sodium_mg INTEGER NOT NULL DEFAULT 0,
            sugar_g REAL NOT NULL DEFAULT 0,
            exercises_json TEXT NOT NULL DEFAULT '[]',
            PRIMARY KEY (client_id, date)
          )
        ''');
          database.execute('''
          INSERT INTO client_daily_metrics
            (client_id, date, completion, calories, sodium_mg, sugar_g,
             exercises_json)
          VALUES ('seed-client-1', '2026-08-18', 80, 1800, 2100, 17.8, '["걷기"]')
        ''');
          // 이 테이블도 v1 부터 있었다. 스냅샷이 빼먹으면 v14 의 `completed_at`
          // 추가가 없는 표를 고치려다 죽는다(#1114).
          database.execute('''
            CREATE TABLE client_routine_history (
              id TEXT NOT NULL PRIMARY KEY,
              client_id TEXT NOT NULL,
              date_label TEXT NOT NULL,
              label TEXT NOT NULL,
              completion_rate INTEGER NOT NULL,
              exercises_json TEXT NOT NULL,
              client_feedback TEXT NOT NULL DEFAULT '',
              trainer_note TEXT NOT NULL DEFAULT '',
              sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          database.execute('''
            INSERT INTO client_routine_history (
              id, client_id, date_label, label, completion_rate, exercises_json,
              client_feedback, trainer_note, sort_order
            ) VALUES (
              'old-history', 'existing-client', '7/9', 'AI 루틴 · 자율 운동', 80,
              '["\\uc2a4\\ucffc\\ud2b8 3\\uc138\\ud2b8"]', '', '', 0
            )
          ''');
          // 실제 DB 에는 이 표가 v1 부터 있다. v16 가 여기에 컬럼을
          // 붙이므로(#1025), 표가 없는 인공 DB 로는 그 갈래를 지날 수 없다.
          database.execute('''
          CREATE TABLE client_diet_entries (
            id TEXT NOT NULL,
            client_id TEXT NOT NULL,
            meal TEXT NOT NULL,
            items TEXT NOT NULL,
            calories INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            carbs_g REAL NOT NULL DEFAULT 0,
            protein_g REAL NOT NULL DEFAULT 0,
            fat_g REAL NOT NULL DEFAULT 0,
            photo_asset TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (id)
          )
          ''');
          // 이 표도 v1 부터 있었다. v17 이 여기에 성별·나이 컬럼을 붙이므로
          // (신규 회원 등록), 표가 없는 인공 DB 로는 그 갈래를 지날 수 없다.
          database.execute('''
          CREATE TABLE trainer_clients (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            avatar TEXT NOT NULL,
            goal TEXT NOT NULL,
            last_message TEXT NOT NULL,
            last_time TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
            calories_today INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sugar_g REAL NOT NULL,
            carbs_g REAL NOT NULL DEFAULT 0,
            protein_g REAL NOT NULL DEFAULT 0,
            fat_g REAL NOT NULL DEFAULT 0,
            last_routine TEXT NOT NULL,
            week_completion_json TEXT NOT NULL,
            sodium_week_json TEXT NOT NULL DEFAULT '[]',
            calories_week_json TEXT NOT NULL DEFAULT '[]',
            sugar_week_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
          ''');
          database.execute('PRAGMA user_version = 12');
        },
      );
      final db = AppDatabase.forTesting(executor);
      addTearDown(db.close);

      final row = await db.select(db.clientDailyMetrics).getSingle();
      final version = await db.customSelect('PRAGMA user_version').getSingle();

      expect(version.read<int>('user_version'), 17);
      // 있던 값은 그대로 남는다.
      expect(row.clientId, 'seed-client-1');
      expect(row.date, '2026-08-18');
      expect(row.calories, 1800);
      expect(row.sodiumMg, 2100);
      expect(row.sugarG, 17.8);
      expect(row.exercisesJson, '["걷기"]');
      // 새 컬럼은 기본값 0 — 다음 재시딩이 실제 값을 채운다. 0 이면 화면이
      // 쌓지 않고 한 색으로 그리므로 재시딩 전에도 그림이 깨지지 않는다.
      expect(row.carbsG, 0);
      expect(row.proteinG, 0);
      expect(row.fatG, 0);
    },
  );

  test(
    'v3 to v17 adds macro·주간 계열·취소·완료 날짜 columns and preserves rows',
    () async {
      final executor = NativeDatabase.memory(
        setup: (database) {
          database.execute('''
          CREATE TABLE trainer_clients (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            avatar TEXT NOT NULL,
            goal TEXT NOT NULL,
            last_message TEXT NOT NULL,
            last_time TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
            calories_today INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sugar_g INTEGER NOT NULL,
            last_routine TEXT NOT NULL,
            week_completion_json TEXT NOT NULL,
            sodium_week_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
          database.execute('''
          CREATE TABLE client_diet_entries (
            id TEXT NOT NULL PRIMARY KEY,
            client_id TEXT NOT NULL,
            meal TEXT NOT NULL,
            items TEXT NOT NULL,
            calories INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
          database.execute('''
          INSERT INTO trainer_clients (
            id, name, avatar, goal, last_message, last_time, active,
            calories_today, sodium_mg, sugar_g, last_routine,
            week_completion_json, sodium_week_json, sort_order
          ) VALUES (
            'existing-client', '기존 회원', '기', '건강 관리', '', '-', 1,
            500, 700, 12, '어제', '[100,0,0,0,0,0,0]', '[700]', 1
          )
        ''');
          database.execute('''
          INSERT INTO client_diet_entries (
            id, client_id, meal, items, calories, sodium_mg, sort_order
          ) VALUES (
            'existing-meal', 'existing-client', '아침', '기존 식단', 500, 700, 0
          )
        ''');
          // 이 테이블은 v1 부터 있었다. 스냅샷이 빼먹으면 그 위에서 도는
          // 마이그레이션이 실제 DB 와 다른 것을 보게 된다(#822).
          database.execute('''
          CREATE TABLE trainer_schedule_entries (
            id TEXT NOT NULL PRIMARY KEY,
            date TEXT NOT NULL,
            time TEXT NOT NULL,
            client_id TEXT,
            client_name TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT '',
            duration_minutes INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            program_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
          // 이 테이블도 v1 부터 있었다. 스냅샷이 빼먹으면 v14 의 `completed_at`
          // 추가가 없는 표를 고치려다 죽는다(#1114).
          database.execute('''
          CREATE TABLE client_routine_history (
            id TEXT NOT NULL PRIMARY KEY,
            client_id TEXT NOT NULL,
            date_label TEXT NOT NULL,
            label TEXT NOT NULL,
            completion_rate INTEGER NOT NULL,
            exercises_json TEXT NOT NULL,
            client_feedback TEXT NOT NULL DEFAULT '',
            trainer_note TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
          database.execute('''
          INSERT INTO client_routine_history (
            id, client_id, date_label, label, completion_rate, exercises_json,
            client_feedback, trainer_note, sort_order
          ) VALUES (
            'old-history', 'existing-client', '7/9', 'AI 루틴 · 자율 운동', 80,
            '["\\uc2a4\\ucffc\\ud2b8 3\\uc138\\ud2b8"]', '', '', 0
          )
        ''');
          database.execute('PRAGMA user_version = 3');
        },
      );
      final db = AppDatabase.forTesting(executor);
      addTearDown(db.close);

      final client = await db.select(db.trainerClients).getSingle();
      final meal = await db.select(db.clientDietEntries).getSingle();
      final version = await db.customSelect('PRAGMA user_version').getSingle();

      expect(version.read<int>('user_version'), 17);
      expect(client.id, 'existing-client');
      expect(client.caloriesToday, 500);
      expect(client.sugarG, 12.0);
      expect(client.carbsG, 0);
      // 새 주간 계열은 기본값으로 들어와 다음 재시딩이 실제 값을 채운다(#746).
      expect(client.caloriesWeekJson, '[]');
      expect(client.sugarWeekJson, '[]');
      expect(client.proteinG, 0);
      expect(client.fatG, 0);
      // v17 의 성별·나이는 회원 ID로 새로 연결되는 회원만 채운다(신규 회원
      // 등록). 예전 행은 값 없이 그대로 남고, 표시는 예전처럼 roster 폴백을
      // 쓴다.
      expect(client.gender, isNull);
      expect(client.age, isNull);
      expect(meal.id, 'existing-meal');
      expect(meal.items, '기존 식단');
      expect(meal.carbsG, 0);
      expect(meal.proteinG, 0);
      expect(meal.fatG, 0);
      // v11 은 리포트 피드백 초안 표를 새로 만든다(#821). 예전 DB 에는 없던
      // 표라, 만들어지지 않으면 초안 저장이 첫 조회에서 죽는다.
      expect(await db.select(db.reportFeedbackDrafts).get(), isEmpty);
      // v12 는 일정에 취소·노쇼 기록 칸을 붙인다(#906). 붙지 않으면 취소를
      // 누르는 순간 없는 컬럼에 쓰다가 죽는다. 예전 행은 값이 없는 것이 정상이고,
      // 그 자체가 "취소가 아님" 이라는 뜻이다.
      final schedule = await db.select(db.trainerScheduleEntries).get();
      expect(schedule, isEmpty);
      await db
          .into(db.trainerScheduleEntries)
          .insert(
            TrainerScheduleEntriesCompanion.insert(
              id: 'migrated-session',
              date: '2026-08-19',
              time: '10:00',
              status: '취소',
              cancelledAt: Value(DateTime(2026, 8, 19, 9)),
              cancellationSource: const Value('member'),
              cancellationReason: const Value('회원 사정'),
            ),
          );
      final stored = await db.select(db.trainerScheduleEntries).getSingle();
      expect(stored.cancellationSource, 'member');
      expect(stored.cancellationReason, '회원 사정');
      expect(stored.cancelledAt, isNotNull);
      expect(stored.noShowAt, isNull);
      // v14 는 운동 기록에 완료 날짜 칸을 붙인다(#1114). 예전 행은 날짜가 없는
      // 것이 정상이고 — 화면은 그런 기록을 기간과 무관하게 늘 보여 준다 —
      // 새로 쓰는 행부터 실제 날짜가 남는다.
      final history = await db.select(db.clientRoutineHistory).getSingle();
      expect(history.id, 'old-history');
      expect(history.dateLabel, '7/9');
      expect(history.completionRate, 80);
      expect(history.completedAt, isNull);
      await db
          .into(db.clientRoutineHistory)
          .insert(
            ClientRoutineHistoryCompanion.insert(
              id: 'dated-history',
              clientId: 'existing-client',
              dateLabel: '8/19 (오늘)',
              label: 'PT 세션 · 트레이너 지도',
              completionRate: 90,
              exercisesJson: '[]',
              completedAt: Value(DateTime(2026, 8, 19, 18, 30)),
            ),
          );
      final dated = await (db.select(
        db.clientRoutineHistory,
      )..where((t) => t.id.equals('dated-history'))).getSingle();
      expect(dated.completedAt, DateTime(2026, 8, 19, 18, 30));
    },
  );

  test('v4 to v17 preserves integer sugar and all client rows', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        database.execute('''
          CREATE TABLE trainer_clients (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            avatar TEXT NOT NULL,
            goal TEXT NOT NULL,
            last_message TEXT NOT NULL,
            last_time TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
            calories_today INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sugar_g INTEGER NOT NULL,
            carbs_g REAL NOT NULL DEFAULT 0,
            protein_g REAL NOT NULL DEFAULT 0,
            fat_g REAL NOT NULL DEFAULT 0,
            last_routine TEXT NOT NULL,
            week_completion_json TEXT NOT NULL,
            sodium_week_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        database.execute('''
          INSERT INTO trainer_clients (
            id, name, avatar, goal, last_message, last_time, active,
            calories_today, sodium_mg, sugar_g, carbs_g, protein_g, fat_g,
            last_routine, week_completion_json, sodium_week_json, sort_order
          ) VALUES
            ('client-a', '기존 회원 A', 'A', '혈압 관리', '보존 메시지', '방금', 1,
             500, 700, 12, 40.5, 20, 10, '어제', '[100]', '[700]', 1),
            ('client-b', '기존 회원 B', 'B', '체중 감량', '다른 메시지', '1시간 전', 0,
             900, 1200, 61, 80, 35.5, 22, '3일 전', '[50]', '[1200]', 2)
        ''');
        // 이 테이블은 v1 부터 있었다. 스냅샷이 빼먹으면 그 위에서 도는
        // 마이그레이션이 실제 DB 와 다른 것을 보게 된다(#822).
        database.execute('''
          CREATE TABLE trainer_schedule_entries (
            id TEXT NOT NULL PRIMARY KEY,
            date TEXT NOT NULL,
            time TEXT NOT NULL,
            client_id TEXT,
            client_name TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT '',
            duration_minutes INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            program_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // v1 부터 있던 테이블이다. 스냅샷이 빼먹으면 그 위에서 도는
        // 마이그레이션이 실제 DB 와 다른 것을 보게 된다(#819).
        database.execute('''
          CREATE TABLE client_diet_entries (
            id TEXT NOT NULL PRIMARY KEY,
            client_id TEXT NOT NULL,
            meal TEXT NOT NULL,
            items TEXT NOT NULL,
            calories INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // 이 테이블도 v1 부터 있었다. 스냅샷이 빼먹으면 v14 의 `completed_at`
        // 추가가 없는 표를 고치려다 죽는다(#1114).
        database.execute('''
          CREATE TABLE client_routine_history (
            id TEXT NOT NULL PRIMARY KEY,
            client_id TEXT NOT NULL,
            date_label TEXT NOT NULL,
            label TEXT NOT NULL,
            completion_rate INTEGER NOT NULL,
            exercises_json TEXT NOT NULL,
            client_feedback TEXT NOT NULL DEFAULT '',
            trainer_note TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        database.execute('''
          INSERT INTO client_routine_history (
            id, client_id, date_label, label, completion_rate, exercises_json,
            client_feedback, trainer_note, sort_order
          ) VALUES (
            'old-history', 'existing-client', '7/9', 'AI 루틴 · 자율 운동', 80,
            '["\\uc2a4\\ucffc\\ud2b8 3\\uc138\\ud2b8"]', '', '', 0
          )
        ''');
        database.execute('PRAGMA user_version = 4');
      },
    );
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    final clients = await db.select(db.trainerClients).get()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final version = await db.customSelect('PRAGMA user_version').getSingle();

    expect(version.read<int>('user_version'), 17);
    expect(clients, hasLength(2));
    expect(clients[0].name, '기존 회원 A');
    expect(clients[0].sugarG, 12.0);
    expect(clients[0].carbsG, 40.5);
    expect(clients[1].name, '기존 회원 B');
    expect(clients[1].active, isFalse);
    expect(clients[1].sugarG, 61.0);
    expect(clients[1].proteinG, 35.5);
    expect(clients[0].caloriesWeekJson, '[]');
    expect(clients[1].sugarWeekJson, '[]');
    // v17 의 성별·나이는 회원 ID로 새로 연결되는 회원만 채운다 — 예전 행은
    // 값 없이 그대로 남는다.
    expect(clients[0].gender, isNull);
    expect(clients[1].age, isNull);
  });

  test(
    'v5 to v17 adds the weekly calorie·sugar series to existing rows',
    () async {
      final executor = NativeDatabase.memory(
        setup: (database) {
          database.execute('''
          CREATE TABLE trainer_clients (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            avatar TEXT NOT NULL,
            goal TEXT NOT NULL,
            last_message TEXT NOT NULL,
            last_time TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
            calories_today INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sugar_g REAL NOT NULL,
            carbs_g REAL NOT NULL DEFAULT 0,
            protein_g REAL NOT NULL DEFAULT 0,
            fat_g REAL NOT NULL DEFAULT 0,
            last_routine TEXT NOT NULL,
            week_completion_json TEXT NOT NULL,
            sodium_week_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
          database.execute('''
          INSERT INTO trainer_clients (
            id, name, avatar, goal, last_message, last_time, active,
            calories_today, sodium_mg, sugar_g, carbs_g, protein_g, fat_g,
            last_routine, week_completion_json, sodium_week_json, sort_order
          ) VALUES (
            'client-a', '기존 회원 A', 'A', '혈압 관리', '보존 메시지', '방금', 1,
            500, 700, 17.8, 40.5, 20, 10, '어제', '[100]', '[700,800]', 1
          )
        ''');
          // 이 테이블은 v1 부터 있었다. 스냅샷이 빼먹으면 그 위에서 도는
          // 마이그레이션이 실제 DB 와 다른 것을 보게 된다(#822).
          database.execute('''
          CREATE TABLE trainer_schedule_entries (
            id TEXT NOT NULL PRIMARY KEY,
            date TEXT NOT NULL,
            time TEXT NOT NULL,
            client_id TEXT,
            client_name TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT '',
            duration_minutes INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            program_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
          // v1 부터 있던 테이블이다. 스냅샷이 빼먹으면 그 위에서 도는
          // 마이그레이션이 실제 DB 와 다른 것을 보게 된다(#819).
          database.execute('''
          CREATE TABLE client_diet_entries (
            id TEXT NOT NULL PRIMARY KEY,
            client_id TEXT NOT NULL,
            meal TEXT NOT NULL,
            items TEXT NOT NULL,
            calories INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
          // 이 테이블도 v1 부터 있었다. 스냅샷이 빼먹으면 v14 의 `completed_at`
          // 추가가 없는 표를 고치려다 죽는다(#1114).
          database.execute('''
            CREATE TABLE client_routine_history (
              id TEXT NOT NULL PRIMARY KEY,
              client_id TEXT NOT NULL,
              date_label TEXT NOT NULL,
              label TEXT NOT NULL,
              completion_rate INTEGER NOT NULL,
              exercises_json TEXT NOT NULL,
              client_feedback TEXT NOT NULL DEFAULT '',
              trainer_note TEXT NOT NULL DEFAULT '',
              sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          database.execute('''
            INSERT INTO client_routine_history (
              id, client_id, date_label, label, completion_rate, exercises_json,
              client_feedback, trainer_note, sort_order
            ) VALUES (
              'old-history', 'existing-client', '7/9', 'AI 루틴 · 자율 운동', 80,
              '["\\uc2a4\\ucffc\\ud2b8 3\\uc138\\ud2b8"]', '', '', 0
            )
          ''');
          database.execute('PRAGMA user_version = 5');
        },
      );
      final db = AppDatabase.forTesting(executor);
      addTearDown(db.close);

      final client = await db.select(db.trainerClients).getSingle();
      final version = await db.customSelect('PRAGMA user_version').getSingle();

      expect(version.read<int>('user_version'), 17);
      // 기존 값은 그대로 두고, 새 계열만 기본값으로 붙는다.
      expect(client.sugarG, 17.8);
      expect(client.sodiumWeekJson, '[700,800]');
      expect(client.caloriesWeekJson, '[]');
      expect(client.sugarWeekJson, '[]');
      // v17 의 성별·나이는 회원 ID로 새로 연결되는 회원만 채운다 — 예전 행은
      // 값 없이 그대로 남는다.
      expect(client.gender, isNull);
      expect(client.age, isNull);
    },
  );

  test('v14 to v17 adds the per-meal sugar·date columns and keeps rows', () async {
    // 끼니 표는 그동안 **오늘 하루**만 담아 날짜가 없었고, 당류도 하루 합계로만
    // 있었다(#1025). 컬럼이 늘어도 있던 끼니는 그대로 읽힌다.
    final executor = NativeDatabase.memory(
      setup: (database) {
        database.execute('''
          CREATE TABLE client_diet_entries (
            id TEXT NOT NULL,
            client_id TEXT NOT NULL,
            meal TEXT NOT NULL,
            items TEXT NOT NULL,
            calories INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            carbs_g REAL NOT NULL DEFAULT 0,
            protein_g REAL NOT NULL DEFAULT 0,
            fat_g REAL NOT NULL DEFAULT 0,
            photo_asset TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (id)
          )
        ''');
        database.execute('''
          INSERT INTO client_diet_entries
            (id, client_id, meal, items, calories, sodium_mg, carbs_g,
             protein_g, fat_g, sort_order)
          VALUES ('seed-diet-1', 'seed-client-1', '점심', '비빔밥',
                  720, 1320, 90.5, 28.0, 18.5, 0)
        ''');
        // 이 표도 v1 부터 있었다. v17 이 여기에 성별·나이 컬럼을 붙이므로
        // (신규 회원 등록), 표가 없는 인공 DB 로는 그 갈래를 지날 수 없다.
        database.execute('''
          CREATE TABLE trainer_clients (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            avatar TEXT NOT NULL,
            goal TEXT NOT NULL,
            last_message TEXT NOT NULL,
            last_time TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
            calories_today INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sugar_g REAL NOT NULL,
            carbs_g REAL NOT NULL DEFAULT 0,
            protein_g REAL NOT NULL DEFAULT 0,
            fat_g REAL NOT NULL DEFAULT 0,
            last_routine TEXT NOT NULL,
            week_completion_json TEXT NOT NULL,
            sodium_week_json TEXT NOT NULL DEFAULT '[]',
            calories_week_json TEXT NOT NULL DEFAULT '[]',
            sugar_week_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        database.execute('PRAGMA user_version = 14');
      },
    );
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    final row = await db.select(db.clientDietEntries).getSingle();
    final version = await db.customSelect('PRAGMA user_version').getSingle();

    expect(version.read<int>('user_version'), 17);
    expect(row.meal, '점심');
    expect(row.calories, 720);
    expect(row.carbsG, 90.5);
    // 새 컬럼은 기본값. 날짜가 빈 행은 날짜로 거르는 조회에 걸리지 않으므로,
    // 재시딩 전에는 기간 뷰의 끼니가 비어 보일 뿐 오늘 화면은 그대로다.
    expect(row.sugarG, 0);
    expect(row.date, '');
    // v16 의 끼니 시각·음식별 영양도 기본값이다. 그런 행은 예전처럼 `items`
    // 한 줄로 읽힌다(#1166).
    expect(row.timeLabel, '');
    expect(row.foodsJson, '[]');
  });

  test('v15 to v17 adds the per-meal time·foods columns and keeps rows', () async {
    // 끼니 카드가 회원 앱과 같아지면서 시각과 음식별 영양이 필요해졌다(#1166).
    // 컬럼이 늘어도 있던 끼니는 그대로 읽히고, 새 값은 기본값이다.
    final executor = NativeDatabase.memory(
      setup: (database) {
        database.execute('''
          CREATE TABLE client_diet_entries (
            id TEXT NOT NULL,
            client_id TEXT NOT NULL,
            meal TEXT NOT NULL,
            items TEXT NOT NULL,
            calories INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            carbs_g REAL NOT NULL DEFAULT 0,
            protein_g REAL NOT NULL DEFAULT 0,
            fat_g REAL NOT NULL DEFAULT 0,
            sugar_g REAL NOT NULL DEFAULT 0,
            date TEXT NOT NULL DEFAULT '',
            photo_asset TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (id)
          )
        ''');
        database.execute('''
          INSERT INTO client_diet_entries
            (id, client_id, meal, items, calories, sodium_mg, carbs_g,
             protein_g, fat_g, sugar_g, date, sort_order)
          VALUES ('seed-diet-1', 'seed-client-1', '점심', '비빔밥',
                  720, 1320, 90.5, 28.0, 18.5, 12.5, '2026-08-23', 0)
        ''');
        // 이 표도 v1 부터 있었다. v17 이 여기에 성별·나이 컬럼을 붙이므로
        // (신규 회원 등록), 표가 없는 인공 DB 로는 그 갈래를 지날 수 없다.
        database.execute('''
          CREATE TABLE trainer_clients (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            avatar TEXT NOT NULL,
            goal TEXT NOT NULL,
            last_message TEXT NOT NULL,
            last_time TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
            calories_today INTEGER NOT NULL,
            sodium_mg INTEGER NOT NULL,
            sugar_g REAL NOT NULL,
            carbs_g REAL NOT NULL DEFAULT 0,
            protein_g REAL NOT NULL DEFAULT 0,
            fat_g REAL NOT NULL DEFAULT 0,
            last_routine TEXT NOT NULL,
            week_completion_json TEXT NOT NULL,
            sodium_week_json TEXT NOT NULL DEFAULT '[]',
            calories_week_json TEXT NOT NULL DEFAULT '[]',
            sugar_week_json TEXT NOT NULL DEFAULT '[]',
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        database.execute('PRAGMA user_version = 15');
      },
    );
    final db = AppDatabase.forTesting(executor);
    addTearDown(db.close);

    final row = await db.select(db.clientDietEntries).getSingle();
    final version = await db.customSelect('PRAGMA user_version').getSingle();

    expect(version.read<int>('user_version'), 17);
    expect(row.meal, '점심');
    expect(row.sugarG, 12.5);
    expect(row.date, '2026-08-23');
    expect(row.timeLabel, '');
    expect(row.foodsJson, '[]');
  });
}
