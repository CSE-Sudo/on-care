// 카카오 웹 로그인 콜백(#330) — kakao_login_callback.html 이 부른다.
//
// 카카오 로그인 팝업이 `?code=…&state=…`(거부하면 `?error=…`)를 붙여 돌아오면, 그 값을
// 같은 출처의 앱 창에 `BroadcastChannel('oncare-kakao-login')` 으로 넘기고 이 창을 닫는다.
// 앱(oncare_social_login 의 KakaoWebLogin)은 자기가 만든 state 와 같은 메시지만 받아
// 인가 코드를 서버(`POST /auth/social/kakao/code`)에서 카카오 토큰으로 바꾼다.
//
// * window.opener 대신 BroadcastChannel 을 쓴다 — 카카오 페이지를 거치며 opener 가
//   끊겨도(Cross-Origin-Opener-Policy) 같은 출처 창끼리는 메시지가 닿는다.
// * 코드는 주소창·방문 기록에 남지 않게 먼저 지운다. 코드는 한 번만 쓰이고 짧게 만료된다.
// * 창이 닫히지 않으면(주소를 직접 연 경우) 안내 문구만 바꾼다. 문구는 textContent 로 넣는다.
(function () {
  "use strict";

  var CHANNEL = "oncare-kakao-login";
  var params = new URLSearchParams(window.location.search);
  var message = JSON.stringify({
    type: CHANNEL,
    code: params.get("code") || "",
    state: params.get("state") || "",
    error: params.get("error") || "",
  });

  try {
    window.history.replaceState(null, "", window.location.pathname);
  } catch (e) {
    // 주소를 못 지워도 코드 전달은 계속한다.
  }

  var sent = false;
  try {
    var channel = new BroadcastChannel(CHANNEL);
    channel.postMessage(message);
    channel.close();
    sent = true;
  } catch (e) {
    sent = false;
  }

  var korean = (navigator.language || "ko").toLowerCase().indexOf("ko") === 0;
  var status = document.getElementById("kakao-login-status");
  if (status) {
    if (sent) {
      status.textContent = korean
        ? "로그인을 마쳤어요. 이 창을 닫고 앱으로 돌아가 주세요."
        : "Signed in. Close this window and return to the app.";
    } else {
      status.textContent = korean
        ? "이 브라우저에서는 로그인을 마칠 수 없어요. 앱에서 다시 시도해 주세요."
        : "Sign-in can't finish in this browser. Please try again in the app.";
    }
  }
  window.close();
})();
