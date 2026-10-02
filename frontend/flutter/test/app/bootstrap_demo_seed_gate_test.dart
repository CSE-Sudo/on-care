import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/bootstrap.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/points/demo_benefits_store.dart' show kDemoBenefitsKey;
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';

/// 앱 시작의 데모 시드 게이트(#2914). 실서버 빌드는 아무도 읽지 않는 데모 행을
/// 기기에 쓰지 않아야 하고, 데모 빌드는 지금처럼 시드돼야 한다.
AppConfig _config({required bool useMockApi}) => AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost:8000/v1',
  useMockApi: useMockApi,
);

void main() {
  late AppDatabase db;
  final Logger logger = Logger(level: Level.off);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('실서버 모드에서는 시드를 부르지 않는다', () async {
    int calls = 0;
    await prepareDemoStorage(
      _config(useMockApi: false),
      db,
      logger,
      seed: (AppDatabase _) async => calls++,
    );

    expect(calls, 0);
  });

  test('실서버 모드에서는 로컬 DB 에 시드 플래그·혜택 장부를 쓰지 않는다', () async {
    await prepareDemoStorage(_config(useMockApi: false), db, logger);

    expect(await db.readValue(kSeedFlag), isNull);
    expect(await db.readValue(kDemoBenefitsKey), isNull);
    expect(await db.select(db.dietEntries).get(), isEmpty);
    expect(await db.select(db.exerciseSessions).get(), isEmpty);
  });

  test('데모 모드에서는 지금처럼 시드를 부른다', () async {
    int calls = 0;
    await prepareDemoStorage(
      _config(useMockApi: true),
      db,
      logger,
      seed: (AppDatabase _) async => calls++,
    );

    expect(calls, 1);
  });

  test('시드가 실패해도 앱 시작을 막지 않는다', () async {
    await expectLater(
      prepareDemoStorage(
        _config(useMockApi: true),
        db,
        logger,
        seed: (AppDatabase _) async => throw StateError('no sqlite3.wasm'),
      ),
      completes,
    );
  });
}
