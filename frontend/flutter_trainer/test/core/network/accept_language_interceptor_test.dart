import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/network/accept_language_interceptor.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/auth_token.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// 앱과 같은 `dioProvider` 를 쓰되 어댑터만 바꾼 컨테이너.
Future<(ProviderContainer, Dio, _CapturingAdapter)> _setUp({
  String? stored,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    TrainerLocaleController.storageKey: ?stored,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
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
  final Dio dio = container.read(dioProvider);
  final _CapturingAdapter adapter = _CapturingAdapter();
  dio.httpClientAdapter = adapter;
  return (container, dio, adapter);
}

Future<void> _choose(ProviderContainer c, TrainerLanguage language) =>
    c.read(trainerLocaleProvider.notifier).setLanguage(language);

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  final TestPlatformDispatcher dispatcher = binding.platformDispatcher;

  void browser(List<Locale> locales) {
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
      expect(
        AcceptLanguageInterceptor.headerValue(const Locale('ko', 'KR')),
        'ko',
      );
    });
  });

  group('dioProvider Accept-Language', () {
    test('a Korean browser sends ko', () async {
      browser(const <Locale>[Locale('ko', 'KR')]);
      final (_, dio, adapter) = await _setUp();

      await dio.get<dynamic>('/trainer/me');

      expect(adapter.lastLanguage, 'ko');
    });

    test('an English browser sends en', () async {
      browser(const <Locale>[Locale('en', 'US')]);
      final (_, dio, adapter) = await _setUp();

      await dio.get<dynamic>('/trainer/me');

      expect(adapter.lastLanguage, 'en');
    });

    test('an unsupported browser sends the language the screen falls back '
        'to', () async {
      browser(const <Locale>[Locale('fr')]);
      final (container, dio, adapter) = await _setUp();

      await dio.get<dynamic>('/trainer/me');

      expect(
        adapter.lastLanguage,
        container.read(trainerResolvedLocaleProvider).languageCode,
      );
      expect(adapter.lastLanguage, 'en');
    });

    test('switching the language changes the header of the next request '
        'without rebuilding Dio', () async {
      browser(const <Locale>[Locale('ko', 'KR')]);
      final (container, dio, adapter) = await _setUp();

      await dio.get<dynamic>('/trainer/clients');
      expect(adapter.lastLanguage, 'ko');

      await _choose(container, TrainerLanguage.english);
      expect(identical(container.read(dioProvider), dio), isTrue);
      await dio.get<dynamic>('/trainer/clients');
      expect(adapter.lastLanguage, 'en');

      await _choose(container, TrainerLanguage.korean);
      await dio.get<dynamic>('/trainer/clients');
      expect(adapter.lastLanguage, 'ko');

      expect(
        adapter.requests.map(
          (RequestOptions r) => r.headers[AcceptLanguageInterceptor.headerName],
        ),
        <String>['ko', 'en', 'ko'],
      );
    });

    test(
      'going back to the browser setting follows the browser again',
      () async {
        browser(const <Locale>[Locale('en', 'GB')]);
        final (container, dio, adapter) = await _setUp();

        await _choose(container, TrainerLanguage.korean);
        await dio.get<dynamic>('/trainer/me');
        expect(adapter.lastLanguage, 'ko');

        await _choose(container, TrainerLanguage.system);
        await dio.get<dynamic>('/trainer/me');
        expect(adapter.lastLanguage, 'en');
      },
    );

    test(
      'a browser language change is picked up by the next request',
      () async {
        browser(const <Locale>[Locale('ko')]);
        final (_, dio, adapter) = await _setUp();

        await dio.get<dynamic>('/trainer/me');
        expect(adapter.lastLanguage, 'ko');

        dispatcher.localesTestValue = const <Locale>[Locale('en')];
        await dio.get<dynamic>('/trainer/me');
        expect(adapter.lastLanguage, 'en');
      },
    );

    test('a fixed choice wins over the browser', () async {
      browser(const <Locale>[Locale('ko', 'KR')]);
      final (container, dio, adapter) = await _setUp();

      await _choose(container, TrainerLanguage.english);
      dispatcher.localesTestValue = const <Locale>[Locale('ko')];
      await dio.get<dynamic>('/trainer/me');

      expect(adapter.lastLanguage, 'en');
    });

    test('a stored choice applies from the very first request', () async {
      browser(const <Locale>[Locale('ko', 'KR')]);
      final (_, dio, adapter) = await _setUp(stored: 'en');

      await dio.get<dynamic>('/trainer/me');

      expect(adapter.lastLanguage, 'en');
    });

    test('every method carries the header', () async {
      browser(const <Locale>[Locale('en')]);
      final (_, dio, adapter) = await _setUp();

      await dio.get<dynamic>('/a');
      await dio.post<dynamic>('/b', data: <String, Object>{'x': 1});
      await dio.put<dynamic>('/c', data: <String, Object>{'x': 1});
      await dio.patch<dynamic>('/d', data: <String, Object>{'x': 1});
      await dio.delete<dynamic>('/e');
      await dio.post<dynamic>(
        '/f',
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
      browser(const <Locale>[Locale('ko')]);
      final (_, dio, adapter) = await _setUp();

      await dio.get<dynamic>(
        '/trainer/me',
        options: Options(headers: <String, Object>{'Accept-Language': 'en'}),
      );
      expect(adapter.lastLanguage, 'en');

      // 헤더 이름의 대소문자가 달라도 호출부 값이 이긴다.
      await dio.get<dynamic>(
        '/trainer/me',
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
      browser(const <Locale>[Locale('en')]);
      final (container, dio, adapter) = await _setUp();
      container.read(authAccessTokenProvider.notifier).state = 'tok';

      await dio.get<dynamic>('/trainer/me');

      expect(adapter.requests.last.headers['Authorization'], 'Bearer tok');
      expect(adapter.lastLanguage, 'en');
    });

    test('is sent even without a session token (login)', () async {
      browser(const <Locale>[Locale('en')]);
      final (_, dio, adapter) = await _setUp();

      await dio.post<dynamic>(
        '/auth/login',
        data: <String, Object>{'email': 'a@b.c'},
      );

      expect(adapter.requests.last.headers.containsKey('Authorization'), false);
      expect(adapter.lastLanguage, 'en');
    });
  });
}
