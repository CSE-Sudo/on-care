/// 기능별 실 백엔드 전환 스위치(`REAL_API`) — #457, 입도 재설계 #616.
///
/// `USE_MOCK_API` 는 전역이라 끄는 순간 로그인·홈·식단·운동·채팅이 한꺼번에 실서버로
/// 넘어간다. 이 스위치는 준비된 기능만 골라 실연동할 수 있게 한다.
///
/// 계약이 두 개다.
///
///  1. **키를 주지 않으면 지금과 완전히 같다.** 배포된 데모가 조용히 실서버를 치기
///     시작하면 안 된다.
///  2. **켜도 열리는 것은 쓰기뿐이다.** 조회까지 열리면 화면의 초기 상태가 데모 것에서
///     서버 것으로 바뀌고, 토큰 없는 데모는 방문자 전원이 계정 하나를 공유하므로
///     남의 기록이 보인다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/interceptors/mock_api_interceptor.dart';

AppConfig _config({Set<String> realApi = const <String>{}}) => AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://example.test/v1',
  useMockApi: true,
  realApiFeatures: realApi,
);

/// 쓰기로 인정하는 메서드. 이 밖의 것을 열려면 이유를 따로 적어야 한다.
const Set<String> _writeMethods = <String>{'POST', 'PUT', 'PATCH', 'DELETE'};

void main() {
  group('AppConfig.isRealApi', () {
    test('키를 주지 않으면 어떤 요청도 실 백엔드로 가지 않는다', () {
      final AppConfig config = _config();

      // 데모 배포가 이 경로다 — 하나라도 true 면 조용히 실서버를 치기 시작한다.
      for (final (String method, String path) in <(String, String)>[
        ('POST', '/ai-coach/chat'),
        ('GET', '/ai-coach/messages'),
        ('POST', '/auth/login'),
        ('POST', '/auth/social/kakao'),
        ('POST', '/diet/analyze'),
        ('GET', '/diet/days/today'),
        ('GET', '/dashboard/summary'),
      ]) {
        expect(config.isRealApi(method, path), isFalse, reason: '$method $path');
      }
    });

    test('AI 코치를 켜도 대화 전송만 열리고 이력 조회는 목업으로 남는다', () {
      final AppConfig config = _config(realApi: <String>{'ai-coach'});

      expect(config.isRealApi('POST', '/ai-coach/chat'), isTrue);

      // #616 의 핵심 회귀. 이력이 서버에서 오면 코치 화면의 초기 상태가 바뀌고,
      // 공유 데모 계정에서는 앞 방문자의 질문이 그대로 보인다.
      expect(config.isRealApi('GET', '/ai-coach/messages'), isFalse);
      expect(config.isRealApi('GET', '/ai-coach/feedback'), isFalse);

      // 켜지 않은 기능은 그대로 목업
      expect(config.isRealApi('POST', '/auth/login'), isFalse);
      expect(config.isRealApi('GET', '/diet/days/today'), isFalse);
    });

    test('식단을 켜도 사진 분석만 열리고 조회·수정·삭제는 목업으로 남는다', () {
      final AppConfig config = _config(realApi: <String>{'diet'});

      expect(config.isRealApi('POST', '/diet/analyze'), isTrue);

      // 조회가 열리면 데모의 끼니 기록이 서버 시드로 바뀐다.
      expect(config.isRealApi('GET', '/diet/days/today'), isFalse);
      expect(config.isRealApi('GET', '/diet/days/2026-08-11'), isFalse);
      expect(config.isRealApi('GET', '/diet/recommendations'), isFalse);
      expect(config.isRealApi('PUT', '/diet/entries/abc'), isFalse);
      expect(config.isRealApi('DELETE', '/diet/entries/abc'), isFalse);
    });

    test('여러 기능을 함께 켤 수 있다', () {
      final AppConfig config = _config(realApi: <String>{'ai-coach', 'auth'});

      expect(config.isRealApi('POST', '/ai-coach/chat'), isTrue);
      expect(config.isRealApi('POST', '/auth/social/google'), isTrue);
      expect(config.isRealApi('POST', '/diet/analyze'), isFalse);
    });

    test('같은 경로라도 메서드가 다르면 열리지 않는다', () {
      final AppConfig config = _config(realApi: <String>{'diet'});

      expect(config.isRealApi('POST', '/diet/analyze'), isTrue);
      expect(config.isRealApi('GET', '/diet/analyze'), isFalse);
    });

    test('메서드 대소문자는 가리지 않는다', () {
      final AppConfig config = _config(realApi: <String>{'diet'});

      expect(config.isRealApi('post', '/diet/analyze'), isTrue);
    });

    test('알 수 없는 키는 아무 요청도 열지 않는다', () {
      // 오타가 조용히 전 기능을 실서버로 보내면 최악이다.
      final AppConfig config = _config(realApi: <String>{'ai_coach', 'typo'});

      expect(config.isRealApi('POST', '/ai-coach/chat'), isFalse);
      expect(config.isRealApi('POST', '/auth/login'), isFalse);
    });

    test('등록된 기능 키는 모두 엔드포인트가 정의돼 있다', () {
      for (final MapEntry<String, List<RealApiRoute>> entry
          in kRealApiFeatures.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} 에 엔드포인트가 없다');
        for (final RealApiRoute route in entry.value) {
          expect(route.pathPrefix.startsWith('/'), isTrue, reason: route.pathPrefix);
          expect(
            route.method,
            equals(route.method.toUpperCase()),
            reason: '${route.method} 는 대문자로 적는다',
          );
        }
      }
    });

    test('등록된 엔드포인트는 전부 쓰기다', () {
      // 조회를 여는 순간 데모 화면의 초기 상태가 움직인다(#616). 정말 열어야 한다면
      // 이 테스트를 고치면서 왜 열어도 되는지 함께 적는다.
      for (final MapEntry<String, List<RealApiRoute>> entry
          in kRealApiFeatures.entries) {
        for (final RealApiRoute route in entry.value) {
          expect(
            _writeMethods,
            contains(route.method),
            reason: '${entry.key} 가 조회(${route.method} ${route.pathPrefix})를 연다',
          );
        }
      }
    });
  });

  group('MockApiInterceptor', () {
    late Logger logger;

    setUp(() => logger = Logger(level: Level.off));

    /// 인터셉터가 목업 응답으로 가로챘는지(resolve), 흘려보냈는지(next) 판정.
    Future<bool> intercepted(
      MockApiInterceptor interceptor,
      String path, {
      String method = 'GET',
    }) async {
      final options = RequestOptions(path: path, method: method);
      bool resolved = false;
      final handler = _RecordingHandler(onResolve: () => resolved = true);
      interceptor.onRequest(options, handler);
      return resolved;
    }

    test('스위치가 꺼져 있으면 알려진 경로를 그대로 가로챈다', () async {
      final interceptor = MockApiInterceptor(logger);
      expect(await intercepted(interceptor, '/ping'), isTrue);
    });

    test('스위치가 켜진 요청은 가로채지 않고 흘려보낸다', () async {
      final interceptor = MockApiInterceptor(
        logger,
        isRealApi: (String method, String path) =>
            method == 'GET' && path.startsWith('/ping'),
      );
      expect(await intercepted(interceptor, '/ping'), isFalse);
    });

    test('메서드가 다르면 스위치가 켜져 있어도 가로챈다', () async {
      final interceptor = MockApiInterceptor(
        logger,
        isRealApi: (String method, String path) =>
            method == 'POST' && path.startsWith('/ping'),
      );
      expect(await intercepted(interceptor, '/ping'), isTrue);
    });
  });
}

/// resolve/next 중 무엇이 불렸는지만 기록하는 핸들러.
class _RecordingHandler extends RequestInterceptorHandler {
  _RecordingHandler({required this.onResolve});

  final void Function() onResolve;

  @override
  void resolve(Response<dynamic> response, [bool callFollowingResponseInterceptor = false]) {
    onResolve();
  }

  @override
  void next(RequestOptions requestOptions) {}
}
