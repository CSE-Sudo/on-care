/// 트레이너 계정 탈퇴. (#505)
///
/// 되돌릴 수 없는 동작이라 확인 절차가 형식만 남으면 안 된다 — 담당 회원 연결과
/// 예약이 함께 사라지고 회원에게는 알림이 간다. 확인은 화면의 이름이 아니라
/// 본인 확인(현재 비밀번호, 소셜로만 가입했으면 소셜 재로그인)이다(#3039).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/data/repositories/mock_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/my/data/trainer_account_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 문구 기대값은 로케일을 명시해 읽는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

/// 탈퇴 호출을 기록하는 페이크.
class _FakeAccountRepository implements TrainerAccountRepository {
  _FakeAccountRepository({this.supportsDeletion = true, this.error});

  @override
  final bool supportsDeletion;

  /// 탈퇴 요청이 던질 실패. 한 번 던지고 나면 지운다 — 고쳐 다시 보내는 흐름을
  /// 보려고.
  Object? error;
  int deleteCalls = 0;
  List<String> lastReasons = const <String>[];
  TrainerReauth? lastReauth;

  @override
  bool get supportsPasswordChange => true;

  @override
  Future<TrainerAuthTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => null;

  @override
  Future<void> deleteAccount({
    required TrainerReauth reauth,
    List<String> reasons = const <String>[],
  }) async {
    deleteCalls++;
    lastReauth = reauth;
    lastReasons = reasons;
    final Object? e = error;
    if (e != null) {
      error = null;
      throw e;
    }
  }
}

/// 소셜로만 가입한 트레이너(#3039) — `/trainer/me` 의 `has_password` 가 false.
class _SocialOnlyAuthRepository extends MockTrainerAuthRepository {
  const _SocialOnlyAuthRepository();

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async =>
      seedTrainerProfileFor(DemoLanguage.ko).copyWith(hasPassword: false);
}

/// 탈퇴는 설정이 아니라 그 아래 고객 지원 화면에 있다(#2227) — 약관·개인정보
/// 다음, 계정을 정리하는 줄로 묶인다.
Future<(_FakeAccountRepository, ProviderContainer)> _pumpSettings(
  WidgetTester tester, {
  bool supportsDeletion = true,
  Object? error,
  bool socialOnly = false,
  Locale locale = const Locale('ko'),
}) async {
  final repo = _FakeAccountRepository(
    supportsDeletion: supportsDeletion,
    error: error,
  );
  final ProviderContainer container = await pumpTrainerApp(
    tester,
    token: 'demo-token',
    at: '${AppRoutes.my}?t=support',
    locale: locale,
    extraOverrides: <Override>[
      trainerAccountRepositoryProvider.overrideWithValue(repo),
      if (socialOnly)
        trainerAuthRepositoryProvider.overrideWithValue(
          const _SocialOnlyAuthRepository(),
        ),
    ],
  );
  return (repo, container);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder target = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

/// 고객 지원의 탈퇴 줄 → 사유(건너뜀) → 탈퇴하기 전에 → 탈퇴 계속까지 간다.
/// 회원 앱과 같은 두 칸을 지나야 마지막 확인창이 뜬다(#2264).
Future<void> _tapDelete(WidgetTester tester) async {
  await _tap(tester, 'delete-account');
  await _tap(tester, 'withdraw-next');
  await _tap(tester, 'withdraw-continue');
}

final Finder _submit = find.byKey(
  const ValueKey<String>('delete-account-submit'),
);
final Finder _passwordField = find.byKey(
  const ValueKey<String>('delete-account-password'),
);

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<AppButton>(_submit).onPressed != null;

Future<void> _enterPassword(WidgetTester tester, String value) async {
  await tester.enterText(
    find.descendant(of: _passwordField, matching: find.byType(TextField)),
    value,
  );
  await settle(tester);
}

void main() {
  testWidgets('고객 지원에 탈퇴 진입점이 있다', (tester) async {
    await _pumpSettings(tester);

    expect(find.text(_ko.myDeleteAccount), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('delete-account')),
      findsOneWidget,
    );
  });

  testWidgets('지울 계정이 없는 빌드에서는 비활성이고 사유를 보여 준다', (tester) async {
    await _pumpSettings(tester, supportsDeletion: false);

    expect(find.text(_ko.myDeleteDemo), findsOneWidget);
    final row = tester.widget<AppListRow>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('delete-account')),
        matching: find.byType(AppListRow),
      ),
    );
    expect(row.onTap, isNull);
  });

  // --- 비밀번호 본인 확인 (#3039) -------------------------------------------

  testWidgets('이름 대신 현재 비밀번호 칸이 있고, 비어 있으면 탈퇴가 눌리지 않는다', (tester) async {
    final (repo, _) = await _pumpSettings(tester);

    await _tapDelete(tester);
    expect(find.text(_ko.myDeleteTitle), findsOneWidget);
    expect(_passwordField, findsOneWidget);
    expect(find.text(_ko.myDeleteReauthPrompt), findsOneWidget);
    // 예전 이름 확인 칸은 없다.
    expect(
      find.byKey(const ValueKey<String>('delete-account-confirm')),
      findsNothing,
    );
    // 비밀번호는 가려서 받는다.
    final TextField field = tester.widget<TextField>(
      find.descendant(of: _passwordField, matching: find.byType(TextField)),
    );
    expect(field.obscureText, isTrue);

    expect(_submitEnabled(tester), isFalse);
    await tester.tap(_submit);
    await settle(tester);
    expect(repo.deleteCalls, 0);

    await _enterPassword(tester, 'current-pw-1');
    expect(_submitEnabled(tester), isTrue);

    await _enterPassword(tester, '');
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets('입력한 현재 비밀번호를 탈퇴 요청에 싣는다', (tester) async {
    final (repo, _) = await _pumpSettings(tester);

    await _tapDelete(tester);
    await _enterPassword(tester, 'current-pw-1');
    await _tap(tester, 'delete-account-submit');

    expect(repo.deleteCalls, 1);
    expect(
      repo.lastReauth,
      isA<PasswordReauth>().having(
        (r) => r.currentPassword,
        'currentPassword',
        'current-pw-1',
      ),
    );
  });

  testWidgets('취소하면 아무 일도 일어나지 않는다', (tester) async {
    final (repo, _) = await _pumpSettings(tester);

    await _tapDelete(tester);
    await tester.tap(find.text(_ko.actionCancel));
    await settle(tester);

    expect(repo.deleteCalls, 0);
    expect(find.text(_ko.myDeleteTitle), findsNothing);
  });

  for (final MapEntry<ReauthFailure, String> c in <ReauthFailure, String>{
    ReauthFailure.invalidPassword: _ko.myDeleteReauthWrongPassword,
    ReauthFailure.required: _ko.myPwCurrentRequired,
  }.entries) {
    testWidgets('본인 확인이 거절되면(${c.key.name}) 창 안에 알리고 로그아웃하지 않는다', (
      tester,
    ) async {
      final (repo, container) = await _pumpSettings(
        tester,
        error: ReauthRejected(c.key),
      );

      await _tapDelete(tester);
      await _enterPassword(tester, 'wrong-pw-1');
      await _tap(tester, 'delete-account-submit');

      expect(repo.deleteCalls, 1);
      // 비밀번호 칸 아래에 그린다 — 토스트가 아니다.
      expect(
        find.descendant(of: _passwordField, matching: find.text(c.value)),
        findsOneWidget,
      );
      // 창은 그대로, 세션도 그대로다 — 400 은 토큰이 아직 유효하다는 뜻이다.
      expect(find.text(_ko.myDeleteTitle), findsOneWidget);
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(Uri.parse(currentLocation(tester)).path, AppRoutes.my);

      // 고치기 시작하면 문구가 사라지고, 다시 보내면 탈퇴된다.
      await _enterPassword(tester, 'current-pw-1');
      expect(find.text(c.value), findsNothing);
      await _tap(tester, 'delete-account-submit');
      expect(repo.deleteCalls, 2);
      expect(Uri.parse(currentLocation(tester)).path, AppRoutes.signIn);
    });
  }

  testWidgets('그 밖의 실패는 서버 사유를 창 안에 알린다', (tester) async {
    await _pumpSettings(
      tester,
      error: const ServerError(message: '지금은 탈퇴할 수 없어요'),
    );

    await _tapDelete(tester);
    await _enterPassword(tester, 'current-pw-1');
    await _tap(tester, 'delete-account-submit');

    expect(find.text('지금은 탈퇴할 수 없어요'), findsOneWidget);
    expect(find.text(_ko.myDeleteTitle), findsOneWidget);
  });

  testWidgets('영어 화면은 영어 안내·영어 오류를 쓴다', (tester) async {
    await _pumpSettings(
      tester,
      locale: const Locale('en'),
      error: const ReauthRejected(ReauthFailure.invalidPassword),
    );

    await _tapDelete(tester);
    expect(find.text(_en.myDeleteReauthPrompt), findsOneWidget);

    await _enterPassword(tester, 'wrong-pw-1');
    await _tap(tester, 'delete-account-submit');
    expect(find.text(_en.myDeleteReauthWrongPassword), findsOneWidget);
  });

  testWidgets('회원 앱처럼 사유를 고르면 탈퇴하기 전에 그 답을 보여 준다', (tester) async {
    await _pumpSettings(tester);

    final Finder row = find.byKey(const ValueKey<String>('delete-account'));
    await tester.ensureVisible(row);
    await settle(tester);
    await tester.tap(row);
    await settle(tester);
    expect(find.text(_ko.myWithdrawReasonTitle), findsOneWidget);

    await _tap(tester, 'withdraw-reason-leavingWork');
    await _tap(tester, 'withdraw-next');

    expect(find.text(_ko.myWithdrawKeepTitle), findsWidgets);
    expect(find.text(_ko.myWithdrawKeepLeavingWork), findsOneWidget);

    // 계속 사용하기를 누르면 고객 지원으로 돌아간다.
    await _tap(tester, 'withdraw-stay');
    expect(currentLocation(tester), AppRoutes.mySection('support'));
  });

  testWidgets('고른 사유를 탈퇴 요청에 실어 보낸다 (#2264)', (tester) async {
    final (repo, _) = await _pumpSettings(tester);

    await _tap(tester, 'delete-account');
    await _tap(tester, 'withdraw-reason-leavingWork');
    await _tap(tester, 'withdraw-reason-missingFeature');
    await _tap(tester, 'withdraw-next');
    await _tap(tester, 'withdraw-continue');
    await _enterPassword(tester, 'current-pw-1');
    await _tap(tester, 'delete-account-submit');

    expect(repo.deleteCalls, 1);
    // 화면에 보이는 순서가 아니라 사유 목록 순서다 — 서버 코드 그대로.
    expect(repo.lastReasons, <String>['missing_feature', 'leaving_work']);
  });

  testWidgets('탈퇴하면 로그인 화면 주소에 탈퇴 화면이 실리지 않는다 (#2765)', (tester) async {
    final (repo, _) = await _pumpSettings(tester);

    await _tapDelete(tester);
    await _enterPassword(tester, 'current-pw-1');
    await _tap(tester, 'delete-account-submit');

    expect(repo.deleteCalls, 1);
    final String location = currentLocation(tester);
    expect(Uri.parse(location).path, AppRoutes.signIn);
    // 다음에 로그인하는 사람이 탈퇴 화면으로 이어 가지 않는다.
    expect(AppRoutes.resumeTarget(location), isNull);
    expect(Uri.parse(location).queryParameters, isEmpty);
  });

  // --- 소셜로만 가입한 계정 (#3039) -----------------------------------------

  testWidgets('소셜 계정은 비밀번호 칸 대신 소셜 재로그인을 받는다', (tester) async {
    final (repo, _) = await _pumpSettings(tester, socialOnly: true);

    await _tapDelete(tester);

    expect(_passwordField, findsNothing);
    expect(find.text(_ko.myDeleteReauthSocialPrompt), findsOneWidget);
    expect(find.text(_ko.myDeleteReauthSocialAction), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('delete-account-reauth-kakao')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('delete-account-reauth-google')),
      findsOneWidget,
    );
    // 다시 로그인하기 전에는 탈퇴가 눌리지 않는다.
    expect(_submitEnabled(tester), isFalse);

    await _tap(tester, 'delete-account-reauth-kakao');
    expect(
      find.byKey(const ValueKey<String>('delete-account-social-done')),
      findsOneWidget,
    );
    expect(_submitEnabled(tester), isTrue);

    await _tap(tester, 'delete-account-submit');
    expect(repo.deleteCalls, 1);
    // 로그인 화면의 소셜 로그인과 같은 경로로 받은 토큰이다.
    expect(
      repo.lastReauth,
      isA<SocialReauth>()
          .having((r) => r.provider, 'provider', 'kakao')
          .having((r) => r.token, 'token', 'demo-kakao-token'),
    );
    expect(Uri.parse(currentLocation(tester)).path, AppRoutes.signIn);
  });

  testWidgets('소셜 확인이 거절되면 창 안에 알리고 다시 로그인하게 한다', (tester) async {
    final (repo, container) = await _pumpSettings(
      tester,
      socialOnly: true,
      error: const ReauthRejected(ReauthFailure.invalidSocial),
    );

    await _tapDelete(tester);
    await _tap(tester, 'delete-account-reauth-google');
    await _tap(tester, 'delete-account-submit');

    expect(repo.deleteCalls, 1);
    expect(find.text(_ko.myDeleteReauthSocialFailed), findsOneWidget);
    // 쓴 토큰은 버린다 — 다시 로그인해야 탈퇴가 눌린다.
    expect(_submitEnabled(tester), isFalse);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );

    await _tap(tester, 'delete-account-reauth-google');
    expect(_submitEnabled(tester), isTrue);
    await _tap(tester, 'delete-account-submit');
    expect(repo.deleteCalls, 2);
    expect(
      repo.lastReauth,
      isA<SocialReauth>().having((r) => r.provider, 'provider', 'google'),
    );
  });
}
