"""파일 업로드 경로의 본문 상한(413). (#2832)

채팅 사진(회원·트레이너)과 리포트 PDF 경로도 본문을 다 받기 전에 끊는지 본다.
핸들러 안의 `image.read(max + 1)` 검사는 Starlette 가 multipart 본문을 이미 다
받아 적재한 뒤라 막으려던 적재를 막지 못한다.

- 규칙 매칭·가드는 DB 없이 돈다(라우트 표와 미들웨어 규칙만 본다).
- 실제 앱으로 보내는 검사도 대부분 DB 없이 된다 — 상한을 넘는 본문은 라우터·인증에
  닿기 전에 끊기기 때문이다. 상한 이하 정상 전송은 기존 업로드 테스트가 다룬다.
"""
from __future__ import annotations

import re
from collections.abc import Iterator

import pytest
from fastapi import FastAPI, Request, UploadFile
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from starlette.middleware.cors import CORSMiddleware

from app.core.body_limit import BodyLimitRule, RequestBodySizeLimitMiddleware
from app.core.config import Settings
from tests.route_helpers import api_routes

MiB = 1024 * 1024


def _settings(**overrides) -> Settings:
    return Settings(_env_file=None, **overrides)


def _middleware(rules) -> RequestBodySizeLimitMiddleware:
    async def _noop(scope, receive, send):  # pragma: no cover - 호출되지 않음
        return None

    return RequestBodySizeLimitMiddleware(_noop, rules=rules)


# ---- 규칙 표 (DB 불필요) ----


def test_prefix_rule_matches_by_prefix_only():
    rule = BodyLimitRule("/v1/diet/analyze", 10)
    assert rule.matches("/v1/diet/analyze")
    assert not rule.matches("/v1/diet/entries")
    assert not rule.matches("/v2/v1/diet/analyze")


def test_regex_rule_matches_the_whole_path():
    rule = BodyLimitRule(r"/v1/trainer/clients/[^/]+/chat/image", 10, regex=True)
    assert rule.matches("/v1/trainer/clients/user-1/chat/image")
    assert not rule.matches("/v1/trainer/clients/user-1/chat/image/extra")
    assert not rule.matches("/v1/trainer/clients/a/b/chat/image")
    assert not rule.matches("/v1/trainer/clients//chat/image")
    assert not rule.matches("/x/v1/trainer/clients/user-1/chat/image")


def test_first_matching_rule_wins():
    first = BodyLimitRule("/v1/a", 1)
    second = BodyLimitRule("/v1", 2)
    mw = _middleware((first, second))
    assert mw.rule_for("/v1/a/b") is first
    assert mw.rule_for("/v1/c") is second
    assert mw.rule_for("/v2") is None


def test_legacy_arguments_still_build_prefix_rules():
    mw = RequestBodySizeLimitMiddleware(
        None, max_bytes=5, protected_paths=("/a", "/b"), detail="x"
    )
    assert [(r.path, r.max_bytes, r.detail, r.regex) for r in mw.rules] == [
        ("/a", 5, "x", False),
        ("/b", 5, "x", False),
    ]


def test_legacy_paths_without_a_limit_are_refused():
    with pytest.raises(ValueError):
        RequestBodySizeLimitMiddleware(None, protected_paths=("/a",))


def test_main_rules_cover_every_upload_path_with_its_own_limit():
    from app.main import body_limit_rules

    s = _settings()
    mw = _middleware(body_limit_rules(s))
    slack = s.upload_body_slack_bytes
    expected = {
        "/v1/diet/analyze": s.max_upload_bytes,
        "/v1/ai-coach/chat": s.coach_chat_max_body_bytes,
        "/v1/me/coach/chat/image": s.max_chat_image_bytes + slack,
        "/v1/trainer/clients/user-1/chat/image": s.max_chat_image_bytes + slack,
        "/v1/trainer/clients/user-1/report/send-pdf": s.max_report_pdf_bytes + slack,
    }
    for path, limit in expected.items():
        rule = mw.rule_for(path)
        assert rule is not None, path
        assert rule.max_bytes == limit, path

    # JSON 으로 대량 텍스트를 받는 경로와 일반 쓰기 경로는 묶지 않는다.
    for path in ("/v1/coach-docs", "/v1/me/coach/chat", "/v1/trainer/clients/u/chat"):
        assert mw.rule_for(path) is None, path
    # 정규식은 전체 일치다 — 한 단계 더 깊은 경로나 빈 id 는 묶지 않는다.
    for path in (
        "/v1/trainer/clients/u/chat/image/extra",
        "/v1/trainer/clients//chat/image",
    ):
        assert mw.rule_for(path) is None, path
    # 트레이너 AI 코칭 API 는 지웠다(#3085) — 상한 규칙도 함께 없앴다.
    assert mw.rule_for("/v1/trainer/clients/user-1/ai-coach") is None


def test_main_rules_follow_the_settings():
    from app.main import body_limit_rules

    s = _settings(max_chat_image_bytes=MiB, max_report_pdf_bytes=2 * MiB,
                  upload_body_slack_bytes=1024)
    mw = _middleware(body_limit_rules(s))
    assert mw.rule_for("/v1/me/coach/chat/image").max_bytes == MiB + 1024
    assert mw.rule_for("/v1/trainer/clients/u/report/send-pdf").max_bytes == 2 * MiB + 1024


def test_main_rules_have_path_specific_messages():
    from app.main import body_limit_rules

    s = _settings()
    mw = _middleware(body_limit_rules(s))
    image = mw.rule_for("/v1/me/coach/chat/image").detail
    pdf = mw.rule_for("/v1/trainer/clients/u/report/send-pdf").detail
    assert image and "사진" in image and "6MB" in image
    assert pdf and "PDF" in pdf and "8MB" in pdf
    assert mw.rule_for("/v1/trainer/clients/u/chat/image").detail == image


# ---- 파일을 받는 라우트 가드 (DB 불필요) ----


def _takes_a_file(route: APIRoute) -> bool:
    for param in route.dependant.body_params:
        annotation = getattr(param, "type_", None) or param.field_info.annotation
        if annotation is UploadFile or "UploadFile" in str(annotation):
            return True
    return False


def _sample_path(route: APIRoute) -> str:
    return re.sub(r"\{[^}]+\}", "sample-id", route.path)


def _app_body_limit() -> RequestBodySizeLimitMiddleware:
    from app.main import app

    found = [m for m in app.user_middleware if m.cls is RequestBodySizeLimitMiddleware]
    assert len(found) == 1, "본문 상한 미들웨어는 표 하나로 한 번만 등록한다"
    return _middleware(found[0].kwargs["rules"])


def test_every_file_upload_route_has_a_body_limit():
    from app.main import app

    mw = _app_body_limit()
    upload_routes = [r for r in api_routes(app) if _takes_a_file(r)]
    assert upload_routes, "파일을 받는 라우트를 하나도 못 찾았다 — 판정이 깨졌다"
    missing = [r.path for r in upload_routes if mw.rule_for(_sample_path(r)) is None]
    assert missing == [], (
        "파일을 받는 라우트에 본문 상한이 없다. app/main.py 의 body_limit_rules 에 "
        "더할 것: " + ", ".join(missing)
    )


def test_guard_recognizes_the_known_upload_routes():
    from app.main import app

    paths = {r.path for r in api_routes(app) if _takes_a_file(r)}
    assert {
        "/v1/diet/analyze",
        "/v1/me/coach/chat/image",
        "/v1/trainer/clients/{member_id}/chat/image",
        "/v1/trainer/clients/{member_id}/report/send-pdf",
    } <= paths


def test_body_limit_sits_inside_cors():
    """413 에도 CORS 헤더가 붙으려면 CORS 가 바깥(나중 등록 = 목록 앞)이어야 한다."""
    from app.main import app

    classes = [m.cls for m in app.user_middleware]
    assert classes.index(CORSMiddleware) < classes.index(RequestBodySizeLimitMiddleware)


# ---- 실제 앱으로 보내기 — 상한 초과는 라우터·인증 전에 끊긴다 (DB 불필요) ----


@pytest.fixture
def app_client() -> Iterator[TestClient]:
    from app.main import app

    # lifespan(DB 초기화)을 돌리지 않는다 — 413 은 라우터에 닿기 전에 난다.
    yield TestClient(app)


UPLOAD_CASES = [
    ("/v1/me/coach/chat/image", "image", "사진"),
    ("/v1/trainer/clients/user-1/chat/image", "image", "사진"),
    ("/v1/trainer/clients/user-1/report/send-pdf", "pdf", "PDF"),
]


def _limit_for(path: str) -> int:
    from app.main import body_limit_rules, settings

    rule = _middleware(body_limit_rules(settings)).rule_for(path)
    assert rule is not None
    return rule.max_bytes


@pytest.mark.parametrize(("path", "field", "word"), UPLOAD_CASES)
def test_declared_oversized_upload_is_413_with_cors(app_client, path, field, word):
    from app.main import settings

    origin = (settings.cors_origin_list or ["http://localhost:5173"])[0]
    if origin == "*":
        origin = "http://localhost:5173"
    r = app_client.post(
        path,
        files={field: ("big.bin", b"x" * (_limit_for(path) + 1), "application/octet-stream")},
        headers={"Origin": origin, "Authorization": "Bearer not-checked"},
    )
    assert r.status_code == 413, r.text
    assert word in r.json()["detail"]
    assert r.headers.get("access-control-allow-origin") in {origin, "*"}


@pytest.mark.parametrize(("path", "field", "word"), UPLOAD_CASES)
def test_chunked_oversized_upload_is_413(app_client, path, field, word):
    limit = _limit_for(path)

    # 형식이 맞는 multipart 머리를 먼저 보내 파서가 끝까지 읽게 한다. Content-Length
    # 없이(chunked) 보내므로 헤더 검사가 아니라 누적 검사로 막혀야 한다.
    def chunks() -> Iterator[bytes]:
        yield (
            f'--zzz\r\nContent-Disposition: form-data; name="{field}"; '
            'filename="big.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'
        ).encode()
        sent = 0
        piece = b"y" * (256 * 1024)
        while sent <= limit:
            yield piece
            sent += len(piece)

    r = app_client.post(
        path,
        content=chunks(),
        headers={"Content-Type": "multipart/form-data; boundary=zzz"},
    )
    assert r.status_code == 413, r.text
    assert word in r.json()["detail"]


# ---- 미들웨어 단위: 정규식 규칙도 본문을 읽기 전에 끊는다 (DB 불필요) ----


@pytest.fixture
def entered() -> list[str]:
    return []


@pytest.fixture
def mini(entered: list[str]) -> Iterator[TestClient]:
    app = FastAPI()
    app.add_middleware(
        RequestBodySizeLimitMiddleware,
        rules=(
            BodyLimitRule(r"/clients/[^/]+/image", 100, "사진이 커요", regex=True),
            BodyLimitRule("/pdf", 200, "PDF 가 커요"),
        ),
    )

    async def _handle(request: Request) -> dict[str, int]:
        entered.append("handler")
        body = await request.body()
        return {"len": len(body)}

    app.post("/clients/{cid}/image")(_handle)
    app.post("/pdf")(_handle)
    app.post("/clients/{cid}/note")(_handle)

    with TestClient(app) as c:
        yield c


def test_regex_route_rejects_before_the_handler(mini, entered):
    r = mini.post("/clients/abc/image", content=b"x" * 101)
    assert r.status_code == 413
    assert r.json() == {"detail": "사진이 커요"}
    assert entered == []


def test_each_rule_uses_its_own_limit(mini):
    assert mini.post("/clients/abc/image", content=b"x" * 100).status_code == 200
    assert mini.post("/pdf", content=b"x" * 150).status_code == 200
    r = mini.post("/pdf", content=b"x" * 201)
    assert r.status_code == 413
    assert r.json() == {"detail": "PDF 가 커요"}


def test_unmatched_path_is_not_limited(mini):
    assert mini.post("/clients/abc/note", content=b"x" * 1000).status_code == 200

