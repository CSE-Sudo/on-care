/// 데모(목 모드) 알림함을 띄우는 도우미. (#2660)
///
/// 데모 알림함은 목업 저장소가 아니라 실서버와 같은 `DioNotificationRepository` 를
/// 쓰고, 로컬 인터셉터가 drift 의 데모 시드로 답한다. 테스트도 같은 길을 탄다 —
/// 인메모리 drift 에 앱과 같은 시드를 넣고 `appDatabaseProvider` 를 덮는다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';

const AppConfig kDemoNotificationConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 데모 시드 알림 아홉 건 중 안 읽은 것. 시드의 앞 일곱 건이다.
const int kDemoUnreadNotifications = 7;

/// 앱이 부팅 때 넣는 것과 같은 데모 시드가 든 인메모리 DB. 닫는 것은 부른 쪽 몫이다.
Future<AppDatabase> seededDemoDatabase() async {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  await seedIfEmpty(db);
  return db;
}

/// 목 모드 설정 + 시드 DB. 로그는 끈다.
List<Override> demoNotificationOverrides(AppDatabase db) => <Override>[
  appConfigProvider.overrideWithValue(kDemoNotificationConfig),
  appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
  appDatabaseProvider.overrideWithValue(db),
];

/// 데모 알림함이 받는 첫 쪽 — 시드 DB 를 로컬 인터셉터·Dio 저장소로 읽은 그대로다.
Future<List<AlertItem>> fetchDemoAlerts() async {
  final AppDatabase db = await seededDemoDatabase();
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  try {
    return await DioNotificationRepository(dio).fetchPage();
  } finally {
    dio.close();
    await db.close();
  }
}
