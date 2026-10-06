/// 앱을 쓰는 사이 서버가 "필수 동의가 남았다" 며 데이터 요청을 거절할 때 — #3088.
///
/// 회원 데이터·AI API 는 필수 동의가 끝나지 않은 계정에 403 `consent_required`
/// 를 준다. 그 응답을 받으면 세션이 동의가 남은 상태로 바뀌고, 라우터 가드가
/// 동의 화면으로 보내며, 동의를 제출하면 다시 풀린다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/consent_gate.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

const Map<String, Object?> _consentRequired = <String, Object?>{
  'detail': <String, Object?>{
    'code': 'consent_required',
    'missing': <String>['privacy'],
  },
};

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

/// 앱과 같은 인터셉터(인증 → 동의)를 단 Dio 로 세션을 만든다.
ProviderContainer _container(_Backend backend) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      dioProvider.overrideWith((ref) {
        final Dio dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.test/v1',
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
      sessionFeatureResetOverride(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProviderContainer> _signedIn(Map<String, (int, Object?)> routes) async {
  final ProviderContainer container = _container(
    _Backend(<String, (int, Object?)>{
      'POST /auth/login': (
        200,
        <String, Object?>{
          'access_token': 'access-1',
          'refresh_token': 'refresh-1',
          'consent_required': false,
        },
      ),
      ...routes,
    }),
  );
  // 저장된 토큰이 없어 복구는 곧장 로그아웃 상태로 끝난다.
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await container
      .read(sessionControllerProvider.notifier)
      .login(email: 'm@example.com', password: 'pw-12345678');
  expect(container.read(sessionControllerProvider).consentRequired, isFalse);
  return container;
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
          res(403, <String, Object?>{'detail': '회원 전용 API예요.'}),
        ),
        isFalse,
      );
      expect(
        isConsentRequiredResponse(
          res(403, <String, Object?>{
            'detail': <String, Object?>{'code': 'trainer_not_approved'},
          }),
        ),
        isFalse,
      );
      expect(isConsentRequiredResponse(res(403, null)), isFalse);
      expect(isConsentRequiredResponse(null), isFalse);
    });
  });

  group('실행 중 403 consent_required', () {
    test('데이터 요청이 거절되면 동의 화면으로 가고, 동의하면 풀린다', () async {
      final ProviderContainer container = await _signedIn(
        <String, (int, Object?)>{
          'GET /diet/today': (403, _consentRequired),
          'POST /users/me/consents': (
            200,
            <String, Object?>{
              'consent_required': false,
              'consent_pending': <String>[],
            },
          ),
        },
      );
      expect(_redirect(container, AppRoutes.dashboard), isNull);

      // 오류는 그대로 화면에 간다 — 화면의 실패 처리는 바뀌지 않는다.
      await expectLater(
        container.read(dioProvider).get<Object?>('/diet/today'),
        throwsA(isA<DioException>()),
      );

      final SessionState s = container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.consentRequired, isTrue);
      expect(_redirect(container, AppRoutes.dashboard), AppRoutes.consent);
      expect(_redirect(container, AppRoutes.myHealth), AppRoutes.consent);

      await container.read(sessionControllerProvider.notifier).submitConsents(
        <String>['terms', 'privacy', 'health', 'age14'],
      );

      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
      expect(_redirect(container, AppRoutes.consent), AppRoutes.dashboard);
    });

    test('다른 403(권한 없음)은 동의 화면으로 보내지 않는다', () async {
      final ProviderContainer container = await _signedIn(
        <String, (int, Object?)>{
          'GET /diet/today': (
            403,
            <String, Object?>{'detail': '회원 전용 API예요.'},
          ),
        },
      );

      await expectLater(
        container.read(dioProvider).get<Object?>('/diet/today'),
        throwsA(isA<DioException>()),
      );

      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
    });

    test('호출부가 직접 토큰을 넣은 요청은 세션의 것이 아니라 무시한다', () async {
      final ProviderContainer container = await _signedIn(
        <String, (int, Object?)>{'GET /diet/today': (403, _consentRequired)},
      );

      await expectLater(
        container
            .read(dioProvider)
            .get<Object?>(
              '/diet/today',
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
      final ProviderContainer container = await _signedIn(
        const <String, (int, Object?)>{},
      );
      await container.read(sessionControllerProvider.notifier).signOut();

      container.read(consentGateBridgeProvider).notify('access-1');

      final SessionState s = container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.signedOut);
      expect(s.consentRequired, isFalse);
      expect(container.read(authAccessTokenProvider), isNull);
    });
  });
}
