import 'package:flutter/painting.dart';

import 'package:oncare_ui/src/tokens/typography.dart';

/// 달력·날짜 선택창 복원 규격(#1778).
///
/// 9월 15일 회의에서 달력과 날짜 선택창을 `2db5b04` 시점 모양으로 되돌리기로
/// 했다. 그때의 크기·투명도·글자에는 #1690 기본 단계(간격 4의 배수, 투명도 세
/// 단계, 글자 역할 9단계) 밖의 값이 있어, 흩어지지 않도록 달력 컴포넌트가 쓰는
/// 값만 여기에 모은다. 화면 코드는 이 값을 직접 쓰지 않고 `app_calendar.dart`·
/// `app_pickers.dart` 의 컴포넌트를 쓴다.
///
/// 글자 크기는 **그때 눈에 보이던 크기**다. 옛 두 앱은 전역 글자 배율 1.10 을
/// 얹어 그렸는데 #1707 에서 배율을 없앴으므로, 옛 코드의 크기에 1.1 을 곱해
/// 정수로 반올림했다(예: 13.5 → 15, 12 → 13, 16 → 18). 글자를 따라 커지던 날짜
/// 칸도 같은 배율을 곱했다.
class OnCareCalendar {
  OnCareCalendar._();

  // --- 주간 달력(회원앱 식단·운동) ---
  /// 날짜 줄 양옆 이전/다음 주 화살표가 받는 정사각 탭 영역의 한 변.
  static const double weekArrow = 36;

  /// 그 화살표 글리프의 크기. 원 배경 없이 꺾쇠만 두므로, 작은 아이콘으로는
  /// 날짜 숫자 옆에서 눌려 보인다(#2215).
  static const double weekArrowIcon = 28;

  /// 날짜 칸 한 변(옛 30 × 1.1). 기기 글자 배율을 따라 함께 커진다 — 고정하면
  /// 숫자가 칸에 눌린다(#1004). 한 칸 폭보다 크면 칸 폭에 맞춰진다.
  static const double weekDayBox = 33;

  /// 요일 글자와 날짜 칸 사이.
  static const double weekdayGap = 3;

  /// 갈 수 없는 방향 화살표의 불투명도.
  static const double disabledArrowOpacity = 0.35;

  /// 주 라벨 옆 `오늘` 알약의 채움·테두리 — 브랜드 색에 곱하는 투명도.
  static const double todayPillFillAlpha = 0.10;
  static const double todayPillBorderAlpha = 0.25;

  /// `오늘` 알약 안쪽.
  static const EdgeInsets todayPillPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 3,
  );

  // --- 날짜 선택창 달력(두 앱) — Material 달력과 같은 크기 ---
  /// 달력 머리(달 라벨·꺾쇠) 줄 높이.
  static const double pickerHeaderHeight = 52;

  /// 요일 줄·주 줄 한 줄 높이 — 세로 화면(M3, 회원앱). 날짜 원은 이 칸에서 사방
  /// 4 를 뺀 크기다.
  static const double pickerRowHeightPortrait = 48;

  /// 요일 줄·주 줄 한 줄 높이 — 가로 화면(M2, 데스크톱 트레이너웹). 날짜 원이 칸을
  /// 꽉 채운다. Material 달력도 가로 화면에서는 이 크기라, 창 높이가 늘지 않아
  /// 아래 줄이 하단 버튼 뒤로 들어가지 않는다.
  static const double pickerRowHeightLandscape = 42;

  /// 한 달이 차지할 수 있는 최대 주 수. 달이 바뀌거나 달 보기로 바꿔도 달력
  /// 높이가 흔들리지 않게 늘 이만큼 자리를 둔다.
  static const int pickerMaxWeeks = 6;

  /// 달 보기의 열 수 — 열두 달을 3열 × 4줄로 놓는다.
  static const int pickerMonthColumns = 3;

  /// 달 보기 한 칸(알약)의 높이. 날짜 원 지름과 같다.
  static const double pickerMonthCellHeight = 40;

  // --- 기간 선택창(트레이너웹) ---
  /// 날짜 칸의 가로:세로 비율.
  static const double rangeCellAspectRatio = 1.2;

  // --- 글자(옛 크기 × 1.1, 정수 반올림) ---
  /// 주간 달력 위 주 라벨(예: `9월 2주차`). 옛 13.5.
  static const TextStyle weekLabel = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// 주간 달력 요일. 옛 12.
  static const TextStyle weekday = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// 주간 달력 날짜 숫자. 옛 13.5.
  static const TextStyle weekDayNumber = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  /// `오늘` 알약 글자. 옛 12.
  static const TextStyle todayPill = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  /// 기간 선택창 달 라벨(예: `2026년 9월`). 옛 16(700).
  static const TextStyle rangeMonthLabel = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );

  /// 기간 선택창 요일 머리. 옛 12.
  static const TextStyle rangeWeekday = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  /// 기간 선택창 날짜 숫자. 옛 16 — 시작·종료일은 700 으로 굵힌다.
  static const TextStyle rangeDay = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w500,
  );
}
