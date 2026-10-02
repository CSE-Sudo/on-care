// 리포트·채팅 PDF 미리보기가 쓰는 pdf.js 를 올리고 Flutter 를 띄운다. (#2818)
//
// 두 웹(회원 앱·트레이너 웹)이 같은 파일을 쓴다 — 사본이 어긋나면 두 앱의
// `test/web/pdfjs_bundle_test.dart` 가 실패한다. 인라인 <script> 가 아니라 같은
// 출처 파일로 두는 것은 CSP(script-src 에 'unsafe-inline' 없음)와 맞추기 위해서다.
//
// `printing` 패키지는 웹에서 PDF 를 pdf.js 로 그리는데, 아무것도 안 두면 화면을
// 여는 순간 unpkg.com 에서 최신 빌드를 받아 온다. 데모가 남의 CDN 이 살아 있는지에
// 걸리고, 그 최신 빌드는 오래된 사파리에서 돌지 않는다. 게다가 pdf.js 를 못 올리면
// `printing` 은 오류를 내는 대신 잠금을 쥔 채 멈춰서, 미리보기가 영영 스피너만
// 돈다. 그래서 레거시 빌드(오래된 사파리용 폴리필 포함)를 저장소에 싣고
// `pdfjsLib` 를 미리 올려 둔다. 이러면 `printing` 은 자기 로더를 건너뛴다.
//
// 보안:
// * 버전은 CVE-2024-4367(조작된 글꼴로 임의 스크립트 실행) 수정판 4.2.67 이상이다.
//   갱신은 `frontend/tool/update_pdfjs.sh <버전>` 하나로 두 앱 사본·이 상수·
//   `pdfjs/bundle.txt` 를 함께 바꾼다.
// * `getDocument` 는 항상 `isEvalSupported: false` 로 부른다 — 글꼴 경로가
//   `eval`/`new Function` 을 쓰지 않게 해, 다음 취약점에도 한 겹 더 막는다.
//   `printing` 은 `getDocument` 에 데이터만 넘기므로 여기서 감싼다.
//
// 4.x 는 ES 모듈만 내므로 `import()` 로 올린다. 파일 확장자는 `.js` 로 둔다 —
// 정적 호스팅이 `.mjs` 를 자바스크립트 MIME 으로 내보내지 않으면 모듈 로드가
// 막힌다. `printing` 이 자기 로더(CDN)로 빠지지 않게 pdf.js 를 올린 **뒤에**
// Flutter 를 띄운다. pdf.js 를 올리지 못해도 앱은 뜬다.

const PDFJS_VERSION = "4.10.38";

// 문자열·URL·바이트·옵션 객체 어느 형태로 와도 `isEvalSupported: false` 를 건다.
function hardenedSource(src) {
  if (typeof src === "string" || src instanceof URL) {
    return { url: src, isEvalSupported: false };
  }
  if (ArrayBuffer.isView(src) || src instanceof ArrayBuffer) {
    return { data: src, isEvalSupported: false };
  }
  return Object.assign({}, src, { isEvalSupported: false });
}

try {
  // 절대 경로로 준다 — base href(`/frontend/`·`/trainer/`)에 따라 상대 경로의
  // 뜻이 달라진다. `?v=` 는 버전을 바꿀 때 옛 캐시를 피한다.
  const dir = new URL("pdfjs/", document.baseURI).href;
  const lib = await import(`${dir}pdf.min.js?v=${PDFJS_VERSION}`);
  lib.GlobalWorkerOptions.workerSrc =
    `${dir}pdf.worker.min.js?v=${PDFJS_VERSION}`;
  const hardened = Object.assign({}, lib);
  hardened.getDocument = (src) => lib.getDocument(hardenedSource(src));
  window.pdfjsLib = Object.freeze(hardened);
} catch (error) {
  console.error("pdf.js 를 올리지 못했습니다", error);
} finally {
  const boot = document.createElement("script");
  boot.src = "flutter_bootstrap.js";
  boot.async = true;
  document.body.appendChild(boot);
}
