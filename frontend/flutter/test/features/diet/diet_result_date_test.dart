/// 사진 분석 결과 시트의 기록 날짜. (#1241, #1947)
///
/// 분석은 저장한 시각의 날짜로 기록을 남긴다. 지난 식사의 사진이면 실제로 먹은
/// 날로 옮겨야 하는데, #1947 에서 그 자리를 이 시트의 `날짜 변경` 버튼에서 헤더
/// 연필이 여는 식단 상세로 옮겼다 — 이 시트에서는 날짜만 고치고 끼니는 못 고쳐
/// `어제 · 아침` 같은 기록이 남았다. 옮기는 검사는 `meal_detail_date_and_meal_test`
/// 에 있고, 여기서는 시트가 값만 보이는지 본다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
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

MealPhoto get _photo => MealPhoto.fromBytes(_jpegBytes)!;

class _FixedPicker implements MealPhotoPicker {
  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async => _photo;
}

String _label(DateTime date) => DateFormat.yMMMd('ko').format(date);

Future<ProviderContainer> _openResultSheet(
  WidgetTester tester,
  FakeDietRepository repository,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
      dietRepositoryProvider.overrideWithValue(repository),
      sessionFeatureResetOverride(),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  return container;
}

String _shownDate(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('diet-result-date'))).data!;

/// `끼니` 줄의 값. 식단 상세와 같은 배지다.
String _shownMeal(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('diet-result-meal')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('분석이 끝나면 기록 날짜가 오늘로 보인다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    expect(find.text('분석 완료!'), findsOneWidget);
    expect(_shownDate(tester), _label(DateTime(2026, 8, 20)));
  });

  testWidgets('시트의 날짜 줄은 값만 보인다 — 고치는 자리는 헤더 연필 하나다', (
    WidgetTester tester,
  ) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    // 편집 자리가 둘이면 같은 화면에서 고치는 방법이 갈린다(#1947).
    expect(find.byKey(const Key('diet-result-date-change')), findsNothing);
    expect(find.text('날짜 변경'), findsNothing);
    expect(find.byKey(const Key('diet-result-edit')), findsOneWidget);
  });

  // 날짜만 적으면 같은 날 세 끼가 구분되지 않아 어느 끼니로 들어가는지 알 수
  // 없었다(#1897). 그 몫은 끼니 줄이 한다 — 시각은 #1989 에서 빠졌다.
  // 끼니는 사진을 고른 시각이 정한다(`_currentMealType`).
  testWidgets('기록 날짜와 끼니가 따로 두 줄이다 — 시각은 없다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    expect(_shownDate(tester), _label(DateTime(2026, 8, 20)));
    expect(_shownMeal(tester), '아침');
    // 대역은 `09:00` 을 `time_label` 로 계속 준다 — 값이 없어서가 아니라
    // 화면이 그리지 않는 것이다.
    expect(_shownDate(tester), isNot(contains(':')));

    // 끼니가 날짜의 꼬리가 아니라 제 줄에 있다 — 식단 상세와 같은 모양이다.
    final Rect date = tester.getRect(find.byKey(const Key('diet-result-date')));
    final Rect meal = tester.getRect(find.byKey(const Key('diet-result-meal')));
    expect(meal.top, greaterThanOrEqualTo(date.bottom));
    expect(meal.left, moreOrLessEquals(date.left, epsilon: 0.5));
    expect(find.text('끼니'), findsOneWidget);
  });

  testWidgets('끼니는 사진을 고른 시각을 따른다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 19));
    await _openResultSheet(tester, FakeDietRepository());

    expect(_shownMeal(tester), '저녁');
  });

  // 21시 이후는 야식이다(#1988). 그전에는 이 자리가 간식이라, 밤늦게 먹은 것과
  // 낮의 간식이 한 칸에 섞여 코칭에서 갈라 보이지 않았다.
  testWidgets('21시 이후에 올린 기록은 야식으로 추측한다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 22));
    await _openResultSheet(tester, FakeDietRepository());

    expect(_shownMeal(tester), '야식');
  });

  testWidgets('21시 직전은 아직 저녁이다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 20, 59));
    await _openResultSheet(tester, FakeDietRepository());

    expect(_shownMeal(tester), '저녁');
  });

  testWidgets('간식은 어느 시각에서도 추측하지 않는다', (WidgetTester tester) async {
    // 간식은 끼니 사이에 먹는 것이지 특정 시각에 먹는 것이 아니다. 시간대를
    // 떼어 주면 그 시간의 끼니가 매번 간식으로 찍혀 회원이 고쳐야 한다.
    for (final int hour in <int>[0, 7, 10, 11, 14, 15, 17, 20, 21, 23]) {
      // 같은 위젯 종류로 다시 pump 하면 Navigator 가 살아남아 앞 시트가 그대로
      // 남는다. 빈 트리를 한 번 끼워 라우트까지 걷어낸다.
      await tester.pumpWidget(const SizedBox.shrink());
      useFixedKstDate(DateTime(2026, 8, 20, hour));
      await _openResultSheet(tester, FakeDietRepository());

      expect(_shownMeal(tester), isNot('간식'), reason: '$hour 시에 간식으로 추측했다');
    }
  });
}
