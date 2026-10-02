/// 테스트에서 "오늘" 을 고정한다 (#1209).
///
/// 날짜 스트립은 **이번 주(월~일)** 만 보여 준다. "어제" 를 눌러 지난 날짜를
/// 고르는 테스트는 오늘이 월요일이면 누를 칸이 없어 실패한다 — 코드가 아니라
/// 테스트가 요일에 매인 것이다. 그런 테스트는 주 중간의 날짜로 고정한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';

/// 주 중간의 기준일 — 2026-08-20 (목) 오전 9시. 앞뒤로 사흘씩 남아 어제·내일
/// 어느 쪽을 눌러도 스트립 안에 있다.
final DateTime kMidWeekKst = DateTime(2026, 8, 20, 9);

/// [date] 를 오늘로 고정한다. 테스트가 끝나면 실제 시각으로 되돌린다.
void useFixedKstDate([DateTime? date]) {
  final DateTime fixed = date ?? kMidWeekKst;
  debugNowKstOverride = () => fixed;
  addTearDown(() => debugNowKstOverride = null);
}
