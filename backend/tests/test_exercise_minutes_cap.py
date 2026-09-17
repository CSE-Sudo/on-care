"""운동 한 건의 시간에 **상한**이 있는가. (#1903)

`ExerciseSessionCreate.minutes` 에만 상한이 없어, 같은 파일의 칼로리 미리보기·
배정 루틴 완료가 600분에서 막는 동안 저장만 아무 값이나 받았다. 앱은 입력을
600분에서 막으므로 정상 경로로는 나오지 않지만, API 를 직접 치면 하루 10만 분
짜리 기록이 그대로 들어갔다.

그 값은 저장으로 끝나지 않는다. 주간 합계·유형별 분해·소모 칼로리·목표 달성률이
모두 저장된 행에서 다시 계산되고, 근력이면 `sets_of()` 가 분에서 세트를 환산한다
— 한 행이 회원 앱의 그래프와 트레이너 앱의 고객 현황을 같이 무너뜨린다.

여기서 보는 것은 세 갈래다: 추가·수정·배정 루틴 완료. 셋 다 같은 상한을 쓰는지,
그리고 경계값(600)은 그대로 통과하는지까지 본다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

from app.schemas.exercise_api import MAX_EXERCISE_MINUTES

#: 상한을 넘는 값. 예전에는 이 값이 그대로 저장돼 주간 합계로 번졌다.
OVER_CAP = MAX_EXERCISE_MINUTES + 1


def _member_h(client) -> dict:
    """기록이 비어 있는 새 회원. 시드 회원은 기록이 섞여 있어 합계를 견주기 어렵다."""
    email = f"excap-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _session_body(minutes: int) -> dict:
    return {
        "type": "cardio",
        "name": "러닝머신",
        "minutes": minutes,
        "intensity": "moderate",
    }


def test_add_session_rejects_minutes_over_cap(client):
    """상한을 넘는 기록은 422 다 — 저장되지 않는다."""
    h = _member_h(client)

    res = client.post("/v1/exercise/sessions", json=_session_body(OVER_CAP), headers=h)

    assert res.status_code == 422, res.text


def test_add_session_accepts_minutes_at_cap(client):
    """경계값은 그대로 받는다 — 상한을 거는 것이지 좁히는 것이 아니다."""
    h = _member_h(client)

    res = client.post(
        "/v1/exercise/sessions",
        json=_session_body(MAX_EXERCISE_MINUTES),
        headers=h,
    )

    assert res.status_code == 201, res.text
    assert res.json()["minutes"] == MAX_EXERCISE_MINUTES


def test_rejected_minutes_never_reach_the_weekly_totals(client):
    """거절된 값이 집계로 번지지 않는다.

    이 시험의 요점은 422 자체가 아니라 **그 뒤**다. 주간 응답은 저장된 행에서
    다시 계산되므로, 한 번 들어간 값은 그 행을 지우기 전까지 모든 화면에서
    되살아난다.
    """
    h = _member_h(client)
    client.post("/v1/exercise/sessions", json=_session_body(OVER_CAP), headers=h)

    week = client.get("/v1/exercise/weeks/current", headers=h).json()

    assert week["total_minutes"] < OVER_CAP
    assert all(m < OVER_CAP for m in week["daily_minutes"])


def test_update_session_rejects_minutes_over_cap(client):
    """수정도 같은 스키마(`ExerciseSessionCreate`)를 쓴다 — 뒷문으로 들어오지 못한다."""
    h = _member_h(client)
    created = client.post(
        "/v1/exercise/sessions", json=_session_body(30), headers=h
    ).json()

    res = client.put(
        f"/v1/exercise/sessions/{created['id']}",
        json=_session_body(OVER_CAP),
        headers=h,
    )

    assert res.status_code == 422, res.text
    after = client.get("/v1/exercise/weeks/current", headers=h).json()
    assert after["total_minutes"] < OVER_CAP


@pytest.mark.parametrize(
    "field",
    ["minutes"],
)
def test_calorie_preview_and_session_share_one_cap(client, field):
    """미리보기와 저장이 같은 상한을 쓴다.

    곳마다 다르면 미리보기로 숫자를 받아 놓고 저장에서 422 로 떨어지는 값이
    생긴다 — 회원에게는 앱이 제 계산을 못 믿는 것으로 보인다.
    """
    h = _member_h(client)
    body = {
        "type": "cardio",
        "name": "러닝머신",
        field: MAX_EXERCISE_MINUTES,
        "intensity": "moderate",
    }

    preview = client.post("/v1/exercise/calories", json=body, headers=h)
    saved = client.post("/v1/exercise/sessions", json=body, headers=h)

    assert preview.status_code == 200, preview.text
    assert saved.status_code == 201, saved.text
