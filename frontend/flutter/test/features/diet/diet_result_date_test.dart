/// 사진 분석 결과 시트의 기록 날짜와 끼니. (#1241, #1947)
///
/// 분석은 저장한 시각의 날짜로 기록을 남긴다. 지난 식사의 사진을 나중에 올리는
/// 일이 있어, 결과를 확인하는 자리에서 실제로 먹은 날로 **따로** 옮길 수 있어야
/// 한다 — 식단 상세의 `날짜 변경` 과 같은 동작이다. 끼니·음식은 헤더 연필이 여는
/// 식단 상세에서 고친다. 기록 날짜와 끼니는 상세와 같은 두 줄로 보인다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
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

MealPhoto get _photo => MealPhoto.fromBytes(_jpegBytes)!;

class _FixedPicker implements MealPhotoPicker {
  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async => _photo;
}

/// 날짜 옮기기가 실패하는 저장소 — 실패했을 때 화면이 옛 날짜로 남는지 본다.
class _FailingUpdateRepository extends FakeDietRepository {
  int attempts = 0;

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
  }) async {
    attempts += 1;
    throw Exception('boom');
  }
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

  testWidgets('날짜를 고르면 그 즉시 그 날의 식단으로 옮겨진다 — 끼니는 그대로다', (
    WidgetTester tester,
  ) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    final FakeDietRepository repo = FakeDietRepository();
    await _openResultSheet(tester, repo);

    // 저장소를 직접 읽는다 — 위젯 테스트의 가짜 시계에서는 provider 의 future 를
    // 그냥 await 하면 시간이 흐르지 않아 영영 기다린다.
    final int before = (await tester.runAsync(
      () => repo.fetchToday(),
    ))!.entries.length;

    await tester.tap(find.byKey(const Key('diet-result-date-change')));
    await tester.pumpAndSettle();
    // 달력에서 이틀 전(18일)을 고른다.
    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(_shownDate(tester), _label(DateTime(2026, 8, 18)));
    expect(repo.movedEntries.values.single.date, '2026-08-18');
    // 날짜만 옮겼다 — 끼니는 사진을 고른 시각 그대로다.
    expect(_shownMeal(tester), '아침');
    expect(repo.movedEntries.values.single.entry.mealType, MealType.breakfast);

    // 오늘에서 빠지고 고른 날짜에서 보인다 — 한쪽만 바뀌면 하루 합계가 두 날에
    // 겹쳐 보인다.
    final DietDay today = (await tester.runAsync(() => repo.fetchToday()))!;
    expect(today.entries.length, before - 1);
    final DietDay moved = (await tester.runAsync(
      () => repo.fetchByDate(DateTime(2026, 8, 18)),
    ))!;
    expect(
      moved.entries.map((DietEntry e) => e.id),
      contains(repo.movedEntries.keys.single),
    );
  });

  testWidgets('앞날은 고를 수 없다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    final FakeDietRepository repo = FakeDietRepository();
    await _openResultSheet(tester, repo);

    await tester.tap(find.byKey(const Key('diet-result-date-change')));
    await tester.pumpAndSettle();

    // 달력은 오늘(20일)까지만 열려 있다 — 먹지 않은 식사를 기록할 수는 없다.
    // 달력 안으로 좁혀 찾는다 — 뒤에 남아 있는 결과 시트의 탄·단·지도 단위
    // 없는 숫자를 쓴다(#1564).
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('portraitDatePickerCalendar')),
        matching: find.text('21'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(_shownDate(tester), _label(DateTime(2026, 8, 20)));
    expect(repo.movedEntries, isEmpty);
  });

  testWidgets('옮기지 못하면 날짜는 그대로 남고 사정을 알린다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    final _FailingUpdateRepository repo = _FailingUpdateRepository();
    await _openResultSheet(tester, repo);

    await tester.tap(find.byKey(const Key('diet-result-date-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(repo.attempts, 1);
    expect(_shownDate(tester), _label(DateTime(2026, 8, 20)));
    expect(find.textContaining('날짜를 바꾸지 못했어요'), findsOneWidget);
  });

  testWidgets('끼니·음식을 고치는 자리는 헤더 연필이다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    // 날짜만 이 시트에서 따로 옮긴다. 끼니는 값만 보이고 칩이 없다.
    expect(find.byKey(const Key('diet-result-edit')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('diet-result-meal')),
        matching: find.byType(AppChoiceChip),
      ),
      findsNothing,
    );
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
