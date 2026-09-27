"""트레이너 고객 AI 코치의 분당 한도 (#1548).

`POST /trainer/clients/{member_id}/ai-coach` 는 회원 AI 코치와 같은 LLM 경로를
타는데 한도가 없었다. 트레이너 계정 하나가 provider 비용과 quota 를 제한 없이
쓸 수 있었다.

여기서 보는 것:

* 한도(`coach_chat_per_minute`)까지는 통과하고 그다음은 429 + `Retry-After`.
* 오류 계약은 다른 한도와 같다(`{"detail": ...}`).
* 버킷은 **트레이너 id** 단위다 — 같은 IP 의 다른 트레이너는 영향이 없고,
  한 트레이너가 여러 고객에게 나눠 물어도 한 버킷으로 센다.
* 윈도우가 지나면 다시 열린다.
* 한도를 끄면(`RATE_LIMIT_ENABLED=false`) 막지 않는다.
* 한도에 걸린 요청은 LLM 을 부르지도, 대화를 저장하지도 않는다.
* 담당이 아닌 회원에 대한 요청은 한도보다 먼저 404 다(존재를 드러내지 않는다).
"""
from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from uuid import uuid4

import pytest
from sqlalchemy import func, select, text

from app.core.config import get_settings
from app.core.security import create_access_token
from app.models.models import AiConversation, AiMessage, TrainerClient, User

pytest.importorskip("fastapi")


@dataclass
class Pair:
    trainer_id: str
    member_id: str
    headers: dict[str, str]


@pytest.fixture(autouse=True)
def llm_calls(monkeypatch) -> list[str]:
    """LLM 호출을 세고 네트워크를 막는다 — 보는 것은 한도이지 답변 품질이 아니다."""
    calls: list[str] = []

    class _StubLLM:
        name = "stub"
        model_name = "stub-model"

        def generate(self, system_prompt: str, user_prompt: str):
            calls.append(user_prompt)

            class _R:
                text = "확인했습니다."

            return _R()

    monkeypatch.setattr(
        "app.services.coach.chat.get_coach_llm", lambda *a, **k: _StubLLM()
    )
    return calls


def _make_trainer(db_session, *, members: int = 1) -> tuple[str, list[str]]:
    suffix = uuid4().hex[:10]
    trainer_id = f"rl-coach-trainer-{suffix}"
    member_ids = [f"rl-coach-member-{suffix}-{i}" for i in range(members)]
    db_session.add(
        User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="한도 확인 트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    for mid in member_ids:
        db_session.add(
            User(
                id=mid,
                email=f"{mid}@oncare.com",
                name="한도 확인 회원",
                hashed_password="unused",
                role="member",
            )
        )
    db_session.flush()
    for mid in member_ids:
        db_session.add(
            TrainerClient(
                id=f"tc-{uuid4().hex[:12]}",
                trainer_id=trainer_id,
                member_id=mid,
                active=True,
            )
        )
    db_session.commit()
    return trainer_id, member_ids


def _cleanup(db_session, user_ids: list[str]) -> None:
    db_session.rollback()
    db_session.expire_all()
    db_session.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": user_ids})
    db_session.commit()


@pytest.fixture()
def make_pair(db_session) -> Iterator:
    created: list[str] = []

    def _make(members: int = 1) -> tuple[dict[str, str], list[str]]:
        trainer_id, member_ids = _make_trainer(db_session, members=members)
        created.extend([trainer_id, *member_ids])
        return {"Authorization": f"Bearer {create_access_token(trainer_id)}"}, member_ids

    yield _make
    _cleanup(db_session, created)


@pytest.fixture()
def pair(make_pair) -> Pair:
    headers, members = make_pair()
    return Pair(trainer_id="", member_id=members[0], headers=headers)


def _ask(client, headers: dict[str, str], member_id: str, message: str = "이번 주 어때요?"):
    return client.post(
        f"/v1/trainer/clients/{member_id}/ai-coach",
        headers=headers,
        json={"message": message},
    )


def _exhaust(client, headers, member_id) -> None:
    limit = get_settings().coach_chat_per_minute
    for i in range(limit):
        r = _ask(client, headers, member_id, f"질문 {i}")
        assert r.status_code == 200, (i, r.text)


def test_requests_up_to_the_limit_pass(client, pair):
    _exhaust(client, pair.headers, pair.member_id)


def test_the_request_after_the_limit_is_429_with_retry_after(client, pair):
    _exhaust(client, pair.headers, pair.member_id)

    r = _ask(client, pair.headers, pair.member_id)

    assert r.status_code == 429, r.text
    assert r.headers["Retry-After"] == "60"
    # 다른 한도(인증·루틴 생성)와 같은 오류 계약이다.
    assert r.json() == {"detail": "요청이 너무 많습니다. 잠시 후 다시 시도해 주세요."}


def test_a_blocked_request_does_not_call_the_llm_or_store_the_exchange(
    client, db_session, pair, llm_calls
):
    _exhaust(client, pair.headers, pair.member_id)
    calls_before = len(llm_calls)
    db_session.expire_all()
    stored_before = db_session.scalar(
        select(func.count())
        .select_from(AiMessage)
        .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
        .where(AiConversation.user_id == pair.member_id)
    )

    r = _ask(client, pair.headers, pair.member_id, "막혀야 하는 질문")

    assert r.status_code == 429
    assert len(llm_calls) == calls_before
    db_session.expire_all()
    stored_after = db_session.scalar(
        select(func.count())
        .select_from(AiMessage)
        .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
        .where(AiConversation.user_id == pair.member_id)
    )
    assert stored_after == stored_before


def test_trainers_do_not_share_a_bucket(client, make_pair):
    """같은 IP(TestClient)라도 다른 트레이너는 자기 한도를 그대로 쓴다."""
    first_headers, first_members = make_pair()
    second_headers, second_members = make_pair()
    _exhaust(client, first_headers, first_members[0])
    assert _ask(client, first_headers, first_members[0]).status_code == 429

    r = _ask(client, second_headers, second_members[0])

    assert r.status_code == 200, r.text


def test_one_trainer_is_counted_across_all_clients(client, make_pair):
    """고객을 바꿔 가며 물어도 한도는 트레이너 하나에 걸린다."""
    headers, members = make_pair(members=2)
    _exhaust(client, headers, members[0])

    r = _ask(client, headers, members[1])

    assert r.status_code == 429, r.text


def test_trainer_bucket_is_separate_from_member_coach_bucket(client, pair):
    """회원 AI 코치(IP 버킷)를 다 써도 트레이너 버킷은 따로 센다."""
    from app.core.rate_limit import limiter

    limit = get_settings().coach_chat_per_minute
    for _ in range(limit):
        limiter.check("coach-chat:testclient", limit, 60.0)

    r = _ask(client, pair.headers, pair.member_id)

    assert r.status_code == 200, r.text


def test_the_limit_recovers_after_the_window(client, pair, monkeypatch):
    import app.core.rate_limit as rate_limit_module

    now = [1_000_000.0]
    monkeypatch.setattr(rate_limit_module.time, "monotonic", lambda: now[0])
    rate_limit_module.limiter.clear()
    _exhaust(client, pair.headers, pair.member_id)
    assert _ask(client, pair.headers, pair.member_id).status_code == 429

    now[0] += 61.0

    r = _ask(client, pair.headers, pair.member_id)
    assert r.status_code == 200, r.text


def test_the_limit_follows_the_setting(client, pair, monkeypatch):
    """한도는 설정값을 따른다 — 코드에 박힌 숫자가 아니다."""
    monkeypatch.setattr(get_settings(), "coach_chat_per_minute", 2)
    assert _ask(client, pair.headers, pair.member_id).status_code == 200
    assert _ask(client, pair.headers, pair.member_id).status_code == 200

    r = _ask(client, pair.headers, pair.member_id)

    assert r.status_code == 429, r.text


def test_disabled_rate_limit_does_not_block(client, pair, monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", False)
    monkeypatch.setattr(get_settings(), "coach_chat_per_minute", 1)

    for _ in range(3):
        r = _ask(client, pair.headers, pair.member_id)
        assert r.status_code == 200, r.text


def test_a_non_client_is_404_before_the_limit_is_counted(client, pair):
    """남의 회원에 대한 요청은 한도를 소모하지 않고 404 다."""
    limit = get_settings().coach_chat_per_minute
    for _ in range(limit + 2):
        r = _ask(client, pair.headers, "not-my-member")
        assert r.status_code == 404, r.text

    r = _ask(client, pair.headers, pair.member_id)

    assert r.status_code == 200, r.text


def test_history_read_is_not_rate_limited(client, pair):
    """문답 복원(GET)은 LLM 을 부르지 않으므로 한도에 묶이지 않는다."""
    _exhaust(client, pair.headers, pair.member_id)
    assert _ask(client, pair.headers, pair.member_id).status_code == 429

    r = client.get(
        f"/v1/trainer/clients/{pair.member_id}/ai-coach", headers=pair.headers
    )

    assert r.status_code == 200, r.text
