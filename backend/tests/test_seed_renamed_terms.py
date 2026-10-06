"""시드 표기를 바꾸면 이미 시드된 DB 의 시드 행도 다시 돌 때 따라 바뀌는지. (#3201)

`런닝` 을 `러닝` 으로 고쳐도, 같은 id 가 있으면 건너뛰는 시드는 공유 DB 의 지난
기록에 옛 표기를 그대로 남긴다. 시드가 만든 행(시드 id)만 고치고, 이행률·시각
같은 다른 값은 건드리지 않는다.

`current_seed_text`·`current_seed_sentence` 표 테스트는 DB 없이 돈다. 나머지는 DB 필요(로컬 skip, CI 의 Postgres 서비스에서 실행).
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

    # 운동 목록은 지금 시드 표로 다시 맞춰진다(#2508·#3003) — 옛 표기가 남지 않는다.
    assert "런닝" not in row.exercises_json
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


# ── 옛 문장 → 지금 문장(#3202) ───────────────────────────────────────────────


def test_current_seed_sentence_renames_only_whole_seed_sentences():
    from app.db.seed_member_logs import current_seed_sentence

    assert (
        current_seed_sentence("노쇼 반복 — 수업 시간대 재조정 제안")
        == "노쇼 반복 — PT 시간대 재조정 제안"
    )
    assert current_seed_sentence("첫 세션. 체력 수준 점검 위주로 가볍게 진행.") == (
        "첫 PT. 체력 수준 점검 위주로 가볍게 진행."
    )
    # 낱말 치환이 아니다 — 데이터 값과 트레이너가 고쳐 쓴 문장은 그대로다.
    assert current_seed_sentence("PT 세션 · 트레이너 지도") == "PT 세션 · 트레이너 지도"
    assert current_seed_sentence("다음 세션 중량 조절") == "다음 세션 중량 조절"
    assert current_seed_sentence("") == ""
    assert current_seed_sentence(None) is None


def test_renamed_sentences_point_at_the_current_seed():
    """표의 새 문장은 지금 시드에 있고, 옛 문장은 어디에도 남지 않는다."""
    from pathlib import Path

    import app.db.seed_member_data as member_data
    from app.db.seed_member_logs import _RENAMED_SEED_SENTENCES
    from app.db.seed_trainer_notes import _FOLLOW_UPS, _PAST_PT_NOTES

    fixture = (Path(member_data.__file__).parent / "demo_fixture_data.json").read_text(
        encoding="utf-8"
    )
    current = {title for _member, title, *_rest in _FOLLOW_UPS}
    current |= {note for week in _PAST_PT_NOTES for note in week.values()}
    current |= {row[6] for row in member_data._SCHEDULE}
    for old, new in _RENAMED_SEED_SENTENCES.items():
        assert old not in current and f'"{old}"' not in fixture, old
        assert new in current or f'"{new}"' in fixture, new


def test_reseed_rewrites_demo_alert_copy_but_keeps_read_state(client, db_session):
    from datetime import timedelta

    from app.db.init_db import DEMO_USER_ID
    from app.db.seed_notifications import DEMO_NOTIFICATIONS, seed_demo_notifications
    from app.models.models import Notification

    item = next(n for n in DEMO_NOTIFICATIONS if n.id == "noti-demo-4")
    row = db_session.get(Notification, item.id)
    assert row is not None, "데모 알림이 시드되지 않았다"
    created_at = row.created_at - timedelta(days=3)
    # 예전 시드가 넣은 문구 그대로, 회원이 읽은 뒤.
    row.title = "이번 주 리포트가 등록됐어요"
    row.body = "트레이너님이 이번 주 리포트를 등록했어요."
    row.read = True
    row.created_at = created_at
    db_session.commit()

    assert seed_demo_notifications(db_session, DEMO_USER_ID) == 0
    db_session.expire_all()
    row = db_session.get(Notification, item.id)

    assert (row.title, row.body) == (item.title, item.body)
    assert row.read is True
    assert row.created_at == created_at

    row.read = item.read
    db_session.commit()


def test_reseed_renames_seeded_follow_up_title_only_on_exact_match(client, db_session):
    from app.db.seed_trainer_notes import seed_follow_ups
    from app.models.models import TrainerFollowUpTask

    rows = db_session.scalars(
        select(TrainerFollowUpTask)
        .where(TrainerFollowUpTask.id.like("seed-followup-%"))
        .order_by(TrainerFollowUpTask.id)
    ).all()
    assert len(rows) >= 2, "시드 할 일이 없다"
    seeded, edited = rows[0], rows[1]
    originals = {r.id: r.title for r in (seeded, edited)}
    seeded.title = "노쇼 반복 — 수업 시간대 재조정 제안"
    # 트레이너가 고쳐 쓴 제목은 옛 문장과 달라 그대로 남는다.
    edited.title = "노쇼 반복 — 수업 시간대 재조정 제안(금요일)"
    db_session.commit()
    db_session.refresh(seeded)
    updated_at = seeded.updated_at

    seed_follow_ups(db_session, clock.today(), set())
    db_session.commit()
    db_session.refresh(seeded)
    db_session.refresh(edited)

    assert seeded.title == "노쇼 반복 — PT 시간대 재조정 제안"
    assert edited.title == "노쇼 반복 — 수업 시간대 재조정 제안(금요일)"
    # 표기만 고친 할 일을 방금 손본 것처럼 올리지 않는다.
    assert seeded.updated_at == updated_at

    for r in (seeded, edited):
        r.title = originals[r.id]
    db_session.commit()


def test_reseed_renames_old_pt_notes_only_on_exact_match(client, db_session):
    from app.db.seed_trainer_notes import seed_past_pt_notes
    from app.models.models import TrainerSchedule

    rows = db_session.scalars(
        select(TrainerSchedule)
        .where(TrainerSchedule.id.like("seed-pt-%"))
        .order_by(TrainerSchedule.id)
        .limit(2)
    ).all()
    assert len(rows) == 2, "시드 PT 가 없다"
    seeded, edited = rows
    originals = {r.id: r.note for r in rows}
    seeded.note = "당일 취소 후 보강 수업. 컨디션 좋음."
    edited.note = "PT 세션 · 트레이너 지도. 다음 수업 때 확인."
    db_session.commit()

    seed_past_pt_notes(db_session, clock.today())
    db_session.commit()
    db_session.refresh(seeded)
    db_session.refresh(edited)

    assert seeded.note == "당일 취소 후 보강 PT. 컨디션 좋음."
    assert edited.note == "PT 세션 · 트레이너 지도. 다음 수업 때 확인."

    for r in rows:
        r.note = originals[r.id]
    db_session.commit()


def test_reseed_renames_fixture_pt_note(client, db_session):
    from app.db.demo_fixture import load_fixture
    from app.db.seed_member_data import _seed_fixture_pt
    from app.models.models import TrainerSchedule

    member_id = load_fixture().user_app_seed_id
    row = db_session.scalar(
        select(TrainerSchedule)
        .where(TrainerSchedule.id.like(f"seed-fix-pt-{member_id}-%"))
        .limit(1)
    )
    assert row is not None, "김민수의 픽스처 PT 가 없다"
    original = row.note
    row.note = "벤치프레스 37.5kg 4×10 성공. 다음 세션 40kg."
    db_session.commit()

    _seed_fixture_pt(db_session, {member_id})
    db_session.refresh(row)

    assert row.note == "벤치프레스 37.5kg 4×10 성공. 다음 PT 40kg."

    row.note = original
    db_session.commit()
