"""분석용 식판 — 사진 기록일 조건, 담당 필요, 1인 1회, 기한 없음, 교환 경로 차단, 담당
해제 취소. (#2150) DB 필요(로컬 skip, CI 실행).

새로 가입한 회원에 **테스트마다 만든 트레이너**를 붙이고, 식단 행을 직접 넣어 사진
기록일을 채운다.
"""
from __future__ import annotations

from collections.abc import Iterator
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select, update

from app.core import clock
from app.models.models import (
    DietEntry,
    Notification,
    PointsCoupon,
    PointsLedger,
    TrainerClient,
    TrainerProfile,
    User,
)
from app.services import diet_tray_service

GYM_NAME = "식판 테스트짐"
TRAY_CANCELLED = "식판 수령 쿠폰이 취소됐어요"


@pytest.fixture
def trainer_id(db_session) -> Iterator[str]:
    """이 테스트만 쓰는 트레이너. 지우면 담당 링크·프로필은 CASCADE 로 사라진다."""
    created = f"trainer-{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=created,
            email=f"{created}@oncare.com",
            name="식판 트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    db_session.commit()
    db_session.add(TrainerProfile(trainer_id=created, gym_name=GYM_NAME))
    db_session.commit()
    yield created
    db_session.rollback()
    db_session.expire_all()
    user = db_session.get(User, created)
    if user is not None:
        db_session.delete(user)
        db_session.commit()


def _new_member(client) -> tuple[str, dict[str, str]]:
    email = f"tray-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    return member_id, headers


def _link(db_session, member_id: str, trainer_id: str) -> None:
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
        )
    )
    db_session.commit()


def _add_meals(
    db_session,
    member_id: str,
    days: int,
    *,
    start_ago: int = 0,
    engine: str = "gemini",
    per_day: int = 1,
) -> None:
    """오늘에서 [start_ago]일 전부터 거슬러 [days]일 동안 하루 [per_day]끼를 넣는다."""
    today = clock.today()
    for offset in range(start_ago, start_ago + days):
        day = (today - timedelta(days=offset)).isoformat()
        for n in range(per_day):
            db_session.add(
                DietEntry(
                    id=f"de-{uuid4().hex[:12]}",
                    user_id=member_id,
                    date=day,
                    meal_type=("breakfast", "lunch", "dinner")[n % 3],
                    engine=engine,
                )
            )
    db_session.commit()


def _state(client, headers) -> dict:
    r = client.get("/v1/me/diet-tray", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _claim(client, headers, request_id: str | None = None):
    body: dict[str, str] = {}
    if request_id is not None:
        body["client_request_id"] = request_id
    return client.post("/v1/me/diet-tray/claim", json=body, headers=headers)


def _tray_coupons(db_session, member_id: str) -> list[PointsCoupon]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(PointsCoupon).where(
                PointsCoupon.user_id == member_id,
                PointsCoupon.item == diet_tray_service.ITEM_ID,
            )
        ).all()
    )


def test_counts_only_photo_days_inside_window(client, db_session, trainer_id):
    member_id, h = _new_member(client)
    _link(db_session, member_id, trainer_id)
    # 사진 19일(하루 세 끼여도 하루) + 손 기록 5일 + 창 밖(28일 전) 사진 3일.
    _add_meals(db_session, member_id, 19, per_day=3)
    _add_meals(db_session, member_id, 5, start_ago=19, engine="")
    _add_meals(db_session, member_id, 3, start_ago=28)

    state = _state(client, h)
    assert state["photo_days"] == 19
    assert state["required_days"] == 20
    assert state["window_days"] == 28
    assert state["window_to"] == clock.today().isoformat()
    assert state["window_from"] == (clock.today() - timedelta(days=27)).isoformat()
    assert state["status"] == "progress"
    assert state["coupon"] is None

    r = _claim(client, h)
    assert r.status_code == 409, r.text
    assert "1일" in r.json()["detail"]

    # 창 마지막 날(27일 전)에 한 장 더 찍으면 20일이다.
    _add_meals(db_session, member_id, 1, start_ago=27)
    assert _state(client, h)["status"] == "claimable"


def test_requires_trainer(client, db_session):
    member_id, h = _new_member(client)
    _add_meals(db_session, member_id, 20)

    state = _state(client, h)
    assert state["photo_days"] == 20
    assert state["has_trainer"] is False
    assert state["status"] == "progress"
    r = _claim(client, h)
    assert r.status_code == 409
    assert "담당 트레이너" in r.json()["detail"]


def test_claim_issues_zero_point_coupon_once(client, db_session, trainer_id):
    member_id, h = _new_member(client)
    _link(db_session, member_id, trainer_id)
    _add_meals(db_session, member_id, 20)

    r = _claim(client, h, request_id="tray-1")
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["status"] == "issued"
    coupon = body["coupon"]
    assert coupon["item"] == "diet_tray"
    assert coupon["cost"] == 0
    assert coupon["gym_name"] == GYM_NAME
    assert coupon["trainer_name"] == "식판 트레이너"
    # 기한이 없다 — 식판이 언제 헬스장에 닿을지는 우리 사정이다.
    assert coupon["no_expiry"] is True
    assert coupon["days_left"] == 0

    # 같은 요청의 재시도는 새로 만들지 않는다. 다른 요청은 409.
    again = _claim(client, h, request_id="tray-1")
    assert again.status_code == 201
    assert again.json()["coupon"]["id"] == coupon["id"]
    assert _claim(client, h, request_id="tray-2").status_code == 409
    assert len(_tray_coupons(db_session, member_id)) == 1

    # 포인트 내역에는 남지 않는다 — 산 것이 아니다.
    db_session.expire_all()
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(PointsLedger)
            .where(PointsLedger.user_id == member_id)
        )
        == 0
    )

    # 내 쿠폰에 선다.
    coupons = client.get("/v1/me/coupons", headers=h).json()
    assert [c["id"] for c in coupons] == [coupon["id"]]

    # 헬스장에서 받으면(사용 완료) 받음이고, 다시 받을 수 없다.
    used = client.post(f"/v1/me/coupons/{coupon['id']}/use", headers=h)
    assert used.status_code == 200, used.text
    state = _state(client, h)
    assert state["status"] == "received"
    assert state["coupon"]["status"] == "used"
    r = _claim(client, h, request_id="tray-3")
    assert r.status_code == 409
    assert "이미 받았어요" in r.json()["detail"]


def test_tray_coupon_never_expires(client, db_session, trainer_id):
    member_id, h = _new_member(client)
    _link(db_session, member_id, trainer_id)
    _add_meals(db_session, member_id, 20)
    coupon_id = _claim(client, h).json()["coupon"]["id"]

    # 발급을 1년 전으로 옮겨도 쓸 수 있고, 만료 임박 알림도 없다.
    db_session.execute(
        update(PointsCoupon)
        .where(PointsCoupon.id == coupon_id)
        .values(issued_at=clock.now() - timedelta(days=365))
    )
    db_session.commit()
    (coupon,) = client.get("/v1/me/coupons", headers=h).json()
    assert coupon["status"] == "issued"
    assert coupon["no_expiry"] is True
    db_session.expire_all()
    assert db_session.get(PointsCoupon, coupon_id).expiry_reminded_at is None
    assert _state(client, h)["status"] == "issued"


def test_exchange_path_cannot_issue_tray(client, db_session, trainer_id):
    member_id, h = _new_member(client)
    _link(db_session, member_id, trainer_id)
    _add_meals(db_session, member_id, 20)

    r = client.post(
        "/v1/me/points/exchange", json={"item": "diet_tray"}, headers=h
    )
    assert r.status_code == 404
    shop = client.get("/v1/me/points/shop", headers=h).json()
    assert "diet_tray" not in [i["id"] for i in shop["items"]]


def test_unlinking_trainer_cancels_unclaimed_tray(client, db_session, trainer_id):
    member_id, h = _new_member(client)
    _link(db_session, member_id, trainer_id)
    _add_meals(db_session, member_id, 20)
    coupon_id = _claim(client, h).json()["coupon"]["id"]

    assert client.delete("/v1/me/coach/trainer", headers=h).status_code == 204

    (row,) = _tray_coupons(db_session, member_id)
    assert row.id == coupon_id
    assert row.status == "cancelled"
    assert (
        db_session.scalar(
            select(func.count())
            .select_from(Notification)
            .where(
                Notification.user_id == member_id,
                Notification.title == TRAY_CANCELLED,
            )
        )
        == 1
    )
    state = _state(client, h)
    assert state["status"] == "progress"
    assert state["has_trainer"] is False

    # 식판을 받은 것이 아니다 — 새 담당이 생기면 다시 받는다.
    db_session.execute(
        update(TrainerClient)
        .where(TrainerClient.member_id == member_id)
        .values(active=True)
    )
    db_session.commit()
    assert _state(client, h)["status"] == "claimable"
    r = _claim(client, h)
    assert r.status_code == 201, r.text
    assert r.json()["coupon"]["id"] != coupon_id
