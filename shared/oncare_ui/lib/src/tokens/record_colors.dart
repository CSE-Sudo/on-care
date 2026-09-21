import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 기록 달력의 색 — 한 계열의 3단계 진하기. (#2075, #2076)
///
/// 달력 한 칸은 그날 무엇을 남겼는가로 진하기가 갈린다: 아무 기록도 없음(가장
/// 연함) → 식단·운동 중 하나만(중간) → 둘 다(가장 진함). 깃허브 달력처럼 **같은
/// 색상 계열의 농담**이라, 세 단계가 서로 다른 색이 되면 안 된다.
///
/// 계열은 포인트로 바꾼다(#2076). 기본은 회원앱 파랑([base])이고 초록·보라·주황·
/// 분홍을 150P 에 하나씩 연다. 서버가 파는 색 이름(`green`·`purple`·`orange`·
/// `pink`)을 그대로 열쇠로 쓰므로, 서버에 색이 늘면 여기에 한 줄을 더한다 — 앱이
/// 모르는 색이 와도 [rampOf] 가 기본 계열로 그려 빈 달력이 되지 않는다.
///
/// 단계 색은 흰 바탕에 계열 색을 각각 12% · 45% · 100% 로 얹은 값이다. 가장 연한
/// 칸도 카드 바탕(흰색)과 구분되고, 중간 칸이 진한 칸과 한눈에 갈린다.
@immutable
class OnCareRecordRamp {
  const OnCareRecordRamp._({
    required this.name,
    required this.partial,
    required this.full,
  });

  /// 서버가 쓰는 색 이름(`blue`·`green` …). 화면 문구는 앱의 현지화가 정한다.
  final String name;

  /// 아무 기록도 없는 날 — 어느 계열을 골라도 같은 회색이다.
  Color get none => OnCareRecordColors.empty;

  /// 식단·운동 중 하나만 기록한 날.
  final Color partial;

  /// 둘 다 기록한 날.
  final Color full;

  /// 단계 수만큼의 색 — 범례가 순서대로 그린다.
  List<Color> get steps => <Color>[none, partial, full];
}

/// 색 계열 팔레트. [OnCareRecordColors.base] 가 기본 색이다.
class OnCareRecordColors {
  OnCareRecordColors._();

  /// 아무 기록도 없는 날의 칸. 계열과 상관없이 하나다 — 빠진 날은 어느 색을 골라도
  /// "빠진 날" 로 보여야 한다. 흰 카드 위에서 칸 모양이 드러날 만큼만 진하다.
  static const Color empty = Color(0xFFE8ECF0);

  /// 회원앱 파랑 — 포인트가 들지 않는 기본 계열(`OnCareBrand.member.primary`).
  static const OnCareRecordRamp base = OnCareRecordRamp._(
    name: 'blue',
    partial: Color(0xFF9BDAF0),
    full: Color(0xFF3EAFDF),
  );

  static const OnCareRecordRamp green = OnCareRecordRamp._(
    name: 'green',
    partial: Color(0xFF98D9AC),
    full: Color(0xFF34A853),
  );

  static const OnCareRecordRamp purple = OnCareRecordRamp._(
    name: 'purple',
    partial: Color(0xFFB8A9E4),
    full: Color(0xFF6C4BC9),
  );

  static const OnCareRecordRamp orange = OnCareRecordRamp._(
    name: 'orange',
    partial: Color(0xFFF5C49B),
    full: Color(0xFFE8760A),
  );

  static const OnCareRecordRamp pink = OnCareRecordRamp._(
    name: 'pink',
    partial: Color(0xFFF2A8C4),
    full: Color(0xFFE05089),
  );

  /// 팔레트 순서 — 서버 `calendar_color_service.PALETTE` 와 같다.
  static const List<OnCareRecordRamp> ramps = <OnCareRecordRamp>[
    base,
    green,
    purple,
    orange,
    pink,
  ];

  /// [name] 의 계열. 앱이 모르는 색이면 기본 계열이다 — 서버에 색이 늘어도 달력이
  /// 비지 않는다.
  static OnCareRecordRamp rampOf(String? name) {
    for (final OnCareRecordRamp ramp in ramps) {
      if (ramp.name == name) return ramp;
    }
    return base;
  }

  /// 보호권으로 이어 붙인 칸의 방패·테두리 — 가장 연한 칸 위에 얹으므로 진한
  /// 단계 색을 쓴다(#1788, #2075).
  static Color shieldOn(OnCareRecordRamp ramp) => ramp.full;
}
