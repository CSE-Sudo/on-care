/// 세션이 서버의 `consent_required` 를 들고 다니는 경로 — #2819.
///
/// 로그인·소셜 로그인 응답과 저장된 세션 복구(`GET /users/me`)가 같은 값을 읽고,
/// 동의 화면의 저장(`POST /users/me/consents`)이 그 값을 푼다. 가입은 체크한
/// 항목을 `consents` 로 보낸다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/domain/signup_consent.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

/// `METHOD /path` → (상태, 본문). 없는 경로는 404.
class _Server {
  _Server(this.routes);

  final Map<String, (int, Map<String, Object?>?)> routes;
  final List<RequestOptions> requests = <RequestOptions>[];

  late final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          final (int, Map<String, Object?>?)? hit =
              routes['${options.method.toUpperCase()} ${options.path}'];
          final int status = hit?.$1 ?? 404;
          final Response<Object?> response = Response<Object?>(
            requestOptions: options,
            statusCode: status,
            data: hit?.$2 ?? <String, Object?>{},
          );
          if (status >= 400) {
            handler.reject(
              DioException.badResponse(
                statusCode: status,
                requestOptions: options,
                response: response,
              ),
            );
            return;
          }
          handler.resolve(response);
        },
      ),
    );

  RequestOptions last(String path) =>
      requests.lastWhere((RequestOptions r) => r.path == path);
}

const Map<String, Object?> _tokens = <String, Object?>{
  'access_token': 'access-1',
  'refresh_token': 'refresh-1',
};

ProviderContainer _container(_Server server) {
  addTearDown(server.dio.close);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      dioProvider.overrideWithValue(server.dio),
      sessionFeatureResetOverride(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle(ProviderContainer container) async {
  for (int i = 0; i < 40; i++) {
    final SessionState s = container.read(sessionControllerProvider);
    if (s.status != SessionStatus.unknown || s.restoreFailed) {
      for (int tick = 0; tick < 5; tick++) {
        await Future<void>.delayed(Duration.zero);
      }
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('세션 상태가 정해지지 않았다');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('consentRequiredIn', () {
    test('참일 때만 참이다 — 칸이 없거나 다른 값이면 거짓', () {
      expect(
        consentRequiredIn(<String, Object?>{'consent_required': true}),
        isTrue,
      );
      expect(
        consentRequiredIn(<String, Object?>{'consent_required': false}),
        isFalse,
      );
      expect(consentRequiredIn(<String, Object?>{}), isFalse);
      expect(consentRequiredIn(null), isFalse);
      expect(
        consentRequiredIn(<String, Object?>{'consent_required': 'true'}),
        isFalse,
      );
    });
  });

  group('로그인', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

    test('응답이 동의를 요구하면 세션이 그 사실을 든다', () async {
      final _Server server = _Server(<String, (int, Map<String, Object?>?)>{
        'POST /auth/login': (
          200,
          <String, Object?>{..._tokens, 'consent_required': true},
        ),
      });
      final ProviderContainer container = _container(server);
      await _settle(container);

      await container
          .read(sessionControllerProvider.notifier)
          .login(email: 'm@example.com', password: 'pw-12345678');

      final SessionState s = container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.consentRequired, isTrue);
    });

    test('칸이 없는 응답(옛 서버)은 동의를 요구하지 않는다', () async {
      final _Server server = _Server(<String, (int, Map<String, Object?>?)>{
        'POST /auth/login': (200, _tokens),
      });
      final ProviderContainer container = _container(server);
      await _settle(container);

      await container
          .read(sessionControllerProvider.notifier)
          .login(email: 'm@example.com', password: 'pw-12345678');

      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
    });

    test('소셜 첫 로그인도 같은 값을 읽는다', () async {
      final _Server server = _Server(<String, (int, Map<String, Object?>?)>{
        'POST /auth/social/kakao': (
          200,
          <String, Object?>{..._tokens, 'consent_required': true},
        ),
      });
      final ProviderContainer container = _container(server);
      await _settle(container);

      await container
          .read(sessionControllerProvider.notifier)
          .socialLogin(provider: 'kakao', token: 'kakao-token');

      expect(container.read(sessionControllerProvider).consentRequired, isTrue);
    });

    test('데모는 계정이 없어 동의를 묻지 않는다', () async {
      final ProviderContainer container = _container(
        _Server(<String, (int, Map<String, Object?>?)>{}),
      );
      await _settle(container);

      container.read(sessionControllerProvider.notifier).enterDemo();

      final SessionState s = container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.demo);
      expect(s.consentRequired, isFalse);
    });
  });

  group('세션 복구', () {
    setUp(
      () => FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
        'refresh_token': 'stored-refresh',
      }),
    );

    test('기존 가입자는 되살아난 세션에서도 동의 화면을 거친다', () async {
      final ProviderContainer container = _container(
        _Server(<String, (int, Map<String, Object?>?)>{
          'GET /users/me': (
            200,
            <String, Object?>{
              'id': 'u1',
              'consent_required': true,
              'consent_pending': <String>['health', 'privacy'],
            },
          ),
        }),
      );
      container.read(sessionControllerProvider.notifier);
      await _settle(container);

      final SessionState s = container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.consentRequired, isTrue);
    });

    test('동의를 마친 계정은 그대로 들어간다', () async {
      final ProviderContainer container = _container(
        _Server(<String, (int, Map<String, Object?>?)>{
          'GET /users/me': (
            200,
            <String, Object?>{'id': 'u1', 'consent_required': false},
          ),
        }),
      );
      container.read(sessionControllerProvider.notifier);
      await _settle(container);

      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
    });
  });

  group('동의 저장', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

    test('체크한 항목을 보내고, 서버가 풀어 주면 동의 요구가 사라진다', () async {
      final _Server server = _Server(<String, (int, Map<String, Object?>?)>{
        'POST /auth/login': (
          200,
          <String, Object?>{..._tokens, 'consent_required': true},
        ),
        'POST /users/me/consents': (
          200,
          <String, Object?>{
            'consent_required': false,
            'consent_pending': <String>[],
          },
        ),
      });
      final ProviderContainer container = _container(server);
      await _settle(container);
      final SessionController controller = container.read(
        sessionControllerProvider.notifier,
      );
      await controller.login(email: 'm@example.com', password: 'pw-12345678');

      await controller.submitConsents(<String>[
        'terms',
        'privacy',
        'health',
        'age14',
      ]);

      expect(
        (server.last('/users/me/consents').data
            as Map<String, Object?>)['consents'],
        <String>['terms', 'privacy', 'health', 'age14'],
      );
      final SessionState s = container.read(sessionControllerProvider);
      expect(s.status, SessionStatus.authenticated);
      expect(s.consentRequired, isFalse);
    });

    test('서버가 거절하면(422) 던지고 동의 요구는 그대로다', () async {
      final _Server server = _Server(<String, (int, Map<String, Object?>?)>{
        'POST /auth/login': (
          200,
          <String, Object?>{..._tokens, 'consent_required': true},
        ),
        'POST /users/me/consents': (
          422,
          <String, Object?>{
            'detail': <String, Object?>{
              'code': 'consent_required',
              'missing': <String>['health'],
            },
          },
        ),
      });
      final ProviderContainer container = _container(server);
      await _settle(container);
      final SessionController controller = container.read(
        sessionControllerProvider.notifier,
      );
      await controller.login(email: 'm@example.com', password: 'pw-12345678');

      await expectLater(
        controller.submitConsents(<String>['terms']),
        throwsA(isA<DioException>()),
      );
      expect(container.read(sessionControllerProvider).consentRequired, isTrue);
    });

    test('저장하는 사이 로그아웃했다면 결과로 세션을 되살리지 않는다', () async {
      final _Server server = _Server(<String, (int, Map<String, Object?>?)>{
        'POST /auth/login': (
          200,
          <String, Object?>{..._tokens, 'consent_required': true},
        ),
        'POST /auth/logout': (204, null),
        'POST /users/me/consents': (
          200,
          <String, Object?>{'consent_required': false},
        ),
      });
      final ProviderContainer container = _container(server);
      await _settle(container);
      final SessionController controller = container.read(
        sessionControllerProvider.notifier,
      );
      await controller.login(email: 'm@example.com', password: 'pw-12345678');

      final Future<void> saving = controller.submitConsents(
        SignupConsent.memberRequired.toList(),
      );
      await controller.signOut();
      await saving;

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
    });
  });

  group('가입', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

    test('체크한 동의를 가입 요청에 싣는다', () async {
      final _Server server = _Server(<String, (int, Map<String, Object?>?)>{
        'POST /auth/register': (
          201,
          <String, Object?>{
            'id': 'u1',
            'name': '김민수',
            'email': 'new@example.com',
          },
        ),
        'POST /auth/login': (200, _tokens),
      });
      final ProviderContainer container = _container(server);
      await _settle(container);

      await container
          .read(sessionControllerProvider.notifier)
          .register(
            email: 'new@example.com',
            password: 'pw-12345678',
            emailCode: '123456',
            name: '김민수',
            consents: SignupConsent.toPayload(<String>{
              'age14',
              'terms',
              'health',
              'privacy',
              'marketing',
            }),
          );

      final Map<String, Object?> body =
          server.last('/auth/register').data as Map<String, Object?>;
      // 가입 이메일 인증 코드도 같은 본문에 실린다(#3038).
      expect(body['email_code'], '123456');
      expect(body['consents'], <String>[
        'terms',
        'privacy',
        'health',
        'age14',
        'marketing',
      ]);
      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
    });

    test('동의 목록을 주지 않으면 칸 자체를 보내지 않는다', () async {
      final _Server server = _Server(<String, (int, Map<String, Object?>?)>{
        'POST /auth/register': (201, <String, Object?>{'id': 'u1'}),
        'POST /auth/login': (200, _tokens),
      });
      final ProviderContainer container = _container(server);
      await _settle(container);

      await container
          .read(sessionControllerProvider.notifier)
          .register(
            email: 'new@example.com',
            password: 'pw-12345678',
            emailCode: '123456',
          );

      final Map<String, Object?> body =
          server.last('/auth/register').data as Map<String, Object?>;
      expect(body.containsKey('consents'), isFalse);
    });
  });
}
