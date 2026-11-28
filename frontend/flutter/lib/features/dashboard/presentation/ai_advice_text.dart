import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 홈 '오늘의 AI 통합 조언' 본문을 고른다.
///
/// 우선순위:
///
/// 0. 데모 키([kDailyCombinedAdviceKey]) — 체험하기 문장 그대로.
/// 0-1. [DashboardSummary.dietAdviceKey] + [DashboardSummary.exerciseAdviceKey] —
///    식단 문장 뒤에 운동 문장을 잇는다(#3549). 체험하기 카드처럼 하루의 식단과
///    운동을 함께 말한다. 둘 다 규칙 문장이고 AI 를 부르지 않는다. 한쪽이라도
///    모르는 키면 아래로 넘어간다.
/// 1. [DashboardSummary.aiAdviceKey] — 서버·데모가 싣는 로케일 독립 식별자.
///    여기서 ARB 문장으로 푼다(#435, #1943).
///    음식 이름이 든 나트륨 경고도 키(`sodium_over_sources`)와 음식 이름
///    인자로 온다(#2644).
/// 2. [DashboardSummary.sodiumWarning] / [DashboardSummary.exerciseFeedback] —
///    서버가 요청 언어로 만든 문장. 키를 모르거나 인자가 맞지 않을 때만 쓴다.
/// 3. 기록을 권하는 중립 안내(`homeAiAdviceNoRecord`).
///
/// 데모 회원의 하루를 묘사한 문장(`homeAiAdviceBody`, 짬뽕·저녁 PT)은 데모만
/// 싣는 키([kDailyCombinedAdviceKey])로만 고른다. 예전에는 서버가 근거를 주지
/// 않으면 그 문장으로 떨어져, 기록이 없는 회원에게도 실제 분석처럼 보였다
/// (#2813).
String aiAdviceBody(AppLocalizations l, DashboardSummary summary) {
  if (summary.aiAdviceKey == kDailyCombinedAdviceKey) {
    return l.homeAiAdviceBody;
  }
  final String? combined = _combined(l, summary);
  if (combined != null) return combined;
  final String? fromKey = _localized(l, summary);
  return fromKey ??
      summary.sodiumWarning ??
      summary.exerciseFeedback ??
      l.homeAiAdviceNoRecord;
}

/// 모르는 키는 null 을 돌려 서버 문장·ARB 기본값으로 넘긴다 — 서버가 새 키를
/// 먼저 내려도 화면이 비지 않게.
///
/// 운동 되먹임의 분 수는 요약이 이미 들고 있는 값을 쓴다(#1943) — 서버가 같은
/// 응답에서 센 값이라, 문장과 카드가 서로 다른 숫자를 말할 일이 없다. 서버가
/// 목표와 견준 값인 이번 주 유산소 분이다(#3350).
String? _localized(AppLocalizations l, DashboardSummary summary) =>
    switch (summary.aiAdviceKey) {
      kDailyCombinedAdviceKey => l.homeAiAdviceBody,
      'sodium_over' => l.homeAdviceSodiumOver,
      'sodium_over_sources' => switch (_foods(summary.aiAdviceParams)) {
        final List<String> foods => l.homeAdviceSodiumOverSources(
          _joinFoods(l, foods),
        ),
        null => null,
      },
      'exercise_on_track' => l.homeAdviceExerciseOnTrack(
        summary.exerciseCardioMinutes,
      ),
      'exercise_more' => l.homeAdviceExerciseMore(
        summary.exerciseCardioMinutes,
      ),
      'exercise_cardio_start' => l.homeAdviceExerciseCardioStart,
      'exercise_start' => l.homeAdviceExerciseStart,
      _ => null,
    };

/// 식단 문장 + 운동 문장(#3549). 어느 한쪽 키가 없거나 모르면 null.
String? _combined(AppLocalizations l, DashboardSummary summary) {
  final String? diet = _dietSentence(l, summary);
  final String? exercise = _exerciseSentence(l, summary);
  if (diet == null || exercise == null) return null;
  return '$diet $exercise';
}

/// 식단 문장. 음식 이름이 든 나트륨 경고는 원인만 말하므로 다음 끼니 행동을 잇는다.
String? _dietSentence(AppLocalizations l, DashboardSummary summary) =>
    switch (summary.dietAdviceKey) {
      'diet_empty' => l.homeAdviceDietEmpty,
      'diet_ok' => l.homeAdviceDietOk,
      'sodium_over' => l.homeAdviceSodiumOver,
      'sodium_over_sources' => switch (_foods(summary.dietAdviceParams)) {
        final List<String> foods =>
          '${l.homeAdviceSodiumOverSources(_joinFoods(l, foods))} '
              '${l.homeAdviceSodiumNextMeal}',
        null => null,
      },
      _ => null,
    };

/// 운동 문장 — 분 수는 요약이 들고 있는 이번 주 유산소 분이다(#3350).
String? _exerciseSentence(AppLocalizations l, DashboardSummary summary) =>
    switch (summary.exerciseAdviceKey) {
      'exercise_on_track' => l.homeAdviceExerciseOnTrack(
        summary.exerciseCardioMinutes,
      ),
      'exercise_more' => l.homeAdviceExerciseMore(
        summary.exerciseCardioMinutes,
      ),
      'exercise_cardio_start' => l.homeAdviceExerciseCardioStart,
      'exercise_start' => l.homeAdviceExerciseStart,
      _ => null,
    };

/// `foods` 인자 → 비어 있지 않은 음식 이름들. 인자가 없거나 모양이 맞지 않으면
/// null — 받은 문장으로 넘긴다.
List<String>? _foods(Map<String, Object> params) {
  final Object? raw = params['foods'];
  if (raw is! List) return null;
  final List<String> names = <String>[
    for (final Object? name in raw)
      if (name is String && name.trim().isNotEmpty) name.trim(),
  ];
  return names.isEmpty ? null : names;
}

/// 음식 이름을 잇는다 — `라면·김밥`.
/// 서버는 두 개까지만 보내지만, 더 오더라도 앞의 두 개만 쓴다.
String _joinFoods(AppLocalizations l, List<String> names) =>
    names.length == 1 ? names.first : l.homeAdviceFoodPair(names[0], names[1]);
