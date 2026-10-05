import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/auth/data/dtos/trainer_me_dto.dart';
import 'package:oncare_trainer/features/auth/data/repositories/mock_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppInputError, AppInputRules;

/// Real trainer auth against the FastAPI backend. Selected when
/// `USE_MOCK_API=false` (see [trainerAuthRepositoryProvider]).
class DioTrainerAuthRepository implements TrainerAuthRepository {
  DioTrainerAuthRepository(this._dio);

  final Dio _dio;

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async {
    return _tokenCall(
      () => _dio.post<Map<String, Object?>>(
        '/auth/login',
        data: <String, Object?>{'username': email, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
      on401: AuthFailure.invalidCredentials,
    );
  }

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String emailCode,
    List<String>? consents,
  }) async {
    try {
      // 회원용 `/auth/register` 가 아니다 — 그쪽은 role='member' 를 만들어,
      // 가입은 되는데 `/trainer/me` 가 403 을 주는 계정이 생겼다. (#475)
      await _dio.post<Map<String, Object?>>(
        '/auth/trainer/register',
        data: <String, Object?>{
          'email': email,
          'password': password,
          'name': name,
          // 가입 전에 받은 이메일 인증 코드(#3038).
          'email_code': emailCode,
          // 체크한 동의(#2819) — 계정과 한 트랜잭션으로 남는다. 넘기지 않으면
          // 칸을 싣지 않는다(서버는 기록 없이 만들고 로그인 뒤 동의를 받는다).
          'consents': ?consents,
        },
      );
    } on DioException catch (e) {
      final int? status = e.response?.statusCode;
      final String? code = serverDetailCode(e.response?.data);
      if (status == 409) {
        throw const AuthException(AuthFailure.emailTaken);
      }
      // 인증 코드 문제는 코드 칸 아래에 알린다(#3038). 중복 이메일(409)은 서버가
      // 코드보다 먼저 본다.
      if (status == 400 && code == 'invalid_email_code') {
        throw const AuthException(AuthFailure.emailCodeInvalid);
      }
      if (status == 422 && code == 'email_code_required') {
        throw const AuthException(AuthFailure.emailCodeRequired);
      }
      if (status == 422) {
        // 비밀번호가 서버 기준(#1555)에 걸렸으면 그 이유를 알린다. 나머지 422
        // (형식 오류 등)는 화면이 미리 거르는 값이라 알 수 없는 오류로 둔다.
        final AuthFailure? password = _passwordFailure(e.response?.data);
        if (password != null) throw AuthException(password);
      }
      throw _asAuth(e);
    }
    // Registration returns the created user, not a token — sign in next.
    return login(email: email, password: password);
  }

  /// 422 본문의 비밀번호 코드 → 가입 실패 종류. 비밀번호 오류가 없으면 null.
  static AuthFailure? _passwordFailure(Object? data) =>
      switch (AppInputRules.serverPasswordError(data)) {
        null => null,
        AppInputError.passwordTooLong => AuthFailure.passwordTooLong,
        _ => AuthFailure.passwordWeak,
      };

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async {
    return _tokenCall(
      () => _dio.post<Map<String, Object?>>(
        '/auth/social/$provider',
        data: <String, Object?>{'token': token},
      ),
      on401: AuthFailure.unknown,
    );
  }

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async {
    return _tokenCall(
      () => _dio.post<Map<String, Object?>>(
        '/auth/refresh',
        data: <String, Object?>{'refresh_token': refreshToken},
      ),
      on401: AuthFailure.sessionExpired,
      // 회원 앱과 같은 기준 — 갱신을 403 으로 거부해도 세션의 끝이다(#1546).
      on403: AuthFailure.sessionExpired,
    );
  }

  @override
  Future<void> logout(String refreshToken) async {
    if (refreshToken.isEmpty) return;
    await _dio
        .post<void>(
          '/auth/logout',
          data: <String, Object?>{'refresh_token': refreshToken},
        )
        // 기본 타임아웃(연결 10초)을 그대로 기다리면 로그아웃 버튼이 그만큼 멎는다.
        // 폐기는 성사되면 좋은 일이지 사용자를 붙잡을 일이 아니다.
        .timeout(const Duration(seconds: 3));
  }

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async {
    try {
      final res = await _dio.get<Map<String, Object?>>(
        '/trainer/me',
        options: Options(
          headers: <String, Object?>{'Authorization': 'Bearer $accessToken'},
        ),
      );
      final data = res.data;
      if (data == null) {
        // 문구는 화면이 붙인다. (#501)
        throw const ServerError();
      }
      return trainerProfileFromJson(data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403) {
        throw const NotTrainerException();
      }
      if (code == 401) {
        // Surfaced to SessionController so it can attempt a token refresh.
        // 서버 사유만 싣는다 — Dio 원문은 화면에 뜰 수 있는 자리에 두지 않는다.
        throw UnauthorizedError(
          message: serverDetailText(e.response?.data),
          cause: e,
        );
      }
      // Transport failures (network/timeout/5xx) surface as a typed
      // [AppError] — NOT [AuthException] — so SessionController's restore
      // keeps the stored tokens on a transient failure instead of forcing
      // a sign-out (review: don't discard a valid session on a blip).
      throw AppError.fromDio(e);
    }
  }

  /// Runs a token-issuing call and parses `{ access_token, refresh_token }`.
  Future<TrainerAuthTokens> _tokenCall(
    Future<Response<Map<String, Object?>>> Function() call, {
    required AuthFailure on401,
    AuthFailure? on403,
  }) async {
    try {
      final res = await call();
      final data = res.data;
      if (data == null) throw const AuthException(AuthFailure.emptyResponse);
      return TrainerAuthTokens.fromJson(data);
    } on DioException catch (e) {
      final int? code = e.response?.statusCode;
      // 소셜 로그인만 내는 응답이다(#1551) — 다른 요청에는 오지 않는다.
      if (_isSocialEmailInUse(code, e.response?.data)) {
        throw const AuthException(AuthFailure.socialEmailInUse);
      }
      if (code == 401) throw AuthException(on401);
      if (code == 403 && on403 != null) throw AuthException(on403);
      throw _asAuth(e);
    } on FormatException catch (e) {
      throw AuthException(AuthFailure.emptyResponse, detail: e.message);
    }
  }

  /// 409 `detail: {code: social_email_in_use}` 인가(#1551).
  static bool _isSocialEmailInUse(int? status, Object? body) {
    final Object? detail = body is Map ? body['detail'] : null;
    final Object? code = detail is Map ? detail['code'] : null;
    return status == 409 && code == 'social_email_in_use';
  }

  /// Converts a transport failure into a user-facing [AuthException].
  AuthException _asAuth(DioException e) {
    final err = AppError.fromDio(e);
    if (err is NetworkError) {
      return const AuthException(AuthFailure.network);
    }
    return const AuthException(AuthFailure.unknown);
  }
}

/// Selects the trainer auth repository from [AppConfig]: the real
/// Dio-backed implementation against the FastAPI backend, or the
/// in-memory [MockTrainerAuthRepository] for demo / `USE_MOCK_API=true`.
final trainerAuthRepositoryProvider = Provider<TrainerAuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    return MockTrainerAuthRepository(language: ref.watch(demoLanguageProvider));
  }
  return DioTrainerAuthRepository(ref.watch(dioProvider));
}, name: 'trainerAuthRepository');
