"""트레이너 탈퇴. (#505) DB 필요.

회원은 `DELETE /users/me` 로 탈퇴할 수 있었지만 트레이너에게는 같은 경로가 없어,
한번 만든 계정을 지울 방법이 없었다(#475 로 생성 경로가 열린 뒤로는 더더욱).

시드 트레이너를 지우면 다른 테스트가 무너지므로, 여기서는 매번 **새 트레이너를
만들어** 그 계정을 지운다.
"""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select

#: 이 파일이 만드는 계정의 비밀번호. 탈퇴 본인 확인(#3039)에도 같은 값을 보낸다.
PASSWORD = "pw!12345"


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _delete_me(client, token: str):
    """트레이너 탈퇴 — 본인 확인으로 현재 비밀번호를 함께 보낸다."""
    return client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_h(token),
    )


def _login(client, email: str, password: str) -> str:
    res = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


@pytest.fixture()
def gym_id(db_session) -> str:
    """새 트레이너가 소속으로 고를 헬스장. 테스트가 끝나면 지운다."""
    from app.models import models

    gym = models.Place(
        id=f"place-del-{uuid4().hex[:10]}",
        name="탈퇴 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(gym)
    db_session.commit()

    yield gym.id

    place = db_session.get(models.Place, gym.id)
    if place is not None:
        db_session.delete(place)
        db_session.commit()


def _register_member(client) -> tuple[str, str]:
    """새 회원과 토큰. 시드 회원은 이미 담당 트레이너가 있어
    `uq_trainer_client_active_member` 에 걸린다."""
    email = f"del-member-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "탈퇴 테스트 회원"},
    )
    token = _login(client, email, PASSWORD)
    me = client.get("/v1/users/me", headers=_h(token))
    assert me.status_code == 200, me.text
    return token, me.json()["id"]


@pytest.fixture()
def make_trainer(client, db_session):
    """트레이너를 만들고, 테스트가 **실패해도** 남지 않게 치운다.

    테스트 본문에서 만들고 본문에서 지우면, 중간에 실패한 실행이 계정을 남긴다.
    남은 트레이너는 이름이 같아 `test_seeded_trainers_cover_every_gym` 의 중복
    검사를 깨뜨린다 — 실제로 겪었다.
    """
    from app.models import models

    created: list[str] = []

    def _make(gym_id: str) -> tuple[str, str]:
        email = f"del-trainer-{uuid4().hex[:8]}@oncare.com"
        res = client.post(
            "/v1/auth/trainer/register",
            json={
                "email": email,
                "password": PASSWORD,
                "name": f"탈퇴 트레이너 {uuid4().hex[:4]}",
            },
        )
        assert res.status_code in (200, 201), res.text
        token = _login(client, email, PASSWORD)
        # 소속은 가입 뒤에 고른다(#1627).
        picked = client.put(
            "/v1/trainer/me/gym", headers=_h(token), json={"gym_id": gym_id}
        )
        assert picked.status_code == 200, picked.text
        me = client.get("/v1/trainer/me", headers=_h(token))
        assert me.status_code == 200, me.text
        created.append(me.json()["id"])
        return token, me.json()["id"]

    yield _make

    for trainer_id in created:
        row = db_session.get(models.User, trainer_id)
        if row is None:
            continue  # 테스트가 이미 지웠다 — 정상 경로.
        from app.services.trainer import profile as trainer_profile_service

        trainer_profile_service.delete_trainer_account(db_session, row)


def test_trainer_can_delete_their_account(client, db_session, gym_id, make_trainer):
    from app.models import models

    token, trainer_id = make_trainer(gym_id)

    deleted = client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_h(token),
    )
    assert deleted.status_code == 200, deleted.text

    db_session.expire_all()
    assert db_session.get(models.User, trainer_id) is None
    # 프로필도 CASCADE 로 함께 사라진다.
    assert (
        db_session.scalar(
            select(models.TrainerProfile).where(
                models.TrainerProfile.trainer_id == trainer_id
            )
        )
        is None
    )


def test_deleted_trainer_cannot_sign_in_again(client, gym_id, make_trainer):
    email_token, _ = make_trainer(gym_id)
    client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_h(email_token),
    )

    # 지운 계정의 토큰으로는 아무것도 읽을 수 없다.
    assert client.get("/v1/trainer/me", headers=_h(email_token)).status_code in (
        401,
        403,
        404,
    )


def test_deleting_with_clients_unlinks_and_notifies_them(
    client, db_session, gym_id, make_trainer
):
    """담당 회원이 남아 있어도 막지 않되, 회원이 모르게 사라지지 않는다."""
    from app.models import models

    token, trainer_id = make_trainer(gym_id)
    _, member_id = _register_member(client)
    link = models.TrainerClient(
        id=f"tc-{uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        goal="테스트",
        active=True,
        sort_order=1,
    )
    db_session.add(link)
    db_session.commit()

    before = db_session.scalars(
        select(models.Notification).where(
            models.Notification.user_id == member_id
        )
    ).all()

    deleted = client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_h(token),
    )
    assert deleted.status_code == 200, deleted.text

    db_session.expire_all()
    # 담당 링크는 CASCADE 로 사라진다.
    assert (
        db_session.scalar(
            select(models.TrainerClient).where(
                models.TrainerClient.trainer_id == trainer_id
            )
        )
        is None
    )
    after = db_session.scalars(
        select(models.Notification).where(
            models.Notification.user_id == member_id
        )
    ).all()
    assert len(after) == len(before) + 1
    assert any("연결이 해제" in row.title for row in after)


def _link(db_session, trainer_id: str, member_id: str, *, active: bool):
    from app.models import models

    db_session.add(
        models.TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            goal="테스트",
            active=active,
            sort_order=1,
        )
    )
    db_session.commit()


def _member_titles(db_session, member_id: str) -> list[str]:
    from app.models import models

    db_session.expire_all()
    return [
        row.title
        for row in db_session.scalars(
            select(models.Notification).where(
                models.Notification.user_id == member_id
            )
        ).all()
    ]


def test_deleting_does_not_notify_past_clients(
    client, db_session, gym_id, make_trainer
):
    """담당이 이미 끝난 회원에게는 탈퇴 알림을 보내지 않는다(#3024).

    오래전에 끝난 관계를 "담당 트레이너 연결이 해제됐어요" 로 다시 들으면
    지금 담당이 끊긴 것으로 읽힌다.
    """
    token, trainer_id = make_trainer(gym_id)
    _, past_member_id = _register_member(client)
    _link(db_session, trainer_id, past_member_id, active=False)
    before = _member_titles(db_session, past_member_id)

    assert _delete_me(client, token).status_code == 200

    assert _member_titles(db_session, past_member_id) == before


def test_deleting_notifies_active_clients_even_with_switches_off(
    client, db_session, gym_id, make_trainer
):
    """'트레이너 메시지' 를 꺼도 탈퇴 알림은 온다 — 끌 수 없는 알림이다(#3024)."""
    token, trainer_id = make_trainer(gym_id)
    member_token, member_id = _register_member(client)
    switched = client.put(
        "/v1/users/me/notification-settings",
        headers=_h(member_token),
        json={"trainer_message": False, "exercise_reminder": False},
    )
    assert switched.status_code == 200, switched.text
    _link(db_session, trainer_id, member_id, active=True)

    assert _delete_me(client, token).status_code == 200

    assert "담당 트레이너 연결이 해제됐어요" in _member_titles(db_session, member_id)


def test_a_past_client_with_a_booking_hears_only_about_the_booking(
    client, db_session, gym_id, make_trainer
):
    """담당이 끝났어도 예약이 남아 있으면 '예약 취소' 한 건만 받는다(#3024)."""
    from app.models import models

    token, trainer_id = make_trainer(gym_id)
    member_token, member_id = _register_member(client)
    _link(db_session, trainer_id, member_id, active=True)
    slot = client.post(
        "/v1/trainer/reservation-slots",
        headers=_h(token),
        json={
            "starts_at": (
                datetime.now(timezone.utc) + timedelta(days=5)
            ).isoformat(),
            "capacity": 1,
        },
    )
    assert slot.status_code == 201, slot.text
    booked = client.post(
        "/v1/reservations",
        headers=_h(member_token),
        json={"slot_id": slot.json()["id"]},
    )
    assert booked.status_code == 201, booked.text
    # 예약은 남긴 채 담당만 끝난 상태로 만든다.
    link = db_session.scalar(
        select(models.TrainerClient).where(
            models.TrainerClient.trainer_id == trainer_id,
            models.TrainerClient.member_id == member_id,
        )
    )
    link.active = False
    db_session.commit()
    before = _member_titles(db_session, member_id)

    assert _delete_me(client, token).status_code == 200

    added = Counter(_member_titles(db_session, member_id)) - Counter(before)
    assert added == Counter({"예약한 PT가 취소됐어요": 1})


def test_an_active_client_with_a_booking_gets_one_notice(
    client, db_session, gym_id, make_trainer
):
    """담당 중이면서 예약도 있는 회원은 '연결 해제' 한 건만 받는다."""
    token, trainer_id = make_trainer(gym_id)
    member_token, member_id = _register_member(client)
    _link(db_session, trainer_id, member_id, active=True)
    slot = client.post(
        "/v1/trainer/reservation-slots",
        headers=_h(token),
        json={
            "starts_at": (
                datetime.now(timezone.utc) + timedelta(days=5)
            ).isoformat(),
            "capacity": 1,
        },
    )
    assert slot.status_code == 201, slot.text
    booked = client.post(
        "/v1/reservations",
        headers=_h(member_token),
        json={"slot_id": slot.json()["id"]},
    )
    assert booked.status_code == 201, booked.text
    before = len(_member_titles(db_session, member_id))

    assert _delete_me(client, token).status_code == 200

    titles = _member_titles(db_session, member_id)
    assert len(titles) == before + 1
    assert "담당 트레이너 연결이 해제됐어요" in titles


def test_deleting_a_trainer_with_bookings_clears_them(
    client, db_session, gym_id, make_trainer
):
    """예약은 회원·슬롯·일정을 RESTRICT 로 참조한다 — 먼저 치우지 않으면 삭제가 막힌다."""
    from app.models import models

    token, trainer_id = make_trainer(gym_id)
    member_token, member_id = _register_member(client)
    # 예약하려면 담당 링크가 있어야 한다(reserve 의 조건).
    db_session.add(
        models.TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            goal="테스트",
            active=True,
            sort_order=1,
        )
    )
    db_session.commit()

    slot = client.post(
        "/v1/trainer/reservation-slots",
        headers=_h(token),
        json={
            "starts_at": (
                datetime.now(timezone.utc) + timedelta(days=5)
            ).isoformat(),
            "capacity": 1,
        },
    )
    assert slot.status_code == 201, slot.text
    booked = client.post(
        "/v1/reservations",
        headers=_h(member_token),
        json={"slot_id": slot.json()["id"]},
    )
    assert booked.status_code == 201, booked.text
    reservation_id = booked.json()["id"]
    schedule_id = booked.json()["schedule_id"]

    deleted = client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_h(token),
    )
    assert deleted.status_code == 200, deleted.text

    db_session.expire_all()
    assert db_session.get(models.TrainerReservation, reservation_id) is None
    # 슬롯과 그 예약이 만든 일정도 CASCADE 로 사라진다.
    assert db_session.get(models.TrainerReservationSlot, slot.json()["id"]) is None
    assert db_session.get(models.TrainerSchedule, schedule_id) is None


def test_a_member_cannot_delete_a_trainer_account(client):
    """회원 토큰으로는 트레이너 탈퇴 경로를 쓸 수 없다."""
    member_token = _login(client, "jisu@oncare.com", "oncare123")
    assert (
        client.delete("/v1/trainer/me", headers=_h(member_token)).status_code == 403
    )


def test_trainer_deletion_keeps_chosen_reasons_apart_from_members(
    client, db_session, gym_id, make_trainer
):
    """트레이너가 고른 탈퇴 사유는 `trainer_` 를 붙여 남고, 모르는 값은 버린다(#2264).

    회원 사유와 같은 표라 코드만으로 누가 떠났는지 갈라야 한다. 계정과는
    잇지 않는다 — 계정은 이 요청으로 사라진다.
    """
    from app.models import models

    token, _ = make_trainer(gym_id)
    marker = datetime.now(timezone.utc) - timedelta(seconds=1)

    deleted = client.request(
        "DELETE",
        "/v1/trainer/me",
        headers=_h(token),
        json={
            "reasons": ["leaving_work", "missing_feature", "not-a-reason"],
            "current_password": PASSWORD,
        },
    )
    assert deleted.status_code == 200, deleted.text

    db_session.expire_all()
    stored = set(
        db_session.scalars(
            select(models.AccountDeletionReason.reason).where(
                models.AccountDeletionReason.created_at >= marker,
                models.AccountDeletionReason.reason.like("trainer_%"),
            )
        ).all()
    )
    assert {"trainer_leaving_work", "trainer_missing_feature"} <= stored
    assert "trainer_not-a-reason" not in stored


def test_trainer_deletion_without_reasons_still_works(
    client, gym_id, make_trainer
):
    """사유는 탈퇴를 막는 조건이 아니다 — 본문 없이도 지워진다(#2264)."""
    token, _ = make_trainer(gym_id)
    deleted = client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_h(token),
    )
    assert deleted.status_code == 200, deleted.text
