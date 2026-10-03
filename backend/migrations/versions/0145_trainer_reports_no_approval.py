"""트레이너 승인 절차 정리와 회원의 트레이너 신고 표 `trainer_reports`. (#3008)

**승인 절차를 없앤다.** 트레이너는 가입하고 카카오 검색으로 실재하는 헬스장을 고르면
바로 회원 앱에 나오고 회원을 연결한다. 헬스장은 트레이너를 묶는 그룹일 뿐이다.
승인 대기·반려로 남아 있던 트레이너를 approved 로 채우고, 칸의 DB 기본값도
approved 로 바꾼다. `verification_*` 칸은 이력 보존용으로 남긴다 — 어느 코드도 이
값으로 노출·연결을 가르지 않는다.

**신고 표를 둔다.** 승인이 사라진 자리의 사후 관리 경로다. 회원이 트레이너를
사칭·부적절한 메시지·기타 사유로 신고하고, 운영자가 목록을 보고 처리한 뒤 필요하면
계정을 정지한다. 같은 회원이 같은 트레이너를 처리 전(open)에 두 번 신고할 수 없게
(trainer, reporter) 부분 유니크를 건다. 처리된 뒤 다시 신고하는 것은 된다.

Revision ID: 0145_trainer_reports_no_approval
Revises: 0140_program_draft_member
Create Date: 2026-10-03
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0145_trainer_reports_no_approval"
down_revision: str | Sequence[str] | None = "0140_program_draft_member"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 승인 대기·반려 트레이너를 승인으로 채운다 — 이 마이그레이션 뒤로는 그 값이
    # 아무것도 가르지 않지만, 칸을 읽는 사람이 오해하지 않게 맞춰 둔다.
    op.execute(
        "UPDATE trainer_profiles SET verification_status = 'approved' "
        "WHERE verification_status <> 'approved'"
    )
    op.alter_column(
        "trainer_profiles", "verification_status", server_default="approved"
    )

    op.create_table(
        "trainer_reports",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "trainer_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "reporter_id",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("reason", sa.String(32), nullable=False),
        sa.Column("memo", sa.String(200), nullable=False, server_default=""),
        sa.Column("status", sa.String(16), nullable=False, server_default="open"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "resolved_by",
            sa.String(64),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.CheckConstraint(
            "reason IN ('impersonation', 'inappropriate_message', 'other')",
            name="ck_trainer_reports_reason",
        ),
        sa.CheckConstraint(
            "status IN ('open', 'resolved', 'dismissed')",
            name="ck_trainer_reports_status",
        ),
    )
    op.create_index(
        "ix_trainer_reports_trainer_id", "trainer_reports", ["trainer_id"]
    )
    op.create_index(
        "ix_trainer_reports_reporter_id", "trainer_reports", ["reporter_id"]
    )
    # 운영 화면이 읽는 질의 그대로 — 상태별 최근 신고.
    op.create_index(
        "ix_trainer_reports_status_created",
        "trainer_reports",
        ["status", "created_at"],
    )
    op.create_index(
        "uq_trainer_reports_open",
        "trainer_reports",
        ["trainer_id", "reporter_id"],
        unique=True,
        postgresql_where=sa.text("status = 'open'"),
    )


def downgrade() -> None:
    op.drop_index("uq_trainer_reports_open", table_name="trainer_reports")
    op.drop_index("ix_trainer_reports_status_created", table_name="trainer_reports")
    op.drop_index("ix_trainer_reports_reporter_id", table_name="trainer_reports")
    op.drop_index("ix_trainer_reports_trainer_id", table_name="trainer_reports")
    op.drop_table("trainer_reports")
    # 기본값만 되돌린다. 채운 승인 상태는 되돌리지 않는다 — 누가 대기·반려였는지는
    # 이 마이그레이션이 남기지 않았고, 되돌리면 노출 중인 트레이너가 사라진다.
    op.alter_column(
        "trainer_profiles", "verification_status", server_default="pending"
    )
