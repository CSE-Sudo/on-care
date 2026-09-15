import 'package:flutter/material.dart';

/// 글자 역할 9단계(#1690 §3 확정).
///
/// 크기는 **보이는 크기**다. 화면은 숫자 대신 이 역할만 쓴다. 반 포인트와 굵기
/// 800 은 없다. 본문 계열에만 같은 크기의 600 강조 변형([strong])을 허용한다.
///
/// 색은 담지 않는다 — 테마의 `TextTheme` 이 텍스트 색을 입힌다.
class OnCareTypography {
  OnCareTypography._();

  /// 두 앱 공통 서체. 두 앱 pubspec 의 `fonts:` 패밀리 이름과 같아야 한다.
  static const String fontFamily = 'Pretendard';

  /// 큰 숫자(KPI·칼로리).
  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  );

  /// 페이지 제목(모바일 탭 대제목·웹 페이지 헤더).
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  /// 다이얼로그·시트 제목, 모바일 서브 페이지 앱바.
  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  /// 섹션·카드 제목.
  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );

  /// 강조 본문·목록 행 제목.
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  /// 본문·입력 텍스트.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  /// 보조 설명·메뉴 항목·토스트.
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  /// 칩·탭·필드 라벨.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// 도움말·시간·축 라벨·태그.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  // --- 버튼 라벨 — 버튼 컴포넌트 안에서만 쓴다(#1690 §3 확정) ---
  static const TextStyle buttonLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const TextStyle buttonMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const TextStyle buttonSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// 세그먼트 토글 칸 라벨 — `AppSegmentedToggle` 안에서만 쓴다(#1777).
  ///
  /// 공용 토글로 옮기기 전 알약 토글의 글자다. 그때 코드는 12.5 · 700 이었지만
  /// 전역 글자 배율 1.10 이 얹혀 **보이는 크기는 13.75** 였고, 줄 높이는 본문
  /// 테마의 1.5 를 물려받았다. 반 포인트를 두지 않으므로 보이는 크기에 가장 가까운
  /// 14 로 둔다.
  static const TextStyle segment = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );

  /// 역할 목록. 카탈로그·테스트가 순서대로 읽는다.
  static const Map<String, TextStyle> roles = <String, TextStyle>{
    'display': display,
    'titleLarge': titleLarge,
    'titleMedium': titleMedium,
    'titleSmall': titleSmall,
    'bodyLarge': bodyLarge,
    'body': body,
    'bodySmall': bodySmall,
    'label': label,
    'caption': caption,
  };

  /// 기기 접근성 배율 상한. 레이아웃이 실제로 버티는 한계다.
  static const double maxTextScale = 1.3;

  /// 본문 계열의 600 강조 변형. 크기는 그대로 둔다.
  static TextStyle strong(TextStyle style) =>
      style.copyWith(fontWeight: FontWeight.w600);

  /// 숫자가 바뀌어도 폭이 흔들리지 않는 고정폭 숫자.
  static TextStyle numeric(TextStyle style) => style.copyWith(
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// 기기 배율을 존중하되 1.0 ~ [maxTextScale] 로 묶는다.
  static TextScaler scaler(TextScaler device) {
    final double value = device.scale(1).clamp(1.0, maxTextScale);
    return TextScaler.linear(value);
  }

  /// Material `TextTheme` 슬롯을 역할에 맞춘다.
  static TextTheme textTheme({required Color color}) {
    TextStyle s(TextStyle style) => style.copyWith(color: color);
    return TextTheme(
      displayLarge: s(display),
      displayMedium: s(display),
      displaySmall: s(display),
      headlineLarge: s(titleLarge),
      headlineMedium: s(titleLarge),
      headlineSmall: s(titleLarge),
      titleLarge: s(titleLarge),
      titleMedium: s(titleMedium),
      titleSmall: s(titleSmall),
      bodyLarge: s(bodyLarge),
      bodyMedium: s(body),
      bodySmall: s(bodySmall),
      labelLarge: s(label),
      labelMedium: s(strong(caption)),
      labelSmall: s(caption),
    );
  }
}
