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

  // --- 세그먼트 토글(#1777) ---
  // 공용 토글로 옮기기 전 알약 토글의 치수를 되살린 값이다. 높이는 고정하지 않고
  // 글자 + 이 여백으로 정해진다. 간격 척도(4의 배수) 밖의 값이라 이 컴포넌트만 쓴다.

  /// 트랙 안쪽 여백 — 선택 칸 알약이 트랙 테두리에서 떨어지는 폭.
  static const double segmentTrackInset = 3;

  /// 칸 좌우 여백. 누를 자리가 글자에 딱 붙지 않게 넓게 둔다(#1058).
  static const double segmentPaddingHorizontal = 18;

  /// 글자 배율이 `OnCareTypography.maxTextScale` 을 넘을 때의 칸 좌우 여백 —
  /// 세 칸 폭 합이 커져 토글이 통째로 줄어드는 것을 덜어 준다(#1182).
  static const double segmentPaddingHorizontalCompact = 12;

  /// 칸 위아래 여백.
  static const double segmentPaddingVertical = 6;

  /// `thumb` 모양(흰 엄지 스트립) 띠 높이. 이식 전 트레이너웹 식단/운동 전환
  /// 스트립의 높이다 — 이 모양은 글자가 아니라 이 높이에 맞춰 칸이 위아래로 찬다.
  static const double segmentThumbTrackHeight = 44;

  // --- 선 ---
  static const double hairline = 1;
  static const double focusBorder = 1.5;
}
