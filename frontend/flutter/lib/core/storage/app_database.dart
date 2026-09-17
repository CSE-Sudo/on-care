import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'app_database.g.dart';

/// Generic key-value table. Used for tiny app-level state (locale,
/// onboarding flags) and as a stash for JSON snapshots that don't yet
/// warrant their own table (MyHealthState, AiCoachState, …).
class AppKeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

@DataClassName('DietEntryRow')
class DietEntries extends Table {
  TextColumn get id => text()();
  TextColumn get date => text()(); // YYYY-MM-DD
  TextColumn get mealType => text()(); // breakfast|lunch|dinner|snack
  TextColumn get timeLabel => text()(); // "08:20"
  TextColumn get foodsJson => text()(); // [{ "name": "...", "calories": ... }]
  IntColumn get totalCalories => integer()();
  IntColumn get sodiumMg => integer().withDefault(const Constant(0))();
  // 당류만 실수. 서버 계약(diet_entries.sugar_g)이 float 이고 도메인 엔티티도
  // double 이라, 로컬 캐시만 정수면 데모 모드에서 8.5 가 8 로 잘린다.
  RealColumn get sugarG => real().withDefault(const Constant(0.0))();
  // 끼니별 AI 코멘트. 식단 상세가 이 값을 그대로 그린다. 데모 시드가 채워 두고,
  // 새로 분석된 항목은 인식 응답이 준 코멘트를 받는다. 값이 없으면 화면이 칸을
  // 통째로 감추므로 빈 문자열이 안전한 기본값이다.
  TextColumn get aiComment => text().withDefault(const Constant(''))();
  // 끼니 사진 에셋 경로. 예전에는 인터셉터가 시드 id → 에셋 맵을 들고 있어서
  // 새로 추가된 항목에는 사진이 붙지 않았다. 행이 자기 사진을 갖게 한다.
  TextColumn get photoAsset => text().withDefault(const Constant(''))();
  // 회원이 방금 올린 끼니 사진 원본. 데모 백엔드(`LocalApiInterceptor`)가
  // `/diet/photos/{entry id}` 로 되돌려 주고, 끼니 카드는 그 경로를 실서버의
  // 사진 경로와 똑같이 읽는다. 번들 에셋([photoAsset])과 달리 이 사진은 그
  // 기록에만 속하므로 행에 같이 둔다. 사진 없이 만든 기록은 null.
  BlobColumn get photoBytes => blob().nullable()();
  // 재시도 중복 저장 방지 멱등키(요청당 1회). 무키 요청은 null.
  TextColumn get idempotencyKey => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('ExerciseSessionRow')
class ExerciseSessions extends Table {
  TextColumn get id => text()();
  TextColumn get weekStart => text()(); // Monday YYYY-MM-DD
  TextColumn get dayLabel => text()(); // 월/화/수/...
  TextColumn get type => text()(); // cardio|strength|flexibility|other
  /// 회원이 적은 운동 이름. 유형은 집계 축이라 넷뿐이라, 무슨 운동을 했는지는
  /// 이 칸에만 남는다. 이 컬럼이 생기기 전 기록은 빈 문자열이다. (#1276)
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get minutes => integer()();
  /// 근력 기록의 세트 수. 근력이 아니거나 세트를 모르는 기록은 null 이고,
  /// 그때는 분에서 환산해 읽는다. (#1262)
  IntColumn get sets => integer().nullable()();
  /// 근력 기록의 한 세트당 횟수. 세트·중량과 한 벌이라 근력에만 있다. (#1310)
  IntColumn get reps => integer().nullable()();
  /// 근력 기록의 중량(kg). 세트와 짝이라 근력에만 있다. (#1276)
  RealColumn get weight => real().nullable()();
  IntColumn get calories => integer()();
  TextColumn get intensity =>
      text().withDefault(const Constant('moderate'))(); // light|moderate|high
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('NotificationRow')
class NotificationItems extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get category =>
      text()(); // reminder|health_check|achievement|system
  BoolColumn get read => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DriftDatabase(
  tables: <Type>[
    AppKeyValues,
    DietEntries,
    ExerciseSessions,
    NotificationItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'oncare',
          // On web, drift needs the sqlite3 WASM module and a worker
          // script. The release CI downloads both into `web/` so the
          // bundled `index.html` can fetch them at the same origin.
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  /// Use in tests:
  ///   `AppDatabase.forTesting(NativeDatabase.memory())`
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(dietEntries);
        await m.createTable(exerciseSessions);
        await m.createTable(notificationItems);
      }
      if (from < 3) {
        // 운동 강도(intensity) 컬럼 추가 — 기존 행은 기본값 moderate.
        await m.addColumn(exerciseSessions, exerciseSessions.intensity);
      }
      if (from < 4) {
        // 식단 멱등키(idempotency_key) 컬럼 추가 — 기존 행은 null.
        await m.addColumn(dietEntries, dietEntries.idempotencyKey);
      }
      if (from < 5) {
        // 바이탈(체중/혈압/혈당) 기능 제거 — 기존 vitals 테이블 폐기.
        // v2~v4 에서만 vitals 가 생성됐고 v1 DB 에는 없으므로, 없는 테이블을
        // 지우다 실패하지 않도록 IF EXISTS 로 안전하게 드롭한다.
        await customStatement('DROP TABLE IF EXISTS vitals');
      }
      if (from < 6) {
        // 당류 sugar_g: INTEGER → REAL. 테이블을 다시 만들 필요는 없다.
        // SQLite 의 INTEGER 친화도는 "무손실일 때만" 정수로 바꾸므로 8.5 는
        // 그대로 REAL 로 저장되고, 읽을 때는 drift 가 선언 타입(double)으로
        // 매핑한다. 기존 정수 값도 8 → 8.0 으로 읽혀 손실이 없다.
        // 스키마 버전만 올려 이 결정을 기록해 둔다.
      }
      if (from < 7) {
        // 끼니별 AI 코멘트·사진 컬럼 추가 — 기존 행은 빈 문자열.
        //
        // 식단이 인메모리 목업 저장소에서 로컬 인터셉터 경로로 옮겨 오면서
        // 필요해졌다. 그 두 값은 목업 쪽에만 있었고 테이블에는 자리가 없었다.
        await m.addColumn(dietEntries, dietEntries.aiComment);
        await m.addColumn(dietEntries, dietEntries.photoAsset);
      }
      if (from < 8) {
        // 근력 세트 수 컬럼 추가 — 기존 기록은 null 이라 분에서 환산해 읽는다.
        await m.addColumn(exerciseSessions, exerciseSessions.sets);
      }
      if (from < 9) {
        // 운동 이름·중량 컬럼 추가 — 기존 기록은 비어 있다. (#1276)
        await m.addColumn(exerciseSessions, exerciseSessions.name);
        await m.addColumn(exerciseSessions, exerciseSessions.weight);
      }
      if (from < 10) {
        // 근력 횟수 컬럼 추가 — 기존 기록은 비어 있다. 세트·중량만으로는
        // 한 세트에 몇 번을 들었는지가 남지 않는다. (#1310)
        await m.addColumn(exerciseSessions, exerciseSessions.reps);
      }
      if (from < 11) {
        // 끼니 사진 원본 컬럼 추가 — 기존 기록은 null 이라 예전처럼 번들
        // 에셋이나 이모지로 그려진다.
        await m.addColumn(dietEntries, dietEntries.photoBytes);
      }
      if (from < 12) {
        // 회원앱 일정 기능 제거(#1928) — 읽고 쓰는 곳이 없어진 표를 지운다.
        // 바이탈 때(v5)와 같은 방식으로, 없는 표를 지우다 실패하지 않게 한다.
        await customStatement('DROP TABLE IF EXISTS schedule_events');
      }
    },
  );

  // ---- AppKeyValues ----
  Future<void> putValue(String key, String value) {
    return into(appKeyValues).insertOnConflictUpdate(
      AppKeyValuesCompanion.insert(key: key, value: value),
    );
  }

  Future<String?> readValue(String key) async {
    final row = await (select(
      appKeyValues,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> deleteValue(String key) {
    return (delete(appKeyValues)..where((t) => t.key.equals(key))).go();
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}, name: 'appDatabase');
