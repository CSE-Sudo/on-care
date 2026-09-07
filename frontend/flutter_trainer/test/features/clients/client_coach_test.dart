import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_coach_repository.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body) => Response<T>(
  requestOptions: RequestOptions(path: '/trainer/clients/m1/ai-coach'),
  statusCode: 200,
  data: body,
);

DioException _httpError(int status, {Object? body}) => DioException(
  requestOptions: RequestOptions(path: '/trainer/clients/m1/ai-coach'),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: '/trainer/clients/m1/ai-coach'),
    statusCode: status,
    data: body,
  ),
);

const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

const AppConfig _real = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

void main() {
  late _MockDio dio;
  late DioClientCoachRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioClientCoachRepository(dio);
  });

  void stubPost(Object answer) {
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/ai-coach',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok<Map<String, Object?>>(answer as Map<String, Object?>));
  }

  group('실 백엔드 저장소', () {
    test('답변과 근거를 읽는다', () async {
      stubPost(<String, Object?>{
        'member_id': 'm1',
        'reply': '나트륨을 줄이려면 국물을 남기도록 안내해 보세요.',
        'sources': <Object?>['고혈압 식이 가이드', '회원 최근 7일 식단'],
      });

      final answer = await repo.ask(memberId: 'm1', message: '나트륨이 높아요');

      expect(answer.reply, contains('국물'));
      expect(answer.sources, hasLength(2));
    });

    test('근거가 비어 있어도 답변은 온다', () async {
      // 회원 기록만으로 답한 경우다 — 근거 목록이 비는 것이 정상이다.
      stubPost(<String, Object?>{'member_id': 'm1', 'reply': '괜찮아요'});

      final answer = await repo.ask(memberId: 'm1', message: '어때요?');

      expect(answer.reply, '괜찮아요');
      expect(answer.sources, isEmpty);
    });

    test('근거 목록의 빈 문자열은 걸러낸다', () async {
      stubPost(<String, Object?>{
        'member_id': 'm1',
        'reply': 'ok',
        'sources': <Object?>['가이드', '  ', 3],
      });

      final answer = await repo.ask(memberId: 'm1', message: 'q');

      expect(answer.sources, <String>['가이드']);
    });

    test('질문을 그대로 실어 보낸다', () async {
      stubPost(<String, Object?>{'member_id': 'm1', 'reply': 'ok'});

      await repo.ask(memberId: 'm1', message: '나트륨이 높아요');

      final data =
          verify(
                () => dio.post<Map<String, Object?>>(
                  '/trainer/clients/m1/ai-coach',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(data['message'], '나트륨이 높아요');
    });

    test('회원 id 를 경로에 percent-encode 한다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/a%2Fb/ai-coach',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{'reply': 'ok'}),
      );

      await repo.ask(memberId: 'a/b', message: 'q');

      verify(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/a%2Fb/ai-coach',
          data: any(named: 'data'),
        ),
      ).called(1);
    });

    test('404 는 담당 회원이 아니라는 뜻으로 옮긴다', () async {
      // 서버가 남의 회원을 404 로 감춘다 — 트레이너에게는 담당이 아니라는
      // 사실이 필요한 정보다.
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/m1/ai-coach',
          data: any(named: 'data'),
        ),
      ).thenThrow(_httpError(404));

      await expectLater(
        repo.ask(memberId: 'm1', message: 'q'),
        // 404 를 NotFoundError 로 옮기는 것까지가 리포지토리의 일이다.
        // 문구는 화면이 자기 로케일로 붙이므로 여기서는 타입만 본다. (#501)
        throwsA(isA<NotFoundError>()),
      );
    });

    test('400 은 서버 사유를 그대로 보여준다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/m1/ai-coach',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError(400, body: <String, Object?>{'detail': '메시지가 비어 있습니다.'}),
      );

      await expectLater(
        repo.ask(memberId: 'm1', message: 'q'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            '메시지가 비어 있습니다.',
          ),
        ),
      );
    });
  });

  group('provider 분기', () {
    test('데모는 물어볼 수 없고 진입점도 숨긴다', () {
      final container = ProviderContainer(
        overrides: <Override>[appConfigProvider.overrideWithValue(_demo)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(clientCoachRepositoryProvider),
        isA<DemoClientCoachRepository>(),
      );
      // 데모 회원 상세는 지금과 같아야 한다 — 버튼이 아예 그려지지 않는다.
      expect(container.read(clientCoachEnabledProvider), isFalse);
    });

    test('실모드는 백엔드를 쓴다', () {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(clientCoachRepositoryProvider),
        isA<DioClientCoachRepository>(),
      );
      expect(container.read(clientCoachEnabledProvider), isTrue);
    });

    test('데모 저장소는 요청을 흉내내지 않고 거절한다', () async {
      const repo = DemoClientCoachRepository();

      await expectLater(
        repo.ask(memberId: 'm1', message: 'q'),
        throwsA(isA<ValidationError>()),
      );
    });
  });
}
