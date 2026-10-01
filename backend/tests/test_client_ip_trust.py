"""클라이언트 IP 신뢰 범위와 계정 단위 시도 제한. (#2815)

요청자가 `X-Forwarded-For` 를 바꿔 보내도 rate limit 버킷과 감사 로그 IP 가 바뀌지
않아야 하고, IP 를 바꿔 가며 한 계정(로그인 이메일·연결 코드 트레이너)을 노리는
시도는 계정 쪽 버킷에서 막혀야 한다.

앞부분은 DB 없이 도는 순수 검사, 뒷부분(`client` 픽스처)은 CI 의 Postgres 에서 돈다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from starlette.requests import Request

from app.core.client_ip import client_ip
from app.core.config import Settings
from app.core.rate_limit import RateLimiter, limiter, rate_limit

PASSWORD = "ip-trust-pw-1234"


def _settings(**overrides) -> Settings:
    return Settings(_env_file=None, **overrides)


def _request(*xff: str, peer: str | None = "10.0.0.9") -> Request:
    headers = [(b"x-forwarded-for", value.encode()) for value in xff]
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/",
        "headers": headers,
        "client": (peer, 5000) if peer is not None else None,
    }
    return Request(scope)


# ---- 신뢰 홉 수 기본값 ----


def test_proxy_hops_default_is_zero_outside_prod():
    assert _settings(env="dev").effective_proxy_hops == 0
    assert _settings(env="staging").effective_proxy_hops == 0


def test_proxy_hops_default_is_one_in_prod():
    prod = _settings(
        env="prod",
        jwt_secret="x" * 40,
        cors_allow_origins="https://oncare.example",
        seed_demo_data=False,
        auto_create_tables=False,
    )
    assert prod.effective_proxy_hops == 1


def test_proxy_hops_explicit_value_wins():
    assert _settings(env="dev", trusted_proxy_hops=2).effective_proxy_hops == 2
    prod = _settings(
        env="prod",
        jwt_secret="x" * 40,
        cors_allow_origins="https://oncare.example",
        seed_demo_data=False,
        auto_create_tables=False,
        trusted_proxy_hops=0,
    )
    assert prod.effective_proxy_hops == 0


def test_proxy_hops_rejects_negative():
    with pytest.raises(ValueError):
        _settings(trusted_proxy_hops=-1)


# ---- client_ip ----


def test_zero_hops_ignores_forwarded_header():
    """프록시를 믿지 않으면 헤더가 무엇이든 소켓 주소다."""
    request = _request("1.1.1.1", peer="10.0.0.9")
    assert client_ip(request, _settings(trusted_proxy_hops=0)) == "10.0.0.9"


def test_one_hop_reads_rightmost_value():
    """프록시가 붙인 오른쪽 끝 값이 클라이언트다. 왼쪽 위조 값은 무시한다."""
    request = _request("6.6.6.6, 203.0.113.7")
    assert client_ip(request, _settings(trusted_proxy_hops=1)) == "203.0.113.7"


def test_spoofed_left_values_do_not_change_result():
    s = _settings(trusted_proxy_hops=1)
    a = client_ip(_request("1.1.1.1, 203.0.113.7"), s)
    b = client_ip(_request("9.9.9.9, 8.8.8.8, 203.0.113.7"), s)
    assert a == b == "203.0.113.7"


def test_two_hops_reads_second_from_right():
    request = _request("6.6.6.6, 203.0.113.7, 10.1.1.1")
    assert client_ip(request, _settings(trusted_proxy_hops=2)) == "203.0.113.7"


def test_multiple_header_lines_are_joined_in_order():
    request = _request("6.6.6.6", "203.0.113.7")
    assert client_ip(request, _settings(trusted_proxy_hops=1)) == "203.0.113.7"


def test_short_chain_falls_back_to_socket_address():
    """헤더 값이 홉 수보다 적으면 프록시를 거치지 않은 요청이다."""
    request = _request("203.0.113.7", peer="10.0.0.9")
    assert client_ip(request, _settings(trusted_proxy_hops=2)) == "10.0.0.9"


def test_missing_header_falls_back_to_socket_address():
    assert client_ip(_request(peer="10.0.0.9"), _settings(trusted_proxy_hops=1)) == "10.0.0.9"


def test_unknown_peer_is_empty_string():
    assert client_ip(_request(peer=None), _settings(trusted_proxy_hops=0)) == ""


def test_result_is_capped_to_audit_column_length():
    request = _request("x" * 200)
    assert len(client_ip(request, _settings(trusted_proxy_hops=1))) == 64


def test_audit_module_uses_the_same_helper():
    """감사 로그와 rate limit 이 같은 함수를 쓴다."""
    from app.core import rate_limit as rate_limit_module
    from app.services import audit

    assert audit.client_ip is client_ip
    assert rate_limit_module.client_ip is client_ip


# ---- RateLimiter: 실패만 세는 버킷 ----


def test_retry_after_does_not_count_attempts():
    rl = RateLimiter()
    for _ in range(10):
        assert rl.retry_after("k", 3, 60.0) is None


def test_hit_then_retry_after_blocks_at_limit():
    rl = RateLimiter()
    for _ in range(3):
        rl.hit("k", 60.0)
    retry = rl.retry_after("k", 3, 60.0)
    assert retry is not None and 1 <= retry <= 60


def test_reset_clears_failures():
    rl = RateLimiter()
    for _ in range(3):
        rl.hit("k", 60.0)
    rl.reset("k")
    assert rl.retry_after("k", 3, 60.0) is None


def test_failures_expire_with_window(monkeypatch):
    import app.core.rate_limit as module

    now = [1000.0]
    monkeypatch.setattr(module.time, "monotonic", lambda: now[0])
    rl = RateLimiter()
    for _ in range(3):
        rl.hit("k", 60.0)
    assert rl.retry_after("k", 3, 60.0) is not None
    now[0] += 61.0
    assert rl.retry_after("k", 3, 60.0) is None


# ---- rate_limit 의존성: 헤더로 버킷이 갈라지지 않는다 ----


def _limited_app() -> FastAPI:
    app = FastAPI()

    @app.get("/limited", dependencies=[Depends(rate_limit("ip-trust-test", 3))])
    def limited() -> dict[str, str]:
        return {"ok": "yes"}

    return app


def test_rotating_forwarded_header_does_not_split_bucket():
    limiter.clear()
    with TestClient(_limited_app()) as tc:
        codes = [
            tc.get("/limited", headers={"X-Forwarded-For": f"1.1.1.{i}"}).status_code
            for i in range(5)
        ]
    assert codes[:3] == [200, 200, 200]
    assert codes[3:] == [429, 429]


# ---- 로그인 이메일 잠금 (DB) ----


def _register(client, email: str) -> None:
    response = client.post(
        "/v1/auth/register", json={"email": email, "password": PASSWORD, "name": "ip"}
    )
    assert response.status_code == 201, response.text


def _login(client, email: str, password: str, ip: str):
    return client.post(
        "/v1/auth/login",
        data={"username": email, "password": password},
        headers={"X-Forwarded-For": ip},
    )


def test_repeated_failures_lock_email_even_from_different_ips(client):
    email = f"ip-lock-{uuid4().hex[:10]}@oncare.com"
    _register(client, email)
    for i in range(5):
        assert _login(client, email, "wrong-pw-0000", f"1.1.1.{i}").status_code == 401
    # 잠긴 뒤에는 맞는 비밀번호도 429 — 맞는지 여부를 드러내지 않는다.
    locked = _login(client, email, PASSWORD, "2.2.2.2")
    assert locked.status_code == 429
    assert int(locked.headers["Retry-After"]) >= 1


def test_lock_ignores_email_case_and_spaces(client):
    email = f"ip-case-{uuid4().hex[:10]}@oncare.com"
    _register(client, email)
    variants = [email, email.upper(), f"  {email}  ", email.title(), email]
    for i, variant in enumerate(variants):
        assert _login(client, variant, "wrong-pw-0000", f"3.3.3.{i}").status_code == 401
    assert _login(client, email, PASSWORD, "3.3.3.9").status_code == 429


def test_success_resets_failure_count(client):
    email = f"ip-reset-{uuid4().hex[:10]}@oncare.com"
    _register(client, email)
    for _ in range(4):
        assert _login(client, email, "wrong-pw-0000", "4.4.4.4").status_code == 401
    assert _login(client, email, PASSWORD, "4.4.4.4").status_code == 200
    for _ in range(4):
        assert _login(client, email, "wrong-pw-0000", "4.4.4.4").status_code == 401
    assert _login(client, email, PASSWORD, "4.4.4.4").status_code == 200


def test_unknown_email_is_locked_the_same_way(client):
    """없는 이메일도 똑같이 잠겨 가입 여부가 갈리지 않는다."""
    email = f"ip-ghost-{uuid4().hex[:10]}@oncare.com"
    for i in range(5):
        assert _login(client, email, "wrong-pw-0000", f"5.5.5.{i}").status_code == 401
    assert _login(client, email, "wrong-pw-0000", "5.5.5.9").status_code == 429


def test_lock_respects_rate_limit_switch(client, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "rate_limit_enabled", False)
    email = f"ip-off-{uuid4().hex[:10]}@oncare.com"
    _register(client, email)
    for _ in range(7):
        assert _login(client, email, "wrong-pw-0000", "6.6.6.6").status_code == 401
    assert _login(client, email, PASSWORD, "6.6.6.6").status_code == 200


def test_audit_ip_ignores_spoofed_header(client, db_session):
    from sqlalchemy import select

    from app.models.models import AuditLog

    email = f"ip-audit-{uuid4().hex[:10]}@oncare.com"
    _register(client, email)
    assert _login(client, email, "wrong-pw-0000", "6.6.6.6").status_code == 401
    db_session.expire_all()
    row = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == "auth.login",
            AuditLog.success.is_(False),
            AuditLog.detail == email,
        )
    ).first()
    assert row is not None
    # 테스트 환경은 프록시 홉 0 — 소켓 주소(TestClient 는 "testclient")를 적는다.
    assert row.ip == "testclient"
    assert row.ip != "6.6.6.6"


# ---- 연결 코드 트레이너 버킷 (DB) ----


def _trainer_token(client) -> str:
    email = f"ip-trainer-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": PASSWORD, "name": "트레이너"},
    )
    assert response.status_code == 201, response.text
    login = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert login.status_code == 200, login.text
    return login.json()["access_token"]


@pytest.mark.parametrize(
    "path", ["/v1/trainer/pairing-code/preview", "/v1/trainer/pairing-code"]
)
def test_trainer_daily_pairing_cap_survives_ip_rotation(client, monkeypatch, path):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "pairing_redeem_per_day", 3)
    token = _trainer_token(client)
    codes = []
    for i in range(5):
        response = client.post(
            path,
            json={"code": "000000"},
            headers={
                "Authorization": f"Bearer {token}",
                "X-Forwarded-For": f"7.7.{i}.1",
            },
        )
        codes.append(response.status_code)
    # 없는 코드라 처음 셋은 404, 그 뒤는 트레이너 하루 상한으로 429.
    assert codes[:3] == [404, 404, 404]
    assert codes[3:] == [429, 429]


def test_preview_and_redeem_share_trainer_bucket(client, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "pairing_redeem_per_day", 2)
    token = _trainer_token(client)
    headers = {"Authorization": f"Bearer {token}"}
    assert client.post(
        "/v1/trainer/pairing-code/preview", json={"code": "000000"}, headers=headers
    ).status_code == 404
    assert client.post(
        "/v1/trainer/pairing-code", json={"code": "000000"}, headers=headers
    ).status_code == 404
    assert client.post(
        "/v1/trainer/pairing-code/preview", json={"code": "000000"}, headers=headers
    ).status_code == 429


def test_trainer_bucket_is_per_trainer(client, monkeypatch):
    """한 트레이너가 한도를 다 써도 다른 트레이너는 시도할 수 있다."""
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "pairing_redeem_per_day", 1)
    first = _trainer_token(client)
    second = _trainer_token(client)
    path = "/v1/trainer/pairing-code/preview"
    assert client.post(
        path, json={"code": "000000"}, headers={"Authorization": f"Bearer {first}"}
    ).status_code == 404
    assert client.post(
        path, json={"code": "000000"}, headers={"Authorization": f"Bearer {first}"}
    ).status_code == 429
    assert client.post(
        path, json={"code": "000000"}, headers={"Authorization": f"Bearer {second}"}
    ).status_code == 404
