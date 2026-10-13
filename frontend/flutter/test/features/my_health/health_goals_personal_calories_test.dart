import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

/// MY 건강 목표가 회원 정보로 낸 권장 칼로리를 권하고, 받아들이면 목표가 된다. (#2144)
///
/// 흐린 기준선(2000)은 그대로다 — 목표 없는 회원을 홈·식단 탭이 실제로 견주는
/// 값이라, MY 만 다른 수를 말하면 화면끼리 어긋난다. 권장 칼로리는 온보딩과
/// 같은 계산이고, 회원이 버튼을 누르고 저장했을 때만 목표로 굳는다.

const Key _apply = Key('goalApplyPersonalCalories');

Future<MockAccountRepository> _open(
  WidgetTester tester,
  UserProfile profile, {
  bool edit = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final MockAccountRepository repository = MockAccountRepository(
    profile: profile,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repository),
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
  if (edit) {
    await tester.tap(find.byKey(const Key('goalsEditButton')));
    await tester.pumpAndSettle();
  }
  return repository;
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).controller!.text;

Future<void> _tapApply(WidgetTester tester) async {
  final Finder button = find.byKey(_apply);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final Finder saveButton = find.text('저장');
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  // 저장 알림 배너는 3초 뒤 스스로 닫힌다.
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// 권장 안내 줄의 전체 문구 — 항목마다 따로 세운 Text 를 붙여 읽는다(#2140).
String _note(WidgetTester tester, String marker) {
  final Finder wrap = find
      .ancestor(of: find.textContaining(marker), matching: find.byType(Wrap))
      .first;
  return tester
      .widgetList<Text>(find.descendant(of: wrap, matching: find.byType(Text)))
      .map((Text t) => t.data!)
      .join();
}

/// 30세 남성 175cm 70kg — 칼로리 목표는 세운 적 없다.
UserProfile _member({
  String birthDate = '1996-01-01',
  double? heightCm = 175,
  double? weightKg = 70,
  String conditions = '',
  int? dailyCalories,
}) => UserProfile(
  id: 'member',
  name: '김민수',
  email: 'minsu@oncare.com',
  birthDate: birthDate,
  gender: 'male',
  heightCm: heightCm,
  weightKg: weightKg,
  conditions: conditions,
  dailyCalories: dailyCalories,
);

/// 온보딩이 같은 회원에게 미리 채우는 권장값 — 화면이 이 숫자를 말해야 한다.
RecommendedGoals _onboarding(UserProfile p, {Set<String> focus = const {}}) =>
    recommendedGoalsFor(
      ageYears: ageFromBirthDate(p.birthDate, today: todayKst()),
      gender: p.gender,
      heightCm: p.heightCm,
      weightKg: p.weightKg,
      focus: focus,
    );

void main() {
  testWidgets('회원 정보로 낸 권장 칼로리를 온보딩과 같은 숫자로 권한다', (tester) async {
    final UserProfile member = _member();
    await _open(tester, member);

    final RecommendedGoals expected = _onboarding(member);
    expect(expected.isPersonalized, isTrue);
    expect(expected.dailyCalories, isNot(UserProfile.defaultDailyCalories));
    expect(
      _note(tester, '내 정보로 계산한 권장'),
      '내 정보로 계산한 권장: 하루 ${expected.dailyCalories}kcal · '
      '탄·단·지·당류도 이 칼로리에 맞춰 채워요',
    );
    // 칸에 채워 둔 값은 여전히 기준선이다 — 버튼을 누르기 전에는 바꾸지 않는다.
    expect(_text(tester, 'goalCaloriesField'), '2000');
  });

  testWidgets('적용하면 칼로리와 탄·단·지·당류를 그 칼로리 기준으로 채운다', (tester) async {
    final UserProfile member = _member();
    await _open(tester, member);
    await _tapApply(tester);

    final RecommendedGoals expected = _onboarding(member);
    expect(_text(tester, 'goalCaloriesField'), '${expected.dailyCalories}');
    expect(_text(tester, 'goalCarbsField'), '${expected.dailyCarbsG}');
    expect(_text(tester, 'goalProteinField'), '${expected.dailyProteinG}');
    expect(_text(tester, 'goalFatField'), '${expected.dailyFatG}');
    expect(_text(tester, 'goalSugarField'), '${expected.dailySugarG}');
    // 칼로리는 회원이 받아들인 권장값이지 탄단지에서 다시 센 값이 아니다.
    expect(find.text('탄·단·지 목표로 계산한 값이에요'), findsNothing);
  });

  testWidgets('적용하고 저장하면 null 이 아니라 실제 목표로 저장된다', (tester) async {
    final UserProfile member = _member();
    final MockAccountRepository repository = await _open(tester, member);
    await _tapApply(tester);
    await _save(tester);

    final RecommendedGoals expected = _onboarding(member);
    final UserProfile saved = await repository.fetchProfile();
    expect(saved.dailyCalories, expected.dailyCalories);
    expect(saved.dailyCarbsG, expected.dailyCarbsG);
    expect(saved.dailyProteinG, expected.dailyProteinG);
    expect(saved.dailyFatG, expected.dailyFatG);
    expect(saved.dailySugarG, expected.dailySugarG);
  });

  testWidgets('고른 건강 목표도 온보딩과 같이 반영한다', (tester) async {
    final UserProfile member = _member(conditions: '체중 감량');
    await _open(tester, member);

    final RecommendedGoals expected = _onboarding(
      member,
      focus: const <String>{'체중 감량'},
    );
    expect(expected.dailyCalories, lessThan(_onboarding(member).dailyCalories));
    expect(
      _note(tester, '내 정보로 계산한 권장'),
      contains('하루 ${expected.dailyCalories}kcal'),
    );
  });

  testWidgets('목표가 이미 저장된 회원에게도 권장 줄이 보인다', (tester) async {
    await _open(tester, _member(dailyCalories: 2400));

    expect(find.byKey(_apply), findsOneWidget);
    expect(_text(tester, 'goalCaloriesField'), '2400');
  });

  testWidgets('나이·키·체중이 모자라면 권장 줄을 띄우지 않는다', (tester) async {
    await _open(tester, _member(weightKg: null));
    expect(find.byKey(_apply), findsNothing);
  });

  testWidgets('생년월일을 읽을 수 없어도 띄우지 않는다', (tester) async {
    await _open(tester, _member(birthDate: ''));
    expect(find.byKey(_apply), findsNothing);
  });

  testWidgets('보기 모드에서는 권장 줄이 없고 흐린 기준선은 2000 그대로다', (tester) async {
    await _open(tester, _member(), edit: false);

    expect(find.byKey(_apply), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('goalValue-kcal'))).data,
      '${UserProfile.defaultDailyCalories}',
    );
  });
}
