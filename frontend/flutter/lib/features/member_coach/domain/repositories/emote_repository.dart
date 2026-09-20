import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';

/// 채팅 이모티콘 이용권. (#2020)
///
/// 이모티콘 목록은 서버에 묻지 않는다 — 그림이 앱에 있으므로 목록도 앱이 안다
/// (`AppEmotes`). 서버가 정하는 것은 **살 수 있는가·얼마인가·얼마나 남았는가** 다.
abstract interface class EmoteRepository {
  Future<EmoteState> fetchState();

  /// 포인트로 24시간 이용권을 산다. 이용 중이거나 잔액이 모자라면 오류다.
  Future<EmoteState> buyPass();
}
