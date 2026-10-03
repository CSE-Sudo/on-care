"""운영에서 AI 대체 경로 금지 — 키 없는 가짜 인식·해시 임베딩·engine 쿼리. (#2812)

앞쪽은 설정·팩토리만 보는 순수 테스트(DB 불필요), 뒤쪽은 `/diet/analyze` 를 실제로
부르는 DB 테스트다(로컬 skip, CI 실행).
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import select

from app.core.config import Settings

_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF fake-image-bytes"


def _prod(**kw) -> Settings:
    base = dict(
        _env_file=None,
        env="prod",
        jwt_secret="a-strong-random-secret-value-for-prod-tests",
        cors_allow_origins="https://app.oncare.com",
        seed_demo_data=False,
        auto_create_tables=False,
        recognizer="gemini",
        embedder="gemini",
        gemini_api_key="test-gemini-key",
    )
    base.update(kw)
    return Settings(**base)


# ---------- 운영 설정 검증(기동 거부) ----------


def test_prod_starts_with_real_ai_keys():
    s = _prod()
    assert s.missing_ai_config() == []


def test_prod_refuses_to_start_without_the_gemini_key():
    """키가 비면 사진과 무관한 고정 식단이 저장된다 — 기동부터 막는다."""
    with pytest.raises(ValidationError, match="GEMINI_API_KEY"):
        _prod(gemini_api_key="")


@pytest.mark.parametrize(
    ("overrides", "needle"),
    [
        ({"recognizer": "stub"}, "RECOGNIZER=stub"),
        ({"recognizer": "yolo"}, "RECOGNIZER=yolo"),
        ({"embedder": "hash"}, "EMBEDDER=hash"),
        ({"embedder": "openai", "openai_api_key": ""}, "OPENAI_API_KEY"),
        ({"embedder": "litellm"}, "LITELLM_EMBED_MODEL"),
        ({"recognizer": "claude"}, "LITELLM_API_KEY"),
    ],
)
def test_prod_refuses_dev_only_or_unconfigured_ai(overrides, needle):
    with pytest.raises(ValidationError, match=needle):
        _prod(**overrides)


def test_prod_accepts_litellm_recognizer_and_openai_embedder_when_configured():
    s = _prod(
        gemini_api_key="",
        recognizer="claude",
        litellm_base_url="https://proxy.example",
        litellm_api_key="vk",
        embedder="openai",
        openai_api_key="sk-test",
    )
    assert s.missing_ai_config() == []


def test_dev_still_runs_without_any_ai_key():
    """개발·테스트는 지금처럼 키 없이 뜬다(스텁·해시 폴백)."""
    s = Settings(_env_file=None, gemini_api_key="", recognizer="gemini", embedder="gemini")
    assert s.is_prod is False
    # 문제를 알고는 있지만 기동은 막지 않는다.
    assert s.missing_ai_config()


# ---------- 팩토리: 운영에서는 폴백하지 않는다 ----------


@pytest.fixture
def prod_settings(monkeypatch):
    """캐시된 설정을 운영처럼 보이게 한다(검증은 다시 돌지 않는다 — 팩토리만 본다)."""
    from app.core.config import get_settings

    s = get_settings()
    monkeypatch.setattr(s, "env", "prod")
    return s


def test_recognizer_factory_refuses_stub_fallback_in_prod(monkeypatch, prod_settings):
    from app.services.recognizer import factory

    monkeypatch.setattr(prod_settings, "recognizer", "gemini")
    monkeypatch.setattr(prod_settings, "gemini_api_key", "")
    with pytest.raises(factory.RecognizerUnavailable):
        factory.get_recognizer()
    with pytest.raises(factory.RecognizerUnavailable):
        factory.get_recognizer("stub")


def test_recognizer_factory_falls_back_to_stub_in_dev(monkeypatch):
    from app.core.config import get_settings
    from app.services.recognizer import factory

    s = get_settings()
    monkeypatch.setattr(s, "env", "dev")
    monkeypatch.setattr(s, "gemini_api_key", "")
    assert factory.get_recognizer("gemini").name == factory.STUB_ENGINE


def test_embedder_factory_refuses_hash_fallback_in_prod(monkeypatch, prod_settings):
    from app.services.embedder import factory

    monkeypatch.setattr(prod_settings, "gemini_api_key", "")
    with pytest.raises(factory.EmbedderUnavailable):
        factory.get_embedder("gemini")
    with pytest.raises(factory.EmbedderUnavailable):
        factory.get_embedder("hash")


def test_embedder_factory_falls_back_to_hash_in_dev(monkeypatch):
    from app.core.config import get_settings
    from app.services.embedder import factory
    from app.services.embedder.hash_embedder import HashEmbedder

    s = get_settings()
    monkeypatch.setattr(s, "env", "dev")
    monkeypatch.setattr(s, "gemini_api_key", "")
    assert isinstance(factory.get_embedder("gemini"), HashEmbedder)


# ---------- /diet/analyze (DB) ----------


def _register(client) -> tuple[str, dict[str, str]]:
    email = f"aifb-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    user_id = client.get("/v1/users/me", headers=headers).json()["id"]
    return user_id, headers


def _analyze(client, headers, *, query: str = ""):
    return client.post(
        f"/v1/diet/analyze{query}",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers=headers,
    )


def _entries(db_session, user_id: str):
    from app.models.models import DietEntry

    db_session.expire_all()
    return list(db_session.scalars(select(DietEntry).where(DietEntry.user_id == user_id)))


def _balance(client, headers) -> int:
    return client.get("/v1/users/me/health", headers=headers).json()["activity_points"]


def test_prod_without_key_answers_503_and_saves_nothing(client, db_session, monkeypatch):
    """운영에서 키가 빠지면 고정 식단 대신 분석 불가 — 끼니·포인트·사진 없음."""
    from app.core.config import get_settings

    user_id, h = _register(client)
    s = get_settings()
    monkeypatch.setattr(s, "env", "prod")
    monkeypatch.setattr(s, "recognizer", "gemini")
    monkeypatch.setattr(s, "gemini_api_key", "")

    r = _analyze(client, h)

    assert r.status_code == 503, r.text
    assert r.json()["detail"]["code"] == "analysis_unavailable"
    assert r.json()["detail"]["message"]
    monkeypatch.setattr(s, "env", "dev")
    assert _entries(db_session, user_id) == []
    assert _balance(client, h) == 0


def test_prod_ignores_the_engine_query_for_members(client, monkeypatch):
    """운영에서 회원이 `?engine=stub` 을 붙여도 설정된 인식기로 분석한다."""
    from app.core.config import get_settings

    _, h = _register(client)
    monkeypatch.setattr(get_settings(), "env", "prod")

    r = _analyze(client, h, query="?engine=stub")

    assert r.status_code == 200, r.text
    assert r.json()["analysis"]["engine"] != "stub"
    assert r.json()["points"]["awarded"] == 50


def test_prod_ignores_an_unknown_engine_instead_of_failing(client, monkeypatch):
    """준비되지 않은 엔진 이름으로 400·501 을 유발하지 못한다."""
    from app.core.config import get_settings

    _, h = _register(client)
    monkeypatch.setattr(get_settings(), "env", "prod")

    assert _analyze(client, h, query="?engine=yolo").status_code == 200


def test_dev_still_honours_the_engine_query(client):
    """개발에서는 비교실험용으로 그대로 쓴다 — 알 수 없는 엔진은 400."""
    _, h = _register(client)
    assert _analyze(client, h, query="?engine=nope").status_code == 400


def test_stub_result_is_saved_in_dev_but_earns_no_points(client, db_session, monkeypatch):
    """개발용 스텁 결과는 끼니로는 남지만 포인트는 없다 — 사진을 보지 않은 결과다."""
    from app.core.config import get_settings

    user_id, h = _register(client)
    monkeypatch.setattr(get_settings(), "recognizer", "stub")

    r = _analyze(client, h)

    assert r.status_code == 200, r.text
    assert r.json()["analysis"]["engine"] == "stub"
    assert r.json()["points"] == {"awarded": 0, "balance": 0}
    rows = _entries(db_session, user_id)
    assert [row.engine for row in rows] == ["stub"]
    assert _balance(client, h) == 0


def test_real_recognizer_result_still_earns_points(client):
    """실제 인식기(테스트 인식기) 결과는 지금처럼 적립된다."""
    _, h = _register(client)
    r = _analyze(client, h)
    assert r.status_code == 200, r.text
    assert r.json()["points"]["awarded"] == 50
