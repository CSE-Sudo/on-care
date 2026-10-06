// 예전 빌드가 설치한 Flutter 서비스 워커를 지운다(#3204).
//
// 두 웹(회원 앱·트레이너 웹)이 같은 파일을 쓴다 — 사본이 어긋나면 두 앱의
// `test/web/service_worker_test.dart` 가 실패한다. CSP 가 인라인 <script> 를 막으므로
// (script-src 에 'unsafe-inline' 없음) 같은 출처 파일로 둔다.
//
// 지금 빌드는 `web/flutter_bootstrap.js` 템플릿이 서비스 워커를 등록하지 않는다. 그래도
// 예전 빌드를 연 적 있는 브라우저에는 워커가 남아 `main.dart.js` 를 자기 캐시에서
// 내주고, 그러면 새로고침해도 옛 번들이 떠 새 버전 안내가 되풀이된다. 그래서
//
// * 이 앱 폴더(`<base href>`) 아래 등록만 모두 해제한다. 다른 경로(소개 페이지 등)의
//   등록은 건드리지 않는다.
// * 지금 페이지가 워커의 통제를 받고 있었다면 이번 번들이 워커 캐시에서 왔을 수 있으므로
//   탭당 한 번만 다시 읽는다. 해제된 등록은 다음 탐색을 가로채지 않는다. 같은 탭에서
//   두 번 다시 읽지 않도록 sessionStorage 에 표시를 남긴다(저장소를 못 쓰면 다시 읽지 않는다).
// * 브라우저가 서비스 워커를 지원하지 않거나 조회가 실패하면 조용히 넘긴다 — 앱은 그대로 뜬다.
(function () {
  "use strict";

  var RELOAD_KEY = "oncare.swCleanupReloaded";

  if (!("serviceWorker" in navigator)) return;
  var container = navigator.serviceWorker;
  if (typeof container.getRegistrations !== "function") return;

  // 이 앱 폴더(`/frontend/`·`/trainer/`). Flutter 는 이 폴더를 범위로 워커를 등록했다.
  var appScope = new URL(".", document.baseURI).href;
  var controlled = Boolean(container.controller);

  function isMine(registration) {
    return String(registration.scope || "").indexOf(appScope) === 0;
  }

  function reloadOnce() {
    try {
      if (window.sessionStorage.getItem(RELOAD_KEY) === "1") return;
      window.sessionStorage.setItem(RELOAD_KEY, "1");
    } catch (error) {
      return;
    }
    window.location.reload();
  }

  container
    .getRegistrations()
    .then(function (registrations) {
      var mine = registrations.filter(isMine);
      return Promise.all(
        mine.map(function (registration) {
          return registration.unregister();
        })
      );
    })
    .then(function (results) {
      var removed = results.some(Boolean);
      if (removed && controlled) reloadOnce();
    })
    .catch(function (error) {
      console.warn("서비스 워커를 정리하지 못했습니다", error);
    });
})();
