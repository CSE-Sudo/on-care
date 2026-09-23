/// 운동 AI 맞춤 조언 한 마디 — 문장 키·값과 한국어 문장. (#2210)
///
/// 서버(`GET /exercise/advice`)는 한국어 문장(`message`)과 함께 **로케일과 무관한
/// 키와 값**(`advice_key`·`advice_params`)을 준다. 앱은 키로 자기 언어의 ARB
/// 문장을 그리고, 모르는 키면 받은 한국어 문장을 그대로 쓴다 — 홈 통합 조언
/// (`ai_advice_text.dart`, #1943)과 같은 방식이다.
///
/// 키와 한국어 문장의 원본은 서버 `backend/app/services/exercise_advice.py` 다.
/// `app_ko.arb` 의 `exerciseAdvice…` 가 같은 문장을 적고, 두 쪽이 글자까지 같은지는
/// 공유 사례(`test/core/demo/routine_advice_cases.json`)로 본다.
library;

import 'package:oncare/gen/l10n/app_localizations.dart';

/// 조언 한 마디.
class ExerciseAdvice {
  const ExerciseAdvice({
    required this.message,
    this.key,
    this.params = const <String, Object>{},
  });

  /// 서버 응답(`ExerciseAdviceResponse`)에서.
  factory ExerciseAdvice.fromJson(Map<String, Object?> json) => ExerciseAdvice(
    message: (json['message'] as String?) ?? '',
    key: json['advice_key'] as String?,
    params: <String, Object>{
      for (final MapEntry<String, Object?> e
          in ((json['advice_params'] as Map<String, Object?>?) ??
                  const <String, Object?>{})
              .entries)
        if (e.value != null) e.key: e.value!,
    },
  );

  /// 한국어 문장. 키를 모르거나 값이 맞지 않으면 화면이 이 문장을 쓴다.
  final String message;

  /// 문장 키(`routine_today_next` 등). 없으면 [message] 만 있다.
  final String? key;

  /// 문장에 드는 값 — 수, 운동 유형·부위 코드, 운동 이름.
  final Map<String, Object> params;
}

/// 마지막 글자에 받침이 있나. 한글로 끝나지 않으면 null — 조사를 정할 수 없다.
/// 서버 `exercise_advice.has_final_consonant` 와 같다.
bool? hasFinalConsonant(String word) {
  String stripped = word;
  while (stripped.isNotEmpty &&
      ' )]}'.contains(stripped[stripped.length - 1])) {
    stripped = stripped.substring(0, stripped.length - 1);
  }
  if (stripped.isEmpty) return null;
  final int last = stripped.runes.last;
  if (last < 0xAC00 || last > 0xD7A3) return null;
  return (last - 0xAC00) % 28 != 0;
}

String _particle(String word, String withFinal, String withoutFinal) {
  final bool? finalConsonant = hasFinalConsonant(word);
  if (finalConsonant == null) return '$withFinal($withoutFinal)';
  return finalConsonant ? withFinal : withoutFinal;
}

/// 이름 뒤 목적격 조사(을/를). 한국어 ARB 만 쓰고 영어 문장은 무시한다.
String _obj(Object? name) => _particle(_str(name), '을', '를');

/// 이름 뒤 주격 조사(이/가).
String _subj(Object? name) => _particle(_str(name), '이', '가');

String _str(Object? value) {
  if (value is String) return value;
  throw FormatException('조언 값이 문자열이 아니다: $value');
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('조언 값이 수가 아니다: $value');
}

/// [advice] 를 [l] 의 언어로. 모르는 키이거나 값이 맞지 않으면 한국어 [message].
String exerciseAdviceText(AppLocalizations l, ExerciseAdvice advice) {
  final String? key = advice.key;
  if (key == null) return advice.message;
  try {
    return _localized(l, key, advice.params) ?? advice.message;
  } on FormatException {
    return advice.message;
  }
}

/// 서버가 새 키를 먼저 내려도 화면이 비지 않게, 모르는 키는 null 이다.
String? _localized(
  AppLocalizations l,
  String key,
  Map<String, Object> p,
) => switch (key) {
  'record_empty_today' => l.exerciseAdviceRecordEmptyToday,
  'record_empty_week' => l.exerciseAdviceRecordEmptyWeek,
  'record_empty_all' => l.exerciseAdviceRecordEmptyAll,
  'record_today' => l.exerciseAdviceRecordToday(
    _int(p['calories']),
    _int(p['minutes']),
    _str(p['type']),
  ),
  'record_week_one_day' => l.exerciseAdviceRecordWeekOneDay(_int(p['minutes'])),
  'record_week_skew' => l.exerciseAdviceRecordWeekSkew(
    _int(p['days']),
    _int(p['minutes']),
    _str(p['missing']),
    _str(p['top']),
  ),
  'record_week_balanced' => l.exerciseAdviceRecordWeekBalanced(
    _int(p['days']),
    _int(p['minutes']),
  ),
  'record_all_up' => l.exerciseAdviceRecordAllUp,
  'record_all_down' => l.exerciseAdviceRecordAllDown,
  'record_all_steady' => l.exerciseAdviceRecordAllSteady(
    _int(p['days']),
    _int(p['minutes']),
    _int(p['weeks']),
  ),
  'routine_today_all_done' => l.exerciseAdviceRoutineTodayAllDone(
    _int(p['count']),
  ),
  'routine_today_done_next_order' => l.exerciseAdviceRoutineTodayDoneNextOrder(
    _str(p['done']),
    _obj(p['done']),
    _str(p['next']),
    _str(p['then']),
  ),
  'routine_today_done_next' => l.exerciseAdviceRoutineTodayDoneNext(
    _str(p['done']),
    _obj(p['done']),
    _str(p['next']),
  ),
  'routine_today_next_order' => l.exerciseAdviceRoutineTodayNextOrder(
    _str(p['next']),
    _str(p['then']),
  ),
  'routine_today_next' => l.exerciseAdviceRoutineTodayNext(_str(p['next'])),
  'routine_today_left' => l.exerciseAdviceRoutineTodayLeft(_int(p['count'])),
  'routine_today_start_order' => l.exerciseAdviceRoutineTodayStartOrder(
    _str(p['next']),
    _str(p['then']),
  ),
  'routine_today_start' => l.exerciseAdviceRoutineTodayStart(_str(p['next'])),
  'routine_week_none_today' => l.exerciseAdviceRoutineWeekNoneToday(
    _str(p['next']),
  ),
  'routine_week_none_next' => l.exerciseAdviceRoutineWeekNoneNext(
    _str(p['next']),
  ),
  'routine_week_none' => l.exerciseAdviceRoutineWeekNone,
  'routine_week_only' => l.exerciseAdviceRoutineWeekOnly(
    _str(p['missing']),
    _str(p['rest']),
    _str(p['top']),
  ),
  'routine_week_only_short' => l.exerciseAdviceRoutineWeekOnlyShort(
    _str(p['top']),
  ),
  'routine_week_skew' => l.exerciseAdviceRoutineWeekSkew(
    _str(p['missing']),
    _str(p['rest']),
    _int(p['share']),
    _str(p['top']),
  ),
  'routine_week_skew_short' => l.exerciseAdviceRoutineWeekSkewShort(
    _int(p['share']),
    _str(p['top']),
  ),
  'routine_week_praise' => l.exerciseAdviceRoutineWeekPraise(_str(p['how'])),
  'routine_week_counts_today' => l.exerciseAdviceRoutineWeekCountsToday(
    _int(p['assigned']),
    _int(p['completed']),
    _str(p['next']),
  ),
  'routine_week_counts_keep' => l.exerciseAdviceRoutineWeekCountsKeep(
    _int(p['assigned']),
    _int(p['completed']),
    _str(p['rest']),
  ),
  'routine_week_counts' => l.exerciseAdviceRoutineWeekCounts(
    _int(p['assigned']),
    _int(p['completed']),
  ),
  'routine_last_week_none_next' => l.exerciseAdviceRoutineLastWeekNoneNext(
    _str(p['next']),
  ),
  'routine_last_week_none' => l.exerciseAdviceRoutineLastWeekNone,
  'routine_last_week_only' => l.exerciseAdviceRoutineLastWeekOnly(
    _str(p['missing']),
    _str(p['top']),
  ),
  'routine_last_week_only_short' => l.exerciseAdviceRoutineLastWeekOnlyShort(
    _str(p['top']),
  ),
  'routine_last_week_skew' => l.exerciseAdviceRoutineLastWeekSkew(
    _str(p['missing']),
    _int(p['share']),
    _str(p['top']),
  ),
  'routine_last_week_skew_short' => l.exerciseAdviceRoutineLastWeekSkewShort(
    _int(p['share']),
    _str(p['top']),
  ),
  'routine_last_week_praise' => l.exerciseAdviceRoutineLastWeekPraise(
    _str(p['how']),
  ),
  'routine_last_week_counts_more' => l.exerciseAdviceRoutineLastWeekCountsMore(
    _int(p['assigned']),
    _int(p['completed']),
  ),
  'routine_last_week_counts' => l.exerciseAdviceRoutineLastWeekCounts(
    _int(p['assigned']),
    _int(p['completed']),
  ),
  'routine_all_new' => l.exerciseAdviceRoutineAllNew(_int(p['days'])),
  'routine_all_none_next' => l.exerciseAdviceRoutineAllNoneNext(
    _int(p['days']),
    _str(p['next']),
  ),
  'routine_all_none' => l.exerciseAdviceRoutineAllNone(_int(p['days'])),
  'routine_all_done_today_part' => l.exerciseAdviceRoutineAllDoneTodayPart(
    _str(p['part']),
  ),
  'routine_all_done_today_name' => l.exerciseAdviceRoutineAllDoneTodayName(
    _str(p['name']),
    _obj(p['name']),
  ),
  'routine_all_done_today_name_plain' =>
    l.exerciseAdviceRoutineAllDoneTodayNamePlain(_str(p['name'])),
  'routine_all_done_today' => l.exerciseAdviceRoutineAllDoneToday,
  'routine_all_missed_part' => l.exerciseAdviceRoutineAllMissedPart(
    _str(p['part']),
  ),
  'routine_all_missed_part_short' => l.exerciseAdviceRoutineAllMissedPartShort(
    _str(p['part']),
  ),
  'routine_all_missed_name' => l.exerciseAdviceRoutineAllMissedName(
    _str(p['name']),
    _subj(p['name']),
  ),
  'routine_all_missed_name_short' => l.exerciseAdviceRoutineAllMissedNameShort(
    _str(p['name']),
    _subj(p['name']),
  ),
  'routine_all_missed_name_plain' => l.exerciseAdviceRoutineAllMissedNamePlain(
    _str(p['name']),
  ),
  'routine_all_missed_name_plain_short' =>
    l.exerciseAdviceRoutineAllMissedNamePlainShort(_str(p['name'])),
  'routine_all_missed' => l.exerciseAdviceRoutineAllMissed,
  'routine_all_praise' => l.exerciseAdviceRoutineAllPraise(_int(p['weeks'])),
  'routine_all_rate' => l.exerciseAdviceRoutineAllRate(_int(p['pct'])),
  _ => null,
};
