import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/features/auth/data/dtos/trainer_me_dto.dart';
import 'package:oncare_trainer/features/auth/data/repositories/mock_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

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
    required String inviteCode,
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
          'invite_code': inviteCode,
        },
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const AuthException(AuthFailure.emailTaken);
      }
      if (e.response?.statusCode == 422) {
        // 서버는 없는·만료된·이미 쓰인 코드를 구분하지 않는다. 어느 경우든
        // 트레이너가 할 일은 헬스장에 코드를 다시 받는 것이라 결론이 같다.
        throw const AuthException(AuthFailure.inviteCodeInvalid);
      }
      throw _asAuth(e);
    }
    // Registration returns the created user, not a token — sign in next.
    return login(email: email, password: password);
  }

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
        throw UnauthorizedError(message: e.message);
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
  }) async {
    try {
      final res = await call();
      final data = res.data;
      if (data == null) throw const AuthException(AuthFailure.emptyResponse);
      return TrainerAuthTokens.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) throw AuthException(on401);
      throw _asAuth(e);
    } on FormatException catch (e) {
      throw AuthException(AuthFailure.emptyResponse, detail: e.message);
    }
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
