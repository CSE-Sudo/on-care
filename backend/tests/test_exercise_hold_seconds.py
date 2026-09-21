"""버티는 운동의 초 — 한 세트를 **한 번만** 잰다. (#1969)

플랭크·행잉처럼 버티는 운동은 한 세트를 몇 회가 아니라 몇 초로 잰다. 초를 담을
칸이 없던 동안 홀드는 이름에 적히거나(`플랭크 3세트 · 60초`) 45초가 `reps: 3`
으로 적혔다 — 이름에 적힌 글자는 어떤 집계에도 잡히지 않고, `reps: 3` 은 45초를
"3회" 라고 말하는 값이다.

이 스위트가 지키는 것은 넷이다.

1. 회원이 적은 홀드 초가 기록에 **남는다.**
2. `reps` 와 한 자리를 나눠 쓴다 — 초가 오면 횟수가 비고, 회↔초를 되돌린
   수정도 옛 값을 남기지 않는다.
3. 홀드는 여전히 **세트로** 집계된다. 초는 새 집계 축을 만들지 않는다.
4. 종목표의 `isometric` 표시가 폼의 기본값으로 내려간다.
"""
from __future__ import annotations

from uuid import uuid4

from app.core import clock


def _today() -> str:
    return clock.today().isoformat()


def _login(client) -> dict:
    email = f"hold-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "pw!", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _plank(**overrides) -> dict:
    body = {
        "type": "strength",
        "name": "플랭크",
        "minutes": 6,
        "sets": 3,
        "hold_seconds": 45,
        "intensity": "moderate",
        "date": _today(),
    }
    body.update(overrides)
    return body


def test_a_hold_is_stored_in_seconds_and_clears_reps(client):
    """45초 홀드는 45초로 남는다 — `reps: 3` 으로 접히지 않는다."""
    headers = _login(client)
    created = client.post(
        "/v1/exercise/sessions", json=_plank(reps=3), headers=headers
    )
    assert created.status_code == 201, created.text
    row = created.json()
    assert row["hold_seconds"] == 45
    # 한 세트를 두 단위로 적지 않는다. 함께 보내도 초가 맞고 횟수는 비운다 —
    # 이 칸이 없던 시절 초를 억지로 담아 보내던 값이 `reps` 다.
    assert row["reps"] is None
    assert row["sets"] == 3


def test_reps_still_work_for_ordinary_strength(client):
    """회로 재는 근력은 그대로다 — 홀드 칸이 생겼다고 달라지지 않는다."""
    headers = _login(client)
    row = client.post(
        "/v1/exercise/sessions",
        json=_plank(name="스쿼트", reps=12, hold_seconds=None),
        headers=headers,
    ).json()
    assert row["reps"] == 12
    assert row["hold_seconds"] is None


def test_switching_back_to_reps_clears_the_hold(client):
    """회↔초를 되돌린 수정이 옛 초를 남기지 않는다.

    남으면 한 줄이 두 단위로 자기를 말한다 — 화면마다 다르게 읽히는 기록이
    되고, 그것이 이 칸을 만든 이유다.
    """
    headers = _login(client)
    created = client.post(
        "/v1/exercise/sessions", json=_plank(), headers=headers
    ).json()
    updated = client.put(
        f"/v1/exercise/sessions/{created['id']}",
        json=_plank(reps=12, hold_seconds=None),
        headers=headers,
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["hold_seconds"] is None
    assert updated.json()["reps"] == 12


def test_a_hold_is_not_kept_on_a_non_strength_record(client):
    """유산소가 홀드를 들고 있지 않는다 — 세트·횟수·중량과 같은 규칙이다."""
    headers = _login(client)
    row = client.post(
        "/v1/exercise/sessions",
        json=_plank(type="cardio", name="걷기", sets=None, minutes=30),
        headers=headers,
    ).json()
    assert row["hold_seconds"] is None


def test_a_hold_counts_as_sets_not_as_a_new_axis(client):
    """주간 집계는 초를 세지 않는다 — 홀드도 세트로 센다.

    초는 분으로도 세트로도 곧바로 환산되지 않는다. 새 축을 만드는 대신 지금
    축을 그대로 두기로 했으므로, `플랭크 3세트` 는 예전처럼 3세트다.
    """
    headers = _login(client)
    client.post("/v1/exercise/sessions", json=_plank(), headers=headers)
    week = client.get("/v1/exercise/weeks/current", headers=headers).json()
    assert week["strength_sets"][clock.today().weekday()] >= 3


def test_the_catalog_tells_the_form_which_exercises_are_holds(client):
    """`/exercise/calories` 가 `isometric` 을 함께 내려 준다. (#1969)

    폼이 `횟수` 칸을 `초` 칸으로 바꿔 보이는 **기본값**이다. 이름을 다 적은
    시점에 폼이 이미 이 요청을 보내므로, 같은 걸 묻는 요청을 하나 더 두지
    않는다.
    """
    headers = _login(client)
    hold = client.post(
        "/v1/exercise/calories",
        json={
            "type": "strength",
            "name": "플랭크",
            "minutes": 6,
            "intensity": "moderate",
        },
        headers=headers,
    )
    assert hold.status_code == 200, hold.text
    assert hold.json()["isometric"] is True

    reps = client.post(
        "/v1/exercise/calories",
        json={
            "type": "strength",
            "name": "스쿼트",
            "minutes": 15,
            "intensity": "moderate",
        },
        headers=headers,
    ).json()
    assert reps["isometric"] is False


def test_seconds_fill_in_the_minutes_a_record_is_aggregated_by(client):
    """초로 적은 기록도 분을 갖는다. (#1969, #2071)

    주간 집계·트레이너웹이 분을 읽으므로 분 칸은 늘 차 있어야 한다. 45초짜리
    운동이 반올림으로 0분이 되어 거절되지도 않는다.
    """
    headers = _login(client)
    row = client.post(
        "/v1/exercise/sessions",
        json={
            "type": "cardio",
            "name": "걷기",
            "duration_seconds": 45,
            "intensity": "moderate",
            "date": _today(),
        },
        headers=headers,
    )
    assert row.status_code == 201, row.text
    assert row.json()["duration_seconds"] == 45
    assert row.json()["minutes"] == 1


def test_minutes_or_seconds_but_not_neither(client):
    """둘 다 없으면 422 다 — 길이를 모르는 기록은 집계할 수 없다."""
    headers = _login(client)
    rejected = client.post(
        "/v1/exercise/sessions",
        json={
            "type": "cardio",
            "name": "걷기",
            "intensity": "moderate",
            "date": _today(),
        },
        headers=headers,
    )
    assert rejected.status_code == 422


def test_seconds_win_over_minutes_when_both_are_sent(client):
    """두 값이 어긋나면 초가 맞다 — 분은 서버가 다시 계산한다."""
    headers = _login(client)
    row = client.post(
        "/v1/exercise/sessions",
        json={
            "type": "cardio",
            "name": "걷기",
            "minutes": 30,
            "duration_seconds": 600,
            "intensity": "moderate",
            "date": _today(),
        },
        headers=headers,
    ).json()
    assert row["duration_seconds"] == 600
    assert row["minutes"] == 10
