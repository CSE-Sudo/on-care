"""날짜·시각은 계약 표기 하나만 받는다. (#3243)

`date.fromisoformat`(3.11+)은 `20261005`·`2026-W40-1` 도, `strptime("%H:%M")` 은 `9:5`
도 받는다. 트레이너 일정은 받은 원문을 그대로 저장해 문자열로 범위 조회·정렬·
`until < date` 비교를 하므로, 다른 표기가 섞이면 그 비교가 어긋난다.
"""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.schemas.record_dates import is_hhmm, parse_ymd
from app.schemas.trainer_api import ScheduleCreateRequest, ScheduleRecurringRequest


@pytest.mark.parametrize("bad", [
    "20261005", "2026-W40-1", "2026-10-5", "2026-02-30", "２０２６-10-05", "", " 2026-10-05",
])
def test_parse_ymd_rejects_other_shapes(bad):
    with pytest.raises(ValueError):
        parse_ymd(bad)


def test_parse_ymd_reads_the_contract_shape():
    assert parse_ymd("2026-10-05").isoformat() == "2026-10-05"


@pytest.mark.parametrize("value, ok", [
    ("09:05", True), ("23:59", True), ("00:00", True),
    ("9:05", False), ("9:5", False), ("24:00", False), ("12:60", False), ("", False),
])
def test_is_hhmm(value, ok):
    assert is_hhmm(value) is ok


def _schedule(**over):
    body = {"date": "2026-10-05", "time": "09:00"}
    body.update(over)
    return ScheduleCreateRequest(**body)


@pytest.mark.parametrize("bad", ["20261005", "2026-W40-1"])
def test_schedule_rejects_compact_dates(bad):
    with pytest.raises(ValidationError):
        _schedule(date=bad)


@pytest.mark.parametrize("bad", ["9:5", "9:05"])
def test_schedule_rejects_unpadded_times(bad):
    with pytest.raises(ValidationError):
        _schedule(time=bad)


def test_schedule_keeps_the_contract_values():
    s = _schedule()
    assert (s.date, s.time) == ("2026-10-05", "09:00")


def test_recurring_until_rejects_compact_dates():
    """`until` 이 `20261231` 이면 문자열 비교 `until < date` 가 거꾸로 나온다."""
    with pytest.raises(ValidationError):
        ScheduleRecurringRequest(
            date="2026-10-05", time="09:00", weekdays=[1], until="20261231"
        )


@pytest.mark.parametrize("bad", ["2026-1-5", "20260105"])
def test_exercise_week_rejects_other_shapes_instead_of_this_week(client, bad):
    """`2026-1-5` 가 조용히 이번 주로 바뀌지 않고 422 다."""
    r = client.get("/v1/exercise/weeks/current", params={"week_start": bad})
    assert r.status_code == 422, r.text
