"""API 응답 보안 헤더(#2828).

API 는 JSON 과 업로드 파일(사진·PDF)만 내려준다. 브라우저가 이 응답을 문서로 열거나
다른 사이트가 틀 안에 넣어도 스크립트가 돌거나 화면이 덮어씌워지지 않게 한다.

- ``X-Content-Type-Options: nosniff`` — 업로드 파일을 다른 형식으로 짐작해 실행하지 않게.
- ``X-Frame-Options: DENY`` + CSP ``frame-ancestors 'none'`` — 틀 안 삽입 금지(옛 브라우저와
  새 브라우저 모두).
- ``Content-Security-Policy: default-src 'none'`` — 응답이 문서로 열려도 아무것도 불러오거나
  실행하지 않는다. 업로드된 SVG·HTML 이 같은 출처에서 열려도 스크립트가 돌지 못한다.
- ``Referrer-Policy: no-referrer`` — API 주소(쿼리 포함)가 다른 곳으로 새지 않게.
- ``Strict-Transport-Security`` — 운영/HTTPS 에서만.

FastAPI 문서 화면(`/docs`·`/redoc`)은 CDN 스크립트와 인라인 스크립트로 그려지므로 CSP
대상에서 뺀다(나머지 헤더는 그대로). 정적 웹(회원 앱·트레이너 웹)의 헤더는 이 서버가 아니라
정적 호스팅(CloudFront 응답 헤더 정책)이 붙인다.
"""
from __future__ import annotations

#: API 응답의 Content-Security-Policy. 문서로 열려도 아무것도 허용하지 않는다.
API_CONTENT_SECURITY_POLICY = (
    "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
)

#: HSTS 값(2년, 하위 도메인 포함).
HSTS_VALUE = "max-age=63072000; includeSubDomains"

#: CSP 를 붙이지 않는 경로 접두사 — FastAPI 문서 화면.
_DOCS_PREFIXES: tuple[str, ...] = ("/docs", "/redoc")


def _is_docs_path(path: str) -> bool:
    return any(path == p or path.startswith(p + "/") for p in _DOCS_PREFIXES)


def security_headers_for(path: str, *, hsts: bool) -> dict[str, str]:
    """이 경로의 응답에 붙일 보안 헤더."""
    headers = {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
    }
    if not _is_docs_path(path):
        headers["Content-Security-Policy"] = API_CONTENT_SECURITY_POLICY
    if hsts:
        headers["Strict-Transport-Security"] = HSTS_VALUE
    return headers
