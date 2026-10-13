/// 회원 비밀번호 변경·재설정 리포지토리(#2824).
///
/// 서버 응답(상태 코드·본문)이 화면이 고를 실패 이유로 바르게 바뀌는지, 데모가
/// 무엇을 흉내 내는지, 빌드 설정마다 어느 구현을 쓰는지를 본다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/data/repositories/dio_password_repository.dart';
import 'package:oncare/features/auth/data/repositories/mock_password_repository.dart';
import 'package:oncare/features/auth/domain/password_reset_code.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart';
import 'package:oncare/features/auth/presentation/controllers/password_providers.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppInputError;

/// 한 가지 응답만 주는 Dio. 나간 요청은 [requests] 에 남는다.
class _OneAnswer {
  _OneAnswer(this.status, [this.body]);

  final int status;
  final Object? body;
  final List<RequestOptions> requests = <RequestOptions>[];

  Dio build() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          final Response<Object?> res = Response<Object?>(
            requestOptions: options,
            statusCode: status,
            data: body,
          );
          if (status >= 400) {
            handler.reject(
              DioException.badResponse(
                statusCode: status,
                requestOptions: options,
                response: res,
              ),
            );
          } else {
            handler.resolve(res);
          }
        },
      ),
    );
    return dio;
  }
}

/// 연결이 끊긴 Dio.
Dio _offline() {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.reject(
          DioException.connectionError(requestOptions: options, reason: 'off'),
        );
      },
    ),
  );
  return dio;
}

Map<String, Object?> _weak(String type) => <String, Object?>{
  'detail': <Object?>[
    <String, Object?>{
      'type': type,
      'loc': <Object?>['body', 'new_password'],
    },
  ],
};

Future<PasswordChangeError> _changeFails(Dio dio) async {
  try {
    await DioPasswordRepository(
      dio,
    ).changePassword(currentPassword: 'old-pw-1', newPassword: 'new-pw-2');
  } on PasswordChangeError catch (e) {
    return e;
  }
  fail('PasswordChangeError 를 던지지 않았다');
}

Future<PasswordResetError> _confirmFails(Dio dio) async {
  try {
    await DioPasswordRepository(
      dio,
    ).confirmReset(code: 'ABCD-EFGH-JKMN-PQRS', newPassword: 'new-pw-2');
  } on PasswordResetError catch (e) {
    return e;
  }
  fail('PasswordResetError 를 던지지 않았다');
}

Future<PasswordResetError> _requestFails(Dio dio) async {
  try {
    await DioPasswordRepository(dio).requestReset(email: 'a@example.com');
  } on PasswordResetError catch (e) {
    return e;
  }
  fail('PasswordResetError 를 던지지 않았다');
}

void main() {
  group('ReissuedTokens.fromJson', () {
    test('접근·갱신 토큰을 꺼낸다', () {
      final ReissuedTokens? t = ReissuedTokens.fromJson(<String, Object?>{
        'access_token': 'a1',
        'refresh_token': 'r1',
      });
      expect(t?.access, 'a1');
      expect(t?.refresh, 'r1');
    });

    test('갱신 토큰이 없으면 빈 값', () {
      expect(
        ReissuedTokens.fromJson(<String, Object?>{
          'access_token': 'a1',
        })?.refresh,
        '',
      );
    });

    for (final Object? body in <Object?>[
      null,
      'x',
      <String, Object?>{},
      <String, Object?>{'access_token': ''},
      <String, Object?>{'access_token': 3},
    ]) {
      test('접근 토큰이 없으면 null: $body', () {
        expect(ReissuedTokens.fromJson(body), isNull);
      });
    }
  });

  group('DioPasswordRepository.changePassword', () {
    test('POST /users/me/password 로 보내고 새 토큰을 돌려준다', () async {
      final _OneAnswer server = _OneAnswer(200, <String, Object?>{
        'status': 'changed',
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
        'token_type': 'bearer',
      });
      final ReissuedTokens? tokens = await DioPasswordRepository(
        server.build(),
      ).changePassword(currentPassword: 'old-pw-1', newPassword: 'new-pw-2');
      expect(tokens?.access, 'new-access');
      expect(tokens?.refresh, 'new-refresh');
      final RequestOptions req = server.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/users/me/password');
      expect(req.data, <String, String>{
        'current_password': 'old-pw-1',
        'new_password': 'new-pw-2',
      });
    });

    test('토큰 없는 200 도 성공이다 — 비밀번호는 이미 바뀌었다', () async {
      final _OneAnswer server = _OneAnswer(200, <String, Object?>{
        'status': 'changed',
      });
      expect(
        await DioPasswordRepository(
          server.build(),
        ).changePassword(currentPassword: 'old-pw-1', newPassword: 'new-pw-2'),
        isNull,
      );
    });

    test('400 은 현재 비밀번호 불일치', () async {
      final PasswordChangeError e = await _changeFails(
        _OneAnswer(400, <String, Object?>{
          'detail': '현재 비밀번호가 일치하지 않아요.',
        }).build(),
      );
      expect(e.kind, PasswordChangeFailure.wrongCurrent);
    });

    test('409 는 비밀번호 없는 소셜 계정', () async {
      final PasswordChangeError e = await _changeFails(_OneAnswer(409).build());
      expect(e.kind, PasswordChangeFailure.noPassword);
    });

    for (final (String code, AppInputError reason) in <(String, AppInputError)>[
      ('password_weak', AppInputError.passwordWeak),
      ('password_too_long', AppInputError.passwordTooLong),
      ('password_empty', AppInputError.passwordEmpty),
    ]) {
      test('422 $code 는 새 비밀번호 칸의 이유', () async {
        final PasswordChangeError e = await _changeFails(
          _OneAnswer(422, _weak(code)).build(),
        );
        expect(e.kind, PasswordChangeFailure.newRejected);
        expect(e.reason, reason);
      });
    }

    test('모르는 모양의 422 도 새 비밀번호 칸으로 돌린다', () async {
      final PasswordChangeError e = await _changeFails(
        _OneAnswer(422, <String, Object?>{'detail': 'x'}).build(),
      );
      expect(e.kind, PasswordChangeFailure.newRejected);
      expect(e.reason, AppInputError.passwordWeak);
    });

    test('429 는 너무 잦은 시도', () async {
      expect(
        (await _changeFails(_OneAnswer(429).build())).kind,
        PasswordChangeFailure.tooMany,
      );
    });

    test('500·연결 실패는 일시 오류', () async {
      expect(
        (await _changeFails(_OneAnswer(500).build())).kind,
        PasswordChangeFailure.temporary,
      );
      expect(
        (await _changeFails(_offline())).kind,
        PasswordChangeFailure.temporary,
      );
    });
  });

  group('DioPasswordRepository 재설정', () {
    test('요청은 이메일만 보내고 유효 시간을 읽는다', () async {
      final _OneAnswer server = _OneAnswer(202, <String, Object?>{
        'status': 'requested',
        'expires_in_minutes': 30,
      });
      final PasswordResetRequested sent = await DioPasswordRepository(
        server.build(),
      ).requestReset(email: 'member@example.com');
      expect(sent.expiresInMinutes, 30);
      expect(sent.demoCode, isNull);
      final RequestOptions req = server.requests.single;
      expect(req.path, '/auth/password-reset/request');
      expect(req.data, <String, String>{'email': 'member@example.com'});
    });

    test('요청 503 은 발송 불가, 429 는 너무 잦은 요청', () async {
      expect(
        (await _requestFails(_OneAnswer(503).build())).kind,
        PasswordResetFailure.unavailable,
      );
      expect(
        (await _requestFails(_OneAnswer(429).build())).kind,
        PasswordResetFailure.tooMany,
      );
      expect(
        (await _requestFails(_offline())).kind,
        PasswordResetFailure.temporary,
      );
    });

    test('확인은 정규화한 코드를 보낸다', () async {
      final _OneAnswer server = _OneAnswer(200, <String, Object?>{
        'status': 'reset',
      });
      await DioPasswordRepository(
        server.build(),
      ).confirmReset(code: ' abcd efgh-jkmn pqrs ', newPassword: 'new-pw-2');
      final RequestOptions req = server.requests.single;
      expect(req.path, '/auth/password-reset/confirm');
      expect(req.data, <String, String>{
        'token': 'ABCDEFGHJKMNPQRS',
        'new_password': 'new-pw-2',
      });
    });

    test('확인 400 은 틀리거나 만료된 코드', () async {
      final PasswordResetError e = await _confirmFails(
        _OneAnswer(400, <String, Object?>{
          'detail': <String, Object?>{'code': 'invalid_reset_token'},
        }).build(),
      );
      expect(e.kind, PasswordResetFailure.invalidCode);
    });

    test('확인 422 는 새 비밀번호 칸의 이유', () async {
      final PasswordResetError e = await _confirmFails(
        _OneAnswer(422, _weak('password_weak')).build(),
      );
      expect(e.kind, PasswordResetFailure.newRejected);
      expect(e.reason, AppInputError.passwordWeak);
    });
  });

  group('MockPasswordRepository', () {
    const MockPasswordRepository demo = MockPasswordRepository();

    test('변경은 데모에서 막는다', () async {
      expect(demo.supportsPasswordChange, isFalse);
      await expectLater(
        demo.changePassword(currentPassword: 'a1', newPassword: 'b2'),
        throwsA(
          isA<PasswordChangeError>().having(
            (PasswordChangeError e) => e.kind,
            'kind',
            PasswordChangeFailure.unavailable,
          ),
        ),
      );
    });

    test('요청은 받아 주고 모양이 맞는 데모 코드를 준다', () async {
      final PasswordResetRequested sent = await demo.requestReset(
        email: 'anyone@example.com',
      );
      expect(sent.expiresInMinutes, 30);
      expect(PasswordResetCode.isWellFormed(sent.demoCode!), isTrue);
    });

    test('확인은 모양이 맞는 코드면 성공, 아니면 코드 오류', () async {
      await demo.confirmReset(
        code: MockPasswordRepository.demoCode,
        newPassword: 'new-pw-2',
      );
      await expectLater(
        demo.confirmReset(code: 'nope', newPassword: 'new-pw-2'),
        throwsA(
          isA<PasswordResetError>().having(
            (PasswordResetError e) => e.kind,
            'kind',
            PasswordResetFailure.invalidCode,
          ),
        ),
      );
    });
  });

  group('passwordRepositoryProvider', () {
    PasswordRepository read(AppConfig config) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(config),
          dioProvider.overrideWithValue(_offline()),
        ],
      );
      addTearDown(c.dispose);
      return c.read(passwordRepositoryProvider);
    }

    test('실 서버 빌드는 Dio', () {
      expect(
        read(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://api.test',
            useMockApi: false,
          ),
        ),
        isA<DioPasswordRepository>(),
      );
    });

    test('데모 빌드는 목업', () {
      expect(
        read(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://api.test',
            useMockApi: true,
          ),
        ),
        isA<MockPasswordRepository>(),
      );
    });

    test('인증만 실 서버인 데모는 재설정을 실 서버로, 변경은 데모로', () {
      final PasswordRepository repo = read(
        const AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'https://api.test',
          useMockApi: true,
          realApiFeatures: <String>{'auth'},
        ),
      );
      expect(repo, isA<RealResetDemoChangeRepository>());
      final RealResetDemoChangeRepository split =
          repo as RealResetDemoChangeRepository;
      expect(split.reset, isA<DioPasswordRepository>());
      expect(split.change, isA<MockPasswordRepository>());
      expect(repo.supportsPasswordChange, isFalse);
    });
  });
}
