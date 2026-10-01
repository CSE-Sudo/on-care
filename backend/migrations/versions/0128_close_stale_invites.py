"""담당이 이미 생긴 회원에게 남은 대기 중 담당 요청 정리. (#2894)

동기화 코드 연결·담당 요청 수락이 그 회원의 다른 대기 요청을 닫지 않아, 트레이너
웹 '답 기다리는 요청'과 회원 앱 받은 요청에 이미 끝난 요청이 남아 있다. 서비스가
이제 담당이 생길 때 같은 트랜잭션에서 닫으므로, 그 전에 쌓인 행만 같은 기준으로
한 번 닫는다.

- 지금 활성 담당인 트레이너가 보낸 대기 요청 → `accepted`
- 다른 트레이너가 보낸 대기 요청 → `cancelled`

활성 담당이 없는 회원의 대기 요청은 그대로 둔다 — 아직 수락할 수 있는 요청이다.
되돌리기(downgrade)는 하지 않는다. 닫힌 요청을 다시 대기로 돌리면 이미 담당이 있는
회원에게 수락할 수 없는 요청이 다시 생길 뿐이다.

Revision ID: 0128_close_stale_invites
Revises: 0110_user_token_version
Create Date: 2026-10-01
"""
from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0128_close_stale_invites"
down_revision: str | Sequence[str] | None = "0110_user_token_version"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE trainer_client_invites AS i
        SET status = 'accepted', decided_at = now()
        FROM trainer_clients AS c
        WHERE i.status = 'pending'
          AND c.member_id = i.member_id
          AND c.trainer_id = i.trainer_id
          AND c.active IS TRUE
        """
    )
    op.execute(
        """
        UPDATE trainer_client_invites AS i
        SET status = 'cancelled', decided_at = now()
        FROM trainer_clients AS c
        WHERE i.status = 'pending'
          AND c.member_id = i.member_id
          AND c.trainer_id <> i.trainer_id
          AND c.active IS TRUE
        """
    )


def downgrade() -> None:
    pass
