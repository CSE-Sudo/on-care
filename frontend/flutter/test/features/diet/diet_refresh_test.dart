/// 식단 기록이 바뀐 뒤의 캐시 갱신. (#2625)
///
/// 기간 집계(`이번 주`·`전체`)가 `GET /diet/days` 한 번이 된 뒤(#2236) 저장·
/// 수정·삭제 자리들은 날짜별 캐시만 비웠고, autoDispose 가 아닌 기간 집계는
/// 앱 수명 내내 옛 값으로 남았다. 여기서는 공통 갱신 함수가 무엇을 비우는지를
/// provider 단위로 확인한다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/advice/diet_advice.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_refresh.dart';
import 'package:oncare/shared/services/record_span_provider.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 어느 조회가 몇 번 불렸는지 센다.
class _CountingRepository extends FakeDietRepository {
  int todayCalls = 0;
  int periodCalls = 0;
  int adviceCalls = 0;
  final Map<DateTime, int> byDateCalls = <DateTime, int>{};

  @override
  Future<DietDay> fetchToday() {
    todayCalls++;
    return super.fetchToday();
  }

  @override
  Future<DietDay> fetchByDate(DateTime date) {
    final DateTime day = DateTime(date.year, date.month, date.day);
    byDateCalls[day] = (byDateCalls[day] ?? 0) + 1;
    return super.fetchByDate(date);
  }

  @override
  Future<DietPeriod> fetchPeriod({DateTime? from, DateTime? to}) {
    periodCalls++;
    return super.fetchPeriod(from: from, to: to);
  }

  @override
  Future<DietAdvice> fetchAdvice(String period, {String lang = 'ko'}) {
    adviceCalls++;
    return super.fetchAdvice(period, lang: lang);
  }
}

void main() {
  late _CountingRepository repo;
  late ProviderContainer container;
  late int spanCalls;
  late int dashboardCalls;

  final DietDateRange week = (
    from: DateTime(2026, 8, 17),
    to: DateTime(2026, 8, 23),
  );
  final DietDateRange all = (
    from: DateTime(2026, 6),
    to: DateTime(2026, 8, 20),
  );

  setUp(() {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    repo = _CountingRepository();
    spanCalls = 0;
    dashboardCalls = 0;
    container = ProviderContainer(
      overrides: <Override>[
        dietRepositoryProvider.overrideWithValue(repo),
        recordSpanProvider.overrideWith((Ref ref) {
          spanCalls++;
          return RecordSpan(dietFirstDate: DateTime(2026, 6));
        }),
        dashboardSummaryProvider.overrideWith((Ref ref) {
          dashboardCalls++;
          // 값은 보지 않는다 — 다시 읽혔는지만 센다.
          return Completer<DashboardSummary>().future;
        }),
      ],
    );
    addTearDown(container.dispose);
  });

  /// 화면이 보고 있는 상태를 만든다 — 기간 둘, 오늘, 지난 날 하루, 조언,
  /// 기록 시작일, 홈 요약을 한 번씩 읽어 캐시에 올린다.
  Future<void> warmUp() async {
    container.listen(dashboardSummaryProvider, (_, _) {});
    await container.read(dietPeriodProvider(week).future);
    await container.read(dietPeriodProvider(all).future);
    await container.read(dietTodayProvider.future);
    await container.read(dietByDateProvider(DateTime(2026, 8, 18)).future);
    await container.read(
      dietAdviceProvider((period: 'week', lang: 'ko')).future,
    );
    await container.read(recordSpanProvider.future);
  }

  test('기간 집계는 비우지 않으면 다시 읽지 않는다(캐시가 앱 수명 내내 남는다)', () async {
    await warmUp();
    final int before = repo.periodCalls;

    await container.read(dietPeriodProvider(week).future);
    await container.read(dietPeriodProvider(all).future);

    // 이것이 버그의 바탕이다 — autoDispose 가 아니라 누가 비워 주지 않으면
    // 저장한 끼니가 기간 그래프에 들어오지 않는다.
    expect(repo.periodCalls, before);
  });

  test('기록이 바뀌면 이번 주·전체 집계를 모두 다시 읽는다', () async {
    await warmUp();
    final int before = repo.periodCalls;

    refreshDietRecords(container.invalidate);
    await container.read(dietPeriodProvider(week).future);
    await container.read(dietPeriodProvider(all).future);

    // 범위 둘이 각각 한 번씩 — family 를 통째로 비웠다.
    expect(repo.periodCalls, before + 2);
  });

  test('오늘 식단과 조언도 다시 읽는다', () async {
    await warmUp();
    final int today = repo.todayCalls;
    final int advice = repo.adviceCalls;

    refreshDietRecords(container.invalidate);
    await container.read(dietTodayProvider.future);
    await container.read(
      dietAdviceProvider((period: 'week', lang: 'ko')).future,
    );

    expect(repo.todayCalls, greaterThan(today));
    expect(repo.adviceCalls, advice + 1);
  });

  test('기록 시작일을 다시 읽는다 — `전체` 가 어디서부터 그릴지 바뀔 수 있다', () async {
    await warmUp();
    expect(spanCalls, 1);

    refreshDietRecords(container.invalidate);
    await container.read(recordSpanProvider.future);

    expect(spanCalls, 2);
  });

  test('홈 대시보드 요약을 다시 읽는다', () async {
    await warmUp();
    expect(dashboardCalls, 1);

    refreshDietRecords(container.invalidate);
    container.read(dashboardSummaryProvider);

    expect(dashboardCalls, 2);
  });

  test('넘긴 날짜의 날짜별 캐시를 비운다', () async {
    await warmUp();
    final DateTime past = DateTime(2026, 8, 18);
    final int before = repo.byDateCalls[past]!;

    refreshDietRecords(container.invalidate, dates: <DateTime>[past]);
    await container.read(dietByDateProvider(past).future);

    expect(repo.byDateCalls[past], before + 1);
  });

  test('날짜를 넘기지 않으면 지난 날의 하루 캐시는 그대로 둔다', () async {
    await warmUp();
    final DateTime past = DateTime(2026, 8, 18);
    final int before = repo.byDateCalls[past]!;

    refreshDietRecords(container.invalidate);
    await container.read(dietByDateProvider(past).future);

    // 오늘만 비웠다 — 그 날의 기록을 건드린 흐름만 그 날을 넘긴다.
    expect(repo.byDateCalls[past], before);
  });

  test('시각이 붙은 날짜도 같은 날의 캐시를 비운다', () async {
    await warmUp();
    final DateTime past = DateTime(2026, 8, 18);
    final int before = repo.byDateCalls[past]!;

    refreshDietRecords(
      container.invalidate,
      dates: <DateTime>[DateTime(2026, 8, 18, 21, 30)],
    );
    await container.read(dietByDateProvider(past).future);

    expect(repo.byDateCalls[past], before + 1);
  });
}
