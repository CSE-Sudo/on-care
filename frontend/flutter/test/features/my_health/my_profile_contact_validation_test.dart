/// 내 프로필의 이름·이메일·전화번호·생년월일 형식 검사 (#1883·#1887).
///
/// 이 화면은 **로그인하는 이메일**을 고치는 자리다. 전에는 칸 검사가 없어
/// `asdf` 도 그대로 저장됐고, 그러면 그 회원은 원래 주소로 다시 로그인할 수
/// 없었다(비밀번호 찾기 경로도 없다).
///
/// 서버도 같은 기준으로 막지만(#1883), 거기서 걸리면 화면에는 이유를 알 수 없는
/// "저장에 실패했어요" 토스트만 남는다 — 어느 칸이 문제인지는 여기서만 말해
/// 줄 수 있다. 그래서 **보내기 전에 막는가**를 확인한다.
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
import 'package:oncare_ui/oncare_ui.dart';

/// 저장이 실제로 불렸는지 세는 저장소.
class _CountingAccountRepository extends MockAccountRepository {
  _CountingAccountRepository({super.profile});

  int saves = 0;

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

const Key _name = ValueKey<String>('my-profile-name');
const Key _email = ValueKey<String>('my-profile-email');
const Key _phone = ValueKey<String>('my-profile-phone');
const Key _birth = ValueKey<String>('my-profile-birth');

Future<(AppLocalizations, _CountingAccountRepository)> _openProfile(
  WidgetTester tester, {
  UserProfile? profile,
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final _CountingAccountRepository repository = profile == null
      ? _CountingAccountRepository()
      : _CountingAccountRepository(profile: profile);
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
  await tester.tap(find.byKey(const Key('profileEditButton')));
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
  testWidgets('이메일이 형식에 맞지 않으면 저장을 보내지 않고 칸 아래에 알린다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'asdf');
    await _save(tester, l);

    expect(find.text(l.authEmailInvalid), findsOneWidget);
    expect(repo.saves, 0, reason: '형식이 틀린 이메일은 서버로 보내지 않는다');
  });

  testWidgets('이메일 칸을 비워도 저장을 보내지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_email), '');
    await _save(tester, l);

    expect(find.text(l.authEmailEmpty), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets('전화번호는 숫자만 쳐도 하이픈이 붙고 그대로 저장된다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_phone), '01098765432');
    await tester.pump();
    expect(find.text('010-9876-5432'), findsOneWidget);

    await _save(tester, l);
    expect(repo.saves, 1);
  });

  testWidgets('자릿수가 맞아도 010 으로 시작하지 않으면 저장을 보내지 않는다', (
    WidgetTester tester,
  ) async {
    // 끊어 주기만 하던 때는 아무 숫자 11자리나 그대로 저장됐다 — 트레이너가
    // 담당 회원에게 연락할 때 보는 값이라 걸 수 없으면 없는 것과 같다.
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_phone), '12345678901');
    await tester.pump();
    expect(find.text('123-4567-8901'), findsOneWidget);

    await _save(tester, l);

    expect(find.text(l.signUpPhoneFormatInvalid), findsOneWidget);
    expect(repo.saves, 0);

    await tester.enterText(find.byKey(_phone), '01012345678');
    await tester.pump();
    expect(find.text(l.signUpPhoneFormatInvalid), findsNothing);

    await _save(tester, l);
    expect(repo.saves, 1);
  });

  testWidgets('전화번호가 모자라면 저장을 보내지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_phone), '0101234');
    await _save(tester, l);

    expect(find.text(l.signUpPhoneFormatInvalid), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets('있던 전화번호는 지울 수 없다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_phone), '');
    await _save(tester, l);

    expect(find.text(l.signUpPhoneFormatInvalid), findsOneWidget);
    expect(repo.saves, 0, reason: '가입이 필수로 받은 값을 여기서 비우면 트레이너가 연락할 방법이 사라진다');
  });

  testWidgets('처음부터 전화번호가 없던 회원은 빈 칸으로 저장할 수 있다', (WidgetTester tester) async {
    // 소셜 로그인 가입자와 #1634 이전 가입자가 이 상태다 — 연락처를 넣을
    // 자리가 없었다. 이름만 고치려는데 전화번호로 막으면 안 된다.
    final (
      AppLocalizations l,
      _CountingAccountRepository repo,
    ) = await _openProfile(
      tester,
      profile: const UserProfile(
        id: 'no-phone',
        name: '연락처없음',
        email: 'nophone@oncare.com',
      ),
    );

    expect(find.text(l.signUpPhoneFormatInvalid), findsNothing);
    await _save(tester, l);

    expect(find.text(l.signUpPhoneFormatInvalid), findsNothing);
    expect(repo.saves, 1);
  });

  testWidgets('오류를 보인 뒤 칸을 고치면 문구가 사라진다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'asdf');
    await _save(tester, l);
    expect(find.text(l.authEmailInvalid), findsOneWidget);

    await tester.enterText(find.byKey(_email), 'minsu@oncare.com');
    await tester.pump();
    expect(find.text(l.authEmailInvalid), findsNothing);
  });

  // ---- 이름·생년월일 (#1887) ----

  testWidgets('이름을 비우면 저장을 보내지 않는다', (WidgetTester tester) async {
    // 가입이 필수로 받은 값이다. 비운 채 저장되면 그 회원은 트레이너
    // 로스터·채팅·상담 카드에 공백으로 뜬다.
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_name), '   ');
    await _save(tester, l);

    expect(find.text(l.signUpNameEmpty), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets('이름이 상한을 넘으면 저장을 보내지 않는다', (WidgetTester tester) async {
    // 서버는 422 로 되돌린다 — 전에는 컬럼 길이를 넘겨 500 이었다.
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(
      find.byKey(_name),
      '가' * (AppInputRules.nameMaxLength + 1),
    );
    await _save(tester, l);

    expect(find.text(l.signUpNameTooLong), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets('생년월일이 날짜가 아니면 저장을 보내지 않는다', (WidgetTester tester) async {
    // 저장되면 트레이너의 담당 요청 확인 화면에서 나이가 조용히 비어 보인다.
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_birth), '1990-13-45');
    await _save(tester, l);

    expect(find.text(l.myFieldBirthInvalid), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets('생년월일은 비워 둘 수 있다', (WidgetTester tester) async {
    // 넣을 자리가 없던 시절에 가입한 회원과 소셜 로그인 가입자에게는 처음부터
    // 없는 값이다. 서버도 빈 값은 받는다(#1887).
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_birth), '');
    await _save(tester, l);

    expect(find.text(l.myFieldBirthInvalid), findsNothing);
    expect(repo.saves, 1);
  });
}
