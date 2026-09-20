import 'package:oncare/core/points/demo_emote_pass.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';
import 'package:oncare/features/member_coach/domain/repositories/emote_repository.dart';

/// 데모의 이모티콘 이용권. 규칙은 [DemoEmotePassBook] 하나가 들고 있다. (#2020)
///
/// 이 대역이 따로 세지 않는 이유는, MY 탭의 포인트 사용처에서 산 이용권이 채팅에도
/// 보여야 하기 때문이다 — 서버에서는 같은 표 하나다.
class MockEmoteRepository implements EmoteRepository {
  MockEmoteRepository(this._book);

  final DemoEmotePassBook _book;

  @override
  Future<EmoteState> fetchState() async => EmoteState.fromJson(_book.stateJson());

  @override
  Future<EmoteState> buyPass() async {
    final result = _book.buy();
    if (result.statusCode >= 400) {
      throw StateError('${(result.body as Map<String, Object?>?)?['detail']}');
    }
    return EmoteState.fromJson(result.body! as Map<String, Object?>);
  }
}
