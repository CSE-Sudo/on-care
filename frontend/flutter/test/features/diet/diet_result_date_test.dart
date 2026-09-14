/// 사진 분석 결과 시트의 기록 날짜. (#1241)
///
/// 분석은 저장한 시각의 날짜로 기록을 남긴다. 지난 식사의 사진을 나중에 올리는
/// 일이 있어, 결과를 확인하는 자리에서 실제로 먹은 날로 옮길 수 있어야 한다.
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

void main() {
  testWidgets('분석이 끝나면 기록 날짜가 오늘로 보인다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _openResultSheet(tester, FakeDietRepository());

    expect(find.text('분석 완료!'), findsOneWidget);
    expect(_shownDate(tester), _label(DateTime(2026, 8, 20)));
  });

  testWidgets('날짜를 고치면 그 날의 식단으로 옮겨진다', (WidgetTester tester) async {
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
    // 내일을 눌러도 고른 날은 그대로다. 달력 안으로 좁혀 찾는다 — 뒤에 남아
    // 있는 결과 시트의 탄·단·지도 단위 없는 숫자를 쓴다(#1564).
    await tester.tap(
      find.descendant(
        of: find.byType(CalendarDatePicker),
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
}
