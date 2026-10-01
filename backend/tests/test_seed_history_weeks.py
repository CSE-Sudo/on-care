"""데모 시드의 과거 기록이 지난 리포트의 칼로리 기준까지 덮는지 (#2453).

지난 리포트의 ① 섭취 칼로리 줄은 그 주 앞 4주의 하루 평균을 `지난 4주 평균` 으로
견준다. 데모 리포트 이력의 가장 오래된 주도 그 4주가 있어야 비교와 증감이 서는데,
시드가 12주에 멈춰 있어 오래된 지난 리포트는 `이번 주 평균` 만 보여 줬다.

앞의 셋은 DB 없이 상수만 본다. 뒤의 둘은 기동 시드가 돈 DB 를 읽는다(로컬 skip,
CI 의 Postgres 서비스에서 실행).
"""
from __future__ import annotations

import re
from datetime import date, timedelta
from pathlib import Path

from sqlalchemy import select

from app.core import clock

_ROOT = Path(__file__).resolve().parents[2]
_TRAINER_LIB = _ROOT / "frontend" / "flutter_trainer" / "lib" / "features" / "reports" / "data"


def _dart_int(path: Path, name: str) -> int:
    match = re.search(rf"const int {name} = (\d+);", path.read_text(encoding="utf-8"))
    assert match, f"{path.name} 에서 {name} 을 찾지 못했다"
    return int(match.group(1))


def _monday(day: date) -> date:
    return day - timedelta(days=day.weekday())


def test_history_weeks_cover_report_history_plus_baseline():
    from app.db.seed_roster import (
        CALORIE_BASELINE_WEEKS,
        DEMO_REPORT_HISTORY_WEEKS,
        HISTORY_WEEKS,
    )

    assert HISTORY_WEEKS == DEMO_REPORT_HISTORY_WEEKS + CALORIE_BASELINE_WEEKS
    assert HISTORY_WEEKS >= 18


def test_member_seed_and_fixture_share_the_same_window():
    """두 시드가 따로 적으면 한쪽만 늘어 회원마다 기준이 서거나 빈다."""
    from app.db.demo_fixture import load_fixture
    from app.db.seed_member_data import _HISTORY_WEEKS
    from app.db.seed_roster import HISTORY_WEEKS

    assert _HISTORY_WEEKS == HISTORY_WEEKS
    # 김민수는 공유 픽스처에서 온다 — 그 기간도 이력 창보다 짧으면 안 된다.
    assert load_fixture().history_weeks >= HISTORY_WEEKS


def test_trainer_web_uses_the_same_numbers():
    """트레이너 웹 로컬 데모와 실서버 데모가 같은 창을 쓴다."""
    from app.db.seed_roster import CALORIE_BASELINE_WEEKS, DEMO_REPORT_HISTORY_WEEKS

    assert _dart_int(
        _TRAINER_LIB / "demo_report_history.dart", "demoReportHistoryWeeks"
    ) == DEMO_REPORT_HISTORY_WEEKS
    assert _dart_int(
        _TRAINER_LIB / "repositories" / "calorie_baseline.dart", "kCalorieBaselineWeeks"
    ) == CALORIE_BASELINE_WEEKS


def test_roster_calories_reach_back_through_the_whole_window(client, db_session):
    """칼로리를 적어 온 확장 회원은 이력 창의 모든 주에 기록이 있다."""
    from app.db.seed_member_logs import MEAL_ID_PREFIX
    from app.db.seed_roster import _METRICS, HISTORY_WEEKS
    from app.models.models import DietEntry

    this_monday = _monday(clock.today())
    # 최근 4주의 하루 한 줄은 같은 합계의 끼니로 나뉜다(#2729) — 그 끼니도 센다.
    rows = db_session.execute(
        select(DietEntry.user_id, DietEntry.date).where(
            DietEntry.id.like("seed-roster-diet-%")
            | (
                DietEntry.id.like(f"{MEAL_ID_PREFIX}%")
                & DietEntry.user_id.in_(list(_METRICS))
            ),
            DietEntry.total_calories > 0,
        )
    ).all()
    weeks: dict[str, set[int]] = {}
    for user_id, day in rows:
        back = (this_monday - _monday(date.fromisoformat(day))).days // 7
        weeks.setdefault(user_id, set()).add(back)

    assert weeks, "확장 로스터의 식단 시드가 없다"
    for user_id, seen in weeks.items():
        # 이번 주는 요일에 따라 아직 비어 있을 수 있어 지난 주부터 센다.
        missing = set(range(1, HISTORY_WEEKS)) - seen
        assert not missing, f"{user_id}: {sorted(missing)} 주 전 칼로리 기록이 없다"
        # 이번 주 안의 요일 오프셋만큼 한 주 더 넘어갈 수는 있어도, 그보다 앞은 없다.
        assert max(seen) <= HISTORY_WEEKS


def test_oldest_history_report_has_a_calorie_baseline(client, db_session):
    """가장 오래된 지난 리포트의 앞 4주에 칼로리가 있다 — 실 API 가 그대로 준다."""
    from app.db.seed_roster import (
        CALORIE_BASELINE_WEEKS,
        DEMO_REPORT_HISTORY_WEEKS,
    )

    r = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    headers = {"Authorization": f"Bearer {r.json()['access_token']}"}

    this_monday = _monday(clock.today())
    oldest = this_monday - timedelta(weeks=DEMO_REPORT_HISTORY_WEEKS - 1)
    member = "user-woojin"  # 최우진 — 매일 적는 대조군
    recorded: list[int] = []
    for back in range(1, CALORIE_BASELINE_WEEKS + 1):
        week = oldest - timedelta(weeks=back)
        res = client.get(
            f"/v1/trainer/clients/{member}/report",
            params={"week_start": week.isoformat()},
            headers=headers,
        )
        assert res.status_code == 200, res.text
        recorded += [v for v in res.json()["calories_week"] if v > 0]

    assert recorded, "가장 오래된 지난 리포트의 앞 4주가 비어 기준이 서지 않는다"
