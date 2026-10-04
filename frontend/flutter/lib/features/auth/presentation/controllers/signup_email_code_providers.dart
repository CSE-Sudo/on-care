import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/data/repositories/dio_signup_email_code_repository.dart';
import 'package:oncare/features/auth/domain/signup_email_code.dart';

/// 가입 이메일 인증 코드 요청(#3038). 데모 빌드에서도 같은 저장소를 쓴다 —
/// 요청은 기기 안 목업 API 가 받는다(가입 요청과 같은 길).
final signupEmailCodeRepositoryProvider = Provider<SignupEmailCodeRepository>(
  (ref) => DioSignupEmailCodeRepository(ref.watch(dioProvider)),
  name: 'signupEmailCodeRepository',
);

/// 가입 화면이 데모 코드([SignupEmailCode.demoCode])를 안내할지(#3038).
///
/// 기기 안 목업이 가입을 받을 때만이다. 인증을 실 서버로 보내는 데모
/// (`REAL_API=auth`)는 진짜 메일이 가므로 안내하지 않는다.
final signupDemoCodeHintProvider = Provider<bool>((ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return config.useMockApi &&
      !config.isRealApi('POST', '/auth/register/email-code');
}, name: 'signupDemoCodeHint');
