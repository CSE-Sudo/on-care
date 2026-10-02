import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/shared/services/locale_provider.dart';
import 'package:oncare_core/network/accept_language_interceptor.dart';
import 'package:oncare_core/network/auth_interceptor.dart';

/// 네트워크로 나가지 않고 요청만 받아 두는 어댑터.
class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(<String, Object>{'ok': true}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  /// 마지막 요청의 `Accept-Language`.
  Object? get lastLanguage =>
      requests.last.headers[AcceptLanguageInterceptor.headerName];
}

/// 앱과 같은 `dioProvider`(실서버 모드)를 쓰되 어댑터만 바꾼 컨테이너.
(ProviderContainer, Dio, _CapturingAdapter) _setUp({Locale? chosen}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: Environment.prod,
          apiBaseUrl: 'https://api.test/v1',
          useMockApi: false,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (chosen != null) {
    container.read(localeProvider.notifier).state = chosen;
  }
  final Dio dio = container.read(dioProvider);
  final _CapturingAdapter adapter = _CapturingAdapter();
  dio.httpClientAdapter = adapter;
  return (container, dio, adapter);
}

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  final TestPlatformDispatcher dispatcher = binding.platformDispatcher;

  void device(List<Locale> locales) {
    dispatcher.localesTestValue = locales;
    addTearDown(dispatcher.clearLocalesTestValue);
  }

  group('AcceptLanguageInterceptor.headerValue', () {
    test('sends only the language code', () {
      expect(AcceptLanguageInterceptor.headerValue(const Locale('ko')), 'ko');
      expect(AcceptLanguageInterceptor.headerValue(const Locale('en')), 'en');
      expect(
        AcceptLanguageInterceptor.headerValue(const Locale('en', 'US')),
        'en',
      );
    });
  });

  group('dioProvider Accept-Language', () {
    test('is installed once, ahead of the auth interceptor', () {
      device(const <Locale>[Locale('ko')]);
      final (_, dio, _) = _setUp();

      final List<Interceptor> chain = dio.interceptors.toList();
      final int language = chain.indexWhere(
        (Interceptor i) => i is AcceptLanguageInterceptor,
      );
      final int auth = chain.indexWhere(
        (Interceptor i) => i is AuthInterceptor,
      );
      expect(chain.whereType<AcceptLanguageInterceptor>(), hasLength(1));
      expect(language, isNonNegative);
      expect(language, lessThan(auth));
    });

    test('a Korean device sends ko', () async {
      device(const <Locale>[Locale('ko', 'KR')]);
      final (_, dio, adapter) = _setUp();

      await dio.get<dynamic>('/users/me');

      expect(adapter.lastLanguage, 'ko');
    });

    test('an English device sends en', () async {
      device(const <Locale>[Locale('en', 'US')]);
      final (_, dio, adapter) = _setUp();

      await dio.get<dynamic>('/users/me');

      expect(adapter.lastLanguage, 'en');
    });

    test('an unsupported device sends the language the screen falls back '
        'to', () async {
      device(const <Locale>[Locale('ja')]);
      final (container, dio, adapter) = _setUp();

      await dio.get<dynamic>('/users/me');

      expect(
        adapter.lastLanguage,
        container.read(resolvedLocaleProvider).languageCode,
      );
    });

    test('switching the language changes the header of the next request '
        'without rebuilding Dio', () async {
      device(const <Locale>[Locale('ko', 'KR')]);
      final (container, dio, adapter) = _setUp();

      await dio.get<dynamic>('/dashboard');
      container.read(localeProvider.notifier).state = const Locale('en');
      expect(identical(container.read(dioProvider), dio), isTrue);
      await dio.get<dynamic>('/dashboard');
      container.read(localeProvider.notifier).state = null;
      await dio.get<dynamic>('/dashboard');

      expect(
        adapter.requests.map(
          (RequestOptions r) => r.headers[AcceptLanguageInterceptor.headerName],
        ),
        <String>['ko', 'en', 'ko'],
      );
    });

    test('a device language change is picked up by the next request', () async {
      device(const <Locale>[Locale('en')]);
      final (_, dio, adapter) = _setUp();

      await dio.get<dynamic>('/users/me');
      expect(adapter.lastLanguage, 'en');

      dispatcher.localesTestValue = const <Locale>[Locale('ko')];
      await dio.get<dynamic>('/users/me');
      expect(adapter.lastLanguage, 'ko');
    });

    test('a chosen language wins over the device', () async {
      device(const <Locale>[Locale('ko')]);
      final (_, dio, adapter) = _setUp(chosen: const Locale('en'));

      await dio.get<dynamic>('/users/me');

      expect(adapter.lastLanguage, 'en');
    });

    test('every method carries the header', () async {
      device(const <Locale>[Locale('en')]);
      final (_, dio, adapter) = _setUp();

      await dio.get<dynamic>('/a');
      await dio.post<dynamic>('/b', data: <String, Object>{'x': 1});
      await dio.put<dynamic>('/c', data: <String, Object>{'x': 1});
      await dio.patch<dynamic>('/d', data: <String, Object>{'x': 1});
      await dio.delete<dynamic>('/e');
      await dio.post<dynamic>(
        '/diet/analyze',
        data: FormData.fromMap(<String, Object>{'k': 'v'}),
      );

      expect(adapter.requests, hasLength(6));
      for (final RequestOptions r in adapter.requests) {
        expect(
          r.headers[AcceptLanguageInterceptor.headerName],
          'en',
          reason: '${r.method} ${r.path}',
        );
      }
    });

    test('an explicit header from the caller is kept', () async {
      device(const <Locale>[Locale('ko')]);
      final (_, dio, adapter) = _setUp();

      await dio.get<dynamic>(
        '/users/me',
        options: Options(headers: <String, Object>{'Accept-Language': 'en'}),
      );
      expect(adapter.lastLanguage, 'en');

      await dio.get<dynamic>(
        '/users/me',
        options: Options(headers: <String, Object>{'accept-language': 'en'}),
      );
      expect(adapter.lastLanguage, 'en');
      expect(
        adapter.requests.last.headers.keys
            .where((String k) => k.toLowerCase() == 'accept-language')
            .length,
        1,
      );
    });

    test('works alongside the auth header', () async {
      device(const <Locale>[Locale('en')]);
      final (container, dio, adapter) = _setUp();
      container.read(authAccessTokenProvider.notifier).state = 'tok';

      await dio.get<dynamic>('/users/me');

      expect(adapter.requests.last.headers['Authorization'], 'Bearer tok');
      expect(adapter.lastLanguage, 'en');
    });

    test('is sent even without a session token (login)', () async {
      device(const <Locale>[Locale('ko')]);
      final (_, dio, adapter) = _setUp();

      await dio.post<dynamic>(
        '/auth/login',
        data: <String, Object>{'email': 'a@b.c'},
      );

      expect(adapter.requests.last.headers.containsKey('Authorization'), false);
      expect(adapter.lastLanguage, 'ko');
    });
  });
}
