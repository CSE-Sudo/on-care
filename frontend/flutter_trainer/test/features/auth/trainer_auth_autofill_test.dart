/// 로그인·가입 칸의 자동완성 힌트와 비밀번호 저장 시점 — #2295.
///
/// 브라우저 비밀번호 관리자가 칸을 알아보려면 칸마다 힌트가 있어야 하고, 한
/// 화면의 칸이 한 [AutofillGroup] 에 묶여 있어야 한다. 저장은 서버가 받아 준
/// 뒤에만 한다 — 틀린 비밀번호나 쓰다 만 가입을 저장하라고 권하면 안 된다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_up_page.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 로그인·가입을 성공시키거나 [error] 로 거절하는 페이크.
class _AuthRepository implements TrainerAuthRepository {
  _AuthRepository({this.error});

  /// 주면 로그인·가입·소셜 로그인이 모두 이것을 던진다.
  final Object? error;
  int loginCalls = 0;
  int registerCalls = 0;
  int socialCalls = 0;

  static const TrainerAuthTokens _tokens = TrainerAuthTokens(
    access: 'a',
    refresh: 'r',
  );

  Future<TrainerAuthTokens> _answer() async {
    if (error != null) throw error!;
    return _tokens;
  }

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) {
    loginCalls++;
    return _answer();
  }

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
  }) {
    registerCalls++;
    return _answer();
  }

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) {
    socialCalls++;
    return _answer();
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
        careerYears: null,
        intro: '',
        certifications: <String>[],
        gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
      );
}

/// 실 API 모드.
const AppConfig _realConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

/// 지금까지 플랫폼에 보낸 `finishAutofillContext` 의 `shouldSave` 값들.
List<bool?> _finishCalls(WidgetTester tester) => <bool?>[
  for (final MethodCall call in tester.testTextInput.log)
    if (call.method == 'TextInput.finishAutofillContext')
      call.arguments as bool?,
];

/// 저장하라고(`shouldSave: true`) 알린 횟수.
int _saves(WidgetTester tester) =>
    _finishCalls(tester).where((bool? save) => save == true).length;

Finder _input(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_input(key));

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_input(key), text);
  await tester.pump();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder button = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await settle(tester);
}

/// [key] 칸이 화면의 [AutofillGroup] 안에 있는가.
Finder _groupAround(String key) =>
    find.ancestor(of: _input(key), matching: find.byType(AutofillGroup));

void main() {
  group('로그인 화면', () {
    const String email = 'trainer-login-email';
    const String password = 'trainer-login-password';
    const String submit = 'trainer-login-submit';

    Future<(_AuthRepository, ProviderContainer)> pumpSignIn(
      WidgetTester tester, {
      Object? error,
      Locale locale = const Locale('ko'),
    }) async {
      final _AuthRepository repo = _AuthRepository(error: error);
      final ProviderContainer container = await pumpTrainerApp(
        tester,
        locale: locale,
        extraOverrides: <Override>[
          trainerAuthRepositoryProvider.overrideWithValue(repo),
        ],
      );
      tester.testTextInput.log.clear();
      return (repo, container);
    }

    testWidgets('이메일 칸은 username·email, 비밀번호 칸은 password 힌트다', (tester) async {
      await pumpSignIn(tester);

      expect(find.byType(TrainerSignInPage), findsOneWidget);
      expect(_field(tester, email).autofillHints, <String>[
        AutofillHints.username,
        AutofillHints.email,
      ]);
      expect(_field(tester, password).autofillHints, <String>[
        AutofillHints.password,
      ]);
      // 힌트를 붙여도 원래 입력 설정은 그대로다.
      expect(_field(tester, email).keyboardType, TextInputType.emailAddress);
      expect(_field(tester, password).obscureText, isTrue);
    });

    testWidgets('이메일 칸은 자동 대문자·자동 고침이 꺼져 있다(#2816)', (tester) async {
      await pumpSignIn(tester);

      final TextField field = _field(tester, email);
      expect(field.textCapitalization, TextCapitalization.none);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('두 칸이 같은 AutofillGroup 하나에 묶여 있다', (tester) async {
      await pumpSignIn(tester);

      expect(
        find.descendant(
          of: find.byType(TrainerSignInPage),
          matching: find.byType(AutofillGroup),
        ),
        findsOneWidget,
      );
      expect(_groupAround(email), findsOneWidget);
      expect(_groupAround(password), findsOneWidget);
      expect(
        tester.widget(_groupAround(email)),
        same(tester.widget(_groupAround(password))),
      );
    });

    testWidgets('묶음은 그냥 떠날 때 저장하지 않도록(cancel) 설정돼 있다', (tester) async {
      await pumpSignIn(tester);

      final AutofillGroup group = tester.widget<AutofillGroup>(
        _groupAround(email),
      );
      expect(group.onDisposeAction, AutofillContextAction.cancel);
    });

    testWidgets('로그인에 성공하면 한 번 저장을 알린다', (tester) async {
      final (_AuthRepository repo, ProviderContainer container) =
          await pumpSignIn(tester);

      await _type(tester, email, 'trainer@oncare.com');
      await _type(tester, password, 'pw');
      await _tapKey(tester, submit);

      expect(repo.loginCalls, 1);
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(_saves(tester), 1);
      // 저장 알림이 화면을 걷어 낼 때의 취소보다 먼저 간다.
      expect(_finishCalls(tester).first, isTrue);
      expect(find.byType(TrainerSignInPage), findsNothing);
    });

    for (final AuthFailure failure in <AuthFailure>[
      AuthFailure.invalidCredentials,
      AuthFailure.notTrainer,
      AuthFailure.network,
    ]) {
      testWidgets('서버가 거절하면($failure) 저장하지 않는다', (tester) async {
        final (_AuthRepository repo, ProviderContainer container) =
            await pumpSignIn(tester, error: AuthException(failure));

        await _type(tester, email, 'trainer@oncare.com');
        await _type(tester, password, 'wrong-password');
        await _tapKey(tester, submit);

        expect(repo.loginCalls, 1);
        expect(
          container.read(sessionControllerProvider).status,
          isNot(SessionStatus.authenticated),
        );
        expect(_finishCalls(tester), isEmpty);
        expect(find.byType(TrainerSignInPage), findsOneWidget);
      });
    }

    testWidgets('예상 못 한 오류로 실패해도 저장하지 않는다', (tester) async {
      final (_AuthRepository repo, _) = await pumpSignIn(
        tester,
        error: StateError('boom'),
      );

      await _type(tester, email, 'trainer@oncare.com');
      await _type(tester, password, 'pw');
      await _tapKey(tester, submit);

      expect(repo.loginCalls, 1);
      expect(_finishCalls(tester), isEmpty);
      expect(find.byType(TrainerSignInPage), findsOneWidget);
    });

    testWidgets('형식이 틀려 요청을 보내지 않으면 저장하지 않는다', (tester) async {
      final (_AuthRepository repo, _) = await pumpSignIn(tester);

      await _type(tester, email, 'not-an-email');
      await _tapKey(tester, submit);

      expect(repo.loginCalls, 0);
      expect(_finishCalls(tester), isEmpty);
    });

    testWidgets('실패한 뒤 다시 맞게 로그인하면 그때 한 번 저장한다', (tester) async {
      // 첫 시도는 거절, 두 번째는 받아 주는 저장소를 흉내 낸다.
      final _FlakyRepository repo = _FlakyRepository();
      await pumpTrainerApp(
        tester,
        extraOverrides: <Override>[
          trainerAuthRepositoryProvider.overrideWithValue(repo),
        ],
      );
      tester.testTextInput.log.clear();

      await _type(tester, email, 'trainer@oncare.com');
      await _type(tester, password, 'wrong');
      await _tapKey(tester, submit);
      expect(_saves(tester), 0);

      await _type(tester, password, 'right');
      await _tapKey(tester, submit);
      expect(repo.loginCalls, 2);
      expect(_saves(tester), 1);
    });

    testWidgets('실패한 채 화면이 사라지면 저장이 아니라 취소를 알린다', (tester) async {
      await pumpSignIn(
        tester,
        error: const AuthException(AuthFailure.invalidCredentials),
      );

      await _type(tester, email, 'trainer@oncare.com');
      await _type(tester, password, 'wrong-password');
      await _tapKey(tester, submit);
      await tester.pumpWidget(const SizedBox.shrink());

      expect(_finishCalls(tester), <bool?>[false]);
    });

    testWidgets('소셜 로그인은 입력한 칸과 무관해 저장하지 않는다', (tester) async {
      final (_AuthRepository repo, _) = await pumpSignIn(tester);

      await _tapKey(tester, 'trainer-login-kakao');

      expect(repo.socialCalls, 1);
      expect(_saves(tester), 0);
    });

    testWidgets('영어 화면에서도 힌트와 묶음이 같다', (tester) async {
      await pumpSignIn(tester, locale: const Locale('en'));

      expect(find.byType(TrainerSignInPage), findsOneWidget);
      expect(_field(tester, email).autofillHints, <String>[
        AutofillHints.username,
        AutofillHints.email,
      ]);
      expect(_field(tester, password).autofillHints, <String>[
        AutofillHints.password,
      ]);
      expect(_groupAround(email), findsOneWidget);
    });
  });

  group('가입 화면', () {
    const String name = 'trainer-signup-name';
    const String email = 'trainer-signup-email';
    const String password = 'trainer-signup-password';
    const String confirm = 'trainer-signup-password-confirm';
    const String submit = 'trainer-signup-submit';

    Future<_AuthRepository> pumpSignUp(
      WidgetTester tester, {
      bool demo = false,
      Object? error,
      Locale locale = const Locale('ko'),
    }) async {
      final _AuthRepository repo = _AuthRepository(error: error);
      await pumpTrainerApp(
        tester,
        at: AppRoutes.signUp,
        locale: locale,
        extraOverrides: <Override>[
          if (!demo) ...<Override>[
            appConfigProvider.overrideWithValue(_realConfig),
            ...stillBadges(),
            stillRoster(),
          ],
          trainerAuthRepositoryProvider.overrideWithValue(repo),
        ],
      );
      tester.testTextInput.log.clear();
      return repo;
    }

    Future<void> fill(WidgetTester tester) async {
      await _type(tester, name, '김신규');
      await _type(tester, email, 'new@oncare.com');
      await _type(tester, password, 'signup-pw-1234');
      await _type(tester, confirm, 'signup-pw-1234');
    }

    testWidgets('칸마다 name·username/email·newPassword 힌트다', (tester) async {
      await pumpSignUp(tester);

      expect(find.byType(TrainerSignUpPage), findsOneWidget);
      expect(_field(tester, name).autofillHints, <String>[AutofillHints.name]);
      expect(_field(tester, email).autofillHints, <String>[
        AutofillHints.username,
        AutofillHints.email,
      ]);
      // 가입은 저장된 비밀번호를 채우는 자리가 아니라 새 비밀번호를 받는 자리다.
      expect(_field(tester, password).autofillHints, <String>[
        AutofillHints.newPassword,
      ]);
      expect(_field(tester, confirm).autofillHints, <String>[
        AutofillHints.newPassword,
      ]);
      expect(
        _field(tester, password).autofillHints,
        isNot(contains(AutofillHints.password)),
      );
    });

    testWidgets('이메일 칸은 자동 대문자·자동 고침이 꺼져 있다(#2816)', (tester) async {
      await pumpSignUp(tester);

      final TextField field = _field(tester, email);
      expect(field.textCapitalization, TextCapitalization.none);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('모든 칸이 같은 AutofillGroup 하나에 묶여 있다', (tester) async {
      await pumpSignUp(tester);

      expect(
        find.descendant(
          of: find.byType(TrainerSignUpPage),
          matching: find.byType(AutofillGroup),
        ),
        findsOneWidget,
      );
      final Widget group = tester.widget(_groupAround(name));
      for (final String key in <String>[email, password, confirm]) {
        expect(tester.widget(_groupAround(key)), same(group), reason: key);
      }
      expect(
        (group as AutofillGroup).onDisposeAction,
        AutofillContextAction.cancel,
      );
    });

    testWidgets('데모 가입 화면도 같은 힌트·묶음이다', (tester) async {
      await pumpSignUp(tester, demo: true);

      expect(_groupAround(confirm), findsOneWidget);
      expect(_field(tester, confirm).autofillHints, <String>[
        AutofillHints.newPassword,
      ]);
    });

    testWidgets('가입에 성공하면 한 번 저장을 알린다', (tester) async {
      final _AuthRepository repo = await pumpSignUp(tester);
      await fill(tester);

      await _tapKey(tester, submit);

      expect(repo.registerCalls, 1);
      expect(_saves(tester), 1);
      expect(_finishCalls(tester).first, isTrue);
      expect(find.byType(TrainerSignUpPage), findsNothing);
    });

    testWidgets('데모 가입에 성공해도 한 번 저장을 알린다', (tester) async {
      final _AuthRepository repo = await pumpSignUp(tester, demo: true);
      await fill(tester);

      await _tapKey(tester, submit);

      expect(repo.registerCalls, 1);
      expect(_saves(tester), 1);
    });

    for (final AuthFailure failure in <AuthFailure>[
      AuthFailure.emailTaken,
      AuthFailure.network,
    ]) {
      testWidgets('서버가 가입을 거절하면($failure) 저장하지 않는다', (tester) async {
        final _AuthRepository repo = await pumpSignUp(
          tester,
          error: AuthException(failure),
        );
        await fill(tester);

        await _tapKey(tester, submit);

        expect(repo.registerCalls, 1);
        expect(_finishCalls(tester), isEmpty);
        expect(find.byType(TrainerSignUpPage), findsOneWidget);
      });
    }

    testWidgets('예상 못 한 오류로 가입이 실패해도 저장하지 않는다', (tester) async {
      final _AuthRepository repo = await pumpSignUp(
        tester,
        error: StateError('boom'),
      );
      await fill(tester);

      await _tapKey(tester, submit);

      expect(repo.registerCalls, 1);
      expect(_finishCalls(tester), isEmpty);
    });

    testWidgets('형식이 틀려 보내지 않은 가입은 저장하지 않는다', (tester) async {
      final _AuthRepository repo = await pumpSignUp(tester);
      await fill(tester);
      await _type(tester, confirm, 'different-pw1');

      await _tapKey(tester, submit);

      expect(repo.registerCalls, 0);
      expect(_finishCalls(tester), isEmpty);
    });

    testWidgets('쓰다가 뒤로 나가면 저장이 아니라 취소를 알린다', (tester) async {
      await pumpSignUp(tester);
      await fill(tester);

      await tester.tap(find.byType(AppBackButton));
      await settle(tester);

      expect(find.byType(TrainerSignUpPage), findsNothing);
      expect(_saves(tester), 0);
      expect(_finishCalls(tester), <bool?>[false]);
    });

    testWidgets('영어 화면에서도 힌트와 묶음이 같다', (tester) async {
      await pumpSignUp(tester, locale: const Locale('en'));

      expect(_field(tester, name).autofillHints, <String>[AutofillHints.name]);
      expect(_field(tester, password).autofillHints, <String>[
        AutofillHints.newPassword,
      ]);
      expect(_groupAround(confirm), findsOneWidget);
    });
  });
}

/// 첫 로그인은 거절하고 그다음부터 받아 준다.
class _FlakyRepository extends _AuthRepository {
  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    if (loginCalls == 1) {
      throw const AuthException(AuthFailure.invalidCredentials);
    }
    return _AuthRepository._tokens;
  }
}
