import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppInputError, AppInputRules;

/// 서버가 **새 비밀번호**를 기준 미달로 거절했다(#1555).
///
/// 다른 [ValidationError](현재 비밀번호 불일치 등)는 현재 비밀번호 칸의
/// 문제지만, 이것은 새 비밀번호 칸의 문제다. 서버 문장 대신 [reason] 을 들고
/// 나가 화면이 자기 로케일의 문구를 새 비밀번호 칸 아래에 붙인다.
class NewPasswordRejected extends ValidationError {
  /// [reason] 은 공용 입력 규칙의 오류 종류다.
  const NewPasswordRejected(this.reason);

  /// 무엇이 기준에 맞지 않았는가.
  final AppInputError reason;
}

/// 되돌릴 수 없는 계정 동작 앞의 본인 확인(#3039).
///
/// 토큰만 있으면 탈퇴되던 때가 있었다 — 공용 PC 에 남은 세션이나 새어 나간
/// 토큰으로 계정을 지울 수 있었다. 비밀번호 계정은 현재 비밀번호를, 소셜로만
/// 가입한 계정은 방금 다시 로그인해 받은 소셜 토큰을 함께 보낸다.
sealed class TrainerReauth {
  const TrainerReauth();

  /// 서버 본문에 더할 칸.
  Map<String, Object?> toJson();
}

/// 비밀번호 계정의 본인 확인 — 현재 비밀번호.
final class PasswordReauth extends TrainerReauth {
  const PasswordReauth(this.currentPassword);

  final String currentPassword;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'current_password': currentPassword,
  };
}

/// 소셜로만 가입한 계정의 본인 확인 — 다시 로그인해 받은 제공자 토큰.
final class SocialReauth extends TrainerReauth {
  const SocialReauth({required this.provider, required this.token});

  /// `kakao` · `google`.
  final String provider;
  final String token;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'social_provider': provider,
    'social_token': token,
  };
}

/// 본인 확인이 거절된 이유(#3039). 모두 400 이다 — 토큰은 아직 유효하므로
/// 로그아웃하지 않고, 확인창 안에 알린다.
enum ReauthFailure {
  /// 확인 값을 싣지 않았다(`reauth_required`).
  required,

  /// 현재 비밀번호가 틀렸다(`invalid_current_password`).
  invalidPassword,

  /// 소셜 계정 확인에 실패했다(`invalid_reauth`).
  invalidSocial;

  /// 서버 `detail.code` → 이유. 모르는 코드면 null.
  static ReauthFailure? fromCode(String? code) => switch (code) {
    'reauth_required' => required,
    'invalid_current_password' => invalidPassword,
    'invalid_reauth' => invalidSocial,
    _ => null,
  };
}

/// 서버가 본인 확인을 거절했다(#3039). 다른 [ValidationError] 처럼 입력의
/// 문제라 다시 시도하면 되고, 문구는 화면이 [reason] 으로 고른다.
class ReauthRejected extends ValidationError {
  const ReauthRejected(this.reason);

  final ReauthFailure reason;
}

/// Account-level actions that change credentials.
///
/// Separate from the profile repository because the failure modes are
/// different: a wrong current password is a user error to show inline,
/// not a network error to retry.
abstract interface class TrainerAccountRepository {
  /// Whether this build can actually change the password.
  ///
  /// Demo/mock has no account behind it, so the UI disables the action
  /// and says why instead of pretending it worked.
  bool get supportsPasswordChange;

  /// Changes the password. Throws [AppError] on failure —
  /// [ValidationError] carries the server's reason (wrong current
  /// password, same as current) for inline display.
  ///
  /// 성공하면 서버가 새로 발급한 토큰 한 쌍을 돌려준다(#2766). 서버는 비밀번호를
  /// 바꾸면 그 전에 발급한 토큰을 모두 무효로 만들므로, 호출부가 이 토큰으로
  /// 세션을 갈아 끼워야 이 기기가 로그아웃되지 않는다. 응답에 토큰이 없으면
  /// (토큰 세대 이전 서버) null 이다.
  Future<TrainerAuthTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// 이 빌드에서 계정을 지울 수 있는가. 데모에는 지울 서버 계정이 없다.
  bool get supportsDeletion;

  /// 계정 탈퇴(`DELETE /trainer/me`). 담당 회원 링크·예약이 함께 정리되고
  /// 회원에게는 알림이 간다. 실패는 [AppError]. (#505)
  ///
  /// [reasons] 는 탈퇴 화면에서 고른 사유 코드다(#2264). 서버는 모르는 값을
  /// 버리고, 계정과 잇지 않고 남긴다. 비어 있어도 된다.
  ///
  /// [reauth] 는 본인 확인이다(#3039). 거절되면 [ReauthRejected].
  Future<void> deleteAccount({
    required TrainerReauth reauth,
    List<String> reasons = const <String>[],
  });
}

/// Demo build: no server account to change.
class MockTrainerAccountRepository implements TrainerAccountRepository {
  /// Creates the demo no-op.
  const MockTrainerAccountRepository();

  @override
  bool get supportsPasswordChange => false;

  @override
  bool get supportsDeletion => false;

  @override
  Future<TrainerAuthTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    // 문구는 화면이 붙인다 — 리포지토리에는 컨텍스트가 없어 로케일을 알 수
    // 없고, message 가 비면 호출부가 자기 로케일의 기본 문구로 채운다. (#501)
    throw const ValidationError();
  }

  @override
  Future<void> deleteAccount({
    required TrainerReauth reauth,
    List<String> reasons = const <String>[],
  }) async {
    // 본인 확인은 서버와 같은 규칙으로 먼저 본다(#3039). 데모 로그인은 비어 있지
    // 않은 비밀번호를 모두 받으므로 여기서도 그렇다. 소셜은 데모 로그인이 쓰는
    // 토큰(`demo-<provider>-token`)만 통과한다.
    switch (reauth) {
      case PasswordReauth(:final String currentPassword):
        if (currentPassword.isEmpty) {
          throw const ReauthRejected(ReauthFailure.required);
        }
      case SocialReauth(:final String provider, :final String token):
        if (provider.isEmpty || token.isEmpty) {
          throw const ReauthRejected(ReauthFailure.required);
        }
        if (token != 'demo-$provider-token') {
          throw const ReauthRejected(ReauthFailure.invalidSocial);
        }
    }
    // 확인을 통과해도 데모에는 지울 서버 계정이 없다.
    throw const ValidationError(message: '데모 모드에는 지울 계정이 없어요');
  }
}

/// Real backend: `POST /v1/trainer/me/password`.
class DioTrainerAccountRepository implements TrainerAccountRepository {
  /// Creates the API-backed repository.
  const DioTrainerAccountRepository(this._dio);

  final Dio _dio;

  @override
  bool get supportsPasswordChange => true;

  @override
  bool get supportsDeletion => true;

  @override
  Future<void> deleteAccount({
    required TrainerReauth reauth,
    List<String> reasons = const <String>[],
  }) async {
    try {
      await _dio.delete<Map<String, dynamic>>(
        '/trainer/me',
        // 회원 탈퇴와 같은 본문이다 — 고른 사유가 없으면 빈 목록. 본인 확인
        // 칸(#3039)이 함께 간다.
        data: <String, Object?>{'reasons': reasons, ...reauth.toJson()},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        final ReauthFailure? reason = ReauthFailure.fromCode(
          serverDetailCode(e.response?.data),
        );
        if (reason != null) throw ReauthRejected(reason);
      }
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<TrainerAuthTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        '/trainer/me/password',
        data: <String, String>{
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      // 400 carries the server's own reason ("현재 비밀번호가 일치하지
      // 않습니다."), which is exactly what the trainer needs to read.
      final status = e.response?.statusCode;
      if (status == 422) {
        final AppInputError? reason = AppInputRules.serverPasswordError(
          e.response?.data,
        );
        if (reason != null) throw NewPasswordRejected(reason);
      }
      if (status == 400 || status == 422) {
        // 서버가 준 사유가 있으면 그대로, 없으면 화면이 기본 문구를 붙인다.
        throw ValidationError(message: _detail(e));
      }
      throw AppError.fromDio(e);
    }
    return reissuedTokensFrom(res.data);
  }

  String? _detail(DioException e) {
    final data = e.response?.data;
    if (data is! Map) return null;
    final detail = data['detail'];
    return detail is String ? detail : null;
  }
}

/// 비밀번호 변경 응답에서 새 토큰 한 쌍을 꺼낸다(#2766).
///
/// 변경은 이미 서버에 반영됐다 — 응답 모양이 어긋났다고 던지면 화면이 "실패"로
/// 보여 주는데 비밀번호는 바뀐 상태가 된다. 그래서 토큰이 없거나 형식이 틀리면
/// null 로 돌려주고, 세션은 다음 401 에서 만료 안내와 함께 다시 로그인하게 된다.
TrainerAuthTokens? reissuedTokensFrom(Map<String, dynamic>? body) {
  if (body == null) return null;
  final Object? access = body['access_token'];
  if (access is! String || access.isEmpty) return null;
  final Object? refresh = body['refresh_token'];
  return TrainerAuthTokens(
    access: access,
    refresh: refresh is String ? refresh : '',
  );
}

/// Provides the account repository for the current mode.
final trainerAccountRepositoryProvider = Provider<TrainerAccountRepository>((
  ref,
) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return const MockTrainerAccountRepository();
  }
  return DioTrainerAccountRepository(ref.watch(dioProvider));
}, name: 'trainerAccountRepository');
