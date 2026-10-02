// 한글·이모지 글꼴 보정(index.html 에서 옮김, #2828).
//
// CSP 가 인라인 <script> 를 막으므로(script-src 에 'unsafe-inline' 없음) 같은 출처의
// 파일로 둔다. 내용은 그대로다.
//
// Flutter's HTML web renderer draws text inside the <flt-glass-pane> shadow
// DOM and does not re-pick-up the inherited font until a style recalc; dev
// (DDC) loads also render well after any fixed timeout. A MutationObserver
// re-asserts the font whenever the shadow DOM changes, so it works at any
// load speed and after scroll/navigation. Native/CanvasKit are unaffected.
(function () {
  var STACK =
    "'Apple SD Gothic Neo','AppleGothic','Malgun Gothic','Noto Sans KR','Apple Color Emoji','Segoe UI Emoji','Noto Color Emoji',sans-serif";
  var el, pending = false;
  function reapply() {
    pending = false;
    if (el) el.remove();
    el = document.createElement('style');
    el.textContent =
      'flt-glass-pane, flutter-view, body { font-family: ' + STACK + ' !important; }';
    document.head.appendChild(el);
  }
  function schedule() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(reapply);
  }
  (function watch() {
    var gp = document.querySelector('flt-glass-pane');
    if (gp && gp.shadowRoot) {
      new MutationObserver(schedule).observe(gp.shadowRoot, {
        childList: true,
        subtree: true,
        characterData: true,
      });
      reapply();
    } else {
      setTimeout(watch, 150);
    }
  })();
})();
