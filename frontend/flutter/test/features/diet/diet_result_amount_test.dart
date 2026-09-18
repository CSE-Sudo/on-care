/// 사진 분석 완료 시트의 끼니 내용량 (#1964).
///
/// 영양 분석 결과의 여섯 값은 모두 음식별 양을 재고 나온 값이다(#1876). 식단
/// 수정의 음식 칸이 `내용량` 을 칼로리 위에 두는 것처럼, 분석 결과도 그 기준을
/// 칼로리보다 먼저 보인다. 양을 모르는 음식이 섞이면 합을 낼 수 없어 적지 않는다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

final Uint8List _jpegBytes = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

class _FixedPicker implements MealPhotoPicker {
  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async =>
      MealPhoto.fromBytes(_jpegBytes)!;
}

Map<String, Object?> _food(String name, int kcal, {num? amountG}) =>
    <String, Object?>{
      'name': name,
      'calories': kcal,
      'sodium_mg': 10,
      'sugar_g': 1,
      'source': 'db',
      'amount_g': ?amountG,
    };

/// 분석이 돌려줄 음식을 정해 두는 대역. 저장·조회는 [FakeDietRepository] 그대로다.
class _AnalyzeWith extends FakeDietRepository {
  _AnalyzeWith(this.foods);

  final List<Map<String, Object?>> foods;

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
  }) async {
    final DietAnalysisResult base = await super.analyze(
      photo: photo,
      mealType: mealType,
      idempotencyKey: idempotencyKey,
    );
    final List<RecognizedFood> parsed = foods
        .map(RecognizedFood.fromJson)
        .toList();
    return DietAnalysisResult(
      entryId: base.entryId,
      foods: parsed,
      totalCalories: parsed.fold<int>(
        0,
        (int sum, RecognizedFood f) => sum + f.calories,
      ),
      totalSodiumMg: 20,
      totalSugarG: 2,
      coachComment: '',
      timeLabel: base.timeLabel,
    );
  }
}

Future<void> _openResult(WidgetTester tester, FakeDietRepository repo) async {
  useFixedKstDate(DateTime(2026, 9, 18, 9));
  await tester.binding.setSurfaceSize(const Size(500, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
        dietRepositoryProvider.overrideWithValue(repo),
        sessionFeatureResetOverride(),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDietAddSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('사진 찍기'));
  await tester.pumpAndSettle();
}

Finder get _amountRow => find.byKey(const Key('diet-result-amount'));

void main() {
  group('RecognizedFood.amountG', () {
    test('amount_g 를 읽는다', () {
      expect(
        RecognizedFood.fromJson(_food('현미밥', 310, amountG: 210)).amountG,
        210,
      );
    });

    test('키가 없거나 0 이하면 null 이다 — 모른다와 0g 은 다른 말이다', () {
      expect(RecognizedFood.fromJson(_food('김', 20)).amountG, isNull);
      expect(
        RecognizedFood.fromJson(_food('김', 20, amountG: 0)).amountG,
        isNull,
      );
    });
  });

  group('DietAnalysisResult.totalAmountG', () {
    DietAnalysisResult resultOf(List<Map<String, Object?>> foods) =>
        DietAnalysisResult(
          entryId: 'e',
          foods: foods.map(RecognizedFood.fromJson).toList(),
          totalCalories: 0,
          totalSodiumMg: 0,
          totalSugarG: 0,
          coachComment: '',
        );

    test('모든 음식의 양을 알면 그 합이다', () {
      expect(
        resultOf(<Map<String, Object?>>[
          _food('스크램블 에그', 185, amountG: 100),
          _food('딸기', 32, amountG: 150),
        ]).totalAmountG,
        250,
      );
    });

    test('하나라도 모르면 null 이다 — 아는 것만 더하면 덜 먹은 것처럼 읽힌다', () {
      expect(
        resultOf(<Map<String, Object?>>[
          _food('스크램블 에그', 185, amountG: 100),
          _food('딸기', 32),
        ]).totalAmountG,
        isNull,
      );
    });
  });

  group('분석 완료 시트', () {
    testWidgets('내용량이 칼로리 위에 끼니 합으로 적힌다', (WidgetTester tester) async {
      await _openResult(
        tester,
        _AnalyzeWith(<Map<String, Object?>>[
          _food('스크램블 에그', 185, amountG: 100),
          _food('딸기', 32, amountG: 150),
        ]),
      );

      expect(_amountRow, findsOneWidget);
      expect(
        find.descendant(of: _amountRow, matching: find.text('내용량')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _amountRow, matching: find.text('250')),
        findsOneWidget,
      );
      // 아래 값들의 기준이므로 칼로리보다 위에 선다 — 식단 수정의 음식 칸과 같다.
      expect(
        tester.getTopLeft(_amountRow).dy,
        lessThan(tester.getTopLeft(find.text('칼로리')).dy),
      );
    });

    testWidgets('양을 모르는 음식이 섞이면 내용량을 적지 않는다', (WidgetTester tester) async {
      await _openResult(
        tester,
        _AnalyzeWith(<Map<String, Object?>>[
          _food('스크램블 에그', 185, amountG: 100),
          _food('딸기', 32),
        ]),
      );

      expect(_amountRow, findsNothing);
      expect(find.text('칼로리'), findsOneWidget, reason: '나머지 값은 그대로 보인다');
    });
  });
}
