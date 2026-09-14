/// 사진 분석 결과의 탄·단·지 표시와 AI 메시지 구분. (#1432)
///
/// 서버는 이미 `total_carbs_g`·`total_protein_g`·`total_fat_g` 를 함께 주는데
/// 앱이 읽지 않아, 분석 결과가 칼로리·나트륨·당류만 말했다. AI 가 쓴
/// `coach_comment` 도 수치 카드와 같은 회색이라 서버가 잰 값처럼 보였다.
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
import 'package:oncare_ui/oncare_ui.dart';

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

Future<void> _openResultSheet(
  WidgetTester tester,
  FakeDietRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
        dietRepositoryProvider.overrideWithValue(repository),
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

void main() {
  test('분석 응답의 탄·단·지를 읽는다', () {
    final DietAnalysisResult result = DietAnalysisResult.fromResponse(
      <String, Object?>{
        'entry_id': 'e-1',
        'analysis': <String, Object?>{
          'foods': <Object?>[],
          'total_calories': 615,
          'total_sodium_mg': 1200,
          'total_sugar_g': 9,
          'total_carbs_g': 92.5,
          'total_protein_g': 21,
          'total_fat_g': 14,
          'coach_comment': '나트륨을 조금 줄여 보세요.',
        },
      },
    );

    expect(result.totalCarbsG, 92.5);
    expect(result.totalProteinG, 21);
    expect(result.totalFatG, 14);
  });

  test('탄·단·지가 없는 응답도 0 으로 읽고 죽지 않는다', () {
    final DietAnalysisResult result = DietAnalysisResult.fromResponse(
      <String, Object?>{
        'entry_id': 'e-1',
        'analysis': <String, Object?>{'total_calories': 300},
      },
    );

    expect(result.totalCarbsG, 0);
    expect(result.totalProteinG, 0);
    expect(result.totalFatG, 0);
  });

  testWidgets('결과 화면이 칼로리와 함께 탄·단·지를 적는다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byKey(const Key('diet-result-macros'))),
    );
    final Finder macros = find.byKey(const Key('diet-result-macros'));
    expect(macros, findsOneWidget);
    for (final String label in <String>[
      l.homeMacroCarbs,
      l.homeMacroProtein,
      l.homeMacroFat,
    ]) {
      expect(
        find.descendant(of: macros, matching: find.text(label)),
        findsOneWidget,
      );
    }
    // 대역이 준 값 그대로 — 화면에서 다시 계산하지 않는다. 숫자와 단위는
    // 칼로리·나트륨·당류 행처럼 따로 선다(#1564).
    for (final String grams in <String>['92.5', '21', '14']) {
      expect(
        find.descendant(of: macros, matching: find.text(grams)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: macros, matching: find.text(l.dietUnitG)),
      findsNWidgets(3),
    );
    // 나트륨·당류와 날짜 수정은 그대로다.
    expect(find.text(l.dietSodium), findsOneWidget);
    expect(find.text(l.dietSugar), findsOneWidget);
    expect(find.byKey(const Key('diet-result-date-change')), findsOneWidget);
  });

  testWidgets('AI 메시지는 수치 카드와 다른 파란 배경으로 구분된다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    final Material comment = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const Key('diet-result-coach-comment')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      comment.color,
      OnCareBrand.member.surface,
      reason: '수치 카드(statBg)와 같은 색이면 서버가 잰 값처럼 읽힌다',
    );
  });
}
