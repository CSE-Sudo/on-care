/// 끼니를 저장한 뒤 `이번 주`·`전체` 집계와 기록 시작일이 새 값으로 바뀐다. (#2625)
///
/// 기간 집계는 autoDispose 가 아니다. 저장 흐름이 그것을 비우지 않으면 화면이
/// 보고 있는 동안에도 옛 합계에 머문다 — 실제 화면에서 본 증상이 그것이다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/services/record_span_provider.dart';
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

/// 이번 주 — 2026-08-17(월) ~ 23(일). 오늘은 20일(목).
final DietDateRange _week = (
  from: DateTime(2026, 8, 17),
  to: DateTime(2026, 8, 23),
);

/// 기록 시작일 조회 횟수.
int _spanCalls = 0;

Future<void> _pump(WidgetTester tester, FakeDietRepository repo) async {
  _spanCalls = 0;
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dietRepositoryProvider.overrideWithValue(repo),
        mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
        recordSpanProvider.overrideWith((Ref ref) {
          _spanCalls++;
          return RecordSpan(dietFirstDate: DateTime(2026, 8, 17));
        }),
        sessionFeatureResetOverride(),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext context, Widget? child) => Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
          ],
        ),
        home: Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              // 기간 뷰가 보고 있는 것과 같은 두 값을 화면에 둔다.
              final AsyncValue<DietPeriod> week = ref.watch(
                dietPeriodProvider(_week),
              );
              ref.watch(recordSpanProvider);
              return Column(
                children: <Widget>[
                  Text(
                    '${week.valueOrNull?.totalCalories ?? '-'}',
                    key: const Key('week-total'),
                  ),
                  ElevatedButton(
                    onPressed: () => showDietAddSheet(context),
                    child: const Text('open'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// 대역의 하루 조회는 타이머로 늦게 답한다. `pumpAndSettle` 은 예약된 프레임만
/// 기다리므로, 이레치 조회가 끝날 만큼 시계를 먼저 돌린다.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

int _weekTotal(WidgetTester tester) =>
    int.parse(tester.widget<Text>(find.byKey(const Key('week-total'))).data!);

void main() {
  setUp(() => useFixedKstDate(DateTime(2026, 8, 20, 9)));

  testWidgets('사진 분석으로 저장하면 이번 주 합계가 그만큼 는다', (WidgetTester tester) async {
    await _pump(tester, FakeDietRepository());
    final int before = _weekTotal(tester);
    final int spanBefore = _spanCalls;

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();

    // 대역의 분석 결과는 615kcal(비빔밥+김치)다. 시트가 떠 있는 동안 이미
    // 저장됐으므로 뒤의 합계가 벌써 바뀌어 있다.
    await _settle(tester);
    expect(_weekTotal(tester), before + 615);
    // 첫 기록일 수 있다 — 시작일도 다시 읽었다.
    expect(_spanCalls, greaterThan(spanBefore));
  });

  testWidgets('직접 추가로 저장하면 이번 주 합계가 그만큼 는다', (WidgetTester tester) async {
    await _pump(tester, FakeDietRepository());
    final int before = _weekTotal(tester);
    final int spanBefore = _spanCalls;

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dietManualAddButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppChoiceChip, '저녁'));
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-name-1')),
      '김밥',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-kcal-1')),
      '420',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    await _settle(tester);
    expect(find.byKey(const Key('mealCreatePage')), findsNothing);
    expect(_weekTotal(tester), before + 420);
    expect(_spanCalls, greaterThan(spanBefore));
  });
}
