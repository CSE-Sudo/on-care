/// 트레이너 비밀번호 변경 — 새 비밀번호가 가입과 같은 서버 기준을 따른다(#1555).
///
/// 전에는 길이(8자)만 봐서 숫자만 쓴 값은 서버에서 422 로 막혔고, 그 실패가
/// 현재 비밀번호 칸 아래에 기본 문구로 붙었다. 여기서 고정하는 것:
///
///  * 화면이 서버와 같은 기준(영문·숫자 포함 8자 이상, 64자·72바이트 이하)을
///    먼저 보고, 새 비밀번호 칸 아래에 알린다.
///  * 서버가 새 비밀번호를 거절하면(코드가 실린 422) 새 비밀번호 칸 아래에
///    이 앱의 문구로 알린다.
///  * 현재 비밀번호 불일치(400)는 예전처럼 현재 비밀번호 칸 아래다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/my/data/trainer_account_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

/// 변경 호출을 기록하고 [error] 를 던지는 페이크.
class _FakeAccountRepository implements TrainerAccountRepository {
  _FakeAccountRepository({this.error});

  final Object? error;
  final List<String> newPasswords = <String>[];

  @override
  bool get supportsPasswordChange => true;

  @override
  bool get supportsDeletion => true;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    newPasswords.add(newPassword);
    if (error != null) throw error!;
  }

  @override
  Future<void> deleteAccount() async {}
}

Future<_FakeAccountRepository> _openDialog(
  WidgetTester tester, {
  Object? error,
}) async {
  final repo = _FakeAccountRepository(error: error);
  await pumpTrainerApp(
    tester,
    token: 'demo-token',
    // 비밀번호 변경은 설정 › 계정에 있다(#2264).
    at: AppRoutes.mySection('account'),
    extraOverrides: <Override>[
      trainerAccountRepositoryProvider.overrideWithValue(repo),
    ],
  );
  final button = find.byKey(const ValueKey<String>('change-password'));
  await tester.ensureVisible(button);
  await settle(tester);
  await tester.tap(button);
  await settle(tester);
  return repo;
}

Finder _field(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

Finder _under(String key, String message) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.text(message),
);

Future<void> _fill(
  WidgetTester tester, {
  String current = 'old-pw-1',
  required String next,
  String? confirm,
}) async {
  await tester.enterText(_field('password-current'), current);
  await tester.enterText(_field('password-new'), next);
  await tester.enterText(_field('password-confirm'), confirm ?? next);
  await settle(tester);
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text(_ko.actionChange).last);
  await settle(tester);
}

void main() {
  testWidgets('새 비밀번호 칸 안내가 영문·숫자 규칙을 말한다', (tester) async {
    await _openDialog(tester);

    expect(find.text(_ko.myPwNew(8)), findsOneWidget);
    expect(_ko.myPwNew(8), contains('영문·숫자'));
    expect(_en.myPwNew(8), contains('letters and numbers'));
  });

  for (final String weak in <String>['12345678', 'abcdefgh', 'abc1234']) {
    testWidgets('기준 미달($weak)은 새 비밀번호 칸 아래에 알리고 보내지 않는다', (tester) async {
      final repo = await _openDialog(tester);

      await _fill(tester, next: weak);
      await _confirm(tester);

      expect(_under('password-new', _ko.authErrPasswordWeak), findsOneWidget);
      expect(_under('password-current', _ko.authErrPasswordWeak), findsNothing);
      expect(repo.newPasswords, isEmpty);
    });
  }

  testWidgets('64자를 넘으면 상한 문구를 알리고 보내지 않는다', (tester) async {
    final repo = await _openDialog(tester);

    await _fill(tester, next: '${'a1' * 32}x');
    await _confirm(tester);

    expect(_under('password-new', _ko.authErrPasswordTooLong), findsOneWidget);
    expect(repo.newPasswords, isEmpty);
  });

  testWidgets('한글로 72바이트를 넘어도 상한 문구다', (tester) async {
    final repo = await _openDialog(tester);

    await _fill(tester, next: '${'가' * 22}abc1234');
    await _confirm(tester);

    expect(_under('password-new', _ko.authErrPasswordTooLong), findsOneWidget);
    expect(repo.newPasswords, isEmpty);
  });

  testWidgets('기준에 맞으면 보낸다 — 딱 64자까지', (tester) async {
    final repo = await _openDialog(tester);

    await _fill(tester, next: 'a1' * 32);
    await _confirm(tester);

    expect(repo.newPasswords, <String>['a1' * 32]);
  });

  testWidgets('서버가 새 비밀번호를 거절하면 새 비밀번호 칸 아래에 알린다', (tester) async {
    final repo = await _openDialog(
      tester,
      error: const NewPasswordRejected(AppInputError.passwordTooLong),
    );

    await _fill(tester, next: 'abcd1234');
    await _confirm(tester);

    expect(repo.newPasswords, hasLength(1));
    expect(_under('password-new', _ko.authErrPasswordTooLong), findsOneWidget);
    expect(find.text(_ko.myPwChangeFailed), findsNothing);
  });

  testWidgets('현재 비밀번호 불일치는 예전처럼 현재 비밀번호 칸 아래다', (tester) async {
    await _openDialog(
      tester,
      error: const ValidationError(message: '현재 비밀번호가 일치하지 않습니다.'),
    );

    await _fill(tester, next: 'abcd1234');
    await _confirm(tester);

    expect(_under('password-current', '현재 비밀번호가 일치하지 않습니다.'), findsOneWidget);
  });

  group('DioTrainerAccountRepository — 새 비밀번호 422', () {
    late _MockDio dio;
    late DioTrainerAccountRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioTrainerAccountRepository(dio);
    });

    void answer(int status, Object? body) {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/trainer/me/password',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/trainer/me/password'),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/trainer/me/password'),
            statusCode: status,
            data: body,
          ),
        ),
      );
    }

    Map<String, Object?> detail(String type) => <String, Object?>{
      'detail': <Object?>[
        <String, Object?>{
          'type': type,
          'loc': <Object?>['body', 'new_password'],
          'msg': '서버 문장',
        },
      ],
    };

    for (final MapEntry<String, AppInputError> c in <String, AppInputError>{
      'password_empty': AppInputError.passwordEmpty,
      'password_weak': AppInputError.passwordWeak,
      'password_too_long': AppInputError.passwordTooLong,
    }.entries) {
      test('${c.key} → NewPasswordRejected(${c.value.name})', () async {
        answer(422, detail(c.key));
        await expectLater(
          repo.changePassword(currentPassword: 'old', newPassword: 'x'),
          throwsA(
            isA<NewPasswordRejected>().having(
              (e) => e.reason,
              'reason',
              c.value,
            ),
          ),
        );
      });
    }

    test('비밀번호 코드가 없는 422 는 예전처럼 ValidationError', () async {
      answer(422, detail('missing'));
      await expectLater(
        repo.changePassword(currentPassword: 'old', newPassword: 'x'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e is NewPasswordRejected,
            'is NewPasswordRejected',
            isFalse,
          ),
        ),
      );
    });

    test('400 은 서버 사유를 그대로 싣는다', () async {
      answer(400, <String, Object?>{'detail': '현재 비밀번호가 일치하지 않습니다.'});
      await expectLater(
        repo.changePassword(currentPassword: 'old', newPassword: 'x'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            '현재 비밀번호가 일치하지 않습니다.',
          ),
        ),
      );
    });
  });
}

class _MockDio extends Mock implements Dio {}
