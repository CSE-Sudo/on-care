"""담당 해제 뒤 일정에 붙은 개인운동 조회·수정 (#3239). DB 필요.

해제하면 일정은 취소되지만 붙은 미전송 줄은 남는다. 옛 일정 id 로 그 줄을 읽거나
고치면 해제된 회원의 지금 목표로 계산한 효과 문구가 나갔다 — 처음 붙이는 길만
담당·동의를 보고 있었다.
"""
from __future__ import annotations

from tests.test_trainer_inactive_client_access import (  # noqa: F401 — 픽스처
    _assert_guard,
    _detach,
    _session_with_personal_routine,
    pair,
)


def test_attached_routines_are_hidden_after_detach(client, pair):  # noqa: F811
    session_id = _session_with_personal_routine(client, pair, time="07:10")
    listed = client.get(
        f"/v1/trainer/schedule/{session_id}/routines", headers=pair.headers
    )
    assert listed.status_code == 200, listed.text
    assert [r["name"] for r in listed.json()] == ["해제 확인 걷기"]

    _detach(client, pair)

    listed = client.get(
        f"/v1/trainer/schedule/{session_id}/routines", headers=pair.headers
    )
    assert listed.status_code == 200, listed.text
    # 남의 일정과 같은 답이다.
    assert listed.json() == []


def test_attached_routines_cannot_be_edited_after_detach(client, pair):  # noqa: F811
    session_id = _session_with_personal_routine(client, pair, time="07:30")
    _detach(client, pair)

    r = client.put(
        f"/v1/trainer/schedule/{session_id}/routines",
        json={
            "personal_routines": [
                {"name": "해제 뒤 고친 걷기", "minutes": 10, "type": "유산소"}
            ]
        },
        headers=pair.headers,
    )
    _assert_guard(r)
