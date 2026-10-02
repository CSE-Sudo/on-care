import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/data/repositories/dio_password_repository.dart';
import 'package:oncare/features/auth/data/repositories/mock_password_repository.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart';

/// 지금 빌드의 비밀번호 변경·재설정 리포지토리(#2824).
///
/// - 실 서버 빌드 → [DioPasswordRepository].
/// - 데모 빌드 → [MockPasswordRepository]. 다만 인증만 실 서버로 보내는 데모
///   (`REAL_API=auth`)는 로그인한 계정이 진짜이므로 **재설정도 실 서버로** 보낸다.
///   변경(`/users/me/password`)은 기기 안 목업이 받는 경로라 데모 그대로 둔다.
final passwordRepositoryProvider = Provider<PasswordRepository>((ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  if (!config.useMockApi) {
    return DioPasswordRepository(ref.watch(dioProvider));
  }
  const MockPasswordRepository demo = MockPasswordRepository();
  if (config.isRealApi('POST', '/auth/password-reset/request')) {
    return RealResetDemoChangeRepository(
      reset: DioPasswordRepository(ref.watch(dioProvider)),
      change: demo,
    );
  }
  return demo;
}, name: 'passwordRepository');

/// 재설정은 실 서버, 변경은 데모로 나누어 보내는 리포지토리.
class RealResetDemoChangeRepository implements PasswordRepository {
  const RealResetDemoChangeRepository({
    required this.reset,
    required this.change,
  });

  final PasswordRepository reset;
  final PasswordRepository change;

  @override
  bool get supportsPasswordChange => change.supportsPasswordChange;

  @override
  Future<ReissuedTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => change.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  @override
  Future<PasswordResetRequested> requestReset({required String email}) =>
      reset.requestReset(email: email);

  @override
  Future<void> confirmReset({
    required String code,
    required String newPassword,
  }) => reset.confirmReset(code: code, newPassword: newPassword);
}
