import 'package:oncare_core/storage/browser_session_storage.dart';
import 'package:oncare_core/storage/token_keys.dart';
import 'package:oncare_core/storage/token_session_storage.dart';

// 탭(세션) 단위로만 사는 토큰 저장소(#2828). 인터페이스와 메모리 구현은 두 앱이
// 함께 쓰는 `oncare_core` 에 있다(#3271) — 이 파일을 가져다 쓰던 곳은 그대로다.
export 'package:oncare_core/storage/token_session_storage.dart';

/// 지금 플랫폼의 탭 단위 저장소. 웹이 아니면 `null` — 그때는 영구 보안 저장소
/// (Keychain/Keystore)를 그대로 쓴다. 웹은 복제한 탭이면 복사해 받은 이 앱의
/// 토큰을 버린다(#3248, #3271) — 판정은 두 앱이 함께 쓰는 `oncare_core` 에 있다.
TokenSessionStorage? createPlatformTokenSessionStorage() =>
    createBrowserTokenSessionStorage(TokenKeyspace.trainer);
