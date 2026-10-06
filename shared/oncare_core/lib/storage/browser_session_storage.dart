import 'package:oncare_core/storage/browser_session_storage_stub.dart'
    if (dart.library.js_interop) 'package:oncare_core/storage/browser_session_storage_web.dart'
    as platform;
import 'package:oncare_core/storage/token_keys.dart';
import 'package:oncare_core/storage/token_session_storage.dart';

/// [space] 앱이 쓸 브라우저 탭 단위 토큰 저장소. 웹이 아니면 `null` — 그때는
/// 영구 보안 저장소(Keychain/Keystore)를 그대로 쓴다(#2828).
///
/// 웹이면 복제한 탭인지 먼저 본다(#3248, #3271) — 복제한 탭은 복사해 받은 이
/// 앱의 토큰을 버리고, 원래 탭의 옛 키도 보지 않는다([BrowserTabClaim]).
/// 판정은 페이지마다 한 번이다.
TokenSessionStorage? createBrowserTokenSessionStorage(TokenKeyspace space) =>
    platform.createBrowserSessionStorage(space);
