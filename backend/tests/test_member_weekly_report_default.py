"""트레이너 주간 리포트 알림 기본값 켬. (#3025)

리포트 알림이 기본 꺼짐이라, 설정을 바꾼 적 없는 회원의 알림함에 트레이너가
보낸 리포트가 아무 흔적 없이 도착했다. 서비스 기본값·모델·마이그레이션이 같은
값을 말해야 한다 — 하나만 바뀌면 행이 있는 회원과 없는 회원이 다르게 받는다.

DB 없이 돈다.
"""
from __future__ import annotations

from pathlib import Path

from app.models.models import MemberNotificationSetting
from app.services import notification_service

MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0143_member_weekly_report_default_on.py"
)


def test_service_default_is_on():
    assert notification_service.DEFAULTS[notification_service.WEEKLY_REPORT] is True


def test_model_default_is_on():
    column = MemberNotificationSetting.__table__.c.weekly_report
    assert column.default.arg is True
    assert "true" in str(column.server_default.arg).lower()


def test_model_and_service_agree_on_every_column():
    table = MemberNotificationSetting.__table__.c
    by_key = {
        notification_service.DIET_LOG: table.diet_log,
        notification_service.EXERCISE: table.exercise_reminder,
        notification_service.TRAINER_MESSAGE: table.trainer_message,
        notification_service.AI_COACHING: table.ai_coaching,
        notification_service.WEEKLY_REPORT: table.weekly_report,
    }
    for key, column in by_key.items():
        assert column.default.arg is notification_service.DEFAULTS[key], key


def test_migration_turns_the_column_and_stored_rows_on():
    text = MIGRATION.read_text(encoding="utf-8")
    assert 'revision: str = "0143_member_weekly_report_on"' in text
    assert "server_default=sa.true()" in text
    # 기존 행의 물려받은 `false` 를 한 번 켠다.
    assert "SET weekly_report = TRUE WHERE weekly_report = FALSE" in text


def test_migration_downgrade_restores_only_the_column_default():
    text = MIGRATION.read_text(encoding="utf-8")
    downgrade = text.split("def downgrade()", 1)[1]
    assert "server_default=sa.false()" in downgrade
    assert "UPDATE" not in downgrade


def test_revision_id_fits_the_alembic_version_column():
    # alembic_version.version_num 은 VARCHAR(32) 다.
    assert len("0143_member_weekly_report_on") <= 32
