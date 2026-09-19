/// 분석 완료 시트의 연필은 시트 안에서 수정 모드를 연다. (#2097)
///
/// 예전에는 시트를 닫고 저장된 기록의 식단 상세로 넘어갔다. 시트 아래에
/// `저장` 이 서 있는데 연필이 저장 뒤의 화면을 여니, 회원에게는 흐름이 두
/// 화면으로 끊겨 보였다. 이제는 같은 시트에서 고치고 `저장` 한다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
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

/// 끼니·음식 저장 요청을 받아 적어 두는 저장소.
class _RecordingRepository extends FakeDietRepository {
  final List<({String id, String? mealType, List<FoodItem>? foods})> updates =
      <({String id, String? mealType, List<FoodItem>? foods})>[];
  final List<String> deleted = <String>[];

  @override
  Future<void> deleteEntry(String id) {
    deleted.add(id);
    return super.deleteEntry(id);
  }

  @override
  Future<DietEntry> updateEntry({
    required String id,
    String? date,
    String? mealType,
    String? timeLabel,
    List<FoodItem>? foods,
    int? totalCalories,
    int? sodiumMg,
    double? sugarG,
  }) {
    updates.add((id: id, mealType: mealType, foods: foods));
    return super.updateEntry(
      id: id,
      date: date,
      mealType: mealType,
      timeLabel: timeLabel,
      foods: foods,
      totalCalories: totalCalories,
      sodiumMg: sodiumMg,
      sugarG: sugarG,
    );
  }
}

/// 결과 시트가 닫힌 값. 시트가 아직 열려 있으면 null 이다.
bool? _closedWith;

Future<void> _openResultSheet(
  WidgetTester tester,
  FakeDietRepository repository,
) async {
  _closedWith = null;
  await tester.binding.setSurfaceSize(const Size(500, 2400));
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
                onPressed: () async =>
                    _closedWith = await showDietAddSheet(context),
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

Future<void> _tapEdit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('diet-result-edit')));
  await tester.pumpAndSettle();
}

/// 하단 버튼은 시트 스크롤 끝에 있다(#1897) — 보이게 굴린 뒤 누른다.
/// 포커스를 쥔 입력 칸은 제 커서를 화면에 두려고 스크롤을 되돌리므로, 먼저
/// 포커스를 놓는다 — 회원도 자판을 내린 뒤 버튼까지 내려간다.
Future<void> _tapFooter(WidgetTester tester, String label) =>
    _tapVisible(tester, find.widgetWithText(AppButton, label));

Future<void> _tapVisible(WidgetTester tester, Finder button) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// 영양 결과 목록의 칼로리 값.
String _shownCalories(WidgetTester tester) {
  // 수정 칸에도 `칼로리` 가 있다 — 영양 결과 목록 안에서만 찾는다.
  final Finder row = find.ancestor(
    of: find.descendant(
      of: find.byKey(const Key('diet-result-nutrition')),
      matching: find.text('칼로리'),
    ),
    matching: find.byType(AppTile),
  );
  return tester
      .widgetList<Text>(
        find.descendant(of: row.first, matching: find.byType(Text)),
      )
      .elementAt(1)
      .data!;
}

void main() {
  testWidgets('연필은 시트를 닫지 않고 그 자리에서 수정 모드를 연다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    await _tapEdit(tester);

    // 시트가 그대로다 — 식단 상세로 넘어가지 않았다.
    expect(_closedWith, isNull);
    expect(find.byKey(const Key('mealDetailPage')), findsNothing);
    expect(find.byKey(const Key('diet-result-nutrition')), findsOneWidget);

    // `인식된 음식` 대신 음식별 수정 칸이 선다. 인식한 두 음식이 그대로다.
    expect(find.byKey(const Key('diet-result-foods-editor')), findsOneWidget);
    expect(find.byKey(const Key('diet-result-recognized')), findsNothing);
    final TextField name = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('diet-food-name-1')),
        matching: find.byType(TextField),
      ),
    );
    expect(name.controller!.text, '비빔밥');
    expect(find.byKey(const ValueKey<String>('diet-food-name-2')), findsOne);

    // 끼니는 칩으로 고른다. 이미 고치는 중이라 연필은 감춘다.
    expect(
      find.descendant(
        of: find.byKey(const Key('diet-result-meal')),
        matching: find.byType(AppChoiceChip),
      ),
      findsNWidgets(5),
    );
    expect(find.byKey(const Key('diet-result-edit')), findsNothing);

    // 식단 상세의 수정 모드와 같은 순서다 — 기록 날짜·끼니가 위, 먹은 음식이
    // 그 아래, 영양 결과가 맨 아래.
    final double dateTop = tester
        .getTopLeft(find.byKey(const Key('diet-result-date')))
        .dy;
    final double mealTop = tester
        .getTopLeft(find.byKey(const Key('diet-result-meal')))
        .dy;
    final double foodsTop = tester
        .getTopLeft(find.byKey(const Key('diet-result-foods-editor')))
        .dy;
    final double nutritionTop = tester
        .getTopLeft(find.byKey(const Key('diet-result-nutrition')))
        .dy;
    expect(dateTop, lessThan(mealTop));
    expect(mealTop, lessThan(foodsTop));
    expect(foodsTop, lessThan(nutritionTop));
  });

  testWidgets('합계는 고치는 음식을 곧바로 따라온다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());
    expect(_shownCalories(tester), '615');

    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-kcal-1')),
      '500',
    );
    await tester.pump();

    expect(_shownCalories(tester), '515');
  });

  testWidgets('저장은 고친 끼니·음식을 보내고 시트를 닫는다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    final _RecordingRepository repo = _RecordingRepository();
    await _openResultSheet(tester, repo);

    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-name-1')),
      '돌솥비빔밥',
    );
    await _tapVisible(
      tester,
      find.descendant(
        of: find.byKey(const Key('diet-result-meal')),
        matching: find.text('점심'),
      ),
    );
    await _tapFooter(tester, '저장');

    expect(repo.updates, hasLength(1));
    final update = repo.updates.single;
    expect(update.mealType, 'lunch');
    expect(update.foods!.map((FoodItem f) => f.name), <String>['돌솥비빔밥', '김치']);
    // 고치지 않은 영양도 그대로 되돌려 보낸다 — 빠뜨리면 탄단지가 0 이 된다
    // (#1853).
    expect(update.foods!.first.carbsG, 90);
    expect(update.foods!.first.proteinG, 20);
    expect(update.foods!.first.amountG, 400);

    // 시트가 닫혔고, 저장을 마쳤다는 `true` 로 닫혔다.
    expect(_closedWith, isTrue);
    expect(find.byKey(const Key('diet-result-nutrition')), findsNothing);
    expect(find.text('식단이 저장되었어요'), findsOneWidget);
  });

  testWidgets('취소는 고친 값을 버리고 분석 결과 보기로 돌아간다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    final _RecordingRepository repo = _RecordingRepository();
    await _openResultSheet(tester, repo);

    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-name-1')),
      '돌솥비빔밥',
    );
    await _tapFooter(tester, '취소');

    // 시트는 그대로 열려 있고, 보기로 돌아왔다.
    expect(_closedWith, isNull);
    expect(find.byKey(const Key('diet-result-foods-editor')), findsNothing);
    expect(find.byKey(const Key('diet-result-recognized')), findsOneWidget);
    expect(find.byKey(const Key('diet-result-edit')), findsOneWidget);
    expect(repo.updates, isEmpty);

    // 다시 열면 처음 인식한 값에서 시작한다.
    await _tapEdit(tester);
    final TextField name = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('diet-food-name-1')),
        matching: find.byType(TextField),
      ),
    );
    expect(name.controller!.text, '비빔밥');
  });

  testWidgets('당류가 탄수화물을 넘으면 저장하지 않고 칸 아래에 이유를 보인다', (
    WidgetTester tester,
  ) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    final _RecordingRepository repo = _RecordingRepository();
    await _openResultSheet(tester, repo);

    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-sugar-2')),
      '10',
    );
    await _tapFooter(tester, '저장');

    expect(repo.updates, isEmpty);
    expect(_closedWith, isNull);
    expect(
      find.byKey(const ValueKey<String>('diet-food-sugar-2-error')),
      findsOneWidget,
    );
  });

  testWidgets('음식을 모두 지우고 저장하면 기록을 지울지 묻는다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    final _RecordingRepository repo = _RecordingRepository();
    await _openResultSheet(tester, repo);

    await _tapEdit(tester);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('diet-food-remove-2')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('diet-food-remove-1')),
    );
    await _tapFooter(tester, '저장');

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(AppDialog)),
    );
    expect(find.text(l.dietDeleteWhenEmpty), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.text(l.dietDelete),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.updates, isEmpty);
    expect(_closedWith, isFalse);
    expect(repo.deleted, hasLength(1));
  });
}
