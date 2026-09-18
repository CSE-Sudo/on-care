/// 사진 분석 완료 시트의 음식별 내용량 (#1964).
///
/// 영양 분석 결과는 모두 음식별 양을 재고 나온 값이다(#1876). 양이 틀리면
/// 칼로리·탄단지가 함께 틀리므로, 저장 전 이 시트의 `인식된 음식` 에서 음식마다
/// AI 가 읽은 양이 보여야 머리의 연필로 바로 고칠 수 있다. 식단 탭 끼니 카드·
/// 식단 상세와 같은 자리(이름 옆)·같은 모양(보조색)이다.
///
/// 끼니 **총** 내용량은 두지 않는다. 종류가 다른 음식의 그램을 더한 값은 판단할
/// 근거가 되지 못하고(음료·국물이 부풀린다), 끼니 칼로리도 그 값에서 나오지 않는다.
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

/// `인식된 음식` 줄이 실제로 읽히는 글자.
String _recognized(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('diet-result-recognized-foods')))
    .textSpan!
    .toPlainText();

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

  group('분석 완료 시트', () {
    testWidgets('인식된 음식마다 이름 옆에 양이 붙는다', (WidgetTester tester) async {
      await _openResult(
        tester,
        _AnalyzeWith(<Map<String, Object?>>[
          _food('스크램블 에그', 185, amountG: 100),
          _food('딸기', 32, amountG: 150),
        ]),
      );

      expect(_recognized(tester), '스크램블 에그 100g · 딸기 150g');
    });

    testWidgets('양을 모르는 음식은 이름만 적는다', (WidgetTester tester) async {
      await _openResult(
        tester,
        _AnalyzeWith(<Map<String, Object?>>[
          _food('스크램블 에그', 185, amountG: 100),
          _food('딸기', 32),
        ]),
      );

      // `0g` 이 뜨면 안 먹었다로 읽힌다.
      expect(_recognized(tester), '스크램블 에그 100g · 딸기');
    });

    testWidgets('끼니 총 내용량 줄은 두지 않는다', (WidgetTester tester) async {
      await _openResult(
        tester,
        _AnalyzeWith(<Map<String, Object?>>[
          _food('스크램블 에그', 185, amountG: 100),
          _food('딸기', 32, amountG: 150),
        ]),
      );

      expect(find.text('내용량'), findsNothing);
      expect(find.text('250'), findsNothing, reason: '100g + 150g 을 더한 값');
      expect(find.text('칼로리'), findsOneWidget, reason: '영양 분석 결과는 칼로리부터');
    });
  });
}
