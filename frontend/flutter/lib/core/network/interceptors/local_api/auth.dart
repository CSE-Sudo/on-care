// 로그인·가입 경로(/auth/*).

part of '../local_api_interceptor.dart';

extension _LocalApiAuth on LocalApiInterceptor {
  /// POST /auth/login — the demo accepts any non-empty credentials and
  /// issues a token so the login flow works without a server. Real
  /// credentials are validated by FastAPI when USE_MOCK_API=false.
  ///
  /// 이 데모에서 가입한 이메일만은 서버처럼 가입한 비밀번호를 본다(#2665) —
  /// 틀리면 서버와 같은 401 이다. 그 밖의 이메일은 지금처럼 데모 회원으로 든다.
  Future<Response<Object?>> _authLogin(RequestOptions options) async {
    final body = _jsonBody(options);
    final username = (body['username'] as String? ?? '').trim();
    final password = (body['password'] as String? ?? '').trim();
    if (username.isEmpty || password.isEmpty) {
      return _badRequest(options, 'username and password are required');
    }
    final Map<String, Object?>? account = await _accounts.find(username);
    if (account != null && account['password'] != body['password']) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 401,
        data: <String, Object?>{'detail': '이메일 또는 비밀번호가 올바르지 않습니다.'},
      );
    }
    await _accounts.signIn(account == null ? null : username);
    // 데모 회원으로 든 비밀번호를 남긴다 — 이메일 변경·탈퇴의 본인 확인이 이 값을
    // 본다(#3039). 가입 계정은 가입한 비밀번호를 본다.
    await _accounts.rememberDemoLogin(
      password: account == null ? body['password'] as String? : null,
    );
    await _resetDemoNotificationReads();
    return _ok(options, <String, Object?>{
      'access_token': 'demo-access-${DateTime.now().microsecondsSinceEpoch}',
      'refresh_token': 'demo-refresh',
      'token_type': 'bearer',
    });
  }

  /// POST /auth/register — mirrors FastAPI: returns the created user
  /// `{id, name, email}` with 201. `name` defaults to the email local-part.
  ///
  /// 가입한 계정은 [DemoAccounts] 에 남는다(#2665). 새 계정은 첫 설정 전의 빈
  /// 프로필로 시작해, 로그인하면 실서버처럼 첫 설정으로 간다. 이미 있는
  /// 이메일(데모 회원·데모 세계의 다른 계정·이 데모에서 가입한 계정)은 서버와
  /// 같은 409 로 거절한다.
  ///
  /// 비밀번호는 서버와 같은 기준(`AppInputRules.signUpPassword`, #1555)을 보고,
  /// 어기면 서버와 같은 모양의 422(`detail[].type` 코드)를 준다 — 목업에서만
  /// 가입되는 비밀번호가 있으면 실서버에서 처음 실패를 보게 된다. 서버처럼
  /// 비밀번호의 앞뒤 공백은 자르지 않는다.
  Future<Response<Object?>> _authRegister(RequestOptions options) async {
    final body = _jsonBody(options);
    final email = (body['email'] as String? ?? '').trim();
    final password = body['password'] as String? ?? '';
    final name = (body['name'] as String? ?? '').trim();
    if (email.isEmpty) {
      return _badRequest(options, 'email and password are required');
    }
    final String? passwordCode = switch (AppInputRules.signUpPassword(
      password,
    )) {
      null => null,
      AppInputError.passwordEmpty => 'password_empty',
      AppInputError.passwordTooLong => 'password_too_long',
      _ => 'password_weak',
    };
    // 동의 목록을 보냈다면 서버처럼 필수 항목을 본다(#2819). 보내지 않은 옛
    // 빌드의 가입은 막지 않는다.
    final List<String> missingConsents = _missingConsents(body['consents']);
    if (missingConsents.isNotEmpty) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <Object?>[
            <String, Object?>{
              'type': 'value_error',
              'loc': <Object?>['body'],
              'msg': 'consent_required: ${missingConsents.join(', ')}',
            },
          ],
        },
      );
    }
    if (passwordCode != null) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <Object?>[
            <String, Object?>{
              'type': passwordCode,
              'loc': <Object?>['body', 'password'],
              'msg': passwordCode,
            },
          ],
        },
      );
    }
    if (await _isTakenEmail(email)) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 409,
        data: <String, Object?>{'detail': '이미 가입된 이메일입니다.'},
      );
    }
    // 이메일 인증 코드(#3038) — 서버처럼 중복 확인 뒤에 본다. 데모는 메일을
    // 보내지 않으므로 고정 코드 하나만 받는다.
    final String code = (body['email_code'] as String? ?? '').trim();
    if (code.isEmpty) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <String, Object?>{
            'code': 'email_code_required',
            'message': '이메일 인증 코드를 입력해 주세요.',
          },
        },
      );
    }
    if (code != SignupEmailCode.demoCode) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 400,
        data: <String, Object?>{
          'detail': <String, Object?>{
            'code': 'invalid_email_code',
            'message': '인증 코드가 맞지 않거나 만료되었습니다. 코드를 다시 받아 주세요.',
          },
        },
      );
    }
    // 서버 계정 id 와 같은 `user-<12자리 hex>` 모양이다.
    final String hex = DateTime.now().microsecondsSinceEpoch
        .toRadixString(16)
        .padLeft(12, '0');
    final String id = 'user-${hex.substring(hex.length - 12)}';
    final String savedName = name.isEmpty ? email.split('@').first : name;
    await _accounts.add(
      id: id,
      email: email,
      password: password,
      name: savedName,
      phone: (body['phone'] as String? ?? '').trim(),
    );
    return Response<Object?>(
      requestOptions: options,
      statusCode: 201,
      data: <String, Object?>{'id': id, 'name': savedName, 'email': email},
    );
  }

  /// POST /auth/register/email-code — 가입 인증 코드 요청(#3038).
  ///
  /// 서버처럼 이메일이 가입돼 있든 아니든 같은 202 다. 데모는 메일을 보내지 않고,
  /// 가입은 [SignupEmailCode.demoCode] 를 받는다. 형식이 틀린 이메일·모르는
  /// 용도는 서버와 같은 422 목록이다.
  Future<Response<Object?>> _authRegisterEmailCode(
    RequestOptions options,
  ) async {
    final body = _jsonBody(options);
    final String email = (body['email'] as String? ?? '').trim();
    final Object? purpose = body['purpose'];
    final bool knownPurpose =
        purpose == 'member_signup' || purpose == 'trainer_signup';
    if (AppInputRules.email(email) != null || !knownPurpose) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <Object?>[
            <String, Object?>{
              'type': 'value_error',
              'loc': <Object?>[
                'body',
                if (knownPurpose) 'email' else 'purpose',
              ],
              'msg': 'invalid',
            },
          ],
        },
      );
    }
    return Response<Object?>(
      requestOptions: options,
      statusCode: 202,
      data: <String, Object?>{
        'expires_in_minutes': 10,
        'resend_after_seconds': 60,
      },
    );
  }

  /// 다른 계정이 이미 쓰는 이메일인가 — 데모 회원·데모 세계의 다른 계정
  /// ([_demoTakenEmails])·이 데모에서 가입한 계정. (#2665)
  Future<bool> _isTakenEmail(String email) async {
    final String key = DemoAccounts.normalize(email);
    return key == DemoAccounts.demoEmail ||
        _demoTakenEmails.contains(key) ||
        await _accounts.find(key) != null;
  }

  /// POST /auth/logout — 데모에는 폐기할 서버 세션이 없다. 여기서 받아 주지 않으면
  /// 목업 모드의 로그아웃이 실 네트워크로 새어 나가 타임아웃까지 멎는다(#966).
  Future<Response<Object?>> _authLogout(RequestOptions options) async {
    return Response<Object?>(requestOptions: options, statusCode: 204);
  }

  /// POST /auth/refresh — 데모도 접근 토큰을 회전해 준다. (#1944)
  ///
  /// 데모 라우트 표에 이것이 빠져 있어, 목 빌드의 갱신 요청이 두 인터셉터를 모두
  /// 지나쳐 **실제 `apiBaseUrl` 로 나갔다** — #966 이 `/auth/logout` 에 대해
  /// 막았던 그 누출이 갱신 경로에 남아 있었다.
  ///
  /// 갱신 토큰은 쓰던 것을 그대로 돌려준다. 실서버도 회전 토큰을 항상 새로 주는
  /// 것은 아니라, 앱이 둘 다 다룰 수 있어야 한다.
  Future<Response<Object?>> _authRefresh(RequestOptions options) async {
    final body = _jsonBody(options);
    final refresh = (body['refresh_token'] as String? ?? '').trim();
    if (refresh.isEmpty) {
      return _badRequest(options, 'refresh_token is required');
    }
    return _ok(options, <String, Object?>{
      'access_token': 'demo-access-${DateTime.now().microsecondsSinceEpoch}',
      'refresh_token': refresh,
      'token_type': 'bearer',
    });
  }

  /// POST /auth/social/{provider} — the demo exchanges any non-empty
  /// provider token for a session. Real provider-token verification is
  /// done by FastAPI (+ provider SDK) when USE_MOCK_API=false.
  Future<Response<Object?>> _authSocial(RequestOptions options) async {
    final body = _jsonBody(options);
    final token = (body['token'] as String? ?? '').trim();
    if (token.isEmpty) {
      return _badRequest(options, 'token is required');
    }
    // 데모의 소셜 로그인은 데모 회원으로 든다 — 가입 계정에서 바꿔 들어와도.
    await _accounts.signIn(null);
    // 소셜로 든 데모 회원은 비밀번호 없는 계정처럼 본인 확인을 소셜 재로그인으로
    // 한다(#3039). 어느 provider 로 들었는지 남겨 그 provider 만 받는다.
    await _accounts.rememberDemoLogin(
      socialProvider: options.path.split('/').last,
    );
    await _resetDemoNotificationReads();
    return _ok(options, <String, Object?>{
      'access_token': 'demo-social-${DateTime.now().microsecondsSinceEpoch}',
      'refresh_token': 'demo-refresh',
      'token_type': 'bearer',
    });
  }
}

/// 데모 세계에서 **다른 계정이 이미 쓰는** 이메일(#2639).
///
/// 회원 앱 데모는 김민수 한 명으로 돌지만, 같은 세계의 트레이너와 다른 담당
/// 회원은 백엔드 시드(`backend/app/db/seed_trainer.py` 의 `TRAINER_EMAIL`·
/// `_MEMBERS`)에 계정으로 있다. 그 주소로 바꾸면 실서버처럼 409 로 거절한다 —
/// 목업에서만 되는 저장이 있으면 실서버에서 처음 거절을 보게 된다.
const Set<String> _demoTakenEmails = <String>{
  'trainer@oncare.com',
  'jisu@oncare.com',
  'sungho@oncare.com',
  'hayun@oncare.demo',
  'woojin@oncare.demo',
  'kangseoyeon@oncare.demo',
  'dohyun@oncare.demo',
  'sera@oncare.demo',
  'junhyuk@oncare.demo',
  'yuna@oncare.demo',
  'jiho@oncare.demo',
  'gayoung@oncare.demo',
  'taekyung@oncare.demo',
  'seojin@oncare.demo',
  'eunchae@oncare.demo',
};
