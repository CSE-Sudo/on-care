/// 주간 피드백 보기의 말 — 회원이 고른 답을 그대로 읽어 준다. (#2232)
///
/// 답을 **회원이 고른 그 문장으로** 되돌려 주는 것이 규칙이다. `지쳤어요` 를
/// 고른 회원에게 `컨디션 4단계` 라고 되읽어 주면, 자기가 무슨 말을 보냈는지
/// 알 수 없다. 트레이너 화면도 같은 문장을 쓴다.
library;

import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 컨디션 한 줄.
String weekConditionLabel(AppLocalizations l, WeekCondition value) =>
    switch (value) {
      WeekCondition.great => l.weekConditionGreat,
      WeekCondition.good => l.weekConditionGood,
      WeekCondition.ok => l.weekConditionOk,
      WeekCondition.tired => l.weekConditionTired,
      WeekCondition.bad => l.weekConditionBad,
    };

/// 강도 체감 한 줄.
String weekIntensityLabel(AppLocalizations l, WeekIntensity value) =>
    switch (value) {
      WeekIntensity.tooEasy => l.weekIntensityTooEasy,
      WeekIntensity.right => l.weekIntensityRight,
      WeekIntensity.hard => l.weekIntensityHard,
      WeekIntensity.tooHard => l.weekIntensityTooHard,
    };

/// `9월 15일~21일` — 그 주를 가리키는 말. 안내 카드와 같은 문장을 쓴다.
String weekRangeLabel(AppLocalizations l, DateTime weekStart) {
  final DateTime end = weekStart.add(const Duration(days: 6));
  return l.coachChatReportWeek(
    weekStart.month,
    weekStart.day,
    end.month,
    end.day,
  );
}
