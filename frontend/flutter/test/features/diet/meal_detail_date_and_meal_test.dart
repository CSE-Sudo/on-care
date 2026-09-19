/// 기록 날짜·끼니를 식단 상세 한 자리에서 고치기. (#1947)
///
/// 지난 식사 사진을 올리면 앱은 **저장하는 시각** 으로 끼니를 추측한다. 어젯밤
/// 저녁 사진을 오늘 아침에 올리면 `아침` 으로 찍힌다. 날짜는 분석 완료 시트의
/// `날짜 변경` 으로 옮길 수 있었지만 끼니는 그 화면에서 못 고쳐, `어제 · 아침`
/// 이라는 실제와 다른 기록이 남았다.
///
/// 이제 식단 상세의 `식사 정보` 카드가 날짜와 끼니를 한자리에 둔다. 날짜는
/// **따로** 옮긴다 — 연필 없이 `날짜 변경` 을 누르면 고른 즉시 그 날로 간다.
/// 끼니·음식은 연필(수정 모드)에서 고쳐 `저장` 으로 보낸다. 시각 입력 칸은
/// 두지 않는다 — 식단 화면에서 시각 표시를 걷어냈다(#1989).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 오늘은 2026년 8월 20일(목)이다.
final DateTime _today = DateTime(2026, 8, 20);
final DateTime _yesterday = DateTime(2026, 8, 19);

String _label(DateTime date) => DateFormat.yMMMd('ko').format(date);

Finder get _editButton => find.byKey(const Key('mealDetailEditButton'));
Finder get _dateValue => find.byKey(const Key('meal-detail-date'));
Finder get _dateChange => find.byKey(const Key('meal-detail-date-change'));
Finder get _mealRow => find.byKey(const Key('meal-detail-meal'));
Finder get _detailPage => find.byKey(const Key('mealDetailPage'));

Finder get _anyMealCard => find
    .byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('mealCard-'),
    )
    .first;

String _shownDate(WidgetTester tester) => tester.widget<Text>(_dateValue).data!;

/// 날짜 옮기기만 실패하는 저장소 — 끼니·음식 저장은 그대로 된다.
class _DateMoveFailsRepository extends FakeDietRepository {
  int moveAttempts = 0;

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
    if (date != null) {
      moveAttempts += 1;
      throw Exception('boom');
    }
    return super.updateEntry(
      id: id,
      mealType: mealType,
      timeLabel: timeLabel,
      foods: foods,
      totalCalories: totalCalories,
      sodiumMg: sodiumMg,
      sugarG: sugarG,
    );
  }
}

/// 식단 탭과 상세 라우트를 띄운다. [router] 를 돌려주어 목록을 거치지 않고
/// 상세를 여는 길(분석 완료 시트의 연필)도 흉내 낼 수 있게 한다.
Future<GoRouter> _pumpApp(
  WidgetTester tester,
  FakeDietRepository repo, {
  Size size = const Size(900, 3000),
}) async {
  useFixedKstDate(DateTime(2026, 8, 20, 9));
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const DietRecordPage()),
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

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[dietRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        // 저장 토스트가 내비게이터보다 위의 오버레이를 찾는다.
        builder: (BuildContext context, Widget? child) => Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// 목록의 첫 카드(아침)를 눌러 상세를 연다.
Future<void> _openFromList(WidgetTester tester) async {
  await tester.tap(_anyMealCard);
  await tester.pumpAndSettle();
}

Future<void> _pickDay(WidgetTester tester, int day) async {
  await tester.tap(_dateChange);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('portraitDatePickerCalendar')),
      matching: find.text('$day'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('확인'));
  await tester.pumpAndSettle();
}

Future<void> _pickMeal(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(AppChoiceChip, label));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('저장'));
  await tester.pumpAndSettle();
}

void main() {
  group('보기 모드', () {
    testWidgets('식사 정보 카드에 기록 날짜와 끼니가 나란히 보인다', (WidgetTester tester) async {
      await _pumpApp(tester, FakeDietRepository());
      await _openFromList(tester);

      expect(_shownDate(tester), _label(_today));
      expect(
        find.descendant(of: _mealRow, matching: find.text('아침')),
        findsOneWidget,
      );
      // 끼니·음식은 연필을 눌러야 고친다(#1856). 날짜만은 따로 옮기는
      // 자리가 늘 있다.
      expect(_dateChange, findsOneWidget);
      expect(find.byType(AppChoiceChip), findsNothing);
    });

    testWidgets('날짜와 끼니의 값이 같은 자리에서 시작한다', (WidgetTester tester) async {
      await _pumpApp(tester, FakeDietRepository());
      await _openFromList(tester);

      // 두 줄이 한 칸으로 읽히려면 값의 시작이 맞아야 한다.
      expect(
        tester.getRect(_dateValue).left,
        moreOrLessEquals(tester.getRect(_mealRow).left, epsilon: 0.5),
      );
      expect(
        tester.getRect(_dateValue).top,
        lessThan(tester.getRect(_mealRow).top),
      );
    });

    testWidgets('상세는 목록이 부른 날짜를 보인다', (WidgetTester tester) async {
      // 기록에는 날짜가 없다 — 어느 날의 목록에서 열었는가가 곧 그 날이다.
      useFixedKstDate(DateTime(2026, 8, 20, 9));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DietMealDetailPage(
              entryId: 'past',
              initialMeal: DietMeal(
                id: 'past',
                mealType: MealType.dinner,
                date: DateTime(2026, 8, 15),
                time: '19:00',
                total: 500,
                emoji: '🐟',
                thumbBg: OnCareColors.surfaceInput,
                items: const <DietFood>[DietFood('연어', 500)],
                tags: const <DietTag>[],
                sodium: 0,
                sugar: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_shownDate(tester), _label(DateTime(2026, 8, 15)));
    });
  });

  group('날짜만 따로 옮긴다', () {
    testWidgets('연필 없이 날짜를 고르면 그 즉시 그 날로 옮겨진다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _pumpApp(tester, repo);
      await _openFromList(tester);

      await _pickDay(tester, _yesterday.day);

      final ({String date, DietEntry entry}) moved =
          repo.movedEntries['mock-breakfast']!;
      expect(moved.date, '2026-08-19');
      // 날짜만 옮겼다 — 끼니는 그대로다.
      expect(moved.entry.mealType, MealType.breakfast);
      expect(_detailPage, findsOneWidget);
      expect(_shownDate(tester), _label(_yesterday));
      // 수정 모드로 들어가지 않았다.
      expect(_editButton, findsOneWidget);
      // 목록으로 돌아가면 이 카드가 오늘에서 사라진다 — 어디로 갔는지 말한다.
      expect(find.text('${_label(_yesterday)} 식단으로 옮겼어요'), findsOneWidget);
    });

    testWidgets('날짜를 옮긴 뒤 끼니를 저녁으로 고치면 그 날의 목록에서도 어제 · 저녁이다', (
      WidgetTester tester,
    ) async {
      final FakeDietRepository repo = FakeDietRepository();
      final GoRouter router = await _pumpApp(tester, repo);
      await _openFromList(tester);

      await _pickDay(tester, _yesterday.day);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      await _pickMeal(tester, '저녁');
      await _save(tester);

      expect(
        repo.movedEntries['mock-breakfast']!.entry.mealType,
        MealType.dinner,
      );

      router.pop();
      await tester.pumpAndSettle();
      // 주간 띠에서 어제를 눌러 그 날의 목록을 연다.
      await tester.tap(find.text('${_yesterday.day}').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mealCard-mock-breakfast')));
      await tester.pumpAndSettle();

      expect(_shownDate(tester), _label(_yesterday));
      expect(
        find.descendant(of: _mealRow, matching: find.text('저녁')),
        findsOneWidget,
      );
    });

    testWidgets('앞날은 고를 수 없다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _pumpApp(tester, repo);
      await _openFromList(tester);

      // 달력은 오늘(20일)까지만 열려 있다 — 먹지 않은 식사는 적을 수 없다.
      await _pickDay(tester, 21);

      expect(_shownDate(tester), _label(_today));
      expect(repo.movedEntries, isEmpty);
    });

    testWidgets('옮기지 못하면 날짜는 그대로 남고 사정을 알린다', (WidgetTester tester) async {
      final _DateMoveFailsRepository repo = _DateMoveFailsRepository();
      await _pumpApp(tester, repo);
      await _openFromList(tester);

      await _pickDay(tester, _yesterday.day);

      expect(repo.moveAttempts, 1);
      expect(_shownDate(tester), _label(_today));
      expect(find.textContaining('날짜를 바꾸지 못했어요'), findsOneWidget);
      // 다시 누를 수 있다 — 버튼이 spinner 에 머물지 않는다.
      expect(_dateChange, findsOneWidget);
    });

    testWidgets('수정 중에 날짜를 옮겨도 고치던 끼니는 남고, 취소는 날짜를 되돌리지 않는다', (
      WidgetTester tester,
    ) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _pumpApp(tester, repo);
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      await _pickMeal(tester, '저녁');
      await _pickDay(tester, _yesterday.day);
      // 고치던 끼니는 날짜 옮기기와 섞이지 않는다 — 아직 화면에만 있다.
      expect(
        tester
            .widget<AppChoiceChip>(find.widgetWithText(AppChoiceChip, '저녁'))
            .selected,
        isTrue,
      );
      expect(
        repo.movedEntries['mock-breakfast']!.entry.mealType,
        MealType.breakfast,
      );

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      // 끼니는 되돌아가고, 따로 옮긴 날짜는 남는다.
      expect(
        find.descendant(of: _mealRow, matching: find.text('아침')),
        findsOneWidget,
      );
      expect(_shownDate(tester), _label(_yesterday));
      expect(repo.movedEntries['mock-breakfast']!.date, '2026-08-19');
    });

    testWidgets('분석 완료 시트의 연필로 들어가 날짜를 옮겨도 화면이 남는다', (
      WidgetTester tester,
    ) async {
      // 그 연필은 끼니를 넘기지 않고 id 로만 상세를 연다 — 상세가 오늘 목록에서
      // 기록을 찾는다. 날짜를 옮기면 오늘 목록에서 그 기록이 빠지므로, 목록을
      // 계속 따라가면 방금 옮긴 화면이 `불러오지 못했어요` 로 바뀐다.
      final FakeDietRepository repo = FakeDietRepository();
      final GoRouter router = await _pumpApp(tester, repo);
      unawaited(
        router.push<void>(AppRoutes.dietEntryDetailPath('mock-breakfast')),
      );
      await tester.pumpAndSettle();

      await _pickDay(tester, _yesterday.day);

      expect(repo.movedEntries['mock-breakfast']!.date, '2026-08-19');
      expect(_detailPage, findsOneWidget);
      expect(_shownDate(tester), _label(_yesterday));
      expect(find.text('식단 정보를 불러오지 못했어요.'), findsNothing);
    });
  });

  group('끼니·음식 저장', () {
    testWidgets('연필을 누르면 끼니 칩 다섯이 열린다', (WidgetTester tester) async {
      await _pumpApp(tester, FakeDietRepository());
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _mealRow, matching: find.byType(AppChoiceChip)),
        findsNWidgets(5),
      );
      // 날짜 변경은 수정 모드에서도 같은 자리에 있다.
      expect(_dateChange, findsOneWidget);
    });

    testWidgets('끼니만 고쳐 저장하면 날짜는 보내지 않는다', (WidgetTester tester) async {
      // 끼니·음식 저장이 기록을 다른 날로 옮길 일이 없다 — 날짜는 따로 옮긴다.
      final FakeDietRepository repo = FakeDietRepository();
      await _pumpApp(tester, repo);
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      await _pickMeal(tester, '간식');
      await _save(tester);

      expect(repo.movedEntries, isEmpty);
      final DietEntry saved = (await tester.runAsync(
        () => repo.fetchToday(),
      ))!.entries.firstWhere((DietEntry e) => e.id == 'mock-breakfast');
      expect(saved.mealType, MealType.snack);
      expect(find.text('식단이 저장되었어요'), findsOneWidget);
      expect(find.textContaining('옮겼어요'), findsNothing);
    });
  });

  // 칩 다섯이 한 줄에 다 들어가지 않으면 `간식·야식` 이 함께 아랫줄로 간다.
  // `야식` 하나만 떨어지면 따로 떨어진 선택지처럼 읽힌다 (#2080).
  group('끼니 칩 줄바꿈', () {
    double chipTop(WidgetTester tester, String label) =>
        tester.getTopLeft(find.widgetWithText(AppChoiceChip, label)).dy;

    Future<void> openEdit(WidgetTester tester, Size size) async {
      await _pumpApp(tester, FakeDietRepository(), size: size);
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();
    }

    testWidgets('폰 폭에서는 아침·점심·저녁 / 간식·야식 두 줄이다', (WidgetTester tester) async {
      await openEdit(tester, const Size(390, 3000));

      final double first = chipTop(tester, '아침');
      expect(chipTop(tester, '점심'), first);
      expect(chipTop(tester, '저녁'), first);
      final double second = chipTop(tester, '간식');
      expect(second, greaterThan(first), reason: '간식이 윗줄에 남으면 야식만 떨어진다');
      expect(chipTop(tester, '야식'), second);
    });

    testWidgets('다섯이 한 줄에 들어가는 폭에서는 한 줄이다', (WidgetTester tester) async {
      await openEdit(tester, const Size(900, 3000));

      final double first = chipTop(tester, '아침');
      for (final String label in <String>['점심', '저녁', '간식', '야식']) {
        expect(chipTop(tester, label), first, reason: label);
      }
    });
  });
}
