"""관측성 하드닝(#288) — request-id 생성/검증/전달, 전역 500, DB readiness."""
from __future__ import annotations

import re

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core import observability

_HEX32 = re.compile(r"^[0-9a-f]{32}$")


def test_request_id_generated_when_absent(client):
    r = client.get("/v1/healthz")
    rid = r.headers.get("X-Request-ID")
    assert rid and _HEX32.match(rid)  # 헤더 없으면 새 UUID 생성


def test_request_id_passed_through_when_valid(client):
    r = client.get("/v1/healthz", headers={"X-Request-ID": "abc-123_XYZ.v1"})
    assert r.headers.get("X-Request-ID") == "abc-123_XYZ.v1"


def test_request_id_replaced_when_invalid(client):
    # 형식 위반(공백·특수문자) → 신뢰하지 않고 새로 생성(로그 인젝션 방지)
    bad = "bad id; drop table\nX-Injected: 1"
    r = client.get("/v1/healthz", headers={"X-Request-ID": bad})
    rid = r.headers.get("X-Request-ID")
    assert rid != bad and _HEX32.match(rid)
    # 길이 초과(>64)도 거부
    r2 = client.get("/v1/healthz", headers={"X-Request-ID": "a" * 65})
    assert r2.headers.get("X-Request-ID") != "a" * 65


def test_global_500_hides_detail_and_carries_request_id():
    app = FastAPI()
    observability.install(app)

    @app.get("/boom")
    def boom():
        raise RuntimeError("SECRET: db password = hunter2")

    c = TestClient(app, raise_server_exceptions=False)
    r = c.get("/boom", headers={"X-Request-ID": "trace-abc"})
    assert r.status_code == 500
    assert "SECRET" not in r.text and "hunter2" not in r.text  # 내부 상세 미노출
    body = r.json()
    assert body["detail"] == "내부 서버 오류가 발생했습니다."
    assert body["request_id"] == "trace-abc"
    assert r.headers.get("X-Request-ID") == "trace-abc"


def test_access_log_carries_request_id_on_success(client):
    """정상 200 응답의 액세스 로그에도 request_id 가 실려야 한다(reset 전에 로그).

    로그·헤더가 request_id_ctx.reset() 이후에 실행되면 로그 request_id 가 '-' 가 되어
    상관관계가 끊긴다 — 그 회귀를 막는다.
    """
    import io
    import logging

    from app.core.observability import RequestIdLogFilter

    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(logging.Formatter("[%(request_id)s] %(message)s"))
    handler.addFilter(RequestIdLogFilter())  # contextvar 에서 request_id 주입
    access = logging.getLogger("app.access")
    access.addHandler(handler)
    access.setLevel(logging.INFO)
    try:
        # 헬스 경로(/healthz·/readyz·/ping)는 액세스 로그에서 제외되므로 비-헬스 경로로 검사한다.
        client.get("/v1/version", headers={"X-Request-ID": "trace-log-1"})
    finally:
        access.removeHandler(handler)
    out = stream.getvalue()
    assert "[trace-log-1]" in out  # reset 이전에 로그 → rid 가 '-' 가 아님


# ---------- 위치 좌표·IP 가 요청 로그에 남지 않음 (#3031) ----------

# 일부러 흔하지 않은 자릿수로 고른 좌표·IP — 로그에 우연히 같은 문자열이 섞일 일이 없다.
_LAT = "37.5665123"
_LNG = "126.9780456"
_FORWARDED_IP = "203.0.113.77"
_SEARCH_WORD = "zz-gangnam-probe"

_COORDINATE_REQUESTS = [
    f"/v1/places/nearby?lat={_LAT}&lng={_LNG}&category=fitness",
    f"/v1/gyms?lat={_LAT}&lng={_LNG}",
    f"/v1/gyms/1?lat={_LAT}&lng={_LNG}",
    f"/v1/trainer/gyms/search?query={_SEARCH_WORD}&lat={_LAT}&lng={_LNG}",
    f"/v1/trainer/gyms/nearby?lat={_LAT}&lng={_LNG}",
]


def _capture_access_log(client, url: str) -> tuple[str, list]:
    """한 요청의 `app.access` 출력(포맷된 줄)과 레코드를 함께 돌려준다."""
    import io
    import logging

    from app.core.observability import RequestIdLogFilter

    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(logging.Formatter("[%(request_id)s] %(name)s: %(message)s"))
    handler.addFilter(RequestIdLogFilter())
    records: list = []

    class _Keep(logging.Handler):
        def emit(self, record):
            records.append(record)

    keep = _Keep()
    access = logging.getLogger("app.access")
    access.addHandler(handler)
    access.addHandler(keep)
    access.setLevel(logging.INFO)
    try:
        client.get(url, headers={"X-Forwarded-For": _FORWARDED_IP})
    finally:
        access.removeHandler(handler)
        access.removeHandler(keep)
    return stream.getvalue(), records


@pytest.mark.parametrize("url", _COORDINATE_REQUESTS)
def test_access_log_omits_coordinates(client, url):
    """좌표를 쿼리로 받는 경로도 로그에는 경로만 남는다 — 인증 실패 응답이어도 같다."""
    out, records = _capture_access_log(client, url)
    assert records, "요청 로그가 한 줄은 남아야 한다"
    for needle in ("lat=", "lng=", "query=", "category=", _LAT, _LNG, _SEARCH_WORD, "?"):
        assert needle not in out, f"{needle!r} 가 액세스 로그에 남았다: {out!r}"


@pytest.mark.parametrize("url", _COORDINATE_REQUESTS)
def test_access_log_omits_client_ip(client, url):
    """프록시가 넘긴 사용자 IP(X-Forwarded-For)도, 테스트 클라이언트 주소도 남지 않는다."""
    out, records = _capture_access_log(client, url)
    assert _FORWARDED_IP not in out
    assert "testclient" not in out
    for record in records:
        assert _FORWARDED_IP not in record.getMessage()
        assert all(_FORWARDED_IP not in str(arg) for arg in record.args or ())


def test_access_log_keeps_method_path_status_and_request_id(client):
    """좌표를 빼도 운영 가시성(method·경로·상태·소요시간·request_id)은 그대로다."""
    import logging

    out, records = _capture_access_log(client, _COORDINATE_REQUESTS[0])
    assert len(records) == 1
    assert records[0].levelno == logging.INFO
    line = records[0].getMessage()
    assert line.startswith("GET '/v1/places/nearby' -> ")
    assert re.search(r"-> \d{3} \(\d+\.\dms\)$", line)
    # X-Request-ID 를 주지 않았으니 새로 만든 32자리 요청 id 가 줄 앞에 붙는다.
    assert re.match(r"\[[0-9a-f]{32}\] app\.access: GET ", out)


def test_readyz_ok(client):
    r = client.get("/v1/readyz")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_readyz_503_on_db_failure(client):
    """DB 장애 시 /readyz 는 내부 상세를 숨긴 503. (/healthz 는 liveness 라 영향 없음)"""
    from app.db.session import get_db
    from app.main import app

    rolled_back = {"called": False}

    class _BoomSession:
        def execute(self, *a, **k):
            raise RuntimeError("connection refused to 10.0.0.5:5432")

        def rollback(self):  # /readyz 가 실패 트랜잭션을 정리하는지(리뷰 #291) 확인용
            rolled_back["called"] = True

    def _boom_db():
        yield _BoomSession()

    app.dependency_overrides[get_db] = _boom_db
    try:
        r = client.get("/v1/readyz")
        assert r.status_code == 503
        assert "connection refused" not in r.text  # 원인 미노출
        assert rolled_back["called"] is True        # 예외 시 rollback 호출됨
        # liveness 는 DB 와 무관하게 여전히 200
        assert client.get("/v1/healthz").status_code == 200
    finally:
        app.dependency_overrides.pop(get_db, None)
