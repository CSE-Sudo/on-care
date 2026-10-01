"""트레이너 운영자 승인 상태 `trainer_profiles.verification_*` 추가. (#2825)

트레이너 웹은 이메일·비밀번호만으로 가입되고, 카카오 검색으로 아무 헬스장이나
소속으로 고르면 곧바로 회원 앱 트레이너 찾기에 노출됐다. 그 사이에 운영자 확인이
없어, 소속을 사칭한 계정이 상담 신청 정보와 담당 회원의 건강 기록을 받을 수 있었다.

승인 상태(pending/approved/rejected)와 처리 시각·처리자·반려 사유를 둔다. 승인 전
트레이너는 디렉터리·상담 대상·담당 요청·연결 코드에서 빠진다.

**기존 트레이너는 승인 상태로 채운다.** 이미 회원 앱에 나오던 트레이너가 이
마이그레이션만으로 사라지면 안 된다. 칸을 approved 기본값으로 만들어 기존 행을 한 번에
채운 뒤, 기본값을 pending 으로 바꿔 이후 들어오는 행은 닫힌 쪽에서 시작하게 한다.

Revision ID: 0124_trainer_verification
Revises: 0110_user_token_version
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0124_trainer_verification"
down_revision: str | Sequence[str] | None = "0110_user_token_version"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 기존 행 백필: approved 기본값으로 칸을 만든다.
    op.add_column(
        "trainer_profiles",
        sa.Column(
            "verification_status",
            sa.String(length=16),
            nullable=False,
            server_default="approved",
        ),
    )
    # 이후 새 행은 pending 에서 시작한다.
    op.alter_column(
        "trainer_profiles", "verification_status", server_default="pending"
    )
    op.create_check_constraint(
        "ck_trainer_profiles_verification_status",
        "trainer_profiles",
        "verification_status IN ('pending', 'approved', 'rejected')",
    )
    op.create_index(
        "ix_trainer_profiles_verification_status",
        "trainer_profiles",
        ["verification_status"],
    )
    op.add_column(
        "trainer_profiles",
        sa.Column(
            "verification_decided_at", sa.DateTime(timezone=True), nullable=True
        ),
    )
    op.add_column(
        "trainer_profiles",
        sa.Column(
            "verification_decided_by",
            sa.String(length=64),
            sa.ForeignKey(
                "users.id",
                ondelete="SET NULL",
                name="fk_trainer_profiles_verification_decided_by",
            ),
            nullable=True,
        ),
    )
    op.add_column(
        "trainer_profiles",
        sa.Column(
            "verification_note",
            sa.String(length=300),
            nullable=False,
            server_default="",
        ),
    )


def downgrade() -> None:
    op.drop_column("trainer_profiles", "verification_note")
    op.drop_column("trainer_profiles", "verification_decided_by")
    op.drop_column("trainer_profiles", "verification_decided_at")
    op.drop_index(
        "ix_trainer_profiles_verification_status", table_name="trainer_profiles"
    )
    op.drop_constraint(
        "ck_trainer_profiles_verification_status",
        "trainer_profiles",
        type_="check",
    )
    op.drop_column("trainer_profiles", "verification_status")
