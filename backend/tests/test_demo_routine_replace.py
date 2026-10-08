"""데모 시드 개인운동도 새 개인운동을 보내면 교체된다 (#3309). DB 필요.

시드 개인운동(`seed-routine-…`)은 `delivery_kind` 칸이 생기기 전 모양이라 비어 있다.
교체(`_retire_personal_routines`)가 그 칸으로만 고르던 동안에는, 실서버 데모에서
트레이너가 새 개인운동을 보내면 회원 목록에 시드 것과 새 것이 **함께** 보였다.
"""
from __future__ import annotations

from sqlalchemy import select

from app.core import clock
from app.models.models import TrainerRoutine

MEMBER = "user-7d4e9a2c5f18"
_PROGRAM_URL = f"/v1/trainer/clients/{MEMBER}/program"
_NAME = "시드 교체 테스트 걷기"


def _h(client, email: str) -> dict:
    res = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    )
    assert res.status_code == 200, res.text
    return {"Authorization": f"Bearer {res.json()['access_token']}"}


def _seed_rows(db_session) -> list[TrainerRoutine]:
    return list(
        db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == MEMBER,
                TrainerRoutine.id.like("seed-routine-%"),
            )
        ).all()
    )


def test_sending_personal_routines_replaces_the_seeded_ones(client, db_session):
    seeded = _seed_rows(db_session)
    assert seeded, "김민수 시드 개인운동이 없습니다."
    saved_end = {row.id: row.ended_on for row in seeded}
    seeded_ids = set(saved_end)
    sent_ids: set[str] = set()
    try:
        trainer = _h(client, "trainer@oncare.com")
        res = client.post(
            _PROGRAM_URL,
            json={
                "name": _NAME,
                "sessions": [
                    {
                        "id": "s-walk",
                        "name": _NAME,
                        "exercises": [{"id": "e-walk", "name": _NAME, "duration": 20}],
                    }
                ],
                "delivery_kind": "routine_only",
                "active_days": 7,
                "client_request_id": "req-3309-replace-seed",
            },
            headers=trainer,
        )
        assert res.status_code == 201, res.text
        sent_ids = {row["id"] for row in res.json()}

        member = _h(client, "minsu@oncare.com")
        listed = client.get(
            "/v1/me/coach/routines",
            params={"date": clock.today().isoformat()},
            headers=member,
        )
        assert listed.status_code == 200, listed.text
        ids = {row["id"] for row in listed.json()}
        assert sent_ids <= ids
        assert not seeded_ids & ids, "시드 개인운동이 새 개인운동과 함께 남아 있습니다."

        # 지우지 않고 오늘부로 내린다 — 지난 날짜에는 그대로 보인다(#2161).
        db_session.expire_all()
        assert {r.ended_on for r in _seed_rows(db_session)} == {clock.today().isoformat()}
    finally:
        db_session.expire_all()
        for row in _seed_rows(db_session):
            row.ended_on = saved_end.get(row.id)
        for rid in sent_ids:
            row = db_session.get(TrainerRoutine, rid)
            if row is not None:
                db_session.delete(row)
        db_session.commit()
