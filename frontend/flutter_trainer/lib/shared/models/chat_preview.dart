import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 로스터 미리보기(`lastMessage`/`lastTime`)에 문구 대신 저장하는 코드.
///
/// 저장소가 `'(이모티콘)'`·`'방금'` 처럼 한국어를 그대로 적어 두면, 영어로
/// 바꾼 화면에도 그 글이 남는다. 저장소는 코드만 적고 문구는 화면이 로케일로
/// 정한다([chatPreviewMessage]·[chatPreviewTime]). 회원이 실제로 쓸 수 있는 글과
/// 겹치지 않도록 `@` 로 시작한다.
abstract final class ChatPreviewCode {
  /// 마지막 메시지가 글 없는 이모티콘이다.
  static const String emote = '@emote';

  /// 마지막 메시지가 글 없는 사진이다. 실서버 로스터가 `사진` 으로 주는 자리를
  /// 데모에서도 같게 그린다. (#2493)
  static const String photo = '@photo';

  /// 마지막 메시지를 방금 보냈다.
  static const String justNow = '@just_now';

  /// 마지막 메시지가 루틴 전송 안내다(#2672). 실서버 로스터가 그 안내의 본문
  /// 한 줄(`운동을 보냈어요: …`)을 주는 자리를 데모는 이 코드로 그린다.
  static const String routineDelivered = '@routine_delivered';

  /// [value] 가 문구가 아니라 코드인가. 검색처럼 글 자체를 쓰는 자리가
  /// 코드를 회원의 말로 착각하지 않게 한다.
  static bool isCode(String value) =>
      value == emote ||
      value == photo ||
      value == justNow ||
      value == routineDelivered;
}

/// 목록에 보일 마지막 메시지. 대화가 없으면(빈 값) "아직 대화가 없어요" 다.
String chatPreviewMessage(AppLocalizations l, String lastMessage) {
  if (lastMessage == ChatPreviewCode.emote) return l.messagesPreviewEmote;
  if (lastMessage == ChatPreviewCode.photo) return l.messagesPreviewPhoto;
  if (lastMessage == ChatPreviewCode.routineDelivered) {
    return l.chatRoutineDelivered;
  }
  if (lastMessage.trim().isEmpty) return l.messagesNoPreview;
  return lastMessage;
}

/// 목록에 보일 마지막 메시지 시각.
String chatPreviewTime(AppLocalizations l, String lastTime) =>
    lastTime == ChatPreviewCode.justNow ? l.messagesTimeJustNow : lastTime;

/// [TrainerClient] 의 미리보기를 현재 로케일로 옮긴 값.
extension ChatPreviewLabels on TrainerClient {
  String previewMessage(AppLocalizations l) =>
      chatPreviewMessage(l, lastMessage);

  String previewTime(AppLocalizations l) => chatPreviewTime(l, lastTime);
}
