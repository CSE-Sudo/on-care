import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';

import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 건강 목표의 칼로리 ↔ 탄단지 연동. (#896)
///
/// 목 프로필의 출발값은 2000kcal · 탄 275g · 단 100g · 지 55g 이고,
/// 2000kcal 의 권장 배분(탄 50 · 단 30 · 지 20)은 250 / 150 / 44 다.

Future<void> _openHealthGoals(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HealthGoalsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

/// 라벨로 필드를 찾는다 — 칼로리 칸에는 키가 없다.
TextField _fieldByLabel(WidgetTester tester, String label) {
  final Finder column = find.ancestor(
    of: find.text(label),
    matching: find.byType(Column),
  );
  return tester.widget<TextField>(
    find.descendant(of: column.first, matching: find.byType(TextField)),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).controller!.text;

String _calories(WidgetTester tester) =>
    _fieldByLabel(tester, '일일 칼로리 제한 (kcal)').controller!.text;

void main() {
  testWidgets('화면을 열자마자는 저장된 값이 그대로 남는다', (tester) async {
    await _openHealthGoals(tester);

    expect(_calories(tester), '2000');
    expect(_text(tester, 'goalCarbsField'), '275');
    expect(_text(tester, 'goalProteinField'), '100');
    expect(_text(tester, 'goalFatField'), '55');
    // 자동 계산이 일어나지 않았으니 그 안내도 없다.
    expect(find.text('탄·단·지 목표로 계산한 값이에요'), findsNothing);
  });

  testWidgets('탄단지를 고치면 칼로리가 4/4/9 로 다시 계산된다', (tester) async {
    await _openHealthGoals(tester);

    await tester.enterText(_field('goalCarbsField'), '200');
    await tester.pump();

    // 4×(200+100) + 9×55 = 1695
    expect(_calories(tester), '1695');
    expect(find.text('탄·단·지 목표로 계산한 값이에요'), findsOneWidget);
  });

  testWidgets('세 칸 중 하나라도 비면 칼로리를 건드리지 않는다', (tester) async {
    await _openHealthGoals(tester);

    await tester.enterText(_field('goalProteinField'), '');
    await tester.pump();

    expect(_calories(tester), '2000');
    expect(find.text('탄·단·지 목표로 계산한 값이에요'), findsNothing);
  });

  testWidgets('칼로리를 고치면 탄단지 placeholder 가 권장 배분으로 바뀐다', (tester) async {
    await _openHealthGoals(tester);

    await tester.enterText(_field('goalCarbsField'), '');
    await tester.enterText(_field('goalProteinField'), '');
    await tester.enterText(_field('goalFatField'), '');
    await tester.pump();

    // 1600kcal → 탄 200 · 단 120 · 지 36
    await tester.enterText(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('일일 칼로리 제한 (kcal)'),
              matching: find.byType(Column),
            )
            .first,
        matching: find.byType(TextField),
      ),
      '1600',
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('goalCarbsField')).decoration!.hintText,
      '200',
    );
    expect(
      tester.widget<TextField>(_field('goalProteinField')).decoration!.hintText,
      '120',
    );
    expect(
      tester.widget<TextField>(_field('goalFatField')).decoration!.hintText,
      '36',
    );
    // 값을 덮어쓰지는 않는다.
    expect(_text(tester, 'goalCarbsField'), isEmpty);
  });

  testWidgets('권장 비율로 채우기는 세 칸을 채우고 칼로리를 그 합에 맞춘다', (tester) async {
    await _openHealthGoals(tester);

    final Finder apply = find.byKey(const Key('goalApplyMacroSplit'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pump();

    // 2000kcal → 탄 250 · 단 150 · 지 44, 되돌려 세면 4×400 + 9×44 = 1996
    expect(_text(tester, 'goalCarbsField'), '250');
    expect(_text(tester, 'goalProteinField'), '150');
    expect(_text(tester, 'goalFatField'), '44');
    expect(_calories(tester), '1996');
    // 세 칸이 배분과 같아져도 버튼은 그대로 남는다 — 값을 고쳐 둔 다음 권장
    // 배분으로 되돌릴 길이 이 버튼 하나뿐이라, 조건에 따라 사라지면 되돌릴
    // 방법이 없어진다.
    expect(find.byKey(const Key('goalApplyMacroSplit')), findsOneWidget);
  });
}
