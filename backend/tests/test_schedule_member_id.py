"""스케줄 일정의 회원 id — 응답에 싣고, 옛 행은 이름으로 잇는다. (#2586)"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from sqlalchemy import text

from app.models.models import TrainerClient, TrainerSchedule, User

_MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0104_backfill_schedule_member_id.py"
)


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _trainer_tok(client) -> str:
    return client.post(
        "/v1/auth/login", data={"username": "trainer@oncare.com", "password": "oncare123"}
    ).json()["access_token"]


def _load_migration():
    spec = importlib.util.spec_from_file_location("m0103", _MIGRATION)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_schedule_response_carries_member_id(client, db_session):
    """새 일정에 보낸 회원 id 가 생성·조회 응답에 그대로 실린다."""
    tok = _trainer_tok(client)
    day = "2031-05-14"
    created = client.post(
        "/v1/trainer/schedule",
        json={
            "date": day, "time": "06:00", "client_name": "이지수",
            "member_id": "user-jisu", "type": "1:1 PT", "duration_minutes": 50,
        },
        headers=_h(tok),
    )
    try:
        assert created.status_code == 201, created.text
        body = created.json()
        assert body["member_id"] == "user-jisu"

        rows = client.get(
            "/v1/trainer/schedule", params={"date": day}, headers=_h(tok)
        ).json()
        mine = next(r for r in rows if r["id"] == body["id"])
        assert mine["member_id"] == "user-jisu"

        # 이름만 있는 가망 고객 일정은 null 이다.
        prospect = client.post(
            "/v1/trainer/schedule",
            json={
                "date": day, "time": "08:00", "client_name": "가망고객",
                "type": "상담", "duration_minutes": 30,
            },
            headers=_h(tok),
        )
        assert prospect.status_code == 201, prospect.text
        assert prospect.json()["member_id"] is None
    finally:
        db_session.rollback()
        db_session.query(TrainerSchedule).filter(
            TrainerSchedule.trainer_id == "trainer-demo",
            TrainerSchedule.date == day,
        ).delete(synchronize_session=False)
        db_session.commit()


def test_backfill_links_only_unique_names(client, db_session):
    """같은 트레이너의 담당 회원 중 이름이 한 명과만 맞는 행만 잇는다.

    마이그레이션은 표 전체를 고치므로 커밋하지 않고 같은 트랜잭션에서 확인한 뒤
    되돌린다 — 시드·다른 테스트의 행을 남기지 않는다.
    """
    tag = uuid4().hex[:8]
    trainer = f"trainer-m0103-{tag}"
    other_trainer = f"trainer-m0103-o-{tag}"
    unique_member = f"member-m0103-u-{tag}"
    twin_a = f"member-m0103-a-{tag}"
    twin_b = f"member-m0103-b-{tag}"
    unique_name = f"유일-{tag}"
    twin_name = f"동명-{tag}"
    db_session.add_all([
        User(id=trainer, email=f"{trainer}@t.com", name="T", role="trainer"),
        User(id=other_trainer, email=f"{other_trainer}@t.com", name="T2", role="trainer"),
        User(id=unique_member, email=f"{unique_member}@t.com", name=unique_name),
        User(id=twin_a, email=f"{twin_a}@t.com", name=twin_name),
        User(id=twin_b, email=f"{twin_b}@t.com", name=twin_name),
    ])
    db_session.flush()
    db_session.add_all([
        # 해제된 담당도 지난 일정의 주인이다.
        TrainerClient(id=f"tc-u-{tag}", trainer_id=trainer, member_id=unique_member, active=False),
        TrainerClient(id=f"tc-a-{tag}", trainer_id=trainer, member_id=twin_a, active=True),
        TrainerClient(id=f"tc-b-{tag}", trainer_id=trainer, member_id=twin_b, active=False),
    ])

    def row(key: str, trainer_id: str, name: str, member_id: str | None = None):
        return TrainerSchedule(
            id=f"sched-m0103-{key}-{tag}", trainer_id=trainer_id, member_id=member_id,
            date="2031-05-15", time="10:00", client_name=name, type="1:1 PT",
            duration_minutes=50, status="완료", note="", program_json="[]", sort_order=0,
        )

    rows = {
        "unique": row("unique", trainer, unique_name),
        "twin": row("twin", trainer, twin_name),
        "prospect": row("prospect", trainer, f"가망-{tag}"),
        # 다른 트레이너의 같은 이름 — 그 트레이너의 담당이 아니니 잇지 않는다.
        "other": row("other", other_trainer, unique_name),
        # 이미 id 가 있는 행은 그대로 둔다.
        "kept": row("kept", trainer, unique_name, member_id=twin_a),
    }
    db_session.add_all(rows.values())
    db_session.flush()

    migration = _load_migration()
    try:
        with patch.object(
            migration.op,
            "execute",
            side_effect=lambda sql: db_session.execute(text(sql)),
        ):
            migration.upgrade()
        db_session.expire_all()

        def member_of(key: str) -> str | None:
            return db_session.get(TrainerSchedule, rows[key].id).member_id

        assert member_of("unique") == unique_member
        assert member_of("twin") is None
        assert member_of("prospect") is None
        assert member_of("other") is None
        assert member_of("kept") == twin_a
    finally:
        db_session.rollback()
