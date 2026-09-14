/// 창·페이지 크기와 반응형 기준 폭(#1690 §6·§8). 화면 안에 숫자 기준 폭을 두지 않는다.
class OnCareLayout {
  OnCareLayout._();

  // --- 모바일(회원앱) ---
  /// 탭 페이지·시트 콘텐츠 최대 폭.
  static const double mobileContentMaxWidth = 720;

  /// 확인 다이얼로그 최대 폭.
  static const double mobileDialogMaxWidth = 400;

  /// 태블릿 기준 폭.
  static const double tabletBreakpoint = 600;

  // --- 웹(트레이너웹) ---
  /// 한 열짜리 페이지(폼·목록·설정) 최대 폭.
  static const double webNarrowMaxWidth = 760;

  /// 여러 열 페이지(대시보드·분할 화면) 최대 폭.
  static const double webWideMaxWidth = 1440;

  /// 페이지 헤더 높이.
  static const double webHeaderHeight = 88;

  /// 분할 레이아웃 목록 폭·간격, 분할로 바뀌는 콘텐츠 폭.
  static const double splitListWidth = 380;
  static const double splitGap = 16;
  static const double splitBreakpoint = 900;

  /// 대시보드 두 열 기준 폭.
  static const double twoColumnBreakpoint = 1080;

  /// 사이드바 폭(펼침/레일)과 전환 기준 폭.
  static const double sidebarWidth = 232;
  static const double sidebarRailWidth = 76;
  static const double sidebarExpandBreakpoint = 1280;
  static const double sidebarDrawerBreakpoint = 1024;

  /// 헤더 가운데 검색이 인라인으로 남는 최소 폭.
  static const double headerCenterMinWidth = 400;

  // --- 창(확정) ---
  /// 웹 다이얼로그 폭 — 확인 / 입력 폼 / 상세·미리보기.
  static const double dialogSmall = 400;
  static const double dialogMedium = 560;
  static const double dialogLarge = 800;

  /// 다이얼로그 최대 높이(화면 높이 비율).
  static const double dialogMaxHeightFactor = 0.85;

  /// 바텀시트 최대 높이(화면 높이 비율).
  static const double sheetMaxHeightFactor = 0.9;

  /// 웹 다이얼로그가 화면 위에 남겨야 하는 여백 — 상단 토스트를 가리지 않는다(#1378).
  static const double dialogTopClearance = 100;

  /// 바텀시트 핸들 크기.
  static const double sheetHandleWidth = 36;
  static const double sheetHandleHeight = 4;

  // --- 공통 ---
  /// 로그인·가입 화면 폭.
  static const double authMaxWidth = 400;

  /// 토스트 최대 폭.
  static const double toastMaxWidth = 560;
}
