"""시드 표기를 바꾸면 이미 시드된 DB 의 시드 행도 다시 돌 때 따라 바뀌는지. (#3201)

`런닝` 을 `러닝` 으로 고쳐도, 같은 id 가 있으면 건너뛰는 시드는 공유 DB 의 지난
기록에 옛 표기를 그대로 남긴다. 시드가 만든 행(시드 id)만 고치고, 이행률·시각
같은 다른 값은 건드리지 않는다.

첫 테스트는 DB 없이 돈다. 나머지는 DB 필요(로컬 skip, CI 의 Postgres 서비스에서 실행).
"""
from __future__ import annotations

from sqlalchemy import select

from app.core import clock

_MEMBER_ID = "user-jisu"


def test_current_seed_text_renames_only_the_retired_spelling():
    from app.db.seed_member_logs import current_seed_text

    assert current_seed_text("인터벌 런닝 25분 ✓") == "인터벌 러닝 25분 ✓"
    assert current_seed_text('["런닝 25분 ✓"]') == '["러닝 25분 ✓"]'
    # 운동 카탈로그의 별칭이라 그대로 둔다.
    assert current_seed_text("런닝머신 30분") == "런닝머신 30분"
    assert current_seed_text("") == ""
    assert current_seed_text(None) is None


def test_reseed_renames_seeded_history_without_touching_rate(client, db_session):
    from app.db.seed_member_data import _seed_history
    from app.models.models import RoutineHistory

    row = db_session.scalar(
        select(RoutineHistory)
        .where(
            RoutineHistory.member_id == _MEMBER_ID,
            RoutineHistory.id.like(f"seed-hist-{_MEMBER_ID}-%"),
        )
        .order_by(RoutineHistory.date.desc())
        .limit(1)
    )
    assert row is not None, "지수의 시드 운동 이력이 없다"
    original = (
        row.kind_label, row.exercises_json, row.client_feedback,
        row.trainer_note, row.completion_rate,
    )
    # 예전 시드가 넣어 둔 모양으로 되돌린다.
    row.kind_label = "AI 개인운동"
    row.exercises_json = '["인터벌 런닝 25분 ✓", "스쿼트 ✓"]'
    row.client_feedback = "런닝이 힘들었는데 다 했어요!"
    row.trainer_note = "다음 주 런닝 강도 소폭 올릴 예정."
    row.completion_rate = 42
    db_session.commit()

    _seed_history(db_session, _MEMBER_ID)
    db_session.refresh(row)

    assert row.exercises_json == '["인터벌 러닝 25분 ✓", "스쿼트 ✓"]'
    assert row.client_feedback == "러닝이 힘들었는데 다 했어요!"
    assert row.trainer_note == "다음 주 러닝 강도 소폭 올릴 예정."
    assert row.kind_label == "AI 개인운동"
    # 시드가 표기만 고친다 — 이행률은 처음 넣은 값 그대로다.
    assert row.completion_rate == 42

    (
        row.kind_label, row.exercises_json, row.client_feedback,
        row.trainer_note, row.completion_rate,
    ) = original
    db_session.commit()


def test_reseed_renames_seeded_sessions_only(client, db_session):
    from app.db.seed_member_logs import SESSION_ID_PREFIX, seed_routine_sessions
    from app.models.models import ExerciseSession

    row = db_session.scalar(
        select(ExerciseSession)
        .where(
            ExerciseSession.user_id == _MEMBER_ID,
            ExerciseSession.id.like(f"{SESSION_ID_PREFIX}{_MEMBER_ID}-%"),
        )
        .limit(1)
    )
    assert row is not None, "지수의 시드 운동 세션이 없다"
    original_name = row.name
    minutes, done_at = row.minutes, row.completed_at
    row.name = "런닝"
    db_session.commit()

    seed_routine_sessions(db_session, _MEMBER_ID, 2, clock.today())
    db_session.commit()
    db_session.refresh(row)

    assert row.name == "러닝"
    assert (row.minutes, row.completed_at) == (minutes, done_at)

    row.name = original_name
    db_session.commit()


def test_reseed_renames_seeded_drafts_without_bumping_updated_at(client, db_session):
    from app.db.seed_trainer_notes import seed_drafts
    from app.models.models import TrainerProgramDraft

    row = db_session.scalar(
        select(TrainerProgramDraft).where(
            TrainerProgramDraft.id.like("seed-draft-%"),
            TrainerProgramDraft.sessions_json.like("%러닝%"),
        )
    )
    assert row is not None, "러닝이 든 시드 프로그램 초안이 없다"
    current = row.sessions_json
    row.sessions_json = current.replace("러닝", "런닝")
    db_session.commit()
    db_session.refresh(row)
    updated_at = row.updated_at

    seed_drafts(db_session, clock.today())
    db_session.commit()
    db_session.refresh(row)

    assert row.sessions_json == current
    # 표기만 고친 초안을 트레이너가 방금 고친 것처럼 올리지 않는다.
    assert row.updated_at == updated_at
