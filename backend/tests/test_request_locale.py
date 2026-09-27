"""요청 로케일(#2297) — `Accept-Language` 파싱, 의존성, 미들웨어·컨텍스트 격리.

마지막 테스트(`client` 픽스처) 말고는 DB 가 필요 없다. 미들웨어는 작은 앱에 따로
조립해 검증하고, 실제 앱에는 미들웨어가 걸려 있는지와 헤더를 실은 요청이 통과하는지만
확인한다.
"""
from __future__ import annotations

import asyncio
import threading

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core import observability
from app.core.locale import (
    DEFAULT_LOCALE,
    SUPPORTED_LOCALES,
    RequestLocale,
    RequestLocaleMiddleware,
    current_locale,
    localized,
    parse_accept_language,
)


# ---------------------------------------------------------------------------
# 헤더 파싱
# ---------------------------------------------------------------------------


def test_default_is_korean():
    assert DEFAULT_LOCALE == "ko"
    assert set(SUPPORTED_LOCALES) == {"ko", "en"}


@pytest.mark.parametrize("header", [None, "", "   ", ",", ";", ",,,", ";q=1"])
def test_missing_or_empty_header_falls_back_to_korean(header):
    assert parse_accept_language(header) == "ko"


@pytest.mark.parametrize(
    ("header", "expected"),
    [
        # 앱이 실제로 보내는 값
        ("ko", "ko"),
        ("en", "en"),
        # 지역 태그는 주 언어만 본다
        ("en-US", "en"),
        ("en-GB", "en"),
        ("ko-KR", "ko"),
        ("en_US", "en"),
        # 대소문자·공백
        ("EN", "en"),
        ("En-Us", "en"),
        ("  en  ", "en"),
        ("KO-kr", "ko"),
    ],
)
def test_single_tag(header, expected):
    assert parse_accept_language(header) == expected


@pytest.mark.parametrize(
    ("header", "expected"),
    [
        # 가중치가 가장 큰 지원 언어
        ("ko;q=0.5, en;q=0.9", "en"),
        ("en;q=0.5, ko;q=0.9", "ko"),
        ("en;q=0.1, ko", "ko"),  # q 생략 = 1
        ("ko;q=0.1, en", "en"),
        # 동점이면 먼저 적힌 것
        ("en, ko", "en"),
        ("ko, en", "ko"),
        ("en;q=0.8, ko;q=0.8", "en"),
        ("ko;q=0.8, en;q=0.8", "ko"),
        # 브라우저가 흔히 보내는 모양
        ("en-US,en;q=0.9,ko;q=0.8", "en"),
        ("ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7", "ko"),
        # 지원하지 않는 언어가 가장 앞이면 다음 지원 언어
        ("ja, en;q=0.5", "en"),
        ("fr-FR, de;q=0.9, ko;q=0.1", "ko"),
        ("zh-CN,zh;q=0.9,en;q=0.8", "en"),
        # 가중치 표기 변형
        ("ko;q=0.3, en;Q=0.4", "en"),
        ("ko; q=0.3, en ; q = 0.4", "en"),
        ("en;q=1.000, ko;q=0.999", "en"),
        # q 외의 매개변수는 무시
        ("en;level=1;q=0.9, ko;q=0.5", "en"),
    ],
)
def test_weighted_lists(header, expected):
    assert parse_accept_language(header) == expected


@pytest.mark.parametrize(
    ("header", "expected"),
    [
        # 지원 언어가 없으면 기본값
        ("ja", "ko"),
        ("fr-FR, de;q=0.9", "ko"),
        ("*", "ko"),
        ("*, en;q=0.1", "en"),
        # q=0 은 "받지 않음"
        ("en;q=0", "ko"),
        ("en;q=0.0, ko;q=0", "ko"),
        ("en;q=0, ja", "ko"),
        ("ko;q=0, en;q=0.1", "en"),
        # 깨진 가중치는 그 항목만 버린다
        ("en;q=abc", "ko"),
        ("en;q=", "ko"),
        ("en;q", "ko"),
        ("en;q=1.5", "ko"),
        ("en;q=-0.5", "ko"),
        ("en;q=nan", "ko"),
        ("en;q=inf", "ko"),
        ("en;q=abc, ko;q=0.2", "ko"),
        ("ko;q=abc, en;q=0.2", "en"),
        # 주 언어가 비슷하지만 다른 것
        ("eng", "ko"),
        ("english", "ko"),
        ("kor", "ko"),
        ("enx, ko;q=0.1", "ko"),
    ],
)
def test_fallback_and_malformed(header, expected):
    assert parse_accept_language(header) == expected


def test_overlong_header_only_first_part_is_read():
    # 지원 언어가 한참 뒤에만 있는 비정상 헤더 — 앞부분만 보고 기본값으로 끝낸다.
    header = ",".join(["xx"] * 5000) + ",en"
    assert parse_accept_language(header) == "ko"


def test_entry_count_is_capped():
    header = ",".join(["ja"] * 40) + ",en"
    assert len(header) < 1024
    assert parse_accept_language(header) == "ko"


def test_supported_language_within_cap_is_still_found():
    header = ",".join(["ja"] * 10) + ",en;q=0.3"
    assert parse_accept_language(header) == "en"


# ---------------------------------------------------------------------------
# localized / current_locale
# ---------------------------------------------------------------------------


def test_current_locale_outside_request_is_default():
    assert current_locale() == "ko"


def test_localized_explicit_locale():
    assert localized("안녕", "hello", "ko") == "안녕"
    assert localized("안녕", "hello", "en") == "hello"


def test_localized_uses_current_locale_outside_request():
    assert localized("안녕", "hello") == "안녕"


# ---------------------------------------------------------------------------
# 미들웨어 + 의존성
# ---------------------------------------------------------------------------


def _app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(RequestLocaleMiddleware)

    @app.get("/ctx")
    async def ctx_async():
        return {"locale": current_locale()}

    @app.get("/ctx-sync")
    def ctx_sync():
        # 동기 엔드포인트는 스레드풀에서 돈다 — 컨텍스트가 따라와야 한다.
        return {"locale": current_locale(), "thread": threading.current_thread().name}

    @app.get("/dep")
    def dep(locale: RequestLocale):
        return {"locale": locale, "ctx": current_locale()}

    @app.get("/text")
    def text():
        return {"message": localized("저장했습니다.", "Saved.")}

    return app


@pytest.fixture
def locale_client() -> TestClient:
    return TestClient(_app())


@pytest.mark.parametrize("path", ["/ctx", "/ctx-sync", "/dep"])
@pytest.mark.parametrize(
    ("header", "expected"),
    [(None, "ko"), ("ko", "ko"), ("en", "en"), ("en-US,ko;q=0.5", "en"), ("ja", "ko")],
)
def test_middleware_sets_locale(locale_client, path, header, expected):
    headers = {} if header is None else {"Accept-Language": header}
    body = locale_client.get(path, headers=headers).json()
    assert body["locale"] == expected
    if "ctx" in body:
        assert body["ctx"] == expected


def test_localized_text_follows_header(locale_client):
    assert locale_client.get("/text").json()["message"] == "저장했습니다."
    assert (
        locale_client.get("/text", headers={"Accept-Language": "ko"}).json()["message"]
        == "저장했습니다."
    )
    assert (
        locale_client.get("/text", headers={"Accept-Language": "en"}).json()["message"]
        == "Saved."
    )


def test_locale_does_not_leak_to_next_request(locale_client):
    assert locale_client.get("/ctx", headers={"Accept-Language": "en"}).json() == {
        "locale": "en"
    }
    # 헤더 없는 다음 요청은 다시 기본값이다.
    assert locale_client.get("/ctx").json() == {"locale": "ko"}
    assert locale_client.get("/ctx-sync").json()["locale"] == "ko"
    # 요청이 끝난 바깥 컨텍스트도 그대로다.
    assert current_locale() == "ko"


def test_dependency_works_without_middleware():
    app = FastAPI()

    @app.get("/dep")
    def dep(locale: RequestLocale):
        return {"locale": locale}

    c = TestClient(app)
    assert c.get("/dep").json() == {"locale": "ko"}
    assert c.get("/dep", headers={"Accept-Language": "en"}).json() == {"locale": "en"}
    assert c.get("/dep", headers={"Accept-Language": "en;q=0"}).json() == {
        "locale": "ko"
    }


def test_non_http_scope_passes_through():
    seen: list[str] = []

    async def inner(scope, receive, send):
        seen.append(scope["type"])

    mw = RequestLocaleMiddleware(inner)
    asyncio.run(mw({"type": "lifespan"}, None, None))
    assert seen == ["lifespan"]


def test_context_is_reset_when_endpoint_raises():
    app = FastAPI()
    app.add_middleware(RequestLocaleMiddleware)

    @app.get("/boom")
    async def boom():
        raise RuntimeError("boom")

    c = TestClient(app, raise_server_exceptions=False)
    assert c.get("/boom", headers={"Accept-Language": "en"}).status_code == 500
    assert current_locale() == "ko"


def test_concurrent_requests_do_not_share_locale():
    """동시에 진행 중인 요청이 서로의 언어를 보지 않는다.

    모든 요청이 엔드포인트 안에서 한 번에 멈춰 있다가(장벽) 함께 풀린 뒤 자기
    언어를 읽는다 — 컨텍스트가 공유되면 마지막으로 들어온 요청의 언어가 섞인다.
    """
    app = FastAPI()
    app.add_middleware(RequestLocaleMiddleware)
    n = 20
    arrived = 0
    gate: asyncio.Event | None = None

    @app.get("/slow")
    async def slow():
        nonlocal arrived
        before = current_locale()
        arrived += 1
        if arrived == n:
            gate.set()
        await gate.wait()
        await asyncio.sleep(0)
        return {"before": before, "after": current_locale()}

    async def run() -> list[tuple[str, dict]]:
        nonlocal gate
        gate = asyncio.Event()
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
            langs = ["en" if i % 2 else "ko" for i in range(n)]
            responses = await asyncio.wait_for(
                asyncio.gather(
                    *(c.get("/slow", headers={"Accept-Language": lang}) for lang in langs)
                ),
                timeout=10,
            )
            return [(lang, r.json()) for lang, r in zip(langs, responses)]

    results = asyncio.run(run())
    assert len(results) == n
    for lang, body in results:
        assert body == {"before": lang, "after": lang}


def test_concurrent_sync_endpoints_do_not_share_locale():
    """스레드풀에서 도는 동기 엔드포인트도 요청마다 자기 언어를 본다."""
    app = FastAPI()
    app.add_middleware(RequestLocaleMiddleware)
    n = 8
    barrier = threading.Barrier(n, timeout=10)

    @app.get("/slow-sync")
    def slow_sync():
        before = current_locale()
        barrier.wait()
        return {"before": before, "after": current_locale()}

    async def run():
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
            langs = ["en" if i % 2 else "ko" for i in range(n)]
            responses = await asyncio.gather(
                *(c.get("/slow-sync", headers={"Accept-Language": l}) for l in langs)
            )
            return [(lang, r.json()) for lang, r in zip(langs, responses)]

    for lang, body in asyncio.run(run()):
        assert body == {"before": lang, "after": lang}


# ---------------------------------------------------------------------------
# 전역 500 응답 문구
# ---------------------------------------------------------------------------


def _boom_app(with_locale_middleware: bool) -> TestClient:
    app = FastAPI()
    if with_locale_middleware:
        app.add_middleware(RequestLocaleMiddleware)
    observability.install(app)

    @app.get("/boom")
    def boom():
        raise RuntimeError("SECRET")

    return TestClient(app, raise_server_exceptions=False)


@pytest.mark.parametrize("with_mw", [True, False])
def test_global_500_detail_follows_locale(with_mw):
    c = _boom_app(with_mw)
    ko = c.get("/boom")
    assert ko.status_code == 500
    assert ko.json()["detail"] == "내부 서버 오류가 발생했습니다."
    en = c.get("/boom", headers={"Accept-Language": "en-US,en;q=0.9"})
    assert en.status_code == 500
    assert en.json()["detail"] == "An internal server error occurred."
    assert "SECRET" not in en.text
    unsupported = c.get("/boom", headers={"Accept-Language": "ja"})
    assert unsupported.json()["detail"] == "내부 서버 오류가 발생했습니다."


# ---------------------------------------------------------------------------
# 실제 앱 배선
# ---------------------------------------------------------------------------


def test_main_app_installs_locale_middleware():
    from app.main import app

    assert any(m.cls is RequestLocaleMiddleware for m in app.user_middleware)


def test_main_app_cors_allows_accept_language_preflight():
    """트레이너 웹(다른 출처)이 `Accept-Language` 를 실어 보낼 수 있어야 한다."""
    from app.main import app

    c = TestClient(app)
    r = c.options(
        "/v1/healthz",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "accept-language, authorization",
        },
    )
    assert r.status_code == 200
    allowed = r.headers.get("access-control-allow-headers", "").lower()
    assert allowed == "*" or "accept-language" in allowed


def test_main_app_accepts_header_on_real_route(client):
    """실제 앱 경로가 `Accept-Language` 를 실은 요청을 그대로 받는다(헤더가 계약을 깨지 않음)."""
    for header in ("ko", "en", "en-US,en;q=0.9", "ja", "en;q=abc"):
        r = client.get("/v1/healthz", headers={"Accept-Language": header})
        assert r.status_code == 200
