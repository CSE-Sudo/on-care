"""회원마다 다른 수의 개인운동 기간(운동 탭 `전체` 링) 시드. (#2508)

예전 시드는 확장 회원 모두에게 지난 18주 내내 매주 한 벌을 걸어 링 수가 똑같았다.
`seed_roster._RING_PLAN` 이 회원마다 다르게 정하고, 데모(`seed_rings.dart`)도 같은
표를 쓴다. 데모 쪽 테스트(`test/core/storage/seed_rings_test.dart`)와 같은 날짜·같은
기대값이다 — 한쪽만 고치면 둘 중 하나가 깨진다.
"""
from __future__ import annotations

from datetime import date, timedelta

from app.core import clock
from app.db.seed_roster import _METRICS, _RING_PLAN, ring_windows

#: 데모 테스트의 `kMidWeekKst` 와 같은 날 — 2026-08-20(목).
MID_WEEK = date(2026, 8, 20)

#: 그날 회원마다 그려지는 링 수. 데모 테스트와 같은 표다.
EXPECTED_RINGS = {
    "user-hayun": 15,
    "user-woojin": 7,
    "user-kangseoyeon": 4,
    "user-dohyun": 0,  # 지난 기록 없음 — 오늘 보낸 한 벌은 따로 건다(#3003)
    "user-sera": 7,
    "user-junhyuk": 3,
    "user-yuna": 1,
    "user-jiho": 15,
    "user-gayoung": 2,
    "user-taekyung": 4,
    "user-seojin": 15,
    "user-eunchae": 1,
}


def _rings(member_id: str, today: date) -> list[tuple[date, date, int, bool]]:
    return [
        w for w in ring_windows(
            _METRICS[member_id]["completion"], _RING_PLAN.get(member_id, {}), today
        )
        if w[3] and w[0] <= today
    ]


def test_ring_counts_differ_by_member():
    counts = {m: len(_rings(m, MID_WEEK)) for m in _METRICS}
    assert counts == EXPECTED_RINGS
    assert len(set(counts.values())) >= 6, "링 수가 회원마다 달라야 한다"


def test_split_week_ends_early_and_the_next_one_starts_that_day():
    """배준혁은 지난주 것을 목요일에 바꿨다 — 7일을 못 채운 묶음 하나가 더 있다."""
    rings = _rings("user-junhyuk", MID_WEEK)
    assert [(str(a), str(b)) for a, b, _, _ in rings] == [
        ("2026-08-10", "2026-08-13"),
        ("2026-08-13", "2026-08-15"),
        ("2026-08-17", "2026-08-22"),
    ]


def test_next_week_set_was_sent_yesterday_and_starts_next_monday():
    """최우진은 다음 주 것을 어제 미리 보냈다(#2656) — 이번 주 것은 그 전날까지."""
    windows = ring_windows(
        _METRICS["user-woojin"]["completion"], _RING_PLAN["user-woojin"], MID_WEEK
    )
    current, upcoming = windows[-2], windows[-1]
    assert upcoming[:2] == (date(2026, 8, 24), date(2026, 8, 31))
    assert current[1] == upcoming[0]


def test_first_time_this_week_member_has_no_ring_before_the_first_day():
    """신유나는 이번 주 수요일에 처음 받았다 — 월·화에는 아직 링이 없다."""
    monday = MID_WEEK - timedelta(days=MID_WEEK.weekday())
    assert _rings("user-yuna", monday) == []
    assert len(_rings("user-yuna", monday + timedelta(days=2))) == 1


def test_seeded_routine_days_draw_the_planned_rings(client):
    """실 API 의 날짜별 이행에서 묶은 링 수가 표와 같다."""
    r = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    headers = {"Authorization": f"Bearer {r.json()['access_token']}"}
    today = clock.today()
    for member_id in _METRICS:
        res = client.get(
            f"/v1/trainer/clients/{member_id}/routine-days", headers=headers
        )
        assert res.status_code == 200, res.text
        groups = {
            (row["sent_on"], row["active_from"], row["ended_on"])
            for row in res.json()["routines"]
            if row["personal"] and date.fromisoformat(row["active_from"]) <= today
        }
        # 임도현은 오늘 처음 보낸 한 벌이 링 하나다(`_seed_new_member_routines`).
        sent_today = 1 if not any(_METRICS[member_id]["completion"]) else 0
        assert len(groups) == len(_rings(member_id, today)) + sent_today, member_id
