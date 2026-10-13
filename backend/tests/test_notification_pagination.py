"""알림 목록 페이지네이션과 보존 기간. (#965) DB 필요.

`GET /notifications` 는 사용자의 알림을 **상한 없이** 전부 돌려줬다. 알림을 만드는
훅은 여럿인데(식단·운동·일정) 지우는 경로가 없어, 오래 쓴 계정일수록 알림 탭을 열
때마다 응답이 선형으로 커졌다.

여기서 확인하는 것:
  1. 기본 상한이 있고, 커서로 다음 쪽을 빠짐없이 이어 받는다.
  2. 파라미터 없이 부르던 기존 클라이언트가 깨지지 않는다.
  3. 미확인 배지 수는 페이지네이션과 무관하게 전체 기준이다.
  4. 정리 대상 선정이 **읽은 오래된 알림만** 고른다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.models.models import Notification
from app.services import notification_service

#: 커서 경계를 보려면 기본 상한(50)을 넘겨야 한다.
_TOTAL = 120

_BASE = datetime(2026, 1, 1, 9, 0, tzinfo=timezone.utc)


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def member(client) -> dict:
    """알림이 없는 새 회원. 시드 계정은 다른 테스트가 알림을 더해 수가 흔들린다."""
    email = f"noti-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "알림테스터"},
    )
    assert created.status_code == 201, created.text
    logged_in = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    assert logged_in.status_code == 200, logged_in.text
    return {"id": created.json()["id"], "token": logged_in.json()["access_token"]}


def _seed(db, user_id: str, count: int, *, read: bool = False) -> list[str]:
    """오래된 것부터 `count` 건. 신호를 남기려고 마지막 두 건은 **같은 시각**이다.

    같은 created_at 이 실제로 나온다 — 훅 하나가 여러 알림을 한 트랜잭션에 넣는다.
    시각만으로 자르는 커서라면 이 경계에서 알림이 빠지거나 겹친다.
    """
    ids: list[str] = []
    for i in range(count):
        # 마지막 두 건은 같은 시각(i, i-1 이 아니라 count-2 를 공유).
        offset = min(i, count - 2)
        row = Notification(
            id=f"noti-{i:04d}-{uuid4().hex[:8]}",
            user_id=user_id,
            title=f"알림 {i}",
            body="",
            category="reminder",
            read=read,
            created_at=_BASE + timedelta(minutes=offset),
        )
        db.add(row)
        ids.append(row.id)
    db.commit()
    return ids


def _page(client, token: str, **params) -> list[dict]:
    res = client.get("/v1/notifications", params=params, headers=_h(token))
    assert res.status_code == 200, res.text
    return res.json()


# --------------------------------------------------------------------------
# 목록 상한과 커서
# --------------------------------------------------------------------------
def test_default_page_is_capped_and_newest_first(client, db_session, member):
    """파라미터 없는 호출은 그대로 동작하되 최신 50건까지만 준다."""
    _seed(db_session, member["id"], _TOTAL)

    rows = _page(client, member["token"])

    assert len(rows) == 50
    assert rows[0]["title"] == f"알림 {_TOTAL - 1}"
    times = [r["created_at"] for r in rows]
    assert times == sorted(times, reverse=True)


def test_limit_is_bounded(client, member):
    """채팅 스레드와 같은 규약(1~100)."""
    assert len(_page(client, member["token"], limit=1)) <= 1
    assert client.get(
        "/v1/notifications", params={"limit": 0}, headers=_h(member["token"])
    ).status_code == 422
    assert client.get(
        "/v1/notifications", params={"limit": 101}, headers=_h(member["token"])
    ).status_code == 422


def test_cursor_walks_the_whole_list_without_gaps_or_repeats(
    client, db_session, member
):
    """쪽을 이어 받으면 전체가 정확히 한 번씩 나온다 — 동시각 경계 포함."""
    _seed(db_session, member["id"], _TOTAL)

    seen: list[str] = []
    cursor: dict[str, str] = {}
    for _ in range(20):  # 넉넉한 상한 — 무한 루프로 매달리지 않게.
        rows = _page(client, member["token"], limit=25, **cursor)
        if not rows:
            break
        seen.extend(r["id"] for r in rows)
        last = rows[-1]
        cursor = {"before": last["created_at"], "before_id": last["id"]}

    assert len(seen) == _TOTAL
    assert len(set(seen)) == _TOTAL, "같은 알림이 두 쪽에 걸쳐 나왔다"


def test_cursor_without_before_id_still_pages(client, db_session, member):
    """`before` 만 줘도 동작한다 — tie-break 없이 시각만으로 자른다."""
    _seed(db_session, member["id"], 10)

    first = _page(client, member["token"], limit=4)
    older = _page(client, member["token"], limit=4, before=first[-1]["created_at"])

    assert older
    assert all(r["created_at"] <= first[-1]["created_at"] for r in older)


def test_broken_cursor_is_rejected(client, member):
    res = client.get(
        "/v1/notifications",
        params={"before": "어제"},
        headers=_h(member["token"]),
    )
    assert res.status_code == 422


def test_unread_count_ignores_the_page_size(client, db_session, member):
    """배지는 전체 기준이다 — DB 에서 세므로 쪽 나눔과 무관하다."""
    _seed(db_session, member["id"], _TOTAL)

    counted = client.get(
        "/v1/notifications/unread-count", headers=_h(member["token"])
    ).json()["unread"]

    assert counted == _TOTAL
    assert len(_page(client, member["token"])) == 50


# --------------------------------------------------------------------------
# 보존 기간 — 정리 대상 선정
# --------------------------------------------------------------------------
def test_only_read_notifications_expire(client, db_session, member):
    """미확인은 아무리 오래돼도 남는다. 못 본 알림을 서버가 지우면 안 된다."""
    old = _BASE
    now = old + timedelta(days=notification_service.READ_RETENTION_DAYS + 1)
    db_session.add_all(
        [
            Notification(
                id=f"noti-read-{uuid4().hex[:8]}", user_id=member["id"],
                title="읽은 옛 알림", body="", category="reminder",
                read=True, created_at=old,
            ),
            Notification(
                id=f"noti-unread-{uuid4().hex[:8]}", user_id=member["id"],
                title="안 읽은 옛 알림", body="", category="reminder",
                read=False, created_at=old,
            ),
        ]
    )
    db_session.commit()

    targets = notification_service.expired_notifications(
        db_session, now=now, user_id=member["id"]
    )

    assert [t.title for t in targets] == ["읽은 옛 알림"]


def test_recent_read_notifications_are_kept(client, db_session, member):
    """보존 기간 안쪽은 읽었어도 남는다."""
    created = _BASE
    just_inside = created + timedelta(
        days=notification_service.READ_RETENTION_DAYS - 1
    )
    db_session.add(
        Notification(
            id=f"noti-recent-{uuid4().hex[:8]}", user_id=member["id"],
            title="어제 읽은 알림", body="", category="reminder",
            read=True, created_at=created,
        )
    )
    db_session.commit()

    assert (
        notification_service.expired_notifications(
            db_session, now=just_inside, user_id=member["id"]
        )
        == []
    )


def test_expiry_is_scoped_to_one_user(client, db_session, member):
    """`user_id` 를 주면 그 사람 것만 고른다 — 한 사람만 정리할 때 쓴다."""
    other = client.post(
        "/v1/auth/register",
        json={
            "email": f"noti-other-{uuid4().hex[:8]}@oncare.com",
            "password": "pw-12345!",
            "name": "다른 회원",
        },
    )
    assert other.status_code == 201, other.text
    other_id = other.json()["id"]

    now = _BASE + timedelta(days=notification_service.READ_RETENTION_DAYS + 1)
    for owner in (member["id"], other_id):
        db_session.add(
            Notification(
                id=f"noti-scope-{uuid4().hex[:8]}", user_id=owner,
                title="읽은 옛 알림", body="", category="reminder",
                read=True, created_at=_BASE,
            )
        )
    db_session.commit()

    mine = notification_service.expired_notifications(
        db_session, now=now, user_id=member["id"]
    )

    assert [t.user_id for t in mine] == [member["id"]]


def test_retention_window_must_be_positive(client, db_session, member):
    """0 일이면 '전부 삭제'가 된다. 실수 한 번의 대가가 너무 커서 막는다."""
    with pytest.raises(ValueError):
        notification_service.expired_notifications(db_session, days=0)


def test_purge_removes_exactly_what_was_selected(client, db_session, member):
    """지운 뒤에는 대상만 사라지고 나머지는 그대로다."""
    now = _BASE + timedelta(days=notification_service.READ_RETENTION_DAYS + 1)
    _seed(db_session, member["id"], 3, read=True)   # 오래된 읽은 알림
    kept = Notification(
        id=f"noti-keep-{uuid4().hex[:8]}", user_id=member["id"],
        title="최근 알림", body="", category="reminder",
        read=True, created_at=now - timedelta(days=1),
    )
    db_session.add(kept)
    db_session.commit()

    removed = notification_service.purge_expired(
        db_session, now=now, user_id=member["id"]
    )

    assert removed == 3
    left = db_session.query(Notification).filter(
        Notification.user_id == member["id"]
    ).all()
    assert [row.id for row in left] == [kept.id]


def test_purge_deletes_in_one_statement(client, db_session, member):
    """#3242: 대상을 한 건씩 읽어 지우지 않고 `DELETE` 한 번으로 지운다."""
    from sqlalchemy import event

    now = _BASE + timedelta(days=notification_service.READ_RETENTION_DAYS + 1)
    _seed(db_session, member["id"], 5, read=True)

    deletes: list[str] = []

    def count(conn, cursor, statement, parameters, context, executemany):
        if statement.lstrip().upper().startswith("DELETE"):
            deletes.append(statement)

    engine = db_session.get_bind()
    event.listen(engine, "before_cursor_execute", count)
    try:
        removed = notification_service.purge_expired(
            db_session, now=now, user_id=member["id"]
        )
    finally:
        event.remove(engine, "before_cursor_execute", count)

    assert removed == 5
    assert len(deletes) == 1
    assert db_session.query(Notification).filter(
        Notification.user_id == member["id"]
    ).count() == 0
