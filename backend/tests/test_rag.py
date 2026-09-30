"""RAG 코칭 연동.

- 해시 임베더(결정론·유사도)는 순수(로컬 실행).
- 공공/개인 문서 적재·검색·격리, /ai-coach/feedback 은 DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations

import math
from uuid import uuid4


# ---------- 순수: 오프라인 해시 임베더 ----------

def _cos(a, b):
    return sum(x * y for x, y in zip(a, b))


def test_hash_embedder_deterministic_normalized():
    from app.services.embedder.hash_embedder import HashEmbedder

    e = HashEmbedder()
    v1 = e.embed_one("나트륨 줄이기 저염 식단")
    v2 = e.embed_one("나트륨 줄이기 저염 식단")
    assert len(v1) == e.dim
    assert v1 == v2  # 결정론적(프로세스 무관)
    assert abs(math.sqrt(sum(x * x for x in v1)) - 1.0) < 1e-6  # L2 정규화


def test_hash_embedder_similarity_orders_related_higher():
    from app.services.embedder.hash_embedder import HashEmbedder

    e = HashEmbedder()
    base = e.embed_one("나트륨 관리")
    related = _cos(base, e.embed_one("나트륨 줄이기"))
    unrelated = _cos(base, e.embed_one("주말 영화 관람"))
    assert related > unrelated


def test_litellm_embedder_falls_back_to_hash_without_embed_model(monkeypatch):
    """LiteLLM 프록시에 임베딩 모델이 없으면 해시 임베더로 폴백한다.

    그러지 않으면 LiteLLMEmbedder 가 기동 중 RuntimeError 를 던져 공공/개인 문서가
    하나도 적재되지 않고, RAG 검색이 비어 코치가 규칙 기반 폴백에 갇힌다(#155).
    """
    from app.core.config import get_settings
    from app.services.embedder.factory import get_embedder
    from app.services.embedder.hash_embedder import HashEmbedder

    # 로컬 .env / CI 환경변수에 값이 있어도 결정적이도록, LiteLLM 설정을 직접 비운다.
    settings = get_settings()
    monkeypatch.setattr(settings, "litellm_base_url", "")
    monkeypatch.setattr(settings, "litellm_api_key", "")
    monkeypatch.setattr(settings, "litellm_embed_model", "")

    assert isinstance(get_embedder("litellm"), HashEmbedder)


# ---------- DB(CI): 적재·검색·격리 ----------

def test_public_guidelines_seeded_and_retrieved(client, db_session):
    from sqlalchemy import func, select

    from app.models.models import CoachDocument
    from app.services.coach.rag import retrieve

    n_public = db_session.scalar(
        select(func.count()).select_from(CoachDocument).where(CoachDocument.user_id.is_(None))
    )
    assert n_public and n_public > 0  # 공공 가이드라인이 시드됨

    hits = retrieve(db_session, "나트륨을 줄이려면 어떻게 하나요", user_id="user-7d4e9a2c5f18", domain="diet")
    assert hits["public"]  # 공공 문서가 검색됨


def test_personal_docs_are_isolated_between_users(client, db_session):
    from app.services.coach.rag import ingest_personal_text, retrieve

    a = client.post(
        "/v1/auth/register",
        json={"email": f"raga-{uuid4().hex[:8]}@oncare.com", "password": "test-pw-1234", "name": "A"},
    ).json()["id"]
    b = client.post(
        "/v1/auth/register",
        json={"email": f"ragb-{uuid4().hex[:8]}@oncare.com", "password": "test-pw-1234", "name": "B"},
    ).json()["id"]

    ingest_personal_text(db_session, a, "나는 김치찌개를 자주 먹어 나트륨이 높다", domain="diet", source="diet")
    ingest_personal_text(db_session, b, "B사용자 비밀 삼겹살 기록", domain="diet", source="diet")

    hits = retrieve(db_session, "나트륨 관리", user_id=a, domain="diet")
    personal_text = " ".join(d.content for d in hits["personal"])
    assert hits["personal"]                    # A의 개인 문서가 검색됨
    assert "비밀 삼겹살" not in personal_text   # B의 개인 문서는 절대 섞이지 않음


def test_ai_coach_feedback_shape(client):
    r = client.get("/v1/ai-coach/feedback")
    assert r.status_code == 200
    body = r.json()
    assert body["greeting"]
    # 데모 코칭 시트와 같은 식단·운동 두 장이다(#2706).
    assert [s["tag"] for s in body["suggestions"]] == ["diet", "exercise"]
    assert all("tag" in s and "title" in s and "body" in s for s in body["suggestions"])
