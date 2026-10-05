// 트레이너 웹 부팅 중 로딩 표시와 부팅 실패 안내(#3152).
//
// index.html 의 `#boot-status`(로고·스피너)는 CSS 만으로 첫 바이트부터 보인다. 이
// 스크립트는 그 표시를 언제 거두고 언제 실패 안내로 바꿀지만 정한다. CSP 가 인라인
// <script> 를 막으므로(script-src 에 'unsafe-inline' 없음) 같은 출처 파일로 둔다.
//
// * Flutter 가 첫 프레임을 그리면(`flutter-first-frame`, window 로 온다) 표시를 지운다.
//   표시는 화면 전체를 덮는 고정 레이어라, 지우는 순간 그 아래 앱 화면이 드러난다.
// * BOOT_TIMEOUT_MS 안에 첫 프레임이 없거나, 부팅 스크립트(flutter_bootstrap.js·
//   main.dart.js·CanvasKit)를 받지 못하면 실패 안내와 새로고침 버튼으로 바꾼다.
//   안내를 띄운 뒤에라도 첫 프레임이 오면(아주 느린 회선) 그대로 지운다.
// * 문구는 한국어가 기본이고, 브라우저 언어가 한국어가 아니면 영어로 쓴다.
//
// pdfjs_loader.js 보다 먼저 실행돼야 부팅 스크립트의 로드 오류를 놓치지 않는다 —
// index.html 에서 이 파일을 먼저 부른다. 문구는 textContent 로만 넣는다.
(function () {
  "use strict";

  var BOOT_TIMEOUT_MS = 20000;

  var MESSAGES = {
    ko: {
      loading: "트레이너 웹을 불러오는 중입니다",
      failed: "트레이너 웹을 불러오지 못했습니다. 연결을 확인하고 새로고침해 주세요.",
      reload: "새로고침",
    },
    en: {
      loading: "Loading the trainer web",
      failed: "Couldn't load the trainer web. Check your connection and refresh the page.",
      reload: "Refresh",
    },
  };

  // 이 이름으로 끝나는 스크립트를 못 받으면 앱이 뜰 수 없다.
  var BOOT_SCRIPTS = ["flutter_bootstrap.js", "flutter.js", "main.dart.js", "canvaskit.js"];

  var root = document.getElementById("boot-status");
  if (!root) return;

  function pickLanguage() {
    var langs = navigator.languages && navigator.languages.length
      ? navigator.languages
      : [navigator.language || ""];
    return String(langs[0] || "").toLowerCase().indexOf("ko") === 0 ? "ko" : "en";
  }

  var lang = pickLanguage();
  var text = MESSAGES[lang];

  function setText(selector, value) {
    var node = root.querySelector(selector);
    if (node) node.textContent = value;
  }

  if (lang !== "ko") {
    setText(".boot-label", text.loading);
    setText(".boot-error-text", text.failed);
    setText(".boot-reload", text.reload);
  }

  var finished = false;
  var failed = false;
  var timer = window.setTimeout(fail, BOOT_TIMEOUT_MS);

  function done() {
    if (finished) return;
    finished = true;
    window.clearTimeout(timer);
    window.removeEventListener("error", onResourceError, true);
    if (root.parentNode) root.parentNode.removeChild(root);
  }

  function fail() {
    if (finished || failed) return;
    failed = true;
    window.clearTimeout(timer);
    root.classList.add("boot-failed");
    root.setAttribute("role", "alert");
    var panel = root.querySelector(".boot-error");
    if (panel) panel.hidden = false;
    var button = root.querySelector(".boot-reload");
    if (button) button.focus();
  }

  function isBootScript(src) {
    var path = String(src || "").split("?")[0];
    for (var i = 0; i < BOOT_SCRIPTS.length; i++) {
      var name = BOOT_SCRIPTS[i];
      if (path.slice(-name.length) === name) return true;
    }
    return false;
  }

  // 리소스 로드 오류는 버블링하지 않으므로 캡처 단계에서 받는다.
  function onResourceError(event) {
    var target = event && event.target;
    if (target && target.tagName === "SCRIPT" && isBootScript(target.src)) fail();
  }

  var reload = root.querySelector(".boot-reload");
  if (reload) {
    reload.addEventListener("click", function () {
      window.location.reload();
    });
  }

  window.addEventListener("flutter-first-frame", done, { once: true });
  window.addEventListener("error", onResourceError, true);
})();
