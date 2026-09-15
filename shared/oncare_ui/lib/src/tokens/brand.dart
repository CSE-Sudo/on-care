import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:oncare_ui/src/tokens/colors.dart';

/// 앱마다 다른 색 — 두 앱이 패키지에 주입하는 유일한 색 묶음이다.
///
/// 메인 색이 쓰이는 자리는 각 앱의 메인 색으로 말하고, 빨강 같은 상태색은 두 앱이
/// 같은 값을 쓴다([OnCareColors]). 그래서 이 클래스에는 상태색이 없다.
@immutable
class OnCareBrand {
  const OnCareBrand._({
    required this.name,
    required this.primary,
    required this.strong,
    required this.surface,
    required this.surfaceSoft,
    required this.exerciseCardio,
    required this.exerciseStrength,
    required this.exerciseStretching,
    required this.segmentTrack,
    required this.segmentLabel,
  });

  /// 회원앱 — 파랑.
  static const OnCareBrand member = OnCareBrand._(
    name: 'member',
    primary: Color(0xFF3EAFDF),
    strong: Color(0xFF277DA1),
    surface: Color(0xFFEDF7FC),
    surfaceSoft: Color(0xFFF2F9FB),
    exerciseCardio: Color(0xFF2795C4),
    exerciseStrength: Color(0xFF66C4E8),
    exerciseStretching: Color(0xFFA8E4F7),
    segmentTrack: Color(0xFFF8FAFB),
    segmentLabel: Color(0xFF64748B),
  );

  /// 트레이너웹 — 남색.
  static const OnCareBrand trainer = OnCareBrand._(
    name: 'trainer',
    primary: Color(0xFF2E7DAB),
    strong: Color(0xFF17435F),
    surface: Color(0xFFEAF2F9),
    surfaceSoft: Color(0xFFF2F7FB),
    exerciseCardio: Color(0xFF3793C9),
    exerciseStrength: Color(0xFF87BFDF),
    exerciseStretching: Color(0xFFC2DEEF),
    segmentTrack: OnCareColors.surfaceInput,
    segmentLabel: OnCareColors.textSecondary,
  );

  /// 디버그·카탈로그 표시용 이름.
  final String name;

  /// 주요 버튼·선택·링크·차트 주색.
  final Color primary;

  /// 눌림 상태.
  final Color strong;

  /// 선택 칩 배경·안쪽 타일·hover·읽지 않음.
  final Color surface;

  /// [surface] 보다 한 단계 옅은 바탕 — 주간 달력 양옆 원형 화살표(#1778).
  final Color surfaceSoft;

  /// 운동 유형 램프 — 유산소 → 근력 → 스트레칭으로 연해진다(#1168).
  ///
  /// 두 앱의 현재 값을 그대로 옮겼다. 같은 대비 간격으로 계산하는 통합은 복합
  /// 위젯 이슈(#1697)에서 한다.
  final Color exerciseCardio;
  final Color exerciseStrength;
  final Color exerciseStretching;

  /// 세그먼트 토글(오늘/이번 주/전체·식단/운동) 트랙 채움(#1777).
  ///
  /// 공용 토글로 옮기기 전 두 앱의 알약 토글 값을 그대로 되살렸다 — 회원앱은
  /// 입력 채움보다 옅은 `#F8FAFB`, 트레이너웹은 입력 채움과 같다.
  final Color segmentTrack;

  /// 세그먼트 토글에서 선택되지 않은 칸의 글자·아이콘(#1777).
  ///
  /// 이전 값을 따른다 — 회원앱 `#64748B`, 트레이너웹은 보조 글자색과 같다.
  final Color segmentLabel;

  /// 세그먼트 토글 `thumb` 모양의 띠 채움(#1777).
  ///
  /// 이식 전 스트립은 메인 색 10% 를 얹었다. 흰 바탕 기준 그 값이 [surface] 와
  /// 거의 같아(트레이너 `#EAF2F7` ↔ `#EAF2F9`) 새 색을 두지 않는다.
  Color get segmentThumbTrack => surface;

  /// 세그먼트 토글 `thumb` 모양의 띠 테두리(#1777).
  ///
  /// 이전 스트립은 10% 채움 위에 10% 테두리를 겹쳐 약 19% 였다 — 투명도 단계
  /// [OnCareAlpha.medium] 으로 맞춘 불투명 색이다.
  Color get segmentThumbBorder =>
      OnCareColors.onWhite(primary, OnCareAlpha.medium);

  /// 선택 칩·안내 배너 테두리. 메인 색 40% 를 불투명으로 환산한 값.
  Color get border => OnCareColors.onWhite(primary, OnCareAlpha.strong);

  /// 목표 안쪽 상태. 초록이 아니라 판단을 담지 않는 메인 색이다(#1070).
  Color get statusWithinGoal => primary;

  /// 식단 그래프 색.
  Color get dietChart => primary;

  /// 운동 그래프 색.
  Color get exerciseChart => primary;

  /// 탄단지 — 메인 색 한 가지의 농담(100 / 65 / 35%, #953).
  Color get macroCarbs => primary;
  Color get macroProtein => OnCareColors.onWhite(primary, 0.65);
  Color get macroFat => OnCareColors.onWhite(primary, 0.35);

  @override
  String toString() => 'OnCareBrand.$name';
}
