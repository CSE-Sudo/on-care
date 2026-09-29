"""운동 세션의 개인 RAG 적재 (#586).

운동 코치는 `domain="exercise"` 로 개인 문서를 검색하는데, 지금까지 그 도메인에
개인 문서가 하나도 없어 프롬프트가 운동 조언을 지시해도 근거가 공공 가이드라인뿐이었다.
"""
from __future__ import annotations

import pytest

from app.services.coach import personal_ingest
from tests.exercise_helpers import post_exercise


@pytest.fixture
def _captured(monkeypatch):
    """`_safe` 를 잡아 적재 인자를 그대로 본다(임베딩 호출 없이)."""
    calls: list[dict] = []
    monkeypatch.setattr(
        personal_ingest,
        "_safe",
        # **kwargs 로 받는다 — _safe 에 옵션이 하나 늘 때마다 이 페이크가
        # TypeError 로 깨지는 일을 반복하지 않으려고.
        lambda db, user_id, text, *, domain, source, **opts: calls.append(
            {
                "user_id": user_id, "text": text, "domain": domain,
                "source": source, **opts,
            }
        ),
    )
    return calls


# ---- 문서 형태 (순수) ----

def test_exercise_document_is_written_in_korean(_captured):
    """저장 코드값(cardio/light)을 그대로 넣으면 한국어 질의와 임베딩이 겉돈다."""
    personal_ingest.record_exercise(
        None, "user-1", date="2026-08-11", exercise_type="cardio", minutes=30,
        calories=250, intensity="light",
    )

    text = _captured[0]["text"]
    assert "2026-08-11" in text
    assert "유산소" in text and "cardio" not in text
    assert "30분" in text
    assert "250kcal" in text
    assert "강도 낮음" in text and "light" not in text


def test_exercise_is_ingested_into_the_exercise_domain(_captured):
    personal_ingest.record_exercise(
        None, "user-1", date="2026-08-11", exercise_type="strength", minutes=40,
        calories=300, intensity="high",
    )

    assert _captured[0]["domain"] == "exercise"
    assert _captured[0]["source"] == "exercise"


@pytest.mark.parametrize(
    ("type_", "expected"),
    [
        ("cardio", "유산소"),
        ("strength", "근력"),
        ("stretching", "스트레칭"),
        ("other", "기타"),
        # 옛 값도 표준 라벨로 접힌다 (#996, #1276).
        ("walking", "유산소"),
        ("yoga", "스트레칭"),
        ("flexibility", "스트레칭"),
    ],
)
def test_every_allowed_exercise_type_has_a_label(_captured, type_, expected):
    """라우터의 _ALLOWED_TYPES 전부를 덮는다 — 빠진 값은 코드가 그대로 노출된다."""
    personal_ingest.record_exercise(
        None, "u", date="2026-08-11", exercise_type=type_, minutes=10, calories=50,
        intensity="moderate",
    )
    assert expected in _captured[-1]["text"]


def test_an_unknown_code_degrades_to_itself_instead_of_crashing(_captured):
    personal_ingest.record_exercise(
        None, "u", date="2026-08-11", exercise_type="crossfit", minutes=10,
        calories=50,
        intensity="extreme",
    )

    text = _captured[0]["text"]
    assert "crossfit" in text and "extreme" in text


# ---- 실제 경로 (DB) ----

def _member_token(client) -> str:
    r = client.post(
        "/v1/auth/login",
        data={"username": "minsu@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def test_logging_a_session_ingests_it(client, _captured):
    token = _member_token(client)

    r = post_exercise(
        client,
        headers={"Authorization": f"Bearer {token}"},
        json={"type": "walking", "minutes": 25, "calories": 90, "intensity": "light"},
    )

    assert r.status_code == 201, r.text
    assert len(_captured) == 1
    assert _captured[0]["domain"] == "exercise"
    # walking 은 유산소로 접혀 저장·적재된다 (#996).
    assert "유산소" in _captured[0]["text"] and "25분" in _captured[0]["text"]


def test_ingest_failure_never_breaks_the_session_save(client, monkeypatch):
    """적재는 보조 인덱싱이다 — 실패해도 201 이어야 하고 기록도 남아야 한다."""
    def _boom(*args, **kwargs):
        raise RuntimeError("embedder down")

    monkeypatch.setattr(personal_ingest, "ingest_personal_text", _boom)
    token = _member_token(client)

    r = post_exercise(
        client,
        headers={"Authorization": f"Bearer {token}"},
        json={"type": "yoga", "minutes": 20, "calories": 60, "intensity": "moderate"},
    )

    assert r.status_code == 201, r.text
    week = client.get(
        "/v1/exercise/weeks/current",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert any(s["id"] == r.json()["id"] for s in week.json()["sessions"])


def test_ingest_is_off_when_rag_auto_ingest_is_disabled(client, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "rag_auto_ingest", False)
    calls: list[object] = []
    monkeypatch.setattr(
        personal_ingest, "ingest_personal_text",
        lambda *a, **k: calls.append(a),
    )
    token = _member_token(client)

    r = post_exercise(
        client,
        headers={"Authorization": f"Bearer {token}"},
        json={"type": "cardio", "minutes": 15, "calories": 100, "intensity": "high"},
    )

    assert r.status_code == 201, r.text
    assert calls == []
