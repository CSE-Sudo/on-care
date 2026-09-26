/// 식단 AI 맞춤 조언 — 규칙 한 줄 + 다음 할 일 한 문장. (#2251, #2255)
///
/// 서버(`GET /diet/advice`)는 두 문장을 한국어로(`analysis`·`action`), 그리고
/// **로케일과 무관한 키와 값**(`analysis_key/params`·`action_key/params`)으로 함께
/// 준다. 앱은 키로 자기 언어의 ARB 문장을 그리고, 모르는 키면 받은 문장을 그대로
/// 쓴다 — 운동 조언(`exercise_advice.dart`, #2210)과 같은 방식이다.
///
/// 키가 없는 문장은 AI 가 요청 언어(`lang`)로 만든 것이다. 그대로 쓴다.
///
/// 메뉴 이름·수치는 `**` 로 감싸 온다. ARB 문장도 같은 표시를 쓰지만, 카드는 굵게
/// 그리지 않고 표시만 뗀다(#2255 — 운동 카드와 같은 평문). 강조를 켤 때를 위해
/// 표시는 남겨 둔다.
///
/// 키와 한국어 문장의 원본은 서버 `backend/app/services/diet_advice_copy.py` 다.
/// `app_ko.arb` 의 `dietAdvice…` 가 같은 문장을 적고, 두 쪽이 글자까지 같은지는
/// 공유 사례(`test/core/demo/diet_advice_cases.json`)로 본다.
library;

import 'package:oncare/gen/l10n/app_localizations.dart';

/// 조언 한 문장.
class DietAdviceLine {
  const DietAdviceLine({
    required this.text,
    this.key,
    this.params = const <String, Object>{},
  });

  /// 받은 문장(`**` 표시 포함). 키가 없거나 모르는 키면 화면이 이것을 쓴다.
  final String text;

  /// 문장 키(`today_protein_left` 등). 없으면 AI 가 만든 문장이다.
  final String? key;

  /// 문장에 드는 값 — 수, 끼니·주 코드, 메뉴·음식 이름.
  final Map<String, Object> params;
}

/// 서버 응답(`DietAdviceResponse`).
class DietAdvice {
  const DietAdvice({
    required this.message,
    this.analysis,
    this.action,
    this.actionSource,
  });

  factory DietAdvice.fromJson(Map<String, Object?> json) {
    DietAdviceLine? read(String prefix) {
      final String text = (json[prefix] as String?) ?? '';
      final String? key = json['${prefix}_key'] as String?;
      if (text.isEmpty && key == null) return null;
      return DietAdviceLine(
        text: text,
        key: key,
        params: <String, Object>{
          for (final MapEntry<String, Object?> e
              in ((json['${prefix}_params'] as Map<String, Object?>?) ??
                      const <String, Object?>{})
                  .entries)
            if (e.value != null) e.key: e.value!,
        },
      );
    }

    return DietAdvice(
      message: (json['message'] as String?) ?? '',
      analysis: read('analysis'),
      action: read('action'),
      actionSource: json['action_source'] as String?,
    );
  }

  /// 두 문장을 이은 한국어 평문. 두 문장을 모르는 서버(옛 응답)면 이것만 온다.
  final String message;

  /// 규칙 한 줄.
  final DietAdviceLine? analysis;

  /// 다음 할 일 한 문장. 없을 수 있다(밤늦게 기록이 없을 때 등).
  final DietAdviceLine? action;

  /// 다음 할 일의 출처 — `plan`(추천 메뉴 리스트)·`rules`·`llm`.
  final String? actionSource;
}

String _str(Object? value) {
  if (value is String) return value;
  throw FormatException('조언 값이 문자열이 아니다: $value');
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('조언 값이 수가 아니다: $value');
}

/// [advice] 를 [l] 의 언어로 — 두 문장을 한 칸 띄워 잇는다. `**` 표시는 남긴다.
String dietAdviceText(AppLocalizations l, DietAdvice advice) {
  final DietAdviceLine? analysis = advice.analysis;
  if (analysis == null) return advice.message;
  final DietAdviceLine? action = advice.action;
  return <String>[
    dietAdviceLineText(l, analysis),
    if (action != null) dietAdviceLineText(l, action),
  ].where((String s) => s.isNotEmpty).join(' ');
}

/// 한 문장을 [l] 의 언어로. 키가 없거나 모르는 키, 맞지 않는 값이면 받은 문장.
String dietAdviceLineText(AppLocalizations l, DietAdviceLine line) {
  final String? key = line.key;
  if (key == null) return line.text;
  try {
    return dietAdviceKeyText(l, key, line.params) ?? line.text;
  } on FormatException {
    return line.text;
  }
}

/// 키와 값 → [l] 의 문장. 서버가 새 키를 먼저 내려도 화면이 비지 않게, 모르는
/// 키는 null 이다. 데모(`core/demo/diet_advice.dart`)도 이것으로 한국어 문장을 만든다.
String? dietAdviceKeyText(
  AppLocalizations l,
  String key,
  Map<String, Object> p,
) => switch (key) {
  'today_empty' => l.dietAdviceTodayEmpty,
  'today_missing_meal' => l.dietAdviceTodayMissingMeal,
  'today_sodium_over' => l.dietAdviceTodaySodiumOver(_int(p['sodium_mg'])),
  'today_calorie_over' => l.dietAdviceTodayCalorieOver(_int(p['kcal'])),
  'today_protein_left' => l.dietAdviceTodayProteinLeft(_int(p['protein_g'])),
  'today_balanced' => l.dietAdviceTodayBalanced(_int(p['kcal'])),
  'next_meal' => l.dietAdviceNextMeal(_str(p['slot']), _str(p['menu'])),
  'next_snack' => l.dietAdviceNextSnack(_str(p['menu'])),
  'today_done' => l.dietAdviceTodayDone,
  'today_log_first' => l.dietAdviceTodayLogFirst,
  'week_empty' => l.dietAdviceWeekEmpty,
  'week_skip_breakfast' => l.dietAdviceWeekSkipBreakfast(
    _str(p['scope']),
    _int(p['days']),
  ),
  'week_skip_breakfast_snack' => l.dietAdviceWeekSkipBreakfastSnack(
    _str(p['scope']),
    _int(p['days']),
    _int(p['snack_days']),
  ),
  'week_focus_sodium' => l.dietAdviceWeekFocusSodium(
    _str(p['scope']),
    _int(p['days']),
  ),
  'week_focus_calorie' => l.dietAdviceWeekFocusCalorie(
    _str(p['scope']),
    _int(p['days']),
  ),
  'week_focus_sugar' => l.dietAdviceWeekFocusSugar(
    _str(p['scope']),
    _int(p['days']),
  ),
  'week_focus_protein' => l.dietAdviceWeekFocusProtein(
    _str(p['scope']),
    _int(p['days']),
  ),
  'week_good' => l.dietAdviceWeekGood(_str(p['scope']), _int(p['days'])),
  'week_empty_hint' => l.dietAdviceWeekEmptyHint,
  'tip_breakfast' => l.dietAdviceTipBreakfast,
  'tip_sodium' => l.dietAdviceTipSodium,
  'tip_calorie' => l.dietAdviceTipCalorie,
  'tip_sugar' => l.dietAdviceTipSugar,
  'tip_protein' => l.dietAdviceTipProtein,
  'tip_keep' => l.dietAdviceTipKeep,
  'all_few_records' => l.dietAdviceAllFewRecords(_int(p['days'])),
  'all_slot_sodium' => l.dietAdviceAllSlotSodium(
    _str(p['slot']),
    _int(p['days']),
  ),
  'all_carb_heavy' => l.dietAdviceAllCarbHeavy(_int(p['pct'])),
  'all_protein_light' => l.dietAdviceAllProteinLight(_int(p['pct'])),
  'all_protein_trend_up' => l.dietAdviceAllProteinTrendUp(
    _int(p['before']),
    _int(p['after']),
  ),
  'all_protein_trend_down' => l.dietAdviceAllProteinTrendDown(
    _int(p['before']),
    _int(p['after']),
  ),
  'all_frequent_menu' => l.dietAdviceAllFrequentMenu(
    _str(p['slot']),
    _str(p['food']),
    _int(p['count']),
  ),
  'all_repeated_foods' => l.dietAdviceAllRepeatedFoods(
    _str(p['food1']),
    _str(p['food2']),
  ),
  'all_good' => l.dietAdviceAllGood(_int(p['days'])),
  'all_few_hint' => l.dietAdviceAllFewHint,
  'tip_carb' => l.dietAdviceTipCarb,
  'tip_swap' => l.dietAdviceTipSwap,
  'tip_variety' => l.dietAdviceTipVariety,
  _ => null,
};
