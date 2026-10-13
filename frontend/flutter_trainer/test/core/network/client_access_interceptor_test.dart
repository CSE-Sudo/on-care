import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/network/interceptors/client_access_interceptor.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

/// Answers each request from [respond] and records every path it saw.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final (int, Object?) Function(RequestOptions options) respond;
  final List<String> paths = <String>[];

  int countOf(String path) => paths.where((String p) => p == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.uri.path);
    final (int status, Object? body) = respond(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _guard = '담당 회원을 찾을 수 없어요.';

Dio _dioWith(_FakeAdapter adapter, void Function(String) onLost) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: 'http://localhost/v1',
      validateStatus: (int? s) => s != null && s < 400,
    ),
  )..httpClientAdapter = adapter;
  dio.interceptors.add(ClientAccessInterceptor(onLost));
  return dio;
}

Map<String, Object?> _rosterRow(String id, {bool registered = true}) =>
    <String, Object?>{'id': id, 'name': id, 'registered': registered};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scopedClientId', () {
    test('member data endpoints yield the member id', () {
      for (final String path in <String>[
        '/trainer/clients/m1/diet',
        '/v1/trainer/clients/m1/diet',
        '/v1/trainer/clients/m1/diet/photos/p1',
        '/v1/trainer/clients/m1/chat/read',
        '/v1/trainer/clients/m1/report/summary',
        '/v1/trainer/clients/m1/memos/memo-1',
        '/v1/trainer/clients/m1/report',
        'http://localhost/v1/trainer/clients/m1/routines',
      ]) {
        expect(
          ClientAccessInterceptor.scopedClientId(path),
          'm1',
          reason: path,
        );
      }
    });

    test('an encoded id is decoded', () {
      expect(
        ClientAccessInterceptor.scopedClientId(
          '/v1/trainer/clients/user%20kim/diet',
        ),
        'user kim',
      );
    });

    test('roster, the link itself and non-member paths yield null', () {
      for (final String path in <String>[
        '/v1/trainer/clients',
        '/v1/trainer/clients/',
        // 담당 해제 자체
        '/v1/trainer/clients/m1',
        // 링크 관리 — 404·409 가 원래 링크 상태를 말한다
        '/v1/trainer/clients/m1/registration',
        '/v1/trainer/clients/m1/status',
        '/v1/trainer/schedule',
        '/v1/trainer/follow-ups/task-1',
        '/v1/trainer/routine-suggestions/s1/approve',
        '/v1/me/coach',
        '',
      ]) {
        expect(
          ClientAccessInterceptor.scopedClientId(path),
          isNull,
          reason: path,
        );
      }
    });
  });

  group('onError', () {
    Future<List<String>> lostAfter(int status, String path) async {
      final List<String> lost = <String>[];
      final _FakeAdapter adapter = _FakeAdapter(
        (_) => (status, <String, Object?>{'detail': _guard}),
      );
      final Dio dio = _dioWith(adapter, lost.add);
      await expectLater(dio.get<Object?>(path), throwsA(isA<DioException>()));
      return lost;
    }

    test('a 404 on member data reports the member', () async {
      expect(await lostAfter(404, '/trainer/clients/m1/memos'), <String>['m1']);
    });

    test('other statuses do not report', () async {
      for (final int status in <int>[400, 401, 403, 409, 422, 500]) {
        expect(
          await lostAfter(status, '/trainer/clients/m1/memos'),
          isEmpty,
          reason: '$status',
        );
      }
    });

    test('a 404 outside member data does not report', () async {
      expect(await lostAfter(404, '/trainer/schedule/s1'), isEmpty);
      expect(await lostAfter(404, '/trainer/clients/m1'), isEmpty);
      expect(await lostAfter(404, '/trainer/clients/m1/registration'), isEmpty);
    });

    test('a success does not report', () async {
      final List<String> lost = <String>[];
      final Dio dio = _dioWith(
        _FakeAdapter((_) => (200, <Object?>[])),
        lost.add,
      );
      await dio.get<Object?>('/trainer/clients/m1/memos');
      expect(lost, isEmpty);
    });

    test('the error still reaches the caller unchanged', () async {
      final Dio dio = _dioWith(
        _FakeAdapter((_) => (404, <String, Object?>{'detail': _guard})),
        (_) {},
      );
      try {
        await dio.get<Object?>('/trainer/clients/m1/diet');
        fail('expected a DioException');
      } on DioException catch (error) {
        final AppError mapped = AppError.fromDio(error);
        expect(mapped, isA<NotFoundError>());
        expect(mapped.message, _guard);
      }
    });
  });

  group('ClientAccessLostSignal', () {
    test('broadcasts reports and ignores them after close', () async {
      final ClientAccessLostSignal signal = ClientAccessLostSignal();
      final List<String> seen = <String>[];
      final StreamSubscription<String> sub = signal.stream.listen(seen.add);
      signal.report('m1');
      signal.report('m2');
      await Future<void>.delayed(Duration.zero);
      expect(seen, <String>['m1', 'm2']);
      await sub.cancel();
      await signal.close();
      expect(() => signal.report('m3'), returnsNormally);
    });
  });

  group('DioClientRepository.refreshRoster', () {
    test('re-reads the roster but not the member data streams', () async {
      final _FakeAdapter adapter = _FakeAdapter((RequestOptions o) {
        if (o.uri.path == '/v1/trainer/clients') {
          return (200, <Object?>[_rosterRow('m1')]);
        }
        return (200, <Object?>[]);
      });
      final DioClientRepository repo = DioClientRepository(
        _dioWith(adapter, (_) {}),
        pollInterval: const Duration(hours: 1),
      );
      final StreamSubscription<List<TrainerClient>> roster = repo
          .watchClients()
          .listen((_) {});
      final StreamSubscription<Object?> diet = repo
          .watchDiet('m1')
          .listen((_) {});
      addTearDown(roster.cancel);
      addTearDown(diet.cancel);
      await pumpEventQueue();
      expect(adapter.countOf('/v1/trainer/clients'), 1);
      expect(adapter.countOf('/v1/trainer/clients/m1/diet'), 1);

      repo.refreshRoster();
      await pumpEventQueue();

      expect(adapter.countOf('/v1/trainer/clients'), 2);
      expect(adapter.countOf('/v1/trainer/clients/m1/diet'), 1);
    });

    test('refreshClientData still re-reads both (unchanged)', () async {
      final _FakeAdapter adapter = _FakeAdapter((RequestOptions o) {
        if (o.uri.path == '/v1/trainer/clients') {
          return (200, <Object?>[_rosterRow('m1')]);
        }
        return (200, <Object?>[]);
      });
      final DioClientRepository repo = DioClientRepository(
        _dioWith(adapter, (_) {}),
        pollInterval: const Duration(hours: 1),
      );
      final StreamSubscription<List<TrainerClient>> roster = repo
          .watchClients()
          .listen((_) {});
      final StreamSubscription<Object?> diet = repo
          .watchDiet('m1')
          .listen((_) {});
      addTearDown(roster.cancel);
      addTearDown(diet.cancel);
      await pumpEventQueue();

      repo.refreshClientData('m1');
      await pumpEventQueue();

      expect(adapter.countOf('/v1/trainer/clients'), 2);
      expect(adapter.countOf('/v1/trainer/clients/m1/diet'), 2);
    });
  });

  group('provider wiring (real API mode)', () {
    const AppConfig realApi = AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'http://localhost/v1',
      useMockApi: false,
    );

    test(
      'a refused member request drops the member from clientsProvider',
      () async {
        bool registered = true;
        final _FakeAdapter adapter = _FakeAdapter((RequestOptions o) {
          switch (o.uri.path) {
            case '/v1/trainer/clients':
              return (
                200,
                <Object?>[
                  _rosterRow('m1', registered: registered),
                  _rosterRow('m2'),
                ],
              );
            case '/v1/trainer/clients/m1/memos':
              return (404, <String, Object?>{'detail': _guard});
          }
          return (200, <Object?>[]);
        });
        final ProviderContainer container = ProviderContainer(
          overrides: <Override>[appConfigProvider.overrideWithValue(realApi)],
        );
        addTearDown(container.dispose);
        container.read(dioProvider).httpClientAdapter = adapter;

        final List<List<String>> seen = <List<String>>[];
        container.listen<AsyncValue<List<TrainerClient>>>(clientsProvider, (
          _,
          AsyncValue<List<TrainerClient>> next,
        ) {
          final List<TrainerClient>? value = next.valueOrNull;
          if (value != null) {
            seen.add(value.map((TrainerClient c) => c.id).toList());
          }
        }, fireImmediately: true);
        await pumpEventQueue();
        expect(seen.last, <String>['m1', 'm2']);

        // 회원 앱에서 담당을 끊었다 — 서버는 그 회원 데이터를 404 로 막는다.
        registered = false;
        await expectLater(
          container.read(dioProvider).get<Object?>('/trainer/clients/m1/memos'),
          throwsA(isA<DioException>()),
        );
        await pumpEventQueue();

        expect(seen.last, <String>['m2']);
        expect(adapter.countOf('/v1/trainer/clients'), 2);
      },
    );

    test('a 404 outside member data leaves the roster alone', () async {
      final _FakeAdapter adapter = _FakeAdapter((RequestOptions o) {
        if (o.uri.path == '/v1/trainer/clients') {
          return (200, <Object?>[_rosterRow('m1')]);
        }
        return (404, <String, Object?>{'detail': '일정을 찾을 수 없어요.'});
      });
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[appConfigProvider.overrideWithValue(realApi)],
      );
      addTearDown(container.dispose);
      container.read(dioProvider).httpClientAdapter = adapter;
      container.listen(clientsProvider, (_, _) {}, fireImmediately: true);
      await pumpEventQueue();

      await expectLater(
        container.read(dioProvider).get<Object?>('/trainer/schedule/s1'),
        throwsA(isA<DioException>()),
      );
      await pumpEventQueue();

      expect(adapter.countOf('/v1/trainer/clients'), 1);
    });
  });
}
