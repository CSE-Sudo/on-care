"""포인트 사용처·쿠폰 — 교환, 재등록 쿠폰 규칙, 트레이너 사용 처리, 만료, 담당 해제 반환.
(#1787) DB 필요(로컬 skip, CI 실행).

새로 가입한 회원에 포인트를 넣고 **테스트마다 만든 트레이너**를 담당으로 붙여 확인한다.
시드 트레이너(`trainer-demo`)에 회원을 붙이면 데모 로스터 개수를 세는 테스트가 깨지고,
다른 테스트가 만든 쿠폰·내역과도 섞인다.
"""
from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, time, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select, update

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    AuditLog,
    HealthProfile,
    Notification,
    PointsCoupon,
    PointsLedger,
    TrainerClient,
    TrainerProfile,
    User,
)

TRAINER_NAME = "쿠폰 트레이너"
GYM_NAME = "쿠폰 테스트짐"


def _headers(user_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _make_trainer(db_session, name: str = TRAINER_NAME) -> str:
    trainer_id = f"trainer-{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name=name,
            hashed_password="unused",
            role="trainer",
        )
    )
    # 프로필은 사용자 행이 커밋된 뒤에 넣는다 — 한 번에 넣으면 FK 순서가 어긋난다.
    db_session.commit()
    db_session.add(TrainerProfile(trainer_id=trainer_id, gym_name=GYM_NAME))
    db_session.commit()
    return trainer_id


def _drop_user(db_session, user_id: str) -> None:
    """만든 트레이너를 지운다. 담당 링크·프로필은 CASCADE, 쿠폰의 trainer_id 는 NULL."""
    db_session.rollback()
    db_session.expire_all()
    user = db_session.get(User, user_id)
    if user is not None:
        db_session.delete(user)
        db_session.commit()


@pytest.fixture
def trainer_id(db_session) -> Iterator[str]:
    """이 테스트만 쓰는 트레이너."""
    created = _make_trainer(db_session)
    yield created
    _drop_user(db_session, created)


def _new_member(client, db_session, points: int = 0) -> tuple[str, dict[str, str]]:
    email = f"cpn-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    _set_points(db_session, member_id, points)
    return member_id, headers


def _set_points(db_session, member_id: str, points: int) -> None:
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()


def _link(db_session, member_id: str, trainer_id: str, *, active: bool = True):
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=active,
        )
    )
    db_session.commit()


def _reactivate(db_session, member_id: str) -> None:
    """해제된 링크를 되살린다. (trainer, member) 유일이라 새로 넣지 않는다."""
    db_session.execute(
        update(TrainerClient)
        .where(TrainerClient.member_id == member_id)
        .values(active=True)
    )
    db_session.commit()


def _balance(client, headers) -> int:
    r = client.get("/v1/users/me/health", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()["activity_points"]


def _shop_item(client, headers, item: str) -> dict:
    r = client.get("/v1/me/points/shop", headers=headers)
    assert r.status_code == 200, r.text
    return next(i for i in r.json()["items"] if i["id"] == item)


def _exchange(client, headers, item: str, request_id: str | None = None):
    body: dict[str, str] = {"item": item}
    if request_id is not None:
        body["client_request_id"] = request_id
    return client.post("/v1/me/points/exchange", json=body, headers=headers)


def _notifications(db_session, member_id: str, title: str) -> int:
    db_session.expire_all()
    return db_session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == member_id, Notification.title == title)
    )


def _coupon(db_session, coupon_id: str) -> PointsCoupon:
    db_session.expire_all()
    return db_session.get(PointsCoupon, coupon_id)


def _set_expiry(db_session, coupon_id: str, expires_at: datetime) -> None:
    db_session.execute(
        update(PointsCoupon)
        .where(PointsCoupon.id == coupon_id)
        .values(expires_at=expires_at)
    )
    db_session.commit()


# ---- 교환 목록 ----


def test_shop_lists_items_with_block_reasons(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=1000)

    r = client.get("/v1/me/points/shop", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["balance"] == 1000
    assert body["has_trainer"] is False
    assert [i["id"] for i in body["items"]] == [
        "pt_renewal",
        "salad_discount",
        "protein_discount",
    ]
    renewal, salad, protein = body["items"]
    assert (renewal["cost"], renewal["valid_days"], renewal["redeemer"]) == (
        5000,
        30,
        "trainer",
    )
    assert renewal["available"] is False
    assert renewal["blocked_reason"] == "no_trainer"
    assert renewal["shortfall"] == 4000
    assert salad["available"] is True and salad["blocked_reason"] is None
    assert protein["cost"] == 1000 and protein["redeemer"] == "member"

    _link(db_session, member_id, trainer_id)
    renewal = _shop_item(client, h, "pt_renewal")
    assert renewal["blocked_reason"] == "insufficient_points"
    assert renewal["shortfall"] == 4000


# ---- 교환 ----


def test_exchange_demo_coupon_spends_points(client, db_session):
    member_id, h = _new_member(client, db_session, points=1500)

    r = _exchange(client, h, "salad_discount")

    assert r.status_code == 201, r.text
    body = r.json()
    assert body["spent"] == 1000
    assert body["balance"] == 500
    coupon = body["coupon"]
    assert coupon["status"] == "issued"
    assert coupon["redeemer"] == "member"
    assert len(coupon["code"]) == 8
    assert not set(coupon["code"]) & set("01OI")
    assert coupon["days_left"] == 30
    assert coupon["expires_on"] == (clock.today() + timedelta(days=30)).isoformat()
    assert coupon["issued_on"] == clock.today_iso()
    assert _balance(client, h) == 500

    db_session.expire_all()
    spend = db_session.scalars(
        select(PointsLedger).where(
            PointsLedger.user_id == member_id,
            PointsLedger.kind == "spend",
        )
    ).all()
    assert [(row.delta, row.source_type, row.source_id) for row in spend] == [
        (-1000, "points_coupon", coupon["id"])
    ]

    listed = client.get("/v1/me/coupons", headers=h).json()
    assert [c["id"] for c in listed] == [coupon["id"]]


def test_exchange_insufficient_balance_changes_nothing(client, db_session):
    member_id, h = _new_member(client, db_session, points=900)

    r = _exchange(client, h, "protein_discount")

    assert r.status_code == 409, r.text
    assert "100P" in r.json()["detail"]
    assert _balance(client, h) == 900
    db_session.expire_all()
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(PointsCoupon)
            .where(PointsCoupon.user_id == member_id)
        )
        == 0
    )


def test_exchange_unknown_item_is_404(client, db_session):
    _, h = _new_member(client, db_session, points=9000)
    assert _exchange(client, h, "recipe_pack").status_code == 404


def test_demo_coupon_one_unused_per_kind(client, db_session):
    member_id, h = _new_member(client, db_session, points=5000)

    salad = _exchange(client, h, "salad_discount")
    assert salad.status_code == 201, salad.text
    # 같은 종류를 쓰지 않은 채로 또 받을 수 없다.
    again = _exchange(client, h, "salad_discount")
    assert again.status_code == 409
    assert _balance(client, h) == 4000
    blocked = _shop_item(client, h, "salad_discount")
    assert blocked["available"] is False
    assert blocked["blocked_reason"] == "active_coupon"
    # 다른 종류는 따로 센다.
    assert _shop_item(client, h, "protein_discount")["available"] is True
    protein = _exchange(client, h, "protein_discount")
    assert protein.status_code == 201, protein.text

    # 사용하면 같은 종류를 다시 받을 수 있다.
    salad_id = salad.json()["coupon"]["id"]
    assert client.post(f"/v1/me/coupons/{salad_id}/use", headers=h).status_code == 200
    assert _exchange(client, h, "salad_discount").status_code == 201
    # 만료돼도 다시 받을 수 있다.
    _set_expiry(
        db_session,
        protein.json()["coupon"]["id"],
        clock.now() - timedelta(minutes=1),
    )
    assert _shop_item(client, h, "protein_discount")["available"] is True
    assert _exchange(client, h, "protein_discount").status_code == 201
    assert _balance(client, h) == 1000


def test_exchange_retry_with_request_id_spends_once(client, db_session):
    _, h = _new_member(client, db_session, points=2500)
    key = f"req-{uuid4().hex}"

    first = _exchange(client, h, "salad_discount", key)
    second = _exchange(client, h, "salad_discount", key)

    assert first.status_code == 201 and second.status_code == 201
    assert first.json()["coupon"]["id"] == second.json()["coupon"]["id"]
    assert _balance(client, h) == 1500


def test_pt_renewal_requires_active_trainer(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=6000)

    assert _exchange(client, h, "pt_renewal").status_code == 409
    # 해제된(휴면) 담당 링크만 있으면 담당이 없는 것이다.
    _link(db_session, member_id, trainer_id, active=False)
    assert _exchange(client, h, "pt_renewal").status_code == 409
    assert _balance(client, h) == 6000

    _reactivate(db_session, member_id)
    r = _exchange(client, h, "pt_renewal")

    assert r.status_code == 201, r.text
    coupon = r.json()["coupon"]
    assert coupon["trainer_name"] == TRAINER_NAME
    assert coupon["gym_name"] == GYM_NAME
    assert coupon["redeemer"] == "trainer"
    assert r.json()["balance"] == 1000


def test_pt_renewal_one_unused_coupon_at_a_time(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=12000)
    _link(db_session, member_id, trainer_id)

    first = _exchange(client, h, "pt_renewal")
    assert first.status_code == 201, first.text
    second = _exchange(client, h, "pt_renewal")
    assert second.status_code == 409
    assert _balance(client, h) == 7000
    assert _shop_item(client, h, "pt_renewal")["blocked_reason"] == "active_coupon"

    redeemed = client.post(
        f"/v1/trainer/clients/{member_id}/coupons/{first.json()['coupon']['id']}/redeem",
        headers=_headers(trainer_id),
    )
    assert redeemed.status_code == 200, redeemed.text

    # 사용한 뒤에는 다음 재등록을 위해 다시 교환할 수 있다.
    assert _exchange(client, h, "pt_renewal").status_code == 201
    assert _balance(client, h) == 2000


# ---- 트레이너 사용 처리 ----


def test_trainer_redeems_once_with_notification_and_audit(
    client, db_session, trainer_id
):
    member_id, h = _new_member(client, db_session, points=5000)
    _link(db_session, member_id, trainer_id)
    coupon_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
    trainer = _headers(trainer_id)

    listed = client.get(f"/v1/trainer/clients/{member_id}/coupons", headers=trainer)
    assert listed.status_code == 200, listed.text
    assert [c["id"] for c in listed.json()] == [coupon_id]
    assert "code" not in listed.json()[0]
    assert listed.json()[0]["days_left"] == 30

    url = f"/v1/trainer/clients/{member_id}/coupons/{coupon_id}/redeem"
    first = client.post(url, headers=trainer)
    second = client.post(url, headers=trainer)

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["status"] == "used"
    assert second.json()["used_at"] == first.json()["used_at"]

    row = _coupon(db_session, coupon_id)
    assert row.status == "used"
    assert row.redeemed_by == trainer_id
    assert row.used_at is not None
    assert _notifications(db_session, member_id, "재등록 쿠폰이 사용 처리됐어요") == 1
    audits = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == "points.coupon_redeem",
            AuditLog.detail.contains(coupon_id),
        )
    ).all()
    assert len(audits) == 1
    assert audits[0].user_id == trainer_id

    # 배지가 사라진다 — 사용 가능한 쿠폰이 없다.
    assert client.get(
        f"/v1/trainer/clients/{member_id}/coupons", headers=trainer
    ).json() == []
    member_view = client.get("/v1/me/coupons", headers=h).json()
    assert member_view[0]["status"] == "used"

    notices = client.get("/v1/notifications", headers=h).json()
    redeemed_notice = next(
        n for n in notices if n["title"] == "재등록 쿠폰이 사용 처리됐어요"
    )
    assert redeemed_notice["action"] == {
        "label": "내 혜택 보기",
        "target": "my_benefits",
    }


def test_only_current_trainer_can_list_or_redeem(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=5000)
    _link(db_session, member_id, trainer_id)
    coupon_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]

    other_id = _make_trainer(db_session, name="다른 트레이너")
    other = _headers(other_id)
    try:
        assert (
            client.get(f"/v1/trainer/clients/{member_id}/coupons", headers=other)
            .status_code
            == 404
        )
        assert (
            client.post(
                f"/v1/trainer/clients/{member_id}/coupons/{coupon_id}/redeem",
                headers=other,
            ).status_code
            == 404
        )
        # 회원 계정은 트레이너 경로에 들어오지 못한다.
        assert (
            client.get(f"/v1/trainer/clients/{member_id}/coupons", headers=h)
            .status_code
            == 403
        )
    finally:
        _drop_user(db_session, other_id)
    assert _coupon(db_session, coupon_id).status == "issued"


def test_redeemers_do_not_cross(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=6000)
    _link(db_session, member_id, trainer_id)
    renewal_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
    salad_id = _exchange(client, h, "salad_discount").json()["coupon"]["id"]

    # PT 재등록 쿠폰은 회원이 스스로 사용 처리하지 못한다.
    r = client.post(f"/v1/me/coupons/{renewal_id}/use", headers=h)
    assert r.status_code == 409
    # 트레이너는 회원이 쓰는 쿠폰을 볼 수도 처리할 수도 없다.
    r = client.post(
        f"/v1/trainer/clients/{member_id}/coupons/{salad_id}/redeem",
        headers=_headers(trainer_id),
    )
    assert r.status_code == 404
    assert _coupon(db_session, renewal_id).status == "issued"
    assert _coupon(db_session, salad_id).status == "issued"


def test_member_uses_demo_coupon_once(client, db_session):
    member_id, h = _new_member(client, db_session, points=1000)
    coupon_id = _exchange(client, h, "protein_discount").json()["coupon"]["id"]

    first = client.post(f"/v1/me/coupons/{coupon_id}/use", headers=h)
    second = client.post(f"/v1/me/coupons/{coupon_id}/use", headers=h)

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["status"] == "used"
    assert first.json()["days_left"] == 0
    assert second.json()["used_at"] == first.json()["used_at"]
    assert _coupon(db_session, coupon_id).redeemed_by == member_id

    _, other_h = _new_member(client, db_session)
    assert (
        client.post(f"/v1/me/coupons/{coupon_id}/use", headers=other_h).status_code
        == 404
    )


# ---- 만료 ----


def test_expired_coupon_forfeits_points(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=6000)
    _link(db_session, member_id, trainer_id)
    salad_id = _exchange(client, h, "salad_discount").json()["coupon"]["id"]
    renewal_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
    past = clock.now() - timedelta(minutes=1)
    _set_expiry(db_session, salad_id, past)
    _set_expiry(db_session, renewal_id, past)

    listed = {c["id"]: c for c in client.get("/v1/me/coupons", headers=h).json()}
    assert listed[salad_id]["status"] == "expired"
    assert listed[salad_id]["days_left"] == 0
    assert _coupon(db_session, salad_id).status == "expired"

    assert client.post(f"/v1/me/coupons/{salad_id}/use", headers=h).status_code == 409
    trainer = _headers(trainer_id)
    assert client.get(
        f"/v1/trainer/clients/{member_id}/coupons", headers=trainer
    ).json() == []
    assert (
        client.post(
            f"/v1/trainer/clients/{member_id}/coupons/{renewal_id}/redeem",
            headers=trainer,
        ).status_code
        == 409
    )

    # 만료된 쿠폰은 담당이 끊겨도 돌려주지 않는다.
    assert client.delete("/v1/me/coach/trainer", headers=h).status_code == 204
    assert _balance(client, h) == 0
    assert _coupon(db_session, renewal_id).status == "expired"
    # 만료되면 새 재등록 쿠폰을 교환할 수 있다(담당이 있으면) — 한 장 규칙은 사용 가능한 것만 센다.
    _reactivate(db_session, member_id)
    _set_points(db_session, member_id, 5000)
    assert _exchange(client, h, "pt_renewal").status_code == 201


def test_expiry_reminder_created_once_within_three_days(client, db_session):
    member_id, h = _new_member(client, db_session, points=3000)
    soon_id = _exchange(client, h, "salad_discount").json()["coupon"]["id"]
    later_id = _exchange(client, h, "protein_discount").json()["coupon"]["id"]
    title = "쿠폰이 곧 만료돼요"
    # 마지막 사용일이 이틀 뒤 — 알림 창(3일) 안이다.
    last_day = clock.today() + timedelta(days=2)
    _set_expiry(
        db_session,
        soon_id,
        datetime.combine(last_day + timedelta(days=1), time.min, tzinfo=clock.SEOUL),
    )

    notices = client.get("/v1/notifications", headers=h).json()
    client.get("/v1/me/coupons", headers=h)
    client.get("/v1/notifications", headers=h)

    assert _notifications(db_session, member_id, title) == 1
    reminder = next(n for n in notices if n["title"] == title)
    assert "2일 뒤" in reminder["body"]
    assert reminder["action"]["target"] == "my_benefits"
    assert _coupon(db_session, soon_id).expiry_reminded_at is not None
    assert _coupon(db_session, later_id).expiry_reminded_at is None
    listed = {c["id"]: c for c in client.get("/v1/me/coupons", headers=h).json()}
    assert listed[soon_id]["days_left"] == 2
    assert listed[soon_id]["expires_on"] == last_day.isoformat()


# ---- 담당 해제 ----


@pytest.mark.parametrize("path", ["member_trainer", "member_gym", "trainer_remove"])
def test_disconnect_cancels_renewal_coupon_and_refunds(
    client, db_session, trainer_id, path
):
    member_id, h = _new_member(client, db_session, points=6300)
    _link(db_session, member_id, trainer_id)
    renewal_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
    salad_id = _exchange(client, h, "salad_discount").json()["coupon"]["id"]
    assert _balance(client, h) == 300

    if path == "member_trainer":
        r = client.delete("/v1/me/coach/trainer", headers=h)
    elif path == "member_gym":
        r = client.delete("/v1/me/coach", headers=h)
    else:
        r = client.delete(
            f"/v1/trainer/clients/{member_id}", headers=_headers(trainer_id)
        )
    assert r.status_code == 204, r.text

    assert _balance(client, h) == 5300
    renewal = _coupon(db_session, renewal_id)
    assert renewal.status == "cancelled"
    assert renewal.cancelled_at is not None
    assert _coupon(db_session, salad_id).status == "issued"
    refunds = db_session.scalars(
        select(PointsLedger).where(
            PointsLedger.user_id == member_id, PointsLedger.kind == "refund"
        )
    ).all()
    assert [(row.delta, row.source_id) for row in refunds] == [(5000, renewal_id)]
    assert _notifications(db_session, member_id, "재등록 쿠폰이 취소됐어요") == 1

    listed = {c["id"]: c for c in client.get("/v1/me/coupons", headers=h).json()}
    assert listed[renewal_id]["status"] == "cancelled"


def test_trainer_account_deletion_refunds_renewal_coupon(
    client, db_session, trainer_id
):
    member_id, h = _new_member(client, db_session, points=5000)
    _link(db_session, member_id, trainer_id)
    r = _exchange(client, h, "pt_renewal")
    assert r.status_code == 201, r.text
    assert r.json()["coupon"]["gym_name"] == GYM_NAME
    coupon_id = r.json()["coupon"]["id"]

    deleted = client.delete("/v1/trainer/me", headers=_headers(trainer_id))
    assert deleted.status_code == 200, deleted.text

    assert _balance(client, h) == 5000
    assert _coupon(db_session, coupon_id).status == "cancelled"


def test_refund_happens_once_per_coupon(client, db_session, trainer_id):
    from app.services import points_coupon_service, points_service

    member_id, h = _new_member(client, db_session, points=5000)
    _link(db_session, member_id, trainer_id)
    coupon_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]

    db_session.expire_all()
    assert points_coupon_service.cancel_renewal_coupons(db_session, member_id) == 1
    db_session.commit()
    assert points_coupon_service.cancel_renewal_coupons(db_session, member_id) == 0
    assert (
        points_service.refund(
            db_session, member_id, points_service.SOURCE_POINTS_COUPON, coupon_id
        )
        == 0
    )
    db_session.commit()
    assert _balance(client, h) == 5000
