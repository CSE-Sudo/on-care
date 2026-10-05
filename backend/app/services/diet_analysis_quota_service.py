"""식단 사진 분석 하루 상한 — 외부 비전 모델 비용을 회원 단위로 묶는다. (#2827)

사진 한 장이 비전 모델 호출 한 번이다. 분당 한도(`rate_limit.check_user`)는 폭주하는
클라이언트를 막고, 여기서는 한 회원의 하루 호출 수를 `diet_analyze_per_day` 로 묶는다.

- **모델을 부르기 직전에 센다**([reserve]). 음식을 못 찾은 사진(#2848)도 모델 비용은
  나가므로 센다. 같은 멱등키의 재전송은 모델을 부르지 않으므로 이 길에 오지 않는다.
- **모델 호출이 실패하면 돌려준다**([release]). 공급자 장애로 회원의 하루 상한이
  깎이면 안 된다. 실패를 되풀이하는 클라이언트는 분당 한도가 막는다.
- 날짜는 KST 로 센다 — 자정이 지나면 다시 열린다(AI 챗봇 하루 한도와 같다).
- 같은 회원의 요청이 겹쳐도 상한을 넘지 않게 사용자 행을 잠근 채 세고 넣는다.
"""
from __future__ import annotations

import logging
import uuid

from sqlalchemy import delete, func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core import clock
from app.core.config import get_settings
from app.models.models import DietAnalysisUsage, User

logger = logging.getLogger(__name__)


class DailyAnalysisLimitReached(Exception):
    """오늘 사진 분석 횟수를 다 썼다. 라우터가 429 `daily_limit` 로 옮긴다."""


def daily_limit() -> int:
    """하루 상한. 0 이거나 한도를 끈 환경이면 0(상한 없음)."""
    s = get_settings()
    if not s.rate_limit_enabled:
        return 0
    return max(s.diet_analyze_per_day, 0)


def used_today(db: Session, user_id: str) -> int:
    """오늘(KST) 모델을 부른 횟수."""
    return int(
        db.scalar(
            select(func.count())
            .select_from(DietAnalysisUsage)
            .where(
                DietAnalysisUsage.user_id == user_id,
                DietAnalysisUsage.kst_date == clock.today_iso(),
            )
        )
        or 0
    )


def reserve(db: Session, user_id: str) -> str | None:
    """모델 호출 한 번을 오늘 몫에서 잡는다. 잡은 줄의 id 를 돌려준다. 커밋한다.

    상한을 넘으면 [DailyAnalysisLimitReached]. 상한이 꺼져 있으면 아무것도 쓰지 않고
    None 이다.
    """
    limit = daily_limit()
    if limit <= 0:
        return None
    # 같은 회원의 동시 요청이 둘 다 "아직 19번" 을 읽고 21번째를 넣지 않게 한다.
    db.execute(select(User.id).where(User.id == user_id).with_for_update())
    if used_today(db, user_id) >= limit:
        db.rollback()
        raise DailyAnalysisLimitReached(
            "오늘 사진 분석 횟수를 다 썼어요. 직접 추가로 기록할 수 있어요."
        )
    usage_id = f"dau-{uuid.uuid4().hex[:12]}"
    db.add(DietAnalysisUsage(id=usage_id, user_id=user_id, kst_date=clock.today_iso()))
    db.commit()
    return usage_id


def release(db: Session, usage_id: str | None) -> None:
    """[reserve] 로 잡은 몫을 돌려준다(모델 호출 실패). 커밋한다.

    돌려주기가 실패해도 원래 오류(모델 실패)를 가리지 않게 로그만 남긴다 — 그 한 번이
    오늘 몫에 남을 뿐이다.
    """
    if usage_id is None:
        return
    try:
        db.execute(delete(DietAnalysisUsage).where(DietAnalysisUsage.id == usage_id))
        db.commit()
    except SQLAlchemyError:
        db.rollback()
        logger.exception("사진 분석 사용량 반환 실패 (usage=%s)", usage_id)
