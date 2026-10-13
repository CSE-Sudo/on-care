"""0104_backfill_schedule_member_id 의 upgrade 형태(#3236).

`UPDATE <표> AS <별칭> SET … FROM (…)` 은 이전 패턴(`update <식별자> set`)을 비껴가 `OK` 로
통과했다. 실제 마이그레이션 파일이 바뀌어도 이 형태는 여기서 계속 잡히는지 본다.
"""
from __future__ import annotations

from alembic import op

revision = "0104_fixture"
down_revision = None


def upgrade() -> None:
    op.execute(
        "UPDATE trainer_schedule AS s SET member_id = m.member_id "
        "FROM ("
        "SELECT tc.trainer_id, u.name, MIN(tc.member_id) AS member_id "
        "FROM trainer_clients AS tc JOIN users AS u ON u.id = tc.member_id "
        "WHERE u.name <> '' "
        "GROUP BY tc.trainer_id, u.name "
        "HAVING COUNT(DISTINCT tc.member_id) = 1"
        ") AS m "
        "WHERE s.member_id IS NULL "
        "AND s.trainer_id = m.trainer_id "
        "AND s.client_name = m.name"
    )


def downgrade() -> None:
    pass
