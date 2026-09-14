/// 밀도와 무관하게 두 앱이 같은 크기(#1690 §6).
///
/// 모바일/웹에 따라 달라지는 크기(버튼·입력·칩 높이 등)는 `OnCareDensity` 에 있다.
class OnCareSize {
  OnCareSize._();

  // --- 아이콘(확정) ---
  /// 글자 옆.
  static const double iconSmall = 16;

  /// 버튼 안.
  static const double iconMedium = 20;

  /// 내비·헤더.
  static const double iconLarge = 24;

  /// 빈 화면 그림.
  static const double iconEmptyState = 40;

  /// 허용 아이콘 크기.
  static const List<double> iconScale = <double>[
    iconSmall,
    iconMedium,
    iconLarge,
    iconEmptyState,
  ];

  // --- 뒤로·닫기(확정) ---
  static const double backCloseIcon = 24;
  static const double backCloseTouch = 44;

  // --- 아바타 ---
  static const double avatarSmall = 24;
  static const double avatarMedium = 32;
  static const double avatarLarge = 40;
  static const double avatarXLarge = 56;

  // --- 배지·점 ---
  static const double countBadgeMin = 20;
  static const double dot = 8;

  // --- 진행 표시 ---
  static const double progressBar = 8;
  static const double stepBar = 4;
  static const double spinner = 24;
  static const double spinnerStroke = 2.5;
  static const double inlineSpinner = 16;

  // --- 바텀시트 핸들 ---
  static const double sheetHandleWidth = 36;
  static const double sheetHandleHeight = 4;

  // --- 태그 ---
  static const double tagHeight = 24;

  // --- 선 ---
  static const double hairline = 1;
  static const double focusBorder = 1.5;
}
