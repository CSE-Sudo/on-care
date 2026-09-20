"""포인트 사용처·쿠폰 — 교환, 종류마다 한 장, 락커 한 달 한 번, 회원 휴대폰 사용 처리, 만료,
담당·헬스장 해제 반환. (#1787) DB 필요(로컬 skip, CI 실행).

새로 가입한 회원에 포인트를 넣고 **테스트마다 만든 트레이너·헬스장**을 붙여 확인한다.
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
    MemberGym,
    Notification,
    Place,
    PointsCoupon,
    PointsLedger,
    TrainerClient,
    TrainerProfile,
    User,
)

TRAINER_NAME = "쿠폰 트레이너"
GYM_NAME = "쿠폰 테스트짐"
#: 회원이 연결한 헬스장(`member_gyms`). 트레이너 프로필의 헬스장 문구와 일부러 다르다.
MEMBER_GYM_NAME = "쿠폰 락커짐"

RENEWAL_CANCELLED = "재등록 쿠폰이 취소됐어요"
LOCKER_CANCELLED = "락커 쿠폰이 취소됐어요"


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


@pytest.fixture
def gym_id(db_session) -> Iterator[str]:
    """이 테스트만 쓰는 헬스장. 지우면 회원 헬스장 링크도 CASCADE 로 사라진다."""
    created = f"gym-cpn-{uuid4().hex[:10]}"
    db_session.add(
        Place(
            id=created,
            name=MEMBER_GYM_NAME,
            category="fitness",
            address="쿠폰 테스트 주소",
        )
    )
    db_session.commit()
    yield created
    db_session.rollback()
    db_session.expire_all()
    place = db_session.get(Place, created)
    if place is not None:
        db_session.delete(place)
        db_session.commit()


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


def _link_gym(db_session, member_id: str, gym_id: str) -> None:
    """회원의 '내 헬스장'(`member_gyms`)을 붙인다."""
    db_session.add(MemberGym(member_id=member_id, gym_id=gym_id))
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


def _use(client, headers, coupon_id: str):
    return client.post(f"/v1/me/coupons/{coupon_id}/use", headers=headers)


def _notifications(db_session, member_id: str, title: str) -> int:
    db_session.expire_all()
    return db_session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == member_id, Notification.title == title)
    )


def _audits(db_session, coupon_id: str) -> list[AuditLog]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(AuditLog).where(
                AuditLog.event == "points.coupon_redeem",
                AuditLog.detail.contains(coupon_id),
            )
        ).all()
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


def _move_to_last_month(db_session, coupon_id: str) -> None:
    """교환 시각을 이번 KST 달 1일 0시 직전으로 옮긴다 — 지난달에 교환한 쿠폰."""
    month_start = datetime.combine(
        clock.today().replace(day=1), time.min, tzinfo=clock.SEOUL
    )
    db_session.execute(
        update(PointsCoupon)
        .where(PointsCoupon.id == coupon_id)
        .values(issued_at=month_start - timedelta(minutes=1))
    )
    db_session.commit()


def _refunds(db_session, member_id: str) -> list[tuple[int, str]]:
    db_session.expire_all()
    rows = db_session.scalars(
        select(PointsLedger).where(
            PointsLedger.user_id == member_id, PointsLedger.kind == "refund"
        )
    ).all()
    return sorted((row.delta, row.source_id) for row in rows)


# ---- 교환 목록 ----


def test_shop_lists_items_with_block_reasons(client, db_session, trainer_id, gym_id):
    member_id, h = _new_member(client, db_session, points=7000)

    r = client.get("/v1/me/points/shop", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["balance"] == 7000
    assert body["has_trainer"] is False
    assert body["has_gym"] is False
    assert [i["id"] for i in body["items"]] == [
        "pt_renewal",
        "locker_month",
        "streak_shield",
        "emote_pass_24h",
    ]
    renewal, locker = body["items"][:2]
    assert "redeemer" not in renewal and "redeemer" not in locker
    # 혜택 1만원 = 7,000P — 3만원 할인은 21,000P, 락커 한 달(1만원)은 7,000P.
    assert (renewal["title"], renewal["benefit"]) == (
        "PT 재등록 3만원 할인",
        "PT 재등록 30,000원 할인",
    )
    assert (renewal["cost"], renewal["valid_days"]) == (21000, 30)
    assert (renewal["requires_trainer"], renewal["requires_gym"]) == (True, False)
    assert renewal["available"] is False
    assert renewal["blocked_reason"] == "no_trainer"
    assert renewal["shortfall"] == 14000
    assert (locker["title"], locker["benefit"]) == (
        "개인 락커 1개월 무료",
        "개인 락커 1개월 무료",
    )
    assert (locker["cost"], locker["valid_days"]) == (7000, 30)
    assert (locker["requires_trainer"], locker["requires_gym"]) == (False, True)
    assert locker["available"] is False
    assert locker["blocked_reason"] == "no_gym"
    assert locker["shortfall"] == 0

    _link(db_session, member_id, trainer_id)
    renewal = _shop_item(client, h, "pt_renewal")
    assert renewal["blocked_reason"] == "insufficient_points"
    assert renewal["shortfall"] == 14000

    _link_gym(db_session, member_id, gym_id)
    body = client.get("/v1/me/points/shop", headers=h).json()
    assert body["has_gym"] is True
    locker = next(i for i in body["items"] if i["id"] == "locker_month")
    assert locker["available"] is True and locker["blocked_reason"] is None


def test_catalog_is_gym_benefits_only(client, db_session):
    member_id, h = _new_member(client, db_session, points=30000)

    items = client.get("/v1/me/points/shop", headers=h).json()["items"]
    # 사용처는 헬스장 혜택 두 장과 연속 기록 보호권(#1788), 채팅 이모티콘 24시간
    # 이용권(#2020)이다. 카탈로그 밖 항목은 교환하면 404 다.
    assert [i["id"] for i in items] == [
        "pt_renewal",
        "locker_month",
        "streak_shield",
        "emote_pass_24h",
    ]
    assert _exchange(client, h, "unknown_item").status_code == 404

    assert _balance(client, h) == 30000
    db_session.expire_all()
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(PointsCoupon)
            .where(PointsCoupon.user_id == member_id)
        )
        == 0
    )


# ---- 교환 ----


def test_exchange_locker_spends_points_and_records_gym(client, db_session, gym_id):
    member_id, h = _new_member(client, db_session, points=7500)
    _link_gym(db_session, member_id, gym_id)

    r = _exchange(client, h, "locker_month")

    assert r.status_code == 201, r.text
    body = r.json()
    assert body["spent"] == 7000
    assert body["balance"] == 500
    coupon = body["coupon"]
    assert coupon["status"] == "issued"
    assert coupon["benefit"] == "개인 락커 1개월 무료"
    assert "code" not in coupon
    assert "redeemer" not in coupon
    # 쿠폰 화면이 보여 줄 헬스장은 교환할 때 회원이 연결한 헬스장이다. 트레이너는 없다.
    assert coupon["gym_name"] == MEMBER_GYM_NAME
    assert coupon["trainer_name"] == ""
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
        (-7000, "points_coupon", coupon["id"])
    ]

    listed = client.get("/v1/me/coupons", headers=h).json()
    assert [c["id"] for c in listed] == [coupon["id"]]


def test_locker_requires_connected_gym(client, db_session, trainer_id, gym_id):
    member_id, h = _new_member(client, db_session, points=9000)

    r = _exchange(client, h, "locker_month")
    assert r.status_code == 409
    assert r.json()["detail"] == "헬스장을 연결해야 교환할 수 있어요."
    # 담당 트레이너만 있으면 헬스장이 연결된 것이 아니다 — 코치 카드가 트레이너
    # 소속으로 폴백해 보여 주는 헬스장 문구는 회원의 헬스장 링크가 아니다.
    _link(db_session, member_id, trainer_id)
    assert _exchange(client, h, "locker_month").status_code == 409
    assert _shop_item(client, h, "locker_month")["blocked_reason"] == "no_gym"
    assert _balance(client, h) == 9000

    _link_gym(db_session, member_id, gym_id)
    assert _exchange(client, h, "locker_month").status_code == 201
    assert _balance(client, h) == 2000


def test_exchange_insufficient_balance_changes_nothing(client, db_session, gym_id):
    member_id, h = _new_member(client, db_session, points=6900)
    _link_gym(db_session, member_id, gym_id)

    r = _exchange(client, h, "locker_month")

    assert r.status_code == 409, r.text
    assert "100P" in r.json()["detail"]
    assert _balance(client, h) == 6900
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
    _, h = _new_member(client, db_session, points=30000)
    assert _exchange(client, h, "recipe_pack").status_code == 404


def test_exchange_retry_with_request_id_spends_once(client, db_session, gym_id):
    member_id, h = _new_member(client, db_session, points=8000)
    _link_gym(db_session, member_id, gym_id)
    key = f"req-{uuid4().hex}"

    first = _exchange(client, h, "locker_month", key)
    second = _exchange(client, h, "locker_month", key)

    assert first.status_code == 201 and second.status_code == 201
    assert first.json()["coupon"]["id"] == second.json()["coupon"]["id"]
    assert _balance(client, h) == 1000


def test_locker_once_per_kst_month(client, db_session, gym_id):
    member_id, h = _new_member(client, db_session, points=30000)
    _link_gym(db_session, member_id, gym_id)

    first = _exchange(client, h, "locker_month")
    assert first.status_code == 201, first.text
    first_id = first.json()["coupon"]["id"]
    # 사용하지 않은 쿠폰이 있으면 그 이유가 먼저다.
    assert _exchange(client, h, "locker_month").status_code == 409
    assert _shop_item(client, h, "locker_month")["blocked_reason"] == "active_coupon"

    # 써도 같은 달에는 다시 받을 수 없다.
    assert _use(client, h, first_id).status_code == 200
    blocked = _shop_item(client, h, "locker_month")
    assert blocked["available"] is False
    assert blocked["blocked_reason"] == "monthly_limit"
    again = _exchange(client, h, "locker_month")
    assert again.status_code == 409
    assert again.json()["detail"] == "이번 달에는 이미 교환했어요."
    assert _balance(client, h) == 23000

    # 지난달에 교환한 쿠폰은 이번 달 한도에 들지 않는다.
    _move_to_last_month(db_session, first_id)
    assert _shop_item(client, h, "locker_month")["available"] is True
    second = _exchange(client, h, "locker_month")
    assert second.status_code == 201, second.text

    # 만료된 쿠폰도 이번 달 교환으로 센다 — 기한을 넘겨도 같은 달에 또 받지 못한다.
    _set_expiry(
        db_session, second.json()["coupon"]["id"], clock.now() - timedelta(minutes=1)
    )
    assert _shop_item(client, h, "locker_month")["blocked_reason"] == "monthly_limit"
    assert _exchange(client, h, "locker_month").status_code == 409
    assert _balance(client, h) == 16000


def test_pt_renewal_requires_active_trainer(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=22000)

    assert _exchange(client, h, "pt_renewal").status_code == 409
    # 해제된(휴면) 담당 링크만 있으면 담당이 없는 것이다.
    _link(db_session, member_id, trainer_id, active=False)
    assert _exchange(client, h, "pt_renewal").status_code == 409
    assert _balance(client, h) == 22000

    _reactivate(db_session, member_id)
    r = _exchange(client, h, "pt_renewal")

    assert r.status_code == 201, r.text
    coupon = r.json()["coupon"]
    assert coupon["benefit"] == "PT 재등록 30,000원 할인"
    assert coupon["cost"] == 21000
    # 쿠폰 화면이 보여 줄 담당 트레이너·헬스장은 교환 시점의 사본이다.
    assert coupon["trainer_name"] == TRAINER_NAME
    assert coupon["gym_name"] == GYM_NAME
    assert r.json()["spent"] == 21000
    assert r.json()["balance"] == 1000


def test_pt_renewal_one_unused_coupon_at_a_time(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=44000)
    _link(db_session, member_id, trainer_id)

    first = _exchange(client, h, "pt_renewal")
    assert first.status_code == 201, first.text
    second = _exchange(client, h, "pt_renewal")
    assert second.status_code == 409
    assert _balance(client, h) == 23000
    assert _shop_item(client, h, "pt_renewal")["blocked_reason"] == "active_coupon"

    assert _use(client, h, first.json()["coupon"]["id"]).status_code == 200

    # 사용한 뒤에는 다음 재등록을 위해 다시 교환할 수 있다 — 한 달 한 번 규칙은 없다.
    assert _shop_item(client, h, "pt_renewal")["blocked_reason"] is None
    assert _exchange(client, h, "pt_renewal").status_code == 201
    assert _balance(client, h) == 2000


# ---- 사용 처리(회원 휴대폰) ----


def test_member_phone_uses_pt_renewal_once_with_audit(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=21000)
    _link(db_session, member_id, trainer_id)
    coupon_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]

    first = _use(client, h, coupon_id)
    second = _use(client, h, coupon_id)

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["status"] == "used"
    assert first.json()["used_at"] is not None
    assert first.json()["days_left"] == 0
    # 두 번 눌러도 처음 사용 시각 그대로다.
    assert second.json()["used_at"] == first.json()["used_at"]

    row = _coupon(db_session, coupon_id)
    assert row.status == "used"
    assert row.used_at is not None
    audits = _audits(db_session, coupon_id)
    assert len(audits) == 1
    assert audits[0].user_id == member_id
    # 회원 휴대폰에서 누른 사용이라 알림은 없다.
    db_session.expire_all()
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(Notification)
            .where(
                Notification.user_id == member_id,
                Notification.category == "benefits",
            )
        )
        == 0
    )

    member_view = client.get("/v1/me/coupons", headers=h).json()
    assert member_view[0]["status"] == "used"
    assert member_view[0]["used_at"] == first.json()["used_at"]


def test_member_phone_uses_locker_once_with_audit(client, db_session, gym_id):
    member_id, h = _new_member(client, db_session, points=7000)
    _link_gym(db_session, member_id, gym_id)
    coupon_id = _exchange(client, h, "locker_month").json()["coupon"]["id"]

    first = _use(client, h, coupon_id)
    second = _use(client, h, coupon_id)

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["status"] == "used"
    assert first.json()["days_left"] == 0
    assert second.json()["used_at"] == first.json()["used_at"]
    # 락커도 헬스장 직원이 확인하고 주는 혜택이라 처음 처리에 감사 로그를 남긴다.
    audits = _audits(db_session, coupon_id)
    assert len(audits) == 1
    assert audits[0].user_id == member_id

    _, other_h = _new_member(client, db_session)
    assert _use(client, other_h, coupon_id).status_code == 404


def test_trainer_coupon_endpoints_are_gone(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=21000)
    _link(db_session, member_id, trainer_id)
    coupon_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
    trainer = _headers(trainer_id)

    assert (
        client.get(f"/v1/trainer/clients/{member_id}/coupons", headers=trainer)
        .status_code
        == 404
    )
    assert (
        client.post(
            f"/v1/trainer/clients/{member_id}/coupons/{coupon_id}/redeem",
            headers=trainer,
        ).status_code
        == 404
    )
    assert _coupon(db_session, coupon_id).status == "issued"


def test_other_member_cannot_use_pt_renewal(client, db_session, trainer_id):
    member_id, h = _new_member(client, db_session, points=21000)
    _link(db_session, member_id, trainer_id)
    coupon_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]

    _, other_h = _new_member(client, db_session)
    assert _use(client, other_h, coupon_id).status_code == 404
    assert _coupon(db_session, coupon_id).status == "issued"
    assert _audits(db_session, coupon_id) == []


# ---- 만료 ----


def test_expired_coupon_forfeits_points(client, db_session, trainer_id, gym_id):
    member_id, h = _new_member(client, db_session, points=28000)
    _link(db_session, member_id, trainer_id)
    _link_gym(db_session, member_id, gym_id)
    locker_id = _exchange(client, h, "locker_month").json()["coupon"]["id"]
    renewal_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
    past = clock.now() - timedelta(minutes=1)
    _set_expiry(db_session, locker_id, past)
    _set_expiry(db_session, renewal_id, past)

    listed = {c["id"]: c for c in client.get("/v1/me/coupons", headers=h).json()}
    assert listed[locker_id]["status"] == "expired"
    assert listed[locker_id]["days_left"] == 0
    assert _coupon(db_session, locker_id).status == "expired"

    assert _use(client, h, locker_id).status_code == 409
    assert _use(client, h, renewal_id).status_code == 409
    assert _audits(db_session, renewal_id) == []

    # 만료된 쿠폰은 헬스장·담당이 함께 끊겨도 돌려주지 않는다.
    assert client.delete("/v1/me/coach", headers=h).status_code == 204
    assert _balance(client, h) == 0
    assert _coupon(db_session, renewal_id).status == "expired"
    assert _coupon(db_session, locker_id).status == "expired"
    assert _refunds(db_session, member_id) == []
    # 만료되면 새 재등록 쿠폰을 교환할 수 있다(담당이 있으면) — 한 장 규칙은 사용 가능한 것만 센다.
    _reactivate(db_session, member_id)
    _set_points(db_session, member_id, 21000)
    assert _exchange(client, h, "pt_renewal").status_code == 201


def test_expiry_reminder_created_once_within_three_days(
    client, db_session, trainer_id, gym_id
):
    member_id, h = _new_member(client, db_session, points=28000)
    _link(db_session, member_id, trainer_id)
    _link_gym(db_session, member_id, gym_id)
    soon_id = _exchange(client, h, "locker_month").json()["coupon"]["id"]
    later_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
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
    assert "개인 락커 1개월 무료 쿠폰이 2일 뒤" in reminder["body"]
    assert reminder["action"] == {"label": "내 혜택 보기", "target": "my_benefits"}
    assert _coupon(db_session, soon_id).expiry_reminded_at is not None
    assert _coupon(db_session, later_id).expiry_reminded_at is None
    listed = {c["id"]: c for c in client.get("/v1/me/coupons", headers=h).json()}
    assert listed[soon_id]["days_left"] == 2
    assert listed[soon_id]["expires_on"] == last_day.isoformat()


# ---- 담당·헬스장 해제 ----


@pytest.mark.parametrize("path", ["member_trainer", "member_gym", "trainer_remove"])
def test_disconnect_cancels_coupons_and_refunds(
    client, db_session, trainer_id, gym_id, path
):
    member_id, h = _new_member(client, db_session, points=28300)
    _link(db_session, member_id, trainer_id)
    _link_gym(db_session, member_id, gym_id)
    renewal_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
    locker_id = _exchange(client, h, "locker_month").json()["coupon"]["id"]
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

    # 담당은 세 경로 모두 끊긴다. 헬스장은 `DELETE /me/coach` 만 끊는다.
    gym_ended = path == "member_gym"
    renewal = _coupon(db_session, renewal_id)
    assert renewal.status == "cancelled"
    assert renewal.cancelled_at is not None
    locker = _coupon(db_session, locker_id)
    assert locker.status == ("cancelled" if gym_ended else "issued")
    assert (locker.cancelled_at is not None) is gym_ended
    expected = [(21000, renewal_id)] + ([(7000, locker_id)] if gym_ended else [])
    assert _refunds(db_session, member_id) == sorted(expected)
    assert _balance(client, h) == (28300 if gym_ended else 21300)
    assert _notifications(db_session, member_id, RENEWAL_CANCELLED) == 1
    assert _notifications(db_session, member_id, LOCKER_CANCELLED) == int(gym_ended)

    listed = {c["id"]: c for c in client.get("/v1/me/coupons", headers=h).json()}
    assert listed[renewal_id]["status"] == "cancelled"
    # 취소된 쿠폰은 쓸 수 없다.
    assert _use(client, h, renewal_id).status_code == 409


def test_gym_disconnect_refunds_locker_once_and_frees_monthly_limit(
    client, db_session, gym_id
):
    member_id, h = _new_member(client, db_session, points=7000)
    _link_gym(db_session, member_id, gym_id)
    locker_id = _exchange(client, h, "locker_month").json()["coupon"]["id"]
    assert _balance(client, h) == 0

    assert client.delete("/v1/me/coach", headers=h).status_code == 204

    assert _balance(client, h) == 7000
    assert _coupon(db_session, locker_id).status == "cancelled"
    assert _refunds(db_session, member_id) == [(7000, locker_id)]
    assert _notifications(db_session, member_id, LOCKER_CANCELLED) == 1
    db_session.expire_all()
    notice = db_session.scalar(
        select(Notification).where(
            Notification.user_id == member_id,
            Notification.title == LOCKER_CANCELLED,
        )
    )
    assert notice.category == "benefits"
    assert notice.body == (
        "헬스장 연결이 해제되어 개인 락커 1개월 무료 쿠폰을 취소하고 7,000P를 돌려드렸어요."
    )
    assert _use(client, h, locker_id).status_code == 409
    assert _shop_item(client, h, "locker_month")["blocked_reason"] == "no_gym"

    # 두 번 해제해도 두 번 돌려주지 않는다.
    assert client.delete("/v1/me/coach", headers=h).status_code == 204
    assert _balance(client, h) == 7000
    assert _notifications(db_session, member_id, LOCKER_CANCELLED) == 1

    # 취소돼 돌려받은 쿠폰은 한 달 한 번 규칙에 들지 않는다 — 다시 연결하면 이번 달에 또 받는다.
    _link_gym(db_session, member_id, gym_id)
    assert _shop_item(client, h, "locker_month")["available"] is True
    assert _exchange(client, h, "locker_month").status_code == 201
    assert _balance(client, h) == 0


def test_trainer_account_deletion_refunds_renewal_coupon(
    client, db_session, trainer_id
):
    member_id, h = _new_member(client, db_session, points=21000)
    _link(db_session, member_id, trainer_id)
    r = _exchange(client, h, "pt_renewal")
    assert r.status_code == 201, r.text
    assert r.json()["coupon"]["gym_name"] == GYM_NAME
    coupon_id = r.json()["coupon"]["id"]

    deleted = client.delete("/v1/trainer/me", headers=_headers(trainer_id))
    assert deleted.status_code == 200, deleted.text

    assert _balance(client, h) == 21000
    assert _coupon(db_session, coupon_id).status == "cancelled"


def test_refund_happens_once_per_coupon(client, db_session, trainer_id, gym_id):
    from app.services import points_coupon_service, points_service

    member_id, h = _new_member(client, db_session, points=28000)
    _link(db_session, member_id, trainer_id)
    _link_gym(db_session, member_id, gym_id)
    renewal_id = _exchange(client, h, "pt_renewal").json()["coupon"]["id"]
    locker_id = _exchange(client, h, "locker_month").json()["coupon"]["id"]

    db_session.expire_all()
    assert points_coupon_service.cancel_renewal_coupons(db_session, member_id) == 1
    assert points_coupon_service.cancel_locker_coupons(db_session, member_id) == 1
    db_session.commit()
    assert points_coupon_service.cancel_renewal_coupons(db_session, member_id) == 0
    assert points_coupon_service.cancel_locker_coupons(db_session, member_id) == 0
    for coupon_id in (renewal_id, locker_id):
        assert (
            points_service.refund(
                db_session, member_id, points_service.SOURCE_POINTS_COUPON, coupon_id
            )
            == 0
        )
    db_session.commit()
    assert _balance(client, h) == 28000
