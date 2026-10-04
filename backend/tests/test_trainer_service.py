"""트레이너 서비스 배치 쿼리 — 리뷰 반영(#250).

_latest_by_member 가 회원당 최신 1건만 DB 에서 반환하는지(반환 행 수가 메시지 수가
아니라 회원 수에 비례) 검증한다. DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone


def test_latest_by_member_returns_one_row_per_member(client, db_session):
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import ChatMessage
    from app.services.trainer.roster import _latest_by_member

    # user-jisu 스레드에 메시지 5건을 삽입. 다른 테스트가 남긴 런타임 메시지보다 확실히
    # 최신이 되도록 미래 시각으로 두어(순서 독립) 마지막(msg4)이 선택되는지 검증한다.
    base = datetime.now(timezone.utc) + timedelta(minutes=10)
    ids = [f"chat-test-{i}" for i in range(5)]
    for i, cid in enumerate(ids):
        db_session.add(ChatMessage(
            id=cid, trainer_id=TRAINER_ID, member_id="user-jisu",
            sender="member", body=f"msg{i}", created_at=base + timedelta(minutes=i),
        ))
    db_session.commit()
    try:
        latest = _latest_by_member(
            db_session, ChatMessage, TRAINER_ID,
            ["user-jisu", "user-7d4e9a2c5f18", "user-sungho"],
        )
        # 반환 행 수는 회원 수 이하(메시지 5건이어도) — 회원당 최신 1건만
        assert len(latest) <= 3
        assert "user-jisu" in latest
        # 최신(msg4)이 선택됨
        assert latest["user-jisu"].body == "msg4"
    finally:
        db_session.query(ChatMessage).filter(
            ChatMessage.id.in_(ids)
        ).delete(synchronize_session=False)
        db_session.commit()


def test_assign_routine_sort_order_is_monotonic(client, db_session):
    """연속 배정한 두 루틴의 sort_order 가 max+1 로 단조 증가(같은 초에도 순서 결정론적, #279)."""
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import TrainerRoutine
    from app.services.trainer import routines as trainer_routines_service

    kw = dict(minutes=10, type_="근력", reason="테스트", source="trainer")
    r1 = trainer_routines_service.assign_routine(db_session, TRAINER_ID, "user-jisu", name="rt-a", **kw)
    r2 = trainer_routines_service.assign_routine(db_session, TRAINER_ID, "user-jisu", name="rt-b", **kw)
    try:
        o1 = db_session.get(TrainerRoutine, r1.id).sort_order
        o2 = db_session.get(TrainerRoutine, r2.id).sort_order
        assert o2 == o1 + 1  # 뒤에 배정한 것이 정확히 +1
    finally:
        for rid in (r1.id, r2.id):
            row = db_session.get(TrainerRoutine, rid)
            if row is not None:
                db_session.delete(row)
        db_session.commit()
