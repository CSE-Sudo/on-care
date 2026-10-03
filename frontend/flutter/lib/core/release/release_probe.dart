/// 새 버전 확인의 브라우저 기능(#3023).
///
/// 웹은 `version.txt` 읽기·`visibilitychange`·새로고침을 브라우저에 맡기고, 웹이
/// 아닌 곳(테스트 등)은 스텁이 `null` 을 돌려 확인 자체가 꺼진다.
library;

export 'release_probe_stub.dart'
    if (dart.library.js_interop) 'release_probe_web.dart';
