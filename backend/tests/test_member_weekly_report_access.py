"""회원은 받았거나 산 주의 리포트만 연다. (#3366) DB 필요.

`GET /me/coach/weekly-report` 가 지키는 것:

- 트레이너가 보내지도, 포인트로 사지도 않은 주는 403 이다.
- 받은 주와 산 주는 열린다. 담당이 끊기거나 바뀐 뒤에도 이미 받은 주는 열린다.
- 결과지의 `4주 평균 대비` 가 읽는 직전 넉 주는 `compare_for` 로 비교에 쓰는
  수치만 받는다 — 한 주를 열 수 있다고 그 앞 주들이 통째로 열리지 않는다.

순수 로직(비교 주 판정·비교용 응답)은 DB 없이 돈다. 엔드포인트는 다른 테스트의
시드와 섞이지 않게 회원·트레이너를 새로 만들고, 끝나면 계정째 지운다.
"""
from __future__ import annotations

import json
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import date, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import text

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    ChatMessage,
    DietEntry,
    TrainerClient,
    User,
    WeeklyReportPurchase,
)
from app.schemas.trainer_api import WeeklyReportDayOut, WeeklyReportOut
from app.services import weekly_report_access
from app.services.trainer import member_mirror as trainer_member_mirror_service
from app.services.trainer.reports import week_start_of

PATH = "/v1/me/coach/weekly-report"


def _this_monday() -> date:
    return week_start_of(clock.today())


def _back(weeks: int) -> date:
    """이번 주 월요일에서 [weeks] 주 전 월요일."""
    return _this_monday() - timedelta(weeks=weeks)


# ───────────────────────── 순수 로직: 비교 주 판정 ─────────────────────────


@pytest.mark.parametrize("back", [1, 2, 3, 4])
def test_the_four_weeks_before_are_comparison_weeks(back):
    target = date(2026, 9, 14)
    assert weekly_report_access.is_comparison_week(
        target - timedelta(weeks=back), target
    )


@pytest.mark.parametrize("back", [0, 5, 8, -1])
def test_other_weeks_are_not_comparison_weeks(back):
    """그 주 자신·다섯 주 전·뒤의 주는 비교 칸이 읽지 않는다."""
    target = date(2026, 9, 14)
    assert not weekly_report_access.is_comparison_week(
        target - timedelta(weeks=back), target
    )


def test_comparison_weeks_match_the_sheet_history_length():
    """앱 결과지가 읽는 직전 주 수(`kReportSheetHistoryWeeks`)와 같다."""
    assert weekly_report_access.COMPARISON_WEEKS == 4


def _full_report() -> WeeklyReportOut:
    return WeeklyReportOut(
        member_id="m",
        member_name="회원",
        week_start="2026-09-07",
        week_end="2026-09-13",
        sessions_booked=3,
        sessions_done=2,
        completion_avg=71,
        sodium_over_days=2,
        sodium_avg=2100,
        week_completion=[100, 0, None, 50, 100, None, None],
        sodium_week=[2000, 2200, 0, 0, 0, 0, 0],
        calories_week=[1800, 1900, 0, 0, 0, 0, 0],
        sugar_week=[30.0, 20.0, 0, 0, 0, 0, 0],
        carbs_week=[200.0, 210.0, 0, 0, 0, 0, 0],
        protein_week=[80.0, 90.0, 0, 0, 0, 0, 0],
        fat_week=[50.0, 40.0, 0, 0, 0, 0, 0],
        meal_counts=[3, 2, 0, 0, 0, 0, 0],
        calorie_target=1900,
        sodium_target=2000,
        sugar_target=50.0,
        carbs_target=250.0,
        protein_target=90.0,
        effective_protein_target=90.0,
        fat_target=55.0,
        days=[WeeklyReportDayOut(completion=100, exercises=["스쿼트"])],
        calorie_baseline=1850.0,
        message="초안",
    )


def test_comparison_only_keeps_what_the_average_row_reads():
    full = _full_report()
    slim = weekly_report_access.comparison_only(full)

    assert slim.week_start == full.week_start
    assert slim.week_end == full.week_end
    assert slim.member_id == full.member_id
    assert slim.calories_week == full.calories_week
    assert slim.completion_avg == full.completion_avg
    assert slim.sodium_avg == full.sodium_avg
    assert slim.meal_counts == full.meal_counts


def test_comparison_only_drops_the_rest_of_the_week():
    slim = weekly_report_access.comparison_only(_full_report())

    assert slim.sessions_booked == 0
    assert slim.sessions_done == 0
    assert slim.sodium_over_days == 0
    assert slim.days == []
    assert slim.week_completion == []
    assert slim.sodium_week == []
    assert slim.sugar_week == []
    assert slim.carbs_week == []
    assert slim.protein_week == []
    assert slim.fat_week == []
    assert slim.calorie_target is None
    assert slim.sodium_target is None
    assert slim.effective_protein_target is None
    assert slim.calorie_baseline is None
    assert slim.message == ""


# ─────────────────────────────── 엔드포인트 ────────────────────────────────


@dataclass
class World:
    """회원 하나와 트레이너 둘 — `trainer_id` 가 지금 담당이다."""

    member_id: str
    trainer_id: str
    other_trainer_id: str
    other_member_id: str


def _h(user_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _user(user_id: str, role: str, name: str) -> User:
    return User(
        id=user_id,
        email=f"{user_id}@oncare.com",
        name=name,
        hashed_password="unused",
        role=role,
    )


def _link(db_session, trainer_id: str, member_id: str) -> None:
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
            data_consent_at=clock.now(),
        )
    )
    db_session.commit()


@pytest.fixture()
def world(db_session) -> Iterator[World]:
    suffix = uuid4().hex[:10]
    w = World(
        member_id=f"wa-member-{suffix}",
        trainer_id=f"wa-trainer-{suffix}",
        other_trainer_id=f"wa-other-{suffix}",
        other_member_id=f"wa-member2-{suffix}",
    )
    db_session.add_all(
        [
            _user(w.member_id, "member", "열람 확인 회원"),
            _user(w.other_member_id, "member", "다른 회원"),
            _user(w.trainer_id, "trainer", "담당 코치"),
            _user(w.other_trainer_id, "trainer", "다른 코치"),
        ]
    )
    db_session.flush()
    _link(db_session, w.trainer_id, w.member_id)
    _link(db_session, w.trainer_id, w.other_member_id)
    try:
        yield w
    finally:
        # 계정째 지운다 — 대화·구매·식단 행은 `users.id` CASCADE 로 함께 사라진다.
        db_session.rollback()
        db_session.execute(
            text("DELETE FROM users WHERE id = ANY(:ids)"),
            {
                "ids": [
                    w.member_id,
                    w.other_member_id,
                    w.trainer_id,
                    w.other_trainer_id,
                ]
            },
        )
        db_session.commit()


def _send(
    db_session,
    trainer_id: str,
    member_id: str,
    monday: date,
    *,
    sender: str = "trainer",
) -> None:
    """리포트 전송이 대화에 남기는 안내 한 건."""
    db_session.add(
        ChatMessage(
            id=f"msg-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            sender=sender,
            body="주간 리포트를 보냈어요.",
            report_week_start=monday.isoformat(),
        )
    )
    db_session.commit()


def _buy(db_session, member_id: str, monday: date) -> None:
    db_session.add(
        WeeklyReportPurchase(
            id=f"wrp-{uuid4().hex[:12]}",
            user_id=member_id,
            week_start=monday.isoformat(),
            cost=300,
        )
    )
    db_session.commit()


def _get(
    client,
    member_id: str,
    monday: date | None = None,
    compare_for: date | None = None,
):
    params: dict[str, str] = {}
    if monday is not None:
        params["week_start"] = monday.isoformat()
    if compare_for is not None:
        params["compare_for"] = compare_for.isoformat()
    return client.get(PATH, params=params, headers=_h(member_id))


# ---- 받지도 사지도 않은 주 ----


@pytest.mark.parametrize("back", [0, 1, 4, 12])
def test_week_neither_received_nor_bought_is_403(client, world, back):
    res = _get(client, world.member_id, _back(back))
    assert res.status_code == 403, res.text
    assert res.json()["detail"]


def test_default_week_is_403_when_this_week_was_not_received(client, world):
    """`week_start` 를 빼면 이번 주다 — 기본값이라고 열리지 않는다."""
    assert _get(client, world.member_id).status_code == 403


def test_receiving_one_week_does_not_open_another(client, db_session, world):
    _send(db_session, world.trainer_id, world.member_id, _back(1))

    assert _get(client, world.member_id, _back(1)).status_code == 200
    assert _get(client, world.member_id, _back(2)).status_code == 403
    assert _get(client, world.member_id, _back(0)).status_code == 403


def test_another_members_report_does_not_open_mine(client, db_session, world):
    """같은 트레이너가 다른 회원에게 보낸 리포트는 내 주를 열지 않는다."""
    _send(db_session, world.trainer_id, world.other_member_id, _back(1))
    _buy(db_session, world.other_member_id, _back(2))

    assert _get(client, world.member_id, _back(1)).status_code == 403
    assert _get(client, world.member_id, _back(2)).status_code == 403
    assert _get(client, world.other_member_id, _back(1)).status_code == 200


def test_members_own_message_does_not_count_as_a_report(client, db_session, world):
    """받은 근거는 **트레이너가 보낸** 안내뿐이다."""
    _send(db_session, world.trainer_id, world.member_id, _back(1), sender="member")

    assert _get(client, world.member_id, _back(1)).status_code == 403


def test_plain_chat_does_not_count_as_a_report(client, db_session, world):
    db_session.add(
        ChatMessage(
            id=f"msg-{uuid4().hex[:12]}",
            trainer_id=world.trainer_id,
            member_id=world.member_id,
            sender="trainer",
            body="이번 주도 화이팅이에요.",
        )
    )
    db_session.commit()

    assert _get(client, world.member_id, _back(0)).status_code == 403


def test_future_week_is_still_422_not_403(client, world):
    """아직 오지 않은 주는 열람 판정보다 먼저 거부한다."""
    res = _get(client, world.member_id, _this_monday() + timedelta(days=7))
    assert res.status_code == 422


def test_trainer_token_is_rejected_before_the_access_check(client, world):
    assert _get(client, world.trainer_id, _back(1)).status_code == 403


# ---- 받은 주·산 주 ----


def test_received_week_opens(client, db_session, world):
    _send(db_session, world.trainer_id, world.member_id, _back(1))

    res = _get(client, world.member_id, _back(1))
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["member_id"] == world.member_id
    assert body["week_start"] == _back(1).isoformat()
    assert len(body["days"]) == 7
    assert body["message"] == ""


def test_mid_week_date_opens_the_received_week(client, db_session, world):
    """주 중간 날짜로 물어도 그 주 월요일로 접어 판정한다."""
    _send(db_session, world.trainer_id, world.member_id, _back(1))

    res = _get(client, world.member_id, _back(1) + timedelta(days=4))
    assert res.status_code == 200, res.text
    assert res.json()["week_start"] == _back(1).isoformat()


def test_week_resent_twice_opens_once(client, db_session, world):
    """같은 주를 두 번 보내도(재전송) 그대로 열린다."""
    _send(db_session, world.trainer_id, world.member_id, _back(1))
    _send(db_session, world.trainer_id, world.member_id, _back(1))

    assert _get(client, world.member_id, _back(1)).status_code == 200


def test_bought_week_opens(client, db_session, world):
    _buy(db_session, world.member_id, _back(1))

    res = _get(client, world.member_id, _back(1))
    assert res.status_code == 200, res.text
    assert res.json()["week_start"] == _back(1).isoformat()
    assert _get(client, world.member_id, _back(2)).status_code == 403


def test_bought_week_opens_without_any_trainer(client, db_session, world):
    """포인트 리포트는 담당이 없는 회원이 산다(#2022)."""
    assert trainer_member_mirror_service.disconnect_member_coach(
        db_session, world.member_id
    )
    _buy(db_session, world.member_id, _back(1))

    res = _get(client, world.member_id, _back(1))
    assert res.status_code == 200, res.text
    assert res.json()["sessions_booked"] == 0


def test_service_tells_received_from_bought(db_session, world):
    _send(db_session, world.trainer_id, world.member_id, _back(1))
    _buy(db_session, world.member_id, _back(2))

    assert weekly_report_access.received(db_session, world.member_id, _back(1))
    assert not weekly_report_access.received(db_session, world.member_id, _back(2))
    assert weekly_report_access.can_open(db_session, world.member_id, _back(1))
    assert weekly_report_access.can_open(db_session, world.member_id, _back(2))
    assert not weekly_report_access.can_open(db_session, world.member_id, _back(3))


# ---- 담당이 끊기거나 바뀐 뒤 ----


def test_received_week_stays_open_after_detach(client, db_session, world):
    _send(db_session, world.trainer_id, world.member_id, _back(1))
    assert trainer_member_mirror_service.disconnect_member_coach(
        db_session, world.member_id
    )

    res = _get(client, world.member_id, _back(1))
    assert res.status_code == 200, res.text
    # 받지 않은 주는 담당이 없어도 여전히 닫혀 있다.
    assert _get(client, world.member_id, _back(2)).status_code == 403


def test_received_week_stays_open_after_changing_trainer(client, db_session, world):
    """이전 담당이 보낸 리포트는 새 담당과 이어진 뒤에도 열린다."""
    _send(db_session, world.trainer_id, world.member_id, _back(2))
    assert trainer_member_mirror_service.disconnect_member_coach(
        db_session, world.member_id
    )
    _link(db_session, world.other_trainer_id, world.member_id)
    _send(db_session, world.other_trainer_id, world.member_id, _back(1))

    assert _get(client, world.member_id, _back(2)).status_code == 200
    assert _get(client, world.member_id, _back(1)).status_code == 200
    assert _get(client, world.member_id, _back(3)).status_code == 403


# ---- 비교용 직전 주 ----


def _meal(db_session, member_id: str, day: date, kcal: int) -> None:
    db_session.add(
        DietEntry(
            id=f"wa-meal-{uuid4().hex[:8]}",
            user_id=member_id,
            date=day.isoformat(),
            meal_type="lunch",
            time_label="",
            foods_json=json.dumps([{"name": "테스트 끼니"}], ensure_ascii=False),
            total_calories=kcal,
            sodium_mg=900,
            engine="test",
        )
    )
    db_session.commit()


@pytest.mark.parametrize("back", [1, 2, 3, 4])
def test_weeks_before_an_open_week_are_readable_for_comparison(
    client, db_session, world, back
):
    target = _back(1)
    _send(db_session, world.trainer_id, world.member_id, target)
    week = target - timedelta(weeks=back)

    res = _get(client, world.member_id, week, compare_for=target)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["week_start"] == week.isoformat()
    assert body["week_end"] == (week + timedelta(days=6)).isoformat()
    assert len(body["calories_week"]) == 7
    assert len(body["meal_counts"]) == 7
    # 그 주를 여는 것은 여전히 막혀 있다.
    assert _get(client, world.member_id, week).status_code == 403


def test_comparison_weeks_work_for_a_bought_week(client, db_session, world):
    target = _back(1)
    _buy(db_session, world.member_id, target)

    res = _get(client, world.member_id, _back(3), compare_for=target)
    assert res.status_code == 200, res.text


def test_comparison_response_carries_numbers_but_not_the_week(
    client, db_session, world
):
    """비교 칸이 읽는 값은 실제 기록에서 오고, 그 밖의 칸은 비어 있다."""
    target = _back(1)
    week = _back(2)
    _send(db_session, world.trainer_id, world.member_id, target)
    _meal(db_session, world.member_id, week, 1800)
    _meal(db_session, world.member_id, week + timedelta(days=1), 2000)

    body = _get(client, world.member_id, week, compare_for=target).json()

    assert body["calories_week"][:2] == [1800, 2000]
    assert body["meal_counts"][:2] == [1, 1]
    assert body["sodium_avg"] is not None
    assert body["days"] == []
    assert body["sodium_week"] == []
    assert body["carbs_week"] == []
    assert body["week_completion"] == []
    assert body["calorie_target"] is None
    assert body["calorie_baseline"] is None
    assert body["sessions_booked"] == 0
    assert body["message"] == ""


def test_comparison_request_is_403_when_the_target_week_is_not_open(client, world):
    res = _get(client, world.member_id, _back(2), compare_for=_back(1))
    assert res.status_code == 403, res.text


def test_owning_the_comparison_week_does_not_open_the_target(
    client, db_session, world
):
    """판정은 `compare_for` 주에 건다 — 직전 주를 받았다고 여는 주가 열리지 않는다."""
    _send(db_session, world.trainer_id, world.member_id, _back(2))

    res = _get(client, world.member_id, _back(2), compare_for=_back(1))
    assert res.status_code == 403, res.text


@pytest.mark.parametrize("back", [0, 5, 9])
def test_comparison_reaches_only_four_weeks_back(client, db_session, world, back):
    """여는 주 자신·다섯 주 전부터는 비교 주가 아니다."""
    target = _back(1)
    _send(db_session, world.trainer_id, world.member_id, target)

    res = _get(
        client, world.member_id, target - timedelta(weeks=back), compare_for=target
    )
    assert res.status_code == 422, res.text


def test_week_after_the_target_is_not_a_comparison_week(client, db_session, world):
    _send(db_session, world.trainer_id, world.member_id, _back(2))

    res = _get(client, world.member_id, _back(1), compare_for=_back(2))
    assert res.status_code == 422, res.text


def test_open_week_asked_as_comparison_still_comes_back_slim(
    client, db_session, world
):
    """직전 주도 받은 주라면 따로 열 수 있지만, 비교로 물으면 비교용 수치만 온다."""
    _send(db_session, world.trainer_id, world.member_id, _back(1))
    _send(db_session, world.trainer_id, world.member_id, _back(2))

    slim = _get(client, world.member_id, _back(2), compare_for=_back(1)).json()
    full = _get(client, world.member_id, _back(2)).json()

    assert slim["days"] == []
    assert len(full["days"]) == 7
    assert slim["calories_week"] == full["calories_week"]
    assert slim["completion_avg"] == full["completion_avg"]
    assert slim["sodium_avg"] == full["sodium_avg"]
    assert slim["meal_counts"] == full["meal_counts"]


def test_mid_week_compare_for_lands_on_that_weeks_monday(client, db_session, world):
    target = _back(1)
    _send(db_session, world.trainer_id, world.member_id, target)

    res = client.get(
        PATH,
        params={
            "week_start": _back(2).isoformat(),
            "compare_for": (target + timedelta(days=5)).isoformat(),
        },
        headers=_h(world.member_id),
    )
    assert res.status_code == 200, res.text


@pytest.mark.parametrize("bad", ["2026/09/14", "오늘", "2026-13-01"])
def test_bad_compare_for_is_422(client, world, bad):
    res = client.get(
        PATH,
        params={"week_start": _back(2).isoformat(), "compare_for": bad},
        headers=_h(world.member_id),
    )
    assert res.status_code == 422, res.text


def test_future_compare_for_is_422(client, world):
    res = _get(
        client,
        world.member_id,
        _back(0),
        compare_for=_this_monday() + timedelta(days=7),
    )
    assert res.status_code == 422, res.text


def test_empty_compare_for_means_the_same_as_not_sending_one(
    client, db_session, world
):
    _send(db_session, world.trainer_id, world.member_id, _back(1))

    res = client.get(
        PATH,
        params={"week_start": _back(1).isoformat(), "compare_for": ""},
        headers=_h(world.member_id),
    )
    assert res.status_code == 200, res.text
    assert len(res.json()["days"]) == 7
