import 'package:flutter/painting.dart';

/// 두 앱이 **같은 값**으로 쓰는 색. 앱마다 다른 브랜드 색은 `OnCareBrand` 에 있다.
///
/// 규칙(#1690 §2):
/// - 텍스트 네 단계, 표면 세 가지, 선 두 가지만 둔다. 거의 같은 회색·연파랑을
///   화면마다 새로 고르지 않는다.
/// - 상태색은 두 앱이 같다 — 회원이 자기 폰에서 빨갛게 보는 초과를 트레이너가
///   다른 세기로 보지 않는다(#690, #1239).
/// - 투명도는 [OnCareAlpha] 세 단계만 쓴다.
class OnCareColors {
  OnCareColors._();

  // --- 텍스트 ---
  /// 제목·본문.
  static const Color textPrimary = Color(0xFF1A1A1A);

  /// 보조 설명. 흰 바탕 대비 7.6:1.
  static const Color textSecondary = Color(0xFF465568);

  /// 힌트·캡션·축 라벨. 흰 바탕 대비 4.7:1.
  static const Color textTertiary = Color(0xFF667585);

  /// 비활성. 흰 바탕 대비 3.8:1 — 흐리지만 왜 못 쓰는지는 읽힌다.
  static const Color textDisabled = Color(0xFF768596);

  /// 브랜드·상태 채움 위의 글자.
  static const Color textOnFill = Color(0xFFFFFFFF);

  // --- 표면 ---
  /// 페이지 배경. 두 앱 공통(#1690 확정).
  static const Color surfacePage = Color(0xFFF5F7FA);

  /// 카드·다이얼로그·시트·입력칸 채움(#1776).
  static const Color surfaceCard = Color(0xFFFFFFFF);

  /// 진행 트랙·비활성 채움(비활성 입력칸 포함). 활성 입력칸은 흰 채움이다(#1776).
  /// 세그먼트 트랙은 브랜드별 값(`OnCareBrand.segmentTrack`)이다.
  static const Color surfaceInput = Color(0xFFF2F4F7);

  // --- 선 ---
  /// 카드 테두리·구분선.
  static const Color lineSubtle = Color(0xFFEBEFF3);

  /// 입력창·외곽선 버튼·메뉴 테두리.
  static const Color lineStrong = Color(0xFFD8E0E8);

  // --- 상태 ---
  /// 완료·성공.
  static const Color success = Color(0xFF34C759);

  /// 주의(글자·아이콘).
  static const Color caution = Color(0xFFE8760A);

  /// 주의(채움·막대).
  static const Color cautionFill = Color(0xFFFF953C);

  /// 위험 동작·목표 초과·이탈 위험·새 알림 점. 한 가지 빨강만 쓴다.
  static const Color danger = Color(0xFFF04438);

  // --- 오버레이 ---
  /// 토스트·툴팁 배경.
  static const Color overlayInk = Color(0xFF1A1A1A);

  /// 어두운 오버레이 위의 동작 글자·아이콘. 브랜드 색은 이 바탕에서 가라앉는다.
  static const Color overlayAction = Color(0xFF7FD0F0);

  /// 어두운 오버레이 위의 성공·실패 아이콘. 바탕 대비를 위해 상태색보다 밝다.
  static const Color overlaySuccess = Color(0xFF4CD9B0);
  static const Color overlayError = Color(0xFFFF8A8A);

  /// 모달 뒤 배경 막.
  static const Color scrim = Color(0x8008121C);

  // --- 차트 ---
  /// 그래프 목표선(파선). 데이터 선과 섞이지 않는 중립 회색.
  static const Color chartGoalLine = Color(0xFF98A2B3);

  // --- 외부 브랜드(예외) ---
  // 로그인 버튼의 계정 회사 색은 각 회사 가이드 값을 그대로 쓴다(#1783).

  /// 카카오 로그인 버튼 바탕 — 카카오 로그인 디자인 가이드의 컨테이너 색.
  static const Color kakaoYellow = Color(0xFFFEE500);

  /// 카카오 말풍선 심볼 색 — 카카오 로그인 디자인 가이드의 심볼 색.
  static const Color kakaoSymbol = Color(0xFF000000);

  /// 구글 로그인 버튼 바탕 — Google Identity 브랜딩 가이드 라이트 테마 채움.
  static const Color googleButtonFill = Color(0xFFFFFFFF);

  /// 구글 로그인 버튼 테두리(1px, 안쪽) — 같은 가이드의 라이트 테마 선 색.
  static const Color googleButtonStroke = Color(0xFF747775);

  /// 구글 `G` 로고 네 색 — 파랑.
  static const Color googleBlue = Color(0xFF4285F4);

  /// 구글 `G` 로고 네 색 — 빨강.
  static const Color googleRed = Color(0xFFEA4335);

  /// 구글 `G` 로고 네 색 — 노랑.
  static const Color googleYellow = Color(0xFFFBBC05);

  /// 구글 `G` 로고 네 색 — 초록.
  static const Color googleGreen = Color(0xFF34A853);

  /// [color] 를 흰 바탕 위에 [alpha] 만큼 얹은 **불투명** 색.
  ///
  /// 차트 막대처럼 겹쳐 그리는 자리는 반투명이면 아래 선이 비치므로, 투명도 대신
  /// 이 값을 쓴다.
  static Color onWhite(Color color, double alpha) =>
      Color.alphaBlend(color.withValues(alpha: alpha), surfaceCard);
}

/// 투명도 세 단계(#1690 §2). 이 밖의 값은 쓰지 않는다.
class OnCareAlpha {
  OnCareAlpha._();

  /// 톤 채움(태그·배지 바탕).
  static const double subtle = 0.08;

  /// 눌림·강조 채움.
  static const double medium = 0.16;

  /// 옅은 테두리.
  static const double strong = 0.40;
}
