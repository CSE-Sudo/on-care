"""예약·상담·로스터 목록의 상한과 커서. (#980) DB 필요.

알림(#965)과 같은 문제가 남아 있던 목록들이다 — 계정을 오래 쓸수록 응답이 선형으로
길어지는데, 알림과 달리 **지우는 것이 답이 아니다**(예약·상담은 이력이고, 로스터는
담당 관계다). 그래서 상한과 커서만 씌운다.

여기서 확인하는 것:
  1. 기본 상한이 있고, 커서로 다음 쪽을 빠짐없이·겹치지 않게 이어 받는다.
  2. 파라미터 없이 부르던 기존 클라이언트가 깨지지 않는다.
  3. 첫 쪽에 **지금 쓸모 있는 것**이 온다 — 예약은 다가오는 것부터다.
  4. 미처리 상담 배지는 쪽 나눔과 무관하게 전체 기준이다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.core.security import hash_password
from app.models.models import (
    ConsultationRequest,
    TrainerClient,
    TrainerProfile,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)

EMAIL_PREFIX = "page-test-"
PASSWORD = "page-pw-1234!"

#: 기본 상한(50)의 경계를 보려면 그보다 많아야 한다.
_TOTAL = 120

#: 로스터는 인원수만큼만 자라 120명까지 쌓아 볼 일이 없다 — 상한만 넘기면 된다.
_ROSTER_TOTAL = 60

_BASE = datetime(2026, 3, 1, 9, 0, tzinfo=timezone.utc)

#: 상담 요청의 기준 시각. 예약(`_BASE`)과 달리 **지금 가까이**여야 한다 — 대기 요청은
#: 신청 후 24시간이 지나면 읽는 시점에 만료된다(#1873). 반년 전 시각으로 쌓으면
#: 배지·인박스를 읽는 순간 전부 `expired` 가 된다. 오프셋이 같아 정렬·동시각 경계는
#: 그대로다.
_CONSULT_BASE = datetime.now(timezone.utc) - timedelta(hours=3)


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    res = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


@pytest.fixture()
def member(client) -> dict:
    """예약·상담이 하나도 없는 새 회원. 시드 계정은 다른 테스트가 건드려 수가 흔들린다."""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:8]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "페이지 회원"},
    )
    assert created.status_code == 201, created.text
    return {"id": created.json()["id"], "token": _login(client, email)}


@pytest.fixture()
def trainer(client, db_session) -> dict:
    """담당 고객도 상담 요청도 없는 새 트레이너."""
    suffix = uuid4().hex[:8]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    row = User(
        id=f"page-trainer-{suffix}",
        email=email,
        name="페이지 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(row)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=row.id))
    db_session.commit()
    return {"id": row.id, "token": _login(client, email)}


def _get(client, token: str, path: str, **params) -> list[dict]:
    res = client.get(f"/v1/{path}", params=params, headers=_auth(token))
    assert res.status_code == 200, res.text
    return res.json()


def _walk(client, token: str, path: str, cursor_keys: tuple[str, str], key, **params):
    """커서를 따라 목록 전체를 훑는다. 받은 id 를 순서대로 돌려준다.

    쪽 크기를 기본값보다 작게 잡아 경계를 여러 번 지나게 한다 — 한 쪽에 다 들어가면
    커서가 실제로 동작하는지 알 수 없다.
    """
    before_key, before_id_key = cursor_keys
    seen: list[str] = []
    cursor: dict[str, object] = {}
    for _ in range(30):  # 넉넉한 상한 — 커서가 멈추지 않아도 매달리지 않게.
        rows = _get(client, token, path, limit=25, **params, **cursor)
        if not rows:
            break
        seen.extend(r["id"] for r in rows)
        cursor = {before_key: key(rows[-1]), before_id_key: rows[-1]["id"]}
    return seen


# ---------------------------------------------------------------------------
# GET /reservations/me
# ---------------------------------------------------------------------------
def _seed_reservations(db, member_id: str, trainer_id: str, count: int) -> None:
    """이른 시각부터 `count` 건. 마지막 두 건은 **같은 시각**이다.

    한 트레이너가 같은 시각에 슬롯을 여러 개 열어 둘 수 있어 동시각이 실제로 나온다.
    시각만으로 자르는 커서라면 그 경계에서 예약이 빠지거나 겹친다.
    """
    for i in range(count):
        starts_at = _BASE + timedelta(hours=min(i, count - 2))
        slot = TrainerReservationSlot(
            id=f"slot-page-{i:04d}-{uuid4().hex[:6]}",
            trainer_id=trainer_id,
            starts_at=starts_at,
            capacity=1,
            remaining=0,
        )
        schedule = TrainerSchedule(
            id=f"sched-page-{i:04d}-{uuid4().hex[:6]}",
            trainer_id=trainer_id,
            member_id=member_id,
            date=starts_at.date().isoformat(),
            time=starts_at.strftime("%H:%M"),
            client_name="페이지 회원",
            type="1:1 PT",
            duration_minutes=50,
            status="예정",
            note="",
            program_json="[]",
            sort_order=0,
        )
        db.add_all([slot, schedule])
        # 슬롯·일정을 **먼저** 내보낸다 — 모델에 relationship 이 없어 ORM 이 예약과의
        # 의존을 모르고, 한 번에 flush 하면 예약이 먼저 나가 FK 위반이 된다.
        db.flush()
        db.add(
            TrainerReservation(
                id=f"resv-page-{i:04d}-{uuid4().hex[:6]}",
                member_id=member_id,
                slot_id=slot.id,
                schedule_id=schedule.id,
                status="booked",
            )
        )
    db.commit()


def test_reservations_default_page_is_capped_and_upcoming_first(
    client, db_session, member, trainer
):
    """파라미터 없는 호출은 그대로 동작하되, 늦은 예약부터 50건까지만 준다.

    순서가 중요하다 — 오름차순 그대로 상한만 씌우면 첫 쪽이 **가장 오래된 지난
    예약**으로 차서, 정작 다가오는 예약이 화면에서 사라진다.
    """
    _seed_reservations(db_session, member["id"], trainer["id"], _TOTAL)

    rows = _get(client, member["token"], "reservations/me")

    assert len(rows) == 50
    times = [r["starts_at"] for r in rows]
    assert times == sorted(times, reverse=True)


def test_reservations_limit_is_bounded(client, member):
    """채팅 스레드·알림과 같은 규약(1~100)."""
    assert len(_get(client, member["token"], "reservations/me", limit=1)) <= 1
    for bad in (0, 101):
        res = client.get(
            "/v1/reservations/me",
            params={"limit": bad},
            headers=_auth(member["token"]),
        )
        assert res.status_code == 422


def test_reservations_cursor_walks_the_whole_list(client, db_session, member, trainer):
    """쪽을 이어 받으면 전체가 정확히 한 번씩 나온다 — 동시각 경계 포함."""
    _seed_reservations(db_session, member["id"], trainer["id"], _TOTAL)

    seen = _walk(
        client,
        member["token"],
        "reservations/me",
        ("before", "before_id"),
        key=lambda r: r["starts_at"],
    )

    assert len(seen) == _TOTAL
    assert len(set(seen)) == _TOTAL


def test_reservations_bad_cursor_is_rejected(client, member):
    """커서를 파싱할 수 없으면 422 — 조용히 첫 쪽을 주면 무한 루프가 된다."""
    res = client.get(
        "/v1/reservations/me",
        params={"before": "어제"},
        headers=_auth(member["token"]),
    )
    assert res.status_code == 422


# ---------------------------------------------------------------------------
# GET /consultations/me · GET /trainer/consultations
# ---------------------------------------------------------------------------
def _consultation(member_id: str, trainer_id: str, i: int, count: int, status: str):
    """상담 요청 한 건. 마지막 두 건은 같은 `created_at` 이다.

    같은 시각이 실제로 나온다 — 인박스는 회원 여러 명의 요청이 몰리는 자리다. 시각만으로
    자르는 커서라면 그 경계에서 요청이 빠지거나 겹친다.
    """
    return ConsultationRequest(
        id=f"consult-page-{i:04d}-{uuid4().hex[:6]}",
        member_id=member_id,
        target_type="trainer",
        trainer_id=trainer_id,
        exercise_goal="fitness",
        health_purpose_type="general",
        preferred_date="2026-04-01",
        preferred_time_slot="morning",
        status=status,
        created_at=_CONSULT_BASE + timedelta(minutes=min(i, count - 2)),
    )


def _seed_my_consultations(db, member_id: str, trainer_id: str, count: int) -> None:
    """한 회원이 쌓은 상담 이력 `count` 건.

    대기 중인 요청은 **한 건뿐**이다 — `uq_consultation_requests_pending_trainer` 가
    같은 트레이너에게 보낸 대기 요청을 하나로 막는다. 나머지는 처리된 지난 요청이고,
    회원 목록에는 상태 필터가 없어 그대로 함께 자란다(그래서 상한이 필요하다).
    """
    for i in range(count):
        status = "pending" if i == count - 1 else ("accepted" if i % 2 else "rejected")
        db.add(_consultation(member_id, trainer_id, i, count, status))
    db.commit()


def _seed_inbox(db, trainer_id: str, count: int) -> None:
    """트레이너 인박스에 회원 `count` 명의 미처리 요청을 쌓는다.

    회원마다 한 건씩인 것이 실제 모양이다 — 한 회원이 같은 트레이너에게 대기 요청을
    여러 건 보낼 수는 없다.
    """
    password = hash_password(PASSWORD)  # 한 번만 해싱한다 — 회원 수만큼 돌리면 느리다.
    for i in range(count):
        suffix = uuid4().hex[:8]
        member = User(
            id=f"page-asker-{i:04d}-{suffix}",
            email=f"{EMAIL_PREFIX}asker-{i:04d}-{suffix}@oncare.com",
            name=f"문의 회원 {i}",
            hashed_password=password,
            role="member",
            is_active=True,
        )
        db.add(member)
        db.flush()
        db.add(_consultation(member.id, trainer_id, i, count, "pending"))
    db.commit()


def test_my_consultations_default_page_is_capped(client, db_session, member, trainer):
    """필터가 없어 지난 요청까지 함께 자란다 — 최신 50건."""
    _seed_my_consultations(db_session, member["id"], trainer["id"], _TOTAL)

    rows = _get(client, member["token"], "consultations/me")

    assert len(rows) == 50
    created = [r["created_at"] for r in rows]
    assert created == sorted(created, reverse=True)


def test_my_consultations_cursor_walks_the_whole_list(
    client, db_session, member, trainer
):
    _seed_my_consultations(db_session, member["id"], trainer["id"], _TOTAL)

    seen = _walk(
        client,
        member["token"],
        "consultations/me",
        ("before", "before_id"),
        key=lambda r: r["created_at"],
    )

    assert len(seen) == _TOTAL
    assert len(set(seen)) == _TOTAL


def test_trainer_inbox_is_capped_and_walkable(client, db_session, trainer):
    """`status=all` 은 그 트레이너에게 들어온 요청 전체다 — 여기가 가장 크게 자란다."""
    _seed_inbox(db_session, trainer["id"], _TOTAL)

    first = _get(client, trainer["token"], "trainer/consultations", status="all")
    assert len(first) == 50

    seen = _walk(
        client,
        trainer["token"],
        "trainer/consultations",
        ("before", "before_id"),
        key=lambda r: r["created_at"],
        status="all",
    )
    assert len(seen) == _TOTAL
    assert len(set(seen)) == _TOTAL


def test_pending_count_ignores_pagination(client, db_session, trainer):
    """배지는 DB 에서 센다 — 첫 쪽 안에서 세면 인박스가 길어질수록 조용히 줄어든다."""
    _seed_inbox(db_session, trainer["id"], _TOTAL)

    res = client.get(
        "/v1/trainer/consultations/pending-count", headers=_auth(trainer["token"])
    )
    assert res.status_code == 200, res.text
    assert res.json()["count"] == _TOTAL


# ---------------------------------------------------------------------------
# GET /trainer/clients
# ---------------------------------------------------------------------------
def _seed_roster(db, trainer_id: str, count: int) -> list[str]:
    """담당 회원 `count` 명. 트레이너가 정한 순서(`sort_order`)대로 넣는다."""
    member_ids: list[str] = []
    for i in range(count):
        suffix = uuid4().hex[:8]
        member = User(
            id=f"page-roster-{i:04d}-{suffix}",
            email=f"{EMAIL_PREFIX}roster-{i:04d}-{suffix}@oncare.com",
            name=f"회원 {i}",
            hashed_password=hash_password(PASSWORD),
            role="member",
            is_active=True,
        )
        db.add(member)
        db.flush()
        db.add(
            TrainerClient(
                id=f"tc-page-{i:04d}-{suffix}",
                trainer_id=trainer_id,
                member_id=member.id,
                goal="체력 증진",
                active=True,
                sort_order=i,
            )
        )
        member_ids.append(member.id)
    db.commit()
    return member_ids


def test_roster_default_page_is_capped_and_keeps_trainer_order(
    client, db_session, trainer
):
    """상한을 넘겨도 트레이너가 정한 순서 그대로 앞에서부터 준다."""
    member_ids = _seed_roster(db_session, trainer["id"], _ROSTER_TOTAL)

    rows = _get(client, trainer["token"], "trainer/clients")

    assert len(rows) == 50
    assert [r["id"] for r in rows] == member_ids[:50]


def test_roster_cursor_walks_the_whole_list(client, db_session, trainer):
    """이어 받으면 담당 회원이 한 명도 빠지지 않는다 — 상한이 곧 명단 잘림이면 안 된다."""
    member_ids = _seed_roster(db_session, trainer["id"], _ROSTER_TOTAL)

    seen: list[str] = []
    cursor: dict[str, object] = {}
    for _ in range(10):
        rows = _get(client, trainer["token"], "trainer/clients", limit=25, **cursor)
        if not rows:
            break
        seen.extend(r["id"] for r in rows)
        # 커서는 마지막 카드의 id 하나 — 정렬키(sort_order)는 서버가 찾는다.
        cursor = {"after_id": rows[-1]["id"]}

    assert seen == member_ids


def test_roster_unknown_cursor_is_rejected(client, trainer):
    """명단에 없는 id 로 이어 받으려 하면 422 — 첫 쪽을 다시 주면 제자리를 돈다."""
    res = client.get(
        "/v1/trainer/clients",
        params={"after_id": "no-such-member"},
        headers=_auth(trainer["token"]),
    )
    assert res.status_code == 422
