/// 사진 분석 결과의 영양 줄 구성. (#1432, #1864, #1987)
///
/// 서버는 이미 `total_carbs_g`·`total_protein_g`·`total_fat_g` 를 함께 주는데
/// 앱이 읽지 않아, 분석 결과가 칼로리·나트륨·당류만 말했다.
///
/// #1864 에서 줄 구성을 식단 상세와 같은 탄단지 기준으로 다시 맞췄다 — 탄·단·지를
/// 작은 세 칸으로 따로 두던 묶음은 없어지고 칼로리와 같은 줄 모양이 되었다.
///
/// #1987 에서 시트 아래의 AI 코멘트가 빠졌다. 저장 직전에 회원이 확인할 것은
/// 인식된 음식과 영양 수치이고, 조언은 식단 탭의 `AI 맞춤 조언` 카드 몫이다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
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

  testWidgets('영양 줄이 칼로리·탄수화물·당류·단백질·지방·나트륨 순으로 선다', (
    WidgetTester tester,
  ) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    final Finder block = find.byKey(const Key('diet-result-nutrition'));
    expect(block, findsOneWidget);
    final AppLocalizations l = AppLocalizations.of(tester.element(block));

    // 식단 상세와 같은 순서다 — 당류는 탄수화물에 딸리고 나트륨이 맨 끝이다.
    final List<String> order = <String>[
      l.dietCalories,
      l.homeMacroCarbs,
      l.dietSugar,
      l.homeMacroProtein,
      l.homeMacroFat,
      l.dietSodium,
    ];
    double previous = double.negativeInfinity;
    for (final String label in order) {
      final Finder row = find.descendant(of: block, matching: find.text(label));
      expect(row, findsOneWidget, reason: '$label 줄이 없다');
      final double top = tester.getTopLeft(row).dy;
      expect(top, greaterThan(previous), reason: '$label 이 순서에서 벗어났다');
      previous = top;
    }

    // 대역이 준 값 그대로 — 화면에서 다시 계산하지 않는다.
    for (final String value in <String>[
      '615',
      '92.5',
      '9',
      '21',
      '14',
      '1200',
    ]) {
      expect(
        find.descendant(of: block, matching: find.text(value)),
        findsOneWidget,
      );
    }

    // 당류만 한 칸 들어가 탄수화물에 딸린 값으로 읽힌다.
    expect(
      find.descendant(of: block, matching: find.text('↳')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.descendant(of: block, matching: find.text(l.dietSugar)),
          )
          .dx,
      greaterThan(
        tester
            .getTopLeft(
              find.descendant(of: block, matching: find.text(l.homeMacroCarbs)),
            )
            .dx,
      ),
    );

    // 탄·단·지를 따로 묶던 작은 세 칸은 없어졌다.
    expect(find.byKey(const Key('diet-result-macros')), findsNothing);
  });

  testWidgets('인식된 음식을 고치는 자리는 연필 아이콘이다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    final Finder edit = find.byKey(const Key('diet-result-edit'));
    expect(edit, findsOneWidget);
    expect(tester.widget<AppIconButton>(edit).icon, AppIcons.edit);
    // 아이콘 하나뿐이라 tooltip 이 접근성 이름이다 — 글자 `수정` 을 대신한다.
    final AppLocalizations l = AppLocalizations.of(tester.element(edit));
    expect(tester.widget<AppIconButton>(edit).tooltip, l.actionEdit);
    expect(find.widgetWithText(AppButton, l.actionEdit), findsNothing);
  });

  // `날짜 변경` 버튼은 #1947 에서 빠졌다 — 고치는 자리는 헤더 연필이 여는
  // 식단 상세 한 곳이다. 라벨과 값만 남는다.
  testWidgets('기록 날짜 줄은 라벨·값이 한 줄에서 가운데로 선다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    final Finder value = find.byKey(const Key('diet-result-date'));
    final AppLocalizations l = AppLocalizations.of(tester.element(value));
    final Rect label = tester.getRect(find.text(l.dietRecordDate));
    final Rect date = tester.getRect(value);

    expect(date.center.dy, label.center.dy);
    expect(find.byKey(const Key('diet-result-date-change')), findsNothing);

    // 위아래가 모두 구획이라 라벨도 같은 자리에서 시작해야 한 줄로 읽힌다.
    expect(label.left, tester.getRect(find.text(l.dietCalories)).left);
    expect(label.left, tester.getRect(find.text(l.dietRecognizedFood)).left);
  });

  testWidgets('서버가 AI 코멘트를 줘도 시트는 그리지 않는다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    // 목 저장소는 코멘트를 채워서 준다 — 값이 비어서 안 보이는 것과
    // 화면이 그리지 않는 것을 가른다(#1987).
    expect(find.byKey(const Key('diet-result-coach-comment')), findsNothing);
    expect(find.byIcon(AppIcons.ai), findsNothing);
  });
}
