"""AI 코치 답변의 개인화(#274 수용 기준: "개인 최근 식단이 답변 근거로 반영").

검증하는 사슬은 이렇다:

    POST /diet/analyze  →  diet_entries 저장  →  record_diet 로 개인 RAG 문서 적재
                        →  retrieve 가 그 문서를 찾음  →  채팅 프롬프트에 실림

마지막 단계를 **모델의 말투가 아니라 프롬프트 내용**으로 검증한다. "답변에 스텁이
낸 음식 이름이 나오는지"로 확인하면 LLM 이 그 단어를 안 쓰기만 해도 깨지는, 실패를
신뢰할 수 없는 테스트가 된다. 프롬프트에 근거가 실렸는지는 결정론적이다.

임베딩은 키가 없으면 해시 임베더로 폴백하므로(embedder/factory) CI 에서도 돈다.
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from app.models.models import AiConversation, AiMessage, CoachDocument, DietEntry, User
from app.services.coach.llm_base import LLMResult

from tests.image_fixtures import JPEG as _JPEG  # 진짜 JPEG — 분석 전 정리가 픽셀을 읽는다(#3041)


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


class _RecordingLLM:
    """프롬프트를 붙잡아 두는 가짜 LLM. 답변 내용은 검증 대상이 아니다."""

    name = "recording"

    def __init__(self) -> None:
        self.system_prompt = ""
        self.user_prompt = ""

    def generate(self, system_prompt: str, user_prompt: str, **kwargs) -> LLMResult:
        self.system_prompt = system_prompt
        self.user_prompt = user_prompt
        return LLMResult(text="네, 참고해서 답변드릴게요.", model=self.name)


@pytest.fixture
def recording_llm(monkeypatch) -> _RecordingLLM:
    llm = _RecordingLLM()
    monkeypatch.setattr("app.services.coach.chat.get_coach_llm", lambda *a, **k: llm)
    return llm


@pytest.fixture
def member(client, db_session):
    from app.core.security import hash_password

    email = f"coach-personal-{uuid.uuid4().hex[:8]}@example.com"
    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=email, name="개인화 테스트",
        hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user)
    db_session.commit()

    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    yield user, token

    convo_ids = [
        c.id
        for c in db_session.scalars(
            __import__("sqlalchemy").select(AiConversation).where(
                AiConversation.user_id == user.id
            )
        )
    ]
    if convo_ids:
        db_session.execute(
            delete(AiMessage).where(AiMessage.conversation_id.in_(convo_ids))
        )
    db_session.execute(delete(AiConversation).where(AiConversation.user_id == user.id))
    db_session.execute(delete(CoachDocument).where(CoachDocument.user_id == user.id))
    db_session.execute(delete(DietEntry).where(DietEntry.user_id == user.id))
    db_session.execute(delete(User).where(User.id == user.id))
    db_session.commit()


def test_saved_diet_becomes_a_personal_rag_document(client, db_session, member):
    """식단을 기록하면 코치가 검색할 수 있는 개인 문서가 생긴다."""
    import sqlalchemy as sa

    user, token = member
    res = client.post(
        "/v1/diet/analyze",
        files={"image": ("meal.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers=_h(token),
    )
    assert res.status_code == 200, res.text

    docs = db_session.scalars(
        sa.select(CoachDocument).where(CoachDocument.user_id == user.id)
    ).all()
    assert docs, "식단 저장이 개인 RAG 문서를 만들지 않았다"
    joined = " ".join(d.content for d in docs)
    assert "요거트 아이스크림" in joined  # 스텁 인식기가 낸 음식
    assert "나트륨" in joined


def test_recent_diet_is_grounded_into_the_chat_prompt(
    client, db_session, member, recording_llm
):
    """#274 수용 기준: 개인 최근 식단이 답변 근거로 반영된다.

    모델이 뭐라고 답했는지가 아니라, 개인 기록이 프롬프트의 근거로 들어갔는지를 본다.
    """
    _, token = member
    client.post(
        "/v1/diet/analyze",
        files={"image": ("meal.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers=_h(token),
    )

    res = client.post(
        "/v1/ai-coach/chat",
        json={"message": "오늘 먹은 걸 보고 저녁을 추천해 주세요"},
        headers=_h(token),
    )
    assert res.status_code == 200

    prompt = recording_llm.user_prompt
    assert "[내 건강 기록]" in prompt
    assert "요거트 아이스크림" in prompt, "개인 식단 기록이 프롬프트 근거로 실리지 않았다"


def test_other_users_diet_never_reaches_my_prompt(
    client, db_session, member, recording_llm
):
    """개인 기록이 남의 프롬프트에 섞이면 개인정보 유출이다."""
    from app.core.security import hash_password
    from app.services.coach.rag import ingest_personal_text

    _, token = member

    other = User(
        id=f"user-{uuid.uuid4().hex[:12]}",
        email=f"coach-other-{uuid.uuid4().hex[:8]}@example.com",
        name="다른 사용자", hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(other)
    db_session.commit()
    try:
        ingest_personal_text(
            db_session, other.id, "남의 비밀 기록: 삼겹살 500g",
            domain="diet", source="diet",
        )
        client.post(
            "/v1/ai-coach/chat",
            json={"message": "제 식단 기록 알려주세요"},
            headers=_h(token),
        )
        assert "비밀 기록" not in recording_llm.user_prompt
        assert "삼겹살" not in recording_llm.user_prompt
    finally:
        db_session.execute(delete(CoachDocument).where(CoachDocument.user_id == other.id))
        db_session.execute(delete(User).where(User.id == other.id))
        db_session.commit()


def test_system_prompt_keeps_the_medical_disclaimer(client, member, recording_llm):
    """의료 조언 면책 — 진단 단정 금지와 전문의 상담 권유가 지시에 남아 있어야 한다."""
    _, token = member
    client.post(
        "/v1/ai-coach/chat", json={"message": "혈압약 끊어도 될까요?"}, headers=_h(token)
    )

    system = recording_llm.system_prompt
    assert "진단" in system
    assert "전문의" in system
