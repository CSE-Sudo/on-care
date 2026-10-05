/// 내 프로필 저장이 거절되면 이유를 칸 아래와 토스트로 말한다 — #2639.
///
/// 예전에는 이미 다른 계정이 쓰는 이메일로 저장해도 "저장에 실패했어요. 잠시 후
/// 다시 시도해 주세요" 만 떴다. 같은 값으로 몇 번을 다시 눌러도 막히는데 화면은
/// 다시 해 보라고 했다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';
import 'package:oncare/features/account/domain/entities/profile_update_rejected.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart'
    show ReissuedTokens;
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

/// 저장 호출을 세고, 정해 두면 그 예외로 거절하는 저장소.
class _ScriptedAccountRepository extends MockAccountRepository {
  _ScriptedAccountRepository({super.profile, super.takenEmails});

  int saves = 0;

  /// 채워 두면 저장을 이 예외로 거절한다(한 번 쓰고 비운다).
  Object? failNext;

  @override
  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    MeasureUpdate? heightCm,
    MeasureUpdate? weightKg,
    AccountReauth? reauth,
    String? emailCode,
    void Function(ReissuedTokens tokens)? onTokensReissued,
  }) {
    saves++;
    final Object? failure = failNext;
    if (failure != null) {
      failNext = null;
      return Future<UserProfile>.error(failure);
    }
    return super.updateProfile(
      name: name,
      email: email,
      phone: phone,
      birthDate: birthDate,
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      reauth: reauth,
      emailCode: emailCode,
      onTokensReissued: onTokensReissued,
    );
  }
}

const Key _email = ValueKey<String>('my-profile-email');
const Key _phone = ValueKey<String>('my-profile-phone');

Future<(AppLocalizations, _ScriptedAccountRepository)> _openProfile(
  WidgetTester tester, {
  UserProfile? profile,
  Set<String> takenEmails = const <String>{'trainer@oncare.com'},
  Locale locale = const Locale('ko'),
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final _ScriptedAccountRepository repository = profile == null
      ? _ScriptedAccountRepository(takenEmails: takenEmails)
      : _ScriptedAccountRepository(profile: profile, takenEmails: takenEmails);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
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

/// 이름만 고친다 — 바꾼 칸이 있어야 저장이 나간다(#2655). 거절 처리를 보는
/// 테스트가 요청 없이 끝나지 않게 한다.
Future<void> _editName(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('my-profile-name')),
    '이름고침',
  );
  await tester.pump();
}

Future<void> _save(WidgetTester tester, AppLocalizations l) async {
  await tester.ensureVisible(find.text(l.mySave));
  await tester.tap(find.text(l.mySave));
  await tester.pumpAndSettle();
  // 이메일을 바꾼 저장은 새 주소 인증(#3230)과 본인 확인 창(#3039)을 거친다.
  // 이 파일은 그 뒤의 거절 처리를 보므로 데모 코드와 현재 비밀번호를 적고
  // 넘어간다.
  final Finder code = find.byKey(const ValueKey<String>('email-change-code'));
  if (code.evaluate().isNotEmpty) {
    await tester.enterText(code, '000000');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('email-change-code-confirm')),
    );
    await tester.pumpAndSettle();
  }
  final Finder password = find.byKey(const ValueKey<String>('reauth-password'));
  if (password.evaluate().isNotEmpty) {
    await tester.enterText(password, 'pw-current-1');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('reauth-confirm')));
    await tester.pumpAndSettle();
  }
}

Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(OnCareMotion.toastErrorVisible);
  await tester.pumpAndSettle();
}

String? _fieldError(WidgetTester tester, Key key) =>
    tester.widget<AppTextField>(find.byKey(key)).errorText;

void main() {
  testWidgets('이미 쓰이는 이메일이면 이메일 칸 아래와 토스트에 이유를 보인다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _ScriptedAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'trainer@oncare.com');
    await _save(tester, l);

    expect(repo.saves, 1);
    expect(_fieldError(tester, _email), l.myProfileEmailTaken);
    // 칸 아래 한 번, 토스트 한 번.
    expect(find.text(l.myProfileEmailTaken), findsNWidgets(2));
    expect(find.text(l.mySaveFailed), findsNothing);
    expect(find.text(l.myProfileSaved), findsNothing);
    await _drainToast(tester);

    // 토스트가 사라져도 칸 아래 이유는 남고, 편집 상태가 유지된다.
    expect(_fieldError(tester, _email), l.myProfileEmailTaken);
    expect(find.text(l.mySave), findsOneWidget);
  });

  testWidgets('가입 화면의 이미 가입된 이메일 문구는 쓰지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'trainer@oncare.com');
    await _save(tester, l);

    expect(find.text(l.signUpEmailTaken), findsNothing);
    await _drainToast(tester);
  });

  testWidgets('이메일을 고치면 칸 아래 이유가 사라지고, 되돌리면 다시 뜬다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _) = await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'trainer@oncare.com');
    await _save(tester, l);
    await _drainToast(tester);
    expect(_fieldError(tester, _email), l.myProfileEmailTaken);

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await tester.pump();
    expect(_fieldError(tester, _email), isNull);

    await tester.enterText(find.byKey(_email), 'Trainer@oncare.com');
    await tester.pump();
    expect(_fieldError(tester, _email), l.myProfileEmailTaken);
  });

  testWidgets('거절된 이메일 그대로 다시 누르면 서버에 다시 보내지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, _ScriptedAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'trainer@oncare.com');
    await _save(tester, l);
    await _drainToast(tester);
    expect(repo.saves, 1);

    await _save(tester, l);
    expect(repo.saves, 1, reason: '같은 값은 또 막힌다 — 칸 아래 이유로 충분하다');
    expect(_fieldError(tester, _email), l.myProfileEmailTaken);
  });

  testWidgets('이메일을 고쳐 다시 저장하면 저장된다', (WidgetTester tester) async {
    final (AppLocalizations l, _ScriptedAccountRepository repo) =
        await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'trainer@oncare.com');
    await _save(tester, l);
    await _drainToast(tester);

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _save(tester, l);

    expect(repo.saves, 2);
    expect(find.text(l.myProfileSaved), findsOneWidget);
    expect((await repo.fetchProfile()).email, 'minsu.new@oncare.com');
    await _drainToast(tester);
  });

  testWidgets('편집을 다시 열면 앞서 거절된 이유는 지워진다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'trainer@oncare.com');
    await _save(tester, l);
    await _drainToast(tester);

    await tester.ensureVisible(find.text(l.myCancel));
    await tester.tap(find.text(l.myCancel));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profileEditButton')));
    await tester.pumpAndSettle();

    expect(_fieldError(tester, _email), isNull);
  });

  testWidgets('서버가 연락처 비움으로 거절하면 전화번호 칸 아래에 알린다', (WidgetTester tester) async {
    // 화면이 들고 있던 프로필에는 연락처가 없어 칸 검사가 비움을 허용했지만,
    // 그사이 서버에는 연락처가 생긴 경우다.
    final (
      AppLocalizations l,
      _ScriptedAccountRepository repo,
    ) = await _openProfile(
      tester,
      profile: const UserProfile(
        id: 'stale',
        name: '낡은화면',
        email: 'stale@oncare.com',
      ),
    );
    repo.failNext = const ProfileUpdateRejected(
      ProfileUpdateRejection.phoneRequired,
    );

    await _editName(tester);
    await _save(tester, l);

    expect(_fieldError(tester, _phone), l.myProfilePhoneRequired);
    expect(find.text(l.myProfilePhoneRequired), findsNWidgets(2));
    await _drainToast(tester);

    await tester.enterText(find.byKey(_phone), '01012345678');
    await tester.pump();
    expect(_fieldError(tester, _phone), isNull);
  });

  testWidgets('형식 오류로 거절되면 입력을 확인하라는 토스트를 띄운다', (WidgetTester tester) async {
    final (AppLocalizations l, _ScriptedAccountRepository repo) =
        await _openProfile(tester);
    repo.failNext = const ProfileUpdateRejected(ProfileUpdateRejection.invalid);

    await _editName(tester);
    await _save(tester, l);

    expect(find.text(l.myProfileInvalid), findsOneWidget);
    expect(find.text(l.mySaveFailed), findsNothing);
    expect(_fieldError(tester, _email), isNull);
    await _drainToast(tester);
  });

  testWidgets('이유 없는 실패는 지금처럼 저장 실패 토스트다', (WidgetTester tester) async {
    final (AppLocalizations l, _ScriptedAccountRepository repo) =
        await _openProfile(tester);
    repo.failNext = StateError('네트워크 없음');

    await _editName(tester);
    await _save(tester, l);

    expect(find.text(l.mySaveFailed), findsOneWidget);
    expect(find.text(l.myProfileEmailTaken), findsNothing);
    await _drainToast(tester);
  });

  testWidgets('영어 화면에서는 영어 문구로 알린다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _openProfile(
      tester,
      locale: const Locale('en'),
    );

    await tester.enterText(find.byKey(_email), 'trainer@oncare.com');
    await _save(tester, l);

    expect(_fieldError(tester, _email), 'That email is already in use');
    await _drainToast(tester);
  });
}
