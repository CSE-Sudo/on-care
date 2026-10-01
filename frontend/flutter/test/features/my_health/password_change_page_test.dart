/// MY → 비밀번호 변경(#2824).
///
/// 보내기 전 칸 검사, 서버 실패 이유가 어느 칸에 붙는지, 성공하면 새 토큰으로
/// 이 기기의 세션을 갈아 끼우는지, 바꿀 수 없는 계정(데모·소셜)에서 이유를
/// 먼저 말하는지를 본다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/data/repositories/mock_password_repository.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart';
import 'package:oncare/features/auth/presentation/controllers/password_providers.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/password_change_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const String _current = 'old-pass-1';
const String _newPw = 'new-pass-2';

/// 받은 요청을 적고, 정해 둔 대로 답하는 리포지토리.
class _FakePasswordRepository implements PasswordRepository {
  _FakePasswordRepository({this.error, this.tokens});

  final PasswordChangeError? error;
  final ReissuedTokens? tokens;
  final List<(String, String)> calls = <(String, String)>[];

  @override
  bool get supportsPasswordChange => true;

  @override
  Future<ReissuedTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    calls.add((currentPassword, newPassword));
    final PasswordChangeError? e = error;
    if (e != null) throw e;
    return tokens;
  }

  @override
  Future<PasswordResetRequested> requestReset({required String email}) =>
      throw UnimplementedError();

  @override
  Future<void> confirmReset({
    required String code,
    required String newPassword,
  }) => throw UnimplementedError();
}

Finder _field(PasswordChangeField f) =>
    find.byKey(ValueKey<String>('passwordChange-${f.name}'));
Finder get _submit => find.byKey(const Key('passwordChangeSubmit'));

class _Harness {
  _Harness(this.l, this.container, this.router);
  final AppLocalizations l;
  final ProviderContainer container;
  final GoRouter router;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required PasswordRepository repository,
  UserProfile? profile,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // 로그인한 회원으로 시작한다 — 저장된 토큰을 세션 확인(`/users/me`)이 받아 준다.
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'access_token': 'old-access',
    'refresh_token': 'old-refresh',
  });
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Map<String, Object?>>(
            requestOptions: options,
            statusCode: 200,
            data: <String, Object?>{'id': 'u1'},
          ),
        );
      },
    ),
  );
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.myHealth,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.myHealth,
        builder: (_, _) => const Scaffold(body: Text('MY')),
      ),
      GoRoute(
        path: AppRoutes.mySettingsPath(AppRoutes.passwordSettingsSection),
        builder: (_, _) => const PasswordChangePage(),
      ),
    ],
  );
  addTearDown(router.dispose);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      dioProvider.overrideWithValue(dio),
      sessionFeatureResetOverride(),
      passwordRepositoryProvider.overrideWithValue(repository),
      accountRepositoryProvider.overrideWithValue(
        profile == null
            ? MockAccountRepository()
            : MockAccountRepository(profile: profile),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  container.read(sessionControllerProvider.notifier);
  await tester.pumpAndSettle();
  router.push(AppRoutes.mySettingsPath(AppRoutes.passwordSettingsSection));
  await tester.pumpAndSettle();
  return _Harness(
    AppLocalizations.of(tester.element(find.byType(PasswordChangePage))),
    container,
    router,
  );
}

Future<void> _fill(
  WidgetTester tester, {
  String current = _current,
  String next = _newPw,
  String? confirm,
}) async {
  await tester.enterText(_field(PasswordChangeField.current), current);
  await tester.enterText(_field(PasswordChangeField.next), next);
  await tester.enterText(_field(PasswordChangeField.confirm), confirm ?? next);
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submit);
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('빈 칸으로 누르면 요청 없이 칸 아래에 알린다', (tester) async {
    final _FakePasswordRepository repo = _FakePasswordRepository();
    final _Harness h = await _pump(tester, repository: repo);
    await _tapSubmit(tester);
    expect(repo.calls, isEmpty);
    expect(find.text(h.l.authPasswordEmpty), findsWidgets);
  });

  testWidgets('새 비밀번호는 가입과 같은 규칙으로 본다', (tester) async {
    final _FakePasswordRepository repo = _FakePasswordRepository();
    final _Harness h = await _pump(tester, repository: repo);
    await _fill(tester, next: '12345678');
    await _tapSubmit(tester);
    expect(repo.calls, isEmpty);
    expect(find.text(h.l.signUpPasswordWeak), findsOneWidget);
  });

  testWidgets('확인이 다르면 막는다', (tester) async {
    final _FakePasswordRepository repo = _FakePasswordRepository();
    final _Harness h = await _pump(tester, repository: repo);
    await _fill(tester, confirm: 'other-pass-3');
    await _tapSubmit(tester);
    expect(repo.calls, isEmpty);
    expect(find.text(h.l.signUpPasswordMismatch), findsOneWidget);
  });

  testWidgets('현재와 같은 비밀번호는 보내기 전에 거른다', (tester) async {
    final _FakePasswordRepository repo = _FakePasswordRepository();
    final _Harness h = await _pump(tester, repository: repo);
    await _fill(tester, next: _current);
    await _tapSubmit(tester);
    expect(repo.calls, isEmpty);
    expect(find.text(h.l.passwordChangeSameAsCurrent), findsOneWidget);
  });

  testWidgets('성공하면 새 토큰으로 갈아 끼우고 로그인을 유지한 채 돌아간다', (tester) async {
    final _FakePasswordRepository repo = _FakePasswordRepository(
      tokens: const ReissuedTokens(
        access: 'new-access',
        refresh: 'new-refresh',
      ),
    );
    final _Harness h = await _pump(tester, repository: repo);
    expect(h.container.read(authAccessTokenProvider), 'old-access');

    await _fill(tester);
    await _tapSubmit(tester);

    expect(repo.calls, <(String, String)>[(_current, _newPw)]);
    expect(h.container.read(authAccessTokenProvider), 'new-access');
    expect(
      h.container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
    final SecureTokenStore store = h.container.read(secureTokenStoreProvider);
    expect(await store.readAccessToken(), 'new-access');
    expect(await store.readRefreshToken(), 'new-refresh');
    expect(find.byType(PasswordChangePage), findsNothing);
    expect(find.text('MY'), findsOneWidget);
    expect(find.text(h.l.passwordChangeDone), findsOneWidget);
  });

  testWidgets('현재 비밀번호가 틀리면 그 칸에 붙이고 세션은 그대로다', (tester) async {
    final _FakePasswordRepository repo = _FakePasswordRepository(
      error: const PasswordChangeError(PasswordChangeFailure.wrongCurrent),
    );
    final _Harness h = await _pump(tester, repository: repo);
    await _fill(tester);
    await _tapSubmit(tester);
    expect(find.text(h.l.passwordChangeWrongCurrent), findsOneWidget);
    expect(find.byType(PasswordChangePage), findsOneWidget);
    expect(h.container.read(authAccessTokenProvider), 'old-access');

    // 그 칸을 고치면 서버 오류는 걷힌다.
    await tester.enterText(_field(PasswordChangeField.current), 'retry-pass-9');
    await tester.pump();
    expect(find.text(h.l.passwordChangeWrongCurrent), findsNothing);
  });

  testWidgets('서버가 새 비밀번호를 거절하면 새 비밀번호 칸에 붙인다', (tester) async {
    final _FakePasswordRepository repo = _FakePasswordRepository(
      error: const PasswordChangeError(
        PasswordChangeFailure.newRejected,
        reason: AppInputError.passwordTooLong,
      ),
    );
    final _Harness h = await _pump(tester, repository: repo);
    await _fill(tester);
    await _tapSubmit(tester);
    expect(find.text(h.l.signUpPasswordTooLong), findsOneWidget);
  });

  testWidgets('데모 빌드는 이유를 말하고 칸과 버튼을 끈다', (tester) async {
    final _Harness h = await _pump(
      tester,
      repository: const MockPasswordRepository(),
    );
    expect(find.byKey(const Key('passwordChangeDemoNotice')), findsOneWidget);
    expect(find.text(h.l.passwordChangeDemoTitle), findsOneWidget);
    final AppButton button = tester.widget<AppButton>(_submit);
    expect(button.onPressed, isNull);
    final AppTextField field = tester.widget<AppTextField>(
      _field(PasswordChangeField.current),
    );
    expect(field.enabled, isFalse);
  });

  testWidgets('소셜 로그인 전용 계정은 바꿀 비밀번호가 없다고 말한다', (tester) async {
    final _FakePasswordRepository repo = _FakePasswordRepository();
    final _Harness h = await _pump(
      tester,
      repository: repo,
      profile: const UserProfile(
        id: 'u1',
        name: '소셜',
        email: 'kakao_1@social.oncare',
        hasPassword: false,
      ),
    );
    expect(find.byKey(const Key('passwordChangeSocialNotice')), findsOneWidget);
    expect(find.text(h.l.passwordChangeSocialTitle), findsOneWidget);
    expect(tester.widget<AppButton>(_submit).onPressed, isNull);
  });

  testWidgets('다른 기기는 다시 로그인해야 한다고 미리 알린다', (tester) async {
    final _Harness h = await _pump(
      tester,
      repository: _FakePasswordRepository(),
    );
    expect(find.text(h.l.passwordChangeNote), findsOneWidget);
  });

  test('프로필 응답의 has_password 를 읽는다 — 없으면 참', () {
    expect(
      UserProfile.fromJson(<String, Object?>{
        'has_password': false,
      }).hasPassword,
      isFalse,
    );
    expect(UserProfile.fromJson(<String, Object?>{}).hasPassword, isTrue);
  });
}
