import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// One past workout in a client's history (운동기록 sub-tab). Decoded
/// from the drift `ClientRoutineHistory` row (`exercisesJson` becomes
/// the [exercises] list).
class RoutineHistoryEntry {
  /// Creates a history entry.
  const RoutineHistoryEntry({
    this.id = '',
    required this.dateLabel,
    required this.label,
    required this.completionRate,
    required this.exercises,
    required this.clientFeedback,
    required this.trainerNote,
    this.assignedRoutineId,
    this.completedAt,
    this.date,
    this.kind,
  });

  /// Stable history id used when editing feedback.
  final String id;

  /// Display date (e.g. "7/12 (오늘)").
  ///
  /// 서버·데모가 한국어로 만든 문장이다. 화면은 [routineHistoryDateLabel] 로
  /// 그린다 — [date] 가 있으면 화면 언어로 다시 만든다(#2300).
  final String dateLabel;

  /// Session kind (e.g. "PT 세션 · 트레이너 지도").
  ///
  /// 저장된 이름 그대로다. 화면은 [routineKindLabel] 로 그린다.
  final String label;

  /// 0–100 completion.
  final int completionRate;

  /// 그 세션의 운동들. 값까지 든다(#1902) — 예전에는 `벤치프레스 4세트 · 10회 ·
  /// 40kg ✓` 처럼 이름·수·수행 표시가 한 문자열에 뭉쳐 있었다. 한 줄로 읽히는
  /// 표기는 화면이 만든다(단위는 로케일을 탄다, #1933).
  final List<ClientExerciseItem> exercises;

  /// Client's feedback (may be empty).
  final String clientFeedback;

  /// Trainer's note (may be empty — the note box is hidden then).
  final String trainerNote;

  /// Present only when this history row came from an assigned routine.
  final String? assignedRoutineId;

  /// 운동을 마친 시각. 실 API 는 `completed_at` 으로 늘 채워 주고, 데모는
  /// 시드가 오늘 위에 얹은 날짜를 준다. [dateLabel] 은 화면에 그릴 문자열일
  /// 뿐이라 기간을 판단하는 데 쓸 수 없다 — 거르는 쪽은 언제나 이 값이다.
  final DateTime? completedAt;

  /// 이 기록이 붙는 날(`date`, #2300). [dateLabel] 을 만든 바로 그 날이다.
  ///
  /// [completedAt] 과 다를 수 있다 — 배정 수행은 지난 주 운동을 오늘 고친
  /// 기록도 그 운동을 한 날로 붙는다(#1264). 옛 서버는 주지 않는다.
  final DateTime? date;

  /// [label] 이 서버가 붙인 고정 이름이면 그 코드(`pt_session`·`ai_personal`·
  /// `assigned_routine`). 트레이너가 지은 이름이면 null 이다(#2300).
  final String? kind;
}

/// 이 기록이 붙는 날 — KST 달력일, 시각은 0시. 모르면 `null`. (#2748)
///
/// 서버가 정한 운동일([RoutineHistoryEntry.date])이 먼저다. 지난 날짜로 소급
/// 체크한 기록(#2506)이나 지난 주 운동을 오늘 고친 배정 기록(#1264)은 완료 시각이
/// 오늘이어도 그 운동을 한 날에 붙어야 한다.
///
/// `date` 를 주지 않는 옛 서버는 완료 시각으로 정한다. 실 API 의 완료 시각은
/// UTC 라 그대로 날짜를 자르면 KST 오전 9시 전에 마친 운동이 전날로 간다 — KST
/// 로 옮긴 뒤 자른다. UTC 가 아닌 값(데모가 KST 벽시계로 만든 시각)은 그대로
/// 자른다.
///
/// 일자 묶음·기간 필터·메모 참조 날짜가 모두 이 함수를 쓴다. 한 곳이라도 다른
/// 기준을 쓰면 카드가 놓인 줄과 메모가 가리키는 날이 갈린다.
DateTime? historyDayOf(RoutineHistoryEntry entry) {
  final DateTime? date = entry.date;
  if (date != null) return DateTime(date.year, date.month, date.day);
  final DateTime? at = entry.completedAt;
  if (at == null) return null;
  final DateTime wall = at.isUtc ? at.add(kstOffset) : at;
  return DateTime(wall.year, wall.month, wall.day);
}

/// [range] 안에 있는 기록만. 시작·끝 모두 **포함**이고 시각은 버린다 —
/// 서버가 주는 완료 시각은 하루 중 아무 때나이므로, 마지막 날 0시와 견주면
/// 그날 저녁 운동이 통째로 빠진다.
///
/// 날짜는 [historyDayOf] 로 정한다 — 화면의 일자 묶음과 같은 기준이다(#2748).
///
/// 날짜를 모르는 기록은 **늘 남긴다**. 날짜를 모르는 것과 그 기간이 아닌 것은
/// 다른 말이고, 모른다고 숨기면 트레이너 눈에는 기록이 사라진 것으로
/// 보인다(#1114).
List<RoutineHistoryEntry> historyInRange(
  Iterable<RoutineHistoryEntry> entries,
  ClientDateRange range,
) {
  final DateTime from = DateTime(
    range.from.year,
    range.from.month,
    range.from.day,
  );
  final DateTime to = DateTime(range.to.year, range.to.month, range.to.day);
  return entries
      .where((RoutineHistoryEntry entry) {
        final DateTime? day = historyDayOf(entry);
        if (day == null) return true;
        return !day.isBefore(from) && !day.isAfter(to);
      })
      .toList(growable: false);
}

/// 서버가 붙이는 고정 이름 → 종류 코드. 서버 `_HISTORY_KIND_CODES` 와 같다.
///
/// 코드를 주지 않는 옛 서버와, 이름만 저장하는 데모 DB 의 행도 같은 문구로
/// 그리려고 이름에서도 코드를 되짚는다.
const Map<String, String> _kindByStoredLabel = <String, String>{
  'PT 세션 · 트레이너 지도': 'pt_session',
  'AI 개인운동': 'ai_personal',
  // 옛 시드·픽스처의 이름. 지금은 `AI 개인운동` 으로 부른다(#1453).
  'AI 루틴 · 자율 운동': 'ai_personal',
  '배정 루틴 수행': 'assigned_routine',
  '개인운동': 'personal_routine',
};

/// 화면에 그리는 기록 종류 이름. (#1453, #2300)
///
/// 서버가 붙인 고정 이름은 [kind] 코드로(없으면 저장된 이름에서 되짚어) 화면
/// 언어의 문구를 고른다 — 저장된 문자열을 고치는 마이그레이션 없이 옛 행과 데모
/// DB 까지 같은 이름으로 보인다. 트레이너가 지은 이름은 그대로 둔다.
String routineKindLabel(AppLocalizations l, String raw, {String? kind}) {
  final String? code = routineKindCode(raw, kind: kind);
  return switch (code) {
    'pt_session' => l.workoutKindPtSession,
    // 하루치 개인운동 카드는 `개인운동` 이다(#2510) — 데모·옛 서버의 `AI 개인운동`
    // 도 같은 하루치 카드라 같은 이름으로 부른다. AI 가 짠 것만 담는 카드가
    // 아니다(트레이너가 보낸 것도 섞인다).
    'ai_personal' || 'personal_routine' => l.workoutKindPersonal,
    // 서버는 이름 없는 배정에만 이 코드를 붙인다 — 이름이 있으면 코드가 없다.
    'assigned_routine' => l.workoutKindAssignedRoutine,
    _ => raw,
  };
}

/// 이력의 종류 코드(`pt_session`·`ai_personal`·`assigned_routine`). 서버가 준
/// [kind] 가 없으면(데모·옛 서버) 저장된 고정 이름으로 찾는다 — [routineKindLabel]
/// 과 같은 규칙이다. 트레이너가 지은 이름이면 null.
String? routineKindCode(String raw, {String? kind}) =>
    kind ?? _kindByStoredLabel[raw.trim()];

/// 기록 카드의 날짜 문구 — `9/27 (오늘)` / `9/27 (Today)`. (#2300)
///
/// [RoutineHistoryEntry.date] 가 있으면 화면 언어로 만들고, 없는 옛 서버의
/// 기록만 받은 문장([RoutineHistoryEntry.dateLabel])을 그대로 쓴다.
String routineHistoryDateLabel(
  AppLocalizations l,
  RoutineHistoryEntry entry, {
  DateTime? now,
}) {
  final DateTime? date = entry.date;
  return date == null ? entry.dateLabel : historyDateLabel(l, date, now: now);
}
