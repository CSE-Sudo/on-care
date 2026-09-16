/// 내 프로필의 이메일·전화번호 형식 검사 (#1883).
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
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 저장이 실제로 불렸는지 세는 저장소.
class _CountingAccountRepository extends MockAccountRepository {
  int saves = 0;

  @override
  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    num? heightCm,
    num? weightKg,
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

const Key _email = ValueKey<String>('my-profile-email');
const Key _phone = ValueKey<String>('my-profile-phone');

Future<(AppLocalizations, _CountingAccountRepository)> _openProfile(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final _CountingAccountRepository repository = _CountingAccountRepository();
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

  testWidgets('전화번호가 모자라면 저장을 보내지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_phone), '0101234');
    await _save(tester, l);

    expect(find.text(l.signUpPhoneFormatInvalid), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets('전화번호는 비워 둘 수 있다 — 가입과 다른 점이다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_phone), '');
    await _save(tester, l);

    expect(find.text(l.signUpPhoneFormatInvalid), findsNothing);
    expect(repo.saves, 1, reason: '연락처를 지우는 것은 할 수 있는 일이다');
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
}
