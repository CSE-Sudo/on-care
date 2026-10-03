import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';

/// 서버가 운영자 승인이 없다며 거절한 요청을 알린다 (#3010).
///
/// 반려는 운영자가 서버에서 바꾸는 값이라, 승인된 줄 아는 세션이 이미 반려된
/// 계정일 수 있다. 그때 담당 회원 기록·연결 경로가 403
/// `detail.code='trainer_not_approved'` 를 준다. 그 응답을 신호로 바꿔, 세션이
/// `GET /trainer/me` 를 다시 읽고 배너·버튼을 서버 상태로 맞추게 한다.
///
/// 응답 자체는 그대로 흘려보낸다 — 화면은 지금처럼 오류를 보여 준다.
class VerificationDeniedInterceptor extends Interceptor {
  /// Calls [onDenied] for every `trainer_not_approved` 403.
  VerificationDeniedInterceptor(this.onDenied);

  /// 신호를 받는 쪽.
  final void Function() onDenied;

  /// 서버가 승인 전 거절에 붙이는 코드.
  static const String code = 'trainer_not_approved';

  /// [err] 가 승인 전 거절인가.
  static bool isNotApproved(DioException err) =>
      err.response?.statusCode == 403 &&
      serverDetailCode(err.response?.data) == code;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (isNotApproved(err)) onDenied();
    handler.next(err);
  }
}

/// [VerificationDeniedInterceptor] 가 보내는 신호.
class VerificationDeniedSignal {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// 거절이 있을 때마다 한 번.
  Stream<void> get stream => _controller.stream;

  /// 거절을 알린다. [close] 뒤에는 무시한다.
  void report() {
    if (!_controller.isClosed) _controller.add(null);
  }

  /// Releases the stream.
  Future<void> close() => _controller.close();
}

/// 앱 전체의 [VerificationDeniedSignal] — `dioProvider` 가 보내고 세션 동기화가
/// 받는다.
final verificationDeniedProvider = Provider<VerificationDeniedSignal>((ref) {
  final VerificationDeniedSignal signal = VerificationDeniedSignal();
  ref.onDispose(signal.close);
  return signal;
}, name: 'verificationDenied');
