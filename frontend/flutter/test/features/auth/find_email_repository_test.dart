/// 아이디(가입 이메일) 찾기 저장소와 응답 해석 — #3337.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/auth/data/repositories/dio_find_email_repository.dart';
import 'package:oncare/features/auth/domain/find_email.dart';

/// 정해 둔 상태 코드·본문으로 답하고, 받은 요청을 적어 두는 대역.
class _Server extends Interceptor {
  _Server(this.status, [this.body]);

  final int status;
  final Object? body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final Response<Object?> response = Response<Object?>(
      requestOptions: options,
      statusCode: status,
      data: body,
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
  }
}

/// 응답 없이 끊기는 연결.
class _Offline extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException.connectionError(requestOptions: options, reason: 'offline'),
    );
  }
}

(DioFindEmailRepository, _Server) _repo(int status, [Object? body]) {
  final _Server server = _Server(status, body);
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
    ..interceptors.add(server);
  addTearDown(dio.close);
  return (DioFindEmailRepository(dio), server);
}

Future<List<FoundEmailAccount>> _find(DioFindEmailRepository repo) =>
    repo.find(name: '김온케어', phone: '010-1234-5678');

Matcher _failsWith(FindEmailFailure kind) => throwsA(
  isA<FindEmailError>().having((FindEmailError e) => e.kind, 'kind', kind),
);

void main() {
  group('DioFindEmailRepository', () {
    test('이름과 번호를 보내고 가려진 이메일을 읽는다', () async {
      final (DioFindEmailRepository repo, _Server server) = _repo(
        200,
        <String, Object?>{
          'accounts': <Object?>[
            <String, Object?>{
              'masked_email': 'on***@oncare.com',
              'providers': <Object?>[],
            },
          ],
        },
      );

      final List<FoundEmailAccount> found = await _find(repo);

      expect(server.requests.single.method, 'POST');
      expect(server.requests.single.path, '/auth/find-email');
      expect(server.requests.single.data, <String, String>{
        'name': '김온케어',
        'phone': '010-1234-5678',
      });
      expect(found, hasLength(1));
      expect(found.single.maskedEmail, 'on***@oncare.com');
      expect(found.single.providers, isEmpty);
      expect(found.single.isSocialOnly, isFalse);
    });

    test('맞는 계정이 없으면 실패가 아니라 빈 목록이다', () async {
      final (DioFindEmailRepository repo, _) = _repo(200, <String, Object?>{
        'accounts': <Object?>[],
      });
      expect(await _find(repo), isEmpty);
    });

    test('소셜 가입 계정은 이메일 없이 가입 수단만 읽는다', () async {
      final (DioFindEmailRepository repo, _) = _repo(200, <String, Object?>{
        'accounts': <Object?>[
          <String, Object?>{
            'masked_email': null,
            'providers': <Object?>['kakao', 'google'],
          },
        ],
      });

      final FoundEmailAccount account = (await _find(repo)).single;
      expect(account.maskedEmail, isNull);
      expect(account.isSocialOnly, isTrue);
      expect(account.providers, <String>['kakao', 'google']);
    });

    test('여러 계정은 서버가 준 순서대로 읽는다', () async {
      final (DioFindEmailRepository repo, _) = _repo(200, <String, Object?>{
        'accounts': <Object?>[
          <String, Object?>{'masked_email': 'al***@oncare.com'},
          <String, Object?>{
            'masked_email': 'br***@example.com',
            'providers': <Object?>['google'],
          },
        ],
      });

      final List<FoundEmailAccount> found = await _find(repo);
      expect(found.map((FoundEmailAccount a) => a.maskedEmail), <String>[
        'al***@oncare.com',
        'br***@example.com',
      ]);
      expect(found.last.providers, <String>['google']);
    });

    test('모양이 어긋난 항목은 건너뛴다', () async {
      final (DioFindEmailRepository repo, _) = _repo(200, <String, Object?>{
        'accounts': <Object?>[
          'nope',
          <String, Object?>{},
          <String, Object?>{'masked_email': 42, 'providers': 'kakao'},
          <String, Object?>{'masked_email': 'on***@oncare.com'},
        ],
      });
      expect((await _find(repo)).single.maskedEmail, 'on***@oncare.com');
    });

    test('목록이 없는 응답은 찾지 못함이 아니라 실패다', () async {
      final (DioFindEmailRepository repo, _) = _repo(200, <String, Object?>{});
      await expectLater(_find(repo), _failsWith(FindEmailFailure.temporary));
    });

    test('상태 코드를 화면이 고를 이유로 바꾼다', () async {
      const Map<int, FindEmailFailure> expected = <int, FindEmailFailure>{
        422: FindEmailFailure.invalidInput,
        429: FindEmailFailure.tooMany,
        500: FindEmailFailure.temporary,
        503: FindEmailFailure.temporary,
      };
      for (final MapEntry<int, FindEmailFailure> e in expected.entries) {
        final (DioFindEmailRepository repo, _) = _repo(e.key);
        await expectLater(_find(repo), _failsWith(e.value));
      }
    });

    test('연결이 끊기면 다시 해 볼 수 있는 실패다', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
        ..interceptors.add(_Offline());
      addTearDown(dio.close);
      await expectLater(
        _find(DioFindEmailRepository(dio)),
        _failsWith(FindEmailFailure.temporary),
      );
    });
  });

  group('FoundEmailAccount.fromJson', () {
    test('가려지지 않은 이메일은 받지 않는다', () {
      // 서버가 실수로 전체 이메일을 실어도 화면에 그리지 않는다.
      expect(
        FoundEmailAccount.fromJson(<String, Object?>{
          'masked_email': 'whole@oncare.com',
        }),
        isNull,
      );
      final FoundEmailAccount? social = FoundEmailAccount.fromJson(
        <String, Object?>{
          'masked_email': 'whole@oncare.com',
          'providers': <Object?>['kakao'],
        },
      );
      expect(social?.maskedEmail, isNull);
      expect(social?.providers, <String>['kakao']);
    });

    test('빈 가입 수단 이름은 버린다', () {
      final FoundEmailAccount? account = FoundEmailAccount.fromJson(
        <String, Object?>{
          'masked_email': 'on***@oncare.com',
          'providers': <Object?>['', 7, 'kakao'],
        },
      );
      expect(account?.providers, <String>['kakao']);
    });
  });
}
