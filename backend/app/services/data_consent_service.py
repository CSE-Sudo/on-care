"""담당 링크의 데이터 공유 동의 — 부여·철회·열람 판단. (#1022, #1631)

**담당 해제 = 동의 철회다.** 회원이 담당을 끊든(`DELETE /me/coach`,
`DELETE /me/coach/trainer`) 트레이너가 끊든(`DELETE /trainer/clients/{id}`)
링크의 `data_consent_at` 을 비우고 `data_consent_revoked_at` 에 그 시각을 적는다.
회원 계정·트레이너 계정 탈퇴는 링크 행이 `CASCADE` 로 함께 지워지므로 따로
적을 곳이 없다.

철회는 **앞으로의 열람**만 막는다. 이미 트레이너에게 전해진 채팅·리포트·일정은
지우지 않는다 — 그 기록은 두 사람이 함께 쓴 것이다. 회원 앱의 코치 화면은 활성
담당 기준이라 해제한 동안은 비고, 같은 트레이너와 다시 연결하면 다시 보인다.

끊긴 링크를 되살릴 때(상담 수락·담당 요청 수락·연결 코드) 그 연결의 새 동의만
적는다. 새 동의가 없으면 옛 동의는 살아나지 않고, 트레이너는 회원 기록을 열 수
없다. 판단 규칙을 여러 곳이 각자 들고 있으면 한쪽만 고쳐지므로 여기에 모은다.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import ColumnElement, and_, or_

from app.core import clock
from app.models.models import TrainerClient


def revoke(link: TrainerClient, *, at: datetime | None = None) -> None:
    """링크의 동의를 철회한다(커밋 없음).

    이미 철회된 링크(동의가 비어 있고 철회 시각이 있는 링크)는 건드리지 않는다 —
    두 번 해제해도 처음 철회한 시각이 남는다.
    """
    if link.data_consent_at is None and link.data_consent_revoked_at is not None:
        return
    link.data_consent_at = None
    link.data_consent_revoked_at = at or clock.now()


def grant(link: TrainerClient, at: datetime | None) -> None:
    """이번 연결의 동의 시각을 적는다(커밋 없음).

    `None` 이면 새 동의가 없다는 뜻이다 — 옛 값을 살리지 않고 비운다. 철회
    시각은 지우지 않는다(언제 철회했는지는 이력이다).
    """
    link.data_consent_at = at


def blocks_access(link: TrainerClient) -> bool:
    """트레이너가 이 링크로 회원 기록을 열 수 없는가.

    철회된 뒤 새 동의가 없는 링크만 막는다. 동의 기능(#1022) 이전에 만들어져
    동의도 철회도 없는 링크는 그대로 둔다 — 소급해서 막으면 멀쩡한 담당이
    어느 날 기록을 못 보게 된다.
    """
    return link.data_consent_at is None and link.data_consent_revoked_at is not None


def allows_access_clause() -> ColumnElement[bool]:
    """[blocks_access] 의 반대를 SQL 조건으로. 쿼리 쪽 가드가 쓴다."""
    return or_(
        TrainerClient.data_consent_at.is_not(None),
        TrainerClient.data_consent_revoked_at.is_(None),
    )


def link_is_open(link: TrainerClient | None) -> bool:
    """트레이너가 이 링크로 회원을 **지금 담당 중인 회원**으로 다룰 수 있는가.

    살아 있는 링크(`active`)이면서 동의가 막히지 않은 링크다. 라우터의
    `_require_client` 가 이 판단으로 404 를 가르고, 집계 쿼리는 같은 판단의 SQL
    판인 [open_link_clause] 를 쓴다 — 한쪽만 고쳐지면 "열 수는 없는데 숫자로는
    세는" 회원이 생긴다(#2868).
    """
    return link is not None and bool(link.active) and not blocks_access(link)


def open_link_clause() -> ColumnElement[bool]:
    """[link_is_open] 을 SQL 조건으로. `TrainerClient` 를 조인한 쿼리에 붙인다."""
    return and_(TrainerClient.active.is_(True), allows_access_clause())
