/// 초록이 무엇을 말하는가 — 트레이너 쪽. (#1239)
///
/// 일정·할 일·상담 수락은 `#34C759` 로 완료를 말하는데, 운동 미션 100% 배지와
/// 프로필 저장 완료만 어두운 초록(`#22A882`)이었다. 한 앱 안에서 `완료` 가 두
/// 색으로 갈리고, 회원 앱과도 어긋났다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/workout_view.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  test('완료·성공 초록은 두 앱이 같은 값(#34C759)이다', () {
    // 회원 앱 `AppColors.success` 도 같은 값이다 — 두 패키지가 서로를
    // 참조하지 않으므로 양쪽 테스트가 같은 상수를 지킨다.
    expect(AppColors.success, const Color(0xFF34C759));
  });

  test('미션 100% 는 다른 완료 표시와 같은 초록이다', () {
    expect(workoutRateColor(100), AppColors.success);
    expect(workoutRateColor(120), AppColors.success);
    // 부분 완료는 진행이지 완료가 아니다 — 색이 갈린다(#690).
    expect(workoutRateColor(60), OnCareColors.caution);
    expect(workoutRateColor(0), OnCareColors.textSecondary);
    // 배지(AppTag)의 톤도 같은 세 단계다.
    expect(workoutRateTone(100), AppTagTone.success);
    expect(workoutRateTone(60), AppTagTone.caution);
    expect(workoutRateTone(0), AppTagTone.neutral);
  });

  test('식단 그래프는 이 앱의 브랜드색이다 — 초록이 아니다', () {
    expect(AppColors.dietChart, AppColors.statusWithinGoal);
    expect(AppColors.dietChart, isNot(AppColors.success));
    expect(AppColors.dietChart, const Color(0xFF2E7DAB));
  });
}
