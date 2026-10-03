"""서버 전체·트레이너 하루 AI 호출 상한 서비스. (#3032)

여기서 보는 것:

* 설정값만큼 통과하고 그다음은 막는다 — 전역은 `AiCapacityReached`, 트레이너는
  `TrainerAiDailyLimitReached`. 둘 다 `Retry-After` 로 다음 KST 자정까지 초를 싣는다.
* 0 이거나 `RATE_LIMIT_ENABLED=false` 면 끈다(DB 에 쓰지도 않는다).
* 트레이너 버킷은 계정마다 따로고, 트레이너 상한에 걸린 호출은 전역 몫을 깎지 않는다.
  전역에 걸리면 같은 호출의 트레이너 몫도 되돌린다.
* 날짜는 KST — 23:59 에 다 쓴 몫이 00:00 에 다시 열린다.
* 여러 스레드가 동시에 불러도 상한을 넘지 않는다(행 잠금 안의 조건부 증가).

순수 함수(`seconds_until_reset`·상한 읽기)는 DB 없이, 세는 쪽은 DB 테스트(로컬 skip,
CI 실행)다.
"""
from __future__ import annotations

import threading
from datetime import datetime
from pathlib import Path
from uuid import uuid4

import pytest
from sqlalchemy import delete, text

from app.core import clock
from app.core.config import get_settings
from app.models.models import AiCallUsage, User
from app.services import ai_call_quota as quota

KST = clock.SEOUL
MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0144_ai_call_usages.py"
)


@pytest.fixture
def caps(monkeypatch):
    """한도를 켠 설정. 각 테스트가 상한 값을 직접 넣는다."""
    s = get_settings()
    monkeypatch.setattr(s, "rate_limit_enabled", True)
    monkeypatch.setattr(s, "ai_global_calls_per_day", 0)
    monkeypatch.setattr(s, "trainer_ai_calls_per_day", 0)
    return s


# ---------- 순수 함수 (DB 불필요) ----------


def test_seconds_until_reset_counts_to_the_next_kst_midnight():
    assert quota.seconds_until_reset(datetime(2026, 10, 3, 23, 59, 0, tzinfo=KST)) == 60
    assert quota.seconds_until_reset(datetime(2026, 10, 3, 0, 0, 0, tzinfo=KST)) == 86400
    assert quota.seconds_until_reset(datetime(2026, 10, 3, 12, 0, 0, tzinfo=KST)) == 43200


def test_seconds_until_reset_reads_utc_input_in_kst():
    """UTC 15:00 은 KST 자정이다 — 서버 시간대와 무관하게 KST 로 끊는다."""
    from datetime import timezone

    utc_1459 = datetime(2026, 10, 3, 14, 59, 0, tzinfo=timezone.utc)
    assert quota.seconds_until_reset(utc_1459) == 60


def test_seconds_until_reset_is_never_zero():
    almost = datetime(2026, 10, 3, 23, 59, 59, 999999, tzinfo=KST)
    assert quota.seconds_until_reset(almost) == 1


def test_limits_follow_settings(caps, monkeypatch):
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 500)
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 30)
    assert quota.global_limit() == 500
    assert quota.trainer_limit() == 30
    monkeypatch.setattr(caps, "ai_global_calls_per_day", -1)
    assert quota.global_limit() == 0


def test_limits_are_off_when_rate_limiting_is_disabled(caps, monkeypatch):
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 500)
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 30)
    monkeypatch.setattr(caps, "rate_limit_enabled", False)
    assert quota.global_limit() == 0
    assert quota.trainer_limit() == 0


def test_acquire_does_not_touch_the_db_when_both_caps_are_off(caps, monkeypatch):
    """끈 상태(기본값)에서는 세션조차 열지 않는다 — DB 없는 단위 테스트도 지나간다."""

    def _no_db():
        raise AssertionError("상한이 꺼져 있으면 DB 를 보지 않는다")

    monkeypatch.setattr(quota, "_session", _no_db)
    for _ in range(5):
        quota.acquire(quota.FEATURE_COACH_CHAT)
        quota.acquire(quota.FEATURE_ROUTINE_OPTIONS, trainer_id="trainer-x")


def test_trainer_cap_is_ignored_for_member_features(caps, monkeypatch):
    """트레이너 id 없이 부르는 회원 기능은 트레이너 상한을 보지 않는다."""
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 1)

    def _no_db():
        raise AssertionError("회원 기능은 트레이너 버킷을 세지 않는다")

    monkeypatch.setattr(quota, "_session", _no_db)
    quota.acquire(quota.FEATURE_DIET_PHOTO)


def test_defaults_keep_the_global_cap_off_and_bound_trainers():
    from app.core.config import Settings

    fields = Settings.model_fields
    assert fields["ai_global_calls_per_day"].default == 0
    assert fields["trainer_ai_calls_per_day"].default == 200
    assert fields["llm_max_output_tokens"].default == 4096


# ---------- DB ----------


def _clear_usage() -> None:
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        db.execute(delete(AiCallUsage))
        db.commit()
    finally:
        db.close()


@pytest.fixture
def usage(db_session):
    """테스트마다 빈 카운터에서 시작하고 끝나면 지운다(스위트가 DB 를 공유한다)."""
    _clear_usage()
    yield db_session
    _clear_usage()


@pytest.fixture
def trainers(db_session):
    """FK 를 만족하는 트레이너 계정 둘."""
    ids = [f"ai-cap-trainer-{uuid4().hex[:10]}" for _ in range(2)]
    for tid in ids:
        db_session.add(
            User(
                id=tid,
                email=f"{tid}@oncare.com",
                name="상한 확인 트레이너",
                hashed_password="unused",
                role="trainer",
            )
        )
    db_session.commit()
    yield ids
    db_session.rollback()
    db_session.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": ids})
    db_session.commit()


def test_global_cap_stops_at_the_setting(caps, usage, monkeypatch):
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 3)
    for _ in range(3):
        quota.acquire(quota.FEATURE_COACH_CHAT)

    with pytest.raises(quota.AiCapacityReached) as exc:
        quota.acquire(quota.FEATURE_DIET_PHOTO)
    assert exc.value.retry_after_seconds >= 1
    # 막힌 호출은 세지 않는다 — 값은 상한 그대로다.
    assert quota.used_today(quota.GLOBAL_BUCKET) == 3


def test_every_feature_shares_one_global_bucket(caps, usage, monkeypatch):
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 4)
    quota.acquire(quota.FEATURE_COACH_CHAT)
    quota.acquire(quota.FEATURE_DIET_ADVICE)
    quota.acquire(quota.FEATURE_DIET_RECOMMENDATION)
    quota.acquire(quota.FEATURE_EXERCISE_NAME)
    with pytest.raises(quota.AiCapacityReached):
        quota.acquire(quota.FEATURE_DIET_MENU_PLAN)


def test_zero_global_cap_writes_nothing(caps, usage):
    for _ in range(10):
        quota.acquire(quota.FEATURE_COACH_CHAT)
    assert quota.used_today(quota.GLOBAL_BUCKET) == 0


def test_trainer_cap_stops_one_account_only(caps, usage, trainers, monkeypatch):
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 2)
    first, second = trainers
    quota.acquire(quota.FEATURE_ROUTINE_OPTIONS, trainer_id=first)
    quota.acquire(quota.FEATURE_REPORT_SUMMARY, trainer_id=first)

    with pytest.raises(quota.TrainerAiDailyLimitReached) as exc:
        quota.acquire(quota.FEATURE_TRAINER_COACH, trainer_id=first)
    assert exc.value.retry_after_seconds >= 1

    # 다른 트레이너는 영향이 없다.
    quota.acquire(quota.FEATURE_TRAINER_COACH, trainer_id=second)
    assert quota.used_today(quota.trainer_bucket(first)) == 2
    assert quota.used_today(quota.trainer_bucket(second)) == 1


def test_trainer_rejection_does_not_spend_the_global_share(
    caps, usage, trainers, monkeypatch
):
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 1)
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 100)
    quota.acquire(quota.FEATURE_ROUTINE_OPTIONS, trainer_id=trainers[0])
    for _ in range(3):
        with pytest.raises(quota.TrainerAiDailyLimitReached):
            quota.acquire(quota.FEATURE_ROUTINE_OPTIONS, trainer_id=trainers[0])
    assert quota.used_today(quota.GLOBAL_BUCKET) == 1


def test_global_rejection_rolls_back_the_trainer_share(
    caps, usage, trainers, monkeypatch
):
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 10)
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 1)
    quota.acquire(quota.FEATURE_COACH_CHAT)  # 회원이 전역 몫을 다 썼다

    with pytest.raises(quota.AiCapacityReached):
        quota.acquire(quota.FEATURE_ROUTINE_OPTIONS, trainer_id=trainers[0])
    # 모델을 부르지 않았으니 트레이너 몫도 남아 있어야 한다.
    assert quota.used_today(quota.trainer_bucket(trainers[0])) == 0


def test_the_trainer_row_keeps_the_trainer_id(caps, usage, trainers, monkeypatch):
    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 5)
    quota.acquire(quota.FEATURE_ROUTINE_OPTIONS, trainer_id=trainers[0])
    usage.expire_all()
    row = usage.get(AiCallUsage, (clock.today_iso(), quota.trainer_bucket(trainers[0])))
    assert row is not None
    assert row.trainer_id == trainers[0]
    assert row.calls == 1


def test_counts_reopen_at_kst_midnight(caps, usage, monkeypatch):
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 1)
    before = datetime(2026, 10, 3, 23, 59, 0, tzinfo=KST)
    after = datetime(2026, 10, 4, 0, 0, 0, tzinfo=KST)

    monkeypatch.setattr(clock, "now", lambda: before)
    quota.acquire(quota.FEATURE_COACH_CHAT)
    with pytest.raises(quota.AiCapacityReached) as exc:
        quota.acquire(quota.FEATURE_COACH_CHAT)
    assert exc.value.retry_after_seconds == 60

    monkeypatch.setattr(clock, "now", lambda: after)
    quota.acquire(quota.FEATURE_COACH_CHAT)
    assert quota.used_today(quota.GLOBAL_BUCKET) == 1


def test_concurrent_calls_never_exceed_the_cap(caps, usage, monkeypatch):
    """인스턴스 여러 대가 같은 순간에 불러도 상한을 넘지 않는다."""
    limit = 10
    monkeypatch.setattr(caps, "ai_global_calls_per_day", limit)
    accepted: list[int] = []
    rejected: list[int] = []
    lock = threading.Lock()
    start = threading.Barrier(8)

    def _worker() -> None:
        start.wait()
        for _ in range(5):
            try:
                quota.acquire(quota.FEATURE_COACH_CHAT)
            except quota.AiCapacityReached:
                with lock:
                    rejected.append(1)
            else:
                with lock:
                    accepted.append(1)

    threads = [threading.Thread(target=_worker) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)

    assert len(accepted) == limit
    assert len(rejected) == 8 * 5 - limit
    assert quota.used_today(quota.GLOBAL_BUCKET) == limit


def test_rejections_are_counted_by_reason(caps, usage, trainers, monkeypatch):
    from app.core import metrics

    monkeypatch.setattr(caps, "trainer_ai_calls_per_day", 1)
    monkeypatch.setattr(caps, "ai_global_calls_per_day", 2)
    before = dict(metrics.snapshot()["counters"])

    quota.acquire(quota.FEATURE_ROUTINE_OPTIONS, trainer_id=trainers[0])
    with pytest.raises(quota.TrainerAiDailyLimitReached):
        quota.acquire(quota.FEATURE_ROUTINE_OPTIONS, trainer_id=trainers[0])
    quota.acquire(quota.FEATURE_COACH_CHAT)
    with pytest.raises(quota.AiCapacityReached):
        quota.acquire(quota.FEATURE_COACH_CHAT)

    after = metrics.snapshot()["counters"]

    def delta(key: str) -> int:
        return after.get(key, 0) - before.get(key, 0)

    assert delta("ai_calls.rejected{feature=routine_options,reason=trainer_daily}") == 1
    assert delta("ai_calls.rejected{feature=coach_chat,reason=global_cap}") == 1
    assert delta("ai_calls.acquired{feature=routine_options}") == 1
    assert delta("ai_calls.acquired{feature=coach_chat}") == 1


def test_migration_follows_the_weekly_report_revision():
    """0144 는 0143(주간 리포트 기본 켜짐) 바로 뒤에 붙는다 — 머리 1개 체인.

    머리 개수는 CI 의 Alembic head 검사가 따로 확인한다.
    """
    text_ = MIGRATION.read_text(encoding="utf-8")
    assert 'revision: str = "0144_ai_call_usages"' in text_
    assert (
        'down_revision: str | Sequence[str] | None = "0143_member_weekly_report_on"'
        in text_
    )
    assert "Revises: 0143_member_weekly_report_on" in text_
    assert '"ai_call_usages"' in text_
