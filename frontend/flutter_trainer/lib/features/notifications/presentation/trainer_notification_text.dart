import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/health_focus.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';

/// 알림 한 건의 화면 문장 — 제목과 본문.
typedef TrainerNotificationText = ({String title, String body});

/// 알림 문장을 화면 언어로 조립한다(#2302).
///
/// 서버는 알림마다 틀 코드(`template`)와 언어와 무관한 인자(`args`)를 준다. 아는
/// 틀이면 ARB 문장으로 조립하고, 그렇지 않으면 서버가 준 [TrainerNotification.title]
/// ·[TrainerNotification.body] 를 그대로 쓴다. 서버도 같은 문장을 요청 언어로
/// 조립해 보내므로(`backend/app/services/notification_templates.py`) 되돌아가도
/// 언어가 어긋나지 않는다.
///
/// 틀 코드 문자열은 서버 틀 이름과 같아야 한다 — 백엔드 테스트가 이 파일에서
/// `trainer_*` 코드를 모두 찾는지 확인한다.
///
/// 되돌아가는 경우:
/// - 틀이 없는 옛 알림, 모르는 틀
/// - 인자가 없거나 모양이 다를 때
/// - 회원 이름이 비었을 때 — 이름 없는 경우의 한국어 문장이 알림 종류마다 달라서
///   서버가 저장한 문장을 쓰는 편이 옛 문장과 똑같이 맞는다.
TrainerNotificationText trainerNotificationText(
  AppLocalizations l,
  TrainerNotification n,
) {
  final TrainerNotificationText stored = (title: n.title, body: n.body);
  final String? template = n.template;
  if (template == null) return stored;
  return _assemble(l, template, n.args, n.body) ?? stored;
}

TrainerNotificationText? _assemble(
  AppLocalizations l,
  String template,
  Map<String, Object?> args,
  String storedBody,
) {
  final String? name = _name(args['member_name']);
  switch (template) {
    case 'trainer_health_goal':
      final String? goals = _goals(l, args['focus']);
      if (name == null || goals == null) return null;
      return (
        title: l.notifTplHealthGoalTitle,
        body: l.notifTplHealthGoalBody(name, goals),
      );
    case 'trainer_member_renamed':
      final String? oldName = _name(args['old_name']);
      final String? newName = _name(args['new_name']);
      if (oldName == null || newName == null) return null;
      return (
        title: l.notifTplMemberRenamedTitle,
        body: l.notifTplMemberRenamedBody(oldName, newName),
      );
    case 'trainer_member_withdrawn':
      if (name == null) return null;
      return (
        title: l.notifTplMemberWithdrawnTitle,
        body: l.notifTplMemberWithdrawnBody(name),
      );
    case 'trainer_member_disconnected':
      if (name == null) return null;
      return (
        title: l.notifTplMemberDisconnectedTitle,
        body: l.notifTplMemberDisconnectedBody(name),
      );
    case 'trainer_consult_requested':
    case 'trainer_consult_cancelled':
      final Object? day = args['preferred_date'];
      if (name == null || day is! String || day.isEmpty) return null;
      return (
        title: template == 'trainer_consult_requested'
            ? l.notifTplConsultRequestedTitle
            : l.notifTplConsultCancelledTitle,
        body: l.notifTplMemberWithDetail(name, day),
      );
    case 'trainer_invite_accepted':
      if (name == null) return null;
      return (
        title: l.notifTplInviteAcceptedTitle,
        body: l.notifTplInviteAcceptedBody(name),
      );
    case 'trainer_invite_rejected':
      if (name == null) return null;
      return (
        title: l.notifTplInviteRejectedTitle,
        body: l.notifTplInviteRejectedBody(name),
      );
    case 'trainer_reservation_booked':
      final String? when = _when(l, args['starts_at']);
      if (name == null || when == null) return null;
      return (
        title: l.notifTplReservationBookedTitle,
        body: l.notifTplMemberWithDetail(name, when),
      );
    case 'trainer_reservation_cancelled':
      if (name == null) return null;
      final Object? raw = args['starts_at'];
      // 시각 없이 취소된 예약도 있다 — 그때는 이름만 적는다.
      if (raw == null) {
        return (
          title: l.notifTplReservationCancelledTitle,
          body: l.notifTplMemberOnly(name),
        );
      }
      final String? when = _when(l, raw);
      if (when == null) return null;
      return (
        title: l.notifTplReservationCancelledTitle,
        body: l.notifTplMemberWithDetail(name, when),
      );
    case 'trainer_member_message':
      if (name == null) return null;
      // 본문은 회원이 쓴 메시지 그대로다. 글 없이 사진만 보냈으면 서버가
      // 적어 둔 한국어 안내 대신 화면 언어로 적는다(#1665).
      return (
        title: l.notifTplMemberMessageTitle(name),
        body: args['photo_only'] == true
            ? l.notifTplMemberPhotoBody
            : storedBody,
      );
  }
  return null;
}

/// 비어 있지 않고 앞뒤 공백도 없는 이름. 공백이 붙은 이름은 알림 종류마다 서버가
/// 다르게 다뤄서, 저장된 문장으로 돌아가는 편이 옛 문장과 똑같다.
String? _name(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) return null;
  return value;
}

/// 건강 목표 저장 값 목록 → 화면 문구. 비었으면 "목표 없음".
String? _goals(AppLocalizations l, Object? value) {
  if (value is! List) return null;
  if (value.any((Object? v) => v is! String)) return null;
  if (value.isEmpty) return l.notifTplNoGoals;
  return value
      .cast<String>()
      .map((String v) => healthFocusLabel(l, v))
      .join(kHealthFocusLabelSeparator);
}

/// 서울 벽시계 ISO 시각(`2026-10-01T09:00:00+09:00`) → `10월 01일 09:00` /
/// `10/01 09:00`. 시간대를 옮기지 않고 적힌 시각을 그대로 읽는다 — 서버가 이미
/// 서울 시각으로 적어 둔다.
final RegExp _isoWallClock = RegExp(r'^\d{4}-(\d{2})-(\d{2})T(\d{2}):(\d{2})');

String? _when(AppLocalizations l, Object? value) {
  if (value is! String) return null;
  final RegExpMatch? m = _isoWallClock.firstMatch(value);
  if (m == null) return null;
  return l.notifTplWhen(
    m.group(1)!,
    m.group(2)!,
    '${m.group(3)}:${m.group(4)}',
  );
}
