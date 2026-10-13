/// 식단 직접 추가의 재시도 — 화면을 연 동안 같은 멱등키. (#3095)
///
/// 응답을 잃은 뒤 같은 내용으로 다시 누르면 같은 키라 서버가 처음 끼니를
/// 돌려준다(중복 없음). 내용을 고쳐 다시 누르면 같은 키·다른 끼니라 서버가
/// 409 를 주고, 화면은 이미 저장된 끼니가 있다고 알리며 기록을 다시 읽는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/diet_entry_key_conflict.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

/// 저장 결과를 차례로 정해 둘 수 있는 저장소. 보낸 키와 오늘 식단을 다시 읽은
/// 횟수를 센다.
class _ScriptedDietRepository extends FakeDietRepository {
  /// 앞에서부터 하나씩 쓴다 — 비면 저장이 성공한다.
  final List<Object> failures = <Object>[];
  final List<String?> sentKeys = <String?>[];
  int todayReads = 0;

  @override
  Future<DietDay> fetchToday() {
    todayReads++;
    return super.fetchToday();
  }

  @override
  Future<DietEntry> createEntry({
    required String date,
    required String mealType,
    required List<FoodItem> foods,
    String? idempotencyKey,
  }) async {
    sentKeys.add(idempotencyKey);
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return super.createEntry(
      date: date,
      mealType: mealType,
      foods: foods,
      idempotencyKey: idempotencyKey,
    );
  }
}

Finder _field(String key) => find.byKey(ValueKey<String>(key));

Future<void> _openManualAdd(
  WidgetTester tester,
  _ScriptedDietRepository repository,
) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dietRepositoryProvider.overrideWithValue(repository),
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
        // 오늘 식단을 보고 있는 화면 — 기록을 다시 읽으면 여기서 보인다.
        home: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            ref.watch(dietTodayProvider);
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => openDietManualAddPage(context),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('diet-food-name-1'), '김밥');
  await tester.enterText(_field('diet-food-kcal-1'), '420');
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('저장'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('응답을 잃은 뒤 같은 내용으로 다시 누르면 같은 키로 한 번만 저장된다', (
    WidgetTester tester,
  ) async {
    final _ScriptedDietRepository repository = _ScriptedDietRepository()
      ..failures.add(Exception('receive timeout'));
    await _openManualAdd(tester, repository);

    await _save(tester);
    expect(find.text('저장하지 못했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
    expect(find.byKey(const Key('mealCreatePage')), findsOneWidget);

    await _save(tester);
    await tester.pumpAndSettle();

    expect(repository.sentKeys, hasLength(2));
    expect(repository.sentKeys.first, isNotNull);
    expect(repository.sentKeys[1], repository.sentKeys.first);
    expect(repository.created, hasLength(1));
    expect(find.byKey(const Key('mealCreatePage')), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('고쳐 다시 누른 저장이 409 면 안내하고 기록을 다시 읽는다', (
    WidgetTester tester,
  ) async {
    final _ScriptedDietRepository repository = _ScriptedDietRepository()
      ..failures.addAll(<Object>[
        Exception('receive timeout'),
        const DietEntryKeyConflict(),
      ]);
    await _openManualAdd(tester, repository);
    await _save(tester);
    final int readsBefore = repository.todayReads;

    await tester.enterText(_field('diet-food-kcal-1'), '500');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(repository.sentKeys[1], repository.sentKeys.first);
    expect(find.text('앞서 보낸 끼니가 이미 저장돼 있어요. 기록을 확인해 주세요'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(repository.todayReads, greaterThan(readsBefore));
    // 적던 화면과 내용은 그대로 남는다.
    expect(find.byKey(const Key('mealCreatePage')), findsOneWidget);
    expect(repository.created, isEmpty);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('저장해 닫은 뒤 다시 열면 새 키다', (WidgetTester tester) async {
    final _ScriptedDietRepository repository = _ScriptedDietRepository();
    await _openManualAdd(tester, repository);
    await _save(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('diet-food-name-1'), '김밥');
    await tester.enterText(_field('diet-food-kcal-1'), '420');
    await tester.pumpAndSettle();
    await _save(tester);
    await tester.pumpAndSettle();

    expect(repository.sentKeys, hasLength(2));
    expect(repository.sentKeys[1], isNot(repository.sentKeys.first));
    await tester.pump(const Duration(seconds: 10));
  });
}
