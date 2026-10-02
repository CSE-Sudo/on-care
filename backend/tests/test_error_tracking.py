"""에러 추적(Sentry) 설정·개인정보 필터 — DB 불필요(#2839).

실제 전송 대신 이벤트를 모으는 가짜 전송기로, 보내는 내용에 요청 id 는 있고
Authorization·본문·쿼리·지역 변수는 없는지 확인한다.
"""

from __future__ import annotations

import json

import pytest
import sentry_sdk
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
from sentry_sdk.transport import Transport

from app.core import error_tracking, observability
from app.core.config import Settings

# 실제로 보내지 않는 주소(.invalid 는 해석되지 않는 예약 도메인). 전송은 가짜 전송기가 받는다.
FAKE_DSN = "https://publickey@o0.ingest.example.invalid/1"
#: 이벤트에 절대 실리면 안 되는 값들.
AUTH_VALUE = "Bearer dummy-token-for-scrub-test"
BODY_MARKER = "dummy-health-note-blood-pressure-150"
QUERY_MARKER = "dummy-query-marker"
LOCAL_MARKER = "dummy-local-variable-value"


class _CaptureTransport(Transport):
    """보내려는 이벤트를 목록에 모은다."""

    def __init__(self) -> None:
        super().__init__()
        self.events: list[dict] = []

    def capture_envelope(self, envelope) -> None:
        for item in envelope.items:
            if item.type == "event":
                self.events.append(item.payload.json)


def _settings(**kw) -> Settings:
    base = {"_env_file": None, "env": "staging", "sentry_dsn": FAKE_DSN}
    base.update(kw)
    return Settings(**base)


@pytest.fixture
def reset_sentry():
    yield
    client = sentry_sdk.get_client()
    if client.is_active():
        client.close()
    sentry_sdk.get_global_scope().set_client(None)


# --- 켜는 조건 ---------------------------------------------------------------


def test_disabled_without_dsn():
    assert error_tracking.is_enabled(_settings(sentry_dsn="")) is False
    assert error_tracking.is_enabled(_settings(sentry_dsn="   ")) is False


def test_disabled_in_dev_even_with_dsn():
    assert error_tracking.is_enabled(_settings(env="dev")) is False


@pytest.mark.parametrize("env", ["staging", "prod"])
def test_enabled_with_dsn_outside_dev(env):
    s = Settings.model_construct(env=env, sentry_dsn=FAKE_DSN)
    assert error_tracking.is_enabled(s) is True


def test_init_without_dsn_leaves_sdk_inactive(reset_sentry):
    assert error_tracking.init_error_tracking(_settings(sentry_dsn="")) is False
    assert sentry_sdk.get_client().is_active() is False


def test_init_in_dev_leaves_sdk_inactive(reset_sentry):
    assert error_tracking.init_error_tracking(_settings(env="dev")) is False
    assert sentry_sdk.get_client().is_active() is False


def test_default_settings_have_no_dsn(monkeypatch):
    monkeypatch.delenv("SENTRY_DSN", raising=False)
    s = Settings(_env_file=None)
    assert s.sentry_dsn == ""
    assert s.sentry_sample_rate == 1.0


def test_sample_rate_must_be_between_zero_and_one():
    with pytest.raises(ValueError):
        _settings(sentry_sample_rate=1.5)


def test_init_applies_privacy_options(reset_sentry):
    assert error_tracking.init_error_tracking(
        _settings(sentry_environment="prod-kr"), transport=_CaptureTransport()
    )
    options = sentry_sdk.get_client().options
    assert options["send_default_pii"] is False
    assert options["max_request_body_size"] == "never"
    assert options["include_local_variables"] is False
    assert options["traces_sample_rate"] is None
    assert options["environment"] == "prod-kr"
    assert options["release"].startswith("oncare-backend@")


def test_capture_is_noop_when_disabled(reset_sentry):
    # 초기화하지 않은 상태에서 불러도 예외 없이 지나간다.
    error_tracking.tag_request("rid-1")
    error_tracking.capture_unhandled(RuntimeError("x"), request_id="rid-1")


# --- 개인정보 필터 -----------------------------------------------------------


def test_scrub_event_keeps_only_method_and_path():
    event = {
        "request": {
            "method": "POST",
            "url": f"https://api.example.invalid/v1/diet/analyze?token={QUERY_MARKER}",
            "headers": {"Authorization": AUTH_VALUE, "Cookie": "a=b"},
            "cookies": {"a": "b"},
            "query_string": f"token={QUERY_MARKER}",
            "data": {"note": BODY_MARKER},
            "env": {"REMOTE_ADDR": "10.0.0.1"},
        },
        "user": {"id": "user-1", "ip_address": "10.0.0.1"},
        "extra": {"payload": BODY_MARKER},
    }
    out = error_tracking.scrub_event(event)
    assert out["request"] == {
        "method": "POST",
        "url": "https://api.example.invalid/v1/diet/analyze",
    }
    assert "user" not in out
    assert "extra" not in out
    dumped = json.dumps(out)
    for marker in (AUTH_VALUE, BODY_MARKER, QUERY_MARKER, "10.0.0.1"):
        assert marker not in dumped


def test_scrub_event_drops_frame_vars():
    event = {
        "exception": {
            "values": [
                {
                    "type": "RuntimeError",
                    "stacktrace": {
                        "frames": [{"function": "f", "vars": {"note": LOCAL_MARKER}}]
                    },
                }
            ]
        },
        "threads": {
            "values": [{"stacktrace": {"frames": [{"vars": {"x": LOCAL_MARKER}}]}}]
        },
    }
    out = error_tracking.scrub_event(event)
    assert LOCAL_MARKER not in json.dumps(out)
    assert out["exception"]["values"][0]["stacktrace"]["frames"][0]["function"] == "f"


def test_scrub_event_without_request_is_left_alone():
    event = {"message": "boom", "level": "error"}
    assert error_tracking.scrub_event(dict(event)) == event


def test_scrub_breadcrumb_strips_query_and_message():
    crumb = {
        "category": "httplib",
        "message": f"note={BODY_MARKER}",
        "data": {
            "method": "GET",
            "status_code": 200,
            "url": f"https://dapi.example.invalid/v2/local?query={QUERY_MARKER}",
            "http.query": f"query={QUERY_MARKER}",
        },
    }
    out = error_tracking.scrub_breadcrumb(crumb)
    assert out is not None
    assert out["data"] == {
        "method": "GET",
        "status_code": 200,
        "url": "https://dapi.example.invalid/v2/local",
    }
    assert "message" not in out
    assert error_tracking.scrub_breadcrumb(None) is None


def test_scrub_event_scrubs_breadcrumbs_too():
    event = {
        "breadcrumbs": {
            "values": [{"category": "log", "message": BODY_MARKER, "data": {"x": 1}}]
        }
    }
    out = error_tracking.scrub_event(event)
    assert BODY_MARKER not in json.dumps(out)


# --- 앱에 붙였을 때 ---------------------------------------------------------


def _boom_app() -> FastAPI:
    app = FastAPI()
    observability.install(app)

    @app.post("/v1/boom")
    async def boom(request: Request):
        payload = await request.json()
        note = payload["note"]  # noqa: F841 — 지역 변수가 이벤트에 실리지 않는지 본다
        raise RuntimeError("boom")

    return app


def test_unhandled_error_is_sent_with_request_id_and_without_pii(reset_sentry):
    transport = _CaptureTransport()
    assert error_tracking.init_error_tracking(_settings(), transport=transport)

    with TestClient(_boom_app(), raise_server_exceptions=False) as client:
        res = client.post(
            f"/v1/boom?token={QUERY_MARKER}",
            json={"note": BODY_MARKER},
            headers={"Authorization": AUTH_VALUE, "X-Request-ID": "rid-2839"},
        )
    sentry_sdk.flush()

    assert res.status_code == 500
    assert res.json()["request_id"] == "rid-2839"
    assert transport.events, "처리하지 못한 예외가 전송되지 않았다"
    for event in transport.events:
        assert event["tags"]["request_id"] == "rid-2839"
        dumped = json.dumps(event, ensure_ascii=False)
        for marker in (AUTH_VALUE, BODY_MARKER, QUERY_MARKER):
            assert marker not in dumped
        assert "Authorization" not in dumped
    # 같은 예외는 한 번만 보낸다.
    assert len(transport.events) == 1


def test_unhandled_error_is_not_sent_when_disabled(reset_sentry):
    assert error_tracking.init_error_tracking(_settings(sentry_dsn="")) is False
    with TestClient(_boom_app(), raise_server_exceptions=False) as client:
        res = client.post("/v1/boom", json={"note": BODY_MARKER})
    assert res.status_code == 500
    assert sentry_sdk.get_client().is_active() is False
