import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/interceptors/api_logging_interceptor.dart';
import 'package:oncare/core/network/interceptors/auth_interceptor.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/network/interceptors/mock_api_interceptor.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/points/demo_weekly_challenge.dart';
import 'package:oncare/core/storage/app_database.dart';

/// App-wide `Dio` instance, wired with logging/auth/mock interceptors
/// based on the current [AppConfig]. Feature data sources should read
/// this provider rather than constructing their own `Dio`.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final logger = ref.watch(appLoggerProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      contentType: Headers.jsonContentType,
      // 4xx/5xx are normal API errors and should surface as DioException
      // so callers can react via try/catch, not slip past `res.data!`
      // straight into a misleading "Null check" failure in a fromJson
      // factory.
      validateStatus: (int? status) => status != null && status < 400,
    ),
  );

  // Order matters: LocalApi (drift-backed) and the legacy in-memory
  // MockApi both short-circuit before auth/logging fire.
  if (config.useMockApi) {
    // REAL_API 로 켠 기능의 경로는 두 목업 인터셉터 모두 가로채지 않고 실 네트워크로
    // 흘려보낸다 — 준비된 기능만 골라 실연동해 보여줄 수 있게(전역 USE_MOCK_API 는
    // 끄는 순간 전 기능이 함께 넘어간다).
    dio.interceptors
      ..add(
        LocalApiInterceptor(
          ref.watch(appDatabaseProvider),
          logger,
          isRealApi: config.isRealApi,
          // 목업 운동·코치 저장소와 같은 원장 — 하루 한도와 잔액이 하나다(#1786).
          points: ref.watch(demoPointsLedgerProvider),
          // 목업 헬스장 저장소와 같은 쿠폰 원장 — 해제가 쿠폰 취소로 이어진다(#1787).
          coupons: ref.watch(demoCouponBookProvider),
          // 목업 운동 저장소와 같은 보호권 원장 — 보호한 날에 기록이 생기면
          // 여기서 되돌린다(#1788).
          shields: ref.watch(demoStreakShieldBookProvider),
          // 목업 운동 저장소가 운동한 날을 붙이는 챌린지 — 진행이 운동 탭과 같다(#1789).
          challenges: ref.watch(demoWeeklyChallengeProvider),
        ),
      )
      ..add(MockApiInterceptor(logger, isRealApi: config.isRealApi));
  }
  dio.interceptors.add(AuthInterceptor(ref));
  if (!config.isProd) {
    dio.interceptors.add(ApiLoggingInterceptor(logger));
  }

  ref.onDispose(dio.close);
  return dio;
}, name: 'dio');
