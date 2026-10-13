import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/network/auth_interceptor.dart';

/// 서버가 "필수 동의가 남았다" 며 거절한 응답인가. (#3155)
///
/// 트레이너 API 는 필수 동의(약관·개인정보·만 14세)가 끝나지 않은 계정에
/// `403 {"detail": {"code": "consent_required", "missing": [...]}}` 를 준다 —
/// 회원 앱(#3088)과 같은 계약이다. 다른 403(회원 계정·권한 없음)과는 `code` 로
/// 가른다.
bool isConsentRequiredResponse(Response<Object?>? response) {
  if (response?.statusCode != 403) return false;
  final Object? data = response?.data;
  if (data is! Map) return false;
  final Object? detail = data['detail'];
  return detail is Map && detail['code'] == 'consent_required';
}

/// 네트워크 계층이 "이 세션 토큰은 동의가 남았다" 를 세션 컨트롤러에 알리는 잎
/// 브리지. (#3155)
///
/// 인터셉터가 인증 기능을 직접 가져오면 `dio_client ↔ session_controller` 가
/// 서로를 가져오게 된다(`SessionRefreshBridge` 와 같은 이유). 컨트롤러가
/// 만들어질 때 자신을 붙인다.
class ConsentGateBridge {
  void Function(String token)? _listener;

  /// 세션 컨트롤러를 붙인다.
  void attach(void Function(String token) listener) => _listener = listener;

  /// [listener] 가 지금 붙어 있는 것일 때만 뗀다. 같은 객체의 메서드를 따로
  /// 떼어 낸 함수는 `identical` 이 아니라 `==` 로만 같다.
  void detach(void Function(String token) listener) {
    if (_listener == listener) _listener = null;
  }

  /// [token] 으로 나간 요청이 403 `consent_required` 를 받았다.
  void notify(String token) => _listener?.call(token);
}

/// 앱 전체가 함께 쓰는 [ConsentGateBridge].
final consentGateBridgeProvider = Provider<ConsentGateBridge>(
  (ref) => ConsentGateBridge(),
  name: 'consentGateBridge',
);

/// 트레이너 API 가 403 `consent_required` 를 주면 세션에 알린다. (#3155)
///
/// 로그인 응답의 `consent_required` 만으로는 저장된 세션을 복구한 뒤(문서 버전이
/// 올랐거나, 동의 화면이 없던 빌드로 쓰던 계정) 동의 화면에 닿지 못한다. 이제
/// 세션이 동의가 남은 상태로 바뀌고 라우터 가드가 동의 화면으로 보낸다. 오류는
/// 그대로 호출부에 넘긴다 — 화면의 실패 처리는 바뀌지 않는다.
///
/// 인증 인터셉터가 세션 토큰을 붙여 보낸 요청만 본다. 세션 복구처럼 호출부가
/// 직접 토큰을 넣은 요청은 그 토큰이 아직 세션의 것이 아니다.
class ConsentRequiredInterceptor extends Interceptor {
  ConsentRequiredInterceptor(this.bridge);

  /// 쓸 때마다 부른다 — 컨트롤러가 다시 붙어도 인터셉터를 다시 만들지 않는다.
  final ConsentGateBridge Function() bridge;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final Object? token =
        err.requestOptions.extra[AuthInterceptor.sessionTokenExtra];
    if (token is String &&
        token.isNotEmpty &&
        isConsentRequiredResponse(err.response)) {
      bridge().notify(token);
    }
    handler.next(err);
  }
}
