"""회원 데모 시드(운동·건강프로필)의 주간 경계·멱등성 — 리뷰 반영(#311).

DB 필요(로컬 skip, CI 의 Postgres 서비스에서 실행). client 픽스처가 init_db →
seed_member_health_data 를 먼저 돌린 상태를 검증한다.
"""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import func, select

from app.core import clock


_MEMBER_ID = "user-7d4e9a2c5f18"


def _this_monday_iso() -> str:
    today = clock.today()
    return (today - timedelta(days=today.weekday())).isoformat()


def test_exercise_seed_has_this_week_start(client, db_session):
    """시드가 이번 주(월요일 기준) 세션을 적재한다 — 하드코딩된 과거 주가 아니라.

    조회를 이번 주로 스코프한다: `_seed_exercise` 는 주가 바뀌면 지난주 행을
    지우지 않고 새 주 행을 덧붙이므로, 유저 전체를 조회하면 다음 주부터 지난주
    행까지 섞여 들어와 단정이 깨진다.
    """
    from app.models.models import ExerciseSession

    rows = db_session.scalars(
        select(ExerciseSession).where(
            ExerciseSession.user_id == _MEMBER_ID,
            ExerciseSession.week_start == _this_monday_iso(),
        )
    ).all()
    assert rows, "이번 주 운동 시드가 없습니다."


def test_exercise_seed_skips_future_weekdays(client, db_session):
    """미래 요일은 이번 주 합계·streak 에 잡히지 않도록 시드하지 않는다(#311)."""
    from app.db.seed_member_data import _WEEKDAY_INDEX
    from app.models.models import ExerciseSession

    today_idx = clock.today().weekday()
    labels = db_session.scalars(
        select(ExerciseSession.day_label).where(
            ExerciseSession.user_id == _MEMBER_ID,
            ExerciseSession.week_start == _this_monday_iso(),
        )
    ).all()
    assert labels, "이번 주 운동 시드가 없습니다."
    # 시드된 모든 요일은 오늘(포함) 이전이어야 한다.
    assert all(_WEEKDAY_INDEX[label] <= today_idx for label in labels)


def test_exercise_seed_is_idempotent(client, db_session):
    """재실행해도 세션 수가 늘지 않는다.

    김민수는 픽스처 회원이라 `_seed_from_fixture` 가 그의 `seed-` 행을 통째로
    다시 깐다 — 그래도 결과는 같아야 한다(오늘치가 이미 있으면 손대지 않는다).
    """
    from app.db.seed_member_data import _seed_from_fixture
    from app.models.models import ExerciseSession

    def _count() -> int:
        return db_session.scalar(
            select(func.count())
            .select_from(ExerciseSession)
            .where(
                ExerciseSession.user_id == _MEMBER_ID,
                ExerciseSession.week_start == _this_monday_iso(),
            )
        )

    before = _count()
    assert before > 0
    _seed_from_fixture(db_session, _MEMBER_ID)
    _seed_from_fixture(db_session, _MEMBER_ID)
    assert _count() == before


def test_fixture_sessions_record_the_day_they_happened(client, db_session):
    """시드한 운동에 그날의 `completed_at` 이 함께 적힌다. (#1264)

    없으면 재시드마다 모든 행의 `created_at` 이 지금이 되어, 35주 전 운동도
    최근 활동으로 읽힌다. 논리 운동일과 어긋나지 않는지도 함께 본다.
    """
    from app.models.models import ExerciseSession
    from app.services import exercise_activity

    rows = db_session.scalars(
        select(ExerciseSession).where(
            ExerciseSession.user_id == _MEMBER_ID,
            ExerciseSession.id.like("seed-fix-ex-%"),
        )
    ).all()
    assert rows, "픽스처 운동 시드가 없다"

    for row in rows:
        assert row.completed_at is not None, row.id
        day = exercise_activity.activity_date_of(row)
        assert day is not None
        # 적힌 시각의 KST 날짜가 곧 그 기록의 운동일이다.
        assert clock.to_seoul(row.completed_at).date() == day, row.id


def test_no_personal_doc_points_at_a_deleted_seed_row(client, db_session):
    """지워진 시드 행을 가리키는 개인 RAG 문서가 남지 않는다.

    개인 문서 적재는 추가만 한다. 픽스처를 다시 깔며 행을 지우면 문서만 남아 **옛
    수치를 말하고**, 코치가 같은 날짜에 새 값과 옛 값을 함께 인용하게 된다.
    """
    from app.models.models import CoachDocument, DietEntry, ExerciseSession

    refs = db_session.scalars(
        select(CoachDocument.source_ref).where(
            CoachDocument.user_id == _MEMBER_ID
        )
    ).all()
    diet_ids = set(
        db_session.scalars(
            select(DietEntry.id).where(DietEntry.user_id == _MEMBER_ID)
        ).all()
    )
    exercise_ids = set(
        db_session.scalars(
            select(ExerciseSession.id).where(
                ExerciseSession.user_id == _MEMBER_ID
            )
        ).all()
    )

    orphans = [
        ref
        for ref in refs
        if ref
        and (ref.startswith("seed-diet-") or ref.startswith("seed-fix-diet-"))
        and ref not in diet_ids
    ] + [
        ref
        for ref in refs
        if ref
        and (ref.startswith("seed-ex-") or ref.startswith("seed-fix-ex-"))
        and ref not in exercise_ids
    ]
    assert not orphans, f"삭제된 행을 가리키는 개인 문서가 남았습니다: {orphans[:5]}"


def test_seeded_days_match_the_fixture(client, db_session):
    """DB 에 들어간 김민수의 하루가 픽스처가 말하는 값과 같다.

    두 앱은 같은 픽스처를 읽으므로, 이 단정이 곧 "백엔드로 붙여도 데모에서 보던
    숫자가 그대로"라는 뜻이다(#757).
    """
    from app.db.demo_fixture import load_fixture
    from app.models.models import DietEntry, RoutineHistory

    days = {d.iso: d for d in load_fixture().days_for(clock.today())}

    rows = db_session.scalars(
        select(DietEntry).where(DietEntry.user_id == _MEMBER_ID)
    ).all()
    totals: dict[str, int] = {}
    for row in rows:
        if not row.id.startswith("seed-"):
            continue  # 회원이 직접 남긴 기록은 픽스처 소관이 아니다.
        totals[row.date] = totals.get(row.date, 0) + row.total_calories
    assert totals, "김민수 식단 시드가 없습니다."
    for iso, calories in totals.items():
        assert calories == days[iso].calories, f"{iso} 칼로리가 픽스처와 다릅니다."

    history = db_session.scalars(
        select(RoutineHistory).where(RoutineHistory.member_id == _MEMBER_ID)
    ).all()
    assert history, "김민수 운동 이력 시드가 없습니다."
    for row in history:
        if not row.id.startswith("seed-"):
            continue
        assert row.completion_rate == days[row.date].completion, (
            f"{row.date} 이행률이 픽스처와 다릅니다."
        )


def test_today_pt_schedule_matches_the_fixture_pt(client, db_session):
    """김민수 오늘 PT 일정과 운동 기록 PT 카드가 같은 운동을 말한다(#2567).

    일정 프로그램·이력 줄·픽스처가 종목과 세트·횟수(초)·중량까지 같다. 예전에는
    일정이 `10:00 · 레그프레스 …` 를 따로 지어내, 같은 날 운동 기록의 PT 카드
    (`벤치프레스 …`)와 달랐다.
    """
    import json

    from app.db.demo_fixture import load_fixture
    from app.models.models import RoutineHistory, TrainerSchedule
    from app.services.trainer_service import parse_history_exercise

    today = clock.today()
    fixture_day = load_fixture().days_for(today)[-1]
    assert fixture_day.is_pt

    slot = db_session.scalar(
        select(TrainerSchedule).where(
            TrainerSchedule.member_id == _MEMBER_ID,
            TrainerSchedule.date == today.isoformat(),
            TrainerSchedule.id.like(f"seed-schedule-{today.isoformat()}-%"),
        )
    )
    assert slot is not None, "김민수 오늘 PT 일정 시드가 없습니다."
    program = [
        (
            item["name"],
            item.get("sets"),
            item.get("reps"),
            item.get("hold_seconds"),
            item.get("weight"),
        )
        for item in json.loads(slot.program_json)
    ]
    expected = [
        (e.name, e.sets, e.reps, e.hold_seconds, e.weight)
        for e in fixture_day.exercises
    ]
    assert program == expected

    history = db_session.scalar(
        select(RoutineHistory).where(
            RoutineHistory.member_id == _MEMBER_ID,
            RoutineHistory.date == today.isoformat(),
            RoutineHistory.id.like("seed-%"),
        )
    )
    assert history is not None, "김민수 오늘 PT 이력 시드가 없습니다."
    items = [
        parse_history_exercise(raw) for raw in json.loads(history.exercises_json)
    ]
    assert [
        (i.name, i.sets, i.reps, i.hold_seconds, i.weight) for i in items
    ] == expected


def test_seeded_history_cards_show_the_amounts(client):
    """PT 세션·AI 개인운동 이력 카드에 세트·횟수·중량·시간이 선다(#2567)."""
    r = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    headers = {"Authorization": f"Bearer {r.json()['access_token']}"}

    hist = client.get(
        f"/v1/trainer/clients/{_MEMBER_ID}/history", headers=headers
    ).json()
    # 다른 테스트가 남긴 실제 PT 완료 이력은 소관이 아니다.
    items = [
        item
        for entry in hist
        if entry["id"].startswith("seed-")
        for item in entry["exercise_items"]
    ]
    assert items, "김민수 이력 시드가 없습니다."
    for item in items:
        if item["type"] == "strength":
            assert item["sets"], item
        else:
            assert item["minutes"], item


def test_timeline_members_history_does_not_contradict_today(client, db_session):
    """오늘 타임라인의 회원은 오늘 이력이 없거나, 있으면 같은 운동이다(#2567)."""
    import json

    from app.db.seed_member_data import _SCHEDULE
    from app.models.models import RoutineHistory
    from app.services.trainer_service import parse_history_exercise

    today = clock.today().isoformat()
    for _t, name, member_id, _typ, _dur, _status, _note, program in _SCHEDULE:
        if not member_id or not program:
            continue
        row = db_session.scalar(
            select(RoutineHistory).where(
                RoutineHistory.member_id == member_id,
                RoutineHistory.date == today,
                RoutineHistory.id.like("seed-%"),
            )
        )
        if row is None:
            continue
        names = [
            parse_history_exercise(raw).name
            for raw in json.loads(row.exercises_json)
        ]
        assert names == [item["name"] for item in program], name


def test_health_profile_seeded_once(client, db_session):
    """건강 프로필은 시드되어 있고, 재실행해도 중복 생성되지 않는다(멱등)."""
    from app.db.seed_member_data import _seed_health_profile
    from app.models.models import HealthProfile

    def _count() -> int:
        return db_session.scalar(
            select(func.count())
            .select_from(HealthProfile)
            .where(HealthProfile.user_id == _MEMBER_ID)
        )

    assert _count() == 1
    _seed_health_profile(db_session, _MEMBER_ID)
    assert _count() == 1


def test_health_profile_goals_persisted(client, db_session):
    """프로필이 없던 회원에 시드하면 위험도·활동 관련 필드가 저장된다."""
    from app.models.models import HealthProfile

    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == _MEMBER_ID)
    )
    assert profile is not None
    assert profile.risk_level == "medium"
    assert profile.risk_title
