import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/my/presentation/pages/legal_document_page.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 가입 호출의 인자를 기록하는 페이크. 로그인까지는 성공시킨다.
class _RecordingAuthRepository implements TrainerAuthRepository {
  String? email;
  String? name;
  List<String>? consents;
  int registerCalls = 0;

  /// 가입이 거절될 때 던질 실패. 비밀번호 기준(#1555) 거절을 흉내 낸다.
  AuthException? error;

  static const TrainerAuthTokens _tokens = TrainerAuthTokens(
    access: 'a',
    refresh: 'r',
  );

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    List<String>? consents,
  }) async {
    registerCalls++;
    this.consents = consents;
    this.email = email;
    this.name = name;
    if (error != null) throw error!;
    return _tokens;
  }

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async => _tokens;

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async =>
      const TrainerProfile(
        name: '신규 트레이너',
        email: 'new@oncare.com',
        phone: '',
        specialty: '',
        careerYears: null,
        intro: '',
        certifications: <String>[],
        gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
      );
}

/// 실 API 모드 설정.
const AppConfig _realConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

Future<_RecordingAuthRepository> _pumpSignUp(
  WidgetTester tester, {
  bool demo = false,
  AuthException? error,
}) async {
  final repo = _RecordingAuthRepository()..error = error;
  await pumpTrainerApp(
    tester,
    at: AppRoutes.signUp,
    extraOverrides: <Override>[
      if (!demo) ...<Override>[
        appConfigProvider.overrideWithValue(_realConfig),
        // 가입 흐름을 보는 테스트다. 대시보드에 내려앉은 뒤의 배지 폴링까지
        // 안고 끝나지 않게 멈춰 둔다.
        ...stillBadges(),
        // 명단도 실 API 에서는 스스로 다시 읽는다(#918). 이 테스트가 보는
        // 것은 가입 요청의 인자다.
        stillRoster(),
      ],
      trainerAuthRepositoryProvider.overrideWithValue(repo),
    ],
  );
  return repo;
}

const ValueKey<String> _nameKey = ValueKey<String>('trainer-signup-name');
const ValueKey<String> _emailKey = ValueKey<String>('trainer-signup-email');
const ValueKey<String> _passwordKey = ValueKey<String>(
  'trainer-signup-password',
);
const ValueKey<String> _confirmKey = ValueKey<String>(
  'trainer-signup-password-confirm',
);

Future<void> _fill(
  WidgetTester tester, {
  String name = '김신규',
  String email = 'new@oncare.com',
  String password = 'signup-pw-1234',
  String confirm = 'signup-pw-1234',
}) async {
  await tester.enterText(find.widgetWithText(TextField, '이름'), name);
  await tester.enterText(find.widgetWithText(TextField, '이메일'), email);
  // 비밀번호 안내가 새 규칙을 말한다(#1784).
  await tester.enterText(
    find.widgetWithText(TextField, '비밀번호 (영문·숫자 포함 8자 이상)'),
    password,
  );
  await tester.enterText(find.widgetWithText(TextField, '비밀번호 확인'), confirm);
  await tester.pump();
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
}

/// 필수 동의가 하나라도 꺼져 있으면 전체 동의를 누른다(#2819) — 필수 동의
/// 없이는 가입 버튼이 꺼져 있어, 이 묶음의 형식 검사까지 닿지 않는다. 필수를
/// 이미 다 켠 테스트의 선택 항목은 건드리지 않는다.
Future<void> _agreeAll(WidgetTester tester) async {
  bool on(String id) => tester
      .widget<Checkbox>(
        find.descendant(
          of: find.byKey(ValueKey<String>('consent-$id')),
          matching: find.byType(Checkbox),
        ),
      )
      .value!;
  if (<String>['terms', 'privacy', 'age14'].every(on)) return;
  final Finder all = find.byKey(const ValueKey<String>('consent-all'));
  await tester.ensureVisible(all);
  await tester.pump();
  await tester.tap(all);
  await tester.pump();
}

/// 오류 문구가 늘어 버튼이 화면 밖으로 밀려도 누를 수 있게 끌어온다.
///
/// 동의 묶음까지 들어가 가입 화면이 테스트 창보다 길다. 방금 친 칸에 초점이
/// 남아 있으면 그 칸이 커서를 보이려고 스크롤을 되돌리는 동안 화면이 누름을
/// 받지 않으므로, 초점을 먼저 거두고 스크롤이 멎은 뒤에 누른다.
Future<void> _submit(WidgetTester tester) async {
  await _agreeAll(tester);
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  final Finder submit = find.byKey(
    const ValueKey<String>('trainer-signup-submit'),
  );
  await tester.ensureVisible(submit);
  await settle(tester);
  await tester.tap(submit);
  await settle(tester);
}

/// [key] 칸 **안에**(입력창 아래 오류 자리) [message] 가 그려졌는가.
Finder _errorUnder(ValueKey<String> key, String message) =>
    find.descendant(of: find.byKey(key), matching: find.text(message));

/// 지금 열려 있는 문서. 주소가 아니라 화면을 본다 — `push` 로 쌓은 라우트는
/// 라우터가 아래 화면의 주소를 그대로 들고 있어 URL 로는 구분되지 않는다.
String? _shownDocument(WidgetTester tester) =>
    tester.widget<LegalDocumentPage>(find.byType(LegalDocumentPage)).document;

void main() {
  testWidgets('가입 화면에 초대 코드 입력이 없다', (WidgetTester tester) async {
    // 소속 헬스장은 가입 뒤 헬스장을 찾아 고른다(#1627).
    await _pumpSignUp(tester);

    expect(find.widgetWithText(TextField, '헬스장 초대 코드'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('trainer-signup-invite-code')),
      findsNothing,
    );
  });

  testWidgets('가입하면 소속 헬스장을 고르는 프로필 수정으로 간다 (#2543)', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);
    await _fill(tester);

    await _submit(tester);

    expect(currentLocation(tester), AppRoutes.mySection('edit'));
    expect(find.byKey(const ValueKey<String>('gym-search')), findsOneWidget);
  });

  testWidgets('이름·이메일·비밀번호만으로 가입을 보낸다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester);

    await _submit(tester);

    expect(repo.registerCalls, 1);
    expect(repo.email, 'new@oncare.com');
    expect(repo.name, '김신규');
  });

  testWidgets('비밀번호가 다르면 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester, confirm: 'different-pw1');

    await _submit(tester);

    expect(repo.registerCalls, 0);
    expect(_errorUnder(_confirmKey, '비밀번호가 일치하지 않아요'), findsOneWidget);
  });

  // --- 입력 형식 검사 (#1784) ----------------------------------------------

  testWidgets('빈칸으로 제출하면 칸마다 아래에 문구를 보이고 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);

    // 제출하기 전에는 아무 칸에도 오류가 없다.
    expect(find.text('이름을 입력해 주세요'), findsNothing);
    expect(find.text('이메일을 입력해 주세요'), findsNothing);

    await _submit(tester);

    expect(_errorUnder(_nameKey, '이름을 입력해 주세요'), findsOneWidget);
    expect(_errorUnder(_emailKey, '이메일을 입력해 주세요'), findsOneWidget);
    expect(_errorUnder(_passwordKey, '비밀번호를 입력해 주세요'), findsOneWidget);
    // 둘 다 비어 있으면 서로 같다 — 확인 칸은 조용하다.
    expect(find.text('비밀번호가 일치하지 않아요'), findsNothing);
    // 예전 토스트 문구는 더 이상 뜨지 않는다.
    expect(find.text('이메일과 비밀번호를 입력해 주세요'), findsNothing);
    expect(repo.registerCalls, 0);
  });

  testWidgets('이름이 비었거나 공백뿐이면 보내지 않고, 치면 문구가 사라진다', (
    WidgetTester tester,
  ) async {
    final repo = await _pumpSignUp(tester);
    // 이름 말고는 모두 맞게 채운다.
    await _fill(tester, name: '   ');
    expect(find.text('이름을 입력해 주세요'), findsNothing);

    await _submit(tester);

    expect(_errorUnder(_nameKey, '이름을 입력해 주세요'), findsOneWidget);
    expect(find.text('이메일을 입력해 주세요'), findsNothing);
    expect(repo.registerCalls, 0);

    // 다시 제출하지 않아도 이름을 치는 대로 문구가 사라진다.
    await _type(tester, _nameKey, '김신규');
    expect(find.text('이름을 입력해 주세요'), findsNothing);

    await _submit(tester);

    expect(repo.registerCalls, 1);
    expect(repo.name, '김신규');
  });

  testWidgets('이메일 형식·비밀번호 규칙이 틀리면 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);

    for (final String weak in <String>['abc123', 'abcdefgh', '12345678']) {
      await _fill(tester, email: 'new@oncare', password: weak, confirm: weak);
      await _submit(tester);

      expect(_errorUnder(_emailKey, '이메일 형식이 올바르지 않아요'), findsOneWidget);
      expect(
        _errorUnder(_passwordKey, '영문과 숫자를 포함해 8자 이상 입력해 주세요'),
        findsOneWidget,
        reason: weak,
      );
      expect(repo.registerCalls, 0, reason: weak);
    }
  });

  testWidgets('오류를 보인 칸은 고치는 대로 문구가 사라지고, 다 고치면 보낸다', (
    WidgetTester tester,
  ) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester, password: 'abcdefgh', confirm: 'abcdefgh');

    await _submit(tester);
    expect(find.text('영문과 숫자를 포함해 8자 이상 입력해 주세요'), findsOneWidget);
    // 제출 때 확인 칸은 맞았다.
    expect(find.text('비밀번호가 일치하지 않아요'), findsNothing);

    // 다시 제출하지 않아도 고친 칸의 문구가 사라진다.
    await _type(tester, _passwordKey, 'abcdefg1');
    await tester.pump();
    expect(find.text('영문과 숫자를 포함해 8자 이상 입력해 주세요'), findsNothing);
    // 제출 때 맞았던 확인 칸은 다음 제출까지 오류를 보이지 않는다.
    expect(find.text('비밀번호가 일치하지 않아요'), findsNothing);

    await _submit(tester);
    expect(_errorUnder(_confirmKey, '비밀번호가 일치하지 않아요'), findsOneWidget);
    expect(repo.registerCalls, 0);

    await _type(tester, _confirmKey, 'abcdefg1');
    await tester.pump();
    expect(find.text('비밀번호가 일치하지 않아요'), findsNothing);

    await _submit(tester);
    expect(repo.registerCalls, 1);
  });

  // --- 서버 이메일 길이 상한(#2908) --------------------------------------

  testWidgets('255자를 넘는 이메일은 칸 아래에 길이 문구를 보이고 보내지 않는다', (
    WidgetTester tester,
  ) async {
    // 서버 `contact_format.EMAIL_MAX_LENGTH` 가 422 로 돌려보낼 값을 화면이
    // 먼저 잡는다. 전에는 형식만 보고 통과시켜, 제출 뒤에 서버 오류로 떨어졌다.
    final repo = await _pumpSignUp(tester);
    const String domain = '@oncare.com';
    final String tooLong = '${'a' * (256 - domain.length)}$domain';
    final String atLimit = '${'a' * (255 - domain.length)}$domain';

    await _fill(tester, email: tooLong);
    await _submit(tester);

    expect(_errorUnder(_emailKey, '이메일은 255자까지 입력할 수 있어요'), findsOneWidget);
    expect(find.text('이메일 형식이 올바르지 않아요'), findsNothing);
    expect(repo.registerCalls, 0);

    // 딱 255자면 보낸다.
    await _type(tester, _emailKey, atLimit);
    expect(find.text('이메일은 255자까지 입력할 수 있어요'), findsNothing);
    await _submit(tester);
    expect(repo.registerCalls, 1);
    expect(repo.email, atLimit);
  });

  // --- 서버 비밀번호 기준과 같은 상한(#1555) ------------------------------

  testWidgets('64자를 넘으면 칸 아래에 상한을 알리고 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    final String tooLong = '${'a1' * 32}x';

    await _fill(tester, password: tooLong, confirm: tooLong);
    await _submit(tester);

    expect(
      _errorUnder(_passwordKey, '비밀번호는 64자까지 입력할 수 있어요 (한글·이모지는 더 짧게)'),
      findsOneWidget,
    );
    expect(repo.registerCalls, 0);

    // 딱 64자면 보낸다.
    await _type(tester, _passwordKey, 'a1' * 32);
    await _type(tester, _confirmKey, 'a1' * 32);
    await _submit(tester);
    expect(repo.registerCalls, 1);
  });

  testWidgets('한글로 72바이트를 넘으면 64자 안이어도 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    final String hangul = '${'가' * 22}abc1234';

    await _fill(tester, password: hangul, confirm: hangul);
    await _submit(tester);

    expect(
      _errorUnder(_passwordKey, '비밀번호는 64자까지 입력할 수 있어요 (한글·이모지는 더 짧게)'),
      findsOneWidget,
    );
    expect(repo.registerCalls, 0);
  });

  for (final MapEntry<AuthFailure, String> c in <AuthFailure, String>{
    AuthFailure.passwordWeak: '영문과 숫자를 포함해 8자 이상 입력해 주세요',
    AuthFailure.passwordTooLong: '비밀번호는 64자까지 입력할 수 있어요 (한글·이모지는 더 짧게)',
  }.entries) {
    testWidgets('서버가 비밀번호를 거절하면(${c.key.name}) 비밀번호 문구다', (
      WidgetTester tester,
    ) async {
      final repo = await _pumpSignUp(tester, error: AuthException(c.key));

      await _fill(tester);
      await _submit(tester);

      expect(repo.registerCalls, 1);
      expect(find.text(c.value), findsOneWidget);
    });
  }

  // --- 데모 불변 -----------------------------------------------------------

  testWidgets('데모에서도 같은 칸으로 가입이 진행된다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester, demo: true);
    await _fill(tester);
    await _agreeAll(tester);

    await tester.tap(find.text('가입하고 시작하기'));
    await settle(tester);

    expect(repo.registerCalls, 1);
  });

  // --- 가입 동의 (#2819) ---------------------------------------------------

  bool submitEnabled(WidgetTester tester) =>
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey<String>('trainer-signup-submit')),
          )
          .onPressed !=
      null;

  Future<void> tapKey(WidgetTester tester, String key) async {
    final Finder target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
  }

  testWidgets('간주 동의 문구 대신 항목마다 체크가 있다 — 건강정보 항목은 없다', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);

    expect(find.text('가입하면 아래 문서에 동의하는 것으로 봅니다'), findsNothing);
    expect(find.text('전체 동의'), findsOneWidget);
    expect(find.text('[필수] 이용약관 동의'), findsOneWidget);
    expect(find.text('[필수] 개인정보 수집·이용 동의'), findsOneWidget);
    expect(find.text('[필수] 만 14세 이상이에요'), findsOneWidget);
    expect(find.text('[선택] 마케팅 알림 수신'), findsNothing);
    expect(find.byKey(const ValueKey<String>('consent-health')), findsNothing);
  });

  testWidgets('필수 동의 전에는 가입 버튼이 꺼져 있어 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester);

    expect(submitEnabled(tester), isFalse);
    expect(
      find.byKey(const ValueKey<String>('consent-required-hint')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('trainer-signup-submit')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('trainer-signup-submit')),
    );
    await tester.pump();
    expect(repo.registerCalls, 0);
  });

  testWidgets('전체 동의는 켜고 끄며, 필수를 하나라도 끄면 버튼이 꺼진다', (WidgetTester tester) async {
    await _pumpSignUp(tester);

    await tapKey(tester, 'consent-all');
    expect(submitEnabled(tester), isTrue);

    for (final String id in <String>['terms', 'privacy', 'age14']) {
      await tapKey(tester, 'consent-$id');
      expect(submitEnabled(tester), isFalse, reason: id);
      await tapKey(tester, 'consent-$id');
    }

    await tapKey(tester, 'consent-terms');
    await tapKey(tester, 'consent-all'); // 일부만 켜져 있으면 전부 켠다
    expect(submitEnabled(tester), isTrue);
    await tapKey(tester, 'consent-all'); // 전부 켜져 있으면 전부 끈다
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('마케팅 수신 동의는 더는 묻지 않는다 — 선택 항목이 없다 (#3007)', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);

    expect(
      find.byKey(const ValueKey<String>('consent-marketing')),
      findsNothing,
    );
    expect(find.textContaining('[선택]'), findsNothing);
    for (final String id in <String>['terms', 'privacy', 'age14']) {
      expect(find.byKey(ValueKey<String>('consent-$id')), findsOneWidget);
    }
  });

  testWidgets('체크한 항목을 화면 순서대로 가입 요청에 싣는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester);
    for (final String id in <String>['age14', 'privacy', 'terms']) {
      await tapKey(tester, 'consent-$id');
    }

    await _submit(tester);

    expect(repo.registerCalls, 1);
    expect(repo.consents, <String>['terms', 'privacy', 'age14']);
  });

  testWidgets('처리방침 보기는 문서를 열고, 돌아오면 체크가 그대로다', (WidgetTester tester) async {
    await _pumpSignUp(tester);
    await tapKey(tester, 'consent-terms');

    await tapKey(tester, 'consent-view-privacy');
    await settle(tester);
    expect(_shownDocument(tester), AppRoutes.legalPrivacy);

    await tester.tap(find.byTooltip('뒤로'));
    await settle(tester);
    expect(find.byType(LegalDocumentPage), findsNothing);
    expect(currentLocation(tester), AppRoutes.signUp);
    final Checkbox terms = tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('consent-terms')),
        matching: find.byType(Checkbox),
      ),
    );
    expect(terms.value, isTrue);
  });
}
