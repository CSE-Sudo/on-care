// 회원 앱 부팅 스크립트 템플릿(#3204).
//
// 이 파일이 있으면 `flutter build web` 이 기본 템플릿 대신 이것으로 산출물
// `flutter_bootstrap.js` 를 만든다. 기본 템플릿과 다른 점은 하나다 — 서비스 워커를
// 등록하지 않는다(`serviceWorkerSettings` 를 넘기지 않는다). 등록된 워커가
// `main.dart.js` 를 캐시에서 내주면 새 배포 뒤 새로고침해도 옛 번들이 떠, 새 버전
// 안내가 되풀이된다. 예전 빌드가 설치한 워커는 `js/sw_cleanup.js` 가 지운다.
//
// `--pwa-strategy=none` 은 쓰지 않는다. 숨김·폐기 예정 플래그이고, 빌드가 내는 자기
// 해제형 `flutter_service_worker.js` 를 빈 파일로 바꿔 남은 워커가 스스로 사라지지
// 않는다.
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load();
