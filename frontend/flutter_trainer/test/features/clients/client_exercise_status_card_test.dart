import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_exercise_status_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_section.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/activity_charts.dart';

/// 회원 운동 현황은 회원 앱 `운동 현황` 과 **같은 그림**이다. (#943)
///
/// `오늘` 은 도넛 + 유형별 시간, 기간은 유형별 3색 누적 막대. 예전에는 트레이너만
/// 한 색 막대를 봤다 — 회원이 "이번 주 근력이 적었죠" 라고 말해도 근거가 없었다.
ClientExercisePeriod _fixture(
  ClientPeriodKey key, {
  required List<int> cardio,
  required List<int> strength,
  required List<int> stretch,
}) {
  final List<DateTime> dates = clientRangeDates(
    clientRangeFor(key.period, key.day),
  );
  int at(List<int> xs, int i) => i < xs.length ? xs[i] : 0;
  return ClientExercisePeriod(
    range: clientRangeFor(key.period, key.day),
    days: <ClientExerciseDay>[
      for (int i = 0; i < dates.length; i++)
        ClientExerciseDay(
          date: dates[i],
          minutes: at(cardio, i) + at(strength, i) + at(stretch, i),
          calories: (at(cardio, i) + at(strength, i) + at(stretch, i)) * 6,
          cardioMinutes: at(cardio, i),
          strengthMinutes: at(strength, i),
          stretchingMinutes: at(stretch, i),
        ),
    ],
  );
}

/// 카드를 섹션 헤더와 함께 띄운다 — 실제 화면과 같은 조합이다.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  ClientPeriod _period = ClientPeriod.today;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClientPeriodSection(
          icon: Icons.monitor_heart_outlined,
          title: '운동 현황',
          period: _period,
          onChanged: (ClientPeriod p) => setState(() => _period = p),
          child: ClientExerciseStatusCard(clientId: 'c1', period: _period),
        ),
      ),
    ),
  );
}

Widget _app(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(
    locale: Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: _Host(),
  ),
);

void main() {
  List<Override> withSplit() => <Override>[
    clientExercisePeriodProvider.overrideWith(
      (ref, key) async => _fixture(
        key,
        // `전체`의 두 번째 주가 실행 요일과 무관하게 기록을 갖도록 2주치다.
        // 7일치뿐이면 84일 범위가 월요일에 시작하는 날에는 두 번째 막대가
        // 비어, 주말에만 테스트가 깨진다.
        cardio: const <int>[20, 0, 30, 0, 10, 0, 0, 20, 0, 30, 0, 10, 0, 0],
        strength: const <int>[25, 0, 15, 0, 30, 0, 0, 25, 0, 15, 0, 30, 0, 0],
        stretch: const <int>[15, 0, 0, 0, 20, 0, 0, 15, 0, 0, 0, 20, 0, 0],
      ),
    ),
  ];

  Future<void> pump(WidgetTester tester, List<Override> overrides) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(overrides));
    await tester.pumpAndSettle();
  }

  testWidgets('오늘은 소모 칼로리 도넛과 유형별 값으로 보인다', (tester) async {
    await pump(tester, withSplit());

    expect(find.byType(BurnDonut), findsOneWidget);
    // 소모 칼로리는 도넛 **안**에서 말한다(#1166) — 링 옆에 같은 숫자를 또
    // 적으면 한 화면에서 같은 말이 두 번 나온다. 그래서 `오늘 소모` 는 이제
    // 화면의 글자가 아니라 도넛의 시맨틱 라벨에만 있다.
    expect(
      tester.widget<BurnDonut>(find.byType(BurnDonut)).title,
      '오늘 소모',
    );
    // 유산소·근력·스트레칭이 이름과 값으로 함께 읽힌다 — 소모 칼로리가
    // 무엇으로 채워졌는지가 화면에 있어야 한다.
    for (final String label in <String>['유산소', '근력', '스트레칭']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // 기간 그래프는 오늘에 없다.
    expect(find.byType(BurnBarChart), findsNothing);
    expect(find.byType(BurnGoalRings), findsNothing);
  });

  testWidgets('이번 주는 유형별 목표 링으로 보인다', (tester) async {
    await pump(tester, withSplit());

    await tester.tap(find.byKey(const Key('client-period-week')));
    await tester.pumpAndSettle();

    expect(find.byType(BurnGoalRings), findsOneWidget);
    expect(find.byType(BurnDonut), findsNothing);
    // 유형 셋이 회원 앱과 같은 순서·색으로 줄지어 있다.
    final List<ActivityValueRow> rows = tester
        .widgetList<ActivityValueRow>(find.byType(ActivityValueRow))
        .toList();
    expect(rows.map((ActivityValueRow x) => x.color).take(3).toList(), <Color>[
      AppColors.chartCardio,
      AppColors.chartStrength,
      AppColors.chartStretching,
    ]);
  });

  testWidgets('이번 달 막대 툴팁이 소모 칼로리와 유형별 값을 말한다', (tester) async {
    await pump(tester, withSplit());
    await tester.tap(find.byKey(const Key('client-period-month')));
    await tester.pumpAndSettle();

    final Tooltip tip = tester.widget<Tooltip>(
      find.byKey(const Key('client-exercise-bar-0')),
    );
    final String text = tip.richMessage!.toPlainText();
    expect(text, contains('kcal'));
  });

  testWidgets('전체는 한 칸이 한 주다 (#1077)', (tester) async {
    await pump(tester, withSplit());
    await tester.tap(find.byKey(const Key('client-period-month')));
    await tester.pumpAndSettle();

    // 몇 칸인지는 오늘이 무슨 요일인지에 따라 12 나 13 이 된다 — 숫자를 여기
    // 적으면 주말에만 깨지는 테스트가 된다. 기간이 걸친 **주의 수**로 잰다.
    final int weeks = clientRangeDates(
      clientRangeFor(ClientPeriod.month, todayKst()),
    ).map(clientMondayOf).toSet().length;
    final int bars = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .where(
          (Tooltip t) =>
              (t.key as ValueKey<String>?)?.value.startsWith(
                'client-exercise-bar-',
              ) ??
              false,
        )
        .length;
    expect(bars, weeks);

    // 한 칸이 한 주면 그 칸의 소모 칼로리도 일곱 날을 더한 값이다.
    final Tooltip tip = tester.widget<Tooltip>(
      find.byKey(const Key('client-exercise-bar-1')),
    );
    expect(tip.richMessage!.toPlainText(), contains('kcal'));
  });

  testWidgets('기간을 바꿔도 토글 자리가 움직이지 않는다', (tester) async {
    await pump(tester, withSplit());

    Rect toggleRect() => tester.getRect(
      find.byKey(const ValueKey<String>('client-period-toggle')),
    );

    final Rect atToday = toggleRect();
    await tester.tap(find.byKey(const Key('client-period-week')));
    await tester.pumpAndSettle();
    final Rect atWeek = toggleRect();
    await tester.tap(find.byKey(const Key('client-period-month')));
    await tester.pumpAndSettle();
    final Rect atMonth = toggleRect();

    // 카드 제목 줄에 얹었을 때는 카드가 갈리며 제목 길이가 달라져 토글이
    // 좌우로 움직였다. 헤더는 기간과 무관하게 늘 같은 것을 그린다.
    expect(atWeek, atToday);
    expect(atMonth, atToday);
  });

  testWidgets('유형 분해가 없으면 지어내지 않고 유산소로 둔다', (tester) async {
    await pump(tester, <Override>[
      clientExercisePeriodProvider.overrideWith(
        (ref, key) async => ClientExercisePeriod(
          range: clientRangeFor(key.period, key.day),
          days: <ClientExerciseDay>[
            for (final DateTime d in clientRangeDates(
              clientRangeFor(key.period, key.day),
            ))
              ClientExerciseDay(date: d, minutes: 40, calories: 240),
          ],
        ),
      ),
    ]);

    await tester.tap(find.byKey(const Key('client-period-month')));
    await tester.pumpAndSettle();

    final Tooltip tip = tester.widget<Tooltip>(
      find.byKey(const Key('client-exercise-bar-0')),
    );
    final String text = tip.richMessage!.toPlainText();
    expect(text, contains('유산소'));
    // 없는 근력·스트레칭 값을 지어내면 안 된다.
    expect(text, isNot(contains('근력')));
    expect(text, isNot(contains('스트레칭')));
  });

  testWidgets('폭 1024 · 영어 · 배율 1.3 에서도 토글이 제자리고 넘치지 않는다', (tester) async {
    // #849 가 지키는 가장 좁은 지원 조합. 기간을 바꿔도 헤더가 흔들리지 않아야
    // 하고, 카드가 화면 밖으로 나가면 안 된다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: withSplit(),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const _Host(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect toggleRect() => tester.getRect(
      find.byKey(const ValueKey<String>('client-period-toggle')),
    );
    final Rect atToday = toggleRect();

    for (final String period in <String>['week', 'month']) {
      await tester.tap(find.byKey(Key('client-period-$period')));
      await tester.pumpAndSettle();
      expect(toggleRect(), atToday, reason: period);
      expect(tester.takeException(), isNull, reason: period);
      // 카드가 가로로 넘치지 않는다.
      final Rect card = tester.getRect(
        find.byKey(const ValueKey<String>('client-exercise-status-card')),
      );
      expect(card.right, lessThanOrEqualTo(1024.0 + 0.5), reason: period);
    }
  });

  testWidgets('길이가 짧은 유형 배열이 와도 죽지 않는다 (리뷰 #946)', (tester) async {
    // `hasTypeSplit` 은 셋의 길이가 서로 같은지만 본다. 기간 provider 의 루프는
    // 언제나 7일을 도는데, 길이 2짜리 응답이 분해로 인정되면 d == 2 에서 범위를
    // 넘어 화면이 통째로 죽는다.
    await pump(tester, <Override>[
      clientExercisePeriodProvider.overrideWith((ref, key) async {
        final List<DateTime> dates = clientRangeDates(
          clientRangeFor(key.period, key.day),
        );
        return ClientExercisePeriod(
          range: clientRangeFor(key.period, key.day),
          days: <ClientExerciseDay>[
            for (int i = 0; i < dates.length; i++)
              ClientExerciseDay(
                date: dates[i],
                minutes: i < 2 ? 30 : 0,
                calories: i < 2 ? 180 : 0,
                cardioMinutes: i < 2 ? 30 : 0,
              ),
          ],
        );
      }),
    ]);

    await tester.tap(find.byKey(const Key('client-period-week')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(BurnGoalRings), findsOneWidget);
  });

  test('유형 분해는 길이가 맞을 때만 쓴다', () {
    // 반쪽만 실려 온 응답으로 쌓으면 막대가 실제보다 낮아 보인다.
    const ClientExerciseWeek short = ClientExerciseWeek(
      dayLabels: <String>['월', '화'],
      dailyMinutes: <int>[30, 20],
      dailyCalories: <int>[180, 120],
      cardioMinutes: <int>[30],
      totalMinutes: 50,
      totalCalories: 300,
    );
    expect(short.hasTypeSplit, isFalse);

    const ClientExerciseWeek full = ClientExerciseWeek(
      dayLabels: <String>['월', '화'],
      dailyMinutes: <int>[30, 20],
      dailyCalories: <int>[180, 120],
      cardioMinutes: <int>[20, 10],
      strengthMinutes: <int>[10, 5],
      stretchingMinutes: <int>[0, 5],
      totalMinutes: 50,
      totalCalories: 300,
    );
    expect(full.hasTypeSplit, isTrue);
  });

  test('오늘 기준 키는 KST 를 쓴다', () {
    expect(clientPeriodKeyNow('c1', ClientPeriod.today).day, todayKst());
  });

  group('상세 내역 펼치기/접기', () {
    // 이력은 이미 최신순으로 온다(`clientHistoryProvider` 계약) — 접힌
    // 상태에서 보이는 첫 항목이 곧 가장 최근 기록이어야 한다.
    List<RoutineHistoryEntry> history() => const <RoutineHistoryEntry>[
      RoutineHistoryEntry(
        dateLabel: '오늘 기록',
        label: 'PT 세션',
        completionRate: 100,
        exercises: <String>['레그프레스 3세트 × 12회 · 80kg ✓'],
        clientFeedback: '',
        trainerNote: '',
      ),
      RoutineHistoryEntry(
        dateLabel: '어제 기록',
        label: 'PT 세션',
        completionRate: 80,
        exercises: <String>['데드리프트 4세트 × 8회 · 55kg ✓'],
        clientFeedback: '',
        trainerNote: '',
      ),
    ];

    Widget detailApp(
      List<RoutineHistoryEntry> fixture, {
      ClientPeriod period = ClientPeriod.week,
    }) => ProviderScope(
      overrides: <Override>[
        ...withSplit(),
        clientHistoryProvider.overrideWith(
          (ref, clientId) => Stream<List<RoutineHistoryEntry>>.value(fixture),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ClientExerciseStatusCard(
              clientId: 'c1',
              clientName: '김민수',
              period: period,
            ),
          ),
        ),
      ),
    );

    final Finder toggle = find.byKey(
      const ValueKey<String>('client-exercise-detail-toggle'),
    );
    final Finder collapse = find.byKey(
      const ValueKey<String>('client-exercise-detail-collapse'),
    );

    /// 한 주(7건)를 넘겨야 `더보기` 가 두 번 눌린다.
    List<RoutineHistoryEntry> manyDays(int count) => <RoutineHistoryEntry>[
      for (int i = 0; i < count; i++)
        RoutineHistoryEntry(
          dateLabel: '$i일 전 기록',
          label: 'PT 세션',
          completionRate: 100,
          exercises: const <String>['레그프레스 3세트 × 12회 · 80kg ✓'],
          clientFeedback: '',
          trainerNote: '',
        ),
    ];

    testWidgets('접힌 기본 상태에는 최근 기록 하나만 보인다', (tester) async {
      await tester.pumpWidget(detailApp(history()));
      await tester.pumpAndSettle();

      expect(find.textContaining('오늘 기록'), findsOneWidget);
      expect(find.textContaining('어제 기록'), findsNothing);
      expect(find.text('레그프레스 3세트 × 12회 · 80kg'), findsOneWidget);
      expect(toggle, findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      // 접힌 상태에서는 접을 것이 없다 — 버튼도 없다.
      expect(collapse, findsNothing);
    });

    testWidgets('펼치면 남은 기록이, 접으면 최근 하나만 보인다', (tester) async {
      await tester.pumpWidget(detailApp(history()));
      await tester.pumpAndSettle();

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.textContaining('오늘 기록'), findsOneWidget);
      expect(find.textContaining('어제 기록'), findsOneWidget);
      expect(find.text('데드리프트 4세트 × 8회 · 55kg'), findsOneWidget);
      // 두 건뿐이라 더 펼칠 것이 없다 — `더보기` 는 사라지고 `접기` 만 남는다.
      expect(toggle, findsNothing);
      expect(collapse, findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);

      await tester.tap(collapse);
      await tester.pumpAndSettle();

      expect(find.textContaining('오늘 기록'), findsOneWidget);
      expect(find.textContaining('어제 기록'), findsNothing);
    });

    testWidgets('이번 주는 한 번에 한 주치를 펼치고 버튼은 하나만 남는다 (#1426)', (tester) async {
      // 목록이 길어지면 버튼이 화면 밖으로 내려가 탭이 빗나간다.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 4000);
      addTearDown(tester.view.reset);
      // 스무 건 — 한 주(7)를 넘고도 남는다.
      await tester.pumpWidget(detailApp(manyDays(20)));
      await tester.pumpAndSettle();

      Finder day(int i) => find.textContaining('$i일 전 기록');

      // 접힌 기본은 가장 최근 하나다.
      expect(day(0), findsOneWidget);
      expect(day(1), findsNothing);

      // `더보기` 는 한 번이다 — 한 주치가 한꺼번에 열리고, 그 뒤로 더 내려가는
      // 버튼은 나오지 않는다.
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(day(6), findsOneWidget);
      expect(day(7), findsNothing);
      expect(toggle, findsNothing, reason: '펼친 뒤 `더보기` 가 다시 나오면 안 된다');
      expect(collapse, findsOneWidget);

      // 이번 주는 일곱 줄이라 안쪽 스크롤을 만들지 않는다.
      expect(
        find.byKey(const ValueKey<String>('client-exercise-detail-scroll')),
        findsNothing,
      );

      await tester.tap(collapse);
      await tester.pumpAndSettle();
      expect(day(0), findsOneWidget);
      expect(day(1), findsNothing);
      expect(collapse, findsNothing);
      expect(toggle, findsOneWidget);
    });

    testWidgets('전체는 정해진 높이 안에서 전체 기록을 스크롤한다 (#1426)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 4000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        detailApp(manyDays(20), period: ClientPeriod.month),
      );
      await tester.pumpAndSettle();

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final Finder scroller = find.byKey(
        const ValueKey<String>('client-exercise-detail-scroll'),
      );
      expect(scroller, findsOneWidget);
      // 열이 기록 수만큼 길어지지 않는다 — 스무 건이 정해진 높이 안에 든다.
      expect(tester.getSize(scroller).height, lessThanOrEqualTo(260));

      // 안쪽에서 내리면 뒤쪽 기록이 나온다.
      final ScrollableState inner = tester.state<ScrollableState>(
        find.descendant(of: scroller, matching: find.byType(Scrollable)),
      );
      expect(inner.position.maxScrollExtent, greaterThan(0));
      inner.position.jumpTo(inner.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.textContaining('19일 전 기록'), findsOneWidget);
    });

    testWidgets('기간을 바꾸면 다시 접힌다 (#1426)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 4000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(detailApp(manyDays(20)));
      await tester.pumpAndSettle();

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(collapse, findsOneWidget);

      await tester.pumpWidget(
        detailApp(manyDays(20), period: ClientPeriod.month),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('0일 전 기록'), findsOneWidget);
      expect(find.textContaining('1일 전 기록'), findsNothing);
      expect(toggle, findsOneWidget);
      expect(collapse, findsNothing);
    });

    testWidgets('기록이 하나뿐이면 펼치기 버튼이 없다', (tester) async {
      await tester.pumpWidget(
        detailApp(<RoutineHistoryEntry>[history().first]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('오늘 기록'), findsOneWidget);
      expect(toggle, findsNothing);
      expect(collapse, findsNothing);
    });
  });
}
