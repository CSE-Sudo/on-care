/// 화면이 구독하는 KST 시계 — 분이 바뀔 때마다 한 번씩 값을 낸다. (#2865)
///
/// 대시보드는 트레이너가 하루 종일 띄워 두는 화면이다. build 때 `nowKst()` 를 한
/// 번 읽으면 다른 이유로 다시 그려지기 전까지 "지금 16:03 · 56분 뒤" 가 멈춰
/// 있고, 자정을 넘겨도 어제 일정·어제 할 일이 그대로 남는다. 시각을 쓰는 위젯은
/// [kstNowProvider] 를, 날짜만 필요한 곳은 [kstTodayProvider] 를 watch 한다 —
/// 후자는 날짜 문자열이 바뀔 때만 알리므로 분마다 다시 구독하지 않는다.
///
/// 시각의 원천은 [nowKst] 다. 테스트는 `debugNowKstOverride` 로 시각을 고정하거나
/// [kstClockProvider] 를 가짜 스트림으로 바꿔 분·자정 경과를 흉내 낸다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';

/// [now] 다음 분 경계까지 남은 시간. 정확히 경계 위면 1분 뒤다.
Duration untilNextMinute(DateTime now) {
  final Duration intoMinute = Duration(
    seconds: now.second,
    milliseconds: now.millisecond,
    microseconds: now.microsecond,
  );
  return const Duration(minutes: 1) - intoMinute;
}

/// 구독하자마자 [now] 를 한 번, 그 뒤로는 분 경계마다 한 번씩 낸다.
///
/// 타이머는 구독이 있는 동안만 돈다 — 구독을 끊으면 바로 멈춘다.
Stream<DateTime> kstMinuteTicks({DateTime Function() now = nowKst}) {
  late final StreamController<DateTime> controller;
  Timer? timer;

  void scheduleNext() {
    timer = Timer(untilNextMinute(now()), () {
      if (controller.isClosed) return;
      controller.add(now());
      scheduleNext();
    });
  }

  controller = StreamController<DateTime>(
    onListen: () {
      controller.add(now());
      scheduleNext();
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
      unawaited(controller.close());
    },
  );
  return controller.stream;
}

/// 분 단위 KST 시계.
final kstClockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => kstMinuteTicks(),
  name: 'kstClock',
);

/// 지금(KST). 시계가 첫 값을 내기 전에는 [nowKst] 를 그대로 쓴다.
final kstNowProvider = Provider.autoDispose<DateTime>(
  (ref) => ref.watch(kstClockProvider).valueOrNull ?? nowKst(),
  name: 'kstNow',
);

/// 오늘(KST) `YYYY-MM-DD`. 날짜가 바뀔 때만 알린다(값이 같으면 Riverpod 이
/// 구독자를 깨우지 않는다).
final kstTodayProvider = Provider.autoDispose<String>(
  (ref) => ymd(ref.watch(kstNowProvider)),
  name: 'kstToday',
);
