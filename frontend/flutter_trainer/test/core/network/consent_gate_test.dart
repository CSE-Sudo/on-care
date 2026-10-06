/// 트레이너 API 가 "필수 동의가 남았다" 며 요청을 거절할 때 — #3155.
///
/// 서버는 필수 동의(약관·개인정보·만 14세)가 끝나지 않은 트레이너에게 403
/// `consent_required` 를 준다. 그 응답을 받으면 세션이 동의가 남은 상태로 바뀌고,
/// 라우터 가드가 동의 화면으로 보내며, 동의를 제출하면 다시 풀린다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/network/auth_interceptor.dart';

import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/auth_token.dart';
import 'package:oncare_trainer/core/network/consent_gate.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/auth/data/repositories/consent_repositories.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/consent_repository.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

const AppConfig _realConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: false,
);

const Map<String, Object?> _consentRequired = <String, Object?>{
  'detail': <String, Object?>{
    'code': 'consent_required',
    'missing': <String>['privacy'],
  },
};

const TrainerProfile _profile = TrainerProfile(
  name: '트레이너',
  email: 'trainer@example.com',
  phone: '',
  specialty: '',
  careerYears: null,
  intro: '',
  certifications: <String>[],
  gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
);

/// 로그인은 동의를 마친 계정으로 끝난다 — 동의 요구는 그 뒤 API 가 알린다.
class _AuthRepository implements TrainerAuthRepository {
  static const TrainerAuthTokens _tokens = TrainerAuthTokens(
    access: 'access-1',
    refresh: 'refresh-1',
  );

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String emailCode,
    String phone = '',
    List<String>? consents,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async => _tokens;

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async => _profile;
}

class _ConsentRepository implements ConsentRepository {
  final List<List<String>> submitted = <List<String>>[];

  @override
  Future<bool> submit(List<String> consents) async {
    submitted.add(consents);
    return false;
  }
}

/// `METHOD /path` → (상태, 본문). 없는 경로는 404.
class _Backend implements HttpClientAdapter {
  _Backend(this.routes);

  final Map<String, (int, Object?)> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String path = options.uri.path.replaceFirst('/v1', '');
    final (int, Object?) hit =
        routes['${options.method.toUpperCase()} $path'] ??
        (404, <String, Object?>{});
    return ResponseBody.fromString(
      jsonEncode(hit.$2),
      hit.$1,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 앱과 같은 인터셉터(인증 → 동의)를 단 Dio 로 로그인한 세션을 만든다.
Future<(ProviderContainer, _ConsentRepository)> _signedIn(
  Map<String, (int, Object?)> routes,
) async {
  final _ConsentRepository consent = _ConsentRepository();
  final _Backend backend = _Backend(routes);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_realConfig),
      trainerAuthRepositoryProvider.overrideWithValue(_AuthRepository()),
      consentRepositoryProvider.overrideWithValue(consent),
      dioProvider.overrideWith((ref) {
        final Dio dio = Dio(
          BaseOptions(
            baseUrl: _realConfig.apiBaseUrl,
            validateStatus: (int? s) => s != null && s < 400,
          ),
        )..httpClientAdapter = backend;
        dio.interceptors
          ..add(authInterceptorFor(ref, retryClient: dio))
          ..add(
            ConsentRequiredInterceptor(
              () => ref.read(consentGateBridgeProvider),
            ),
          );
        return dio;
      }),
    ],
  );
  addTearDown(container.dispose);
  // 저장된 토큰이 없어 복구는 곧장 로그아웃 상태로 끝난다.
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await container
      .read(sessionControllerProvider.notifier)
      .login(email: 'trainer@example.com', password: 'pw-12345678');
  expect(container.read(sessionControllerProvider).consentRequired, isFalse);
  return (container, consent);
}

String? _redirect(ProviderContainer container, String location) {
  final SessionState s = container.read(sessionControllerProvider);
  return sessionRedirect(
    s.status,
    location,
    consentRequired: s.consentRequired,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  group('isConsentRequiredResponse', () {
    Response<Object?> res(int status, Object? data) => Response<Object?>(
      requestOptions: RequestOptions(path: '/x'),
      statusCode: status,
      data: data,
    );

    test('403 이고 detail.code 가 consent_required 일 때만 참', () {
      expect(isConsentRequiredResponse(res(403, _consentRequired)), isTrue);
      expect(isConsentRequiredResponse(res(422, _consentRequired)), isFalse);
      expect(
        isConsentRequiredResponse(
          res(403, <String, Object?>{'detail': '트레이너 권한이 필요합니다.'}),
        ),
        isFalse,
      );
      expect(
        isConsentRequiredResponse(
          res(403, <String, Object?>{
            'detail': <String, Object?>{'code': 'client_link_inactive'},
          }),
        ),
        isFalse,
      );
      expect(isConsentRequiredResponse(res(403, null)), isFalse);
      expect(isConsentRequiredResponse(null), isFalse);
    });
  });

  group('ConsentGateBridge', () {
    test('붙인 것만 떼고, 떼면 알림이 가지 않는다', () {
      final ConsentGateBridge bridge = ConsentGateBridge();
      final List<String> got = <String>[];
      void listener(String token) => got.add(token);
      void other(String token) {}

      bridge
        ..attach(listener)
        ..notify('t1')
        ..detach(other)
        ..notify('t2')
        ..detach(listener)
        ..notify('t3');

      expect(got, <String>['t1', 't2']);
    });
  });

  group('실행 중 403 consent_required', () {
    test('트레이너 API 가 거절하면 동의 화면으로 가고, 동의하면 풀린다', () async {
      final (
        ProviderContainer container,
        _ConsentRepository consent,
      ) = await _signedIn(<String, (int, Object?)>{
        'GET /trainer/clients': (403, _consentRequired),
      });
      expect(_redirect(container, AppRoutes.dashboard), isNull);

      // 오류는 그대로 호출부에 간다 — 화면의 실패 처리는 바뀌지 않는다.
      await expectLater(
        container.read(dioProvider).get<Object?>('/trainer/clients'),
        throwsA(isA<DioException>()),
      );

      final SessionState s = container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.consentRequired, isTrue);
      // 같은 계정이다 — 프로필을 버리지 않는다.
      expect(s.profile?.email, _profile.email);
      expect(_redirect(container, AppRoutes.dashboard), AppRoutes.consent);
      expect(_redirect(container, AppRoutes.clients), AppRoutes.consent);

      await container.read(sessionControllerProvider.notifier).submitConsents(
        <String>['terms', 'privacy', 'age14'],
      );

      expect(consent.submitted.single, <String>['terms', 'privacy', 'age14']);
      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
      expect(_redirect(container, AppRoutes.consent), AppRoutes.dashboard);
    });

    test('다른 403(권한 없음)은 동의 화면으로 보내지 않는다', () async {
      final (ProviderContainer container, _) = await _signedIn(
        <String, (int, Object?)>{
          'GET /trainer/clients': (
            403,
            <String, Object?>{'detail': '트레이너 권한이 필요합니다.'},
          ),
        },
      );

      await expectLater(
        container.read(dioProvider).get<Object?>('/trainer/clients'),
        throwsA(isA<DioException>()),
      );

      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
    });

    test('호출부가 직접 토큰을 넣은 요청은 세션의 것이 아니라 무시한다', () async {
      final (ProviderContainer container, _) = await _signedIn(
        <String, (int, Object?)>{
          'GET /trainer/clients': (403, _consentRequired),
        },
      );

      await expectLater(
        container
            .read(dioProvider)
            .get<Object?>(
              '/trainer/clients',
              options: Options(
                headers: <String, Object?>{'Authorization': 'Bearer other'},
              ),
            ),
        throwsA(isA<DioException>()),
      );

      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
    });

    test('로그아웃 뒤 늦게 온 응답은 세션을 바꾸지 않는다', () async {
      final (ProviderContainer container, _) = await _signedIn(
        const <String, (int, Object?)>{},
      );
      await container.read(sessionControllerProvider.notifier).signOut();

      container.read(consentGateBridgeProvider).notify('access-1');

      final SessionState s = container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.signedOut);
      expect(s.consentRequired, isFalse);
      expect(container.read(authAccessTokenProvider), isNull);
    });

    test('다른 토큰의 알림은 지금 세션을 바꾸지 않는다', () async {
      final (ProviderContainer container, _) = await _signedIn(
        const <String, (int, Object?)>{},
      );

      container.read(consentGateBridgeProvider).notify('stale-token');

      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
    });
  });

  test('앱의 Dio 에 동의 인터셉터가 인증 인터셉터 뒤에 달려 있다', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[appConfigProvider.overrideWithValue(_realConfig)],
    );
    addTearDown(container.dispose);

    final List<Interceptor> interceptors = container
        .read(dioProvider)
        .interceptors
        .toList();
    final int consent = interceptors.indexWhere(
      (Interceptor i) => i is ConsentRequiredInterceptor,
    );
    expect(consent, greaterThanOrEqualTo(0));
    expect(
      interceptors.indexWhere((Interceptor i) => i is AuthInterceptor),
      lessThan(consent),
    );
  });
}
