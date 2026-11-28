import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 트레이너에게 보내는 것의 종류 — 같은 원인도 무엇을 보냈느냐에 따라 문구가
/// 다르다. (#3346)
enum CoachSendKind { message, emote, photo, weeklyFeedback }

/// 전송 실패 문구. [reason] 이 null 이면 서버가 거절한 것이 아니라 닿지 못한
/// 것(망 오류 등)이라 다시 시도를 권한다. (#3346)
///
/// 화면마다 따로 가르면 한 곳만 옛 문구("다시 시도해 주세요")로 남는다 —
/// 글·이모티콘·사진·주간 피드백이 모두 여기서 고른다.
String coachSendFailureText(
  AppLocalizations l,
  CoachSendKind kind,
  CoachSendFailure? reason,
) {
  switch (kind) {
    case CoachSendKind.message:
      return switch (reason) {
        CoachSendFailure.unassigned => l.coachChatUnassigned,
        // 거절된 키는 저장소가 버렸다 — 다시 보내면 새 키로 간다.
        null || CoachSendFailure.conflict => l.coachChatSendFailed,
        _ => l.coachChatSendRejected,
      };
    case CoachSendKind.emote:
      return switch (reason) {
        CoachSendFailure.unassigned => l.coachChatUnassigned,
        CoachSendFailure.emoteLocked => l.emoteSendLocked,
        null || CoachSendFailure.conflict => l.emoteSendFailed,
        _ => l.emoteSendRejected,
      };
    case CoachSendKind.photo:
      return switch (reason) {
        CoachSendFailure.unassigned => l.coachChatUnassigned,
        CoachSendFailure.photoTooLarge => l.dietPhotoTooLarge,
        null => l.coachPhotoSendFailed,
        _ => l.coachPhotoSendRejected,
      };
    case CoachSendKind.weeklyFeedback:
      return switch (reason) {
        CoachSendFailure.unassigned => l.weeklyFeedbackSendUnassigned,
        null => l.weeklyFeedbackSendFailed,
        _ => l.weeklyFeedbackSendRejected,
      };
  }
}
