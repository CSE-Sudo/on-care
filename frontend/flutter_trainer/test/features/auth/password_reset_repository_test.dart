/// 트레이너 웹 비밀번호 재설정 리포지토리(#2824).
///
/// 서버 응답이 화면이 고를 실패 이유로 바르게 바뀌는지, 데모가 무엇을 흉내
/// 내는지, 빌드 설정마다 어느 구현을 쓰는지를 본다. 규약은 회원 앱과 같다 —
/// 두 앱이 같은 엔드포인트를 쓴다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/auth/data/repositories/password_reset_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/password_reset_code.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/password_reset_repository.dart';
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

Future<PasswordResetError> _requestFails(Dio dio) async {
  try {
    await DioPasswordResetRepository(dio).requestReset(email: 'a@example.com');
  } on PasswordResetError catch (e) {
    return e;
  }
  fail('PasswordResetError 를 던지지 않았다');
}

Future<PasswordResetError> _confirmFails(Dio dio) async {
  try {
    await DioPasswordResetRepository(
      dio,
    ).confirmReset(code: 'ABCD-EFGH-JKMN-PQRS', newPassword: 'new-pw-2');
  } on PasswordResetError catch (e) {
    return e;
  }
  fail('PasswordResetError 를 던지지 않았다');
}

void main() {
  group('DioPasswordResetRepository', () {
    test('요청은 이메일만 보내고 유효 시간을 읽는다', () async {
      final _OneAnswer server = _OneAnswer(202, <String, Object?>{
        'status': 'requested',
        'expires_in_minutes': 30,
      });
      final PasswordResetRequested sent = await DioPasswordResetRepository(
        server.build(),
      ).requestReset(email: 'trainer@example.com');
      expect(sent.expiresInMinutes, 30);
      expect(sent.demoCode, isNull);
      final RequestOptions req = server.requests.single;
      expect(req.path, '/auth/password-reset/request');
      expect(req.data, <String, String>{'email': 'trainer@example.com'});
    });

    test('유효 시간이 없는 응답도 요청 성공이다', () async {
      final PasswordResetRequested sent = await DioPasswordResetRepository(
        _OneAnswer(202, <String, Object?>{'status': 'requested'}).build(),
      ).requestReset(email: 'trainer@example.com');
      expect(sent.expiresInMinutes, 0);
    });

    test('요청 503 은 발송 불가, 429 는 너무 잦은 요청, 연결 실패는 일시 오류', () async {
      expect(
        (await _requestFails(_OneAnswer(503).build())).kind,
        PasswordResetFailure.unavailable,
      );
      expect(
        (await _requestFails(_OneAnswer(429).build())).kind,
        PasswordResetFailure.tooMany,
      );
      expect(
        (await _requestFails(_OneAnswer(500).build())).kind,
        PasswordResetFailure.temporary,
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
      await DioPasswordResetRepository(
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

    for (final (String type, AppInputError reason) in <(String, AppInputError)>[
      ('password_weak', AppInputError.passwordWeak),
      ('password_too_long', AppInputError.passwordTooLong),
    ]) {
      test('확인 422 $type 은 새 비밀번호 칸의 이유', () async {
        final PasswordResetError e = await _confirmFails(
          _OneAnswer(422, _weak(type)).build(),
        );
        expect(e.kind, PasswordResetFailure.newRejected);
        expect(e.reason, reason);
      });
    }

    test('확인 429 는 너무 잦은 시도', () async {
      expect(
        (await _confirmFails(_OneAnswer(429).build())).kind,
        PasswordResetFailure.tooMany,
      );
    });
  });

  group('MockPasswordResetRepository', () {
    const MockPasswordResetRepository demo = MockPasswordResetRepository();

    test('요청은 받아 주고 모양이 맞는 데모 코드를 준다', () async {
      final PasswordResetRequested sent = await demo.requestReset(
        email: 'demo@example.com',
      );
      expect(sent.expiresInMinutes, 30);
      expect(sent.demoCode, MockPasswordResetRepository.demoCode);
      expect(PasswordResetCode.isWellFormed(sent.demoCode!), isTrue);
    });

    test('확인은 모양이 맞는 코드면 성공, 아니면 코드 오류', () async {
      await demo.confirmReset(
        code: MockPasswordResetRepository.demoCode,
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

  group('passwordResetRepositoryProvider', () {
    PasswordResetRepository read({required bool mock}) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://api.test',
              useMockApi: mock,
            ),
          ),
          dioProvider.overrideWithValue(_offline()),
        ],
      );
      addTearDown(c.dispose);
      return c.read(passwordResetRepositoryProvider);
    }

    test('실 서버 빌드는 Dio', () {
      expect(read(mock: false), isA<DioPasswordResetRepository>());
    });

    test('데모 빌드는 목업', () {
      expect(read(mock: true), isA<MockPasswordResetRepository>());
    });
  });
}
