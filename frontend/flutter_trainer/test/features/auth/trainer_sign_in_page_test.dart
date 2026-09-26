import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 로그인 호출을 세는 페이크. [failure] 를 주면 서버가 거절한 것처럼 던진다.
class _RecordingAuthRepository implements TrainerAuthRepository {
  _RecordingAuthRepository({this.failure});

  final AuthFailure? failure;
  int loginCalls = 0;
  int socialCalls = 0;
  String? email;
  String? socialProvider;
  String? password;

  static const TrainerAuthTokens _tokens = TrainerAuthTokens(
    access: 'a',
    refresh: 'r',
  );

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    this.email = email;
    this.password = password;
    if (failure != null) throw AuthException(failure!);
    return _tokens;
  }

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String inviteCode,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async {
    socialCalls++;
    socialProvider = provider;
    if (failure != null) throw AuthException(failure!);
    return _tokens;
  }

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async => _tokens;

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async =>
      const TrainerProfile(
        name: '트레이너',
        email: 'trainer@oncare.com',
        phone: '',
        specialty: '',
        career: '',
        intro: '',
        certifications: <String>[],
        gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
      );
}

const ValueKey<String> _emailKey = ValueKey<String>('trainer-login-email');
const ValueKey<String> _passwordKey = ValueKey<String>(
  'trainer-login-password',
);

Future<_RecordingAuthRepository> _pumpWithRepo(
  WidgetTester tester, {
  AuthFailure? failure,
}) async {
  final repo = _RecordingAuthRepository(failure: failure);
  await pumpTrainerApp(
    tester,
    extraOverrides: <Override>[
      trainerAuthRepositoryProvider.overrideWithValue(repo),
    ],
  );
  return repo;
}

Future<void> _type(
  WidgetTester tester,
  ValueKey<String> key,
  String text,
) async {
  await tester.enterText(
    find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
  // 사라지는 오류 문구는 서서히 빠진다(Material 167ms) — 전환을 끝까지 돌린다.
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _submit(WidgetTester tester) async {
  final Finder submit = find.byKey(
    const ValueKey<String>('trainer-login-submit'),
  );
  await tester.ensureVisible(submit);
  await tester.pump();
  await tester.tap(submit);
  await tester.pump();
}

/// [key] 칸 **안에**(입력창 아래 오류 자리) [message] 가 그려졌는가.
Finder _errorUnder(ValueKey<String> key, String message) =>
    find.descendant(of: find.byKey(key), matching: find.text(message));

void main() {
  for (final mock in <bool>[true, false]) {
    for (final provider in <String>['kakao', 'google']) {
      for (final fail in <bool>[false, true]) {
        testWidgets('$provider mock=$mock fail=$fail 소셜 버튼 로그인', (
          tester,
        ) async {
          final repo = _RecordingAuthRepository(
            failure: fail ? AuthFailure.invalidCredentials : null,
          );
          final router = GoRouter(
            initialLocation: '/login',
            routes: <RouteBase>[
              GoRoute(
                path: '/login',
                builder: (_, _) => const TrainerSignInPage(),
              ),
              GoRoute(
                path: '/dashboard',
                builder: (_, _) => const Scaffold(body: Text('로그인 완료')),
              ),
            ],
          );
          addTearDown(router.dispose);
          final container = await pumpTrainerApp(
            tester,
            seed: false,
            extraOverrides: <Override>[
              trainerAuthRepositoryProvider.overrideWithValue(repo),
              appRouterProvider.overrideWithValue(router),
              appConfigProvider.overrideWithValue(
                AppConfig(
                  environment: Environment.dev,
                  apiBaseUrl: 'https://api.test',
                  useMockApi: mock,
                ),
              ),
            ],
          );
          container.read(sessionControllerProvider);
          await settle(tester);
          final button = find.byKey(
            ValueKey<String>('trainer-login-$provider'),
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await settle(tester);
          expect(repo.socialCalls, mock ? 1 : 0);
          expect(repo.loginCalls, mock ? 0 : 1);
          if (mock) {
            expect(repo.socialProvider, provider);
          } else {
            expect(repo.email, 'trainer@oncare.com');
            expect(repo.password, 'oncare123');
          }
          expect(
            container.read(sessionControllerProvider).status,
            fail ? SessionStatus.signedOut : SessionStatus.authenticated,
          );
          if (fail) {
            expect(find.byType(TrainerSignInPage), findsOneWidget);
            expect(
              find.text(
                AppLocalizations.of(
                  tester.element(find.byType(TrainerSignInPage)),
                ).authSocialSignInFailed,
              ),
              findsOneWidget,
            );
          } else {
            expect(find.text('로그인 완료'), findsOneWidget);
          }
        });
      }
    }
  }

  group('TrainerSignInPage', () {
    testWidgets('회원 앱 로그인과 같은 부품·문구로 선다 (#2226)', (tester) async {
      await _pumpWithRepo(tester);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(TrainerSignInPage)),
      );

      // 틀·입력칸·소셜 줄은 두 앱이 나눠 쓰는 부품이다.
      expect(find.byType(AppAuthLayout), findsOneWidget);
      expect(find.byType(AppSocialLoginRow), findsOneWidget);
      // 비밀번호 보이기/감추기도 공용 부품이다 — 아이콘은 앱의 묶음을 따른다.
      expect(find.byType(AppPasswordToggle), findsOneWidget);
      expect(
        tester.widget<AppPasswordToggle>(find.byType(AppPasswordToggle)).obscure,
        isTrue,
      );

      // 트레이너의 정체성 문구는 그대로 둔다 — 회원 앱과 같은 로고·배치라
      // 제목까지 같으면 어느 쪽에 로그인하는지 알아채기 어렵다.
      expect(find.text(l.appTitleSpaced), findsOneWidget);
      expect(find.text(l.authTagline), findsOneWidget);
      expect(find.text(l.authSignInAction), findsOneWidget);
      expect(find.text(l.authNoAccountQuestion), findsOneWidget);
      expect(find.text(l.authSignUpAction), findsOneWidget);
    });

    testWidgets('빈칸으로 로그인하면 칸 아래에 빨간 문구를 보이고 요청하지 않는다', (tester) async {
      final repo = await _pumpWithRepo(tester);

      // 제출하기 전에는 아무 칸에도 오류가 없다.
      expect(find.text('이메일을 입력해 주세요'), findsNothing);

      await _submit(tester);

      expect(_errorUnder(_emailKey, '이메일을 입력해 주세요'), findsOneWidget);
      expect(_errorUnder(_passwordKey, '비밀번호를 입력해 주세요'), findsOneWidget);
      // 예전 토스트 문구는 더 이상 뜨지 않는다.
      expect(find.text('이메일과 비밀번호를 입력해 주세요'), findsNothing);
      expect(repo.loginCalls, 0);

      final BuildContext context = tester.element(find.byKey(_emailKey));
      final Text error = tester.widget<Text>(find.text('이메일을 입력해 주세요'));
      expect(error.style?.color, Theme.of(context).colorScheme.error);
    });

    testWidgets('이메일 형식이 틀리면 형식 문구를 보이고 요청하지 않는다', (tester) async {
      final repo = await _pumpWithRepo(tester);

      await _type(tester, _emailKey, 'trainer@oncare');
      await _type(tester, _passwordKey, 'oncare123');
      await tester.pump();
      // 입력만으로는 오류를 보이지 않는다 — 첫 제출 전이다.
      expect(find.text('이메일 형식이 올바르지 않아요'), findsNothing);

      await _submit(tester);

      expect(_errorUnder(_emailKey, '이메일 형식이 올바르지 않아요'), findsOneWidget);
      expect(find.text('비밀번호를 입력해 주세요'), findsNothing);
      expect(repo.loginCalls, 0);
    });

    testWidgets('오류를 보인 칸은 고치는 대로 문구가 사라진다', (tester) async {
      final repo = await _pumpWithRepo(tester);

      await _type(tester, _emailKey, 'trainer');
      await _submit(tester);
      expect(find.text('이메일 형식이 올바르지 않아요'), findsOneWidget);
      expect(find.text('비밀번호를 입력해 주세요'), findsOneWidget);

      // 다시 제출하지 않아도 칸마다 지금 값으로 다시 검사한다.
      await _type(tester, _emailKey, 'trainer@oncare.com');
      await tester.pump();
      expect(find.text('이메일 형식이 올바르지 않아요'), findsNothing);
      expect(find.text('비밀번호를 입력해 주세요'), findsOneWidget);

      await _type(tester, _passwordKey, 'pw');
      await tester.pump();
      expect(find.text('비밀번호를 입력해 주세요'), findsNothing);
      expect(repo.loginCalls, 0);
    });

    testWidgets('로그인은 가입 비밀번호 규칙을 걸지 않는다', (tester) async {
      // 규칙 이전에 만든 계정이 막히지 않아야 한다(#1784).
      final repo = await _pumpWithRepo(tester);

      await _type(tester, _emailKey, 'trainer@oncare.com');
      await _type(tester, _passwordKey, 'pw');
      await _submit(tester);
      await settle(tester);

      expect(repo.loginCalls, 1);
      expect(repo.password, 'pw');
      expect(find.text('영문과 숫자를 포함해 8자 이상 입력해 주세요'), findsNothing);
    });

    testWidgets('서버가 거절한 로그인은 칸 오류가 아니라 토스트로 알린다', (tester) async {
      final repo = await _pumpWithRepo(
        tester,
        failure: AuthFailure.invalidCredentials,
      );

      await _type(tester, _emailKey, 'trainer@oncare.com');
      await _type(tester, _passwordKey, 'wrong-password');
      await _submit(tester);
      await settle(tester);

      expect(repo.loginCalls, 1);
      expect(find.text('이메일 또는 비밀번호가 올바르지 않습니다.'), findsOneWidget);
      expect(find.text('이메일 형식이 올바르지 않아요'), findsNothing);
      expect(find.text('비밀번호를 입력해 주세요'), findsNothing);
    });

    testWidgets('소셜 로그인은 구분선 아래 원형 카카오·구글 버튼이다', (tester) async {
      // 전체 폭 글자 버튼 대신 가운데에 나란히 놓인 원형 버튼이다(#1783).
      await pumpTrainerApp(tester);

      expect(find.text('SNS 계정으로 로그인'), findsOneWidget);
      expect(find.text('또는'), findsNothing);
      final Finder kakao = find.byKey(
        const ValueKey<String>('trainer-login-kakao'),
      );
      final Finder google = find.byKey(
        const ValueKey<String>('trainer-login-google'),
      );
      expect(kakao, findsOneWidget);
      expect(google, findsOneWidget);
      // 그림만 있는 버튼이라 이름은 화면 읽기 라벨·툴팁으로만 남는다.
      expect(find.bySemanticsLabel('카카오로 시작하기'), findsOneWidget);
      expect(find.bySemanticsLabel('구글로 시작하기'), findsOneWidget);
      expect(find.byTooltip('카카오로 시작하기'), findsOneWidget);
      expect(find.byTooltip('구글로 시작하기'), findsOneWidget);
      expect(find.text('카카오로 시작하기'), findsNothing);
      expect(tester.getCenter(kakao).dy, tester.getCenter(google).dy);
      expect(
        tester.getCenter(kakao).dy,
        greaterThan(tester.getCenter(find.text('SNS 계정으로 로그인')).dy),
      );
    });

    testWidgets('카카오 원형 버튼을 누르면 소셜 로그인으로 들어간다', (tester) async {
      final container = await pumpTrainerApp(tester);
      final Finder kakao = find.byKey(
        const ValueKey<String>('trainer-login-kakao'),
      );

      await tester.ensureVisible(kakao);
      await tester.pump();
      await tester.tap(kakao);
      await settle(tester);

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
    });

    testWidgets('데모 진입은 기본 빌드에서 뜨지 않는다', (tester) async {
      // 로그인 없이 콘솔로 들어가는 경로를 화면에서 내렸다. 코드는 남아 있고
      // 노출만 SHOW_DEMO_ENTRY 로 막았다. (#1526)
      await pumpTrainerApp(tester);

      expect(find.text('로그인 없이 데모 둘러보기'), findsNothing);
      // 로그인 화면 자체는 그대로다 — 감춘 것이 이 버튼뿐임을 함께 못 박는다.
      expect(find.widgetWithText(InkWell, '로그인'), findsOneWidget);
    });

    testWidgets('demo bypass enters demo mode and leaves the login screen', (
      tester,
    ) async {
      // 진입 버튼은 기본 빌드에서 감춰 뒀다. 되돌릴 수 있게 남긴 경로이므로
      // 플래그를 켜고 그 경로가 계속 도는지 확인한다. (#1526)
      final container = await pumpTrainerApp(tester, demoEntry: true);

      // The demo link sits below the fold on the (taller, redesigned)
      // login screen — scroll it into view before tapping.
      await tester.ensureVisible(find.text('로그인 없이 데모 둘러보기'));
      await tester.pump();
      await tester.tap(find.text('로그인 없이 데모 둘러보기'));
      await settle(tester);

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.demo,
      );
      // Left the login screen (no more login button / demo link).
      expect(find.text('로그인 없이 데모 둘러보기'), findsNothing);
      expect(find.text('계정 만들기'), findsNothing);
    });

    testWidgets('login with credentials authenticates and navigates away', (
      tester,
    ) async {
      final container = await pumpTrainerApp(tester);

      await tester.enterText(
        find.byType(TextField).at(0),
        'trainer@oncare.com',
      );
      await tester.enterText(find.byType(TextField).at(1), 'pw');
      await tester.tap(find.widgetWithText(InkWell, '로그인'));
      await settle(tester);

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(find.text('계정 만들기'), findsNothing);
    });
  });
}
