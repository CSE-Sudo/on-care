/// 기록 날짜·끼니를 식단 상세 한 자리에서 고치기. (#1947)
///
/// 지난 식사 사진을 올리면 앱은 **저장하는 시각** 으로 끼니를 추측한다. 어젯밤
/// 저녁 사진을 오늘 아침에 올리면 `아침` 으로 찍힌다. 날짜는 분석 완료 시트의
/// `날짜 변경` 으로 옮길 수 있었지만 끼니는 그 화면에서 못 고쳐, `어제 · 아침`
/// 이라는 실제와 다른 기록이 남았다.
///
/// 이제 연필 하나를 문으로 삼아 날짜·끼니·음식을 함께 고친다. 시각 입력 칸은
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

/// 식단 탭과 상세 라우트를 띄운다. [router] 를 돌려주어 목록을 거치지 않고
/// 상세를 여는 길(분석 완료 시트의 연필)도 흉내 낼 수 있게 한다.
Future<GoRouter> _pumpApp(WidgetTester tester, FakeDietRepository repo) async {
  useFixedKstDate(DateTime(2026, 8, 20, 9));
  await tester.binding.setSurfaceSize(const Size(900, 3000));
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
      // 보기 모드에서는 고칠 자리가 없다 — 연필을 눌러야 열린다(#1856).
      expect(_dateChange, findsNothing);
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

  group('수정 모드', () {
    testWidgets('연필 하나로 날짜 변경과 끼니 칩 다섯이 함께 열린다', (WidgetTester tester) async {
      await _pumpApp(tester, FakeDietRepository());
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      expect(_dateChange, findsOneWidget);
      expect(
        find.descendant(of: _mealRow, matching: find.byType(AppChoiceChip)),
        findsNWidgets(5),
      );
    });

    testWidgets('어제 저녁으로 고쳐 저장하면 날짜와 끼니가 함께 저장된다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _pumpApp(tester, repo);
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      await _pickDay(tester, _yesterday.day);
      await _pickMeal(tester, '저녁');
      // 저장 전에는 화면에만 있다 — 고르는 즉시 옮기지 않는다.
      expect(repo.movedEntries, isEmpty);
      await _save(tester);

      final ({String date, DietEntry entry}) moved =
          repo.movedEntries['mock-breakfast']!;
      expect(moved.date, '2026-08-19');
      expect(moved.entry.mealType, MealType.dinner);

      // 화면에 남아 보기 모드로 돌아가고, 고친 값이 그대로 보인다.
      expect(_detailPage, findsOneWidget);
      expect(_shownDate(tester), _label(_yesterday));
      expect(
        find.descendant(of: _mealRow, matching: find.text('저녁')),
        findsOneWidget,
      );
      // 목록으로 돌아가면 이 카드가 오늘에서 사라진다 — 어디로 갔는지 말한다.
      expect(find.text('${_label(_yesterday)} 식단으로 옮겼어요'), findsOneWidget);
    });

    testWidgets('옮긴 기록을 그 날의 목록에서 다시 열어도 그 값이다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      final GoRouter router = await _pumpApp(tester, repo);
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      await _pickDay(tester, _yesterday.day);
      await _pickMeal(tester, '저녁');
      await _save(tester);

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

    testWidgets('날짜를 바꾸지 않으면 날짜는 보내지 않는다', (WidgetTester tester) async {
      // 같은 날을 다시 보내도 서버에서는 달라지는 것이 없지만, 보내지 않으면
      // 화면이 날짜를 잘못 알고 있어도 기록이 엉뚱한 날로 옮겨 가지 않는다.
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
      // 옮기지 않았으니 `옮겼어요` 가 아니라 평소의 저장 알림이다.
      expect(find.text('식단이 저장되었어요'), findsOneWidget);
      expect(find.textContaining('옮겼어요'), findsNothing);
    });

    testWidgets('앞날은 고를 수 없다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _pumpApp(tester, repo);
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      // 달력은 오늘(20일)까지만 열려 있다 — 먹지 않은 식사는 적을 수 없다.
      await _pickDay(tester, 21);
      expect(_shownDate(tester), _label(_today));

      await _save(tester);
      expect(repo.movedEntries, isEmpty);
    });

    testWidgets('취소하면 날짜와 끼니가 함께 되돌아간다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _pumpApp(tester, repo);
      await _openFromList(tester);
      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      await _pickDay(tester, _yesterday.day);
      await _pickMeal(tester, '저녁');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(_shownDate(tester), _label(_today));
      expect(
        find.descendant(of: _mealRow, matching: find.text('아침')),
        findsOneWidget,
      );
      expect(repo.movedEntries, isEmpty);
    });

    testWidgets('분석 완료 시트의 연필로 들어가 날짜를 옮겨도 화면이 남는다', (
      WidgetTester tester,
    ) async {
      // 그 연필은 끼니를 넘기지 않고 id 로만 상세를 연다 — 상세가 오늘 목록에서
      // 기록을 찾는다. 날짜를 옮겨 저장하면 오늘 목록에서 그 기록이 빠지므로,
      // 목록을 계속 따라가면 방금 저장한 화면이 `불러오지 못했어요` 로 바뀐다.
      final FakeDietRepository repo = FakeDietRepository();
      final GoRouter router = await _pumpApp(tester, repo);
      unawaited(
        router.push<void>(AppRoutes.dietEntryDetailPath('mock-breakfast')),
      );
      await tester.pumpAndSettle();

      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      await _pickDay(tester, _yesterday.day);
      await _pickMeal(tester, '저녁');
      await _save(tester);

      expect(repo.movedEntries['mock-breakfast']!.date, '2026-08-19');
      expect(_detailPage, findsOneWidget);
      expect(_shownDate(tester), _label(_yesterday));
      expect(find.text('식단 정보를 불러오지 못했어요.'), findsNothing);
    });
  });
}
