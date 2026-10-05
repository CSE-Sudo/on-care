import 'package:intl/intl.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// `식단 분석` 문장 → 화면 언어의 문장. (#2379)
///
/// 서버 `diet_trainer_analysis` 의 한국어·영어 틀과 **같은 문장**이어야 한다 — 공유
/// 사례 파일의 `renderings` 로 테스트가 본다. 모르는 키면 null 이다(서버가 먼저 새
/// 키를 내보낸 경우) — 카드는 그 문장만 빼고 그린다.
String? clientDietSentenceText(AppLocalizations l, ClientDietSentence s) {
  final Map<String, Object> p = s.params;
  String str(String k) => '${p[k] ?? ''}';
  int number(String k) => (p[k] as num?)?.toInt() ?? 0;
  final String nutrient = str('nutrient');
  // 단위는 한국어 붙임(`4,286mg`), 영어 띄움(`4,286 mg`) — 서버 `_fmt` 와 같다(#3120).
  final bool spaced = !l.localeName.startsWith('ko');
  String amount(String k, [String? of]) =>
      formatDietAmount(number(k), of ?? nutrient, spaced: spaced);
  return switch (s.key) {
    'tr_today_empty' => l.clientDietAnalysisTodayEmpty,
    'tr_today_over' => l.clientDietAnalysisTodayOver(
      str('slot'),
      str('food'),
      amount('food_value'),
      nutrient,
      amount('value'),
      amount('target'),
      str('ratio'),
    ),
    'tr_today_over_meal' => l.clientDietAnalysisTodayOverMeal(
      str('slot'),
      amount('food_value'),
      nutrient,
      amount('value'),
      amount('target'),
      str('ratio'),
    ),
    'tr_today_protein_short' => l.clientDietAnalysisTodayProteinShort(
      amount('value', 'protein'),
      amount('gap', 'protein'),
    ),
    'tr_today_protein_chronic' => l.clientDietAnalysisTodayProteinChronic(
      amount('value', 'protein'),
      amount('gap', 'protein'),
      amount('avg', 'protein'),
    ),
    'tr_today_missing' => l.clientDietAnalysisTodayMissing(str('slot')),
    'tr_today_good' => l.clientDietAnalysisTodayGood(amount('kcal', 'calorie')),
    'tr_week_empty' => l.clientDietAnalysisWeekEmpty,
    'tr_week_skip_breakfast' => l.clientDietAnalysisWeekSkipBreakfast(
      str('scope'),
      number('logged'),
      number('days'),
    ),
    'tr_week_skip_breakfast_snack' =>
      l.clientDietAnalysisWeekSkipBreakfastSnack(
        str('scope'),
        number('logged'),
        number('days'),
        number('snack_days'),
      ),
    'tr_week_over' => l.clientDietAnalysisWeekOver(
      str('scope'),
      number('logged'),
      number('days'),
      nutrient,
    ),
    'tr_week_cause' => l.clientDietAnalysisWeekCause(
      str('weekday'),
      str('slot'),
      str('food'),
      amount('food_value'),
    ),
    'tr_week_protein_short' => l.clientDietAnalysisWeekProteinShort(
      str('scope'),
      number('logged'),
      number('days'),
    ),
    'tr_week_good' => l.clientDietAnalysisWeekGood(
      str('scope'),
      number('days'),
    ),
    'tr_week_breakfast_snack_food' =>
      l.clientDietAnalysisWeekBreakfastSnackFood(str('food'), number('count')),
    'tr_week_protein_avg' => l.clientDietAnalysisWeekProteinAvg(
      amount('value', 'protein'),
    ),
    'tr_week_good_avg' => l.clientDietAnalysisWeekGoodAvg(
      amount('kcal', 'calorie'),
      amount('protein', 'protein'),
    ),
    'tr_week_vs_last_more' ||
    'tr_week_vs_last_less' ||
    'tr_week_vs_last_same' => l.clientDietAnalysisWeekVsLast(
      number('prev_logged'),
      number('prev_days'),
      s.key.substring('tr_week_vs_last_'.length),
    ),
    'tr_all_few' => l.clientDietAnalysisAllFew(number('days')),
    'tr_all_slot_sodium' => l.clientDietAnalysisAllSlotSodium(
      str('slot'),
      number('days'),
    ),
    'tr_all_carb_heavy' => l.clientDietAnalysisAllCarbHeavy(number('pct')),
    'tr_all_protein_light' => l.clientDietAnalysisAllProteinLight(
      number('pct'),
    ),
    'tr_all_protein_trend_up' => l.clientDietAnalysisAllProteinTrendUp(
      number('before'),
      number('after'),
    ),
    'tr_all_protein_trend_down' => l.clientDietAnalysisAllProteinTrendDown(
      number('before'),
      number('after'),
    ),
    'tr_all_frequent' => l.clientDietAnalysisAllFrequent(
      str('slot'),
      str('food'),
      number('count'),
    ),
    'tr_all_repeated' => l.clientDietAnalysisAllRepeated(
      str('food1'),
      str('food2'),
    ),
    'tr_all_good' => l.clientDietAnalysisAllGood(number('days')),
    'tr_foods_one' => l.clientDietAnalysisFoodsOne(
      str('food1'),
      number('count1'),
    ),
    'tr_foods_two' => l.clientDietAnalysisFoodsTwo(
      str('food1'),
      number('count1'),
      str('food2'),
      number('count2'),
    ),
    _ => null,
  };
}

/// 문장들을 한 문단으로 — 모르는 키는 뺀다.
String clientDietAnalysisText(AppLocalizations l, ClientDietAnalysis a) => a
    .sentences
    .map((ClientDietSentence s) => clientDietSentenceText(l, s))
    .whereType<String>()
    .join(' ');

/// `4,286mg` · `70g` · `2,600kcal` — 서버 틀과 같은 모양(천 단위 쉼표). 한국어는
/// 단위를 붙이고, [spaced] 면(영어) `4,286 mg` 처럼 띄운다.
String formatDietAmount(int value, String nutrient, {bool spaced = false}) {
  final String unit = switch (nutrient) {
    'sodium' => 'mg',
    'calorie' => 'kcal',
    _ => 'g',
  };
  return '${NumberFormat('#,##0', 'en').format(value)}${spaced ? ' ' : ''}$unit';
}
