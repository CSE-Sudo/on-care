"""목록 엔드포인트가 공유하는 커서 파싱. (#980)

이 저장소의 목록 커서는 한 가지 모양이다 — 받은 마지막 항목의 `(정렬키, id)` 를
`(before, before_id)` 로 되돌려 준다. 시각만으로 자르면 같은 정렬키를 가진 항목이
여러 건일 때 그 경계에서 항목이 빠지거나 겹치므로 id 를 tie-break 로 함께 쓴다.

파싱 규칙이 엔드포인트마다 복사돼 있으면 오프셋 없는 커서의 해석 같은 세부가 한쪽만
고쳐진다. 규칙은 여기 한 곳에 둔다.
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import HTTPException

#: 목록 한 쪽의 기본 건수. 채팅 스레드·알림과 같은 값이다.
DEFAULT_PAGE = 50

#: 한 번에 받아 갈 수 있는 최대 건수.
MAX_PAGE = 100


def parse_before(before: str | None) -> datetime | None:
    """ISO datetime 커서를 읽는다. 값이 없으면 첫 쪽(None).

    오프셋 없이 온 커서는 **UTC** 로 읽는다 — 정렬키는 UTC 로 저장되므로
    (`app.core.clock`), 서버 로컬 타임존에 맡기면 쪽 경계가 밀린다.
    """
    if not before:
        return None
    try:
        cursor = datetime.fromisoformat(before)
    except ValueError as exc:
        raise HTTPException(
            status_code=422, detail="before 는 ISO datetime 이어야 해요."
        ) from exc
    if cursor.tzinfo is None:
        return cursor.replace(tzinfo=timezone.utc)
    return cursor
