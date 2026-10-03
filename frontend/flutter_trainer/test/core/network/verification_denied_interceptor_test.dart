import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/network/interceptors/verification_denied_interceptor.dart';

/// 승인 전 거절(403 `trainer_not_approved`)을 신호로 바꾼다 (#3010).
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final Object? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<int> _deniedCount(int status, Object? body) async {
  int denied = 0;
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: 'http://localhost/v1',
      validateStatus: (int? s) => s != null && s < 400,
    ),
  )..httpClientAdapter = _Adapter(status, body);
  dio.interceptors.add(VerificationDeniedInterceptor(() => denied++));
  try {
    await dio.get<Object?>('/trainer/clients/m-1/memos');
  } on DioException {
    // 응답은 그대로 흘러간다 — 화면은 지금처럼 오류를 보인다.
  }
  return denied;
}

void main() {
  test('403 trainer_not_approved 는 신호를 한 번 보낸다', () async {
    expect(
      await _deniedCount(403, <String, Object?>{
        'detail': <String, Object?>{
          'code': 'trainer_not_approved',
          'message': '운영자 승인 뒤에 담당 회원의 기록을 볼 수 있습니다.',
        },
      }),
      1,
    );
  });

  test('다른 403·다른 코드·다른 상태는 신호가 아니다', () async {
    expect(
      await _deniedCount(403, <String, Object?>{'detail': '트레이너 전용 API 입니다.'}),
      0,
    );
    expect(
      await _deniedCount(403, <String, Object?>{
        'detail': <String, Object?>{'code': 'consent_required'},
      }),
      0,
    );
    expect(
      await _deniedCount(404, <String, Object?>{
        'detail': <String, Object?>{'code': 'trainer_not_approved'},
      }),
      0,
    );
  });

  test('신호는 닫힌 뒤 무시된다', () async {
    final VerificationDeniedSignal signal = VerificationDeniedSignal();
    int seen = 0;
    signal.stream.listen((_) => seen++);
    signal.report();
    await Future<void>.delayed(Duration.zero);
    await signal.close();
    signal.report();
    expect(seen, 1);
  });
}
