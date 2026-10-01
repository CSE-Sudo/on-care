"""식단 사진 분석 호출 한도·비용 상한. (#2827)

- rate limiter 의 사용자 id 버킷은 순수 단위 테스트(DB 불필요).
- `/diet/analyze` 의 분당 한도·하루 상한·멱등 재전송·KST 자정·바이트 검사는 DB
  테스트(로컬 skip, CI 실행). 인식기는 라우터의 `get_recognizer` 를 바꿔 끼워 호출
  횟수를 센다 — "외부 모델이 호출되지 않는다" 를 직접 확인한다.
"""
from __future__ import annotations

from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.schemas.diet import DietAnalysis, RecognizedFood

_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF fake-image-bytes"
_PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16
_WEBP = b"RIFF\x00\x00\x00\x00WEBPVP8 " + b"\x00" * 8


# ---------- rate limiter: 사용자 id 버킷 ----------


@pytest.fixture
def limits(monkeypatch):
    from app.core.config import get_settings

    s = get_settings()
    monkeypatch.setattr(s, "rate_limit_enabled", True)
    return s


def test_check_user_counts_each_member_separately(limits):
    from app.core import rate_limit

    for _ in range(2):
        rate_limit.check_user("diet-analyze-unit", "user-a", 2)
    with pytest.raises(HTTPException) as exc:
        rate_limit.check_user("diet-analyze-unit", "user-a", 2)
    assert exc.value.status_code == 429
    assert exc.value.headers["Retry-After"] == "60"
    # 같은 Wi-Fi 의 다른 회원은 영향을 받지 않는다.
    rate_limit.check_user("diet-analyze-unit", "user-b", 2)


def test_check_user_carries_a_coded_detail(limits):
    from app.core import rate_limit

    detail = {"code": "rate_limited", "message": "잠시 후"}
    rate_limit.check_user("diet-analyze-unit", "user-c", 1, detail=detail)
    with pytest.raises(HTTPException) as exc:
        rate_limit.check_user("diet-analyze-unit", "user-c", 1, detail=detail)
    assert exc.value.detail == detail


def test_check_user_does_not_share_the_ip_bucket(limits):
    """사용자 키는 IP 키와 다른 이름공간이다 — 같은 문자열이어도 섞이지 않는다."""
    from app.core import rate_limit

    rate_limit.limiter.check("diet-analyze-unit:user-d", 1, 60.0)
    rate_limit.check_user("diet-analyze-unit", "user-d", 1)


@pytest.mark.parametrize("per_minute", [0, -1])
def test_check_user_is_off_for_zero_or_negative(limits, per_minute):
    from app.core import rate_limit

    for _ in range(50):
        rate_limit.check_user("diet-analyze-unit", "user-e", per_minute)


def test_check_user_is_off_when_rate_limiting_is_disabled(monkeypatch, limits):
    from app.core import rate_limit

    monkeypatch.setattr(limits, "rate_limit_enabled", False)
    for _ in range(50):
        rate_limit.check_user("diet-analyze-unit", "user-f", 1)


def test_daily_limit_follows_settings(monkeypatch, limits):
    from app.services import diet_analysis_quota_service as quota

    monkeypatch.setattr(limits, "diet_analyze_per_day", 7)
    assert quota.daily_limit() == 7
    monkeypatch.setattr(limits, "diet_analyze_per_day", -3)
    assert quota.daily_limit() == 0
    monkeypatch.setattr(limits, "diet_analyze_per_day", 7)
    monkeypatch.setattr(limits, "rate_limit_enabled", False)
    assert quota.daily_limit() == 0


def test_defaults_bound_a_members_daily_cost():
    from app.core.config import Settings

    s = Settings(_env_file=None, diet_analyze_per_minute=10, diet_analyze_per_day=20)
    assert s.diet_analyze_per_minute == 10
    assert s.diet_analyze_per_day == 20
    fields = Settings.model_fields
    assert fields["diet_analyze_per_minute"].default == 10
    assert fields["diet_analyze_per_day"].default == 20


# ---------- /diet/analyze (DB) ----------


class _CountingRecognizer:
    name = "counting-test"

    def __init__(self, *, foods=None, error: Exception | None = None):
        self.calls = 0
        self.media_types: list[str] = []
        self._foods = (
            foods
            if foods is not None
            else [RecognizedFood(name="바나나", amount_g=120, calories=105)]
        )
        self._error = error

    async def recognize(self, image_bytes: bytes, media_type: str) -> DietAnalysis:
        self.calls += 1
        self.media_types.append(media_type)
        if self._error is not None:
            raise self._error
        return DietAnalysis(engine=self.name, foods=list(self._foods))


@pytest.fixture
def recognizer(monkeypatch):
    from app.api.v1 import diet as diet_api

    def _install(**kw) -> _CountingRecognizer:
        rec = _CountingRecognizer(**kw)
        monkeypatch.setattr(diet_api, "get_recognizer", lambda engine=None: rec)
        return rec

    return _install


@pytest.fixture
def kst_day(monkeypatch):
    """하루 상한이 읽는 KST 날짜를 고정·전환한다(서버 로컬 시계와 무관)."""
    from app.services import diet_analysis_quota_service as quota

    state = {"day": "2026-10-01"}
    monkeypatch.setattr(quota, "clock", SimpleNamespace(today_iso=lambda: state["day"]))
    return state


def _register(client) -> tuple[str, dict[str, str]]:
    email = f"limit-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def _analyze(client, headers, *, body: bytes = _JPEG, mime: str = "image/jpeg", key=None):
    data = {"meal_type": "lunch"}
    if key:
        data["idempotency_key"] = key
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", body, mime)},
        data=data,
        headers=headers,
    )


def _used(db_session, user_id: str, day: str) -> int:
    from sqlalchemy import func, select

    from app.models.models import DietAnalysisUsage

    db_session.expire_all()
    return int(
        db_session.scalar(
            select(func.count())
            .select_from(DietAnalysisUsage)
            .where(DietAnalysisUsage.user_id == user_id, DietAnalysisUsage.kst_date == day)
        )
        or 0
    )


def test_per_minute_limit_answers_429_before_calling_the_model(
    client, limits, monkeypatch, recognizer, kst_day
):
    monkeypatch.setattr(limits, "diet_analyze_per_minute", 2)
    rec = recognizer()
    _, h = _register(client)

    assert _analyze(client, h).status_code == 200
    assert _analyze(client, h).status_code == 200
    r = _analyze(client, h)

    assert r.status_code == 429, r.text
    assert r.json()["detail"]["code"] == "rate_limited"
    assert r.headers.get("Retry-After") == "60"
    assert rec.calls == 2


def test_per_minute_limit_is_per_member_not_per_ip(
    client, limits, monkeypatch, recognizer, kst_day
):
    """TestClient 는 모든 요청이 같은 IP 다 — 한 회원이 막혀도 다른 회원은 된다."""
    monkeypatch.setattr(limits, "diet_analyze_per_minute", 1)
    recognizer()
    _, a = _register(client)
    _, b = _register(client)

    assert _analyze(client, a).status_code == 200
    assert _analyze(client, a).status_code == 429
    assert _analyze(client, b).status_code == 200


def test_daily_limit_answers_429_daily_limit_without_calling_the_model(
    client, db_session, limits, monkeypatch, recognizer, kst_day
):
    monkeypatch.setattr(limits, "diet_analyze_per_day", 2)
    rec = recognizer()
    user_id, h = _register(client)

    assert _analyze(client, h).status_code == 200
    assert _analyze(client, h).status_code == 200
    r = _analyze(client, h)

    assert r.status_code == 429, r.text
    assert r.json()["detail"]["code"] == "daily_limit"
    assert r.json()["detail"]["message"]
    assert rec.calls == 2
    assert _used(db_session, user_id, kst_day["day"]) == 2


def test_daily_limit_reopens_after_kst_midnight(
    client, db_session, limits, monkeypatch, recognizer, kst_day
):
    monkeypatch.setattr(limits, "diet_analyze_per_day", 1)
    recognizer()
    user_id, h = _register(client)

    assert _analyze(client, h).status_code == 200
    assert _analyze(client, h).status_code == 429

    kst_day["day"] = "2026-10-02"
    assert _analyze(client, h).status_code == 200
    assert _used(db_session, user_id, "2026-10-01") == 1
    assert _used(db_session, user_id, "2026-10-02") == 1


def test_idempotent_replay_does_not_spend_the_quota(
    client, db_session, limits, monkeypatch, recognizer, kst_day
):
    monkeypatch.setattr(limits, "diet_analyze_per_day", 1)
    monkeypatch.setattr(limits, "diet_analyze_per_minute", 1)
    rec = recognizer()
    user_id, h = _register(client)
    key = f"idem-{uuid4().hex}"

    first = _analyze(client, h, key=key)
    replay = _analyze(client, h, key=key)

    assert first.status_code == 200
    assert replay.status_code == 200, replay.text
    assert replay.json()["entry_id"] == first.json()["entry_id"]
    assert rec.calls == 1
    assert _used(db_session, user_id, kst_day["day"]) == 1
    # 새 키는 새 호출이다 — 이제 막힌다.
    assert _analyze(client, h, key=f"idem-{uuid4().hex}").status_code == 429


def test_model_failure_gives_the_quota_back(
    client, db_session, limits, monkeypatch, recognizer, kst_day
):
    """공급자 장애로 회원의 하루 몫이 깎이지 않는다."""
    monkeypatch.setattr(limits, "diet_analyze_per_day", 1)
    user_id, h = _register(client)

    recognizer(error=RuntimeError("provider down"))
    assert _analyze(client, h).status_code == 502
    assert _used(db_session, user_id, kst_day["day"]) == 0

    recognizer()
    assert _analyze(client, h).status_code == 200


def test_unimplemented_engine_gives_the_quota_back(
    client, db_session, limits, monkeypatch, recognizer, kst_day
):
    monkeypatch.setattr(limits, "diet_analyze_per_day", 1)
    user_id, h = _register(client)

    recognizer(error=NotImplementedError("not yet"))
    assert _analyze(client, h).status_code == 501
    assert _used(db_session, user_id, kst_day["day"]) == 0


def test_a_photo_without_food_still_counts(
    client, db_session, limits, monkeypatch, recognizer, kst_day
):
    """음식을 못 찾은 사진도 모델 비용은 나갔다(#2848 과 함께)."""
    monkeypatch.setattr(limits, "diet_analyze_per_day", 1)
    user_id, h = _register(client)

    recognizer(foods=[])
    assert _analyze(client, h).status_code == 422
    assert _used(db_session, user_id, kst_day["day"]) == 1

    recognizer()
    assert _analyze(client, h).status_code == 429


@pytest.mark.parametrize(
    ("body", "mime"),
    [
        (b"hello, not an image", "image/jpeg"),
        (b"%PDF-1.7 fake", "image/png"),
        (b"GIF89a" + b"\x00" * 16, "image/webp"),
    ],
)
def test_non_image_bytes_are_refused_before_the_model_whatever_the_header(
    client, db_session, limits, recognizer, kst_day, body, mime
):
    rec = recognizer()
    user_id, h = _register(client)

    r = _analyze(client, h, body=body, mime=mime)

    assert r.status_code == 415, r.text
    assert rec.calls == 0
    assert _used(db_session, user_id, kst_day["day"]) == 0


@pytest.mark.parametrize(
    ("body", "header", "sniffed"),
    [
        (_JPEG, "application/octet-stream", "image/jpeg"),
        (_PNG, "image/jpeg", "image/png"),
        (_WEBP, "image/png", "image/webp"),
    ],
)
def test_the_model_receives_the_sniffed_media_type(
    client, recognizer, kst_day, body, header, sniffed
):
    """헤더는 참고만 한다 — 실제 바이트 형식을 모델에 넘긴다."""
    rec = recognizer()
    _, h = _register(client)

    r = _analyze(client, h, body=body, mime=header)

    assert r.status_code == 200, r.text
    assert rec.media_types == [sniffed]


def test_no_usage_rows_when_rate_limiting_is_disabled(
    client, db_session, limits, monkeypatch, recognizer, kst_day
):
    monkeypatch.setattr(limits, "rate_limit_enabled", False)
    monkeypatch.setattr(limits, "diet_analyze_per_day", 1)
    recognizer()
    user_id, h = _register(client)

    assert _analyze(client, h).status_code == 200
    assert _analyze(client, h).status_code == 200
    assert _used(db_session, user_id, kst_day["day"]) == 0
