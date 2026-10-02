import 'package:oncare/core/points/demo_emote_book.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';
import 'package:oncare/features/member_coach/domain/repositories/emote_repository.dart';

/// 데모의 채팅 이모티콘. 규칙은 [DemoEmoteBook] 하나가 들고 있다. (#2153)
class MockEmoteRepository implements EmoteRepository {
  MockEmoteRepository(this._book);

  final DemoEmoteBook _book;

  @override
  Future<EmoteState> fetchState() async =>
      EmoteState.fromJson(_book.stateJson());

  @override
  Future<EmoteState> unlock(
    String emoteId, {
    required String clientRequestId,
  }) async {
    final result = _book.unlock(emoteId, clientRequestId: clientRequestId);
    if (result.statusCode >= 400) {
      // 실서버와 같은 거절 이유로 바꾼다 — 시트가 두 경로에서 같은 문구를 띄운다.
      final EmoteUnlockRejected? rejected = EmoteUnlockRejected.fromResponse(
        result.statusCode,
        result.body,
      );
      if (rejected != null) throw rejected;
      throw StateError('${(result.body as Map<String, Object?>?)?['detail']}');
    }
    return EmoteState.fromJson(result.body! as Map<String, Object?>);
  }
}
