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
  Future<EmoteState> unlock(String emoteId) async {
    final result = _book.unlock(emoteId);
    if (result.statusCode >= 400) {
      throw StateError('${(result.body as Map<String, Object?>?)?['detail']}');
    }
    return EmoteState.fromJson(result.body! as Map<String, Object?>);
  }
}
