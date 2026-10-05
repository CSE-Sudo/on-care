/// 회원 상세 `식단` 탭의 끼니 카드 — 회원 앱과 같은 말로 읽힌다. (#2333, #2087)
///
/// 회원 앱은 음식명 옆 내용량(#1964), `총 칼로리`(#1848), 시각 없는 아침→야식
/// 순서(#1989)로 바뀌었다. 트레이너 카드는 상세 화면이 따로 없어 합계까지 든다
/// — 탄단지 비중·당류·나트륨 네 칸 오른쪽 끝에 `총 … kcal`. 끼니가 회원 하루
/// 목표의 절반을 넘기면 그 영양을 가장 많이 보탠 음식을 짚는다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/diet_view.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 오늘 끼니를 [meals] 로 바꿔 끼우는 저장소 — 나머지(로스터·요약)는 시드다.
class _TodayMealsRepository extends DriftClientRepository {
  _TodayMealsRepository(super.db, this.meals);

  final List<ClientDietEntry> meals;

  @override
  Stream<List<ClientDietEntry>> watchDiet(String clientId) =>
      Stream<List<ClientDietEntry>>.value(meals);
}

ClientDietEntry _meal(String id, String meal) => ClientDietEntry(
  id: id,
  meal: meal,
  items: '밥',
  calories: 300,
  sodiumMg: 10,
  carbsG: 60,
  proteinG: 6,
  fatG: 2,
  foods: const <ClientDietFood>[ClientDietFood(name: '밥', calories: 300)],
);

Finder _mealCard(String id) => find.byKey(ValueKey<String>('diet-meal-$id'));

Finder _flags(Finder card) => find.descendant(
  of: card,
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('client-diet-food-flag-'),
  ),
);

/// [card] 안에서 [text] 를 적은 [AppTag] 의 음식 줄 이름.
bool _flagBeside(WidgetTester tester, Finder card, String food, String text) {
  final Finder line = find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate(
      (Widget w) => w.runtimeType.toString() == '_FoodLine',
    ),
  );
  if (line.evaluate().isEmpty) return false;
  return find
      .descendant(
        of: line.first,
        matching: find.textContaining(food, findRichText: true),
      )
      .evaluate()
      .isNotEmpty;
}

Future<void> _open(
  WidgetTester tester, {
  String clientId = 'seed-client-6',
  List<ClientDietEntry>? meals,
  MemberHealthProfile? profile,
  Size size = const Size(1400, 2400),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.clientDetail(clientId, section: 'diet'),
    extraOverrides: <Override>[
      if (meals != null)
        clientRepositoryProvider.overrideWith(
          (ref) => _TodayMealsRepository(ref.watch(appDatabaseProvider), meals),
        ),
      if (profile != null)
        memberHealthProfileProvider.overrideWith((ref, id) async => profile),
    ],
  );
  await tester.pumpAndSettle();
}

/// 실제 서체를 싣는다. 테스트 기본 서체는 모든 글자를 정사각형으로 그려 폭이
/// 부풀려진다 — 당류를 한 줄에 둘지 가르는 폭 셈을 실제 폭으로 봐야 한다.
Future<void> _loadFonts() async {
  final FontLoader loader = FontLoader('Pretendard');
  for (final String w in <String>['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final Uint8List b = File(
      'assets/fonts/Pretendard-$w.otf',
    ).readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.view(b.buffer)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadFonts);

  // 회원이 **얼마나** 먹었는지는 코칭의 기본 단위다. 백엔드는 `foods_json` 을
  // 그대로 흘려 보내 `amount_g` 가 이미 응답에 실려 있었는데, 엔티티가 그 키를
  // 읽지 않아 트레이너 화면까지 오지 못했다 (#2087).
  group('ClientDietFood.amountG', () {
    test('amount_g 를 읽는다', () {
      final ClientDietFood food = ClientDietFood.fromJson(<String, Object?>{
        'name': '현미밥',
        'amount_g': 210,
        'calories': 310,
      });
      expect(food.amountG, 210);
    });

    test('키가 없거나 0 이하면 null 이다 — 모른다와 0g 은 다른 말이다', () {
      expect(
        ClientDietFood.fromJson(<String, Object?>{'name': '김'}).amountG,
        isNull,
      );
      expect(
        ClientDietFood.fromJson(<String, Object?>{
          'name': '김',
          'amount_g': 0,
        }).amountG,
        isNull,
      );
    });
  });

  testWidgets('음식 이름 옆에 내용량을 적고, 모르는 음식에는 적지 않는다', (tester) async {
    await _open(
      tester,
      meals: const <ClientDietEntry>[
        ClientDietEntry(
          id: 'amount-breakfast',
          meal: '아침',
          items: '현미밥, 김',
          calories: 330,
          sodiumMg: 105,
          sugarG: 0.9,
          carbsG: 70,
          proteinG: 7,
          fatG: 2,
          foods: <ClientDietFood>[
            ClientDietFood(
              name: '현미밥',
              amountG: 210,
              calories: 310,
              sodiumMg: 5,
              sugarG: 0.4,
            ),
            // 서버가 양을 얻지 못한 음식 — 이 필드 이전 기록도 이렇게 온다.
            ClientDietFood(name: '김', calories: 20, sodiumMg: 100, sugarG: 0.5),
          ],
        ),
      ],
    );

    final Finder card = _mealCard('amount-breakfast');
    expect(
      find.descendant(
        of: card,
        matching: find.text('현미밥  210g', findRichText: true),
      ),
      findsOneWidget,
    );
    // 양을 모르는 음식은 이름만 — `0g` 을 적으면 안 먹었다는 말이 된다.
    expect(
      find.descendant(of: card, matching: find.text('김', findRichText: true)),
      findsOneWidget,
    );
    // 음식 kcal 은 오른쪽 끝, 합계는 네 칸 오른쪽 끝에 `총` 을 붙여 선다 —
    // `총 칼로리` 라벨 줄은 따로 두지 않는다.
    expect(
      find.descendant(of: card, matching: find.text('310kcal')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('총 330kcal')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('총 칼로리')),
      findsNothing,
    );
  });

  group('끼니 합계 자리', () {
    Finder total(String id) =>
        find.byKey(ValueKey<String>('client-diet-total-$id'));
    Finder sodium(String id) =>
        find.byKey(ValueKey<String>('client-diet-sodium-$id'));

    testWidgets('폭이 넉넉하면 네 칸 옆, 나트륨 값 줄에 선다', (tester) async {
      await _open(
        tester,
        meals: <ClientDietEntry>[_meal('wide', '아침')],
        size: const Size(1600, 2400),
      );

      expect(
        (tester.getCenter(total('wide')).dy -
                tester.getCenter(sodium('wide')).dy)
            .abs(),
        lessThan(4),
      );
      expect(
        tester.getTopLeft(total('wide')).dx,
        greaterThan(tester.getTopRight(sodium('wide')).dx),
      );
      // 옆자리를 내줘도 당류는 탄수화물 g 값 옆 한 줄에 남는다.
      expect(
        (tester
                    .getCenter(
                      find.byKey(
                        const ValueKey<String>('client-diet-sugar-wide'),
                      ),
                    )
                    .dy -
                tester.getCenter(sodium('wide')).dy)
            .abs(),
        lessThan(4),
      );
    });

    testWidgets('옆에 두면 당류가 밀리는 폭에서는 네 칸 위 한 줄로 오른다', (tester) async {
      await _open(
        tester,
        // 시드 강서연 점심(짬뽕)과 같은 값 — `95.1g 당류 8.6g` 은 합계에
        // 옆자리를 내주면 탄수화물 칸에 한 줄로 들지 않는다.
        meals: const <ClientDietEntry>[
          ClientDietEntry(
            id: 'split',
            meal: '점심',
            items: '짬뽕',
            calories: 707,
            sodiumMg: 300,
            carbsG: 95.1,
            proteinG: 35.4,
            fatG: 12.7,
            sugarG: 8.6,
            // 사진 칸만큼 줄 폭이 좁아진다 — 오늘 탭의 실제 카드 폭.
            photoAsset: 'assets/demo/images/diet-vegetable-bibimbap.jpg',
            foods: <ClientDietFood>[ClientDietFood(name: '짬뽕', calories: 707)],
          ),
        ],
        size: const Size(1100, 2400),
      );

      expect(
        tester.getBottomLeft(total('split')).dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey<String>('client-diet-nutrients-split'),
                ),
              )
              .dy,
        ),
      );
      expect(find.text('총 칼로리'), findsNothing);
    });
  });

  testWidgets('끼니는 아침·점심·저녁·간식·야식 순이다 — 저장 순서가 아니다', (tester) async {
    // 서버는 저장 순서로 준다 — 어제 저녁 사진을 오늘 아침에 올리면 저녁이
    // 먼저 온다. 같은 끼니(간식 둘)끼리는 받은 순서를 지킨다.
    await _open(
      tester,
      meals: <ClientDietEntry>[
        _meal('dinner', '저녁'),
        _meal('snack-1', '간식'),
        _meal('late', '야식'),
        _meal('breakfast', '아침'),
        _meal('snack-2', '간식'),
        _meal('lunch', '점심'),
      ],
    );

    final List<String> order = <String>[
      'breakfast',
      'lunch',
      'dinner',
      'snack-1',
      'snack-2',
      'late',
    ];
    for (int i = 1; i < order.length; i++) {
      expect(
        tester.getTopLeft(_mealCard(order[i - 1])).dy,
        lessThan(tester.getTopLeft(_mealCard(order[i])).dy),
        reason: '${order[i - 1]} 가 ${order[i]} 보다 위여야 한다',
      );
    }
  });

  group('과다 짚기 — 회원 하루 목표의 절반', () {
    testWidgets('나트륨·당류를 넘긴 끼니는 가장 많이 보탠 음식을 짚는다', (tester) async {
      // 강서연(시드): 점심 마라탕 1,850mg — 나트륨 목표 2,000mg 의 절반을 넘는다.
      // 저녁 치킨·맥주 당류 56g — 당류 목표 50g 의 절반(25g)을 넘고, 그중
      // 치킨(48g)이 가장 많이 보탰다. 저녁 나트륨 900mg 은 선 아래다.
      await _open(tester);

      final Finder lunch = find.ancestor(
        of: find.text('점심'),
        matching: find.byType(AppCard),
      );
      final Finder dinner = find.ancestor(
        of: find.text('저녁'),
        matching: find.byType(AppCard),
      );
      expect(_flags(lunch.first), findsOneWidget);
      expect(_flagBeside(tester, lunch.first, '마라탕', '나트륨 1,850mg'), isTrue);
      expect(_flags(dinner.first), findsOneWidget);
      expect(_flagBeside(tester, dinner.first, '치킨', '당류 48g'), isTrue);

      // 합계 줄의 넘긴 값만 빨강이다.
      // 세부 줄의 항목 하나(`당류 56g · `)의 글자색.
      // 합계 칸의 당류(`당류 56g`)·나트륨 값(`900mg`) 글자색.
      Color? colorOf(Finder card, String part) => tester
          .widget<Text>(
            find.descendant(
              of: card,
              matching: find.byWidgetPredicate(
                (Widget w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      part == '당류'
                          ? 'client-diet-sugar-'
                          : 'client-diet-sodium-',
                    ),
              ),
            ),
          )
          .style
          ?.color;

      expect(colorOf(dinner.first, '당류'), OnCareColors.danger);
      expect(colorOf(dinner.first, '나트륨'), isNot(OnCareColors.danger));
      expect(colorOf(lunch.first, '나트륨'), OnCareColors.danger);
    });

    testWidgets('기준은 회원이 정한 목표를 따라간다', (tester) async {
      // 목표를 넉넉히 잡은 회원 — 나트륨 4,000mg(절반 2,000) · 당류 120g
      // (절반 60) 이면 같은 끼니라도 짚을 것이 없다.
      await _open(
        tester,
        profile: const MemberHealthProfile(
          memberId: 'seed-client-6',
          memberName: '강서연',
          dailySodiumMg: 4000,
          dailySugarG: 120,
        ),
      );

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'client-diet-food-flag-',
              ),
        ),
        findsNothing,
      );
    });

    test('선은 하루 목표의 절반이고, 목표가 없으면 회원 앱 기본값이다', () {
      final MealLimits defaults = mealLimitsOf(null);
      expect(defaults.sodiumMg, 1000);
      expect(defaults.sugarG, 25);

      final MealLimits own = mealLimitsOf(
        const MemberHealthProfile(
          memberId: 'm',
          memberName: 'm',
          dailySodiumMg: 1800,
          dailySugarG: 30,
        ),
      );
      expect(own.sodiumMg, 900);
      expect(own.sugarG, 15);
    });
  });

  // 당류는 탄수화물의 일부라 그 칸 안에 적는다. 폭이 넉넉하면 g 값 오른쪽 한
  // 줄에, 칸이 좁아 그 한 줄이 줄어들 만큼이면 아래 줄로 내린다 — 한 줄로 두면
  // 좁은 폭에서 두 값이 함께 읽을 수 없을 만큼 작아졌다.
  for (final (String label, Size size, bool inline) in <(String, Size, bool)>[
    ('넓은 화면에서는 탄수화물 값 오른쪽', const Size(1400, 2400), true),
    ('좁은 폭에서는 탄수화물 값 아래 줄', const Size(480, 2400), false),
  ]) {
    testWidgets('당류 자리 — $label', (tester) async {
      await _open(tester, clientId: 'seed-client-1', size: size);

      final Finder carbs = find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'client-diet-col-carbs-',
            ),
      );
      final Finder sugar = find
          .descendant(
            of: carbs.first,
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'client-diet-sugar-',
                  ),
            ),
          )
          .first;
      final Finder grams = find
          .descendant(
            of: carbs.first,
            matching: find.textContaining(RegExp(r'^[\d.]+g$')),
          )
          .first;
      final Rect s = tester.getRect(sugar);
      final Rect g = tester.getRect(grams);
      if (inline) {
        expect(s.left, greaterThan(g.right), reason: '당류가 g 값 오른쪽이 아니다');
        expect(s.top, lessThan(g.bottom), reason: '당류가 g 값과 다른 줄이다');
      } else {
        expect(
          s.top,
          greaterThanOrEqualTo(g.bottom - 1),
          reason: '당류가 아래 줄이 아니다',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('좁은 화면·큰 글씨에서도 끼니 카드가 넘치지 않는다', (tester) async {
    // 480 폭은 분할 패널의 좁은 쪽, 1.3 배는 접근성 검사(#1004)가 쓰는 값이다.
    // 긴 이름·내용량·짚는 배지 둘이 한 줄에 서는 끼니로 본다. 회원은 김민수 —
    // 강서연은 이 폭에서 머리의 신호 배지가 넘쳐(이 카드와 무관) 검사가 흐려진다.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(
      tester,
      clientId: 'seed-client-1',
      size: const Size(480, 2400),
      meals: const <ClientDietEntry>[
        ClientDietEntry(
          id: 'narrow',
          meal: '간식',
          items: '초코 케이크 한 조각, 카페라떼',
          calories: 1491,
          sodiumMg: 2181,
          sugarG: 37.4,
          carbsG: 151.4,
          proteinG: 10.1,
          fatG: 26.4,
          foods: <ClientDietFood>[
            ClientDietFood(
              name: '초코 케이크 한 조각',
              amountG: 110,
              calories: 1338,
              sodiumMg: 2121,
              sugarG: 21.6,
            ),
            ClientDietFood(
              name: '카페라떼',
              amountG: 300,
              calories: 153,
              sodiumMg: 60,
              sugarG: 15.8,
            ),
          ],
        ),
      ],
    );

    // 한 음식이 두 영양을 모두 보탰다 — 배지 둘이 한 줄에 선다.
    expect(_flags(_mealCard('narrow')), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('client-diet-total-narrow')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('이번 주에서 펼친 끼니에는 사진을 받지 않는다 — 사진은 오늘에서', (tester) async {
    // 날짜별 조회도 사진 정보를 준다. 그래도 그리지 않는다 — 사진은 끼니마다
    // 서버에서 받아 오고, 여러 날을 오가며 펼치는 자리라 받을 사진이 많다.
    // 여기서 보려는 것은 무엇을 얼마나 먹었나다.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
      extraOverrides: <Override>[
        clientDietOnProvider.overrideWith(
          (ref, key) async => const <ClientDietEntry>[
            ClientDietEntry(
              id: 'with-photo',
              meal: '아침',
              items: '오트밀',
              calories: 300,
              sodiumMg: 10,
              carbsG: 50,
              proteinG: 10,
              fatG: 5,
              photoAsset: 'assets/demo/images/diet-oatmeal-banana.jpeg',
            ),
            ClientDietEntry(
              id: 'without-photo',
              meal: '점심',
              items: '김밥',
              calories: 400,
              sodiumMg: 700,
              carbsG: 60,
              proteinG: 12,
              fatG: 10,
            ),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('client-period-toggle')),
        matching: find.text('이번 주'),
      ),
    );
    await tester.pumpAndSettle();
    final Finder records = find.byKey(
      const ValueKey<String>('diet-daily-records'),
    );
    await tester.ensureVisible(records);
    await tester.pumpAndSettle();
    final Finder openable = find.descendant(
      of: records,
      matching: find.byIcon(AppIcons.expandMore),
    );
    await tester.tap(
      find.ancestor(of: openable.first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: records, matching: find.byType(Image)),
      findsNothing,
      reason: '펼친 끼니가 사진을 받는다',
    );
    // 사진 대신 이름과 양, 끼니 kcal 이 선다.
    expect(
      find.descendant(
        of: records,
        matching: find.text('오트밀', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: records, matching: find.text('300kcal')),
      findsOneWidget,
    );
  });

  testWidgets('펼친 날 맨 위에 하루 합계가 끼니 줄과 같은 모양으로 선다', (tester) async {
    // 예전에는 알약 셋(`칼로리 … 탄수화물 · 단백질 · 지방`, `나트륨`, `당류`)
    // 이었다 — 칼로리 알약 안에 탄단지를 품고 당류를 떼어 끼니 줄과 말투가
    // 달랐다. 하루 합계의 빨강은 회원 **하루 목표**(나트륨 2,000mg)다.
    await _open(tester, clientId: 'seed-client-1');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('client-period-toggle')),
        matching: find.text('이번 주'),
      ),
    );
    await tester.pumpAndSettle();
    final Finder records = find.byKey(
      const ValueKey<String>('diet-daily-records'),
    );
    await tester.ensureVisible(records);
    await tester.pumpAndSettle();
    final Finder openable = find.descendant(
      of: records,
      matching: find.byIcon(AppIcons.expandMore),
    );
    await tester.tap(
      find.ancestor(of: openable.first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();

    final Finder total = find.byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'client-diet-day-total-',
          ),
    );
    expect(total, findsOneWidget);
    expect(
      find.descendant(of: total, matching: find.text('하루 합계')),
      findsOneWidget,
    );
    // 합계 줄은 첫 줄에 음식 이름이 없어, 영양 한 줄이 라벨과 같은 줄에
    // 선다(#2421) — 둘째 줄로 내려가면 첫 줄이 통째로 빈다.
    final Finder macros = find.descendant(
      of: total,
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'client-diet-macros-',
            ),
      ),
    );
    expect(
      (tester.getCenter(macros).dy -
              tester
                  .getCenter(
                    find.descendant(of: total, matching: find.text('하루 합계')),
                  )
                  .dy)
          .abs(),
      lessThan(4),
    );
    // 합계 kcal 은 끼니 kcal 과 같은 열에 서므로 `총` 을 붙여 가른다.
    expect(
      find.descendant(
        of: total,
        matching: find.textContaining(RegExp(r'^총 [\d,]+ kcal$')),
      ),
      findsOneWidget,
    );
    // 알약은 없다.
    expect(
      find
          .descendant(of: records, matching: find.byType(AppTag))
          .evaluate()
          .where((Element e) => (e.widget as AppTag).label.startsWith('칼로리')),
      isEmpty,
    );
    // 김민수의 오늘은 나트륨 4,657mg — 하루 목표 2,000mg 을 넘어 빨강이다.
    Color? sodiumColor;
    for (final RichText rich in tester.widgetList<RichText>(
      find.descendant(of: total, matching: find.byType(RichText)),
    )) {
      rich.text.visitChildren((InlineSpan span) {
        if (span is TextSpan && (span.text ?? '').startsWith('나트륨')) {
          sodiumColor = span.style?.color;
          return false;
        }
        return true;
      });
    }
    expect(sodiumColor, OnCareColors.danger);
  });

  testWidgets('펼친 날의 나트륨 알약에 이름이 두 번 나오지 않는다', (tester) async {
    await _open(tester, clientId: 'seed-client-1');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('client-period-toggle')),
        matching: find.text('이번 주'),
      ),
    );
    await tester.pumpAndSettle();

    final Finder records = find.byKey(
      const ValueKey<String>('diet-daily-records'),
    );
    await tester.ensureVisible(records);
    await tester.pumpAndSettle();
    final Finder openable = find.descendant(
      of: records,
      matching: find.byIcon(AppIcons.expandMore),
    );
    await tester.tap(
      find.ancestor(of: openable.first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: records,
        matching: find.textContaining('나트륨 나트륨', findRichText: true),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: records,
        matching: find.textContaining(
          RegExp(r'나트륨 [\d,]+mg'),
          findRichText: true,
        ),
      ),
      findsWidgets,
    );
  });
}
