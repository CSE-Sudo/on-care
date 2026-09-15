import 'package:flutter/painting.dart';

import 'package:oncare_ui/src/tokens/typography.dart';

/// 달력·날짜 선택창 복원 규격(#1778).
///
/// 9월 15일 회의에서 달력과 날짜 선택창을 `2db5b04` 시점 모양으로 되돌리기로
/// 했다. 그때의 크기·투명도·글자에는 #1690 기본 단계(간격 4의 배수, 투명도 세
/// 단계, 반 포인트 없음) 밖의 값이 있어, 흩어지지 않도록 달력 컴포넌트가 쓰는
/// 값만 여기에 모은다. 화면 코드는 이 값을 직접 쓰지 않고 `app_calendar.dart`·
/// `app_pickers.dart` 의 컴포넌트를 쓴다.
class OnCareCalendar {
  OnCareCalendar._();

  // --- 주간 달력(회원앱 식단·운동) ---
  /// 날짜 줄 양옆 이전/다음 주 원형 화살표의 지름.
  static const double weekArrow = 28;

  /// 날짜 칸 한 변. 글자 배율을 따라 함께 커진다 — 고정하면 숫자가 칸에 눌린다(#1004).
  static const double weekDayBox = 30;

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

  // --- 월간 달력 시트(회원앱 일정) ---
  /// 시트 높이(화면 높이 비율). 주 줄이 남은 높이를 나눠 갖는다.
  static const double monthSheetHeightFactor = 0.85;

  /// 한 주 줄의 최소 높이. 날짜 숫자와 일정 칩 한 줄이 들어가는 최소치다 —
  /// 남은 높이를 주 수로 나눈 값이 이보다 작으면 줄이지 않고 스크롤한다(#669).
  static const double monthMinRowHeight = 56;

  /// 시트 제목 옆 원형 닫기 버튼의 지름과 그 안 아이콘 크기.
  static const double circleClose = 32;
  static const double circleCloseIcon = 18;

  /// 요일 머리 띠의 위아래 안쪽.
  static const double weekdayBandVerticalPadding = 6;

  /// 오늘 칸 바탕 — 브랜드 색에 곱하는 투명도.
  static const double todayCellAlpha = 0.05;

  /// 칸 안 일정 칩의 안쪽.
  static const EdgeInsets eventChipPadding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 2,
  );

  /// 일정 칩·범례 견본 바탕 — 카테고리 색을 흰 바탕에 얹는 비율(옅은 파스텔).
  static const double eventTintAlpha = 0.18;

  /// 범례 견본 한 변과 모서리.
  static const double legendSwatch = 10;
  static const Radius legendSwatchRadius = Radius.circular(3);

  // --- 기간 선택창(트레이너웹) ---
  /// 날짜 칸의 가로:세로 비율.
  static const double rangeCellAspectRatio = 1.2;

  // --- 글자 ---
  /// 주간 달력 위 주 라벨(예: `9월 2주차`).
  static const TextStyle weekLabel = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );

  /// 주간 달력 요일.
  static const TextStyle weekday = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  /// 주간 달력 날짜 숫자.
  static const TextStyle weekDayNumber = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
  );

  /// `오늘` 알약 글자.
  static const TextStyle todayPill = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  /// 월간 달력 칸 안 일정 칩 글자. 칸이 좁아 가장 작다.
  static const TextStyle eventChip = TextStyle(
    fontFamily: OnCareTypography.fontFamily,
    fontSize: 9,
  );
}
