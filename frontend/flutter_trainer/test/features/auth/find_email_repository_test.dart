/// 트레이너 웹 이메일 찾기 리포지토리(#3439).
///
/// 트레이너 전용 경로를 부르는지, 서버 응답이 화면이 고를 결과·실패로 바르게
/// 바뀌는지, 데모가 서버 규칙(가림·빈 목록)을 흉내 내는지, 빌드 설정마다 어느
/// 구현을 쓰는지를 본다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/auth/data/repositories/find_email_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/find_email_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

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

Future<List<FoundEmailAccount>> _find(Dio dio) =>
    DioFindEmailRepository(dio).find(name: '김코치', phone: '010-1234-5678');

Future<FindEmailFailure> _fails(Dio dio) async {
  try {
    await _find(dio);
  } on FindEmailError catch (e) {
    return e.kind;
  }
  fail('FindEmailError 를 던지지 않았다');
}

void main() {
  group('DioFindEmailRepository', () {
    test('트레이너 전용 경로로 이름·번호를 보낸다', () async {
      final _OneAnswer server = _OneAnswer(200, <String, Object?>{
        'accounts': <Object?>[],
      });
      await _find(server.build());

      expect(server.requests, hasLength(1));
      expect(server.requests.single.path, '/auth/trainer/find-email');
      expect(server.requests.single.data, <String, String>{
        'name': '김코치',
        'phone': '010-1234-5678',
      });
    });

    test('가려진 이메일과 소셜 가입 수단을 읽는다', () async {
      final List<FoundEmailAccount> found = await _find(
        _OneAnswer(200, <String, Object?>{
          'accounts': <Object?>[
            <String, Object?>{
              'masked_email': 'co***@oncare.com',
              'providers': <Object?>[],
            },
            <String, Object?>{
              'masked_email': null,
              'providers': <Object?>['google'],
            },
          ],
        }).build(),
      );

      expect(found, hasLength(2));
      expect(found[0].maskedEmail, 'co***@oncare.com');
      expect(found[0].isSocialOnly, isFalse);
      expect(found[1].maskedEmail, isNull);
      expect(found[1].providers, <String>['google']);
    });

    test('가려지지 않은 이메일은 그리지 않는다', () async {
      final List<FoundEmailAccount> found = await _find(
        _OneAnswer(200, <String, Object?>{
          'accounts': <Object?>[
            <String, Object?>{
              'masked_email': 'coach@oncare.com',
              'providers': <Object?>[],
            },
          ],
        }).build(),
      );
      expect(found, isEmpty);
    });

    test('찾지 못하면 빈 목록이다', () async {
      expect(
        await _find(
          _OneAnswer(200, <String, Object?>{'accounts': <Object?>[]}).build(),
        ),
        isEmpty,
      );
    });

    test('목록이 없는 응답은 찾지 못함이 아니라 일시 실패다', () async {
      expect(
        await _fails(_OneAnswer(200, <String, Object?>{}).build()),
        FindEmailFailure.temporary,
      );
    });

    test('422 · 429 · 그 밖의 실패를 나눈다', () async {
      expect(
        await _fails(_OneAnswer(422).build()),
        FindEmailFailure.invalidInput,
      );
      expect(await _fails(_OneAnswer(429).build()), FindEmailFailure.tooMany);
      expect(await _fails(_OneAnswer(500).build()), FindEmailFailure.temporary);
      expect(await _fails(_offline()), FindEmailFailure.temporary);
    });
  });

  group('MockFindEmailRepository', () {
    const MockFindEmailRepository demo = MockFindEmailRepository();

    test('데모 트레이너의 이름·번호면 가린 이메일 하나를 준다', () async {
      final List<FoundEmailAccount> found = await demo.find(
        name: ' ${seedTrainerProfile.name} ',
        phone: seedTrainerProfile.phone.replaceAll('-', ''),
      );

      expect(found, hasLength(1));
      final String masked = found.single.maskedEmail!;
      expect(masked, contains('***@'));
      expect(masked, isNot(seedTrainerProfile.email));
      expect(
        masked,
        MockFindEmailRepository.maskEmail(seedTrainerProfile.email),
      );
    });

    test('이름이나 번호가 다르면 빈 목록이다', () async {
      expect(
        await demo.find(name: '없는코치', phone: seedTrainerProfile.phone),
        isEmpty,
      );
      expect(
        await demo.find(name: seedTrainerProfile.name, phone: '010-9999-9999'),
        isEmpty,
      );
    });

    test('형식이 틀린 번호는 서버처럼 입력 오류다', () async {
      await expectLater(
        demo.find(name: seedTrainerProfile.name, phone: '0101234'),
        throwsA(isA<FindEmailError>()),
      );
    });

    test('가림은 서버와 같은 규칙이다', () {
      expect(
        MockFindEmailRepository.maskEmail('abcdef@example.com'),
        'ab***@example.com',
      );
      expect(
        MockFindEmailRepository.maskEmail('ab@example.com'),
        'a***@example.com',
      );
      expect(
        MockFindEmailRepository.maskEmail('a@example.com'),
        '***@example.com',
      );
      expect(MockFindEmailRepository.maskEmail('not-an-email'), '***');
    });
  });

  group('findEmailRepositoryProvider', () {
    FindEmailRepository read({required bool mock}) {
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
      return c.read(findEmailRepositoryProvider);
    }

    test('실 서버 빌드는 Dio', () {
      expect(read(mock: false), isA<DioFindEmailRepository>());
    });

    test('데모 빌드는 목업', () {
      expect(read(mock: true), isA<MockFindEmailRepository>());
    });
  });
}
