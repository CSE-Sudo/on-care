"""회원 AI 코치 요청의 입력 크기 제한 (#1549).

`message`·`history`·각 턴 `content` 에 제한이 없었다. 요청 수 한도(분당)는 요청
**개수**만 막아, 한 요청의 크기가 만드는 토큰 비용·context 초과·메모리를 막지
못했다.

여기서 보는 것:

* 스키마 경계값 — 질문 1000자, 턴 2000자, history 20턴까지는 받고 하나라도 넘으면 422.
* 트레이너 고객 AI 코치의 질문 한도와 같은 값이다.
* 초과 요청은 **provider 를 부르기 전에** 거절되고 아무것도 저장되지 않는다.
* 본문 전체 상한은 413 이고, 핸들러에 닿기 전에 끊긴다. 필드 한도를 다 채운
  정상 요청은 JSON 이스케이프로 보내도 그 상한 안에 든다.
"""
from __future__ import annotations

import json
import uuid
from collections.abc import Iterator

import pytest
from fastapi import Request
from pydantic import ValidationError
from sqlalchemy import func, select, text

from app.core.config import get_settings
from app.models.models import AiConversation, AiMessage, User
from app.schemas.misc_api import (
    COACH_HISTORY_MAX_TURNS,
    COACH_MESSAGE_MAX_CHARS,
    COACH_TURN_MAX_CHARS,
    ChatRequest,
    ChatTurn,
)
from app.schemas.trainer_api import ClientCoachRequest


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _turns(n: int, content: str = "안녕") -> list[dict[str, str]]:
    return [
        {"role": "user" if i % 2 == 0 else "coach", "content": content}
        for i in range(n)
    ]


# ---- 스키마 경계값 ----


def test_limits_are_the_documented_values():
    assert COACH_MESSAGE_MAX_CHARS == 1000
    assert COACH_TURN_MAX_CHARS == 2000
    assert COACH_HISTORY_MAX_TURNS == 20


def test_member_and_trainer_question_limits_match():
    """회원·트레이너 AI 코치가 같은 질문 길이를 받는다."""
    trainer_max = ClientCoachRequest.model_fields["message"].metadata
    assert any(getattr(m, "max_length", None) == COACH_MESSAGE_MAX_CHARS for m in trainer_max)


def test_message_at_the_limit_is_accepted():
    req = ChatRequest(message="가" * COACH_MESSAGE_MAX_CHARS)
    assert len(req.message) == COACH_MESSAGE_MAX_CHARS


def test_message_over_the_limit_is_rejected():
    with pytest.raises(ValidationError):
        ChatRequest(message="가" * (COACH_MESSAGE_MAX_CHARS + 1))


def test_message_limit_counts_characters_not_bytes():
    """한글 1000자(3000바이트)도 1000자다 — 바이트로 세면 한국어만 3배 짧아진다."""
    ChatRequest(message="한" * COACH_MESSAGE_MAX_CHARS)


def test_history_at_the_turn_limit_is_accepted():
    req = ChatRequest(message="q", history=_turns(COACH_HISTORY_MAX_TURNS))
    assert len(req.history) == COACH_HISTORY_MAX_TURNS


def test_history_over_the_turn_limit_is_rejected():
    with pytest.raises(ValidationError):
        ChatRequest(message="q", history=_turns(COACH_HISTORY_MAX_TURNS + 1))


def test_turn_content_at_the_limit_is_accepted():
    ChatTurn(role="coach", content="a" * COACH_TURN_MAX_CHARS)


def test_turn_content_over_the_limit_is_rejected():
    with pytest.raises(ValidationError):
        ChatTurn(role="coach", content="a" * (COACH_TURN_MAX_CHARS + 1))


def test_one_oversized_turn_rejects_the_whole_request():
    history = _turns(3)
    history[1]["content"] = "a" * (COACH_TURN_MAX_CHARS + 1)
    with pytest.raises(ValidationError):
        ChatRequest(message="q", history=history)


def test_turn_role_is_bounded():
    with pytest.raises(ValidationError):
        ChatTurn(role="x" * 17, content="hi")


def test_history_is_still_optional():
    """보내지 않아도 된다는 기존 계약은 그대로다."""
    assert ChatRequest(message="q").history == []


def test_default_history_is_not_shared_between_requests():
    a = ChatRequest(message="q")
    a.history.append(ChatTurn(role="user", content="x"))
    assert ChatRequest(message="q").history == []


# ---- API: 422 는 provider 앞에서 ----


@pytest.fixture
def llm_calls(monkeypatch) -> list[str]:
    calls: list[str] = []

    class _StubLLM:
        name = "stub"
        model_name = "stub-model"

        def generate(self, system_prompt: str, user_prompt: str):
            calls.append(user_prompt)

            class _R:
                text = "좋아요. 천천히 해 봐요."

            return _R()

    monkeypatch.setattr(
        "app.services.coach.chat.get_coach_llm", lambda *a, **k: _StubLLM()
    )
    return calls


@pytest.fixture
def member(client, db_session) -> Iterator[tuple[User, str]]:
    """담당 트레이너가 없는 새 회원 — AI 챗봇을 쓰고, 오늘 무료가 남아 있다."""
    from app.core.security import hash_password

    email = f"input-limit-{uuid.uuid4().hex[:8]}@example.com"
    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=email, name="입력 한도",
        hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user)
    db_session.commit()
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    yield user, token
    db_session.rollback()
    db_session.execute(text("DELETE FROM users WHERE id = :id"), {"id": user.id})
    db_session.commit()


def _stored_count(db_session, user_id: str) -> int:
    db_session.expire_all()
    return db_session.scalar(
        select(func.count())
        .select_from(AiMessage)
        .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
        .where(AiConversation.user_id == user_id)
    )


def _chat(client, token: str, payload: dict):
    return client.post("/v1/ai-coach/chat", json=payload, headers=_h(token))


def test_api_accepts_a_message_at_the_limit(client, member, llm_calls):
    _, token = member

    r = _chat(client, token, {"message": "가" * COACH_MESSAGE_MAX_CHARS})

    assert r.status_code == 200, r.text
    assert len(llm_calls) == 1


def test_api_rejects_a_long_message_before_calling_the_provider(
    client, db_session, member, llm_calls
):
    user, token = member

    r = _chat(client, token, {"message": "가" * (COACH_MESSAGE_MAX_CHARS + 1)})

    assert r.status_code == 422, r.text
    assert r.json()["detail"][0]["loc"] == ["body", "message"]
    assert llm_calls == []
    assert _stored_count(db_session, user.id) == 0


def test_api_rejects_too_many_history_turns(client, db_session, member, llm_calls):
    user, token = member

    r = _chat(
        client, token,
        {"message": "q", "history": _turns(COACH_HISTORY_MAX_TURNS + 1)},
    )

    assert r.status_code == 422, r.text
    assert r.json()["detail"][0]["loc"] == ["body", "history"]
    assert llm_calls == []
    assert _stored_count(db_session, user.id) == 0


def test_api_rejects_an_oversized_history_turn(client, member, llm_calls):
    _, token = member
    history = _turns(2)
    history[0]["content"] = "a" * (COACH_TURN_MAX_CHARS + 1)

    r = _chat(client, token, {"message": "q", "history": history})

    assert r.status_code == 422, r.text
    assert r.json()["detail"][0]["loc"] == ["body", "history", 0, "content"]
    assert llm_calls == []


def test_api_accepts_a_full_history_at_every_limit(client, member, llm_calls):
    """세 한도를 모두 끝까지 채운 요청도 정상이다(본문 상한에도 걸리지 않는다)."""
    _, token = member

    r = _chat(
        client, token,
        {
            "message": "가" * COACH_MESSAGE_MAX_CHARS,
            "history": _turns(COACH_HISTORY_MAX_TURNS, "나" * COACH_TURN_MAX_CHARS),
        },
    )

    assert r.status_code == 200, r.text


def test_limits_do_not_consume_the_daily_quota(client, member, llm_calls):
    """거절된 요청은 오늘 무료 대화를 쓰지 않는다."""
    _, token = member
    before = client.get("/v1/ai-coach/quota", headers=_h(token)).json()["free_left"]

    _chat(client, token, {"message": "가" * (COACH_MESSAGE_MAX_CHARS + 1)})

    after = client.get("/v1/ai-coach/quota", headers=_h(token)).json()["free_left"]
    assert after == before


def test_trainer_question_over_the_limit_is_still_422(client):
    """트레이너 쪽 기존 한도도 같은 값으로 그대로다."""
    token = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    member_id = client.get("/v1/trainer/clients", headers=_h(token)).json()[0]["id"]

    r = client.post(
        f"/v1/trainer/clients/{member_id}/ai-coach",
        headers=_h(token),
        json={"message": "가" * (COACH_MESSAGE_MAX_CHARS + 1)},
    )

    assert r.status_code == 422, r.text


# ---- 본문 전체 상한(413) ----


def test_body_limit_covers_a_maximal_escaped_request():
    """필드 한도를 다 채운 요청을 `\\uXXXX` 로 이스케이프해 보내도 상한 안이다.

    다른 클라이언트가 ensure_ascii 로 직렬화해도 정상 요청이 413 이 되면 안 된다.
    """
    payload = {
        "message": "가" * COACH_MESSAGE_MAX_CHARS,
        "history": [
            {"role": "coach", "content": "나" * COACH_TURN_MAX_CHARS}
            for _ in range(COACH_HISTORY_MAX_TURNS)
        ],
        "pay_with_points": True,
        "client_request_id": "x" * 64,
    }
    size = len(json.dumps(payload, ensure_ascii=True).encode("utf-8"))
    assert size < get_settings().coach_chat_max_body_bytes


def test_api_rejects_an_oversized_body_with_413(client, member, llm_calls):
    _, token = member
    limit = get_settings().coach_chat_max_body_bytes
    body = json.dumps({"message": "q", "padding": "a" * limit}).encode("utf-8")

    r = client.post(
        "/v1/ai-coach/chat",
        content=body,
        headers={**_h(token), "Content-Type": "application/json"},
    )

    assert r.status_code == 413, r.text
    assert r.json() == {
        "detail": "요청이 너무 큽니다. 질문과 대화 기록을 줄여 다시 보내 주세요."
    }
    assert llm_calls == []


def test_body_limit_does_not_touch_other_coach_paths(client, member):
    """상한은 채팅 경로에만 건다 — 조회 경로는 그대로다."""
    _, token = member

    r = client.get("/v1/ai-coach/messages", headers=_h(token))

    assert r.status_code == 200, r.text


def test_body_limit_middleware_uses_the_given_detail():
    """업로드가 아닌 경로는 "업로드 용량" 이 아니라 준 문구로 거절한다."""
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.core.body_limit import RequestBodySizeLimitMiddleware

    app = FastAPI()
    app.add_middleware(
        RequestBodySizeLimitMiddleware,
        max_bytes=10,
        protected_paths=("/chat",),
        detail="너무 커요",
    )
    reached: list[str] = []

    @app.post("/chat")
    async def _chat_handler(request: Request) -> dict:
        # JSON 엔드포인트처럼 본문을 실제로 읽는다.
        await request.body()
        reached.append("read")
        return {}

    with TestClient(app) as c:
        r = c.post("/chat", content=b"x" * 11)
        chunked = c.post("/chat", content=iter([b"x" * 6, b"x" * 6]))

    assert r.status_code == 413
    assert r.json() == {"detail": "너무 커요"}
    assert chunked.status_code == 413
    assert reached == []
