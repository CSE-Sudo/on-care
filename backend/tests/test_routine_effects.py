"""추천 개인운동의 효과 한 줄 (#2570).

회원 카드에서 운동 이름 아래 서는 줄이다. 트레이너가 적은 것만 저장하고, 비어
있으면 응답 때 운동 유형 × 회원 첫 건강 목표 문구표로 채운다. 앞의 두 테스트는
DB 없이, 나머지는 DB 가 있어야 돈다.
"""
from __future__ import annotations

import json
from datetime import timedelta
from pathlib import Path

import pytest
from sqlalchemy import or_, select

from app.core import clock
from app.data import routine_effects
from app.data.routine_effects import auto_routine_effect
from app.models.models import HealthProfile, TrainerRoutine, TrainerSchedule
from app.services import trainer_service

#: 문구표 원본. 트레이너 웹도 같은 파일과 비교한다.
SHARED_PATH = (
    Path(__file__).resolve().parents[2]
    / "shared/routine_effects/routine_effects.json"
)

MEMBER = "user-jisu"
TRAINER = "trainer-demo"
_PREFIX = "효과 한 줄 테스트"


def test_backend_table_matches_the_shared_original():
    """서버 사본이 원본과 같다 — 트레이너 웹 placeholder 와 회원 문구가 갈리지 않게."""
    shared = json.loads(SHARED_PATH.read_text(encoding="utf-8"))
    assert routine_effects.ROUTINE_EFFECT_DEFAULTS == shared["default"]
    assert routine_effects.ROUTINE_EFFECTS_BY_GOAL == shared["by_goal"]


@pytest.mark.parametrize(
    ("routine_type", "goals", "expected"),
    [
        # 첫 목표만 본다 — 저장값(쉼표)도, 트레이너 웹 표시값(가운뎃점)도.
        ("유산소", "혈압 관리, 체중 감량", "혈압 관리에 도움"),
        ("유산소", "체중 감량 · 혈압 관리", "체지방 감량에 도움"),
        ("근력", "자세 교정", "자세 지지 근육 강화"),
        ("스트레칭", "재활", "관절 가동 범위 회복"),
        # 표에 없는 목표·목표 없음은 유형 기본값이다.
        ("근력", "혈압 관리", "근력·근지구력 향상"),
        ("스트레칭", "", "유연성·부상 예방"),
        ("유산소", None, "체력 향상·만성질환 예방"),
        # 기타는 무엇인지 알 수 없어 비운다.
        ("기타", "체중 감량", ""),
    ],
)
def test_auto_effect_follows_type_and_first_goal(routine_type, goals, expected):
    assert auto_routine_effect(routine_type, goals) == expected


@pytest.fixture
def member_goals(db_session):
    """이 파일 동안 회원 목표를 `혈압 관리, 체중 감량` 으로 둔다."""
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == MEMBER)
    )
    created = profile is None
    if created:
        profile = HealthProfile(user_id=MEMBER)
        db_session.add(profile)
    before = profile.conditions
    profile.conditions = "혈압 관리, 체중 감량"
    db_session.commit()
    yield
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == MEMBER)
    )
    if created:
        db_session.delete(profile)
    else:
        profile.conditions = before
    db_session.commit()


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _cleanup(db_session, day: str | None = None) -> None:
    if day is not None:
        for row in db_session.scalars(
            select(TrainerSchedule).where(
                TrainerSchedule.trainer_id == TRAINER,
                TrainerSchedule.member_id == MEMBER,
                TrainerSchedule.date == day,
            )
        ).all():
            db_session.delete(row)
    for routine in db_session.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id == MEMBER,
            or_(
                TrainerRoutine.name.like(f"{_PREFIX}%"),
                TrainerRoutine.program_name.like(f"{_PREFIX}%"),
            ),
        )
    ).all():
        db_session.delete(routine)
    db_session.commit()


def _schedule_body(day: str) -> dict:
    return {
        "name": f"{_PREFIX} PT",
        "sessions": [
            {
                "id": "session-1",
                "name": "세션 A",
                "exercises": [{"id": "ex-1", "name": "스쿼트", "sets": 3}],
            }
        ],
        "date": day,
        "time": "16:00",
        "duration_minutes": 60,
        "client_name": "이지수",
        "client_request_id": f"req-2570-{day}",
        "personal_routines": [
            # 트레이너가 비워 둔 줄 — 문구표가 채운다.
            {
                "name": f"{_PREFIX} 걷기",
                "minutes": 30,
                "type": "유산소",
                "reason": "PT 사이 유산소",
                "source": "ai",
            },
            # 트레이너가 고친 줄 — 적은 그대로 간다.
            {
                "name": f"{_PREFIX} 어깨 스트레칭",
                "minutes": 8,
                "type": "스트레칭",
                "effect": " 오른쪽 어깨 보호 ",
                "source": "trainer",
            },
        ],
    }


def test_scheduled_personal_routines_keep_written_effect_and_fill_the_rest(
    client, db_session, member_goals
):
    """적은 효과는 그대로, 빈 효과는 회원 첫 목표의 문구로 나간다. (#2570)"""
    token = _tok(client)
    day = (clock.today() + timedelta(days=80)).isoformat()
    _cleanup(db_session, day)
    try:
        r = client.post(
            f"/v1/trainer/clients/{MEMBER}/program-schedule",
            json=_schedule_body(day),
            headers=_h(token),
        )
        assert r.status_code == 201, r.text
        personal = r.json()["personal_routines"]
        assert [p["effect"] for p in personal] == [
            "혈압 관리에 도움",
            "오른쪽 어깨 보호",
        ]
        # AI 추천 사유는 효과와 섞이지 않고 제자리에 남는다.
        assert personal[0]["reason"] == "PT 사이 유산소"

        # 저장은 트레이너가 적은 것만 — 자동 문구는 목표가 바뀌면 따라가야 한다.
        db_session.expire_all()
        saved = {
            row.name: row.effect
            for row in db_session.scalars(
                select(TrainerRoutine).where(
                    TrainerRoutine.id.in_([p["id"] for p in personal])
                )
            )
        }
        assert saved == {
            f"{_PREFIX} 걷기": "",
            f"{_PREFIX} 어깨 스트레칭": "오른쪽 어깨 보호",
        }

        # 효과만 고친 수정은 운동을 바꾼 것이 아니라 AI 출처가 그대로다.
        session_id = r.json()["session"]["id"]
        items = [
            {
                "name": p["name"],
                "minutes": p["minutes"],
                "type": p["type"],
                "source": p["source"],
            }
            for p in personal
        ]
        items[0]["effect"] = "숨 고르기 연습"
        items[1]["effect"] = ""
        updated = client.put(
            f"/v1/trainer/schedule/{session_id}/routines",
            json={"personal_routines": items},
            headers=_h(token),
        )
        assert updated.status_code == 200, updated.text
        rows = updated.json()
        assert [p["effect"] for p in rows] == ["숨 고르기 연습", "혈압·심박 안정"]
        assert rows[0]["source"] == "ai"
    finally:
        _cleanup(db_session, day)


def test_routine_only_delivery_carries_each_exercise_effect(
    client, db_session, member_goals
):
    """`개인운동만` 은 운동 하나가 배정 한 건이라 그 운동의 효과가 배정의 효과다."""
    token = _tok(client)
    _cleanup(db_session)
    try:
        r = client.post(
            f"/v1/trainer/clients/{MEMBER}/program",
            json={
                "name": f"{_PREFIX} 이번 주 개인운동",
                "sessions": [
                    {
                        "id": "session-walk",
                        "name": "걷기",
                        "exercises": [
                            {"id": "ex-1", "name": "걷기", "duration": 30,
                             "type": "유산소"},
                        ],
                    },
                    {
                        "id": "session-bridge",
                        "name": "힙 브리지",
                        "exercises": [
                            {"id": "ex-2", "name": "힙 브리지", "type": "근력",
                             "sets": 3, "reps": 15, "effect": "허리 보호"},
                        ],
                    },
                ],
                "delivery_kind": "routine_only",
                "active_days": 7,
                "client_request_id": "req-2570-only",
            },
            headers=_h(token),
        )
        assert r.status_code == 201, r.text
        assert [row["effect"] for row in r.json()] == [
            "혈압 관리에 도움",
            "허리 보호",
        ]
    finally:
        _cleanup(db_session)


def test_multi_exercise_session_has_no_auto_effect(db_session, member_goals):
    """운동 여럿으로 짠 세션은 한 유형의 효과로 말할 수 없어 비운다."""
    exercises = [
        {"id": "a", "name": "스쿼트", "type": "근력", "sets": 3},
        {"id": "b", "name": "걷기", "type": "유산소", "duration": 10},
    ]
    row = TrainerRoutine(
        id="rt-2570-multi",
        trainer_id=TRAINER,
        member_id=MEMBER,
        name="세션 A",
        minutes=10,
        type="근력",
        reason="",
        source="trainer",
        exercises_json=json.dumps(exercises, ensure_ascii=False),
    )
    assert trainer_service._routine_effect(db_session, row) == ""
    # 트레이너가 적었다면 그것은 싣는다.
    row.effect = "하체 근력"
    assert trainer_service._routine_effect(db_session, row) == "하체 근력"
