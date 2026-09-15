import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// `/me/coach` (MemberCoachOut) → [MemberCoach].
MemberCoach memberCoachFromJson(Map<String, Object?> json) {
  final gym = json['gym'];
  return MemberCoach(
    trainerId: _str(json['trainer_id']),
    name: _str(json['name']),
    specialty: _str(json['specialty']),
    career: _str(json['career']),
    intro: _str(json['intro']),
    gymName: gym is Map<String, Object?> ? _str(gym['name']) : '',
    goal: _str(json['goal']),
  );
}

/// `/me/coach/routines` element (RoutineOut) → [CoachRoutine].
CoachRoutine coachRoutineFromJson(Map<String, Object?> json) {
  return CoachRoutine(
    id: _str(json['id']),
    name: _str(json['name']),
    minutes: json['minutes'] is num ? (json['minutes']! as num).toInt() : 0,
    type: _str(json['type']),
    reason: _str(json['reason']),
    source: _str(json['source']),
    completed: json['completed'] == true,
    completedAt: DateTime.tryParse(_str(json['completed_at'])),
    completedMinutes: json['completed_minutes'] is num
        ? (json['completed_minutes']! as num).toInt()
        : null,
    completedIntensity: json['completed_intensity'] as String?,
    trainerFeedback: _str(json['trainer_feedback']),
    programName: _str(json['program_name']),
    sessionName: _str(json['session_name']),
    sessionOrder: json['session_order'] is num
        ? (json['session_order']! as num).toInt()
        : 0,
    exercises: _coachRoutineExercises(json['exercises']),
    // 완료 응답(`RoutineCompleteOut`)에만 있다(#1786).
    pointsAward: PointsAward.fromJson(json['points']),
  );
}

/// `RoutineOut.exercises` → [CoachRoutineExercise] 목록. (#709)
///
/// 키가 아예 없던 예전 응답은 빈 목록이라, 화면이 예전처럼 [CoachRoutine.reason]
/// 만 보여 준다.
List<CoachRoutineExercise> _coachRoutineExercises(Object? raw) {
  if (raw is! List) return const <CoachRoutineExercise>[];
  return <CoachRoutineExercise>[
    for (final entry in raw)
      if (entry is Map<String, Object?>)
        CoachRoutineExercise(
          name: _str(entry['name']),
          sets: _str(entry['sets']),
          reps: _str(entry['reps']),
          weight: _str(entry['weight']),
          duration: _str(entry['duration']),
          rest: _str(entry['rest']),
          memo: _str(entry['memo']),
        ),
  ];
}

/// `/me/coach/sessions` element (ScheduleSessionOut) → [CoachSession].
///
/// 날짜가 깨져도 던지지 않는다 — 한 행 때문에 일정 전체가 사라지면 안 된다.
/// 화면이 date == null 인 항목을 걸러낸다.
CoachSession coachSessionFromJson(Map<String, Object?> json) {
  final Object? rawProgram = json['program'];
  return CoachSession(
    id: _str(json['id']),
    date: DateTime.tryParse(_str(json['date'])),
    time: _str(json['time']),
    type: _str(json['type']),
    durationMinutes: json['duration_minutes'] is num
        ? (json['duration_minutes']! as num).toInt()
        : 0,
    status: _str(json['status']),
    note: _str(json['note']),
    program: rawProgram is List<Object?>
        ? rawProgram
              .map((Object? item) {
                if (item is! Map<String, Object?>) {
                  throw const FormatException('Invalid coach program item.');
                }
                return CoachProgramItem(
                  name: _str(item['name']),
                  // 예전 행에는 `"12회"`·`"80kg"` 같은 문자열이 남아 있다 —
                  // 숫자만 되짚어 읽는다. (#1310)
                  sets: _looseInt(item['sets']),
                  reps: _looseInt(item['reps']),
                  weight: _looseDouble(item['weight']),
                );
              })
              .toList(growable: false)
        : const <CoachProgramItem>[],
  );
}

/// `/me/coach/chat` element (ChatMessageOut) → [CoachMessage]. From the
/// member's viewpoint `sender` is `me` | `trainer`.
CoachMessage coachMessageFromJson(Map<String, Object?> json) {
  final CoachSender sender = switch (json['sender']) {
    'me' => CoachSender.me,
    'trainer' => CoachSender.trainer,
    _ => throw const FormatException('Invalid member chat sender.'),
  };

  return CoachMessage(
    id: _requiredString(json, 'id'),
    sender: sender,
    body: _requiredString(json, 'body'),
    timeLabel: _requiredString(json, 'time_label'),
    createdAt: _requiredDateTime(json, 'created_at'),
    attachment: _attachment(json['attachment']),
    reportWeekStart: _reportWeekStart(json['report_week_start']),
  );
}

/// 리포트 등록 안내라면 그 주 월요일. (#1600)
///
/// 파일명이나 본문으로 추측하지 않는다 — 서버가 실어 보낸 값만 본다. 값이
/// 날짜가 아니면 표시를 포기하고 일반 메시지로 둔다: 안내 상자 하나 때문에
/// 대화 전체가 뜨지 않는 편보다 낫다.
DateTime? _reportWeekStart(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

CoachAttachment? _attachment(Object? value) {
  if (value == null) return null;
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid member chat attachment.');
  }
  // 모르는 종류는 조용히 지나치지 않는다 — 그릴 방법을 모르는 첨부를 빈 자리로
  // 두면, 트레이너는 보냈다고 믿고 회원은 아무것도 못 본다.
  final kind = CoachAttachmentKind.parse(value['type']);
  if (kind == null) {
    throw const FormatException('Invalid member chat attachment.');
  }
  final size = value['file_size'];
  if (size is! int || size < 0) {
    throw const FormatException('Invalid chat attachment size.');
  }
  return CoachAttachment(
    kind: kind,
    fileName: _requiredString(value, 'file_name'),
    fileId: _requiredString(value, 'file_id'),
    fileSize: size,
    downloadPath: _requiredString(value, 'download_path'),
  );
}

String _str(Object? v) => v is String ? v : '';

/// 숫자이거나, 숫자를 품은 옛 문자열("12회")이거나, 아무것도 아니거나. (#1310)
int _looseInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is! String) return 0;
  final String digits = v.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? 0 : int.parse(digits);
}

/// [_looseInt] 의 소수 판 — 중량("80kg"·"12.5")용.
double _looseDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is! String) return 0;
  return double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is String) return value;
  throw FormatException('Invalid member chat $key.');
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Invalid member chat $key.');
}

/// `MemberClientInviteOut` → [CoachInvite]. (#919)
CoachInvite coachInviteFromJson(Map<String, Object?> json) => CoachInvite(
  id: json['id']! as String,
  trainerId: json['trainer_id'] as String? ?? '',
  trainerName: json['trainer_name'] as String? ?? '',
  gymName: json['gym_name'] as String?,
  message: json['message'] as String?,
);
