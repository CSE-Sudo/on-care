/// 테스트에서 "오늘" 을 고정한다.
///
/// 스케줄 시드는 요일로 수업을 놓는다(토 14:00 …). 지난 요일은 완료, 남은
/// 요일은 예정이라, 고정하지 않으면 "예정" 을 재는 테스트가 **그 요일을 지나는
/// 순간** 깨진다. 8/28 에 통과한 커밋이 8/30(일)에 18건 깨졌다.
///
/// 회원 앱의 `test/helpers/fixed_clock.dart` 와 같은 모양이다 (#1209).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';

/// 주 중간의 기준 시각 — 2026-08-20(목) 13:00.
///
/// 목요일 낮인 이유는 그 주의 수업이 앞뒤로 갈리기 때문이다. 오전 슬롯은 이미
/// 지났고(완료), 토요일 14:00 박성호 수업은 아직 오지 않았다(예정). 한쪽만
/// 있으면 다른 쪽 규칙이 깨져도 테스트가 통과한다.
final DateTime kMidWeekKst = DateTime(2026, 8, 20, 13);

/// 토요일 오후 — 2026-08-22(토) 15:00.
///
/// 시간표의 마지막 수업(토 14:00 박성호)이 **오늘이면서 이미 지난** 시각이다.
/// 완료·노쇼 동작은 지나간 약속에만 열리므로(`schedule_page.dart` 의
/// `isFuture`), 그 동작을 재는 테스트는 여기에 맞춰야 한다.
final DateTime kSaturdayKst = DateTime(2026, 8, 22, 15);

/// 같은 목요일 저녁 — 2026-08-20(목) 21:00.
///
/// 시드가 그날 놓는 수업(12:00~19:00)이 **모두 시작한 뒤**다. 완료·노쇼는
/// 날짜가 아니라 시작 시각이 지나야 열리므로(#2760), 오늘 16:00 박성호 수업을
/// 완료·노쇼로 처리하는 테스트는 이 시각에 맞춘다. 요일이 같아 시드는
/// [kMidWeekKst] 와 똑같이 깔린다.
final DateTime kMidWeekEveningKst = DateTime(2026, 8, 20, 21);

/// [date] 를 지금으로 고정한다. 테스트가 끝나면 실제 시각으로 되돌린다.
void useFixedKstDate([DateTime? date]) {
  final DateTime fixed = date ?? kMidWeekKst;
  debugNowKstOverride = () => fixed;
  addTearDown(() => debugNowKstOverride = null);
}
