import 'dart:math';

/// Creates an idempotency key for one logical create attempt.
///
/// 서버는 operation마다 인증 주체와 `client_request_id`를 scope로
/// 중복 생성을 막는다(#581, #605). 재시도할 때는 **같은 키를 다시
/// 보내야** 하고, 새 사용자 행동에서만 새로 만든다. 요청마다 새로
/// 만들면 멱등성이 아무것도 막지 못한다.
///
/// 네트워크 실패 뒤에는 호출부가 이 값을 붙들고 있다가 재시도에 그대로 쓴다.
/// 요청이 성공했거나 보낼 내용이 바뀌면 새 시도다.
///
/// `uuid` 패키지를 들이지 않는다. 여기서 필요한 건 전역 유일성이 아니라 한
/// 인증 주체(회원·트레이너) 안에서 겹치지 않을 정도의 무작위성이고, 그 정도는
/// `Random.secure()` 로 충분하다.
String newClientRequestId() {
  final Random rng = Random.secure();
  final StringBuffer buffer = StringBuffer('req-');
  for (int i = 0; i < 16; i++) {
    buffer.write(rng.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
}
