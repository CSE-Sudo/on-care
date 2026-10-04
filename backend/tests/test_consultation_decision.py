"""상담 수락·거절. (#467, #2584)

수락은 **상담 일정 확정**이지 담당 연결(등록)이 아니다. 수락하면 회원이 고른 자리에
`상담` 일정이 잡히고, 담당 링크·헬스장 연결·건강 목표는 건드리지 않는다. 등록은
상담 뒤 현장에서 회원이 띄운 6자리 코드로 한다 — 그래서 "수락해도 로스터에 없다",
"코드로 연결하면 상담 일정이 그대로 이어진다"를 `GET /trainer/clients`·
`GET /trainer/schedule` 응답으로 확인한다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.core.clock import SEOUL
from app.core.security import hash_password
from app.models.models import (
    ConsultationRequest,
    MemberGym,
    MemberPairingCode,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import consultation_service

EMAIL_PREFIX = "decide-test-"
PLACE_PREFIX = "decide-place-"
SLOT_PREFIX = "decide-slot-"
PASSWORD = "decide-pw-1234"


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        db_session.query(TrainerSchedule).filter(
            (TrainerSchedule.trainer_id.in_(user_ids))
            | (TrainerSchedule.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(ConsultationRequest).filter(
            (ConsultationRequest.member_id.in_(user_ids))
            | (ConsultationRequest.trainer_id.in_(user_ids))
            | (ConsultationRequest.decided_by.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerReservationSlot).filter(
            TrainerReservationSlot.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerClient).filter(
            (TrainerClient.trainer_id.in_(user_ids))
            | (TrainerClient.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerClientInvite).filter(
            (TrainerClientInvite.trainer_id.in_(user_ids))
            | (TrainerClientInvite.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(MemberPairingCode).filter(
            MemberPairingCode.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(Notification).filter(
            Notification.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(MemberGym).filter(
            MemberGym.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(MemberGym).filter(
        MemberGym.gym_id.like(f"{PLACE_PREFIX}%")
    ).delete(synchronize_session=False)
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
        synchronize_session=False
    )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _member(client) -> tuple[str, str]:
    """회원 계정 하나. (id, token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "상담 회원"},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _gym(db_session) -> Place:
    place = Place(
        id=f"{PLACE_PREFIX}{uuid4().hex[:10]}",
        name="승인 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    db_session.commit()
    return place


def _trainer(client, db_session, *, gym: Place | None = None) -> tuple[User, str]:
    """로그인 가능한 트레이너. 소속 헬스장은 주어지면 그것, 아니면 새로 만든다."""
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"decide-trainer-{suffix}",
        email=email,
        name="승인 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(
        TrainerProfile(
            trainer_id=trainer.id,
            gym_id=(gym or _gym(db_session)).id,
        )
    )
    db_session.commit()
    return trainer, _login(client, email)


def _gym_id_of(db_session, trainer: User) -> str:
    """트레이너의 소속 헬스장 id. TrainerProfile 의 PK 는 trainer_id 가 아니다."""
    return (
        db_session.query(TrainerProfile.gym_id)
        .filter(TrainerProfile.trainer_id == trainer.id)
        .scalar()
    )


def _open_slot(trainer_id: str, *, hours_ahead: float = 48) -> TrainerReservationSlot:
    """그 트레이너가 연 `1:1 PT` 빈 자리 하나. (#1873)

    테스트의 `db_session` 이 아니라 자체 세션을 쓴다 — 상담을 거는 28곳에 세션을
    흘려보내지 않기 위해서다. 커밋한 행은 API 세션에서도 그대로 보인다.

    기본값 48시간 뒤는 상담 폼 하한(`CONSULT_SLOT_MIN_LEAD_HOURS`, 4시간)을 넉넉히
    넘긴 값이다.
    """
    from app.db.session import SessionLocal

    slot = TrainerReservationSlot(
        id=f"{SLOT_PREFIX}{uuid4().hex[:10]}",
        trainer_id=trainer_id,
        starts_at=datetime.now(timezone.utc) + timedelta(hours=hours_ahead),
        duration_minutes=30,
        capacity=1,
        remaining=1,
        session_type="1:1 PT",
    )
    with SessionLocal() as session:
        session.add(slot)
        session.commit()
        session.refresh(slot)
        session.expunge(slot)
    return slot


def _request_consultation(
    client, token: str, *, trainer_id: str, hours_ahead: float = 48
) -> str:
    """회원이 그 트레이너의 빈 자리를 하나 골라 상담을 신청한다. (#1873)

    희망 시각을 적어 보내던 방식은 없어졌다 — 자리를 먼저 열고 그 자리를 고른다.
    """
    slot = _open_slot(trainer_id, hours_ahead=hours_ahead)
    payload = {
        "trainer_id": trainer_id,
        "exercise_goal": "weight_loss",
        "health_purpose_type": "general",
        "health_purpose_detail": None,
        "slot_id": slot.id,
        "message": "상담 부탁드립니다.",
        "data_sharing_consent": True,
    }
    response = client.post("/v1/consultations", headers=_auth(token), json=payload)
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _accept(client, trainer_token: str, consultation_id: str) -> dict:
    response = client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(trainer_token),
        json={},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _pair_by_code(client, member_token: str, trainer_token: str) -> None:
    """회원이 코드를 띄우고 트레이너가 입력한다 — 상담 뒤 등록 경로(#1634, #2584)."""
    issued = client.post("/v1/users/me/pairing-code", headers=_auth(member_token))
    assert issued.status_code == 200, issued.text
    redeemed = client.post(
        "/v1/trainer/pairing-code",
        json={"code": issued.json()["code"]},
        headers=_auth(trainer_token),
    )
    assert redeemed.status_code == 200, redeemed.text


def _schedule_on(client, trainer_token: str, day: str) -> list[dict]:
    response = client.get(
        f"/v1/trainer/schedule?from={day}&to={day}", headers=_auth(trainer_token)
    )
    assert response.status_code == 200, response.text
    return response.json()


def _roster_ids(client, trainer_token: str) -> set[str]:
    roster = client.get("/v1/trainer/clients", headers=_auth(trainer_token))
    assert roster.status_code == 200, roster.text
    return {c["id"] for c in roster.json()}


# --- 인박스 조회 -----------------------------------------------------------


def test_inbox_shows_only_requests_addressed_to_me(client, db_session):
    """인박스에는 나를 지정한 요청만 뜬다.

    같은 헬스장 동료에게 간 요청까지 보이면, 회원이 고른 트레이너가 아닌 사람이
    상담을 가져갈 수 있다.
    """
    gym = _gym(db_session)
    trainer, trainer_token = _trainer(client, db_session, gym=gym)
    colleague, _ = _trainer(client, db_session, gym=gym)
    _, member_token = _member(client)
    _, other_member_token = _member(client)

    mine = _request_consultation(client, member_token, trainer_id=trainer.id)
    colleagues = _request_consultation(
        client, other_member_token, trainer_id=colleague.id
    )

    response = client.get("/v1/trainer/consultations", headers=_auth(trainer_token))

    assert response.status_code == 200, response.text
    by_id = {item["id"]: item for item in response.json()}
    assert mine in by_id
    assert colleagues not in by_id
    # 카드가 회원 이름을 렌더하므로 id 만 오면 안 된다.
    assert by_id[mine]["member_name"] == "상담 회원"


def test_inbox_excludes_other_trainers_requests(client, db_session):
    """다른 헬스장으로 간 요청은 보이지 않는다."""
    _, mine_token = _trainer(client, db_session)
    other_trainer, _ = _trainer(client, db_session)
    _, member_token = _member(client)

    foreign_id = _request_consultation(
        client, member_token, trainer_id=other_trainer.id
    )

    response = client.get("/v1/trainer/consultations", headers=_auth(mine_token))

    assert response.status_code == 200, response.text
    assert foreign_id not in {item["id"] for item in response.json()}


def test_inbox_defaults_to_pending_only(client, db_session):
    """기본 필터는 미처리. 처리한 건은 status=all 로만 보인다."""
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    client.post(
        f"/v1/trainer/consultations/{consultation_id}/reject",
        headers=_auth(trainer_token),
        json={"note": "일정이 어려워요"},
    )

    pending = client.get(
        "/v1/trainer/consultations", headers=_auth(trainer_token)
    ).json()
    every = client.get(
        "/v1/trainer/consultations?status=all", headers=_auth(trainer_token)
    ).json()

    assert consultation_id not in {item["id"] for item in pending}
    assert consultation_id in {item["id"] for item in every}


def test_pending_count_matches_inbox(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    _request_consultation(client, member_token, trainer_id=trainer.id)

    count = client.get(
        "/v1/trainer/consultations/pending-count", headers=_auth(trainer_token)
    )
    inbox = client.get("/v1/trainer/consultations", headers=_auth(trainer_token))

    assert count.status_code == 200, count.text
    assert count.json()["count"] == len(inbox.json()) == 1


# --- 회원 취소 -------------------------------------------------------------


def test_member_cancel_notifies_target_trainer(client, db_session):
    """회원이 취소하면 대상 트레이너에게 알림이 남는다. (#1625)

    알림이 없으면 인박스와 배지에서 요청이 이유 없이 사라져, 트레이너는 자신이
    이미 처리한 것인지 회원이 취소한 것인지 구분할 수 없다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )

    response = client.delete(
        f"/v1/consultations/{consultation_id}", headers=_auth(member_token)
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "cancelled"

    titles = [
        item["title"]
        for item in client.get(
            "/v1/trainer/notifications", headers=_auth(trainer_token)
        ).json()
    ]
    assert "상담 요청이 취소됐어요" in titles
    # 요청이 사라진 것과 알림이 남은 것이 같은 트랜잭션이어야 한다.
    count = client.get(
        "/v1/trainer/consultations/pending-count", headers=_auth(trainer_token)
    )
    assert count.json()["count"] == 0


def test_cancel_without_target_trainer_creates_no_notification(client, db_session):
    """대상 트레이너가 지워진 요청은 알릴 곳이 없다 — 알림을 만들지 않는다."""
    member_id, member_token = _member(client)
    consultation_id = f"decide-orphan-{uuid4().hex[:10]}"
    db_session.add(
        ConsultationRequest(
            id=consultation_id,
            member_id=member_id,
            target_type="gym",
            trainer_id=None,
            exercise_goal="weight_loss",
            health_purpose_type="general",
            preferred_date=(date.today() + timedelta(days=1)).isoformat(),
            preferred_time_slot="19:00",
            status="pending",
        )
    )
    db_session.commit()
    before = db_session.query(Notification).count()

    response = client.delete(
        f"/v1/consultations/{consultation_id}", headers=_auth(member_token)
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "cancelled"
    assert db_session.query(Notification).count() == before


def test_member_cannot_read_trainer_inbox(client):
    _, member_token = _member(client)
    response = client.get("/v1/trainer/consultations", headers=_auth(member_token))
    assert response.status_code == 403


# --- 승인 -------------------------------------------------------------------


def test_accept_confirms_the_consultation_without_linking(client, db_session):
    """수락은 상담 일정 확정이다 — 담당 링크·로스터·헬스장은 그대로다. (#2584)

    수락만으로 담당이 되면 등록하지 않은 사람의 식단·기록까지 트레이너에게 열린다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )

    body = _accept(client, trainer_token, consultation_id)

    assert body["status"] == "accepted"
    assert body["client_connected"] is False
    assert body["schedule_created"] is True
    assert body["schedule_id"]
    assert body["decided_by"] == trainer.id
    assert body["decided_at"]

    assert member_id not in _roster_ids(client, trainer_token)
    assert (
        db_session.query(TrainerClient)
        .filter(TrainerClient.member_id == member_id)
        .count()
        == 0
    )
    # 등록하지 않은 회원의 '내 헬스장' 이 상담 한 번으로 바뀌지 않는다.
    assert db_session.get(MemberGym, member_id) is None
    # 연결 전 회원은 담당 트레이너 일정을 받지 않는다 — 수락된 상담은 내 상담 요청에서 본다.
    sessions = client.get("/v1/me/coach/sessions", headers=_auth(member_token))
    assert sessions.status_code == 200, sessions.text
    assert sessions.json() == []


def test_accept_books_a_consultation_on_the_slot_the_member_picked(
    client, db_session
):
    """수락하면 회원이 고른 자리 그대로 `상담` 일정이 잡힌다. (#1873, #2584)

    자리는 `1:1 PT` 자리를 함께 쓰지만 잡히는 것은 상담이다. 메모 칸은 트레이너만
    보는 상담 메모 자리라 회원 문의 글을 넣지 않는다 — 문의 글은 요청에 남고
    `consultation` 으로 따로 온다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    slot = _open_slot(trainer.id)
    created = client.post(
        "/v1/consultations",
        headers=_auth(member_token),
        json={
            "trainer_id": trainer.id,
            "exercise_goal": "weight_loss",
            "health_purpose_type": "general",
            "health_purpose_detail": None,
            "slot_id": slot.id,
            "message": "상담 부탁드립니다.",
            "data_sharing_consent": True,
        },
    )
    assert created.status_code == 201, created.text
    consultation_id = created.json()["id"]

    body = _accept(client, trainer_token, consultation_id)

    local = slot.starts_at.astimezone(SEOUL)
    session = (
        db_session.query(TrainerSchedule)
        .filter_by(trainer_id=trainer.id, member_id=member_id)
        .one()
    )
    assert session.id == body["schedule_id"]
    assert session.consultation_id == consultation_id
    assert session.date == local.date().isoformat()
    assert session.time == local.strftime("%H:%M")
    assert session.type == "상담"
    assert session.note == ""
    assert session.duration_minutes == slot.duration_minutes
    assert session.status == "예정"


def test_accepted_consultation_shows_on_the_schedule_before_linking(
    client, db_session
):
    """연결 전 회원의 상담 일정도 트레이너 스케줄에 보인다. (#2584)

    스케줄은 회원이 붙은 일정을 활성 담당일 때만 보여 준다(#2281). 수락이 연결을
    만들지 않으면 그 규칙에 걸려 상담 일정이 사라진다. 카드가 그릴 `상담 요청
    내용` 도 함께 온다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    schedule_id = _accept(client, trainer_token, consultation_id)["schedule_id"]
    day = db_session.get(TrainerSchedule, schedule_id).date

    rows = {r["id"]: r for r in _schedule_on(client, trainer_token, day)}

    assert schedule_id in rows
    row = rows[schedule_id]
    assert row["type"] == "상담"
    assert row["note"] == ""
    assert row["consultation"] == {
        "id": consultation_id,
        "exercise_goal": "weight_loss",
        "health_purpose_type": "general",
        "health_purpose_detail": None,
        "message": "상담 부탁드립니다.",
    }
    dates = client.get(
        "/v1/trainer/schedule/booked-dates", headers=_auth(trainer_token)
    )
    assert day in dates.json()


def test_trainer_writes_a_consultation_memo_before_linking(client, db_session):
    """연결 전 회원과의 상담에도 트레이너가 상담 메모를 적을 수 있다. (#2574, #2584)

    일정 수정은 활성 담당이 아니면 404 인데(#2281), 상담 요청으로 생긴 상담
    일정은 그 경계 밖이다 — 스케줄에 보이는데 손댈 수 없으면 안 된다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    schedule_id = _accept(client, trainer_token, consultation_id)["schedule_id"]

    updated = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        json={"note": "주 3회 희망, 무릎 통증 확인"},
        headers=_auth(trainer_token),
    )

    assert updated.status_code == 200, updated.text
    assert updated.json()["note"] == "주 3회 희망, 무릎 통증 확인"


def test_code_pairing_after_accept_continues_the_consultation(client, db_session):
    """상담 뒤 코드로 연결하면 상담 일정이 담당 회원 일정으로 그대로 이어진다. (#2584)

    회원 쪽에는 상담 메모·요청 내용이 가지 않는다(#2515) — 트레이너만 보는 값이다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    gym_id = _gym_id_of(db_session, trainer)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    schedule_id = _accept(client, trainer_token, consultation_id)["schedule_id"]
    memo = client.put(
        f"/v1/trainer/schedule/{schedule_id}",
        json={"note": "트레이너만 보는 상담 메모"},
        headers=_auth(trainer_token),
    )
    assert memo.status_code == 200, memo.text

    _pair_by_code(client, member_token, trainer_token)

    assert member_id in _roster_ids(client, trainer_token)
    # 헬스장 연결은 코드 연결이 한다.
    db_session.expire_all()
    assert db_session.get(MemberGym, member_id).gym_id == gym_id
    day = db_session.get(TrainerSchedule, schedule_id).date
    of_member = client.get(
        f"/v1/trainer/schedule?member_id={member_id}&from={day}&to={day}",
        headers=_auth(trainer_token),
    )
    assert of_member.status_code == 200, of_member.text
    assert schedule_id in {r["id"] for r in of_member.json()}
    mine = client.get("/v1/me/coach/sessions", headers=_auth(member_token))
    assert mine.status_code == 200, mine.text
    row = next(r for r in mine.json() if r["id"] == schedule_id)
    assert row["type"] == "상담"
    assert row["note"] == ""
    assert row["consultation"] is None


def test_unlinked_members_consultation_stays_named_but_pt_is_anonymous(
    client, db_session
):
    """해제된 담당의 PT 일정은 익명이고(#2589) 상담 일정은 이름 그대로 남는다(#2584).

    회원이 직접 신청한 상담은 담당과 별개라, 해제 때 남은 일정을 거둘 때도
    취소하지 않는다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    consult_id = _accept(client, trainer_token, consultation_id)["schedule_id"]
    consult = db_session.get(TrainerSchedule, consult_id)
    day = consult.date
    _pair_by_code(client, member_token, trainer_token)
    # 상담 시각(지금+48h)과 겹치지 않는 시각에 PT 를 잡는다 — 겹치면 409(#2284).
    pt_time = "20:00" if consult.time < "12:00" else "06:00"
    pt = client.post(
        "/v1/trainer/schedule",
        json={
            "date": day,
            "time": pt_time,
            "client_name": "상담 회원",
            "member_id": member_id,
            "type": "1:1 PT",
            "duration_minutes": 60,
        },
        headers=_auth(trainer_token),
    )
    assert pt.status_code in (200, 201), pt.text

    assert client.delete("/v1/me/coach", headers=_auth(member_token)).status_code == 204

    rows = {r["id"]: r for r in _schedule_on(client, trainer_token, day)}
    consult = rows[consult_id]
    assert consult["member_detached"] is False
    assert consult["client_name"] == "상담 회원"
    assert consult["status"] == "예정"
    assert consult["consultation"]["id"] == consultation_id
    pt_row = rows[pt.json()["id"]]
    assert pt_row["member_detached"] is True
    assert pt_row["client_name"] == "해제 회원"


def test_accept_ignores_a_schedule_the_client_tries_to_dictate(client, db_session):
    """옛 클라이언트가 날짜·시각을 함께 보내도 자리가 정한 시각이 이긴다. (#1873)

    승인 본문에서 그 인자들을 걷어냈으므로 서버는 조용히 무시한다 — 시각을 정하는
    사람이 둘이면 회원이 모르는 일정에 묶인다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    slot = _open_slot(trainer.id)
    local = slot.starts_at.astimezone(SEOUL)
    # 넘기는 시각은 자리 시각에서 한 시간 비킨다 — 고정값(05:00)이면 KST 05:00 에
    # 도는 CI 에서 자리 시각과 같아져 두 단언이 함께 성립할 수 없다(#2727).
    dictated = (local + timedelta(hours=1)).strftime("%H:%M")
    created = client.post(
        "/v1/consultations",
        headers=_auth(member_token),
        json={
            "trainer_id": trainer.id,
            "exercise_goal": "weight_loss",
            "health_purpose_type": "general",
            "health_purpose_detail": None,
            "slot_id": slot.id,
            "message": None,
            "data_sharing_consent": True,
        },
    )
    assert created.status_code == 201, created.text

    response = client.post(
        f"/v1/trainer/consultations/{created.json()['id']}/accept",
        headers=_auth(trainer_token),
        json={
            "date": (date.today() + timedelta(days=9)).isoformat(),
            "time": dictated,
            "type": "상담",
            "duration_minutes": 30,
        },
    )

    assert response.status_code == 200, response.text
    session = (
        db_session.query(TrainerSchedule)
        .filter_by(trainer_id=trainer.id, member_id=member_id)
        .one()
    )
    assert session.time == local.strftime("%H:%M")
    assert session.time != dictated


def test_accept_notifies_the_member(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )

    client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(trainer_token),
        json={},
    )

    alerts = client.get("/v1/notifications", headers=_auth(member_token))
    assert alerts.status_code == 200, alerts.text
    accepted = [
        a for a in alerts.json() if a["title"] == "상담 요청이 승인됐어요"
    ]
    assert accepted
    # 수락은 담당 연결이 아니다 — "담당으로 연결" 로 읽히면 안 된다(#2584).
    assert "담당" not in accepted[0]["body"]
    # 결과는 내 상담 요청으로 간다(#2067). 담당 연결 알림과 같은 갈래였을 때는
    # 운동 탭으로 가서 결과를 따로 찾아야 했다.
    assert accepted[0]["category"] == "consult_decision"
    assert accepted[0]["action"]["target"] == "consultations"


def test_accept_twice_conflicts(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )

    first = client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(trainer_token),
        json={},
    )
    second = client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(trainer_token),
        json={},
    )

    assert first.status_code == 200, first.text
    assert second.status_code == 409, second.text


def test_accept_is_allowed_for_a_member_coached_elsewhere(client, db_session):
    """다른 트레이너의 담당 회원이어도 상담은 수락된다 — 담당은 그대로다. (#2584)

    수락은 연결이 아니므로 막을 이유가 없다. 담당을 옮기는 결정은 코드 연결이
    막거나 받는다(회원당 활성 담당 1명).

    연결된 회원은 다른 트레이너에게 새로 신청하지 못하므로(#2611), 신청을 먼저
    내 두고 그 사이 다른 트레이너와 코드로 연결된 경우를 본다.
    """
    first_trainer, first_token = _trainer(client, db_session)
    second_trainer, second_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    request = _request_consultation(
        client, member_token, trainer_id=second_trainer.id
    )
    _pair_by_code(client, member_token, first_token)

    body = _accept(client, second_token, request)

    assert body["status"] == "accepted"
    db_session.expire_all()
    links = (
        db_session.query(TrainerClient)
        .filter(TrainerClient.member_id == member_id, TrainerClient.active.is_(True))
        .all()
    )
    assert [link.trainer_id for link in links] == [first_trainer.id]
    assert member_id not in _roster_ids(client, second_token)


def test_commit_decision_maps_a_constraint_race_to_already_decided():
    """경합으로 제약에 걸린 커밋은 500 이 아니라 '이미 처리됨'(409)이 된다.

    아래의 두 트레이너 테스트는 TestClient 가 동기라 **진짜 경합을 재현하지 못한다**
    — 늦은 요청은 잠금이 없어도 `status != pending` 에서 걸린다. 실제 경합에서만
    도달하는 것은 커밋의 IntegrityError 경로이므로, 그 매핑을 여기서 직접 덮는다.
    """

    class _RacingSession:
        """커밋이 제약 위반으로 실패하는 세션. 롤백 여부까지 확인한다."""

        def __init__(self) -> None:
            self.rolled_back = False

        def commit(self) -> None:
            raise IntegrityError("INSERT", {}, Exception("unique violation"))

        def rollback(self) -> None:
            self.rolled_back = True

    session = _RacingSession()

    with pytest.raises(consultation_service.ConsultationAlreadyDecided):
        consultation_service._commit_decision(session)

    # 롤백하지 않으면 세션이 실패한 트랜잭션에 갇혀 이후 쿼리가 전부 죽는다.
    assert session.rolled_back is True


def test_same_gym_colleague_can_neither_see_nor_take_the_request(
    client, db_session
):
    """같은 헬스장 동료라도 남에게 간 요청은 보지도 가져가지도 못한다.

    예전에는 헬스장으로 온 요청을 소속 누구나 받을 수 있어, 회원이 지목하지 않은
    트레이너가 담당이 될 수 있었다.
    """
    gym = _gym(db_session)
    target, target_token = _trainer(client, db_session, gym=gym)
    colleague, colleague_token = _trainer(client, db_session, gym=gym)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=target.id
    )

    assert target.id != colleague.id
    inbox = client.get(
        "/v1/trainer/consultations", headers=_auth(colleague_token)
    )
    assert consultation_id not in {item["id"] for item in inbox.json()}

    stolen = client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(colleague_token),
        json={},
    )
    mine = client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(target_token),
        json={},
    )

    assert stolen.status_code == 404, stolen.text
    assert mine.status_code == 200, mine.text


def test_accept_for_an_existing_client_keeps_the_link(client, db_session):
    """이미 담당 중인 회원의 상담(재상담·점검)을 수락해도 연결은 그대로다. (#2585)"""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    _pair_by_code(client, member_token, trainer_token)
    request = _request_consultation(client, member_token, trainer_id=trainer.id)

    _accept(client, trainer_token, request)

    db_session.expire_all()
    links = (
        db_session.query(TrainerClient)
        .filter(TrainerClient.member_id == member_id)
        .all()
    )
    assert len(links) == 1
    assert links[0].active is True
    assert member_id in _roster_ids(client, trainer_token)


def test_linked_member_consultation_leaves_the_link_as_is(client, db_session):
    """담당 트레이너에게 낸 상담을 수락해도 연결 상태는 바뀌지 않는다. (#2585)

    회원 앱은 담당 트레이너에게도 상담을 요청할 수 있고, 이미 동의한 연결이라
    동의를 다시 묻지 않고 보낸다. 수락이 링크를 새로 만들거나, 링크의 동의 시각을
    이번 신청 시각으로 덮으면 연결이 한 번 더 맺어진 것처럼 남는다. 연결은 코드로
    만든다 — 상담 수락은 연결을 만들지 않는다(#2584).
    """
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    _pair_by_code(client, member_token, trainer_token)
    db_session.expire_all()
    link = db_session.scalar(
        select(TrainerClient).where(TrainerClient.member_id == member_id)
    )
    link_id, consented_at, goal = link.id, link.data_consent_at, link.goal

    request = _request_consultation(client, member_token, trainer_id=trainer.id)
    accepted = client.post(
        f"/v1/trainer/consultations/{request}/accept",
        headers=_auth(trainer_token),
        json={},
    )

    assert accepted.status_code == 200, accepted.text
    db_session.expire_all()
    links = db_session.scalars(
        select(TrainerClient).where(TrainerClient.member_id == member_id)
    ).all()
    assert [row.id for row in links] == [link_id]
    assert links[0].active is True
    assert links[0].data_consent_at == consented_at
    assert links[0].goal == goal


def _consultation_payload(trainer_id: str) -> dict:
    return {
        "trainer_id": trainer_id,
        "exercise_goal": "weight_loss",
        "health_purpose_type": "general",
        "health_purpose_detail": None,
        "slot_id": _open_slot(trainer_id).id,
        "message": "상담 부탁드립니다.",
        "data_sharing_consent": True,
    }


def test_linked_member_cannot_request_another_trainer(client, db_session):
    """담당이 있는 회원은 다른 트레이너에게 상담을 낼 수 없다. (#2611)

    같은 헬스장 동료든 다른 헬스장 트레이너든 같다. 대기 중복 409 와 섞이지 않게
    `detail.code` 를 싣고, 요청 행을 남기지 않는다.
    """
    gym = _gym(db_session)
    coach, coach_token = _trainer(client, db_session, gym=gym)
    colleague, _ = _trainer(client, db_session, gym=gym)
    elsewhere, _ = _trainer(client, db_session)
    member_id, member_token = _member(client)
    _pair_by_code(client, member_token, coach_token)

    for target in (colleague, elsewhere):
        payload = _consultation_payload(target.id)
        response = client.post(
            "/v1/consultations", headers=_auth(member_token), json=payload
        )

        assert response.status_code == 409, response.text
        assert response.json()["detail"]["code"] == "linked_to_other_trainer"
    db_session.expire_all()
    assert (
        db_session.query(ConsultationRequest)
        .filter(ConsultationRequest.member_id == member_id)
        .count()
        == 0
    )


def test_member_can_request_another_trainer_after_disconnecting(client, db_session):
    """담당 연결을 해제하면 다른 트레이너에게 다시 상담을 낼 수 있다. (#2611)"""
    _, coach_token = _trainer(client, db_session)
    other, _ = _trainer(client, db_session)
    _, member_token = _member(client)
    _pair_by_code(client, member_token, coach_token)

    disconnected = client.delete("/v1/me/coach/trainer", headers=_auth(member_token))
    assert disconnected.status_code == 204, disconnected.text

    _request_consultation(client, member_token, trainer_id=other.id)


def test_accept_foreign_request_is_not_found(client, db_session):
    """남의 요청은 403 이 아니라 404 — id 존재 여부를 알려 주지 않는다."""
    _, outsider_token = _trainer(client, db_session)
    target_trainer, _ = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=target_trainer.id
    )

    response = client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(outsider_token),
        json={},
    )

    assert response.status_code == 404, response.text


# --- 거절 -------------------------------------------------------------------


def test_reject_records_the_reason_and_creates_no_link(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )

    response = client.post(
        f"/v1/trainer/consultations/{consultation_id}/reject",
        headers=_auth(trainer_token),
        json={"note": "  이번 달은 정원이 찼어요  "},
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "rejected"
    assert body["decision_note"] == "이번 달은 정원이 찼어요"

    assert (
        db_session.query(TrainerClient)
        .filter(TrainerClient.member_id == member_id)
        .count()
        == 0
    )
    alerts = client.get("/v1/notifications", headers=_auth(member_token)).json()
    rejected = [a for a in alerts if a["title"] == "상담 요청이 거절됐어요"]
    assert rejected and rejected[0]["body"] == "이번 달은 정원이 찼어요"
    # 사유를 보여 주는 곳이 내 상담 요청이다(#2067).
    assert rejected[0]["action"]["target"] == "consultations"


def test_member_sees_the_reason_but_never_the_deciding_trainer(
    client, db_session
):
    """회원 응답에는 사유·처리 시각만 싣고 처리자 id 는 싣지 않는다. (#473)

    회원에게 필요한 것은 결과와 이유이지 누가 눌렀는지가 아니다. 트레이너 인박스
    쪽에는 처리 이력으로 남는다.
    """
    gym = _gym(db_session)
    trainer, trainer_token = _trainer(client, db_session, gym=gym)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )

    client.post(
        f"/v1/trainer/consultations/{consultation_id}/reject",
        headers=_auth(trainer_token),
        json={"note": "이번 달은 정원이 찼어요"},
    )

    mine = client.get("/v1/consultations/me", headers=_auth(member_token))

    assert mine.status_code == 200, mine.text
    row = next(r for r in mine.json() if r["id"] == consultation_id)
    assert row["status"] == "rejected"
    assert row["decision_note"] == "이번 달은 정원이 찼어요"
    assert row["decided_at"] is not None
    assert "decided_by" not in row
    # 트레이너 인박스 쪽에는 그대로 남아 있어야 한다(누가 가져갔는지 이력).
    inbox = client.get(
        "/v1/trainer/consultations?status=all", headers=_auth(trainer_token)
    )
    taken = next(r for r in inbox.json() if r["id"] == consultation_id)
    assert taken["decided_by"] == trainer.id


def test_pending_consultation_has_no_decision_fields(client, db_session):
    """대기 중인 요청은 사유·처리 시각이 비어 있다."""
    trainer, _ = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )

    mine = client.get("/v1/consultations/me", headers=_auth(member_token))

    row = next(r for r in mine.json() if r["id"] == consultation_id)
    assert row["status"] == "pending"
    assert row["decision_note"] is None
    assert row["decided_at"] is None


def test_reject_after_accept_conflicts(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    _, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    client.post(
        f"/v1/trainer/consultations/{consultation_id}/accept",
        headers=_auth(trainer_token),
        json={},
    )

    response = client.post(
        f"/v1/trainer/consultations/{consultation_id}/reject",
        headers=_auth(trainer_token),
        json={"note": "취소"},
    )

    assert response.status_code == 409, response.text


# --- 회원 건강 목표 (#1818) ----------------------------------------------------


def _member_profile(client, member_token: str) -> dict:
    response = client.get("/v1/users/me/profile", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    return response.json()


def _clear_member_profile(db_session, member_id: str) -> None:
    from app.models.models import HealthProfile

    db_session.rollback()
    db_session.query(HealthProfile).filter(HealthProfile.user_id == member_id).delete(
        synchronize_session=False
    )
    db_session.commit()


def test_accept_leaves_the_member_health_goal_alone(client, db_session):
    """수락만으로는 회원 건강 목표를 채우지 않는다 — 연결 전이다. (#2584)"""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    try:
        _accept(client, trainer_token, consultation_id)
        assert not _member_profile(client, member_token).get("conditions")
    finally:
        _clear_member_profile(db_session, member_id)


def test_code_pairing_fills_member_health_goal_from_the_consultation(
    client, db_session
):
    """목표를 고른 적 없는 회원은 코드로 연결될 때 상담 목표가 건강 목표가 된다.

    상담 수락이 연결을 만들지 않게 되면서(#2584) 목표 채우기(#1818)가 코드 연결로
    옮겨 왔다.
    """
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    consultation_id = _request_consultation(
        client, member_token, trainer_id=trainer.id
    )
    try:
        _accept(client, trainer_token, consultation_id)
        _pair_by_code(client, member_token, trainer_token)

        assert _member_profile(client, member_token)["conditions"] == "체중 감량"
        roster = client.get("/v1/trainer/clients", headers=_auth(trainer_token)).json()
        assert next(c for c in roster if c["id"] == member_id)["goal"] == "체중 감량"
        db_session.expire_all()
        link = (
            db_session.query(TrainerClient)
            .filter(
                TrainerClient.trainer_id == trainer.id,
                TrainerClient.member_id == member_id,
            )
            .one()
        )
        assert link.goal == "체중 감량"
    finally:
        _clear_member_profile(db_session, member_id)


def test_code_pairing_keeps_goals_the_member_already_picked(client, db_session):
    """이미 고른 건강 목표(마이페이지)는 상담 목표로 덮지 않는다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    try:
        saved = client.put(
            "/v1/users/me/health-goals",
            headers=_auth(member_token),
            json={"conditions": "근력 향상"},
        )
        assert saved.status_code == 200, saved.text
        consultation_id = _request_consultation(
            client, member_token, trainer_id=trainer.id
        )
        _accept(client, trainer_token, consultation_id)

        _pair_by_code(client, member_token, trainer_token)

        assert _member_profile(client, member_token)["conditions"] == "근력 향상"
    finally:
        _clear_member_profile(db_session, member_id)
