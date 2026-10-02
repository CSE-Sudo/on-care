/// 운동 저장소를 앱의 데모(목업 모드)와 **같은 경로**로 띄운다. (#2724)
///
/// 데모는 `DioExerciseRepository` + 로컬 목업 API(drift)를 쓴다(#2662). 예전
/// 시험들은 그 자리에 메모리 대역(`MockExerciseRepository`)을 끼워, 실제 데모와
/// 다른 구현을 상대로 돌았다 — 둘이 어긋나도 시험이 잡지 못했다. 여기서는 메모리
/// drift 를 공유 픽스처로 시드하고, 앱과 같은 연결로 그 위에서 돈다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/features/exercise/data/repositories/dio_exercise_repository.dart';

/// 픽스처로 시드한 메모리 DB. 시험이 끝나면 닫는다.
///
/// 위젯 시험은 가짜 비동기 안에서 돈다 — 시드는 [WidgetTester.runAsync] 로
/// 돌려야 끝난다. [tester] 를 주지 않으면(단위 시험) 바로 기다린다.
Future<AppDatabase> seededDemoDatabase([WidgetTester? tester]) async {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  if (tester == null) {
    await seedIfEmpty(db);
  } else {
    await tester.runAsync(() => seedIfEmpty(db));
  }
  return db;
}

/// 위젯 시험의 오버라이드 — 앱의 `exerciseRepositoryProvider` 가 그대로
/// Dio → 로컬 목업 API → [db] 로 간다. `appLoggerProvider` 는 시험이 따로
/// 덮는다(Dio 가 읽는다).
List<Override> demoExerciseOverrides(AppDatabase db) => <Override>[
  appDatabaseProvider.overrideWithValue(db),
];

/// 빈 메모리 DB — 시드 없이 시험이 기록을 직접 넣을 때. 시험이 끝나면 닫는다.
AppDatabase emptyDemoDatabase() {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

/// [db] 위의 로컬 목업 API 를 부르는 Dio — 앱의 목업 모드와 같은 연결이다.
/// 호출을 세는 대역이 `DioExerciseRepository` 를 상속할 때 쓴다.
Dio demoExerciseDio(AppDatabase db, {LocalApiInterceptor? api}) =>
    Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..interceptors.add(api ?? LocalApiInterceptor(db, Logger(level: Level.off)));

/// 단위 시험용 — [db] 위의 로컬 목업 API 와 그것을 부르는 운동 저장소.
///
/// [points] 를 주면 그 원장에 적립한다 — 앱에서는 목업 코치 저장소와 같은 원장이다.
({LocalApiInterceptor api, DioExerciseRepository repository}) demoExerciseBackend(
  AppDatabase db, {
  DemoPointsLedger? points,
}) {
  final LocalApiInterceptor api = LocalApiInterceptor(
    db,
    Logger(level: Level.off),
    points: points,
  );
  return (
    api: api,
    repository: DioExerciseRepository(demoExerciseDio(db, api: api)),
  );
}
