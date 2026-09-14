/// 간격(#1690 §5). 4의 배수만 쓴다. [s2] 는 선·점 사이 간격에만 쓴다.
class OnCareSpacing {
  OnCareSpacing._();

  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;

  /// 허용 값 전체. 하드코딩 검사·테스트가 읽는다.
  static const List<double> scale = <double>[
    s2,
    s4,
    s8,
    s12,
    s16,
    s20,
    s24,
    s32,
    s40,
    s48,
  ];

  // --- 역할 ---
  /// 카드 안쪽.
  static const double cardPadding = s16;

  /// 안쪽 타일·배너 안쪽.
  static const double tilePadding = s12;

  /// 카드 사이.
  static const double cardGap = s12;

  /// 섹션 사이.
  static const double sectionGap = s24;

  /// 다이얼로그 안쪽.
  static const double dialogPadding = s24;

  /// 바텀시트 안쪽.
  static const double sheetPadding = s20;

  /// 두 버튼 사이(반반 하단 버튼).
  static const double buttonGap = s8;
}
