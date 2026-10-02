/// 서비스 기준 시각 — 항상 KST(Asia/Seoul).
///
/// `DateTime.now()` 는 **기기 로컬 시간**이다. 기기 타임존이 KST 가 아니면 앱이
/// 판단하는 "오늘" 이 서버가 판단하는 "오늘" 과 어긋난다 — 기기가 UTC 면
/// KST 00:00~09:00 사이에 앱은 하루 전을 오늘로 본다. 아침에 기록한 식사가 전날
/// 칸에 들어가고, 서버가 준 오늘치 데이터와 화면의 날짜 라벨이 하루 밀린다.
///
/// 백엔드는 같은 문제를 #557 에서 `app/core/clock.py` 로 없앴다(프로세스
/// 타임존이 UTC 여도 도메인 날짜는 KST). 앱에도 같은 계층을 두어 양쪽이 같은
/// "오늘" 을 본다(#850).
///
/// **KST 는 서머타임이 없어 항상 UTC+9 다.** 그래서 tz 데이터베이스 없이 고정
/// 오프셋으로 충분하다.
///
/// 돌려주는 값은 **KST 벽시계를 필드에 담은 로컬 `DateTime`** 이다. 호출부는
/// `year`·`month`·`day`·`weekday`·`hour` 만 읽으므로 이 편이 쓰기 쉽다. 대신
/// 앱 안에서는 이 함수만 쓰고 `DateTime.now()` 를 섞지 않는다 — 섞으면 두 값의
/// 기준이 9시간 어긋난다. 그 규칙은 `test/core/utils/clock_test.dart` 가 지킨다.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// KST 는 서머타임이 없다 — 언제나 UTC+9.
const Duration kstOffset = Duration(hours: 9);

/// 테스트가 "지금" 을 고정하는 자리. null 이면 실제 시각이다.
///
/// 날짜 스트립처럼 **오늘이 무슨 요일인지**에 따라 화면이 달라지는 곳을 재려면
/// 오늘을 고정해야 한다. 고정하지 않으면 그 테스트는 요일에 매인다 — 지난
/// 날짜를 고르는 테스트들이 스트립에 이번 주(월~일)만 있는 탓에 **월요일마다**
/// 깨졌다 (#1209).
///
/// 앱 코드에서는 절대 건드리지 않는다. 테스트는 `test/helpers/fixed_clock.dart`
/// 의 `useFixedKstDate` 로 쓰고, 그쪽이 끝나면 되돌린다.
@visibleForTesting
DateTime Function()? debugNowKstOverride;

/// KST 기준 현재 시각.
DateTime nowKst() {
  final DateTime Function()? fixed = debugNowKstOverride;
  if (fixed != null) return fixed();
  final DateTime seoul = DateTime.now().toUtc().add(kstOffset);
  // `isUtc` 를 떼어 로컬 `DateTime` 으로 만든다. 필드는 서울의 벽시계 그대로다.
  return DateTime(
    seoul.year,
    seoul.month,
    seoul.day,
    seoul.hour,
    seoul.minute,
    seoul.second,
    seoul.millisecond,
    seoul.microsecond,
  );
}

/// KST 기준 오늘 — 시각은 0시로 자른다. 날짜만 비교할 때 쓴다.
DateTime todayKst() {
  final DateTime n = nowKst();
  return DateTime(n.year, n.month, n.day);
}

/// [d] 의 날짜에서 달력으로 [days] 일 뒤(음수면 앞)의 날 — 시각은 0시다. (#2890)
///
/// `d.add(Duration(days: n))` 는 달력의 하루가 아니라 **정확히 24시간**을
/// 더한다. 서머타임이 있는 기기 시간대(미국·유럽·호주 등)에서 시계가 바뀌는
/// 날을 건너가면 한 시간이 남거나 모자라 전날 23:00 으로 떨어지고, 그 값을
/// `ymd()` 로 자르면 날짜가 하루 어긋난다. `DateTime` 생성자는 넘친 일 수를
/// 달력 기준으로 정규화하므로 시간대 전환과 상관없이 자정이 유지된다.
/// 날짜만 다루는 계산(주 이동·요일 칸·반복 회차)은 이 함수를 쓴다.
DateTime addCalendarDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// [d] 가 속한 주의 월요일 0시. (#2890)
///
/// 주 단위 조회 키·주간 화면의 첫 칸이다. [addCalendarDays] 와 같은 이유로
/// `subtract(Duration(days: …))` 를 쓰지 않는다.
DateTime mondayOf(DateTime d) =>
    addCalendarDays(d, -(d.weekday - DateTime.monday));
