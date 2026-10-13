"""AI 챗봇 하루 한도 — 무료 대화와 포인트로 여는 추가 대화. (#2145) DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.models.models import HealthProfile
from app.services.coach.llm_base import LLMResult


@pytest.fixture
def llm(monkeypatch):
    """AI 가 답하는 환경. `fail` 을 참으로 두면 검색 기반 대체 답이 나온다."""
    from app.services.coach import chat as chat_service

    state = {"fail": False}

    class _StubLLM:
        def generate(self, system_prompt: str, user_prompt: str) -> LLMResult:
            if state["fail"]:
                raise RuntimeError("LLM 장애")
            return LLMResult(text="물을 한 컵 더 드세요.", model="stub")

    monkeypatch.setattr(chat_service, "get_coach_llm", lambda *a, **k: _StubLLM())
    return state


@pytest.fixture
def small_limits(monkeypatch):
    """무료 1회, 포인트 1회(50P) — 경계를 짧게 본다."""
    settings = get_settings()
    monkeypatch.setattr(settings, "coach_chat_free_per_day", 1)
    monkeypatch.setattr(settings, "coach_chat_paid_per_day", 1)
    monkeypatch.setattr(settings, "coach_chat_paid_cost", 50)


def _member(client, db_session, points: int) -> dict[str, str]:
    email = f"quota-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()
    return headers


def _send(client, headers, **extra):
    return client.post(
        "/v1/ai-coach/chat", headers=headers, json={"message": "물 얼마나?", **extra}
    )


def test_free_then_paid_then_daily_limit(client, db_session, llm, small_limits):
    h = _member(client, db_session, points=100)

    # AI 가 답하지 못한 대화는 무료 횟수를 쓰지 않는다.
    llm["fail"] = True
    assert _send(client, h).json()["quota"]["free_left"] == 1
    llm["fail"] = False

    assert _send(client, h).json()["points_spent"] == 0
    # 무료를 다 쓴 뒤에는 동의가 있어야 포인트로 보낸다.
    blocked = _send(client, h)
    assert blocked.status_code == 402
    assert blocked.json()["detail"]["code"] == "points_required"

    key = uuid4().hex
    paid = _send(client, h, pay_with_points=True, client_request_id=key).json()
    assert (paid["points_spent"], paid["balance_after"]) == (50, 50)
    # 재전송은 두 번 차감하지 않는다.
    again = _send(client, h, pay_with_points=True, client_request_id=key).json()
    assert again["balance_after"] == 50
    assert client.get("/v1/ai-coach/quota", headers=h).json()["next"] == "exhausted"

    limit = _send(client, h, pay_with_points=True)
    assert (limit.status_code, limit.json()["detail"]["code"]) == (429, "daily_limit")
    # 저장된 대화에서도 산 답변 아래에 차감을 다시 그린다.
    spent = [
        m["points_spent"]
        for m in client.get("/v1/ai-coach/messages", headers=h).json()["messages"]
        if m["role"] != "user"
    ]
    assert spent.count(50) == 1


def test_paid_chat_needs_enough_points(client, db_session, llm, small_limits):
    h = _member(client, db_session, points=10)
    _send(client, h)

    r = _send(client, h, pay_with_points=True)

    assert r.status_code == 409
    assert (r.json()["detail"]["code"], r.json()["detail"]["shortfall"]) == (
        "insufficient_points",
        40,
    )


def test_free_per_day_is_five(client, db_session, llm):
    """기본 무료는 하루 5회다(#2217). 여섯 번째부터 포인트 동의를 묻는다."""
    h = _member(client, db_session, points=0)

    for turn in range(5):
        r = _send(client, h)
        assert r.status_code == 200
        assert r.json()["quota"]["free_left"] == 4 - turn

    blocked = _send(client, h)
    assert blocked.status_code == 402
    assert blocked.json()["detail"]["code"] == "points_required"


# ── 응답을 못 받은 앱의 다시 보내기 (#2846) ─────────────────────────────


def _questions(client, headers) -> list[str]:
    return [
        m["content"]
        for m in client.get("/v1/ai-coach/messages", headers=headers).json()["messages"]
        if m["role"] == "user"
    ]


def test_resend_of_last_free_chat_replays_without_consent(
    client, db_session, llm, small_limits
):
    """마지막 무료 대화가 서버에서 끝난 뒤 같은 키로 다시 오면 동의를 묻지 않고
    저장한 답을 준다 — 앱의 한도가 이미 "포인트" 로 바뀌어 있어도 다시 세지 않는다."""
    h = _member(client, db_session, points=100)
    key = uuid4().hex

    first = _send(client, h, client_request_id=key)
    assert first.status_code == 200, first.text
    resend = _send(client, h, client_request_id=key)

    assert resend.status_code == 200, resend.text
    assert resend.json()["reply"] == first.json()["reply"]
    assert resend.json()["points_spent"] == 0
    quota = client.get("/v1/ai-coach/quota", headers=h).json()
    assert quota["free_left"] == 0
    assert quota["next"] == "paid"
    # 질문도 한 번만 저장된다.
    assert _questions(client, h).count("물 얼마나?") == 1


def test_resend_of_paid_chat_spends_once(client, db_session, llm, small_limits):
    h = _member(client, db_session, points=100)
    _send(client, h)
    key = uuid4().hex

    paid = _send(client, h, pay_with_points=True, client_request_id=key)
    resend = _send(client, h, pay_with_points=True, client_request_id=key)

    assert paid.status_code == 200 and resend.status_code == 200
    assert paid.json()["points_spent"] == 50
    assert resend.json()["balance_after"] == 50
    assert client.get("/v1/me/points/shop", headers=h).json()["balance"] == 50
    assert _questions(client, h).count("물 얼마나?") == 2


def test_new_key_for_same_text_is_a_new_chat(client, db_session, llm, small_limits):
    """새로 쓴 글은 새 키라 새 대화로 센다 — 앱이 키를 다시 쓰는 것이 중요한 까닭."""
    h = _member(client, db_session, points=100)
    _send(client, h, client_request_id=uuid4().hex)

    again = _send(client, h, client_request_id=uuid4().hex)

    assert again.status_code == 402
    assert again.json()["detail"]["code"] == "points_required"


# ── 동시 전송과 잔액 부족 (#3240) ─────────────────────────────────────


def _member_id(client, headers) -> str:
    return client.get("/v1/users/me", headers=headers).json()["id"]


def _ai_chat_ledger(db_session, member_id: str) -> list:
    from app.models.models import PointsLedger
    from app.services import ai_chat_quota_service

    db_session.expire_all()
    return list(
        db_session.scalars(
            select(PointsLedger).where(
                PointsLedger.user_id == member_id,
                PointsLedger.reason == ai_chat_quota_service.REASON_AI_CHAT,
            )
        ).all()
    )


def test_overlapping_sends_cannot_pass_the_balance(
    client, db_session, llm, small_limits, monkeypatch
):
    """두 요청이 답을 기다리는 사이에 겹쳐도 잔액을 넘겨 쓰지 못한다.

    예전에는 확인(`plan`)과 기록(`record`) 사이에 잠금이 없어 50P 로 동시에 보낸
    요청이 모두 통과하고, 기록에서 잔액이 모자란 쪽은 무료로 답을 받았다. 이제는
    LLM 을 부르기 전에 몫을 잡으므로 두 번째는 답하기 전에 거절된다.
    """
    from app.services import ai_chat_quota_service, points_service

    monkeypatch.setattr(get_settings(), "coach_chat_paid_per_day", 3)
    h = _member(client, db_session, points=50)
    member_id = _member_id(client, h)
    assert _send(client, h).status_code == 200  # 무료 1회를 쓴다.

    first = ai_chat_quota_service.reserve(
        db_session, member_id, pay_with_points=True, client_request_id=None
    )
    with pytest.raises(points_service.InsufficientPoints):
        ai_chat_quota_service.reserve(
            db_session, member_id, pay_with_points=True, client_request_id=None
        )

    db_session.expire_all()
    assert points_service.balance(db_session, member_id) == 0
    ai_chat_quota_service.release(db_session, member_id, first)
    assert points_service.balance(db_session, member_id) == 50


def test_overlapping_sends_cannot_pass_the_daily_limit(client, db_session, small_limits):
    """무료 한도도 먼저 잡은 몫으로 센다 — 답을 기다리는 대화가 한도를 차지한다."""
    from app.services import ai_chat_quota_service

    h = _member(client, db_session, points=0)
    member_id = _member_id(client, h)

    ai_chat_quota_service.reserve(
        db_session, member_id, pay_with_points=False, client_request_id=None
    )
    with pytest.raises(ai_chat_quota_service.PointsConsentRequired):
        ai_chat_quota_service.reserve(
            db_session, member_id, pay_with_points=False, client_request_id=None
        )


def test_a_paid_chat_without_an_ai_answer_leaves_no_charge(
    client, db_session, llm, small_limits
):
    """포인트로 보냈는데 대체 답이 나오면 잡아 둔 차감을 없던 일로 한다 — 내역에도 없다."""
    h = _member(client, db_session, points=100)
    member_id = _member_id(client, h)
    _send(client, h)

    llm["fail"] = True
    r = _send(client, h, pay_with_points=True)

    assert r.status_code == 200, r.text
    assert (r.json()["points_spent"], r.json()["balance_after"]) == (0, None)
    quota = r.json()["quota"]
    assert (quota["paid_left"], quota["balance"]) == (1, 100)
    assert _ai_chat_ledger(db_session, member_id) == []


def test_a_resend_while_the_first_is_waiting_is_in_progress(
    client, db_session, llm, small_limits
):
    """같은 키의 요청이 아직 답을 기다리는 중이면 두 번째는 409 `in_progress` 다."""
    from app.services import ai_chat_quota_service

    h = _member(client, db_session, points=100)
    member_id = _member_id(client, h)
    key = uuid4().hex
    ai_chat_quota_service.reserve(
        db_session, member_id, pay_with_points=False, client_request_id=key
    )

    r = _send(client, h, client_request_id=key)

    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "in_progress"


def test_an_abandoned_reservation_is_swept_by_the_next_send(
    client, db_session, small_limits
):
    """답을 기다리던 프로세스가 끝나 남은 예약은 다음 전송이 거둔다 — 키가 달라도.

    거두지 않으면 그날 몫과 잡아 둔 포인트가 답 없이 묶인다.
    """
    from datetime import timedelta

    from app.core import clock
    from app.models.models import AiChatUsage
    from app.services import ai_chat_quota_service, points_service

    h = _member(client, db_session, points=100)
    member_id = _member_id(client, h)
    ai_chat_quota_service.reserve(
        db_session, member_id, pay_with_points=False, client_request_id=uuid4().hex
    )
    abandoned = ai_chat_quota_service.reserve(
        db_session, member_id, pay_with_points=True, client_request_id=uuid4().hex
    )
    db_session.expire_all()
    assert points_service.balance(db_session, member_id) == 50
    for row in db_session.scalars(
        select(AiChatUsage).where(AiChatUsage.user_id == member_id)
    ).all():
        row.created_at = clock.now() - timedelta(minutes=10)
    db_session.commit()

    # 무료 몫이 돌아와 동의 없이 보낼 수 있고, 잡혔던 50P 도 돌아온다.
    fresh = ai_chat_quota_service.reserve(
        db_session, member_id, pay_with_points=False, client_request_id=uuid4().hex
    )

    db_session.expire_all()
    assert db_session.get(AiChatUsage, abandoned) is None
    assert db_session.get(AiChatUsage, fresh) is not None
    assert points_service.balance(db_session, member_id) == 100
    assert _ai_chat_ledger(db_session, member_id) == []


# ── 메시지 식별자와 대체 답 재전송 (#3352) ────────────────────────────


def _history(client, headers) -> list[dict]:
    return client.get("/v1/ai-coach/messages", headers=headers).json()["messages"]


def test_reply_carries_the_ids_of_the_two_stored_rows(client, db_session, llm):
    """응답의 식별자·저장 시각·키는 저장된 대화의 그 두 줄과 같은 값이다."""
    h = _member(client, db_session, points=0)
    key = uuid4().hex

    body = _send(client, h, client_request_id=key).json()

    question, answer_ = _history(client, h)
    assert (question["role"], answer_["role"]) == ("user", "coach")
    assert body["user_message_id"] == question["id"]
    assert body["reply_message_id"] == answer_["id"]
    assert body["user_message_id"] != body["reply_message_id"]
    assert body["user_created_at"] is not None
    assert body["reply_created_at"] is not None
    assert body["client_request_id"] == key
    assert (question["client_request_id"], answer_["client_request_id"]) == (key, key)


def test_a_send_without_a_key_still_gets_ids(client, db_session, llm):
    """키 없이 보낸 옛 앱의 전송도 식별자는 받는다 — 키만 null 이다."""
    h = _member(client, db_session, points=0)

    body = _send(client, h).json()

    assert body["client_request_id"] is None
    stored = _history(client, h)
    assert [m["id"] for m in stored] == [
        body["user_message_id"],
        body["reply_message_id"],
    ]
    assert [m["client_request_id"] for m in stored] == [None, None]


def test_old_response_fields_are_unchanged(client, db_session, llm):
    """옛 앱이 읽는 필드는 그대로다 — 추가만 했다."""
    h = _member(client, db_session, points=0)

    body = _send(client, h, client_request_id=uuid4().hex).json()

    assert {
        "reply",
        "sources",
        "user_insight",
        "points_spent",
        "balance_after",
        "quota",
    } <= set(body)
    stored = _history(client, h)[0]
    assert {
        "role",
        "content",
        "sources",
        "created_at",
        "insight",
        "points_spent",
        "balance_after",
    } <= set(stored)


def test_resend_after_a_fallback_answer_replays_it(
    client, db_session, llm, small_limits
):
    """모델 장애로 대체 답이 나간 전송을 같은 키로 다시 보내면 그 답을 재생한다 —
    대화에 같은 질문이 한 쌍 더 남지 않는다."""
    h = _member(client, db_session, points=100)
    key = uuid4().hex
    llm["fail"] = True

    first = _send(client, h, client_request_id=key)
    resend = _send(client, h, client_request_id=key)

    assert first.status_code == 200 and resend.status_code == 200, resend.text
    assert resend.json()["reply"] == first.json()["reply"]
    assert resend.json()["user_message_id"] == first.json()["user_message_id"]
    assert resend.json()["reply_message_id"] == first.json()["reply_message_id"]
    assert _questions(client, h).count("물 얼마나?") == 1
    assert len(_history(client, h)) == 2


def test_fallback_replay_still_costs_nothing(client, db_session, llm, small_limits):
    """대체 답은 처음에도 재생에도 무료 횟수·포인트를 쓰지 않는다."""
    h = _member(client, db_session, points=100)
    member_id = _member_id(client, h)
    key = uuid4().hex
    llm["fail"] = True

    _send(client, h, client_request_id=key)
    resend = _send(client, h, client_request_id=key)

    assert (resend.json()["points_spent"], resend.json()["balance_after"]) == (0, None)
    quota = resend.json()["quota"]
    assert (quota["free_left"], quota["paid_left"], quota["balance"]) == (1, 1, 100)
    assert _ai_chat_ledger(db_session, member_id) == []


def test_fallback_replay_is_not_answered_again_after_recovery(
    client, db_session, llm, small_limits
):
    """모델이 돌아온 뒤 같은 키로 다시 와도 새로 답하지 않는다 — 저장한 대체 답이
    그 전송의 답이다. 새로 물으려면 새 키로 보낸다."""
    h = _member(client, db_session, points=100)
    key = uuid4().hex
    llm["fail"] = True
    first = _send(client, h, client_request_id=key)

    llm["fail"] = False
    resend = _send(client, h, client_request_id=key)
    fresh = _send(client, h, client_request_id=uuid4().hex)

    assert resend.json()["reply"] == first.json()["reply"]
    assert fresh.json()["reply"] == "물을 한 컵 더 드세요."
    assert _questions(client, h).count("물 얼마나?") == 2


def test_fallback_replay_is_per_member(client, db_session, llm, small_limits):
    """남의 키와 같은 값을 보내도 남의 답이 재생되지 않는다."""
    mine = _member(client, db_session, points=0)
    other = _member(client, db_session, points=0)
    key = uuid4().hex
    llm["fail"] = True
    first = _send(client, mine, client_request_id=key)

    theirs = _send(client, other, client_request_id=key)

    assert theirs.status_code == 200, theirs.text
    assert theirs.json()["user_message_id"] != first.json()["user_message_id"]
    assert len(_history(client, other)) == 2
    assert len(_history(client, mine)) == 2


def test_resend_of_paid_chat_replays_the_same_rows(
    client, db_session, llm, small_limits
):
    """AI 가 답한 전송의 재생도 같은 두 줄의 식별자를 돌려준다."""
    h = _member(client, db_session, points=100)
    _send(client, h)
    key = uuid4().hex

    paid = _send(client, h, pay_with_points=True, client_request_id=key).json()
    resend = _send(client, h, pay_with_points=True, client_request_id=key).json()

    assert resend["user_message_id"] == paid["user_message_id"]
    assert resend["reply_message_id"] == paid["reply_message_id"]
    assert resend["client_request_id"] == key
    assert resend["points_spent"] == 50


def test_a_fallback_saved_between_the_check_and_the_reservation_is_replayed(
    client, db_session, llm, small_limits, monkeypatch
):
    """처음 볼 때는 없던 같은 키의 대체 답이 몫을 잡는 사이 저장됐으면, 잡은 몫을
    거두고 그 답을 재생한다 — 한 쌍 더 저장하지 않는다."""
    from app.services import ai_chat_quota_service
    from app.services.coach import conversation

    h = _member(client, db_session, points=100)
    member_id = _member_id(client, h)
    key = uuid4().hex
    real_reserve = ai_chat_quota_service.reserve

    def _reserve_after_other_finishes(db, user_id, **kwargs):
        # 먼저 온 같은 키의 요청이 대체 답을 저장하고 사용 기록을 거둔 뒤다.
        conversation.append_exchange(
            db,
            user_id,
            question="물 얼마나?",
            reply="먼저 저장된 대체 답",
            sources=[],
            client_request_id=key,
        )
        return real_reserve(db, user_id, **kwargs)

    monkeypatch.setattr(
        ai_chat_quota_service, "reserve", _reserve_after_other_finishes
    )

    r = _send(client, h, client_request_id=key)

    assert r.status_code == 200, r.text
    assert r.json()["reply"] == "먼저 저장된 대체 답"
    assert _questions(client, h).count("물 얼마나?") == 1
    assert r.json()["quota"]["free_left"] == 1
    assert _ai_chat_ledger(db_session, member_id) == []
