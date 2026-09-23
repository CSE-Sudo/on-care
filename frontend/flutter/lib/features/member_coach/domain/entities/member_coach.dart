import 'package:oncare/core/points/points_award.dart';

/// The member's assigned trainer (coach) summary — `/me/coach`.
class MemberCoach {
  const MemberCoach({
    required this.trainerId,
    required this.name,
    required this.specialty,
    required this.career,
    required this.intro,
    required this.gymName,
    required this.goal,
  });

  final String trainerId;
  final String name;
  final String specialty;
  final String career;
  final String intro;
  final String gymName;

  /// The coaching goal the trainer set for this member.
  final String goal;
}

/// 하루치 추천 개인운동 — 그날 걸려 있던 목록과 그날 완료(`completed`). (#2161)
///
/// 추천 개인운동은 매일 새로 체크하는 목록이라, 기간을 되짚는 쪽(운동 AI 맞춤
/// 조언, #2162)은 날마다 "무엇이 걸려 있었고 무엇을 했나" 를 읽는다. 실서버의
/// `trainer_service.member_routine_days` 와 같은 모양이다.
typedef RoutineDay = ({DateTime date, List<CoachRoutine> routines});

/// A routine the member received from their coach — `/me/coach/routines`.
class CoachRoutine {
  const CoachRoutine({
    required this.id,
    required this.name,
    required this.minutes,
    required this.type,
    required this.reason,
    required this.source,
    this.intensity = 'moderate',
    this.completed = false,
    this.completedAt,
    this.completedMinutes,
    this.completedIntensity,
    this.trainerFeedback = '',
    this.programName = '',
    this.sessionName = '',
    this.sessionOrder = 0,
    this.exercises = const <CoachRoutineExercise>[],
    this.pointsAward,
    this.sets,
    this.reps,
    this.weight,
  });

  final String id;
  final String name;
  final int minutes;
  final String type;
  final String reason;

  /// 방금 완료해 받은 포인트(#1786). 완료 응답에만 있고, 목록의 루틴은 null 이다.
  /// AI 추천·트레이너 배정 모두 같은 규칙이고 하루 한도를 넘으면 0 이다.
  final PointsAward? pointsAward;

  /// `ai` (AI-suggested) or `trainer` (hand-assigned).
  final String source;

  /// 트레이너가 권하는 강도 — `light` | `moderate` | `high`. (#2160)
  ///
  /// 서버가 배정마다 들고 있던 값인데 회원 앱은 받지 않아, 회원은 이 운동을 어느
  /// 강도로 하라는 것인지 모르고 시작했다. 이 필드를 모르는 옛 응답은 서버
  /// 기본값과 같은 `moderate` 로 읽는다.
  final String intensity;
  final bool completed;
  final DateTime? completedAt;
  final int? completedMinutes;
  final String? completedIntensity;
  final String trainerFeedback;

  /// 여러 세션으로 짜인 프로그램의 이름. 단일 루틴은 빈 문자열이다(#709).
  final String programName;

  /// 이 루틴이 그 프로그램의 어느 세션인가. 세션이 하나뿐이면 빈 문자열.
  final String sessionName;

  /// 프로그램 안에서의 세션 순서(0부터).
  final int sessionOrder;

  /// 이 세션에 담긴 운동 구성. 예전에는 이름만 [reason] 에 이어 붙어 왔다.
  final List<CoachRoutineExercise> exercises;

  /// 근력 루틴의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 null 이다.
  /// (#1276, #1310)
  ///
  /// 서버(`RoutineOut`)와 데모 픽스처가 진작부터 이 셋을 내려보내고 있었는데
  /// 엔티티에 받을 칸이 없어 화면 직전에 버려졌다. 그래서 근력 루틴이 `근력 ·
  /// 10분` 으로만 보였다 — 운동 현황 링·주간 목표는 같은 루틴을 세트로 세는데
  /// 목록만 분으로 적어, 같은 기록이 화면마다 다른 수가 됐다(#1262, #1901).
  final int? sets;
  final int? reps;
  final double? weight;

  /// 이 루틴이 여러 세션짜리 프로그램의 한 세션인가.
  bool get isProgramSession => sessionName.isNotEmpty;

  bool get isTrainerRecommended => source == 'trainer';
  bool get isAiRecommended => source == 'ai';

  CoachRoutine copyWith({
    bool? completed,
    DateTime? completedAt,
    int? completedMinutes,
    String? completedIntensity,
    String? trainerFeedback,
    PointsAward? pointsAward,
  }) => CoachRoutine(
    id: id,
    name: name,
    minutes: minutes,
    type: type,
    reason: reason,
    source: source,
    completed: completed ?? this.completed,
    completedAt: completedAt ?? this.completedAt,
    completedMinutes: completedMinutes ?? this.completedMinutes,
    completedIntensity: completedIntensity ?? this.completedIntensity,
    trainerFeedback: trainerFeedback ?? this.trainerFeedback,
    // 완료만 표시해도 프로그램·세션·운동 구성은 그대로 남아야 한다 — 빠뜨리면
    // 완료를 누른 순간 화면에서 프로그램 제목과 운동이 사라진다(#709).
    programName: programName,
    sessionName: sessionName,
    sessionOrder: sessionOrder,
    exercises: exercises,
    // 세트·횟수·중량은 트레이너가 정한 배정 값이라 완료 표시에 흔들리지 않는다.
    sets: sets,
    reps: reps,
    weight: weight,
    // 적립은 그 응답 한 번의 일이라 복사본에 따라가지 않는다 — 넘길 때만 싣는다.
    pointsAward: pointsAward,
  );
}

/// A PT session the coach booked for the member — `/me/coach/sessions`.
///
/// The trainer owns the schedule: the member can see it but not change it, so
/// this carries no edit affordance. (#490)
class CoachSession {
  /// Creates a booked session.
  const CoachSession({
    required this.id,
    required this.date,
    required this.time,
    required this.type,
    required this.durationMinutes,
    required this.status,
    this.note = '',
    this.program = const <CoachProgramItem>[],
  });

  /// Server id.
  final String id;

  /// `YYYY-MM-DD` parsed. Unparseable dates keep the session out of the
  /// screen rather than throwing — one bad row must not blank the list.
  final DateTime? date;

  /// `HH:MM` as the server sent it.
  final String time;

  /// 1:1 PT · 그룹 · 상담 …
  final String type;

  /// Session length.
  final int durationMinutes;

  /// 예정 | 완료 | 취소 | 노쇼 | 공백.
  ///
  /// 취소·노쇼는 트레이너가 "그 PT 는 진행되지 않았다" 고 남긴 기록이다(#871).
  /// 회원 화면에서는 앞으로의 일정과 섞이지 않는 것이 핵심이다.
  final String status;

  /// The trainer's feedback recorded when completing the session.
  final String note;

  /// The workout program attached by the trainer.
  final List<CoachProgramItem> program;

  /// Whether this session is still ahead.
  ///
  /// **예정인 것만** 앞으로의 일정이다. 예전에는 "완료가 아닌 것" 으로 판정했는데,
  /// 트레이너가 취소·노쇼로 남긴 세션이 생기면서 그 규칙은 진행되지 않은 PT 를
  /// 회원의 '오늘의 일정' 에 그대로 세웠다(#871).
  bool get isUpcoming => status == '예정';

  /// Whether the trainer has completed this session.
  bool get isDone => status == '완료';

  /// 트레이너가 취소한 세션.
  bool get isCancelled => status == '취소';

  /// 회원이 오지 않은 것으로 기록된 세션.
  bool get isNoShow => status == '노쇼';
}

/// One exercise in a trainer-authored PT program.
class CoachProgramItem {
  const CoachProgramItem({
    required this.name,
    required this.sets,
    required this.reps,
    required this.weight,
    this.duration = 0,
  });

  final String name;

  /// 근력 항목의 세트 수·한 세트당 횟수·중량(kg). 트레이너가 적지 않았으면
  /// 0 이다 — 서버가 숫자로 내려주므로 화면도 숫자로 읽는다. 예전에는 `"12회"`
  /// 같은 문자열이라, 서버가 숫자로 바뀐 뒤 이 카드에서 값이 통째로 사라졌다.
  /// (#1276, #1310)
  final int sets;
  final int reps;
  final double weight;

  /// 유산소·스트레칭·기타 항목의 운동 시간(분). 서버는 근력 항목에서는 이 값을
  /// 비우고 세트·횟수·중량을 사용한다.
  final int duration;
}

/// Chat message viewpoint for the member: their own message vs the coach's.
enum CoachSender { me, trainer }

/// A message in the member↔coach thread — `/me/coach/chat`.
class CoachMessage {
  const CoachMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.timeLabel,
    required this.createdAt,
    this.attachment,
    this.reportWeekStart,
    this.emoteId,
  });

  final String id;
  final CoachSender sender;
  final String body;
  final String timeLabel;
  final DateTime createdAt;
  final CoachAttachment? attachment;

  /// 이 메시지가 주간 리포트 등록 안내라면 그 주의 월요일. (#1421)
  ///
  /// 파일명으로 리포트 여부를 추측하지 않는다 — 트레이너가 보낸 사진에
  /// `report` 가 들어 있다고 리포트가 되지는 않는다. 리포트라는 사실은
  /// 보내는 쪽이 실어 보내는 값으로만 판단한다. 트레이너 앱의
  /// `ClientChatMessage.reportWeekStart` 와 같은 값이다.
  final DateTime? reportWeekStart;

  /// 이 메시지가 이모티콘이면 그 id. (#2020)
  ///
  /// 본문(`body`)은 이모티콘을 그리지 못하는 자리(알림·목록의 마지막 메시지)가
  /// 읽는 글이라 함께 온다. 그림은 이 id 로 고른다.
  final String? emoteId;

  bool get fromMe => sender == CoachSender.me;
}

/// 첨부의 종류. 화면이 그릴 방법을 이 값으로 정한다.
///
/// 주간 리포트 PDF(#778)로 시작해 트레이너가 보내는 사진(#921)이 더해졌다.
enum CoachAttachmentKind {
  /// 내려받는다.
  pdf,

  /// 대화 안에서 그린다.
  image;

  static CoachAttachmentKind? parse(Object? value) => switch (value) {
    'pdf' => CoachAttachmentKind.pdf,
    'image' => CoachAttachmentKind.image,
    _ => null,
  };
}

class CoachAttachment {
  const CoachAttachment({
    required this.kind,
    required this.fileName,
    required this.fileId,
    required this.fileSize,
    required this.downloadPath,
  });

  final CoachAttachmentKind kind;

  bool get isImage => kind == CoachAttachmentKind.image;

  final String fileName;
  final String fileId;
  final int fileSize;
  final String downloadPath;
}

/// 배정된 세션 안의 운동 한 항목 — 트레이너 편집기가 적어 준 값 그대로다.
///
/// 세트·횟수·중량은 문자열이다. 트레이너가 "10회"·"자체중량" 처럼 적을 수 있고,
/// 숫자로 바꾸면 그 표현이 사라진다(#709).
/// 배정 세션에 담긴 운동 한 항목. (#709)
///
/// 값은 **수**로 든다(#1904). 서버(`ProgramDraftExercise`)가 `_loose_int` 로
/// 이미 숫자만 남겨 내려보내는데(`"자체중량"` → null, `"10회"` → 10) 이 클래스만
/// 문자열로 받아, 화면이 그 문자열을 다시 `int.tryParse` 로 되짚고 있었다.
///
/// 한 줄 요약은 `coachRoutineExerciseLabel` 이 만든다 — 세트·분·초의 단위는
/// 로케일을 타는데 엔티티는 `AppLocalizations` 에 닿을 수 없다(#1933).
class CoachRoutineExercise {
  const CoachRoutineExercise({
    required this.name,
    this.sets,
    this.reps,
    this.weight,
    this.duration,
    this.rest,
    this.memo = '',
  });

  final String name;

  /// 근력의 세트 수·한 세트당 횟수·중량(kg).
  final int? sets;
  final int? reps;
  final double? weight;

  /// 유산소·스트레칭의 운동 시간(분).
  final int? duration;

  /// 세트 사이 휴식(초). 지금 서버 계약에는 없고, 이 값을 싣던 옛 응답에서만 온다.
  final int? rest;

  final String memo;
}

/// 트레이너가 나에게 보낸 담당 요청. (#919)
///
/// 상담 요청(내가 트레이너에게 보내는 쪽)의 반대 방향이다. 담당 관계는 내
/// 식단·건강 기록을 트레이너에게 여는 일이라, 트레이너가 명단에 넣는 것이
/// 아니라 **내가 수락해야** 성립한다. 화면도 그 순서로 보여 준다.
class CoachInvite {
  const CoachInvite({
    required this.id,
    required this.trainerId,
    required this.trainerName,
    this.gymName,
    this.message,
  });

  final String id;
  final String trainerId;
  final String trainerName;

  /// 트레이너의 소속 헬스장. 누구인지 알아보는 데 이름만으로는 부족할 때가 있다.
  final String? gymName;

  /// 트레이너가 함께 보낸 한마디.
  final String? message;
}
