"""트레이너가 보는 회원 기간 조회의 응답 내용. (#2910)

트레이너 화면의 기간 그래프는 세 경로를 읽는다.

* `GET /trainer/clients/{id}/diet/days`      — 회원 `GET /diet/days` 와 같은 규칙
* `GET /trainer/clients/{id}/exercise/weeks` — 회원 `GET /exercise/weeks` 와 같은 규칙
* `GET /trainer/clients/{id}/records/span`   — 회원 `GET /me/records/span` 과 같다

지금까지는 해제된 회원에게 404 인지(#2281)만 봤고, 열렸을 때 **무엇을 돌려주는지**는
보지 않았다. 여기서는 같은 회원·같은 기록으로 회원 경로와 트레이너 경로를 함께 불러
본문이 같은지 대조하고, 트레이너 경로에만 있는 조건(담당 확인·회원 프로필의 목표)을
본다.

"오늘" 을 목요일(2026-09-17, KST)로 고정한다. DB 필요(로컬 skip, CI 실행).
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select, text

from app.core import clock
from app.core.security import create_access_token
from app.models.models import DietEntry, HealthProfile, TrainerClient, User
from tests.exercise_helpers import post_exercise

THURSDAY = datetime(2026, 9, 17, 10, 0, tzinfo=clock.SEOUL)
TODAY = "2026-09-17"
THIS_MONDAY = "2026-09-14"
GUARD_DETAIL = "담당 고객을 찾을 수 없습니다."
PASSWORD = "period-pw-2910"


@pytest.fixture
def thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@dataclass
class Linked:
    trainer_id: str
    member_id: str
    trainer_headers: dict[str, str]
    member_headers: dict[str, str]

    def trainer_path(self, suffix: str) -> str:
        return f"/v1/trainer/clients/{self.member_id}{suffix}"


def _new_member(client, db_session) -> tuple[str, dict[str, str]]:
    email = f"period2910-{uuid4().hex[:8]}@oncare.com"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "기간 회원"},
    )
    assert r.status_code in (200, 201), r.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    ).json()["access_token"]
    headers = _h(token)
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    if (
        db_session.scalar(
            select(HealthProfile).where(HealthProfile.user_id == member_id)
        )
        is None
    ):
        db_session.add(HealthProfile(user_id=member_id))
        db_session.commit()
    return member_id, headers


def _new_trainer(db_session) -> tuple[str, dict[str, str]]:
    trainer_id = f"period2910-trainer-{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="기간 트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    db_session.commit()
    return trainer_id, _h(create_access_token(trainer_id))


def _link(db_session, trainer_id: str, member_id: str) -> None:
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
            data_consent_at=THURSDAY,
        )
    )
    db_session.commit()


def _cleanup(db_session, user_ids: list[str]) -> None:
    db_session.rollback()
    db_session.expire_all()
    db_session.execute(
        text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": user_ids}
    )
    db_session.commit()


@pytest.fixture
def linked(client, db_session, thursday) -> Iterator[Linked]:
    """담당 중이고 데이터 공유에 동의한 (트레이너, 회원) 한 쌍."""
    member_id, member_headers = _new_member(client, db_session)
    trainer_id, trainer_headers = _new_trainer(db_session)
    _link(db_session, trainer_id, member_id)
    try:
        yield Linked(trainer_id, member_id, trainer_headers, member_headers)
    finally:
        _cleanup(db_session, [trainer_id, member_id])


def _add_diet(
    db_session, member_id: str, day: str, *, calories: int, sodium: int = 0
) -> None:
    db_session.add(
        DietEntry(
            id=f"diet-p2910-{uuid4().hex[:10]}",
            user_id=member_id,
            date=day,
            meal_type="lunch",
            time_label="12:00",
            total_calories=calories,
            sodium_mg=sodium,
            sugar_g=5,
            carbs_g=40,
            protein_g=20,
            fat_g=10,
        )
    )
    db_session.commit()


def _add_exercise(client, headers, day: str, *, minutes: int = 30) -> None:
    r = post_exercise(
        client,
        json={
            "type": "cardio",
            "name": "걷기",
            "minutes": minutes,
            "calories": 0,
            "date": day,
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text


def _get(client, path: str, headers, **params) -> dict:
    r = client.get(path, params=params or None, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _set_goals(db_session, member_id: str, **values) -> None:
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    for key, value in values.items():
        setattr(profile, key, value)
    db_session.commit()


# ---------------------------------------------------------------------------
# 회원 경로와 같은 본문
# ---------------------------------------------------------------------------


def test_diet_days_matches_member_response(client, db_session, linked):
    """같은 구간이면 날짜별 합계가 회원 앱이 받는 본문과 한 글자도 다르지 않다."""
    _add_diet(db_session, linked.member_id, "2026-09-02", calories=640, sodium=900)
    _add_diet(db_session, linked.member_id, "2026-09-02", calories=310, sodium=400)
    _add_diet(db_session, linked.member_id, "2026-09-16", calories=520)

    params = {"from": "2026-09-01", "to": TODAY}
    member = _get(client, "/v1/diet/days", linked.member_headers, **params)
    trainer = _get(
        client, linked.trainer_path("/diet/days"), linked.trainer_headers, **params
    )

    assert trainer == member
    assert trainer["from_date"] == "2026-09-01"
    assert trainer["to_date"] == TODAY
    # 기록이 없는 날도 0 으로 채워 온다 — i 번째 칸이 i 번째 날이다.
    assert len(trainer["days"]) == 17
    by_day = {d["date"]: d for d in trainer["days"]}
    assert by_day["2026-09-01"]["total_calories"] == 0
    assert by_day["2026-09-02"]["total_calories"] == 950
    assert by_day["2026-09-02"]["total_sodium_mg"] == 1300
    assert by_day["2026-09-16"]["total_calories"] == 520


def test_diet_days_without_from_starts_at_first_record(client, db_session, linked):
    """`from` 을 생략하면 두 경로 모두 회원의 첫 기록일부터다."""
    _add_diet(db_session, linked.member_id, "2026-08-20", calories=500)
    _add_diet(db_session, linked.member_id, "2026-09-10", calories=700)

    member = _get(client, "/v1/diet/days", linked.member_headers)
    trainer = _get(client, linked.trainer_path("/diet/days"), linked.trainer_headers)

    assert trainer == member
    assert trainer["from_date"] == "2026-08-20"
    assert trainer["to_date"] == TODAY


def test_diet_days_future_end_is_pulled_to_today(client, db_session, linked):
    """`to` 가 오늘보다 뒤여도 트레이너 쪽 구간은 회원 쪽처럼 오늘에서 끝난다."""
    _add_diet(db_session, linked.member_id, "2026-09-15", calories=480)

    params = {"from": THIS_MONDAY, "to": "2026-09-30"}
    member = _get(client, "/v1/diet/days", linked.member_headers, **params)
    trainer = _get(
        client, linked.trainer_path("/diet/days"), linked.trainer_headers, **params
    )

    assert trainer == member
    assert trainer["to_date"] == TODAY


def test_exercise_weeks_matches_member_response(client, db_session, linked):
    """주 단위 집계(요일별 분·칼로리·유형별 분·연속일·목표)가 회원 앱과 같다."""
    _add_exercise(client, linked.member_headers, "2026-09-01", minutes=40)
    _add_exercise(client, linked.member_headers, "2026-09-15", minutes=25)
    _add_exercise(client, linked.member_headers, "2026-09-16", minutes=20)

    params = {"from": "2026-08-31", "to": TODAY}
    member = _get(client, "/v1/exercise/weeks", linked.member_headers, **params)
    trainer = _get(
        client, linked.trainer_path("/exercise/weeks"), linked.trainer_headers, **params
    )

    assert trainer == member
    assert trainer["from_week"] == "2026-08-31"
    assert trainer["to_week"] == THIS_MONDAY
    weeks = {w["week_start"]: w for w in trainer["weeks"]}
    assert set(weeks) == {"2026-08-31", "2026-09-07", THIS_MONDAY}
    assert weeks["2026-08-31"]["total_minutes"] == 40
    assert weeks["2026-09-07"]["total_minutes"] == 0
    assert weeks[THIS_MONDAY]["total_minutes"] == 45


def test_exercise_weeks_without_from_starts_at_first_record_week(
    client, db_session, linked
):
    """`from` 을 생략하면 두 경로 모두 첫 기록이 있는 주의 월요일부터다."""
    _add_exercise(client, linked.member_headers, "2026-09-03")  # 목요일

    member = _get(client, "/v1/exercise/weeks", linked.member_headers)
    trainer = _get(
        client, linked.trainer_path("/exercise/weeks"), linked.trainer_headers
    )

    assert trainer == member
    assert trainer["from_week"] == "2026-08-31"
    assert trainer["to_week"] == THIS_MONDAY


def test_exercise_weeks_goals_follow_member_profile(client, db_session, linked):
    """주간 목표선은 **트레이너가 아니라 그 회원의** 프로필에서 온다."""
    _add_exercise(client, linked.member_headers, "2026-09-15")
    params = {"from": THIS_MONDAY, "to": TODAY}

    _set_goals(
        db_session,
        linked.member_id,
        weekly_exercise_minutes_goal=210,
        weekly_burn_goal=1800,
    )
    member = _get(client, "/v1/exercise/weeks", linked.member_headers, **params)
    trainer = _get(
        client, linked.trainer_path("/exercise/weeks"), linked.trainer_headers, **params
    )
    assert trainer == member
    week = trainer["weeks"][-1]
    assert week["weekly_goal_minutes"] == 210
    assert week["weekly_goal_calories"] == 1800

    # 주간 소모 목표가 비면 하루 소모 목표 × 7 이다(#2726) — 트레이너 쪽도 같다.
    _set_goals(db_session, linked.member_id, weekly_burn_goal=None, daily_burn_kcal=300)
    member = _get(client, "/v1/exercise/weeks", linked.member_headers, **params)
    trainer = _get(
        client, linked.trainer_path("/exercise/weeks"), linked.trainer_headers, **params
    )
    assert trainer == member
    assert trainer["weeks"][-1]["weekly_goal_calories"] == 2100


def test_records_span_matches_member_response(client, db_session, linked):
    """식단·운동이 각자 제 첫 기록일을 가진다 — 회원 경로와 같다."""
    _add_diet(db_session, linked.member_id, "2026-08-25", calories=500)
    _add_diet(db_session, linked.member_id, "2026-09-05", calories=600)
    _add_exercise(client, linked.member_headers, "2026-09-08")

    member = _get(client, "/v1/me/records/span", linked.member_headers)
    trainer = _get(client, linked.trainer_path("/records/span"), linked.trainer_headers)

    assert trainer == member
    assert trainer == {
        "diet_first_date": "2026-08-25",
        "exercise_first_date": "2026-09-08",
    }


@pytest.mark.parametrize(
    "has_diet,has_exercise", [(False, False), (True, False), (False, True)]
)
def test_records_span_is_null_for_missing_side(
    client, db_session, linked, has_diet, has_exercise
):
    """기록이 없는 쪽은 null 이다 — 한쪽 기록이 다른 쪽 구간을 늘리지 않는다."""
    if has_diet:
        _add_diet(db_session, linked.member_id, "2026-09-11", calories=500)
    if has_exercise:
        _add_exercise(client, linked.member_headers, "2026-09-12")

    member = _get(client, "/v1/me/records/span", linked.member_headers)
    trainer = _get(client, linked.trainer_path("/records/span"), linked.trainer_headers)

    assert trainer == member
    assert trainer["diet_first_date"] == ("2026-09-11" if has_diet else None)
    assert trainer["exercise_first_date"] == ("2026-09-12" if has_exercise else None)


def test_empty_member_gets_today_only_diet_period(client, db_session, linked):
    """기록이 하루도 없으면 오늘 하루짜리 0 칸 — 회원 경로와 같다."""
    member = _get(client, "/v1/diet/days", linked.member_headers)
    trainer = _get(client, linked.trainer_path("/diet/days"), linked.trainer_headers)

    assert trainer == member
    assert trainer["from_date"] == TODAY
    assert trainer["to_date"] == TODAY
    assert [d["date"] for d in trainer["days"]] == [TODAY]
    assert trainer["days"][0]["total_calories"] == 0


# ---------------------------------------------------------------------------
# 트레이너 경로에만 있는 조건
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("suffix", ["/diet/days", "/exercise/weeks"])
@pytest.mark.parametrize("bad", ["2026-13-40", "not-a-date"])
def test_invalid_bounds_are_422(client, linked, suffix, bad):
    """`from`·`to` 가 날짜가 아니면 422 다 — 회원 경로와 같은 검증이다."""
    for key in ("from", "to"):
        r = client.get(
            linked.trainer_path(suffix),
            params={key: bad},
            headers=linked.trainer_headers,
        )
        assert r.status_code == 422, (key, r.text)


@pytest.mark.parametrize("suffix", ["/diet/days", "/exercise/weeks", "/records/span"])
def test_other_trainers_member_is_404(client, db_session, linked, suffix):
    """담당이 아닌 트레이너는 같은 404·같은 문구 — 기록이 있다는 사실도 새지 않는다."""
    _add_diet(db_session, linked.member_id, "2026-09-15", calories=500)
    stranger_id, stranger_headers = _new_trainer(db_session)
    try:
        r = client.get(linked.trainer_path(suffix), headers=stranger_headers)
        assert r.status_code == 404, r.text
        assert r.json()["detail"] == GUARD_DETAIL
    finally:
        _cleanup(db_session, [stranger_id])


@pytest.mark.parametrize("suffix", ["/diet/days", "/exercise/weeks", "/records/span"])
def test_member_token_cannot_read_trainer_path(client, linked, suffix):
    """회원 토큰으로는 트레이너 경로를 열 수 없다(자기 자신이라도)."""
    r = client.get(linked.trainer_path(suffix), headers=linked.member_headers)
    assert r.status_code == 403, r.text


def test_trainer_period_does_not_mix_other_members(client, db_session, linked):
    """같은 트레이너의 다른 회원 기록이 섞이지 않는다."""
    other_id, other_headers = _new_member(client, db_session)
    try:
        _link(db_session, linked.trainer_id, other_id)
        _add_diet(db_session, other_id, "2026-09-15", calories=999)
        _add_exercise(client, other_headers, "2026-09-15", minutes=90)
        _add_diet(db_session, linked.member_id, "2026-09-16", calories=410)

        diet = _get(
            client,
            linked.trainer_path("/diet/days"),
            linked.trainer_headers,
            **{"from": THIS_MONDAY, "to": TODAY},
        )
        by_day = {d["date"]: d["total_calories"] for d in diet["days"]}
        assert by_day == {
            "2026-09-14": 0,
            "2026-09-15": 0,
            "2026-09-16": 410,
            TODAY: 0,
        }

        weeks = _get(
            client,
            linked.trainer_path("/exercise/weeks"),
            linked.trainer_headers,
            **{"from": THIS_MONDAY, "to": TODAY},
        )
        assert weeks["weeks"][-1]["total_minutes"] == 0

        span = _get(client, linked.trainer_path("/records/span"), linked.trainer_headers)
        assert span == {"diet_first_date": "2026-09-16", "exercise_first_date": None}
    finally:
        _cleanup(db_session, [other_id])
