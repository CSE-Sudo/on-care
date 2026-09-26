import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_ai_analysis_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// Seeded client ids by display name — the detail is addressed by id.
const Map<String, String> seedClientIds = <String, String>{
  '김민수': 'seed-client-1',
  '이지수': 'seed-client-2',
  '박성호': 'seed-client-3',
  '강서연': 'seed-client-6',
  // The brand-new client: no meals, no history, no sodium series.
  '임도현': 'seed-client-7',
};

class _DietFailsOnceRepository extends DriftClientRepository {
  _DietFailsOnceRepository(super.db);

  int watchDietCalls = 0;

  @override
  Stream<List<ClientDietEntry>> watchDiet(String clientId) {
    watchDietCalls++;
    if (watchDietCalls == 1) {
      return Stream<List<ClientDietEntry>>.error(
        StateError('diet transport detail'),
      );
    }
    return super.watchDiet(clientId);
  }
}

void main() {
  group('ClientRepository.watchDiet', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test('returns the 3 meals in seeded order for a client', () async {
      final meals = await DriftClientRepository(
        db,
      ).watchDiet('seed-client-1').first;
      expect(meals.map((m) => m.meal).toList(), <String>['아침', '점심', '간식']);
      // 같은 끼니 라벨이 하루에 두 번 저장돼도 목록 위젯 키가 겹치지 않도록
      // 고유한 id 를 함께 준다 — meal 라벨만으로는 고유하지 않다.
      expect(meals.map((m) => m.id).toSet(), hasLength(3));
      expect(meals.every((m) => m.id.isNotEmpty), isTrue);
      expect(meals.first.items, '스크램블 에그, 딸기');
      expect(meals.first.calories, 247);
      expect(meals.first.sodiumMg, 359);
      expect(meals.first.carbsG, 10.4);
      expect(meals.first.proteinG, 16);
      expect(meals.first.fatG, 14.8);
      expect(meals[1].items, '짬뽕');
      expect(meals[1].calories, 707);
      expect(meals[1].sodiumMg, 4286);
      expect(meals[1].carbsG, 95.1);
      expect(meals[1].proteinG, 35.4);
      expect(meals[1].fatG, 12.7);
      expect(meals[2].items, '아이스 아메리카노, 견과류 한 봉');
      expect(meals[2].calories, 100);
      expect(meals[2].sodiumMg, 12);
      expect(meals[2].carbsG, 6.1);
      expect(meals[2].proteinG, 3);
      expect(meals[2].fatG, 6.6);

      final minsu = (await DriftClientRepository(db).watchClients().first)
          .firstWhere((client) => client.id == 'seed-client-1');
      expect(minsu.calories, 1054);
      expect(minsu.sodiumMg, 4657);
      expect(minsu.sugarG, 16.7);
      expect(minsu.carbsG, 111.6);
      expect(minsu.proteinG, 54.4);
      expect(minsu.fatG, 34.1);
    });

    test('returns per-client data (clients differ)', () async {
      final repo = DriftClientRepository(db);
      final jisu = await repo.watchDiet('seed-client-2').first;
      final seongho = await repo.watchDiet('seed-client-3').first;
      expect(jisu.first.items, '그릭요거트, 블루베리');
      expect(seongho[1].items, '짜장면'); // 점심
    });
  });

  group('seeded weekly series', () {
    // 계열은 이번 주 월→일이다(#746). 아래 두 테스트는 시드 시계를 고정한다 —
    // 무엇이 이번 주에 남는지는 요일마다 다르므로, 실행한 날에 기대값을 맡기면
    // 코드를 건드리지 않아도 월·화요일에 깨진다(#826).
    Future<List<TrainerClient>> seededOn(DateTime pinned) async {
      // 이 그룹의 `db` 와 겹쳐 열어 두면 drift 가 인스턴스 중복을 경고한다.
      // 로스터를 읽고 나면 볼 일이 없으므로 그 자리에서 닫는다.
      final pinnedDb = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        await seedIfEmpty(pinnedDb, clock: pinned);
        return await DriftClientRepository(pinnedDb).watchClients().first;
      } finally {
        await pinnedDb.close();
      }
    }

    test(
      'client rows carry this week\'s sodium history on its weekdays',
      () async {
        // 2026-08-19 은 수요일, 2026-08-17 은 월요일이다.
        for (final pinned in <DateTime>[
          DateTime(2026, 8, 19, 10),
          DateTime(2026, 8, 17, 10),
        ]) {
          final clients = await seededOn(pinned);
          final todayIndex = pinned.weekday - 1;
          for (final c in clients) {
            // 요일 라벨과 함께 그리므로 길이는 늘 7이고, 오늘 값은 마지막 칸이
            // 아니라 오늘 요일 칸에 놓인다.
            expect(c.sodiumWeek, hasLength(7), reason: '${c.name} on $pinned');
            expect(
              c.sodiumWeek[todayIndex],
              c.sodiumMg,
              reason: '${c.name} on $pinned',
            );
            // 아직 오지 않은 요일은 누구에게나 0 — 기록 없음과 같은 표현이다.
            expect(
              c.sodiumWeek.skip(todayIndex + 1),
              everyElement(0),
              reason: '${c.name} on $pinned',
            );
          }
        }
      },
    );

    test('a seeded day from before Monday stays in last week', () async {
      // 이지수의 시드에서 목표를 넘는 날은 2100 하나뿐이고, 그 값은 오늘에서
      // 이틀 앞이다. 수요일에는 이번 주에 남고 월요일에는 잘려 나간다 — 잘린
      // 날이 집계에 남으면 지난주 기록을 이번 주로 세는 것이다.
      final onWednesday = await seededOn(DateTime(2026, 8, 19, 10));
      final jisuWed = onWednesday.firstWhere((c) => c.name == '이지수');
      expect(jisuWed.sodiumWeek.first, 2100);
      expect(jisuWed.sodiumOverDays, 1);

      final onMonday = await seededOn(DateTime(2026, 8, 17, 10));
      final jisuMon = onMonday.firstWhere((c) => c.name == '이지수');
      expect(jisuMon.sodiumWeek.where((mg) => mg > 0), hasLength(1));
      expect(jisuMon.sodiumOverDays, 0);

      // 픽스처가 정하는 김민수는 자기 날짜대로 놓이므로, 오늘까지의 기록이
      // 있는 한 주 평균이 잡힌다.
      final minsu = onWednesday.firstWhere((c) => c.name == '김민수');
      expect(minsu.sodiumOverDays, greaterThan(0));
      expect(minsu.sodiumWeekAvg, isNotNull);
    });
  });

  group('DietView', () {
    // 식단·운동은 자기 `ListView` 를 만들지 않는다(#1024) — 신체·목표·메모
    // 패널과 하나의 스크롤을 공유하도록 `embedded: true` 로 그려진다. 그
    // 공유 스크롤(`ListView`) 자체가 `client-detail-tabs-$clientId` 키를
    // 달고 있다.
    Finder detailScrollable(String clientId) => find
        .descendant(
          of: find.byKey(ValueKey<String>('client-detail-tabs-$clientId')),
          matching: find.byType(Scrollable),
        )
        .first;

    // 끼니 카드는 `meal.id` 를 키로 쓴다(같은 끼니 라벨이 하루에 두 번 저장될
    // 수 있어 라벨만으로는 고유하지 않다) — 그래서 라벨 배지 텍스트로 카드를
    // 찾아 올라간다.
    Finder mealCardFinder(String mealLabel) => find.ancestor(
      of: find.text(mealLabel),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('diet-meal-'),
      ),
    );

    Future<ProviderContainer> openDiet(
      WidgetTester tester,
      String clientName, {
      DateTime? seedClock,
    }) => pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(seedClientIds[clientName]!, section: 'diet'),
      seedClock: seedClock,
    );

    testWidgets('서버 조언이 없으면 AI 분석 카드를 세우지 않는다 (#2271)', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        extraOverrides: <Override>[
          clientDietAdviceProvider.overrideWith(
            (ref, key) async => throw StateError('advice offline'),
          ),
        ],
      );

      // 예전에는 이 사이 화면이 나트륨 목표만 보고 `나트륨이 목표치를 …
      // 초과했어요` / `균형이 잘 맞아요` 를 지어냈다. 운동 탭처럼 자리를 비운다.
      expect(
        find.byKey(const ValueKey<String>('diet-ai-analysis')),
        findsNothing,
      );
      expect(find.textContaining('나트륨이 목표치를'), findsNothing);
      expect(find.textContaining('균형이 잘 맞아요'), findsNothing);
    });

    testWidgets('a failed diet retries in place on a narrow viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith(
            (ref) => _DietFailsOnceRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
      );

      expect(find.text('식단을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('아직 기록된 식단이 없어요'), findsNothing);
      expect(find.text('diet transport detail'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('diet-retry-seed-client-1')),
          matching: find.byType(AppButton),
        ),
      );
      await settle(tester);

      final repository =
          container.read(clientRepositoryProvider) as _DietFailsOnceRepository;
      final context = tester.element(find.byType(Navigator).first);
      expect(repository.watchDietCalls, 2);
      expect(
        GoRouter.of(context).routeInformationProvider.value.uri.toString(),
        AppRoutes.clientDetail('seed-client-1', section: 'diet'),
      );
      expect(find.text('오늘 섭취 칼로리'), findsOneWidget);
      // 회원 앱과 같은 **한 장**이다(#698, #1166): 칼로리 링 + 탄단지 글자
      // 진행 바 세 줄(#2156). 예전의 세 장짜리 묶음은 없어졌다.
      expect(
        find.byKey(const Key('client-nutrition-summary-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('client-nutrition-calorie-progress')),
        findsOneWidget,
      );
      final calorieProgress = tester.widget<NutritionCalorieRing>(
        find.byKey(const Key('client-nutrition-calorie-progress')),
      );
      // 목표 안쪽은 **메인 색**이다 (#1166) — 회원 앱이 자기 메인 색을 쓰는
      // 자리와 같다. 초록은 "정상" 으로 읽혀서 목표에 한참 못 미친 날까지
      // 괜찮다고 말한다.
      expect(calorieProgress.color, OnCareBrand.trainer.primary);
      for (final String label in <String>['탄수화물', '단백질', '지방']) {
        expect(
          find.byKey(Key('client-nutrition-macro-$label')),
          findsOneWidget,
          reason: label,
        );
      }
      Finder inMacro(String label, String text) => find.descendant(
        of: find.byKey(Key('client-nutrition-macro-$label')),
        matching: find.textContaining(text),
      );
      expect(inMacro('탄수화물', '111.6'), findsOneWidget);
      expect(inMacro('단백질', '54.4'), findsOneWidget);
      expect(inMacro('지방', '34.1'), findsOneWidget);

      // 헤더의 경고 배지는 그대로다 — 카드에서 내린 것은 막대뿐이다.
      expect(find.text('나트륨 초과'), findsOneWidget);
      // 나트륨·당류 막대는 없다 — 회원 앱 `오늘` 카드와 같다(회원 앱 #1986,
      // #2156). 그 자리에 탄·단·지 진행 바가 선다.
      expect(
        find.byKey(const Key('client-nutrition-mineral-나트륨')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('client-nutrition-mineral-당류')),
        findsNothing,
      );
      for (final String label in <String>['탄수화물', '단백질', '지방']) {
        expect(
          find.byKey(Key('client-nutrition-macro-progress-$label')),
          findsOneWidget,
          reason: label,
        );
      }
      // The detail header plus the 7-day trend card push every meal card
      // down, so reach them by scrolling.
      await tester.scrollUntilVisible(
        find.text('아침'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('아침'), findsOneWidget);
      // 음식은 이제 **한 줄씩** 이름과 영양을 함께 적는다 (#1166) — 회원 앱
      // 끼니 카드와 같다. 예전에는 이름을 쉼표로 이어 붙인 한 줄뿐이었다.
      expect(find.text('스크램블 에그'), findsOneWidget);
      expect(find.text('딸기'), findsOneWidget);
      // 위 영양 요약 카드에도 '오늘 섭취 칼로리' 가 있어 전체 트리를 뒤지면
      // 끼니 카드의 칼로리가 사라져도 통과한다 — 아침 카드 범위로 좁힌다.
      expect(
        find.descendant(
          of: mealCardFinder('아침'),
          matching: find.textContaining('칼로리', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.text('탄수화물 10.4g · 단백질 16g · 지방 14.8g'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('점심'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('점심'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('간식'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('간식'), findsOneWidget);
      // Over-target AI comment (4657 − 2000 = 2657mg) — last list item,
      // built lazily, so scroll it into view first.
      await tester.scrollUntilVisible(
        find.textContaining('나트륨이 목표치를 2657mg 초과했어요'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.textContaining('나트륨이 목표치를 2657mg 초과했어요'), findsOneWidget);
    });

    testWidgets('목표를 넘긴 날은 링을 채우되 100%라고 적지 않는다 (#820)', (tester) async {
      // 강서연은 2,260 / 2,000 kcal 로 목표를 넘겼다.
      await openDiet(tester, '강서연');

      final ring = tester.widget<NutritionCalorieRing>(
        find.byKey(const Key('client-nutrition-calorie-progress')),
      );
      // 링은 한 바퀴에서 멈춘다 — 넘긴 양은 링이 그릴 수 없다.
      expect(ring.value, 1.0);
      // 숫자는 자르지 않는다. '100%' 는 바로 아래 '목표보다 260 kcal 넘었어요'
      // 와 정면으로 어긋난다.
      expect(find.text('113%'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('거른 끼니는 카드 없이 다음 끼니부터 선다 (#1381)', (tester) async {
      // 강서연은 아침을 걸렀다 — `거름` 카드가 아니라 점심 카드부터다.
      await openDiet(tester, '강서연');

      await tester.scrollUntilVisible(
        find.text('점심'),
        150,
        scrollable: detailScrollable('seed-client-6'),
      );
      expect(find.text('아직 기록된 식단이 없어요'), findsNothing);
      expect(find.text('거름'), findsNothing);
      expect(find.text('아침'), findsNothing);
      // 음식은 한 줄에 하나, 그 옆에 회색 글씨로 kcal · mg · g.
      expect(find.text('치킨'), findsOneWidget);
      expect(find.text('맥주'), findsOneWidget);
      expect(find.text('치킨, 맥주'), findsNothing);
      expect(find.text('960kcal · 870mg · 48g'), findsOneWidget);
    });

    testWidgets('macro values wrap without overflow on a narrow screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await openDiet(tester, '김민수');
      await tester.scrollUntilVisible(
        find.byKey(const Key('client-nutrition-summary-card')),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a client with no logged meals gets a hint, not a verdict', (
      tester,
    ) async {
      // 임도현 has not recorded anything yet. The tiles read 0 either
      // way, so without this the tab silently praised a blank day.
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail(seedClientIds['임도현']!, section: 'diet'),
      );

      await tester.scrollUntilVisible(
        find.text('아직 기록된 식단이 없어요'),
        150,
        scrollable: detailScrollable('seed-client-7'),
      );
      expect(find.text('아직 기록된 식단이 없어요'), findsOneWidget);
      expect(find.textContaining('균형이 잘 맞아요'), findsNothing);
      expect(find.textContaining('나트륨이 목표치를'), findsNothing);
      // The trend card is skipped too — there is no series to draw.
      expect(find.text('최근 7일 나트륨 추이'), findsNothing);
    });

    testWidgets('AI 코멘트가 기간을 따라 바뀐다 (#1017)', (tester) async {
      // 오늘 하루만 보고 쓴 문장을 이번 주 그래프 아래 그대로 두면, 화면과
      // 조언이 서로 다른 기간을 말한다.
      //
      // 평일(목요일)로 고정한다. 주말에 돌리면 이번 주 문장이 `넘은 날 수` 가
      // 아니라 `주말에 나트륨이 올라요` 분기로 먼저 빠져, 코드를 건드리지 않아도
      // 토·일에만 깨졌다(#2090 에서 토요일에 드러났다).
      final container = await openDiet(
        tester,
        '김민수',
        seedClock: DateTime(2026, 8, 13, 10),
      );
      await tester.scrollUntilVisible(
        find.textContaining('나트륨이 목표치를'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );

      await tester.tap(_periodSegment('이번 주'));
      await tester.pumpAndSettle();

      // 이번 주 며칠이 넘었는지는 실행한 요일마다 달라진다 — 시드가 오늘까지만
      // 채우기 때문이다(#826 과 같은 종류). 고정된 "2일" 을 기대하면 코드를
      // 건드리지 않아도 요일에 따라 깨진다. `sodiumOverDays` 는 위젯이 읽는
      // 것과 같은 이번 주 계열에서 나온 값이라, 실행한 날과 무관하게 맞는
      // 문장을 고를 수 있다.
      final minsu = container
          .read(clientsProvider)
          .value!
          .firstWhere((c) => c.id == 'seed-client-1');
      final over = minsu.sodiumOverDays;
      final expectedText = over >= 3
          ? '이번 주 $over일이나 나트륨을 넘겼어요'
          : over > 0
          ? '이번 주 $over일만 권장량을 넘었어요'
          : '나트륨을 권장량 안에서 지켰어요';

      // 오늘 문장은 사라지고, 그 자리에 이번 주를 읽은 문장이 온다.
      expect(find.textContaining('나트륨이 목표치를'), findsNothing);
      expect(find.textContaining(expectedText), findsOneWidget);
    });

    testWidgets('AI 카드 제목이 기간을 말한다 (#1025)', (tester) async {
      // `오늘` 과 `이번 주` 가 같은 제목이면, 카드가 무엇을 두고 한 말인지
      // 문장을 다 읽어야만 알 수 있다.
      //
      // `전체` 는 여기서 확인하지 않는다 — 날짜별 기록이 열두 주치라 조언
      // 카드까지 끌어내리는 사이 기간 토글이 화면 밖으로 나가, 검증이 아니라
      // 스크롤을 시험하게 된다. 세 기간의 제목은 아래 `titleOf` 로 함께 본다.
      await openDiet(tester, '김민수');
      await tester.scrollUntilVisible(
        find.text('AI 분석'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('AI 분석'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('diet-ai-analysis')))
            .dy,
        lessThan(tester.getTopLeft(mealCardFinder('아침')).dy),
      );

      await tester.tap(_periodSegment('이번 주'));
      await tester.pumpAndSettle();
      // 기간을 바꾸면 그래프 카드 아래에 날짜별 기록이 붙어 AI 카드가 화면
      // 밖으로 내려간다 — 목록이 게으르게 만들어지므로 다시 끌어올린다.
      await tester.scrollUntilVisible(
        find.text('AI 기간 분석'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('AI 기간 분석'), findsOneWidget);
      expect(find.text('AI 분석'), findsNothing);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('diet-ai-analysis')))
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('diet-daily-records')),
              )
              .dy,
        ),
      );
    });

    testWidgets('세 기간의 AI 카드 제목이 서로 다르다 (#1025)', (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) {
              l = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final List<String> titles = <String>[
        for (final ClientPeriod p in ClientPeriod.values)
          ClientAiAnalysisCard.titleOf(l, p),
      ];
      expect(titles, <String>['AI 분석', 'AI 기간 분석', 'AI 전체 분석']);
      expect(titles.toSet(), hasLength(3));
    });

    testWidgets('날짜 줄을 누르면 그날 기록이 펼쳐진다 (#1025)', (tester) async {
      // 그래프는 "얼마나" 만 말한다. 그날 무엇을 먹었는지는 줄을 눌러야 나온다.
      await openDiet(tester, '김민수');
      await tester.tap(_periodSegment('이번 주'));
      await tester.pumpAndSettle();

      final Finder records = find.byKey(
        const ValueKey<String>('diet-daily-records'),
      );
      await tester.scrollUntilVisible(
        records,
        150,
        scrollable: detailScrollable('seed-client-1'),
      );

      // 화살표가 있는 줄만 펼칠 수 있다 — 기록이 없는 날은 펼칠 것이 없다.
      expect(find.text('탄단지'), findsNothing);
      final Finder openable = find.descendant(
        of: records,
        matching: find.byIcon(Icons.expand_more_rounded),
      );
      expect(openable, findsWidgets);
      await tester.ensureVisible(openable.first);
      await tester.pumpAndSettle();
      final Finder row = find
          .ancestor(of: openable.first, matching: find.byType(InkWell))
          .first;
      await tester.tap(row);
      await tester.pumpAndSettle();

      // 펼친 줄에는 그날의 항목이 이름표와 값을 한 알약에 담아 선다.
      // 이 목록 안에서만 찾는다 — 위 영양 요약 카드에도 같은 낱말이 있다.
      Finder pill(String label) => find.descendant(
        of: records,
        matching: find.textContaining(label, findRichText: true),
      );
      expect(pill('칼로리'), findsWidgets);
      expect(pill('나트륨'), findsWidgets);
    });

    testWidgets('좁은 화면·큰 글씨에서도 날짜 줄이 넘치지 않는다 (#1025)', (tester) async {
      // 날짜 칸의 폭이 고정이라 글씨 배율이 커지면 가장 먼저 깨질 자리다.
      // 480 폭은 분할 패널의 좁은 쪽, 1.3 배는 접근성 검사(#1004)가 쓰는 값이다.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openDiet(tester, '김민수');
      await tester.tap(_periodSegment('이번 주'));
      await tester.pumpAndSettle();

      final Finder records = find.byKey(
        const ValueKey<String>('diet-daily-records'),
      );
      await tester.scrollUntilVisible(
        records,
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      final Finder openable = find.descendant(
        of: records,
        matching: find.byIcon(Icons.expand_more_rounded),
      );
      await tester.ensureVisible(openable.first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(of: openable.first, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('이지수 (sodium under target) shows the balanced AI comment', (
      tester,
    ) async {
      await openDiet(tester, '이지수');

      // The detail header sits above the list, so her 아침 card can start
      // below the fold on the test viewport.
      await tester.scrollUntilVisible(
        find.text('그릭요거트'),
        150,
        scrollable: detailScrollable('seed-client-2'),
      );
      expect(find.text('그릭요거트'), findsOneWidget);
      // Under target in the diet summary.
      expect(find.text('mg 초과'), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('오늘 식단은 균형이 잘 맞아요'),
        150,
        scrollable: detailScrollable('seed-client-2'),
      );
      expect(find.textContaining('오늘 식단은 균형이 잘 맞아요'), findsOneWidget);
    });
  });
}

/// 기간 토글에서 [label] 칸. 세그먼트는 칸마다 키가 없어 토글 안의 글자로 찾는다.
Finder _periodSegment(String label) => find.descendant(
  of: find.byKey(const ValueKey<String>('client-period-toggle')),
  matching: find.text(label),
);
