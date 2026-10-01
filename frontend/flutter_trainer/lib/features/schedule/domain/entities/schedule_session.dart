import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// PT 세션 프로그램의 운동 한 항목 (예: 레그프레스 3세트 · 80kg).
///
/// 회원 앱의 운동 추가 시트와 같은 칸을 받는다(#1276) — 날짜·종류·이름·
/// 시간(또는 세트·횟수·중량)·강도. 예전에는 그 값들이 전부 문자열이라
/// 같은 운동이 화면마다 다른 모양으로 저장됐고, 회원 기록과 나란히 집계할 수가
/// 없었다.
class ProgramItem {
  /// Creates a program item.
  const ProgramItem({
    required this.name,
    this.type = '근력',
    this.date,
    this.duration,
    this.durationSeconds,
    this.sets,
    this.reps,
    this.holdSeconds,
    this.weight,
    this.intensity = 'moderate',
    this.session = '',
  });

  /// Exercise name.
  final String name;

  /// 운동 유형 계약값('유산소'|'근력'|'스트레칭'|'기타') — 코칭 탭 루틴 배정과
  /// 같은 어휘다(#1233). 이 값이 없는 예전 행은 '근력'으로 읽힌다.
  final String type;

  /// 이 운동을 하는 날. 아직 정하지 않았으면 null.
  final DateTime? date;

  /// 유산소·스트레칭·기타의 운동 시간(분). 근력은 세트로 재므로 null 이다.
  /// PT 완료 자동 기록은 이 값이 없으면 세션 슬롯 전체 길이로 되돌아간다(#1233).
  final int? duration;

  /// 같은 운동 시간을 초로(#2221). 트레이너가 시·분·초로 적은 그대로다.
  /// 이 칸이 생기기 전의 행은 비어 있다 — 읽을 때는 [seconds] 를 쓴다.
  final int? durationSeconds;

  /// 이 운동의 시간(초). 초가 없는 예전 행은 분 × 60 이다. 근력은 null.
  int? get seconds =>
      durationSeconds ?? (duration == null ? null : duration! * 60);

  /// 근력의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 null 이다.
  final int? sets;
  final int? reps;

  /// 버티는 운동이면 한 세트를 버티는 시간(초). [reps] 와 한 자리를 나눠
  /// 쓴다 — 있으면 횟수가 비고, 없으면 반대다. 칸이 없던 동안 트레이너는
  /// `플랭크 3세트 · 60초` 를 **이름에** 적을 수밖에 없었다. (#1969)
  final int? holdSeconds;
  final double? weight;

  /// 운동 강도 계약값('light'|'moderate'|'high').
  final String intensity;

  /// Which session of a multi-session program this item belongs to (#709).
  ///
  /// Empty for a single-session program and for rows written before sessions
  /// existed — the schedule then reads as the flat list it always was.
  final String session;

  /// 유형에 맞지 않는 칸을 비운 항목.
  ///
  /// 근력은 세트·횟수·중량으로, 나머지는 시간으로 잰다(#1276). 유형과 다른 칸을
  /// 달고 있는 항목은 화면에서 뜻이 없는 줄이 된다 — `저강도 유산소(걷기)
  /// 3세트 · 30회` 처럼. 예전에 저장된 행과 다른 화면이 보낸 값이 그대로 들어오는
  /// 자리라, 읽을 때와 보낼 때 양쪽에서 한 번씩 거른다.
  ProgramItem get byType => ProgramItem(
    name: name,
    type: type,
    date: date,
    duration: type == '근력' ? null : duration,
    durationSeconds: type == '근력' ? null : durationSeconds,
    sets: type == '근력' ? sets : null,
    // 한 세트는 회로든 초로든 한 번만 잰다 — 초가 있으면 횟수를 버린다(#1969).
    reps: type == '근력' && holdSeconds == null ? reps : null,
    holdSeconds: type == '근력' ? holdSeconds : null,
    weight: type == '근력' ? weight : null,
    intensity: intensity,
    session: session,
  );
}

/// 상담 일정을 만든 상담 요청의 내용 — 카드의 `상담 요청 내용`. (#2584)
///
/// 회원이 신청할 때 적은 것이라 읽기 전용이다. 예전에는 수락이 문의 글을 일정
/// 메모에 넣어, 트레이너 메모 자리에 회원 글이 섞였다. 코드는 상담 인박스와 같은
/// 값이라 같은 이름표(`exerciseGoalLabels`)로 읽는다.
class ScheduleConsultation {
  const ScheduleConsultation({
    required this.id,
    required this.goalCode,
    this.message,
  });

  /// 상담 요청 id.
  final String id;

  /// 운동 목표 코드('weight_loss' …).
  final String goalCode;

  /// 회원이 남긴 문의 글. 적지 않았으면 null.
  final String? message;
}

/// One slot on the trainer's daily timeline (스케줄 탭). Decoded from
/// the drift `TrainerScheduleEntries` row (`programJson` → [program]).
class ScheduleSession {
  /// Creates a schedule slot.
  const ScheduleSession({
    required this.id,
    required this.date,
    required this.time,
    this.clientId,
    required this.clientName,
    required this.type,
    required this.durationMinutes,
    required this.status,
    required this.note,
    required this.program,
    this.programSent = false,
    this.cancelledAt,
    this.cancellationSource = '',
    this.cancellationReason = '',
    this.noShowAt,
    this.consultation,
    this.memberDetached = false,
    this.isReservation = false,
  });

  /// 회원이 예약 슬롯으로 잡은 일정인가(#2756). 예약이 시각·회원·좌석을
  /// 갖고 있어 일반 일정 수정·삭제는 서버가 409 로 막는다 — 카드는 그 동작을
  /// 잠그고 취소를 안내한다. 메모·프로그램은 고칠 수 있다.
  final bool isReservation;

  /// 상담 요청으로 생긴 상담 일정이면 그 요청의 내용(#2584). 직접 잡은 일정은
  /// null 이다.
  final ScheduleConsultation? consultation;

  /// Row id.
  final String id;

  /// 완료한 세션의 프로그램을 회원에게 보냈는가. 보낸 적 없는 세션과 이미 보낸
  /// 세션은 화면에서 다른 것을 말해야 한다(#822).
  final bool programSent;

  /// Calendar day (`YYYY-MM-DD`). Carried on the entity because the week
  /// calendar and the client's 루틴 tab both render sessions from more
  /// than one day at a time.
  final String date;

  /// Slot time (e.g. "10:00").
  final String time;

  /// Booked client's id. Null for gap slots, 미등록(상담) 고객, and rows
  /// stored before v3 — see the drift column comment (#386).
  final String? clientId;

  /// Booked client's display name — empty for a gap slot. 표시 전용이다.
  /// 조회는 [clientId] 로 한다.
  final String clientName;

  /// Session kind (e.g. "1:1 PT", "상담") — empty for a gap.
  final String type;

  /// Duration in minutes (0 for a gap).
  final int durationMinutes;

  /// 완료 | 예정 | 취소 | 노쇼 | 공백.
  final String status;

  /// 취소·노쇼로 마무리된 세션의 기록(#871). 예정·완료는 전부 비어 있다.
  ///
  /// 데모(`USE_MOCK_API=true`)도 같은 값을 저장한다(#906) — 데모가 이 기능을
  /// 실제로 눌러 보는 자리라, 취소한 쪽을 고르고도 카드에 남지 않으면 취소가
  /// 삭제와 어떻게 다른지 전달되지 않는다.
  final DateTime? cancelledAt;

  /// ''(해당 없음) | member | trainer | other.
  final String cancellationSource;

  /// 트레이너만 보는 짧은 사유. 회원에게는 나가지 않는다.
  final String cancellationReason;

  final DateTime? noShowAt;

  /// 담당이 끊긴(해제·동의 철회) 회원의 일정인가(#2589). 참이면 서버가 이름을
  /// `해제 회원` 으로, 회원 id·글·프로그램을 비워 보낸다 — 트레이너가 참여한
  /// 수업 기록으로만 남고 회원 상세·코칭으로 이어지지 않는다.
  final bool memberDetached;

  /// Trainer's note for the session (may be empty).
  final String note;

  /// The session's exercise program (empty when none).
  final List<ProgramItem> program;

  /// Whether this is an empty ("빈 시간") slot.
  bool get isGap => status == ScheduleStatus.gap;

  /// Whether the session is done.
  bool get isDone => status == ScheduleStatus.done;

  /// Whether the session is still upcoming (예정).
  bool get isUpcoming => status == ScheduleStatus.upcoming;

  /// 진행 전에 거두어진 약속.
  bool get isCancelled => status == ScheduleStatus.cancelled;

  /// 예약된 시간에 회원이 오지 않은 세션.
  bool get isNoShow => status == ScheduleStatus.noShow;

  /// 결말이 정해진 세션(완료·취소·노쇼) — 더 이상 상태가 바뀌지 않는다.
  bool get isFinished => ScheduleStatus.finished.contains(status);

  /// Whether the card can expand. Every booked session opens: 완료 shows
  /// the finished program, 예정 shows the plan (or a no-plan hint), and
  /// both expose the manage/chat actions.
  bool get expandable => !isGap;
}

/// [session] 의 시작 시각(KST 날짜+`HH:mm`)이 [now] 와 같거나 지났는가. (#2760)
///
/// 완료와 노쇼가 이 판정을 쓴다. 날짜만 비교하던 때에는 오늘 20:00 PT 를
/// 오전에 노쇼·완료로 처리할 수 있었고, 완료는 아직 하지 않은 운동을 회원
/// 기록에 미리 만들었다. 완료는 종료가 아니라 시작 시각부터 연다 — PT 가 일찍
/// 끝나는 경우를 막지 않는다. [now] 는 KST 벽시계(`nowKst()`)다. 시각 형식이
/// 깨졌으면 날짜만으로 판정한다(예전 규칙). 서버 `session_has_started` 와 같다.
bool sessionHasStarted(ScheduleSession session, DateTime now) =>
    hasStartedAt(session.date, session.time, now);

/// [sessionHasStarted] 의 값 판. 데모 저장소가 행을 엔티티로 바꾸기 전에 쓴다.
bool hasStartedAt(String date, String time, DateTime now) {
  final String today =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  if (date != today) return date.compareTo(today) < 0;
  final int? start = clockMinutes(time);
  if (start == null) return true;
  return start <= now.hour * 60 + now.minute;
}

/// `HH:mm` 을 자정부터의 분으로. 형식이 다르면 null. (#1012)
int? clockMinutes(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

/// `12:00–12:50` — 시작과 끝. 시각이 `HH:mm` 이 아니면 [session]의 시작
/// 시각 그대로.
String timeRangeLabel(AppLocalizations l, ScheduleSession session) {
  final start = clockMinutes(session.time);
  if (start == null) return session.time;
  return l.schedTimeRange(session.time, _hhmm(start + session.durationMinutes));
}

/// 두 시간대가 겹치는가 — 반열린 구간 `[시작, 끝)` 끼리 비교한다(#1581).
///
/// 10:00–11:00 과 11:00–12:00 은 이어질 뿐 겹치지 않는다. 길이가 0인 세션은
/// 시작 1분으로 본다. 시각이 `HH:mm` 이 아니면 겹치지 않는 것으로 본다. 서버
/// `_overlapping_planned_sessions` 와 같은 규칙이다.
bool timeRangesOverlap(String aTime, int aMinutes, String bTime, int bMinutes) {
  final aStart = clockMinutes(aTime);
  final bStart = clockMinutes(bTime);
  if (aStart == null || bStart == null) return false;
  final aEnd = aStart + (aMinutes < 1 ? 1 : aMinutes);
  final bEnd = bStart + (bMinutes < 1 ? 1 : bMinutes);
  return aStart < bEnd && bStart < aEnd;
}

/// 프로그램을 붙일 기존 PT 를 하나로 정할 수 없다(#1581) — 겹치는 예정 세션이
/// 여럿인데 고르지 않았거나, 고른 세션이 그 사이 후보에서 빠졌다.
class ProgramAttachConflictError implements Exception {
  const ProgramAttachConflictError();

  @override
  String toString() => 'ProgramAttachConflictError';
}

/// 잡거나 옮기려는 시간이 트레이너의 다른 일정과 겹쳐 아무것도 바꾸지 않았다.
/// (#2284)
///
/// 서버 409 `schedule_overlap` 이다. 겹친 세션을 들고 다니는 까닭은 "겹칩니다"
/// 만으로는 트레이너가 무엇을 옮겨야 할지 모르기 때문이다 — 화면이 몇 시 누구
/// 일정인지 짚어 준다. 서버가 목록을 싣지 않으면 비어 있다.
class ScheduleOverlapError implements Exception {
  const ScheduleOverlapError([this.conflicts = const <ScheduleSession>[]]);

  final List<ScheduleSession> conflicts;

  @override
  String toString() => 'ScheduleOverlapError(${conflicts.length})';
}

/// 자정부터의 분을 `HH:mm` 으로.
String _hhmm(int minutes) {
  final wrapped = minutes % (24 * 60);
  final hour = (wrapped ~/ 60).toString().padLeft(2, '0');
  final minute = (wrapped % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}
