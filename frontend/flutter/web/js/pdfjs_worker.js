// pdf.js 워커 주소 지정(index.html 에서 옮김, #2828).
//
// CSP 가 인라인 <script> 를 막으므로 같은 출처의 파일로 둔다. pdfjs/pdf.min.js
// 바로 뒤에 올려야 `printing` 이 자기 로더(unpkg.com)를 건너뛴다.
if (window.pdfjsLib) {
  // 워커 주소는 절대 경로로 준다 — base href 가 `/frontend/` 라 상대 경로는
  // 어디서 푸느냐에 따라 달라진다.
  window.pdfjsLib.GlobalWorkerOptions.workerSrc = new URL(
    "pdfjs/pdf.worker.min.js",
    document.baseURI,
  ).href;
}
