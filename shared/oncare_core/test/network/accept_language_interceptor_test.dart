/// 공용 언어 헤더 인터셉터. (#2297, #2907)
///
/// 두 앱은 각자의 언어 provider 를 읽는 함수로 이 인터셉터를 조립한다(앱 쪽
/// 조립 테스트는 각 앱의 `accept_language_interceptor_test.dart`). 여기서는
/// 요청마다 언어를 읽는지, 호출부가 고른 언어를 덮지 않는지만 본다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_core/network/accept_language_interceptor.dart';

class _Capture implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Capture capture;
  late Dio dio;
  Locale current = const Locale('ko');

  setUp(() {
    current = const Locale('ko');
    capture = _Capture();
    dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
      ..httpClientAdapter = capture
      ..interceptors.add(AcceptLanguageInterceptor(() => current));
  });

  Object? sentLanguage() =>
      capture.requests.last.headers[AcceptLanguageInterceptor.headerName];

  test('headerValue 는 언어 코드만 보낸다', () {
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

  test('지금 언어를 싣고, 언어가 바뀌면 다음 요청부터 새 언어가 나간다', () async {
    await dio.get<Object?>('/a');
    expect(sentLanguage(), 'ko');

    current = const Locale('en', 'US');
    await dio.get<Object?>('/b');
    expect(sentLanguage(), 'en');
  });

  test('호출부가 넣은 언어는 대소문자와 상관없이 덮지 않는다', () async {
    await dio.get<Object?>(
      '/a',
      options: Options(headers: <String, Object?>{'accept-language': 'en'}),
    );
    expect(sentLanguage(), 'en');
  });
}
