import 'package:flutter/animation.dart';

/// 움직임(#1690 §6). 화면마다 시간·곡선을 새로 고르지 않는다.
class OnCareMotion {
  OnCareMotion._();

  /// 눌림·hover 같은 즉각 반응.
  static const Duration fast = Duration(milliseconds: 120);

  /// 토글·탭 전환.
  static const Duration normal = Duration(milliseconds: 200);

  /// 시트·패널 등장.
  static const Duration slow = Duration(milliseconds: 300);

  /// 경로를 따라 그리는 차트(도넛·추이 선). 처음 나타날 때 한 번만.
  static const Duration chartDraw = Duration(milliseconds: 750);

  /// 막대 차트. 막대마다 시차가 있어 조금 더 길다.
  static const Duration chartGrow = Duration(milliseconds: 850);

  /// 글자 옆 작은 미터.
  static const Duration meterFill = Duration(milliseconds: 600);

  /// 막대 차트 시차 비율(0 = 동시에, 1 = 하나씩).
  static const double barStagger = 0.45;

  /// 기본 곡선.
  static const Curve curve = Curves.easeOutCubic;

  /// 사라질 때 곡선.
  static const Curve exitCurve = Curves.easeInCubic;

  // --- 토스트 ---
  static const Duration toastEnter = Duration(milliseconds: 220);
  static const Duration toastExit = Duration(milliseconds: 180);
  static const Duration toastVisible = Duration(seconds: 2);

  /// 실패는 다시 시도할지 정해야 하므로 더 머문다.
  static const Duration toastErrorVisible = Duration(milliseconds: 3500);

  /// 동작 버튼이 있으면 눌러 볼 시간을 준다.
  static const Duration toastActionVisible = Duration(seconds: 4);
}
