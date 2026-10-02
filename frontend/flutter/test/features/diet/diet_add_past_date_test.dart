/// 지난 날짜 화면의 `식단 추가` 는 그 날짜로 저장한다. (#2849)
///
/// 식단 탭에서 어제를 보며 `식단 추가` 를 누르면 사진 분석이든 직접 입력이든
/// 오늘로 저장돼, 어제 목록에는 끝내 보이지 않았다. 하단 `+` 는 지금처럼
/// 오늘이다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/record_span.dart';

/// 오늘은 2026년 8월 20일(목), 어제는 19일이다.
final DateTime _today = DateTime(2026, 8, 20);
final DateTime _yesterday = DateTime(2026, 8, 19);

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

String _label(DateTime d) => DateFormat.yMMMd('ko').format(d);

Widget _app(FakeDietRepository repo, {required Widget home}) {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/diet/entries/:entryId',
        builder: (BuildContext context, GoRouterState state) =>
            DietMealDetailPage(
              entryId: state.pathParameters['entryId']!,
              initialMeal: state.extra as DietMeal?,
            ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: <Override>[
      dietRepositoryProvider.overrideWithValue(repo),
      mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
      testRecordSpanOverride(),
      sessionFeatureResetOverride(),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (BuildContext context, Widget? child) => Overlay(
        initialEntries: <OverlayEntry>[
          OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
        ],
      ),
    ),
  );
}

Future<void> _pumpDietTab(WidgetTester tester, FakeDietRepository repo) async {
  useFixedKstDate(DateTime(2026, 8, 20, 9));
  await tester.binding.setSurfaceSize(const Size(900, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(repo, home: const DietRecordPage()));
  await tester.pumpAndSettle();
}

/// 주간 띠에서 어제를 눌러 그 날 목록을 연 뒤 `식단 추가` 를 누른다.
Future<void> _addOnYesterday(WidgetTester tester) async {
  await tester.tap(find.text('${_yesterday.day}').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('식단 추가'));
  await tester.tap(find.text('식단 추가'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('어제를 보며 연 사진 분석은 어제로 저장되고 어제 목록에 나타난다', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = FakeDietRepository();
    await _pumpDietTab(tester, repo);
    await _addOnYesterday(tester);

    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();

    // 서버에 그 날짜를 싣는다 — 저장한 뒤 옮기는 두 번의 요청이 아니다.
    expect(repo.analyzedDates, <String?>['2026-08-19']);
    // 결과 시트의 날짜도 어제로 시작한다.
    expect(
      tester.widget<Text>(find.byKey(const Key('diet-result-date'))).data,
      _label(_yesterday),
    );

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    // 돌아온 어제 목록에 방금 저장한 끼니가 있다.
    expect(find.byKey(const Key('mealCard-mock-diet-1')), findsOneWidget);
    expect(repo.movedEntries.keys, contains('mock-diet-1'));
  });

  testWidgets('어제를 보며 연 직접 입력은 날짜가 어제로 시작하고 어제로 저장된다', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = FakeDietRepository();
    await _pumpDietTab(tester, repo);
    await _addOnYesterday(tester);

    await tester.tap(find.byKey(const Key('dietManualAddButton')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('meal-create-date'))).data,
      _label(_yesterday),
    );

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

    expect(repo.created.single.date, '2026-08-19');
  });

  testWidgets('오늘을 보며 연 추가는 날짜를 싣지 않는다 — 서버가 저장하는 날이다', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = FakeDietRepository();
    await _pumpDietTab(tester, repo);

    await tester.ensureVisible(find.text('식단 추가'));
    await tester.tap(find.text('식단 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();

    expect(repo.analyzedDates, <String?>[null]);
    expect(
      tester.widget<Text>(find.byKey(const Key('diet-result-date'))).data,
      _label(_today),
    );
  });

  group('showDietAddSheet', () {
    Future<void> pumpOpener(
      WidgetTester tester,
      FakeDietRepository repo, {
      DateTime? date,
    }) async {
      useFixedKstDate(DateTime(2026, 8, 20, 9));
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          repo,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDietAddSheet(context, date: date),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('날짜 없이 열면(하단 +) 오늘이다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await pumpOpener(tester, repo);

      await tester.tap(find.byKey(const Key('dietManualAddButton')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('meal-create-date'))).data,
        _label(_today),
      );
    });

    testWidgets('앞날을 넘겨도 오늘로 시작한다 — 먹지 않은 식사는 기록하지 않는다', (
      WidgetTester tester,
    ) async {
      final FakeDietRepository repo = FakeDietRepository();
      await pumpOpener(tester, repo, date: DateTime(2026, 8, 22));

      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();

      expect(repo.analyzedDates, <String?>[null]);
      expect(
        tester.widget<Text>(find.byKey(const Key('diet-result-date'))).data,
        _label(_today),
      );
    });
  });
}
