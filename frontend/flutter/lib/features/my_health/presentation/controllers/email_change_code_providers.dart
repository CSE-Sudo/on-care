import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';

/// 이메일 변경 확인 코드 창이 데모 코드를 안내할지(#3230).
///
/// 가입 화면의 `signupDemoCodeHintProvider` 와 같은 규칙이다 — 기기 안 목업이
/// 이메일 변경 코드를 받을 때만 안내하고, 실 서버로 보내는 데모(`REAL_API`)는
/// 진짜 메일이 가므로 안내하지 않는다. 화면이 `useMockApi` 로 갈라지지 않도록
/// 판단을 여기 둔다(#2791).
final emailChangeDemoCodeHintProvider = Provider<bool>((ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return config.useMockApi && !config.isRealApi('POST', '/users/me/email/code');
}, name: 'emailChangeDemoCodeHint');
