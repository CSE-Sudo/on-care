import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/client_platform.dart';
import 'package:oncare/core/network/consent_gate.dart';
import 'package:oncare/core/network/interceptors/api_logging_interceptor.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/network/request_timeouts.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/points/demo_weekly_challenge.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/shared/services/locale_provider.dart';
import 'package:oncare_core/network/accept_language_interceptor.dart';

/// App-wide `Dio` instance, wired with logging/auth/local-api interceptors
/// based on the current [AppConfig]. Feature data sources should read
/// this provider rather than constructing their own `Dio`.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final logger = ref.watch(appLoggerProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: apiConnectTimeout,
      receiveTimeout: apiReceiveTimeout,
      // 사진 업로드는 요청 단위로 늘린다(`photoUploadSendTimeout`, #3141).
      sendTimeout: apiSendTimeout,
      contentType: Headers.jsonContentType,
      // 웹 빌드는 자기가 웹이라고 알린다 — 서버가 짧은 refresh 토큰을 준다(#2828).
      headers: clientPlatformHeaders(),
      // 4xx/5xx are normal API errors and should surface as DioException
      // so callers can react via try/catch, not slip past `res.data!`
      // straight into a misleading "Null check" failure in a fromJson
      // factory.
      validateStatus: (int? status) => status != null && status < 400,
    ),
  );

  // 화면 언어는 가장 먼저 싣는다 — 목업 인터셉터도 같은 요청 헤더를 보게.
  // 언어는 요청마다 읽으므로 언어가 바뀌어도 Dio 를 다시 만들지 않는다(#2297).
  dio.interceptors.add(
    AcceptLanguageInterceptor(() => ref.read(resolvedLocaleProvider)),
  );

  // Order matters: LocalApi (drift-backed) short-circuits before auth/logging
  // fire.
  //
  // 상수 [kDemoCodeIncluded] 를 먼저 본다 — 운영 릴리스에서는 이 분기 전체가
  // 컴파일 때 사라져 로컬 API·시드가 번들에 들어가지 않는다(#3157).
  if (kDemoCodeIncluded && config.useMockApi) {
    // REAL_API 로 켠 기능의 경로는 목업 인터셉터가 가로채지 않고 실 네트워크로
    // 흘려보낸다 — 준비된 기능만 골라 실연동해 보여줄 수 있게(전역 USE_MOCK_API 는
    // 끄는 순간 전 기능이 함께 넘어간다).
    dio.interceptors.add(
      LocalApiInterceptor(
        ref.watch(appDatabaseProvider),
        logger,
        isRealApi: config.isRealApi,
        // 목업 코치 저장소와 같은 원장 — 하루 한도와 잔액이 하나다(#1786).
        points: ref.watch(demoPointsLedgerProvider),
        // 목업 헬스장 저장소와 같은 쿠폰 원장 — 해제가 쿠폰 취소로 이어진다(#1787).
        coupons: ref.watch(demoCouponBookProvider),
        // 사용처(쿠폰 원장)와 같은 보호권 원장 — 보호한 날에 운동 기록이
        // 생기면 여기서 되돌린다(#1788).
        shields: ref.watch(demoStreakShieldBookProvider),
        // 챌린지 원장(#1789). 운동한 날은 이 인터셉터의 운동 표(운동 탭과 같은
        // 기록)로 센다(#2662).
        challenges: ref.watch(demoWeeklyChallengeProvider),
      ),
    );
  }
  // 실행 중 만료된 토큰은 갱신 뒤 원 요청을 한 번 다시 보낸다(#1546).
  dio.interceptors.add(authInterceptorFor(ref, retryClient: dio));
  // 실행 중 필수 동의가 남게 되면(문서 버전 갱신 등) 동의 화면으로 보낸다(#3088).
  dio.interceptors.add(
    ConsentRequiredInterceptor(() => ref.read(consentGateBridgeProvider)),
  );
  if (!config.isProd) {
    dio.interceptors.add(ApiLoggingInterceptor(logger));
  }

  ref.onDispose(dio.close);
  return dio;
}, name: 'dio');
