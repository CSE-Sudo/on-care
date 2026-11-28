/// 테스트 실행 동안 '오늘'을 실행 시작일로 묶는 시계 고정 (#2940).
///
/// 실행이 KST 자정을 걸치면 같은 테스트 안에서 `nowKst()` 를 두 번 읽은 값이
/// 하루 어긋난다 — 화면이 고른 날짜와 가짜 저장소가 판정한 '오늘'이 달라져
/// 저장한 값이 오늘 목록에 안 보인다. [KstDatePin] 은 **날짜는 시작일로 두고
/// 시·분·초는 실제 시계를 따른다.** 같은 날 안에서는 실제 시각 그대로다.
///
/// `test/flutter_test_config.dart` 가 [installRunKstDatePin] 으로 모든 테스트
/// 앞에 걸어 둔다. 자기 시각을 넣는 테스트(`useFixedKstDate`, 직접 대입한
/// `debugNowKstOverride`)는 그 위에 덮어쓰므로 그 값이 우선한다.
///
/// CI 는 같은 테스트를 KST 자정 직전·직후에 시작한 것처럼 한 번 더 돌린다
/// (#3448). `--dart-define=ONCARE_TEST_KST_TIME=23:59` 처럼 시각을 주면 실행의
/// 실제 시계가 오늘 그 시각에서 출발해 흐른다([runStartKstClock]). 낮에만 도는
/// CI 에서는 "실제 시각으로 만들고 그 뒤 시각을 옮겨 보는" 테스트가 통과하다가,
/// 밤에 main 이 깨진 뒤에야 드러났기 때문이다(#1607·#1762·#3448).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';

/// 고정을 걷어 낸 실제 KST 시각.
///
/// [nowKst] 의 실제 계산을 그대로 쓰려고 덮어쓴 값을 잠깐 비웠다 되돌린다.
DateTime realNowKst() {
  final DateTime Function()? saved = debugNowKstOverride;
  debugNowKstOverride = null;
  try {
    return nowKst();
  } finally {
    debugNowKstOverride = saved;
  }
}

/// CI 의 자정 실행이 주는 출발 시각(`HH:MM`, KST). 비어 있으면 실제 시계다.
const String kTestKstStartTime = String.fromEnvironment('ONCARE_TEST_KST_TIME');

/// 실행의 실제 시계 — [startTime] 이 있으면 오늘 그 시각에서 출발해 흐른다.
/// 주지 않으면 [kTestKstStartTime] 을 쓴다.
///
/// 날짜는 실제 오늘을 그대로 둔다. 요일은 평소 CI 처럼 실행일을 따르고, 시·분만
/// 자정 언저리로 옮긴다. 시계를 멈추지 않는 것은 실제 밤 실행처럼 자정을
/// 넘기는 경우까지 그대로 겪게 하려는 것이다.
///
/// 테스트가 `debugNowKstOverride = null` 로 고정을 비운 동안의 [nowKst] 는
/// 이 시계를 거치지 않고 실제 시각이다 — 앱 코드의 시계 자리는 건드리지 않는다.
DateTime Function() runStartKstClock([String? startTime]) {
  final String hhmm = startTime ?? kTestKstStartTime;
  if (hhmm.isEmpty) return realNowKst;
  final RegExpMatch? match = RegExp(
    r'^([01]\d|2[0-3]):([0-5]\d)$',
  ).firstMatch(hhmm);
  if (match == null) {
    throw ArgumentError.value(
      hhmm,
      'ONCARE_TEST_KST_TIME',
      'HH:MM(00:00~23:59) 형식이어야 합니다',
    );
  }
  final DateTime today = realNowKst();
  final DateTime start = DateTime(
    today.year,
    today.month,
    today.day,
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
  );
  final Stopwatch elapsed = Stopwatch()..start();
  return () => start.add(elapsed.elapsed);
}

/// 날짜만 [startDate] 로 묶은 KST 시계.
///
/// [source] 는 실제 시계다. 자정 직전·직후를 검증하는 테스트는 이것만 바꿔
/// 실제 시각이 넘어간 상황을 재현한다.
class KstDatePin {
  KstDatePin({DateTime Function()? source})
    : source = source ?? runStartKstClock() {
    final DateTime start = this.source();
    startDate = DateTime(start.year, start.month, start.day);
  }

  DateTime Function() source;

  /// 실행 시작일(0시).
  late final DateTime startDate;

  /// 시각은 [source] 를 따르고 날짜는 [startDate] 로 둔다.
  DateTime now() {
    final DateTime current = source();
    if (current.year == startDate.year &&
        current.month == startDate.month &&
        current.day == startDate.day) {
      return current;
    }
    return DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      current.hour,
      current.minute,
      current.second,
      current.millisecond,
      current.microsecond,
    );
  }
}

/// 이 실행(테스트 파일)에 걸린 고정. [installRunKstDatePin] 전에는 null.
KstDatePin? runKstDatePin;

/// 모든 테스트 앞에서 [debugNowKstOverride] 가 비어 있으면 실행 고정을 건다.
///
/// 앞 테스트가 끝나며 `debugNowKstOverride = null` 로 되돌려도 다음 테스트
/// 시작 때 다시 걸린다. 테스트 본문·`setUp` 에서 넣는 값은 이 뒤에 들어오므로
/// 그 값이 우선한다.
void installRunKstDatePin([KstDatePin? pin]) {
  final KstDatePin installed = pin ?? KstDatePin();
  runKstDatePin = installed;
  setUp(() {
    debugNowKstOverride ??= installed.now;
  });
}
