"""담당 트레이너가 없는 회원의 AI 자동 추천. (#782) DB 필요.

예전에는 담당이 없으면 `/me/coach/routines` 가 늘 빈 목록이라, 그 회원은 운동
탭에서 받을 것이 아무것도 없었다. 승인할 사람이 없으므로 추천 범위 자체를
보수적으로 좁혀 내려준다.
"""
from __future__ import annotations

import pytest
from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.models import AiConversation, TrainerClient, TrainerRoutine
from app.services import auto_routine_service


def _token(client, email: str) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def lone_member(client):
    """담당 트레이너 링크를 잠시 끊어 '담당 없는 회원' 을 만든다.

    시드 회원을 쓰되 끝나면 되돌린다 — 다른 테스트가 같은 회원의 담당 관계를
    전제하므로 여기서 영구히 끊으면 안 된다.
    """
    member_id = "user-jisu"
    db = SessionLocal()
    links = list(
        db.scalars(
            select(TrainerClient).where(TrainerClient.member_id == member_id)
        ).all()
    )
    saved = [(link.trainer_id, link.active) for link in links]
    for link in links:
        link.active = False
    db.commit()
    db.close()

    yield member_id

    db = SessionLocal()
    for (trainer_id, active), link in zip(
        saved,
        db.scalars(
            select(TrainerClient).where(TrainerClient.member_id == member_id)
        ).all(),
        strict=False,
    ):
        link.active = active
    # 이 테스트가 만든 자동 추천은 남기지 않는다.
    for row in db.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.trainer_id.is_(None),
        )
    ).all():
        db.delete(row)
    # AI 코치 대화도 함께 지운다 — 감지는 대화에서 매번 계산되므로(#2016), 앞
    # 테스트가 적어 둔 `무릎이 아파요` 가 남으면 다음 테스트의 추천까지 좁힌다.
    for convo in db.scalars(
        select(AiConversation).where(AiConversation.user_id == member_id)
    ).all():
        db.delete(convo)
    db.commit()
    db.close()


def test_member_without_a_trainer_now_gets_routines(client, lone_member):
    mine = client.get(
        "/v1/me/coach/routines", headers=_h(_token(client, "jisu@oncare.com"))
    )

    assert mine.status_code == 200, mine.text
    body = mine.json()
    assert body, "담당이 없어도 받을 것이 있어야 한다"
    assert {r["name"] for r in body} == {
        name for name, _, _, _, _ in auto_routine_service.SAFE_ROUTINES
    }


def test_auto_recommendations_stay_in_a_safe_range(client, lone_member):
    mine = client.get(
        "/v1/me/coach/routines", headers=_h(_token(client, "jisu@oncare.com"))
    )

    # 승인할 사람이 없으므로 범위 자체가 안전장치다. 고강도·고위험 운동을
    # 회원 기록만으로 새로 처방하지 않는다.
    assert {r["type"] for r in mine.json()} <= {"유산소", "스트레칭"}
    assert all(r["minutes"] <= 30 for r in mine.json())
    assert all(r["reason"] for r in mine.json()), "왜 하는지 없이 주지 않는다"


def test_opening_twice_does_not_pile_up_recommendations(client, lone_member):
    token = _token(client, "jisu@oncare.com")

    first = client.get("/v1/me/coach/routines", headers=_h(token)).json()
    second = client.get("/v1/me/coach/routines", headers=_h(token)).json()

    # 화면을 열 때마다 만들면 목록이 하루 만에 길어진다.
    assert [r["id"] for r in first] == [r["id"] for r in second]


def test_auto_recommendation_can_be_completed(client, lone_member):
    token = _token(client, "jisu@oncare.com")
    routine = client.get("/v1/me/coach/routines", headers=_h(token)).json()[0]

    done = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=_h(token),
        json={"minutes": 15, "intensity": "light", "member_note": ""},
    )

    # 담당이 없다고 완료가 막히면, 화면에 보이는 운동을 수행할 수 없다.
    assert done.status_code == 200, done.text
    assert done.json()["completed"] is True


def test_a_member_with_a_trainer_gets_no_auto_recommendation(client):
    """담당이 있으면 이 경로는 아예 돌지 않는다 — 검토 흐름이 대신한다(#790)."""
    mine = client.get(
        "/v1/me/coach/routines", headers=_h(_token(client, "jisu@oncare.com"))
    ).json()

    safe_names = {name for name, _, _, _, _ in auto_routine_service.SAFE_ROUTINES}
    assert not (safe_names & {r["name"] for r in mine})


def _say(db, member_id: str, text: str) -> None:
    """회원이 AI 코치에 한 줄 적는다 — 감지는 대화에서 매번 계산된다."""
    from app.services.coach import conversation

    conversation.append_exchange(
        db, member_id, question=text, reply="알겠어요", sources=[]
    )
    db.commit()


def test_sore_knee_drops_the_weight_bearing_routine(client, lone_member):
    """무릎이 아프다고 말한 회원에게 걷기를 그대로 권하지 않는다. (#2016)

    이 모듈은 건강 정보를 **내리는 쪽으로만** 쓴다 — 빼기만 하고 다른 운동을
    끼워 넣지 않는다. 대신 무엇을 하라고 정하는 것은 처방이다.
    """
    db = SessionLocal()
    _say(db, lone_member, "무릎이 아파요")
    db.close()

    auto_routine_service.ensure_auto_routines(SessionLocal(), lone_member)
    db = SessionLocal()
    names = {
        row.name
        for row in db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == lone_member,
                TrainerRoutine.trainer_id.is_(None),
            )
        ).all()
    }
    db.close()

    assert "저강도 걷기" not in names
    assert "전신 스트레칭" in names


def test_saying_it_was_hard_shortens_the_routines(client, lone_member):
    """힘들다고 말한 적이 있으면 시간을 줄인다 — 올리지는 않는다. (#2016)"""
    db = SessionLocal()
    _say(db, lone_member, "너무 힘들어서 못 했어요")
    db.close()

    auto_routine_service.ensure_auto_routines(SessionLocal(), lone_member)
    db = SessionLocal()
    rows = {
        row.name: row.minutes
        for row in db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == lone_member,
                TrainerRoutine.trainer_id.is_(None),
            )
        ).all()
    }
    db.close()

    base = {
        name: minutes
        for name, minutes, _, _, _ in auto_routine_service.SAFE_ROUTINES
    }
    assert rows
    for name, minutes in rows.items():
        assert minutes < base[name]
        assert minutes >= auto_routine_service._MIN_MINUTES


def test_a_dismissed_insight_no_longer_narrows_the_routines(client, lone_member):
    """기록 창에서 치운 오탐은 추천도 좁히지 않는다. (#1975 · #2016)"""
    from app.models.models import AiMessage

    db = SessionLocal()
    _say(db, lone_member, "무릎이 아파요")
    message_id = db.scalar(
        select(AiMessage.id)
        .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
        .where(AiConversation.user_id == lone_member, AiMessage.role == "user")
    )
    db.get(AiMessage, message_id).insight_dismissed = True
    db.commit()
    db.close()

    auto_routine_service.ensure_auto_routines(SessionLocal(), lone_member)
    db = SessionLocal()
    names = {
        row.name
        for row in db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == lone_member,
                TrainerRoutine.trainer_id.is_(None),
            )
        ).all()
    }
    db.close()

    assert "저강도 걷기" in names


def _auto_rows(member_id: str) -> dict[str, int]:
    db = SessionLocal()
    rows = {
        row.name: row.minutes
        for row in db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.trainer_id.is_(None),
            )
        ).all()
    }
    db.close()
    return rows


def test_pain_mentioned_later_the_same_day_updates_todays_routines(
    client, lone_member
):
    """아침에 추천을 본 뒤 통증을 말하면 그날 추천부터 바뀐다. (#2016)

    한 번 만들고 끝내면, 무릎이 아프다고 말한 회원에게 그날 하루 걷기가 그대로
    권해진다 — 대화를 참고한다는 약속이 다음 날에야 지켜진다.
    """
    token = _token(client, "jisu@oncare.com")
    morning = client.get("/v1/me/coach/routines", headers=_h(token)).json()
    assert "저강도 걷기" in {r["name"] for r in morning}

    db = SessionLocal()
    _say(db, lone_member, "무릎이 아파요")
    db.close()

    later = client.get("/v1/me/coach/routines", headers=_h(token)).json()
    names = {r["name"] for r in later}
    assert "저강도 걷기" not in names
    assert "전신 스트레칭" in names
    # 다시 열어도 늘지 않는다 — 고친 뒤에도 같은 날 한 벌이다.
    again = client.get("/v1/me/coach/routines", headers=_h(token)).json()
    assert [r["id"] for r in again] == [r["id"] for r in later]


def test_a_finished_routine_stays_even_if_pain_is_mentioned_after(
    client, lone_member
):
    """이미 끝낸 운동은 목록에서 빠지지 않는다 — 회원이 한 일이 지워진다."""
    token = _token(client, "jisu@oncare.com")
    walk = next(
        r
        for r in client.get("/v1/me/coach/routines", headers=_h(token)).json()
        if r["name"] == "저강도 걷기"
    )
    done = client.post(
        f"/v1/me/coach/routines/{walk['id']}/complete",
        headers=_h(token),
        json={"minutes": 20, "intensity": "light", "member_note": ""},
    )
    assert done.status_code == 200, done.text

    db = SessionLocal()
    _say(db, lone_member, "무릎이 아파요")
    db.close()

    after = client.get("/v1/me/coach/routines", headers=_h(token)).json()
    by_name = {r["name"]: r for r in after}
    assert by_name["저강도 걷기"]["id"] == walk["id"]
    assert by_name["저강도 걷기"]["completed"] is True


def test_dismissing_the_insight_brings_the_routine_back_the_same_day(
    client, lone_member
):
    """오탐을 치우면 그날 안에 좁혔던 추천이 돌아온다. (#1975 · #2016)"""
    from app.models.models import AiMessage

    db = SessionLocal()
    _say(db, lone_member, "무릎이 아파요")
    db.close()
    auto_routine_service.ensure_auto_routines(SessionLocal(), lone_member)
    assert "저강도 걷기" not in _auto_rows(lone_member)

    db = SessionLocal()
    message_id = db.scalar(
        select(AiMessage.id)
        .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
        .where(AiConversation.user_id == lone_member, AiMessage.role == "user")
    )
    db.get(AiMessage, message_id).insight_dismissed = True
    db.commit()
    db.close()

    auto_routine_service.ensure_auto_routines(SessionLocal(), lone_member)
    assert "저강도 걷기" in _auto_rows(lone_member)
