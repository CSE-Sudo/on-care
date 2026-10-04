/// 칼로리를 모르는 음식이 섞인 날의 식단 조회.
///
/// 사진 인식이 칼로리를 읽지 못한 음식은 서버에 `calories: null` 로 남고, 옛
/// 문자열 항목은 칼로리 키 자체가 없다(#724). 예전에는 앱이 칼로리를 null
/// 단언으로 읽어서 이런 줄이 하나만 섞여도 그날 식단 전체의 파싱이 실패했고,
/// 식단 탭이 오류 화면이 됐다. 지금은 모르는 칼로리를 0 kcal 로 센다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';

/// 칼로리 모름·키 없음·정상 값이 한 끼니에 섞이고, 끼니·하루 합계도 null 인 응답.
Map<String, Object?> _dayJson() => <String, Object?>{
  'entries': <Object?>[
    <String, Object?>{
      'id': 'diet-lunch',
      'meal_type': 'lunch',
      'time_label': '12:40',
      'foods': <Object?>[
        <String, Object?>{
          'name': '김치찌개',
          'calories': null,
          'source': 'estimate',
        },
        <String, Object?>{'name': '현미밥', 'calories': 300, 'source': 'db'},
        <String, Object?>{'name': '나물무침'},
      ],
      'total_calories': null,
      'sodium_mg': 900,
      'sugar_g': 4,
    },
    <String, Object?>{
      'id': 'diet-dinner',
      'meal_type': 'dinner',
      'time_label': '19:00',
      'foods': <Object?>[
        <String, Object?>{'name': '된장국', 'calories': 120},
      ],
      'total_calories': 120,
      'sodium_mg': 700,
      'sugar_g': 2,
    },
  ],
  'total_calories': null,
  'total_sodium_mg': 1600,
  'total_sugar_g': 6,
  'ai_coach_message': '',
};

/// 위 응답을 실제 파서로 읽어 돌려주는 대역 — 화면이 파싱 결과를 그대로 받는다.
class _UnknownCalorieDay extends FakeDietRepository {
  @override
  Future<DietDay> fetchToday() async => DietDay.fromJson(_dayJson());

  @override
  Future<DietDay> fetchByDate(DateTime date) async =>
      DietDay.fromJson(_dayJson());
}

void main() {
  group('kcalOf', () {
    test('없음·null·숫자가 아닌 값은 0 이다', () {
      expect(kcalOf(null), 0);
      expect(kcalOf('많이'), 0);
      expect(kcalOf(<String, Object?>{}), 0);
      expect(kcalOf(true), 0);
    });

    test('숫자는 정수로 반올림하고, 숫자 문자열도 읽는다', () {
      expect(kcalOf(285), 285);
      expect(kcalOf(249.6), 250);
      expect(kcalOf('180'), 180);
      expect(kcalOf(' 75.4 '), 75);
    });

    test('음수·무한대·NaN 은 0 으로 접는다', () {
      expect(kcalOf(-30), 0);
      expect(kcalOf(double.infinity), 0);
      expect(kcalOf(double.nan), 0);
    });
  });

  group('FoodItem.fromJson', () {
    test('calories 가 null 이면 0 kcal 이다', () {
      final FoodItem f = FoodItem.fromJson(<String, Object?>{
        'name': '김치찌개',
        'calories': null,
      });
      expect(f.name, '김치찌개');
      expect(f.calories, 0);
    });

    test('calories 키가 없어도 파싱된다', () {
      expect(FoodItem.fromJson(<String, Object?>{'name': '나물'}).calories, 0);
    });

    test('정상 값은 그대로다', () {
      expect(
        FoodItem.fromJson(<String, Object?>{
          'name': '현미밥',
          'calories': 300,
        }).calories,
        300,
      );
    });
  });

  group('DietDay.fromJson', () {
    test('칼로리 모르는 음식이 섞인 하루가 예외 없이 파싱된다', () {
      final DietDay day = DietDay.fromJson(_dayJson());

      expect(day.entries, hasLength(2));
      final DietEntry lunch = day.entries.first;
      expect(lunch.foods.map((FoodItem f) => f.calories), <int>[0, 300, 0]);
      expect(lunch.totalCalories, 0);
      expect(day.totalCalories, 0);
    });

    test('모르는 칼로리는 0 kcal 로 하루 합계에 들어간다', () {
      final DietDay day = DietDay.fromJson(_dayJson());

      // 음식 합(0 + 300 + 0 + 120)이 서버 합계(null → 0)보다 우선한다.
      expect(day.effectiveCalories, 420);
      expect(day.effectiveSodiumMg, 1600);
    });

    test('하루 합계 칸들이 비어 있어도 파싱된다', () {
      final DietDay day = DietDay.fromJson(<String, Object?>{
        'entries': <Object?>[],
        'total_calories': null,
        'total_sodium_mg': null,
        'total_sugar_g': null,
        'ai_coach_message': null,
      });
      expect(day.entries, isEmpty);
      expect(day.totalCalories, 0);
      expect(day.totalSodiumMg, 0);
      expect(day.totalSugarG, 0);
      expect(day.aiCoachMessage, '');
    });

    test('Dio 저장소도 같은 응답을 읽는다', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions o, RequestInterceptorHandler h) {
            h.resolve(
              Response<Map<String, Object?>>(
                requestOptions: o,
                statusCode: 200,
                data: _dayJson(),
              ),
            );
          },
        ),
      );

      final DietDay day = await DioDietRepository(
        dio,
      ).fetchByDate(DateTime(2026, 10, 5));
      expect(day.entries.first.foods, hasLength(3));
      expect(day.effectiveCalories, 420);
    });
  });

  testWidgets('칼로리 모르는 음식이 있는 날에도 식단 탭이 오류가 아니라 목록을 보인다', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(_UnknownCalorieDay()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DietRecordPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorState), findsNothing);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DietRecordPage)),
    );
    expect(find.text(l.dietMealLunch), findsWidgets);
    expect(find.text(l.dietMealDinner), findsWidgets);
    expect(find.textContaining('김치찌개'), findsWidgets);
  });
}
