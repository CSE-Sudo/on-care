import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/data/repositories/signup_email_code_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/signup_email_code_repository.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/my/presentation/pages/legal_document_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 가입 호출의 인자를 기록하는 페이크. 로그인까지는 성공시킨다.
class _RecordingAuthRepository implements TrainerAuthRepository {
  String? email;
  String? name;
  String? emailCode;
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
    required String emailCode,
    List<String>? consents,
  }) async {
    registerCalls++;
    this.emailCode = emailCode;
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

/// 인증 코드 요청을 기록하는 페이크(#3038). 실 서버처럼 데모 코드는 주지 않는다.
class _RecordingCodeRepository implements SignupEmailCodeRepository {
  final List<String> requests = <String>[];

  /// 요청이 던질 실패.
  SignupEmailCodeError? error;

  @override
  Future<SignupEmailCodeSent> request({required String email}) async {
    requests.add(email);
    if (error != null) throw error!;
    return const SignupEmailCodeSent(
      expiresInMinutes: 10,
      resendAfterSeconds: 60,
    );
  }
}

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

/// 실 API 모드 설정.
const AppConfig _realConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

/// 실 API 모드에서 가입 화면이 쓴 인증 코드 페이크. 데모면 목업 그대로다.
late _RecordingCodeRepository _codes;

Future<_RecordingAuthRepository> _pumpSignUp(
  WidgetTester tester, {
  bool demo = false,
  AuthException? error,
  SignupEmailCodeError? codeError,
  Locale locale = const Locale('ko'),
}) async {
  final repo = _RecordingAuthRepository()..error = error;
  _codes = _RecordingCodeRepository()..error = codeError;
  await pumpTrainerApp(
    tester,
    at: AppRoutes.signUp,
    locale: locale,
    extraOverrides: <Override>[
      if (!demo) ...<Override>[
        appConfigProvider.overrideWithValue(_realConfig),
        // 가입 흐름을 보는 테스트다. 대시보드에 내려앉은 뒤의 배지 폴링까지
        // 안고 끝나지 않게 멈춰 둔다.
        ...stillBadges(),
        // 명단도 실 API 에서는 스스로 다시 읽는다(#918). 이 테스트가 보는
        // 것은 가입 요청의 인자다.
        stillRoster(),
        signupEmailCodeRepositoryProvider.overrideWithValue(_codes),
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
const ValueKey<String> _codeKey = ValueKey<String>('trainer-signup-code');
const ValueKey<String> _codeSendKey = ValueKey<String>(
  'trainer-signup-code-send',
);
const ValueKey<String> _codeResendKey = ValueKey<String>(
  'trainer-signup-code-resend',
);

/// 실 서버 코드처럼 생긴 6자리. 데모 코드(000000)와 다르게 둔다.
const String _validCode = '123456';

/// `인증 코드 받기` 를 누른다(#3038). 남은 시간을 정확히 보려고 시간을 흘리지
/// 않는 펌프만 쓴다 — [settle] 은 2초를 흘린다.
Future<void> _requestCode(WidgetTester tester) async {
  final Finder send = find.byKey(_codeSendKey);
  await tester.ensureVisible(send);
  await tester.pump();
  await tester.tap(send);
  await tester.pump();
  await tester.pump();
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  final Finder field = find.descendant(
    of: find.byKey(_codeKey),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, code);
  await tester.pump();
}

/// 칸을 채운다. [code] 가 있으면 이메일을 넣은 뒤 코드를 받아 그 값을 넣는다
/// (#3038) — 코드 6자리가 없으면 가입 버튼이 꺼져 있다.
Future<void> _fill(
  WidgetTester tester, {
  String name = '김신규',
  String email = 'new@oncare.com',
  String password = 'signup-pw-1234',
  String confirm = 'signup-pw-1234',
  String? code = _validCode,
}) async {
  await tester.enterText(find.widgetWithText(TextField, '이름'), name);
  await tester.enterText(find.widgetWithText(TextField, '이메일'), email);
  if (code != null) {
    await _requestCode(tester);
    await _enterCode(tester, code);
  }
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

  testWidgets('이름·이메일·비밀번호와 인증 코드로 가입을 보낸다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester);

    await _submit(tester);

    expect(repo.registerCalls, 1);
    expect(repo.email, 'new@oncare.com');
    expect(repo.name, '김신규');
    expect(repo.emailCode, _validCode);
  });

  testWidgets('비밀번호가 다르면 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester, confirm: 'different-pw1');

    await _submit(tester);

    expect(repo.registerCalls, 0);
    expect(_errorUnder(_confirmKey, '비밀번호가 일치하지 않아요'), findsOneWidget);
  });

  // --- 입력 형식 검사 (#1784) ----------------------------------------------

  testWidgets('빈 이메일로 코드를 받으려 하면 이메일 칸 아래에 알리고 요청하지 않는다', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);

    expect(find.text('이메일을 입력해 주세요'), findsNothing);
    await _requestCode(tester);

    expect(_errorUnder(_emailKey, '이메일을 입력해 주세요'), findsOneWidget);
    expect(_codes.requests, isEmpty);
    expect(find.byKey(_codeKey), findsNothing);
  });

  testWidgets('코드를 받은 뒤 빈칸으로 제출하면 칸마다 아래에 문구를 보이고 보내지 않는다', (
    WidgetTester tester,
  ) async {
    final repo = await _pumpSignUp(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '이메일'),
      'new@oncare.com',
    );
    await _requestCode(tester);
    await _enterCode(tester, _validCode);

    // 제출하기 전에는 아무 칸에도 오류가 없다.
    expect(find.text('이름을 입력해 주세요'), findsNothing);

    await _submit(tester);

    expect(_errorUnder(_nameKey, '이름을 입력해 주세요'), findsOneWidget);
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

  testWidgets('이메일 형식이 틀리면 코드를 요청하지 않는다', (WidgetTester tester) async {
    await _pumpSignUp(tester);
    await tester.enterText(find.widgetWithText(TextField, '이메일'), 'new@oncare');

    await _requestCode(tester);

    expect(_errorUnder(_emailKey, '이메일 형식이 올바르지 않아요'), findsOneWidget);
    expect(_codes.requests, isEmpty);
    expect(find.byKey(_codeKey), findsNothing);
  });

  testWidgets('비밀번호 규칙이 틀리면 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester);

    for (final String weak in <String>['abc123', 'abcdefgh', '12345678']) {
      await _type(tester, _passwordKey, weak);
      await _type(tester, _confirmKey, weak);
      await _submit(tester);

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

    expect(_errorUnder(_emailKey, '이메일은 255자까지 입력할 수 있어요'), findsOneWidget);
    expect(find.text('이메일 형식이 올바르지 않아요'), findsNothing);
    // 코드 요청 단계에서 막힌다 — 가입 요청까지 가지 않는다.
    expect(_codes.requests, isEmpty);
    expect(repo.registerCalls, 0);

    // 딱 255자면 코드를 받고 보낸다.
    await _type(tester, _emailKey, atLimit);
    expect(find.text('이메일은 255자까지 입력할 수 있어요'), findsNothing);
    await _requestCode(tester);
    expect(_codes.requests, <String>[atLimit]);
    await _enterCode(tester, _validCode);
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
    await _fill(tester, code: MockSignupEmailCodeRepository.demoCode);
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
    expect(find.text('[선택] 마케팅 알림 수신'), findsOneWidget);
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
    // 동의 말고 버튼을 끄는 조건(인증 코드, #3038)은 먼저 채워 둔다.
    await _fill(tester);

    await tapKey(tester, 'consent-all');
    expect(submitEnabled(tester), isTrue);

    await tapKey(tester, 'consent-marketing');
    expect(submitEnabled(tester), isTrue, reason: '마케팅은 선택이다');

    for (final String id in <String>['terms', 'privacy', 'age14']) {
      await tapKey(tester, 'consent-$id');
      expect(submitEnabled(tester), isFalse, reason: id);
      await tapKey(tester, 'consent-$id');
    }

    await tapKey(tester, 'consent-all'); // 일부만 켜져 있으면 전부 켠다
    await tapKey(tester, 'consent-all'); // 전부 켜져 있으면 전부 끈다
    expect(submitEnabled(tester), isFalse);
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

  // --- 이메일 인증 코드 (#3038) --------------------------------------------

  bool codeSubmitEnabled(WidgetTester tester) =>
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey<String>('trainer-signup-submit')),
          )
          .onPressed !=
      null;

  AppButton resendButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.byKey(_codeResendKey));

  testWidgets('인증 코드 받기를 누르면 코드 칸·남은 시간·다시 받기가 열린다', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);

    // 받기 전에는 코드 칸이 없다.
    expect(find.byKey(_codeKey), findsNothing);
    expect(find.text(_ko.signUpCodeSend), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '이메일'),
      ' new@oncare.com ',
    );
    await _requestCode(tester);

    expect(_codes.requests, <String>['new@oncare.com']);
    expect(find.byKey(_codeKey), findsOneWidget);
    expect(find.byKey(_codeSendKey), findsNothing);
    expect(find.text(_ko.signUpCodeLabel), findsOneWidget);
    // 가입된 주소든 아니든 같은 안내다.
    expect(find.text(_ko.signUpCodeSentNotice), findsOneWidget);
    expect(find.text(_ko.signUpCodeRemaining('10:00')), findsOneWidget);
    expect(find.text(_ko.signUpCodeResendIn(60)), findsOneWidget);
    expect(resendButton(tester).onPressed, isNull);
    // 실 서버 모드에는 데모 코드 안내가 없다.
    expect(
      find.byKey(const ValueKey<String>('trainer-signup-code-demo')),
      findsNothing,
    );
  });

  testWidgets('6자리를 넣어야 가입 버튼이 켜지고, 숫자만 받는다', (WidgetTester tester) async {
    await _pumpSignUp(tester);
    await _fill(tester, code: null);
    await _agreeAll(tester);

    // 코드를 받기 전에는 동의를 다 해도 꺼져 있다.
    expect(codeSubmitEnabled(tester), isFalse);

    await tester.enterText(
      find.widgetWithText(TextField, '이메일'),
      'new@oncare.com',
    );
    await _requestCode(tester);
    expect(codeSubmitEnabled(tester), isFalse);

    await _enterCode(tester, '12345');
    expect(codeSubmitEnabled(tester), isFalse);

    await _enterCode(tester, '12a4b6');
    final TextField field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(_codeKey),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, '1246');
    expect(codeSubmitEnabled(tester), isFalse);

    await _enterCode(tester, '1234567');
    expect(field.controller!.text, '123456');
    expect(codeSubmitEnabled(tester), isTrue);
  });

  testWidgets('코드를 받은 뒤 이메일을 고치면 코드 칸을 비우고 닫는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester);
    await _agreeAll(tester);
    expect(codeSubmitEnabled(tester), isTrue);

    await _type(tester, _emailKey, 'other@oncare.com');

    expect(find.byKey(_codeKey), findsNothing);
    expect(find.byKey(_codeSendKey), findsOneWidget);
    expect(codeSubmitEnabled(tester), isFalse);
    expect(repo.registerCalls, 0);

    // 새 주소로 다시 받으면 빈 코드 칸이 열린다.
    await _requestCode(tester);
    expect(_codes.requests, <String>['new@oncare.com', 'other@oncare.com']);
    final TextField field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(_codeKey),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('대소문자·공백만 바꾼 이메일은 같은 코드를 그대로 둔다', (WidgetTester tester) async {
    await _pumpSignUp(tester);
    await _fill(tester);

    await _type(tester, _emailKey, 'NEW@oncare.com ');

    expect(find.byKey(_codeKey), findsOneWidget);
  });

  for (final MapEntry<AuthFailure, String> c in <AuthFailure, String>{
    AuthFailure.emailCodeInvalid: '인증 코드가 맞지 않거나 만료됐어요. 코드를 다시 받아 주세요.',
    AuthFailure.emailCodeRequired: '이메일 인증 코드를 입력해 주세요.',
  }.entries) {
    testWidgets('서버가 코드를 거절하면(${c.key.name}) 코드 칸 아래에 알리고 폼을 지킨다', (
      WidgetTester tester,
    ) async {
      final repo = await _pumpSignUp(tester, error: AuthException(c.key));
      await _fill(tester);

      await _submit(tester);

      expect(repo.registerCalls, 1);
      expect(_errorUnder(_codeKey, c.value), findsOneWidget);
      // 화면은 그대로다 — 다른 칸의 값도 남는다.
      expect(currentLocation(tester), AppRoutes.signUp);
      expect(find.text('김신규'), findsOneWidget);

      // 코드를 고치면 문구가 사라진다.
      await _enterCode(tester, '654321');
      expect(find.text(c.value), findsNothing);
    });
  }

  testWidgets('남은 시간이 흐르고, 다 지나면 만료 안내로 바뀐다', (WidgetTester tester) async {
    await _pumpSignUp(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '이메일'),
      'new@oncare.com',
    );
    await _requestCode(tester);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_ko.signUpCodeRemaining('9:59')), findsOneWidget);
    expect(find.text(_ko.signUpCodeResendIn(59)), findsOneWidget);

    await tester.pump(const Duration(minutes: 10));
    expect(find.text(_ko.signUpCodeExpired), findsOneWidget);
  });

  testWidgets('다시 받기는 대기 시간이 지나야 눌리고, 누르면 새 코드를 받는다', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '이메일'),
      'new@oncare.com',
    );
    await _requestCode(tester);
    await _enterCode(tester, '111111');

    expect(resendButton(tester).onPressed, isNull);
    await tester.pump(const Duration(seconds: 59));
    expect(resendButton(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_ko.signUpCodeResend), findsOneWidget);
    expect(resendButton(tester).onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(_codeResendKey));
    await tester.pump();
    await tester.tap(find.byKey(_codeResendKey));
    await tester.pump();
    await tester.pump();

    expect(_codes.requests, <String>['new@oncare.com', 'new@oncare.com']);
    // 새 코드를 받았으니 칸을 비우고 대기·유효 시간을 다시 센다.
    final TextField field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(_codeKey),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, isEmpty);
    expect(find.text(_ko.signUpCodeResendIn(60)), findsOneWidget);
    expect(find.text(_ko.signUpCodeRemaining('10:00')), findsOneWidget);
  });

  for (final MapEntry<SignupEmailCodeFailure, String> c
      in <SignupEmailCodeFailure, String>{
        SignupEmailCodeFailure.tooMany: '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.',
        SignupEmailCodeFailure.unavailable:
            '지금은 인증 메일을 보낼 수 없어요. 잠시 후 다시 시도해 주세요.',
        SignupEmailCodeFailure.temporary: '인증 코드를 보내지 못했어요. 잠시 후 다시 시도해 주세요.',
      }.entries) {
    testWidgets('코드 요청이 실패하면(${c.key.name}) 알리고 칸을 열지 않는다', (
      WidgetTester tester,
    ) async {
      await _pumpSignUp(tester, codeError: SignupEmailCodeError(c.key));
      await tester.enterText(
        find.widgetWithText(TextField, '이메일'),
        'new@oncare.com',
      );
      await _requestCode(tester);
      await tester.pump();

      expect(find.text(c.value), findsOneWidget);
      expect(find.byKey(_codeKey), findsNothing);
      expect(find.byKey(_codeSendKey), findsOneWidget);
    });
  }

  testWidgets('데모에서는 데모 코드를 안내하고, 그 코드로 가입된다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester, demo: true);
    await tester.enterText(
      find.widgetWithText(TextField, '이메일'),
      'new@oncare.com',
    );
    await _requestCode(tester);

    final Finder demo = find.byKey(
      const ValueKey<String>('trainer-signup-code-demo'),
    );
    expect(demo, findsOneWidget);
    expect(
      find.descendant(
        of: demo,
        matching: find.text(
          _ko.signUpCodeDemoNote(MockSignupEmailCodeRepository.demoCode),
        ),
      ),
      findsOneWidget,
    );
    // 안내만 한다 — 칸을 대신 채우지 않는다.
    final TextField field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(_codeKey),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, isEmpty);

    // 이메일은 건드리지 않고 나머지 칸을 채운다 — 고치면 코드가 버려진다.
    await _type(tester, _nameKey, '김신규');
    await _type(tester, _passwordKey, 'signup-pw-1234');
    await _type(tester, _confirmKey, 'signup-pw-1234');
    await _enterCode(tester, MockSignupEmailCodeRepository.demoCode);
    await _submit(tester);
    expect(repo.emailCode, MockSignupEmailCodeRepository.demoCode);
  });

  testWidgets('영어 화면은 코드 단계도 영어다', (WidgetTester tester) async {
    await _pumpSignUp(tester, locale: const Locale('en'));

    expect(find.text(_en.signUpCodeSend), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(_emailKey),
        matching: find.byType(TextField),
      ),
      'new@oncare.com',
    );
    await _requestCode(tester);

    expect(find.text(_en.signUpCodeLabel), findsOneWidget);
    expect(find.text(_en.signUpCodeSentNotice), findsOneWidget);
    expect(find.text(_en.signUpCodeRemaining('10:00')), findsOneWidget);
    expect(find.text(_en.signUpCodeResendIn(60)), findsOneWidget);
    expect(_en.signUpCodeResendIn(60), 'Resend in 60s');
  });
}
