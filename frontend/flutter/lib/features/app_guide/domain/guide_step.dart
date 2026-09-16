/// 처음 홈에 들어온 회원에게 짚어 주는 자리. (#1857)
///
/// 순서는 회원이 실제로 하게 되는 차례를 따른다 — 오늘 기록을 보고, 알림을 받고,
/// 끼니를 남기고, 빠르게 추가하고, 운동을 하고, 그 결과로 포인트가 쌓인다.
enum GuideStepId {
  /// 홈의 오늘 식단·영양 카드.
  homeSummary,

  /// 머리의 알림 벨.
  alerts,

  /// 하단 내비 `식단` 칸.
  diet,

  /// 하단 내비 가운데 `+`.
  quickAdd,

  /// 하단 내비 `운동` 칸.
  exercise,

  /// 하단 내비 `MY` 칸 — 건강 목표와 포인트.
  points,
}

/// 가이드가 짚는 차례. 마지막은 포인트다 — 앞의 기록들이 무엇으로 돌아오는지가
/// 마지막에 남아야 기억된다.
const List<GuideStepId> kGuideSteps = <GuideStepId>[
  GuideStepId.homeSummary,
  GuideStepId.alerts,
  GuideStepId.diet,
  GuideStepId.quickAdd,
  GuideStepId.exercise,
  GuideStepId.points,
];
