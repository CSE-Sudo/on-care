/// 일정 상태·종류의 **계약값**과 그 표시 문구를 갈라 두는 곳. (#501)
///
/// `TrainerSchedule.status`(`예정`|`완료`|`공백`)와 `type`(`1:1 PT`|`상담`)은 화면
/// 문구처럼 보이지만 실제로는 **DB 에 저장되고 서버로 나가는 값**이다. 백엔드가
/// `status == '예정'` 인 행만 완료 처리하고(`trainer_service.complete_session`)
/// drift 쿼리도 이 문자열로 거른다.
///
/// 다국어를 넣으면서 가장 쉽게 저지를 수 있는 사고가 이 값을 화면 문구로 착각해
/// 번역하는 것이다. 영어 로케일에서 `status: 'Completed'` 가 저장되는 순간 그 행은
/// 어느 쿼리에도 걸리지 않고, 되돌리려면 데이터를 고쳐야 한다.
///
/// 그래서 **계약값은 여기 상수로 못 박고**, 화면에 보일 문구는 `AppLocalizations`
/// 에서 따로 가져온다. 코드에 흩어진 리터럴을 지우면 어느 쪽 용도인지 읽는 사람이
/// 헷갈릴 일도 없다.
library;

import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// `TrainerSchedule.status` 에 저장되는 값. **번역하지 않는다.**
abstract final class ScheduleStatus {
  static const String upcoming = '예정';
  static const String done = '완료';

  /// 진행 전에 거두어진 약속. **삭제와 다르다** — 삭제는 잘못 만든 일정을 없애는
  /// 일이고, 취소는 실제로 있었던 약속이 진행되지 않았다는 기록이다(#871).
  static const String cancelled = '취소';

  /// 예약된 시간에 회원이 오지 않은 상태. 취소와 따로 센다.
  static const String noShow = '노쇼';

  static const String gap = '공백';

  /// 더 이상 결말이 바뀌지 않는 상태들. 백엔드의 `SCHEDULE_TERMINAL` 과 같은
  /// 집합이라, 화면이 서버가 409 로 막을 동작을 아예 내놓지 않는다.
  static const Set<String> finished = <String>{done, cancelled, noShow};
}

/// 취소 주체 계약값(`cancellation_source`). 빈 문자열은 "취소가 아님"이다.
abstract final class CancellationSource {
  static const String member = 'member';
  static const String trainer = 'trainer';
  static const String other = 'other';

  /// 취소 다이얼로그의 선택지 순서.
  static const List<String> all = <String>[member, trainer, other];
}

/// `TrainerSchedule.type` 에 저장되는 값. **번역하지 않는다.**
abstract final class SessionType {
  static const String personalTraining = '1:1 PT';
  static const String consultation = '상담';

  /// 포인트 체험(#1790) — 예약 슬롯에서 `포인트 체험 허용` 을 켜야만 생기는 20분
  /// 자세 점검 자리다. 트레이너가 일정 화면에서 직접 고르는 종류가 아니라 [all] 에
  /// 넣지 않는다. 회원이 예약하면 그 일정이 이 종류로 들어온다.
  static const String pointsTrial = '체험';

  /// 체험 자리의 시간(분). 서버가 20분으로 고정한다.
  static const int pointsTrialMinutes = 20;

  /// 일정 생성·수정 화면의 선택지 순서.
  static const List<String> all = <String>[personalTraining, consultation];
}

/// 저장된 상태값 → 화면 문구.
String scheduleStatusLabel(AppLocalizations l, String status) =>
    switch (status) {
      ScheduleStatus.upcoming => l.scheduleStatusUpcoming,
      ScheduleStatus.done => l.scheduleStatusDone,
      ScheduleStatus.cancelled => l.scheduleStatusCancelled,
      ScheduleStatus.noShow => l.scheduleStatusNoShow,
      ScheduleStatus.gap => l.scheduleStatusGap,
      // 서버가 새 상태를 추가했는데 앱이 모르는 경우. 빈칸을 보여 주느니 원문을 그대로
      // 내보낸다 — 무엇이 들어왔는지 화면에서 확인할 수 있다.
      _ => status,
    };

/// 저장된 종류값 → 화면 문구.
String sessionTypeLabel(AppLocalizations l, String type) => switch (type) {
  SessionType.personalTraining => l.sessionTypePersonalTraining,
  SessionType.consultation => l.sessionTypeConsultation,
  SessionType.pointsTrial => l.sessionTypePointsTrial,
  _ => type,
};

/// 저장된 취소 주체값 → 화면 문구. 상태값과 같은 이유로 계약값은 번역하지 않는다.
String cancellationSourceLabel(AppLocalizations l, String source) =>
    switch (source) {
      CancellationSource.member => l.schedCancelByMember,
      CancellationSource.trainer => l.schedCancelByTrainer,
      CancellationSource.other => l.schedCancelByOther,
      _ => source,
    };
