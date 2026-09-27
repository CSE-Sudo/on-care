/// 회원 상세 `식단` 탭의 끼니 카드 — 회원 앱과 같은 말로 읽힌다. (#2333, #2087)
///
/// 회원 앱은 음식명 옆 내용량(#1964), `총 칼로리`(#1848), 시각 없는 아침→야식
/// 순서(#1989)로 바뀌었다. 트레이너 카드는 상세 화면이 따로 없어 합계까지 든다
/// — `총 칼로리` 옆 탄단지 비중과 막대, 오른쪽 당류·나트륨. 끼니가 회원 하루
/// 목표의 절반을 넘기면 그 영양을 가장 많이 보탠 음식을 짚는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
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
    // 음식 kcal 은 오른쪽 끝, 합계는 `총 칼로리` 줄.
    expect(
      find.descendant(of: card, matching: find.text('310 kcal')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('330 kcal')),
      findsOneWidget,
    );
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
      Color? colorOf(Finder card, String part) {
        final Text text = find
            .descendant(
              of: find.descendant(
                of: card,
                matching: find.byWidgetPredicate(
                  (Widget w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(
                        'client-diet-extras-',
                      ),
                ),
              ),
              matching: find.byType(Text),
            )
            .evaluate()
            .map((Element e) => e.widget as Text)
            .firstWhere((Text t) => (t.data ?? '').startsWith(part));
        return text.style?.color;
      }

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
    expect(find.text('총 칼로리'), findsWidgets);
    expect(tester.takeException(), isNull);
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
      matching: find.byIcon(Icons.expand_more_rounded),
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
