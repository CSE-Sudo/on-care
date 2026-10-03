import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/network/accept_language_interceptor.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/auth_token.dart';
import 'package:oncare_trainer/core/network/client_platform.dart';
import 'package:oncare_trainer/core/network/interceptors/api_logging_interceptor.dart';
import 'package:oncare_trainer/core/network/interceptors/client_access_interceptor.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';

/// App-wide `Dio` instance, wired with language + auth + logging interceptors from
/// the current [AppConfig]. Feature data sources read this provider
/// rather than constructing their own `Dio`.
///
/// Unlike the user app there is no local/mock interceptor here — mock
/// mode is selected at the repository layer (mock vs Dio implementation),
/// so `dioProvider` always talks to the real backend when used.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      contentType: Headers.jsonContentType,
      // 웹 빌드는 자기가 웹이라고 알린다 — 서버가 짧은 refresh 토큰을 준다(#2828).
      headers: clientPlatformHeaders(),
      // Surface 4xx/5xx as DioException so callers react via try/catch
      // instead of dereferencing a null body in a fromJson factory.
      validateStatus: (int? status) => status != null && status < 400,
    ),
  );

  // 화면 언어는 요청마다 읽는다 — 언어를 바꿔도 Dio 를 다시 만들지 않는다(#2297).
  // 실행 중 만료된 토큰은 갱신 뒤 원 요청을 한 번 다시 보낸다(#1546).
  dio.interceptors
    ..add(
      AcceptLanguageInterceptor(() => ref.read(trainerResolvedLocaleProvider)),
    )
    ..add(authInterceptorFor(ref, retryClient: dio));
  // 담당이 해제된 회원의 404 를 로스터 재검증으로 잇는다(#2281).
  dio.interceptors.add(
    ClientAccessInterceptor(ref.watch(clientAccessLostProvider).report),
  );
  if (!config.isProd) {
    dio.interceptors.add(const ApiLoggingInterceptor());
  }

  ref.onDispose(dio.close);
  return dio;
}, name: 'dio');
