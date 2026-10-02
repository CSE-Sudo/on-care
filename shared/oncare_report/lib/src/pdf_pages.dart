/// PDF 를 쪽 그림으로 굽고, 인쇄 창에 넘기는 플랫폼별 구현.
///
/// 웹은 `index.html` 이 같은 출처에서 올려 둔 pdf.js 를 **직접** 부른다.
/// `printing` 플러그인의 웹 구현은 pdf.js 가 있는지를 `window.eval` 로 묻는데,
/// 두 웹 셸의 CSP 는 `'unsafe-eval'` 을 열지 않아(#2828) 그 물음에서 죽는다 —
/// 미리보기가 스피너만 돌거나 `미리보기를 만들지 못했어요` 로 끝났다. 정책을
/// 넓히는 대신 그 길을 타지 않는다. 네이티브는 지금처럼 `printing` 이 한다.
library;

export 'pdf_pages_io.dart' if (dart.library.js_interop) 'pdf_pages_web.dart';
