/// 가이드가 머무는 탭. 하단 내비의 차례와 같다. (#1857)
enum GuideTab { home, diet, exercise, my }

/// 처음 들어온 회원에게 짚어 주는 자리. (#1857)
///
/// **탭을 옮겨 가며** 그 탭의 화면 위에서 짚는다. 홈의 식단 카드 하나만 띄워 놓고
/// 운동과 포인트까지 말하면, 정작 그 화면에 갔을 때 무엇을 봐야 할지 모른다.
enum GuideStepId {
  /// 홈 — 오늘의 AI 통합 조언.
  homeAdvice,

  /// 홈 — 하단 가운데 `+`.
  quickAdd,

  /// 식단 탭 — 영양 요약.
  dietNutrition,

  /// 운동 탭 — 운동 현황.
  exerciseStatus,

  /// 운동 탭 — 내 헬스장·트레이너.
  gym,

  /// MY 탭 — 내 정보와 기본 설정.
  mySettings,

  /// MY 탭 — 포인트.
  points,
}

/// 가이드가 짚는 차례. 탭 순서(홈 → 식단 → 운동 → MY)를 따르고, 마지막은
/// 포인트다 — 앞의 기록들이 무엇으로 돌아오는지가 마지막에 남아야 기억된다.
const List<GuideStepId> kGuideSteps = <GuideStepId>[
  GuideStepId.homeAdvice,
  GuideStepId.quickAdd,
  GuideStepId.dietNutrition,
  GuideStepId.exerciseStatus,
  GuideStepId.gym,
  GuideStepId.mySettings,
  GuideStepId.points,
];

/// 그 단계를 어느 탭에서 짚는가.
GuideTab guideTabOf(GuideStepId step) => switch (step) {
  GuideStepId.homeAdvice || GuideStepId.quickAdd => GuideTab.home,
  GuideStepId.dietNutrition => GuideTab.diet,
  GuideStepId.exerciseStatus || GuideStepId.gym => GuideTab.exercise,
  GuideStepId.mySettings || GuideStepId.points => GuideTab.my,
};
