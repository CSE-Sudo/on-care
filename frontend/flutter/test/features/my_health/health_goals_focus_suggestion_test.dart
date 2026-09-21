import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// MY 건강 목표의 `권장 비율로 채우기` 가 고른 건강 목표를 따른다. (#1816)
///
/// 온보딩과 같은 계산이라, 가입 때 받은 권장값과 MY 에서 다시 채운 값이 같다.

Future<void> _open(WidgetTester tester, UserProfile profile) async {
  await tester.binding.setSurfaceSize(const Size(900, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(
          MockAccountRepository(profile: profile),
        ),
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
  // 건강 목표는 보기 모드로 열린다 — 연필을 눌러야 칸이 열린다(#2132).
  await tester.tap(find.byKey(const Key('goalsEditButton')));
  await tester.pumpAndSettle();
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).controller!.text;

String? _hint(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).decoration!.hintText;

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder target = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

UserProfile _profile(String conditions) => UserProfile(
  id: 'member',
  name: '김민수',
  email: 'minsu@oncare.com',
  conditions: conditions,
  weightKg: 70,
  dailyCalories: 2000,
  dailyCarbsG: 275,
  dailyProteinG: 100,
  dailyFatG: 55,
);

void main() {
  testWidgets('운동 권장값은 고른 목표를 반영하고 안내 문구도 같은 숫자를 말한다', (tester) async {
    await _open(tester, _profile('체력 강화, 자세 교정'));

    expect(_hint(tester, 'goalCardioField'), '200');
    expect(
      find.text('권장: 하루 300kcal · 주 유산소 200분 · 근력 21세트 · 스트레칭 90분'),
      findsOneWidget,
    );

    final Finder apply = find.byKey(const Key('goalApplyExerciseGoals'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(_text(tester, 'goalDailyBurnField'), '300');
    expect(_text(tester, 'goalCardioField'), '200');
    expect(_text(tester, 'goalStrengthField'), '21');
    expect(_text(tester, 'goalFlexibilityField'), '90');
  });

  testWidgets('근력 향상은 체중으로 단백질을 채우고, 목표를 풀면 비율로 돌아간다', (tester) async {
    await _open(tester, _profile('근력 향상'));

    expect(
      find.text('2000kcal 기준 권장 배분: 탄수화물 262g · 단백질 112g · 지방 56g · 당류 50g'),
      findsOneWidget,
    );

    await _tapKey(tester, 'goal-focus-근력 향상');
    expect(
      find.text('2000kcal 기준 권장 배분: 탄수화물 275g · 단백질 100g · 지방 56g · 당류 50g'),
      findsOneWidget,
    );

    await _tapKey(tester, 'goal-focus-근력 향상');
    final Finder apply = find.byKey(const Key('goalApplyMacroSplit'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(_text(tester, 'goalProteinField'), '112');
    expect(_text(tester, 'goalCarbsField'), '262');
    expect(_text(tester, 'goalFatField'), '56');
  });

  testWidgets('식습관 개선을 고르고 채우면 당류가 총열량 5% 가 된다', (tester) async {
    await _open(tester, _profile('식습관 개선'));

    final Finder apply = find.byKey(const Key('goalApplyMacroSplit'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    final Finder sugar = find.descendant(
      of: find
          .ancestor(
            of: find.text('일일 당류 제한 (g)'),
            matching: find.byType(Column),
          )
          .first,
      matching: find.byType(TextField),
    );
    // 탄단지를 채운 뒤 칼로리는 그 합(2004kcal)으로 맞춰지지만, 당류는 채울 때의
    // 2000kcal 기준이다: 2000×0.05/4 = 25
    expect(tester.widget<TextField>(sugar).controller!.text, '25');
  });
}
