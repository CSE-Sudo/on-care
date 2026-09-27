"""트레이너 알림함 커서 페이지네이션. (#2293) DB 필요.

`GET /trainer/notifications` 는 최신 100건에서 끊기고 커서가 없었다. 미읽음 배지
(`/trainer/notifications/unread-count`)는 전체를 세서, 100건보다 오래된 미읽음은
배지에만 잡히고 목록 어디에서도 볼 수 없었다.

여기서 확인하는 것:
  1. 서비스(`list_for_trainer`)가 `(created_at, id)` 순서로 한 쪽을 자르고, 다음
     쪽이 있을 때만 커서 행을 돌려준다 — 동시각 경계 포함.
  2. 파라미터 없는 호출은 전과 같다(최신 100건, 같은 필드).
  3. 다음 쪽 커서가 응답 헤더로 실리고, 헤더를 따라가면 전체가 정확히 한 번씩 나온다.
  4. 잘못된 커서·범위를 벗어난 `limit` 은 422, 회원 토큰은 403, 남의 알림은 섞이지 않는다.
  5. 미읽음 배지와 모두 읽음은 쪽 나눔과 무관하게 전체를 대상으로 한다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.core.config import get_settings
from app.core.security import hash_password
from app.models.models import Notification, Place, TrainerProfile, User
from app.services import notification_service
from app.services import notification_templates as nt

EMAIL_PREFIX = "noti-page-"
PLACE_PREFIX = "noti-page-place-"
PASSWORD = "noti-page-pw-1234"

#: 기본 쪽(100건)을 넘겨야 두 번째 쪽이 생긴다.
_TOTAL = 130

_BASE = datetime(2026, 1, 1, 9, 0, tzinfo=timezone.utc)

NEXT_BEFORE = "x-next-before"
NEXT_BEFORE_ID = "x-next-before-id"


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
        db_session.query(Notification).filter(
            Notification.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
        synchronize_session=False
    )
    db_session.commit()


def _h(token: str, extra: dict | None = None) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}", **(extra or {})}


def _login(client, email: str, password: str = PASSWORD) -> str:
    res = client.post("/v1/auth/login", data={"username": email, "password": password})
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


@pytest.fixture()
def make_trainer(client, db_session):
    """알림이 하나도 없는 새 트레이너 `(토큰, id)`.

    시드 트레이너는 다른 테스트가 알림을 더해 수가 흔들린다.
    """

    def _make() -> tuple[str, str]:
        suffix = uuid4().hex[:10]
        place = Place(
            id=f"{PLACE_PREFIX}{suffix}", name="쪽 나눔 헬스장", category="fitness", address="서울"
        )
        db_session.add(place)
        email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
        trainer = User(
            id=f"noti-page-trainer-{suffix}",
            email=email,
            name=f"쪽 나눔 트레이너 {suffix[:4]}",
            hashed_password=hash_password(PASSWORD),
            role="trainer",
            is_active=True,
        )
        db_session.add(trainer)
        db_session.flush()
        db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=place.id))
        db_session.commit()
        return _login(client, email), trainer.id

    return _make


@pytest.fixture()
def trainer(make_trainer) -> tuple[str, str]:
    return make_trainer()


def _seed(
    db,
    user_id: str,
    count: int,
    *,
    read: bool = False,
    same_time_tail: int = 2,
    base: datetime = _BASE,
) -> list[str]:
    """오래된 것부터 `count` 건. 가장 최근 [same_time_tail] 건은 **같은 시각**이다.

    같은 created_at 이 실제로 나온다 — 훅 하나가 여러 알림을 한 트랜잭션에 넣는다.
    시각만으로 자르는 커서라면 이 경계에서 알림이 빠지거나 겹친다.
    """
    ids: list[str] = []
    shared = count - same_time_tail
    for i in range(count):
        offset = min(i, shared)
        row = Notification(
            id=f"noti-{user_id[-6:]}-{i:04d}",
            user_id=user_id,
            title=f"알림 {i}",
            body="",
            category="message",
            read=read,
            created_at=base + timedelta(minutes=offset),
        )
        db.add(row)
        ids.append(row.id)
    db.commit()
    return ids


def _newest_first(db, user_id: str) -> list[str]:
    """DB 가 정하는 기대 순서 — `(created_at, id)` 내림차순."""
    rows = (
        db.query(Notification.id, Notification.created_at)
        .filter(Notification.user_id == user_id)
        .all()
    )
    return [r.id for r in sorted(rows, key=lambda r: (r.created_at, r.id), reverse=True)]


def _get(client, token: str, *, headers: dict | None = None, **params):
    return client.get(
        "/v1/trainer/notifications", params=params, headers=_h(token, headers)
    )


def _walk(client, token: str, **params) -> tuple[list[str], int]:
    """헤더 커서를 따라 끝까지 읽는다. `(id 순서, 쪽 수)`."""
    seen: list[str] = []
    cursor: dict[str, str] = {}
    for pages in range(1, 50):  # 무한 루프로 매달리지 않게.
        res = _get(client, token, **params, **cursor)
        assert res.status_code == 200, res.text
        seen.extend(r["id"] for r in res.json())
        if NEXT_BEFORE not in res.headers:
            assert NEXT_BEFORE_ID not in res.headers
            return seen, pages
        cursor = {
            "before": res.headers[NEXT_BEFORE],
            "before_id": res.headers[NEXT_BEFORE_ID],
        }
    raise AssertionError("커서가 끝나지 않는다")


# --------------------------------------------------------------------------
# 서비스 — list_for_trainer
# --------------------------------------------------------------------------
def test_service_first_page_and_cursor_row(db_session, trainer):
    _, trainer_id = trainer
    _seed(db_session, trainer_id, 5)
    expected = _newest_first(db_session, trainer_id)

    rows, last = notification_service.list_for_trainer(db_session, trainer_id, limit=3)

    assert [r.id for r in rows] == expected[:3]
    assert last is not None and last.id == expected[2]


def test_service_exact_last_page_has_no_cursor(db_session, trainer):
    """딱 [limit] 건이면 다음 쪽이 없다 — 빈 쪽을 한 번 더 부르게 하지 않는다."""
    _, trainer_id = trainer
    _seed(db_session, trainer_id, 4)

    rows, last = notification_service.list_for_trainer(db_session, trainer_id, limit=4)

    assert len(rows) == 4
    assert last is None


def test_service_empty_inbox(db_session, trainer):
    _, trainer_id = trainer
    rows, last = notification_service.list_for_trainer(db_session, trainer_id)
    assert rows == []
    assert last is None


def test_service_default_limit_is_the_old_cap(db_session, trainer):
    """파라미터 없는 호출이 전과 같은 결과를 받게 기본 건수는 예전 상한 그대로다."""
    assert notification_service.TRAINER_PAGE_DEFAULT == 100
    assert notification_service.TRAINER_PAGE_MAX == 100
    _, trainer_id = trainer
    _seed(db_session, trainer_id, 101)

    rows, last = notification_service.list_for_trainer(db_session, trainer_id)

    assert len(rows) == 100
    assert last is rows[-1]


def test_service_composite_cursor_splits_identical_timestamps(db_session, trainer):
    """같은 시각 여러 건 가운데서 잘려도 빠지거나 겹치지 않는다."""
    _, trainer_id = trainer
    _seed(db_session, trainer_id, 6, same_time_tail=4)
    expected = _newest_first(db_session, trainer_id)

    first, last = notification_service.list_for_trainer(db_session, trainer_id, limit=2)
    assert last is not None
    # 경계가 같은 시각 묶음 한가운데에 떨어진다.
    assert first[0].created_at == first[1].created_at
    rest, tail = notification_service.list_for_trainer(
        db_session,
        trainer_id,
        limit=10,
        before=last.created_at,
        before_id=last.id,
    )

    assert [r.id for r in first + rest] == expected
    assert tail is None


def test_service_time_only_cursor_skips_the_whole_instant(db_session, trainer):
    """`before_id` 가 없으면 그 시각 전부를 건너뛴다(회원 알림과 같은 규칙)."""
    _, trainer_id = trainer
    _seed(db_session, trainer_id, 5, same_time_tail=3)
    newest = _newest_first(db_session, trainer_id)
    instant = db_session.get(Notification, newest[0]).created_at

    rows, _ = notification_service.list_for_trainer(
        db_session, trainer_id, before=instant
    )

    assert all(r.created_at < instant for r in rows)
    assert [r.id for r in rows] == newest[3:]


def test_service_only_reads_the_given_trainer(db_session, make_trainer):
    _, mine = make_trainer()
    _, theirs = make_trainer()
    _seed(db_session, mine, 3)
    _seed(db_session, theirs, 3)

    rows, _ = notification_service.list_for_trainer(db_session, mine, limit=100)

    assert {r.user_id for r in rows} == {mine}


# --------------------------------------------------------------------------
# API — 기존 호출과의 호환
# --------------------------------------------------------------------------
def test_no_params_keeps_the_old_shape_and_cap(client, db_session, trainer):
    token, trainer_id = trainer
    _seed(db_session, trainer_id, _TOTAL)
    expected = _newest_first(db_session, trainer_id)

    res = _get(client, token)

    assert res.status_code == 200, res.text
    body = res.json()
    assert isinstance(body, list)
    assert [r["id"] for r in body] == expected[:100]
    assert set(body[0]) >= {
        "id",
        "title",
        "body",
        "category",
        "read",
        "created_at",
        "time_ago",
        "subject_id",
        "template",
        "args",
        "target_date",
    }


def test_short_inbox_has_no_cursor_headers(client, db_session, trainer):
    token, trainer_id = trainer
    _seed(db_session, trainer_id, 3)

    res = _get(client, token)

    assert res.status_code == 200, res.text
    assert len(res.json()) == 3
    assert NEXT_BEFORE not in res.headers
    assert NEXT_BEFORE_ID not in res.headers


def test_empty_inbox_is_an_empty_list(client, trainer):
    token, _ = trainer
    res = _get(client, token)
    assert res.status_code == 200, res.text
    assert res.json() == []
    assert NEXT_BEFORE not in res.headers


# --------------------------------------------------------------------------
# API — 커서
# --------------------------------------------------------------------------
def test_cursor_headers_point_at_the_last_row(client, db_session, trainer):
    token, trainer_id = trainer
    _seed(db_session, trainer_id, _TOTAL)

    res = _get(client, token)
    last = res.json()[-1]

    assert res.headers[NEXT_BEFORE_ID] == last["id"]
    assert datetime.fromisoformat(res.headers[NEXT_BEFORE]) == datetime.fromisoformat(
        last["created_at"].replace("Z", "+00:00")
    )


def test_second_page_continues_after_the_first(client, db_session, trainer):
    token, trainer_id = trainer
    _seed(db_session, trainer_id, _TOTAL)
    expected = _newest_first(db_session, trainer_id)

    first = _get(client, token)
    second = _get(
        client,
        token,
        before=first.headers[NEXT_BEFORE],
        before_id=first.headers[NEXT_BEFORE_ID],
    )

    assert second.status_code == 200, second.text
    assert [r["id"] for r in second.json()] == expected[100:]
    # 마지막 쪽 — 커서가 없다.
    assert NEXT_BEFORE not in second.headers


def test_walking_the_headers_returns_everything_once(client, db_session, trainer):
    token, trainer_id = trainer
    _seed(db_session, trainer_id, _TOTAL, same_time_tail=7)
    expected = _newest_first(db_session, trainer_id)

    seen, pages = _walk(client, token, limit=9)

    assert seen == expected
    assert len(seen) == len(set(seen))
    assert pages == -(-_TOTAL // 9)


@pytest.mark.parametrize("limit", [1, 2, 3, 5])
def test_identical_timestamps_across_page_boundaries(
    client, db_session, trainer, limit
):
    """모든 알림이 같은 시각이어도 쪽 경계에서 빠지거나 겹치지 않는다."""
    token, trainer_id = trainer
    _seed(db_session, trainer_id, 8, same_time_tail=8)
    expected = _newest_first(db_session, trainer_id)

    seen, _ = _walk(client, token, limit=limit)

    assert seen == expected


def test_exact_multiple_ends_without_an_empty_page(client, db_session, trainer):
    token, trainer_id = trainer
    _seed(db_session, trainer_id, 10)

    seen, pages = _walk(client, token, limit=5)

    assert len(seen) == 10
    assert pages == 2


def test_offsetless_cursor_is_read_as_utc(client, db_session, trainer):
    """오프셋 없는 커서는 UTC 로 읽는다 — 서버 타임존에 따라 경계가 밀리지 않는다."""
    token, trainer_id = trainer
    _seed(db_session, trainer_id, 5, same_time_tail=1)
    expected = _newest_first(db_session, trainer_id)
    third = db_session.get(Notification, expected[2]).created_at
    naive = third.astimezone(timezone.utc).replace(tzinfo=None).isoformat()

    res = _get(client, token, before=naive)

    assert res.status_code == 200, res.text
    assert [r["id"] for r in res.json()] == expected[3:]


def test_paged_rows_keep_template_target_and_locale(client, db_session, trainer):
    """두 번째 쪽도 첫 쪽과 같은 필드(#2302 틀·인자, #2292 목적지 날짜)와 언어로 온다."""
    token, trainer_id = trainer
    _seed(db_session, trainer_id, 3, base=_BASE + timedelta(days=1))
    old = Notification(
        id=f"noti-{trainer_id[-6:]}-old",
        user_id=trainer_id,
        category="reservation",
        read=False,
        subject_id="member-1",
        target_date="2026-01-05",
        created_at=_BASE,
        **notification_service.texts(
            title=None,
            template=nt.TRAINER_MEMBER_RENAMED,
            template_args={"old_name": "이지수", "new_name": "Jisoo"},
        ),
    )
    db_session.add(old)
    db_session.commit()

    first = _get(client, token, limit=3, headers={"Accept-Language": "en"})
    second = _get(
        client,
        token,
        limit=3,
        before=first.headers[NEXT_BEFORE],
        before_id=first.headers[NEXT_BEFORE_ID],
        headers={"Accept-Language": "en"},
    )

    assert second.status_code == 200, second.text
    [row] = second.json()
    assert row["id"] == old.id
    assert row["template"] == nt.TRAINER_MEMBER_RENAMED
    assert row["args"] == {"old_name": "이지수", "new_name": "Jisoo"}
    assert row["target_date"] == "2026-01-05"
    assert row["subject_id"] == "member-1"
    assert row["title"] == "Member renamed"
    assert row["time_ago"].endswith("ago")


# --------------------------------------------------------------------------
# API — 잘못된 요청과 권한
# --------------------------------------------------------------------------
@pytest.mark.parametrize("limit", [0, -1, 101])
def test_limit_out_of_range_is_422(client, trainer, limit):
    token, _ = trainer
    assert _get(client, token, limit=limit).status_code == 422


def test_limit_upper_bound_is_accepted(client, trainer):
    token, _ = trainer
    assert _get(client, token, limit=100).status_code == 200


@pytest.mark.parametrize("before", ["어제", "2026-13-01", "not-a-date", "12345abc"])
def test_malformed_cursor_is_422(client, trainer, before):
    token, _ = trainer
    res = _get(client, token, before=before)
    assert res.status_code == 422, res.text


def test_tie_break_without_a_time_is_422(client, trainer):
    """시각 없이 id 만 오면 어디서 자를지 모른다 — 첫 쪽을 조용히 주지 않는다."""
    token, _ = trainer
    res = _get(client, token, before_id="noti-anything")
    assert res.status_code == 422, res.text


def test_member_token_cannot_page_the_trainer_inbox(client):
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:8]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "쪽 나눔 회원"},
    )
    assert created.status_code == 201, created.text
    token = _login(client, email)

    res = _get(client, token, limit=5, before=_BASE.isoformat(), before_id="x")

    assert res.status_code == 403


def test_anonymous_request_is_rejected(client):
    res = client.get("/v1/trainer/notifications", params={"limit": 5})
    assert res.status_code in (401, 403)


def test_cursor_never_reaches_into_another_trainers_inbox(
    client, db_session, make_trainer
):
    """남의 알림 id·시각을 커서로 넣어도 내 알림만 나온다."""
    token, mine = make_trainer()
    _, theirs = make_trainer()
    _seed(db_session, mine, 4)
    their_ids = _seed(db_session, theirs, 6, base=_BASE + timedelta(days=2))
    their_newest = db_session.get(Notification, their_ids[-1])

    res = _get(
        client,
        token,
        before=(their_newest.created_at + timedelta(minutes=1)).isoformat(),
        before_id=their_newest.id,
    )

    assert res.status_code == 200, res.text
    ids = [r["id"] for r in res.json()]
    assert len(ids) == 4
    assert not set(ids) & set(their_ids)


# --------------------------------------------------------------------------
# 배지·읽음 처리는 쪽과 무관
# --------------------------------------------------------------------------
def test_unread_badge_counts_beyond_the_first_page(client, db_session, trainer):
    token, trainer_id = trainer
    _seed(db_session, trainer_id, _TOTAL)

    unread = client.get("/v1/trainer/notifications/unread-count", headers=_h(token))

    assert unread.status_code == 200, unread.text
    assert unread.json()["unread"] == _TOTAL


def test_old_unread_is_reachable_through_the_cursor(client, db_session, trainer):
    """이 이슈의 증상 — 첫 쪽보다 오래된 미읽음도 목록에서 찾아 읽을 수 있다."""
    token, trainer_id = trainer
    _seed(db_session, trainer_id, _TOTAL, read=True)
    oldest = Notification(
        id=f"noti-{trainer_id[-6:]}-stale",
        user_id=trainer_id,
        title="오래된 미읽음",
        body="",
        category="message",
        read=False,
        created_at=_BASE - timedelta(days=1),
    )
    db_session.add(oldest)
    db_session.commit()

    first_ids = [r["id"] for r in _get(client, token).json()]
    assert oldest.id not in first_ids
    seen, _ = _walk(client, token)
    assert oldest.id in seen

    marked = client.post(
        f"/v1/trainer/notifications/{oldest.id}/read", headers=_h(token)
    )
    assert marked.status_code == 200, marked.text
    unread = client.get("/v1/trainer/notifications/unread-count", headers=_h(token))
    assert unread.json()["unread"] == 0


def test_read_all_marks_every_page(client, db_session, trainer):
    token, trainer_id = trainer
    _seed(db_session, trainer_id, _TOTAL)

    res = client.post("/v1/trainer/notifications/read-all", headers=_h(token))

    assert res.status_code == 200, res.text
    assert res.json()["marked_read"] == _TOTAL
    seen_read = []
    cursor: dict[str, str] = {}
    while True:
        page = _get(client, token, **cursor)
        seen_read.extend(r["read"] for r in page.json())
        if NEXT_BEFORE not in page.headers:
            break
        cursor = {
            "before": page.headers[NEXT_BEFORE],
            "before_id": page.headers[NEXT_BEFORE_ID],
        }
    assert len(seen_read) == _TOTAL
    assert all(seen_read)
    unread = client.get("/v1/trainer/notifications/unread-count", headers=_h(token))
    assert unread.json()["unread"] == 0


def test_read_all_leaves_other_trainers_alone(client, db_session, make_trainer):
    token, mine = make_trainer()
    other_token, theirs = make_trainer()
    _seed(db_session, mine, 3)
    _seed(db_session, theirs, 3)

    client.post("/v1/trainer/notifications/read-all", headers=_h(token))

    unread = client.get(
        "/v1/trainer/notifications/unread-count", headers=_h(other_token)
    )
    assert unread.json()["unread"] == 3


# --------------------------------------------------------------------------
# 브라우저가 커서 헤더를 읽을 수 있는가
# --------------------------------------------------------------------------
def test_cursor_headers_are_exposed_to_the_browser(client, db_session, trainer):
    """CORS 가 헤더를 노출하지 않으면 트레이너 웹은 늘 마지막 쪽이라고 읽는다."""
    token, trainer_id = trainer
    _seed(db_session, trainer_id, 3)
    settings = get_settings()
    origin = (
        "http://localhost:5173"
        if settings.is_cors_wildcard or not settings.cors_origin_list
        else settings.cors_origin_list[0]
    )

    res = _get(client, token, limit=1, headers={"Origin": origin})

    assert res.status_code == 200, res.text
    exposed = {
        h.strip().lower()
        for h in res.headers.get("access-control-expose-headers", "").split(",")
    }
    assert {NEXT_BEFORE, NEXT_BEFORE_ID} <= exposed
