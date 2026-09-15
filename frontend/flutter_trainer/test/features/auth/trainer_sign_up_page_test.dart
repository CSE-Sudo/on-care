import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

import '../../helpers/pump_app.dart';

/// 가입 호출의 인자를 기록하는 페이크. 로그인까지는 성공시킨다.
class _RecordingAuthRepository implements TrainerAuthRepository {
  String? email;
  String? name;
  String? inviteCode;
  int registerCalls = 0;

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
    required String inviteCode,
  }) async {
    registerCalls++;
    this.email = email;
    this.name = name;
    this.inviteCode = inviteCode;
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
        career: '',
        intro: '',
        certifications: <String>[],
        gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
      );
}

/// 실 API 모드 설정 — 초대 코드 입력이 그려지는 쪽.
const AppConfig _realConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

Future<_RecordingAuthRepository> _pumpSignUp(
  WidgetTester tester, {
  bool demo = false,
}) async {
  final repo = _RecordingAuthRepository();
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
const ValueKey<String> _codeKey = ValueKey<String>(
  'trainer-signup-invite-code',
);

Future<void> _fill(
  WidgetTester tester, {
  String name = '김신규',
  String email = 'new@oncare.com',
  String password = 'signup-pw-1234',
  String confirm = 'signup-pw-1234',
  String? code,
}) async {
  await tester.enterText(find.widgetWithText(TextField, '이름'), name);
  await tester.enterText(find.widgetWithText(TextField, '이메일'), email);
  // 비밀번호 안내가 새 규칙을 말한다(#1784).
  await tester.enterText(
    find.widgetWithText(TextField, '비밀번호 (영문·숫자 포함 8자 이상)'),
    password,
  );
  await tester.enterText(find.widgetWithText(TextField, '비밀번호 확인'), confirm);
  if (code != null) {
    await tester.enterText(find.widgetWithText(TextField, '헬스장 초대 코드'), code);
  }
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
  // 도움말이 있는 칸(초대 코드)은 오류 문구가 도움말로 서서히 바뀐다
  // (Material 167ms). 전환이 끝나야 사라진 문구가 트리에서도 빠진다.
  await tester.pump(const Duration(milliseconds: 200));
}

/// 오류 문구가 늘어 버튼이 화면 밖으로 밀려도 누를 수 있게 끌어온다.
Future<void> _submit(WidgetTester tester) async {
  final Finder submit = find.byKey(
    const ValueKey<String>('trainer-signup-submit'),
  );
  await tester.ensureVisible(submit);
  await tester.pump();
  await tester.tap(submit);
  await settle(tester);
}

/// [key] 칸 **안에**(입력창 아래 오류 자리) [message] 가 그려졌는가.
Finder _errorUnder(ValueKey<String> key, String message) =>
    find.descendant(of: find.byKey(key), matching: find.text(message));

void main() {
  testWidgets('가입 화면에 초대 코드 입력이 있다', (WidgetTester tester) async {
    await _pumpSignUp(tester);

    expect(find.widgetWithText(TextField, '헬스장 초대 코드'), findsOneWidget);
    expect(find.text('소속 헬스장에서 발급받은 코드를 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('초대 코드를 그대로 실어 보낸다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester, code: 'ONCARE1');

    await _submit(tester);

    expect(repo.registerCalls, 1);
    expect(repo.inviteCode, 'ONCARE1');
    expect(repo.email, 'new@oncare.com');
  });

  testWidgets('코드 앞뒤 공백은 정리해서 보낸다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester, code: '  ONCARE1  ');

    await _submit(tester);

    expect(repo.inviteCode, 'ONCARE1');
  });

  testWidgets('코드 없이는 가입 요청을 보내지 않는다', (WidgetTester tester) async {
    // 코드가 소속을 결정하므로, 없으면 서버에 물어볼 것도 없다.
    final repo = await _pumpSignUp(tester);
    await _fill(tester);

    await _submit(tester);

    expect(repo.registerCalls, 0);
    // 코드 칸 아래에서 안내 대신 오류 문구가 뜬다(#1784).
    expect(_errorUnder(_codeKey, '헬스장에서 받은 초대 코드를 입력해 주세요'), findsOneWidget);
    expect(find.text('소속 헬스장에서 발급받은 코드를 입력해 주세요.'), findsNothing);

    // 코드를 넣으면 오류가 사라지고 안내가 돌아온다.
    await _type(tester, _codeKey, 'ONCARE1');
    await tester.pump();
    expect(find.text('헬스장에서 받은 초대 코드를 입력해 주세요'), findsNothing);
    expect(find.text('소속 헬스장에서 발급받은 코드를 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('비밀번호가 다르면 코드가 있어도 보내지 않는다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester);
    await _fill(tester, confirm: 'different-pw1', code: 'ONCARE1');

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
    expect(_errorUnder(_codeKey, '헬스장에서 받은 초대 코드를 입력해 주세요'), findsOneWidget);
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
    await _fill(tester, name: '   ', code: 'ONCARE1');
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
      await _fill(
        tester,
        email: 'new@oncare',
        password: weak,
        confirm: weak,
        code: 'ONCARE1',
      );
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
    await _fill(tester, password: 'abcdefgh', confirm: 'abcdefgh', code: 'C1');

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

  // --- 데모 불변 -----------------------------------------------------------

  testWidgets('데모 가입 화면에는 코드 입력이 없다', (WidgetTester tester) async {
    // 데모에는 코드를 검증할 백엔드가 없다. 무엇을 넣어도 통과하는 죽은 입력을
    // 두느니 그리지 않는다 — 데모 화면이 지금 그대로여야 한다.
    await _pumpSignUp(tester, demo: true);

    expect(find.widgetWithText(TextField, '헬스장 초대 코드'), findsNothing);
    expect(find.text('소속 헬스장에서 발급받은 코드를 입력해 주세요.'), findsNothing);
  });

  testWidgets('데모에서는 코드 없이도 가입이 진행된다', (WidgetTester tester) async {
    final repo = await _pumpSignUp(tester, demo: true);
    await _fill(tester);

    await tester.tap(find.text('가입하고 시작하기'));
    await settle(tester);

    expect(repo.registerCalls, 1);
    expect(repo.inviteCode, '');
  });
}
