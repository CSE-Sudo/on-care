/// 건강 목표는 연필을 눌러야 고쳐진다. (#2132)
///
/// 내 프로필·식단 끼니 상세와 같은 방식이다. 목표는 회원과 트레이너가 같은
/// 칸을 고치는 값이라, 열어 본 김에 스친 값이 그대로 저장되면 상대가 정한
/// 목표가 말없이 덮인다. 들어오면 읽는 화면이고, 고치겠다고 말해야 열린다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 나트륨만 세우지 않은 회원. 관리 초점은 하나 골라 뒀다.
const UserProfile _profile = UserProfile(
  id: 'user-goals-edit',
  name: '연필',
  email: 'pencil@oncare.com',
  conditions: '체중 감량',
  dailyCalories: 1800,
  dailySugarG: 40,
  dailyCarbsG: 200,
  dailyProteinG: 120,
  dailyFatG: 50,
  dailyBurnKcal: 400,
  weeklyCardioMinutes: 150,
  weeklyStrengthSets: 21,
  weeklyFlexibilityMinutes: 60,
);

Future<void> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(
          MockAccountRepository(profile: _profile),
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
}

Future<void> _beginEdit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('goalsEditButton')));
  await tester.pumpAndSettle();
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

void main() {
  testWidgets('들어오면 읽는 화면이다 — 칸도 저장 줄도 없다', (tester) async {
    await _open(tester);

    expect(find.byKey(const Key('goalsEditButton')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('mySettingsSaveRow')), findsNothing);
    // 값을 덮어쓰는 버튼도 내지 않는다.
    expect(find.byKey(const Key('goalApplyExerciseGoals')), findsNothing);
    expect(find.byKey(const Key('goalApplyMacroSplit')), findsNothing);
    // 저장된 목표는 그대로 읽힌다.
    expect(find.text('1800'), findsOneWidget);
  });

  testWidgets('세운 적 없는 칸은 숫자를 흐리게 두고, 카드가 한 줄로 밝힌다', (tester) async {
    await _open(tester);

    // 나트륨만 세우지 않았다 — 권장값이 적히되 흐린 색이라 내가 정한 값과
    // 구별된다. 칸마다 꼬리표를 달지 않는 대신 카드가 한 번만 말한다.
    Color colorOf(String key) =>
        tester.widget<Text>(find.byKey(Key('goalValue-$key'))).style!.color!;
    expect(find.text('${UserProfile.defaultDailySodiumMg}'), findsOneWidget);
    expect(colorOf('sodium'), OnCareColors.textTertiary);
    expect(colorOf('kcal'), OnCareColors.textPrimary);

    // 각주는 흐린 숫자가 있는 식단 카드에만 선다 — 운동 목표는 다 세워 뒀다.
    // 흐린 숫자는 홈·운동 탭이 실제로 재는 기준선이라 `권장치` 라 부르지
    // 않는다 — 아래쪽 `권장:` 줄은 관리 초점을 반영한 다른 수다.
    expect(find.byKey(const Key('goalUnsetHint')), findsOneWidget);
    expect(find.text('흐린 값은 목표를 세우기 전의 기본 기준이에요'), findsOneWidget);
  });

  testWidgets('수정 모드에서는 각주를 내지 않는다 — 칸이 스스로 말한다', (tester) async {
    await _open(tester);
    await _beginEdit(tester);

    expect(find.byKey(const Key('goalUnsetHint')), findsNothing);
  });

  testWidgets('관리 초점은 고른 것만 남는다 — 고르지 않은 칩은 내지 않는다', (tester) async {
    await _open(tester);

    expect(find.byType(AppChoiceChip), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('goal-focus-tag-체중 감량')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('goal-focus-tag-재활')),
      findsNothing,
    );

    await _beginEdit(tester);
    // 고칠 때는 여덟 개가 모두 선다.
    expect(find.byType(AppChoiceChip), findsNWidgets(8));
  });

  testWidgets('권장 안내는 항목 중간에서 줄이 끊기지 않는다', (tester) async {
    // 한 덩어리 Text 였을 때는 한글이 글자 사이 어디서나 끊겨 `스트레칭 60`
    // 에서 줄이 바뀌고 `분` 만 다음 줄에 남았다. 항목마다 Text 를 세워 두면
    // 줄은 항목과 항목 사이에서만 바뀐다.
    await _open(tester);
    await _beginEdit(tester);

    final Finder note = find
        .ancestor(
          of: find.textContaining('권장: 하루'),
          matching: find.byType(Wrap),
        )
        .first;
    final List<String> parts = tester
        .widgetList<Text>(
          find.descendant(of: note, matching: find.byType(Text)),
        )
        .map((Text t) => t.data!)
        .toList();

    // 네 항목이 각자 선다 — 숫자와 단위가 같은 Text 안에 있어 떨어질 수 없다.
    expect(parts, hasLength(4));
    expect(parts.last, endsWith('분'));
    expect(parts.join(), startsWith('권장: 하루'));

    // 읽어 주는 것은 여전히 한 문장이다.
    final SemanticsNode semantics = tester.getSemantics(note);
    expect(semantics.label, parts.join());
  });

  testWidgets('연필을 누르면 칸과 저장 줄이 열리고, 연필은 사라진다', (tester) async {
    await _open(tester);
    await _beginEdit(tester);

    expect(find.byKey(const Key('goalsEditButton')), findsNothing);
    expect(find.byKey(const Key('mySettingsSaveRow')), findsOneWidget);
    expect(_field('goalCaloriesField'), findsOneWidget);
  });

  testWidgets('취소하면 고치던 값이 저장된 목표로 되돌아간다', (tester) async {
    await _open(tester);
    await _beginEdit(tester);

    await tester.enterText(_field('goalCaloriesField'), '2500');
    await tester.pump();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.text('2500'), findsNothing);
    expect(find.text('1800'), findsOneWidget);

    // 다시 열어도 버린 값이 남아 있지 않다.
    await _beginEdit(tester);
    expect(
      tester.widget<TextField>(_field('goalCaloriesField')).controller!.text,
      '1800',
    );
  });
}
