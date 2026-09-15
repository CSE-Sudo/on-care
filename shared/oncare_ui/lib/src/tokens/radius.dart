import 'package:flutter/painting.dart';

/// 모서리(#1690 §4). 조작 요소는 [md] 12 하나다(확정).
///
/// 이 밖의 반경(2·3·6·9·10·13·14·18·24·28)은 쓰지 않는다. 아바타만 원형이다.
class OnCareRadius {
  OnCareRadius._();

  /// 차트 막대·말풍선 꼬리.
  static const Radius xs = Radius.circular(4);

  /// 툴팁·작은 사각 표시.
  static const Radius sm = Radius.circular(8);

  /// 버튼·아이콘 버튼 배경·입력창·선택 칩·안쪽 타일·배너·메뉴·목록 행.
  static const Radius md = Radius.circular(12);

  /// 토스트·채팅 말풍선.
  static const Radius lg = Radius.circular(16);

  /// 카드·다이얼로그·바텀시트 위 모서리.
  static const Radius xl = Radius.circular(20);

  /// 태그·배지·세그먼트 트랙과 선택 칸(#1777).
  static const Radius pill = Radius.circular(999);

  static const BorderRadius xsAll = BorderRadius.all(xs);
  static const BorderRadius smAll = BorderRadius.all(sm);
  static const BorderRadius mdAll = BorderRadius.all(md);
  static const BorderRadius lgAll = BorderRadius.all(lg);
  static const BorderRadius xlAll = BorderRadius.all(xl);
  static const BorderRadius pillAll = BorderRadius.all(pill);

  /// 바텀시트 위 모서리.
  static const BorderRadius sheetTop = BorderRadius.vertical(top: xl);
}
