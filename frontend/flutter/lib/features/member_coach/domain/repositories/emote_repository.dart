import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';

/// 채팅 이모티콘 — 하나씩 사서 7일 동안 쓴다. (#2153)
///
/// 이모티콘 목록은 서버에 묻지 않는다 — 그림이 앱에 있으므로 목록도 앱이 안다
/// (`AppEmotes`). 서버가 정하는 것은 **무엇을 쓰고 있는가·얼마인가·얼마나 남았는가** 다.
abstract interface class EmoteRepository {
  Future<EmoteState> fetchState();

  /// 포인트로 이모티콘 하나를 7일 동안 연다.
  ///
  /// [clientRequestId] 는 **구매 시도 하나**의 키다. 응답을 못 받고 다시 누르면 같은
  /// 키를 보내야 서버가 두 번 차감하지 않고 지금 상태를 돌려준다(#2845). 서버가
  /// 분명히 거절하면 [EmoteUnlockRejected], 망 오류 등은 그 밖의 오류다.
  Future<EmoteState> unlock(String emoteId, {required String clientRequestId});
}

/// 서버가 이모티콘 구매를 **분명히** 거절한 이유. (#2845)
enum EmoteUnlockFailure {
  /// 이미 쓰고 있다 — 응답을 못 받은 첫 구매가 끝나 있던 경우도 여기다.
  alreadyUnlocked,

  /// 담당 트레이너가 없다.
  trainerRequired,

  /// 포인트가 모자라다.
  insufficientPoints,
}

/// 서버가 구매를 거절했다. 같은 키로 다시 보내도 결과가 같으므로 키를 버린다.
class EmoteUnlockRejected implements Exception {
  const EmoteUnlockRejected(this.reason);

  final EmoteUnlockFailure reason;

  /// 응답 상태·본문에서 거절 이유를 읽는다. 이유를 모르면 null 이다 — 그때는
  /// 일반 실패로 다루고 상태를 다시 읽어 확인한다.
  static EmoteUnlockRejected? fromResponse(int? status, Object? body) {
    final Object? detail = body is Map ? body['detail'] : null;
    final Object? code = detail is Map ? detail['code'] : null;
    final EmoteUnlockFailure? reason = switch ((status, code)) {
      (409, 'already_unlocked') => EmoteUnlockFailure.alreadyUnlocked,
      (409, 'trainer_required') => EmoteUnlockFailure.trainerRequired,
      (400, _) => EmoteUnlockFailure.insufficientPoints,
      _ => null,
    };
    return reason == null ? null : EmoteUnlockRejected(reason);
  }

  @override
  String toString() => 'EmoteUnlockRejected($reason)';
}
