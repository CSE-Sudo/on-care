"""운영 카카오 장소 검색 키 누락 기동 점검(#3161) — DB 불필요.

키가 비면 장소 API 는 DB 장소만 읽고, 데모 시드가 꺼진 서버는 데모 장소를 빼므로
헬스장 찾기가 늘 빈 목록이다(#2914). 기동은 막지 않되 운영은 ERROR, 스테이징은 WARN 으로
남기고 개발은 조용한지 본다.
"""
from __future__ import annotations

import logging

import pytest

from app.core import startup_checks
from app.core.config import Settings

KEY = "test-kakao-rest-key"


def _prod(**kw) -> Settings:
    base = dict(
        _env_file=None,
        env="prod",
        jwt_secret="a-strong-random-secret-value-for-prod-tests",
        cors_allow_origins="https://app.oncare.com",
        seed_demo_data=False,
        auto_create_tables=False,
        # conftest 가 EMBEDDER=hash 를 환경변수로 심으므로 운영 값을 명시한다.
        gemini_api_key="test-gemini-key",
        recognizer="gemini",
        embedder="gemini",
        attachment_s3_bucket="oncare-prod",
        google_client_ids="test-google-client.apps.googleusercontent.com",
        kakao_app_id="1234567",
        apple_client_ids="com.example.oncare",
        # 운영 메일 필수 가드(#3131)와 함께 병합돼도 이 파일이 깨지지 않게 둔다.
        smtp_host="smtp.example.com",
        mail_from="On-Care <no-reply@example.com>",
        kakao_rest_api_key=KEY,
    )
    base.update(kw)
    return Settings(**base)


def _other(env: str, **kw) -> Settings:
    return Settings(_env_file=None, env=env, **kw)


def _places(messages: list[str]) -> list[str]:
    return [m for m in messages if "장소 검색" in m]


def _records(caplog, level: int) -> list[str]:
    return [
        r.getMessage()
        for r in caplog.records
        if r.name == "app.startup" and r.levelno == level and "장소 검색" in r.getMessage()
    ]


# ---- 판정 ----


@pytest.mark.parametrize(
    ("kw", "needle"),
    [
        ({"kakao_rest_api_key": ""}, "KAKAO_REST_API_KEY"),
        ({"kakao_rest_api_key": "   "}, "KAKAO_REST_API_KEY"),
        ({"places_provider": "seed"}, "PLACES_PROVIDER=seed"),
        ({"kakao_rest_api_key": "", "places_provider": "kakao"}, "KAKAO_REST_API_KEY"),
    ],
    ids=["empty", "blank", "forced-seed", "forced-kakao-without-key"],
)
def test_problem_is_reported(kw, needle):
    problem = startup_checks.places_search_problem(_prod(**kw))
    assert problem is not None
    assert needle in problem


@pytest.mark.parametrize("provider", ["auto", "kakao"])
def test_no_problem_with_a_key(provider):
    assert startup_checks.places_search_problem(_prod(places_provider=provider)) is None


# ---- 운영: ERROR, 기동은 계속 ----


def test_prod_without_key_logs_an_error_and_keeps_starting(caplog):
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        messages = startup_checks.check(_prod(kakao_rest_api_key=""))  # 예외 없음

    places = _places(messages)
    assert len(places) == 1
    message = places[0]
    assert "헬스장 찾기가 항상 빈 목록" in message
    assert "KAKAO_REST_API_KEY" in message
    assert _records(caplog, logging.ERROR) == [f"[startup] {message}"]
    assert _records(caplog, logging.WARNING) == []


def test_prod_alias_production_is_treated_as_prod(caplog):
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        startup_checks.check(_prod(env="production", kakao_rest_api_key=""))
    assert len(_records(caplog, logging.ERROR)) == 1


def test_prod_forced_seed_provider_logs_an_error(caplog):
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        messages = startup_checks.check(_prod(places_provider="seed"))
    assert any("PLACES_PROVIDER=seed" in m for m in _places(messages))
    assert len(_records(caplog, logging.ERROR)) == 1


def test_prod_with_key_says_nothing(caplog):
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        messages = startup_checks.check(_prod())
    assert _places(messages) == []
    assert _records(caplog, logging.ERROR) == []
    assert _records(caplog, logging.WARNING) == []


def test_prod_message_does_not_leak_the_key(caplog):
    """키가 있을 때는 아무것도 남기지 않으므로 값이 로그에 실릴 일이 없다."""
    with caplog.at_level(logging.DEBUG, logger="app.startup"):
        startup_checks.check(_prod())
    assert KEY not in caplog.text


# ---- 스테이징: WARN ----


def test_staging_without_key_warns(caplog):
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        messages = startup_checks.check(_other("staging"))
    places = _places(messages)
    assert len(places) == 1
    assert "스테이징" in places[0]
    assert len(_records(caplog, logging.WARNING)) == 1
    assert _records(caplog, logging.ERROR) == []


def test_staging_with_key_says_nothing():
    assert _places(startup_checks.check(_other("staging", kakao_rest_api_key=KEY))) == []


# ---- 개발: 조용 ----


@pytest.mark.parametrize("kw", [{}, {"places_provider": "seed"}])
def test_dev_without_key_is_quiet(caplog, kw):
    """개발은 키 없이 시드 장소로 도는 것이 정상이다."""
    with caplog.at_level(logging.WARNING, logger="app.startup"):
        messages = startup_checks.check(_other("dev", **kw))
    assert _places(messages) == []
    assert _records(caplog, logging.ERROR) == []
