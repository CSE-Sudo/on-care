import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 버튼 크기 세 가지.
enum OnCareButtonSize { large, medium, small }

/// 플랫폼 밀도 — 회원앱(모바일)과 트레이너웹(웹)이 다르게 주입하는 크기 묶음.
///
/// 같은 컴포넌트가 크기만 달리 쓰고, 글자·반경·색은 밀도와 무관하다(#1690 §6).
@immutable
class OnCareDensity {
  const OnCareDensity._({
    required this.name,
    required this.isWeb,
    required this.buttonLarge,
    required this.buttonMedium,
    required this.buttonSmall,
    required this.inputMedium,
    required this.inputLarge,
    required this.chip,
    required this.iconButton,
    required this.iconButtonIcon,
    required this.listRowMin,
    required this.minTouchTarget,
    required this.pagePadding,
    required this.menuItem,
    required this.chatBubblePadding,
  });

  /// 회원앱.
  static const OnCareDensity mobile = OnCareDensity._(
    name: 'mobile',
    isWeb: false,
    buttonLarge: 52,
    buttonMedium: 44,
    buttonSmall: 32,
    inputMedium: 44,
    inputLarge: 52,
    chip: 36,
    iconButton: 44,
    iconButtonIcon: 24,
    listRowMin: 56,
    minTouchTarget: 44,
    pagePadding: 20,
    menuItem: 44,
    chatBubblePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  /// 트레이너웹.
  static const OnCareDensity web = OnCareDensity._(
    name: 'web',
    isWeb: true,
    buttonLarge: 44,
    buttonMedium: 36,
    buttonSmall: 28,
    inputMedium: 36,
    inputLarge: 44,
    chip: 32,
    iconButton: 36,
    iconButtonIcon: 20,
    listRowMin: 48,
    minTouchTarget: 32,
    // 콘솔 화면은 목록 열 폭이 고정이라 바깥 여백이 곧 빈 공간이다 — 좁게 둔다.
    pagePadding: 16,
    menuItem: 36,
    chatBubblePadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  );

  /// 디버그·카탈로그 표시용 이름.
  final String name;

  /// 웹 콘솔 밀도인지. 다이얼로그 위 여백·앱바 제목 정렬처럼 배치가 갈리는 곳이 읽는다.
  final bool isWeb;

  /// 버튼 높이 — 큰 / 기본 / 작은(확정).
  final double buttonLarge;
  final double buttonMedium;
  final double buttonSmall;

  /// 입력창 높이 — 버튼과 줄이 맞는다.
  final double inputMedium;
  final double inputLarge;

  /// 선택 칩 높이. 세그먼트 토글은 글자에 맞춘 높이라 이 값을 쓰지 않는다(#1777).
  final double chip;

  /// 뒤로·닫기를 뺀 아이콘 버튼의 한 변과 그 안 아이콘 크기.
  final double iconButton;
  final double iconButtonIcon;

  /// 목록 행 최소 높이.
  final double listRowMin;

  /// 최소 터치 영역.
  final double minTouchTarget;

  /// 페이지 좌우 여백.
  final double pagePadding;

  /// 메뉴·드롭다운 항목 높이.
  final double menuItem;

  /// 채팅 말풍선 안쪽.
  final EdgeInsets chatBubblePadding;

  /// [size] 에 맞는 버튼 높이.
  double buttonHeight(OnCareButtonSize size) => switch (size) {
    OnCareButtonSize.large => buttonLarge,
    OnCareButtonSize.medium => buttonMedium,
    OnCareButtonSize.small => buttonSmall,
  };

  @override
  String toString() => 'OnCareDensity.$name';
}
