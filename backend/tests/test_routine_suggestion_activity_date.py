"""AI 개인운동 신호는 **고객 앱이 보는 날짜**로 최근을 판단한다. (#1264)

예전에는 `created_at`(적재 시각)으로 걸렀다. 김민수 데모는 35주치를 재시드할
때마다 모든 행의 `created_at` 이 재시드 시각이라, 35주 전 운동이 최근 운동으로
잡혔다. 반대로 과거 기록을 늦게 입력하면 최근 운동이 최근이 아니게 된다.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

import pytest
from sqlalchemy import delete

from app.core import clock
from app.models.models import ExerciseSession, User
from app.services import exercise_activity as activity
from app.services import routine_suggestion_service as suggestions

TRAINER = "trainer-demo"

#: 적재만 오래된/방금 된 시각. 논리 운동일과 어긋나게 두어 규칙을 드러낸다.
_LONG_AGO = datetime(2020, 1, 1, tzinfo=timezone.utc)


def _labels_for(day: date) -> tuple[str, str]:
    """그날의 (주 시작, 요일 라벨) — 고객 앱이 저장하는 형태 그대로."""
    monday = day - timedelta(days=day.weekday())
    return monday.isoformat(), activity.WEEKDAY_LABELS[day.weekday()]


@pytest.fixture()
def member(db_session):
    """운동 기록이 하나도 없는 회원. 시드 회원은 일정·기록이 섞여 있어 쓰지 않는다."""
    member_id = f"user-activity-{clock.now().timestamp():.0f}"
    db_session.add(
        User(
            id=member_id,
            email=f"{member_id}@example.com",
            name="활동일 테스트",
            hashed_password="",
        )
    )
    db_session.commit()
    yield member_id
    db_session.execute(
        delete(ExerciseSession).where(ExerciseSession.user_id == member_id)
    )
    db_session.execute(delete(User).where(User.id == member_id))
    db_session.commit()


def _add_session(
    db,
    member_id: str,
    *,
    day: date | None,
    minutes: int = 30,
    type_: str = "strength",
    created_at: datetime = _LONG_AGO,
    completed_at: datetime | None = None,
    assigned: bool = False,
) -> None:
    week_start, day_label = _labels_for(day) if day else ("", "")
    row = ExerciseSession(
        id=f"ex-test-{member_id}-{day}-{type_}-{minutes}",
        user_id=member_id,
        week_start=week_start,
        day_label=day_label,
        type=type_,
        minutes=minutes,
        calories=minutes * 6,
        completed_at=completed_at,
        assigned_trainer_id=TRAINER if assigned else None,
        source="assigned_routine" if assigned else "member",
    )
    db.add(row)
    db.flush()
    # `created_at` 은 server_default 라 넣은 뒤에 덮어써야 한다.
    row.created_at = created_at
    db.commit()


def _signals(db, member_id: str):
    return suggestions._collect_signals(db, TRAINER, member_id)


def test_reseeded_old_workout_is_not_recent(db_session, member):
    """35주 전 운동을 **오늘 적재**해도 최근 운동이 아니다."""
    long_ago = clock.today() - timedelta(weeks=35)
    _add_session(
        db_session, member, day=long_ago, created_at=clock.now(), minutes=600
    )

    signals = _signals(db_session, member)
    assert signals.has_records is False
    assert signals.strength_heavy is False


def test_recent_workout_counts_even_when_loaded_long_ago(db_session, member):
    """논리 운동일이 최근이면 `created_at` 이 오래돼도 최근 운동이다."""
    _add_session(db_session, member, day=clock.today() - timedelta(days=1))

    signals = _signals(db_session, member)
    assert signals.has_records is True
    # 근력만 있으니 근력 편중이고 유산소가 없다.
    assert signals.strength_heavy is True
    assert signals.low_cardio is True


@pytest.mark.parametrize(
    ("days_ago", "counts"),
    [(0, True), (13, True), (14, False), (20, False)],
)
def test_window_is_today_plus_thirteen_days(db_session, member, days_ago, counts):
    """최근 구간은 **오늘을 포함한 14개 날짜**다."""
    _add_session(db_session, member, day=clock.today() - timedelta(days=days_ago))

    assert _signals(db_session, member).has_records is counts


def test_assigned_routine_record_is_not_pt_feedback(db_session, member):
    """이 트레이너가 배정한 개인운동 기록은 운동 기록일 뿐 피드백 신호가 아니다.

    개인 운동 트레이너 피드백은 없앴다(#2517) — 피드백 신호는 완료한 PT 일정의
    글만 본다.
    """
    _add_session(
        db_session,
        member,
        day=clock.today() - timedelta(days=2),
        assigned=True,
    )

    signals = _signals(db_session, member)
    assert signals.has_records is True
    assert signals.trainer_feedback is False


def test_broken_week_start_falls_back_to_completed_at(db_session, member):
    """옛 행(주차·요일이 깨짐)은 `completed_at` 의 KST 날짜로 읽는다."""
    _add_session(
        db_session,
        member,
        day=None,
        created_at=_LONG_AGO,
        completed_at=activity.noon(clock.today() - timedelta(days=3)),
    )

    assert _signals(db_session, member).has_records is True


def test_consult_note_is_not_counted_as_pt_feedback(db_session, member):
    """상담 일정의 글은 상담 메모다 — PT 피드백으로 세지 않는다(#2587)."""
    from app.models.models import TrainerSchedule

    day = (clock.today() - timedelta(days=1)).isoformat()
    db_session.add(
        TrainerSchedule(
            id=f"sch-consult-{member}",
            trainer_id=TRAINER,
            member_id=member,
            date=day,
            type="상담",
            status="완료",
            note="등록 상담 — 결혼식 전 감량 희망",
        )
    )
    db_session.commit()
    try:
        signals = _signals(db_session, member)
        assert signals.trainer_feedback is False
        assert signals.pt_just_finished is False

        db_session.add(
            TrainerSchedule(
                id=f"sch-pt-{member}",
                trainer_id=TRAINER,
                member_id=member,
                date=day,
                type="1:1 PT",
                status="완료",
                note="스쿼트 자세 좋아졌어요",
            )
        )
        db_session.commit()
        signals = _signals(db_session, member)
        assert signals.trainer_feedback is True
        assert signals.pt_just_finished is True
    finally:
        db_session.execute(
            delete(TrainerSchedule).where(TrainerSchedule.member_id == member)
        )
        db_session.commit()
