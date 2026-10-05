"""운동 기록은 오늘(KST)까지만 받는다. (#3042)

포인트 하루 한도는 적립 시점 기준이고 주간 챌린지는 일요일까지의 기록을 센다.
앞날을 받으면 월요일에 화~일 기록을 미리 넣어 하루에 여러 날 몫의 포인트를 받고,
주가 끝나면 챌린지 성공 보상까지 받는다. 이 스위트는

- 스키마: 오늘·지난 날·생략은 통과, 앞날은 식단과 같은 문구로 거절(KST 자정 경계 포함),
- API: 추가(한 건·여러 건)·수정이 앞날을 422 로 막고 아무것도 남기지 않는지,
- 챌린지: 앞날 추가가 막혀 미리 채울 수 없고, 검증 전에 저장된 "미리 적은 기록"은
  판정에서 빠지는지

를 본다. 스키마 단위 테스트는 DB 없이, 나머지는 DB 테스트(로컬 skip, CI 실행)다.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta
from types import SimpleNamespace
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select

from app.core import clock
from tests.exercise_helpers import post_exercise

_FUTURE = "date 는 오늘보다 뒤일 수 없습니다."

#: 기준 주 — 2026-09-14(월) ~ 2026-09-20(일).
MON = date(2026, 9, 14)
TUE = MON + timedelta(days=1)
WED = MON + timedelta(days=2)
SAT = MON + timedelta(days=5)
SUN = MON + timedelta(days=6)
NEXT_MON = MON + timedelta(days=7)
_LABELS = ("월", "화", "수", "목", "금", "토", "일")


@pytest.fixture
def at(monkeypatch):
    """`at(day, hour, minute)` 로 서비스 시각(KST)을 옮긴다."""

    def _set(day: date, hour: int = 10, minute: int = 0) -> None:
        moment = datetime.combine(day, time(hour, minute), tzinfo=clock.SEOUL)
        monkeypatch.setattr(clock, "now", lambda: moment)

    return _set


def _session(**overrides):
    from app.schemas.exercise_api import ExerciseSessionCreate

    body = {"type": "cardio", "name": "걷기", "minutes": 30, **overrides}
    return ExerciseSessionCreate(**body)


def _messages(err: ValidationError) -> list[str]:
    return [e["msg"] for e in err.errors()]


# ---------- 스키마 (DB 없이) ----------


def test_today_and_past_days_are_accepted(at):
    at(WED)
    assert _session(date=WED).date == WED
    assert _session(date=TUE).date == TUE
    assert _session(date=MON - timedelta(days=30)).date == MON - timedelta(days=30)


def test_an_omitted_date_stays_empty_and_means_today(at):
    at(WED)
    assert _session().date is None


def test_tomorrow_is_refused_with_the_diet_wording(at):
    at(WED)
    with pytest.raises(ValidationError) as exc:
        _session(date=WED + timedelta(days=1))
    assert any(_FUTURE in m for m in _messages(exc.value))


def test_the_boundary_is_kst_midnight(at):
    """서버 시계(KST)로 판정한다 — 23:59 엔 내일이 앞날, 자정이 지나면 오늘이다."""
    at(TUE, 23, 59)
    with pytest.raises(ValidationError):
        _session(date=WED)

    at(WED, 0, 0)
    assert _session(date=WED).date == WED


def test_one_future_item_fails_the_whole_list(at):
    from app.schemas.exercise_api import ExerciseSessionsCreate

    at(WED)
    with pytest.raises(ValidationError):
        ExerciseSessionsCreate(
            sessions=[
                {"type": "cardio", "minutes": 30, "date": WED.isoformat()},
                {"type": "cardio", "minutes": 30, "date": SAT.isoformat()},
            ]
        )


def test_diet_and_exercise_share_one_rule(at):
    """비교와 문구는 한 곳(`record_dates`)이다 — 두 기록이 다른 말을 하지 않는다."""
    from app.schemas import diet_api, record_dates

    at(WED)
    assert record_dates.FUTURE_DATE_MESSAGE == _FUTURE
    assert record_dates.not_after_today(WED) == WED
    with pytest.raises(ValueError, match=_FUTURE):
        record_dates.not_after_today(WED + timedelta(days=1))
    with pytest.raises(ValueError, match=_FUTURE):
        diet_api._past_or_today((WED + timedelta(days=1)).isoformat())
    assert diet_api._past_or_today(WED.isoformat()) == WED.isoformat()


def test_written_in_advance_compares_with_the_kst_day_it_was_stored():
    from app.services.weekly_challenge_service import written_in_advance

    stored_monday_night = datetime.combine(MON, time(23, 30), tzinfo=clock.SEOUL)
    row = SimpleNamespace(created_at=stored_monday_night)
    assert written_in_advance(row, TUE) is True
    assert written_in_advance(row, MON) is False
    assert written_in_advance(row, MON - timedelta(days=3)) is False  # 뒤늦게 적은 기록
    # 저장 시각은 UTC 로 들어와도 KST 날짜로 본다(월요일 23:30 KST = 14:30 UTC).
    utc_naive = datetime(2026, 9, 14, 14, 30)
    assert written_in_advance(SimpleNamespace(created_at=utc_naive), TUE) is True
    assert written_in_advance(SimpleNamespace(created_at=None), TUE) is False


# ---------- API (DB) ----------


def _register(client) -> tuple[str, dict[str, str]]:
    email = f"future-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def _sessions_of(db_session, member_id: str) -> int:
    from app.models.models import ExerciseSession

    db_session.expire_all()
    return int(
        db_session.scalar(
            select(func.count())
            .select_from(ExerciseSession)
            .where(ExerciseSession.user_id == member_id)
        )
        or 0
    )


def _ledger_of(db_session, member_id: str) -> int:
    from app.models.models import PointsLedger

    db_session.expire_all()
    return int(
        db_session.scalar(
            select(func.count())
            .select_from(PointsLedger)
            .where(PointsLedger.user_id == member_id)
        )
        or 0
    )


def _walk(day: date | None = None, minutes: int = 30) -> dict:
    body = {"type": "cardio", "name": "걷기", "minutes": minutes, "calories": 0}
    if day is not None:
        body["date"] = day.isoformat()
    return body


def test_a_future_record_is_refused_and_leaves_nothing(client, db_session, at):
    at(WED)
    member_id, h = _register(client)

    r = post_exercise(client, json=_walk(WED + timedelta(days=1)), headers=h)

    assert r.status_code == 422, r.text
    assert _FUTURE in r.text
    assert _sessions_of(db_session, member_id) == 0
    assert _ledger_of(db_session, member_id) == 0


def test_one_future_item_refuses_the_whole_batch(client, db_session, at):
    at(WED)
    member_id, h = _register(client)

    r = client.post(
        "/v1/exercise/sessions",
        json={"sessions": [_walk(WED), _walk(TUE), _walk(SAT)]},
        headers=h,
    )

    assert r.status_code == 422, r.text
    assert _sessions_of(db_session, member_id) == 0
    assert _ledger_of(db_session, member_id) == 0


@pytest.mark.parametrize("offset", [0, 1, 6, None])
def test_today_past_and_omitted_dates_still_save_and_award(client, at, offset):
    at(WED)
    _, h = _register(client)
    day = None if offset is None else WED - timedelta(days=offset)

    r = post_exercise(client, json=_walk(day), headers=h)

    assert r.status_code == 201, r.text
    assert r.json()["points"]["awarded"] == 20
    assert r.json()["date"] == (day or WED).isoformat()


def test_moving_a_record_to_a_future_day_is_refused(client, db_session, at):
    from app.models.models import ExerciseSession

    at(WED)
    _, h = _register(client)
    session_id = post_exercise(client, json=_walk(TUE), headers=h).json()["id"]

    r = client.put(
        f"/v1/exercise/sessions/{session_id}", json=_walk(SAT, minutes=45), headers=h
    )

    assert r.status_code == 422, r.text
    db_session.expire_all()
    row = db_session.get(ExerciseSession, session_id)
    assert row.day_label == "화"
    assert row.week_start == MON.isoformat()
    assert row.minutes == 30


def test_moving_a_record_to_a_past_day_and_editing_without_a_date_still_work(
    client, at
):
    at(WED)
    _, h = _register(client)
    session_id = post_exercise(client, json=_walk(WED), headers=h).json()["id"]

    moved = client.put(
        f"/v1/exercise/sessions/{session_id}", json=_walk(MON), headers=h
    )
    assert moved.status_code == 200, moved.text
    assert moved.json()["date"] == MON.isoformat()

    kept = client.put(
        f"/v1/exercise/sessions/{session_id}", json=_walk(minutes=50), headers=h
    )
    assert kept.status_code == 200, kept.text
    assert kept.json()["date"] == MON.isoformat()
    assert kept.json()["minutes"] == 50


# ---------- 주간 챌린지 (DB) ----------


def _challenger(client, db_session, *, goal: int = 3) -> tuple[str, dict[str, str]]:
    from app.models.models import HealthProfile

    member_id, h = _register(client)
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        profile = HealthProfile(user_id=member_id)
        db_session.add(profile)
    profile.activity_points = 1000
    profile.weekly_workout_goal = goal
    db_session.commit()
    return member_id, h


def _stored_record(db_session, member_id: str, day: date, *, stored_on: date) -> None:
    """[day] 의 기록을 [stored_on] 정오(KST)에 저장된 것으로 표에 직접 넣는다.

    검증이 들어가기 전에 저장된 앞날 기록을 재현한다.
    """
    from app.models.models import ExerciseSession
    from app.services import exercise_activity

    db_session.add(
        ExerciseSession(
            id=f"ex-{uuid4().hex[:12]}",
            user_id=member_id,
            week_start=(day - timedelta(days=day.weekday())).isoformat(),
            day_label=_LABELS[day.weekday()],
            type="cardio",
            minutes=30,
            calories=120,
            source="member",
            completed_at=exercise_activity.noon(day),
            created_at=datetime.combine(stored_on, time(12, 0), tzinfo=clock.SEOUL),
        )
    )
    db_session.commit()


def _settled(client, h) -> dict:
    r = client.get("/v1/me/challenges", headers=h)
    assert r.status_code == 200, r.text
    return next(c for c in r.json() if c["week_start"] == MON.isoformat())


def test_a_member_cannot_fill_the_week_in_advance_through_the_api(
    client, db_session, at
):
    at(MON)
    _, h = _challenger(client, db_session, goal=3)
    assert client.post(
        "/v1/me/challenges/weekly/join", json={}, headers=h
    ).status_code == 201

    assert post_exercise(client, json=_walk(MON), headers=h).status_code == 201
    for day in (TUE, WED, SAT):
        r = post_exercise(client, json=_walk(day), headers=h)
        assert r.status_code == 422, r.text

    at(NEXT_MON, 0, 1)
    assert _settled(client, h)["status"] == "failed"


def test_records_written_in_advance_do_not_count_at_settlement(
    client, db_session, at
):
    at(MON)
    member_id, h = _challenger(client, db_session, goal=3)
    assert client.post(
        "/v1/me/challenges/weekly/join", json={}, headers=h
    ).status_code == 201
    # 월요일에 화·수·토를 미리 적어 둔 기록(검증 전에 저장된 것).
    _stored_record(db_session, member_id, MON, stored_on=MON)
    for day in (TUE, WED, SAT):
        _stored_record(db_session, member_id, day, stored_on=MON)

    at(NEXT_MON, 0, 1)
    settled = _settled(client, h)

    assert settled["status"] == "failed"
    assert settled["rewarded"] == 0


def test_records_written_on_the_day_or_later_still_count(client, db_session, at):
    at(MON)
    member_id, h = _challenger(client, db_session, goal=3)
    assert client.post(
        "/v1/me/challenges/weekly/join", json={}, headers=h
    ).status_code == 201
    _stored_record(db_session, member_id, MON, stored_on=MON)  # 그날 적음
    _stored_record(db_session, member_id, WED, stored_on=WED)  # 그날 적음
    _stored_record(db_session, member_id, TUE, stored_on=SUN)  # 뒤늦게 적음

    at(NEXT_MON, 0, 1)
    settled = _settled(client, h)

    assert settled["status"] == "succeeded"
    assert settled["rewarded"] == 200
