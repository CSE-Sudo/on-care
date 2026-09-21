"""담당 요청 알림의 요청 ID. (#1802)

과거 알림은 요청을 정확히 복원할 근거가 없어 null로 유지한다.
"""
import sqlalchemy as sa
from alembic import op

revision = "0083_notification_invite_id"
down_revision = "0082_isometric_hold_seconds"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("notifications", sa.Column("invite_id", sa.String(64), nullable=True))


def downgrade() -> None:
    op.execute(
        "UPDATE notifications SET category = 'consultation_result' "
        "WHERE category = 'coach_invite'"
    )
    op.drop_column("notifications", "invite_id")
