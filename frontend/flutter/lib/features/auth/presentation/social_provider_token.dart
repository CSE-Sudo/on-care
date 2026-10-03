import 'package:oncare/core/config/app_config.dart';

/// 카카오·구글로 로그인해 provider 토큰을 받는다.
///
/// 로그인 화면과 본인 확인 창(#3039)이 같은 길을 쓴다 — 소셜 전용 계정은 비밀번호
/// 대신 방금 다시 로그인해 받은 토큰으로 본인임을 보인다.
///
/// #330 실제 SDK 연동 전이라 기기 안 목업으로 가는 데모 설정에서만 고정 토큰을
/// 돌려준다. 그 밖의 설정에서는 null 이다 — 화면은 버튼을 꺼 둔다(#2769).
Future<String?> obtainSocialProviderToken(
  AppConfig config,
  String provider,
) async {
  if (!config.usesMockSocialLogin) return null;
  return 'demo-$provider-token';
}
