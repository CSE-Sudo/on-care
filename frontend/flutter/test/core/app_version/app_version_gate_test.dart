/// 최소 지원 버전 확인(#3045).
///
/// 서버 `/version` 의 `min_app_version` 과 빌드 버전을 비교한다. 확인하지 못하면
/// 평소처럼 진행한다(fail-open). 웹은 확인하지 않는다.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/app_version/app_version.dart';
import 'package:oncare/core/app_version/app_version_gate.dart';
import 'package:oncare/core/network/dio_client.dart';

/// `GET /version` 만 답하는 Dio. [reply] 가 `null` 이면 연결 실패를 낸다.
Dio _versionDio(
  List<String> calls, {
  required Map<String, Object?>? Function() reply,
}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        calls.add('${options.method} ${options.path}');
        final Map<String, Object?>? body = reply();
        if (body == null) {
          handler.reject(
            DioException.connectionError(
              requestOptions: options,
              reason: 'offline',
            ),
          );
          return;
        }
        handler.resolve(
          Response<Map<String, Object?>>(
            requestOptions: options,
            statusCode: 200,
            data: body,
          ),
        );
      },
    ),
  );
  return dio;
}

Future<void> _drain() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('evaluateAppVersion', () {
    AppVersionStatus status(String? current, Object? min) =>
        evaluateAppVersion(current: current, minRaw: min).status;

    test('최소 버전이 없으면(null·빈 값) 검사하지 않는다', () {
      expect(status('0.4.0', null), AppVersionStatus.supported);
      expect(status('0.4.0', ''), AppVersionStatus.supported);
      expect(status('0.4.0', '  '), AppVersionStatus.supported);
      // 빌드 버전을 못 읽어도 막을 이유가 없다.
      expect(status(null, null), AppVersionStatus.supported);
    });

    test('낮으면 업데이트가 필요하다', () {
      expect(status('0.4.0', '0.5.0'), AppVersionStatus.updateRequired);
      expect(status('1.9.0', '1.10.0'), AppVersionStatus.updateRequired);
      expect(status('0.4.0+9', '0.4.1'), AppVersionStatus.updateRequired);
    });

    test('같거나 높으면 지원된다', () {
      expect(status('0.5.0', '0.5.0'), AppVersionStatus.supported);
      expect(status('0.5.0+1', '0.5.0'), AppVersionStatus.supported);
      expect(status('1.10.0', '1.9.0'), AppVersionStatus.supported);
    });

    test('판단할 수 없으면 unknown — 막지 않는다', () {
      expect(status(null, '0.5.0'), AppVersionStatus.unknown);
      expect(status('dev', '0.5.0'), AppVersionStatus.unknown);
      expect(status('0.4.0', 'next'), AppVersionStatus.unknown);
      expect(status('0.4.0', 5), AppVersionStatus.unknown);
      expect(status('0.4.0', <String>['0.5.0']), AppVersionStatus.unknown);
    });

    test('화면에 쓸 두 버전을 함께 싣는다', () {
      final AppVersionGateState s = evaluateAppVersion(
        current: '0.4.0',
        minRaw: '0.5.0',
      );
      expect(s.currentVersion, '0.4.0');
      expect(s.minVersion, '0.5.0');
      expect(s.updateRequired, isTrue);
    });
  });

  group('AppVersionGate', () {
    AppVersionGate gate({
      bool enabled = true,
      String? current = '0.4.0',
      required Future<Map<String, Object?>?> Function() fetch,
      Duration timeout = kAppVersionCheckTimeout,
    }) {
      final AppVersionGate g = AppVersionGate(
        enabled: enabled,
        readCurrentVersion: () async => current,
        fetchVersionInfo: fetch,
        timeout: timeout,
      );
      addTearDown(g.dispose);
      return g;
    }

    test('처음은 unknown 이다', () {
      expect(
        gate(fetch: () async => null).state.status,
        AppVersionStatus.unknown,
      );
    });

    test('서버의 최소 버전보다 낮으면 updateRequired', () async {
      final AppVersionGate g = gate(
        fetch: () async => <String, Object?>{'min_app_version': '0.5.0'},
      );
      await g.check();
      expect(g.state.status, AppVersionStatus.updateRequired);
    });

    test('최소 버전이 null 이면 supported', () async {
      final AppVersionGate g = gate(
        fetch: () async => <String, Object?>{
          'api_version': 'v1',
          'min_app_version': null,
        },
      );
      await g.check();
      expect(g.state.status, AppVersionStatus.supported);
    });

    test('필드가 없는 옛 서버면 supported', () async {
      final AppVersionGate g = gate(
        fetch: () async => <String, Object?>{
          'api_version': 'v1',
          'app_version': '0.4.0',
        },
      );
      await g.check();
      expect(g.state.status, AppVersionStatus.supported);
    });

    test('연결 실패면 unknown 그대로 — 앱은 평소처럼 켜진다', () async {
      final AppVersionGate g = gate(fetch: () async => throw StateError('x'));
      await g.check();
      expect(g.state.status, AppVersionStatus.unknown);
    });

    test('시간 안에 답이 없으면 접는다', () async {
      final Completer<Map<String, Object?>?> never =
          Completer<Map<String, Object?>?>();
      final AppVersionGate g = gate(
        fetch: () => never.future,
        timeout: const Duration(milliseconds: 20),
      );
      await g.check();
      expect(g.state.status, AppVersionStatus.unknown);
    });

    test('빈 응답이면 바꾸지 않는다', () async {
      final AppVersionGate g = gate(fetch: () async => null);
      await g.check();
      expect(g.state.status, AppVersionStatus.unknown);
    });

    test('이미 막았는데 다시 확인이 실패하면 계속 막는다', () async {
      bool offline = false;
      final AppVersionGate g = gate(
        fetch: () async {
          if (offline) throw StateError('offline');
          return <String, Object?>{'min_app_version': '0.5.0'};
        },
      );
      await g.check();
      offline = true;
      await g.check();
      expect(g.state.status, AppVersionStatus.updateRequired);
    });

    test('서버가 최소 버전을 내리면 다시 확인할 때 풀린다', () async {
      String? min = '0.5.0';
      final AppVersionGate g = gate(
        fetch: () async => <String, Object?>{'min_app_version': min},
      );
      await g.check();
      expect(g.state.updateRequired, isTrue);
      min = null;
      await g.check();
      expect(g.state.status, AppVersionStatus.supported);
    });

    test('꺼져 있으면 묻지 않는다', () async {
      int calls = 0;
      final AppVersionGate g = gate(
        enabled: false,
        fetch: () async {
          calls++;
          return <String, Object?>{'min_app_version': '9.9.9'};
        },
      );
      await g.check();
      expect(calls, 0);
      expect(g.state.status, AppVersionStatus.unknown);
    });

    test('동시에 부르면 한 번만 묻는다', () async {
      int calls = 0;
      final Completer<Map<String, Object?>?> gateReply =
          Completer<Map<String, Object?>?>();
      final AppVersionGate g = gate(
        fetch: () {
          calls++;
          return gateReply.future;
        },
      );
      final Future<void> a = g.check();
      final Future<void> b = g.check();
      gateReply.complete(<String, Object?>{'min_app_version': '0.1.0'});
      await Future.wait(<Future<void>>[a, b]);
      expect(calls, 1);
      expect(g.state.status, AppVersionStatus.supported);
    });
  });

  group('appVersionCheckEnabledFor', () {
    test('웹은 확인하지 않는다', () {
      expect(appVersionCheckEnabledFor(isWeb: true), isFalse);
      expect(appVersionCheckEnabledFor(isWeb: false), isTrue);
    });
  });

  group('appVersionGateProvider', () {
    // 실제 이벤트 루프에서 돈다 — provider 를 만들 때 시작하는 /version 요청이
    // testWidgets 의 가짜 시간 안에 묶이면 끝나지 않는다. 앱 수명 주기 소식은
    // 초기화한 테스트 바인딩으로 보낸다.
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();

    late List<String> calls;
    Map<String, Object?>? Function() reply = () => null;

    setUp(() {
      calls = <String>[];
      reply = () => <String, Object?>{'min_app_version': '0.5.0'};
    });

    ProviderContainer container({required bool enabled}) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appVersionCheckEnabledProvider.overrideWithValue(enabled),
          appVersionProvider.overrideWith((ref) async => '0.4.0'),
          dioProvider.overrideWithValue(
            _versionDio(calls, reply: () => reply()),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('기본은 꺼져 있다 — /version 을 부르지 않는다', () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appVersionProvider.overrideWith((ref) async => '0.4.0'),
          dioProvider.overrideWithValue(
            _versionDio(calls, reply: () => reply()),
          ),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(appVersionGateProvider).status, AppVersionStatus.unknown);
      await _drain();
      expect(calls, isEmpty);
    });

    test('켜면 만들 때 한 번 확인한다', () async {
      final ProviderContainer c = container(enabled: true);
      c.read(appVersionGateProvider);
      await _drain();

      expect(calls, <String>['GET /version']);
      expect(
        c.read(appVersionGateProvider).status,
        AppVersionStatus.updateRequired,
      );
      expect(c.read(appVersionGateProvider).minVersion, '0.5.0');
    });

    test('/version 이 실패해도 unknown 이다', () async {
      reply = () => null;
      final ProviderContainer c = container(enabled: true);
      c.read(appVersionGateProvider);
      await _drain();

      expect(c.read(appVersionGateProvider).status, AppVersionStatus.unknown);
    });

    test('백그라운드에서 돌아오면 다시 확인한다', () async {
      reply = () => <String, Object?>{'min_app_version': null};
      final ProviderContainer c = container(enabled: true);
      c.read(appVersionGateProvider);
      await _drain();
      expect(calls, hasLength(1));
      expect(c.read(appVersionGateProvider).status, AppVersionStatus.supported);

      reply = () => <String, Object?>{'min_app_version': '0.5.0'};
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _drain();

      expect(calls, hasLength(2));
      expect(
        c.read(appVersionGateProvider).status,
        AppVersionStatus.updateRequired,
      );
    });
  });
}
