import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 홈 '오늘의 AI 통합 조언' 본문을 고른다.
///
/// 우선순위:
///
/// 1. [DashboardSummary.aiAdviceKey] — 서버·데모가 싣는 로케일 독립 식별자.
///    여기서 ARB 문장으로 풀어야 영어 로케일에서 영어가 나온다(#435, #1943).
///    음식 이름이 든 나트륨 경고도 키(`sodium_over_sources`)와 음식 이름
///    인자로 온다(#2644).
/// 2. [DashboardSummary.sodiumWarning] / [DashboardSummary.exerciseFeedback] —
///    서버가 요청 언어로 만든 문장. 키를 모르거나 인자가 맞지 않을 때만 쓴다.
/// 3. ARB 기본 문구.
String aiAdviceBody(AppLocalizations l, DashboardSummary summary) {
  final String? fromKey = _localized(l, summary);
  return fromKey ??
      summary.sodiumWarning ??
      summary.exerciseFeedback ??
      l.homeAiAdviceBody;
}

/// 모르는 키는 null 을 돌려 서버 문장·ARB 기본값으로 넘긴다 — 서버가 새 키를
/// 먼저 내려도 화면이 비지 않게.
///
/// 운동 되먹임의 분 수는 요약이 이미 들고 있는 값을 쓴다(#1943) — 서버가 같은
/// 응답에서 센 값이라, 문장과 카드가 서로 다른 숫자를 말할 일이 없다.
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
        summary.exerciseMinutes,
      ),
      'exercise_more' => l.homeAdviceExerciseMore(summary.exerciseMinutes),
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

/// 음식 이름을 지금 언어로 잇는다 — 한국어 `라면·김밥`, 영어 `라면 and 김밥`.
/// 서버는 두 개까지만 보내지만, 더 오더라도 앞의 두 개만 쓴다.
String _joinFoods(AppLocalizations l, List<String> names) =>
    names.length == 1 ? names.first : l.homeAdviceFoodPair(names[0], names[1]);
