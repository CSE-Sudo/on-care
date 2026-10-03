"""운영 배포 하드닝 — CORS 가드/파싱(순수) + 보안 헤더(DB)."""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config import Settings


# ---------- 순수 ----------

def test_prod_blocks_wildcard_cors():
    """운영에서 CORS 와일드카드('*')면 기동이 막혀야 한다."""
    with pytest.raises(ValidationError):
        Settings(_env_file=None, env="prod", jwt_secret="x" * 40, cors_allow_origins="*")


def test_cors_origin_list_parsing():
    s = Settings(_env_file=None, cors_allow_origins="https://a.com, https://b.com ,")
    assert s.cors_origin_list == ["https://a.com", "https://b.com"]
    assert s.is_cors_wildcard is False
    assert Settings(_env_file=None, cors_allow_origins="*").is_cors_wildcard is True


def test_wildcard_disables_credentials_semantics():
    # 와일드카드면 credentials 를 켜지 않는다(main.py 가 이 규칙을 사용)
    assert Settings(_env_file=None, cors_allow_origins="*").is_cors_wildcard is True


# ---------- DB(CI) ----------

def test_security_headers_present(client):
    r = client.get("/v1/ping")
    assert r.status_code == 200
    assert r.headers.get("X-Content-Type-Options") == "nosniff"
    assert r.headers.get("X-Frame-Options") == "DENY"
    assert r.headers.get("Referrer-Policy") == "no-referrer"
    # dev(비운영·force_https=false)에서는 HSTS 를 붙이지 않는다
    assert "Strict-Transport-Security" not in r.headers
