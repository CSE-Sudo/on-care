"""담당 요청 알림과 프로필 동물 마이그레이션의 head를 합친다.

두 분기는 서로 다른 테이블을 변경한다. 기존 revision을 유지해 어느 분기를
먼저 적용한 DB에서도 나머지를 적용한 뒤 같은 head에 도달할 수 있게 한다.
"""

revision = "0084_merge_notification_pets"
down_revision = ("0083_notification_invite_id", "0083_profile_pets")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
