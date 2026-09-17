/// 내 프로필 저장이 **말한 값만** 바꾸는가. (#1941)
///
/// 세 자리가 있었다.
///  * 키·몸무게를 비우고 저장하면 저장소가 그 키를 통째로 빼, 서버가
///    "손대지 않음"으로 읽어 지운 값이 되살아났다.
///  * 같은 칸에 입력 필터가 없어 `70kg` 같은 붙여넣기가 조용히 무시됐다.
///  * 성별을 고른 적 없는 회원이 전화번호만 고쳐도 `male` 이 저장됐다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 마지막으로 받은 인자를 그대로 붙들어 두는 저장소.
class _RecordingAccountRepository extends MockAccountRepository {
  _RecordingAccountRepository({super.profile});

  int saves = 0;
  String? lastGender;
  MeasureUpdate? lastHeight;
  MeasureUpdate? lastWeight;

  @override
  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    MeasureUpdate? heightCm,
    MeasureUpdate? weightKg,
    String? goals,
  }) {
    saves++;
    lastGender = gender;
    lastHeight = heightCm;
    lastWeight = weightKg;
    return super.updateProfile(
      name: name,
      email: email,
      phone: phone,
      birthDate: birthDate,
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      goals: goals,
    );
  }
}

const Key _phone = ValueKey<String>('my-profile-phone');
const Key _height = ValueKey<String>('my-profile-height');
const Key _weight = ValueKey<String>('my-profile-weight');
const Key _genderFemale = ValueKey<String>('profile-gender-female');

Future<(AppLocalizations, _RecordingAccountRepository)> _openProfile(
  WidgetTester tester, {
  UserProfile? profile,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final _RecordingAccountRepository repository = profile == null
      ? _RecordingAccountRepository()
      : _RecordingAccountRepository(profile: profile);
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
        home: const ProfileSettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    AppLocalizations.of(tester.element(find.byType(ProfileSettingsPage))),
    repository,
  );
}

Future<void> _save(WidgetTester tester, AppLocalizations l) async {
  await tester.ensureVisible(find.text(l.mySave));
  await tester.tap(find.text(l.mySave));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('키를 비우고 저장하면 지움으로 나간다', (WidgetTester tester) async {
    final (AppLocalizations l, _RecordingAccountRepository repo) =
        await _openProfile(tester, profile: _profileWith(gender: 'male'));

    await tester.enterText(find.byKey(_height), '');
    await _save(tester, l);

    expect(repo.saves, 1);
    expect(repo.lastHeight, const MeasureUpdate.clear());
    // 손대지 않은 몸무게는 적힌 값 그대로 나간다 — 지움이 아니다.
    expect(repo.lastWeight?.value, isNotNull);
  });

  testWidgets('적어 넣은 키는 값으로 나간다', (WidgetTester tester) async {
    final (AppLocalizations l, _RecordingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_height), '172.5');
    await _save(tester, l);

    expect(repo.lastHeight, const MeasureUpdate(172.5));
  });

  testWidgets('단위가 붙은 값은 칸에 들어오지 않는다', (WidgetTester tester) async {
    await _openProfile(tester);

    await tester.enterText(find.byKey(_weight), '70kg');
    await tester.pump();

    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(_weight),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '70',
    );
  });

  testWidgets('범위를 벗어난 키는 저장을 보내지 않고 칸 아래에 알린다', (WidgetTester tester) async {
    final (AppLocalizations l, _RecordingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_height), '400');
    await _save(tester, l);

    expect(repo.saves, 0);
    expect(find.text(l.myGoalRange(50, 300)), findsOneWidget);
  });

  testWidgets('성별을 고른 적 없으면 보내지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, _RecordingAccountRepository repo) =
        await _openProfile(tester, profile: _profileWith(gender: ''));

    await tester.enterText(find.byKey(_phone), '010-1234-5678');
    await _save(tester, l);

    expect(repo.saves, 1);
    expect(repo.lastGender, isNull, reason: '고른 적 없는 성별을 굳히지 않는다');
  });

  testWidgets('성별을 고르면 그 값이 나간다', (WidgetTester tester) async {
    final (AppLocalizations l, _RecordingAccountRepository repo) =
        await _openProfile(tester, profile: _profileWith(gender: ''));

    await tester.ensureVisible(find.byKey(_genderFemale));
    await tester.tap(find.byKey(_genderFemale));
    await tester.pumpAndSettle();
    await _save(tester, l);

    expect(repo.lastGender, 'female');
  });

  testWidgets('이미 고른 적 있으면 고치지 않아도 그대로 나간다', (WidgetTester tester) async {
    final (AppLocalizations l, _RecordingAccountRepository repo) =
        await _openProfile(tester, profile: _profileWith(gender: 'female'));

    await _save(tester, l);

    expect(repo.lastGender, 'female');
  });
}

/// 키·몸무게가 이미 채워져 있고 성별만 갈아 끼운 프로필.
UserProfile _profileWith({required String gender}) => UserProfile(
  id: 'user-7d4e9a2c5f18',
  name: '김민수',
  email: 'minsu@oncare.com',
  phone: '010-1234-5678',
  birthDate: '1990-01-15',
  gender: gender,
  heightCm: 175,
  weightKg: 70,
);
