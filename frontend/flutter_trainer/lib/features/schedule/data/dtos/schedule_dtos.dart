import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';

/// Maps the FastAPI `ScheduleSessionOut` JSON onto [ScheduleSession].
///
/// Every field is read defensively: a slot with one unexpected value
/// should render with a blank field, not blank the whole timeline.
ScheduleSession scheduleSessionFromJson(Map<String, dynamic> json) {
  return ScheduleSession(
    id: _str(json['id']),
    date: _str(json['date']),
    time: _str(json['time']),
    // 서버는 고객을 member_id 로 참조한다. 빈 문자열은 미등록(상담) 슬롯이라
    // null 로 눕혀 이름 폴백 경로와 같은 의미가 되게 한다(#386).
    clientId: _str(json['member_id']).isEmpty ? null : _str(json['member_id']),
    clientName: _str(json['client_name']),
    type: _str(json['type']),
    durationMinutes: _int(json['duration_minutes']),
    status: _str(json['status']),
    note: _str(json['note']),
    program: _programFromJson(json['program']),
    programSent: json['program_sent'] == true,
    cancelledAt: _time(json['cancelled_at']),
    cancellationSource: _str(json['cancellation_source']),
    cancellationReason: _str(json['cancellation_reason']),
    noShowAt: _time(json['no_show_at']),
  );
}

/// Encodes a program for `ScheduleCreateRequest` / `ScheduleUpdateRequest`.
List<Map<String, Object?>> programToJson(List<ProgramItem> program) {
  return <Map<String, Object?>>[
    for (final item in program) programItemToJson(item),
  ];
}

/// `일정 추가` 명령 본문 — 배정 본문([assignment])에 일정 칸을 더한다(#1580).
/// 시간 길이는 이 경계에 오기 전에 트레이너가 고른 시작·종료로 계산돼 있다.
Map<String, Object?> programScheduleToJson({
  required Map<String, Object?> assignment,
  required String date,
  required String time,
  required int durationMinutes,
  required String clientName,
  String? sessionId,
}) => <String, Object?>{
  ...assignment,
  'date': date,
  'time': time,
  'duration_minutes': durationMinutes,
  'client_name': clientName,
  'session_id': ?sessionId,
};

/// 항목 하나의 계약 형태. 서버 `ProgramItem` 스키마와 1:1 이다 (#1276).
///
/// 유형에 맞지 않는 칸은 싣지 않는다([ProgramItem.byType]) — 유산소를 세트로
/// 적은 항목이 한 번 저장되면 그 뒤로는 모든 화면이 그렇게 읽는다.
Map<String, Object?> programItemToJson(ProgramItem raw) {
  final ProgramItem item = raw.byType;
  return <String, Object?>{
    'name': item.name,
    'type': item.type,
    'date': item.date == null ? null : ymd(item.date!),
    'duration': item.duration,
    'sets': item.sets,
    'reps': item.reps,
    'weight': item.weight,
    'intensity': item.intensity,
    'session': item.session,
  };
}

List<ProgramItem> _programFromJson(Object? raw) {
  if (raw is! List) return const <ProgramItem>[];
  return <ProgramItem>[
    for (final entry in raw)
      if (entry is Map<String, dynamic>) programItemFromJson(entry),
  ];
}

/// 계약 형태 → [ProgramItem].
///
/// 세트·중량·시간은 예전에 자유 문자열("10회"·"20kg")로 저장됐다 — 숫자만
/// 되짚어 읽는다(#1276). 서버의 `LooseInt`/`LooseFloat` 와 같은 규칙이다.
///
/// 유형과 맞지 않는 칸은 읽으면서 버린다([ProgramItem.byType]) — 규칙이 서기
/// 전에 저장된 행이 그대로 남아 있어, 읽는 쪽에서 거르지 않으면 `유산소
/// 3세트 · 30회` 같은 줄이 계속 화면에 뜬다.
ProgramItem programItemFromJson(Map<String, Object?> entry) => ProgramItem(
  name: _str(entry['name']),
  // 이 키가 없던 예전 일정은 기본값으로 읽힌다(#1233).
  type: entry['type'] is String && (entry['type'] as String).isNotEmpty
      ? entry['type'] as String
      : '근력',
  date: DateTime.tryParse(_str(entry['date'])),
  duration: looseInt(entry['duration']),
  sets: looseInt(entry['sets']),
  reps: looseInt(entry['reps']),
  weight: looseDouble(entry['weight']),
  intensity:
      entry['intensity'] is String && (entry['intensity'] as String).isNotEmpty
      ? entry['intensity'] as String
      : 'moderate',
  // 세션 키가 없던 예전 일정은 빈 문자열 — 평면 목록으로 읽힌다(#709).
  session: _str(entry['session']),
).byType;

/// 숫자거나 숫자를 품은 문자열("10회")이면 정수로. 아니면 null.
int? looseInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is! String) return null;
  final String digits = v.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.parse(digits);
}

/// [looseInt] 의 소수 판 — 중량("20kg"·"12.5")용.
double? looseDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is! String) return null;
  return double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), ''));
}

String _str(Object? v) => v is String ? v : '';

/// 서버 타임스탬프. 값이 없거나 읽을 수 없으면 null — 취소 시각 하나 때문에
/// 하루 전체가 비지 않게 한다(다른 필드와 같은 방어 규약).
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

// FastAPI emits JSON numbers that can decode as double on web — normalise
// through num so `as int` never throws.
int _int(Object? v) => v is num ? v.toInt() : 0;
