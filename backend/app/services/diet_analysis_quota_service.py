"""식단 사진 분석 하루 상한 — 외부 비전 모델 비용을 회원 단위로 묶는다. (#2827)

사진 한 장이 비전 모델 호출 한 번이다. 분당 한도(`rate_limit.check_user`)는 폭주하는
클라이언트를 막고, 여기서는 한 회원의 하루 호출 수를 `diet_analyze_per_day` 로 묶는다.

- **모델을 부르기 직전에 센다**([reserve]). 음식을 못 찾은 사진(#2848)도 모델 비용은
  나가므로 센다. 같은 멱등키의 재전송은 모델을 부르지 않으므로 이 길에 오지 않는다.
- **같은 멱등키가 아직 분석 중이면 세지 않고 거절한다**([AnalysisInProgress], #3354).
  앱은 답이 늦으면 같은 키로 다시 보내는데, 저장된 끼니만 보고 재전송을 가리면 첫
  요청이 모델을 기다리는 동안 들어온 두 번째가 횟수와 모델 호출을 한 번씩 더 쓴다.
  멱등키로 잡은 줄은 id 가 회원·키에서 정해져([_keyed_id]) 그 줄이 곧 "이 키는
  분석 중" 이라는 표시다.
- **모델 호출이 실패하면 돌려준다**([release]). 공급자 장애로 회원의 하루 상한이
  깎이면 안 된다. 실패를 되풀이하는 클라이언트는 분당 한도가 막는다.
- 날짜는 KST 로 센다 — 자정이 지나면 다시 열린다(AI 챗봇 하루 한도와 같다).
- 같은 회원의 요청이 겹쳐도 상한을 넘지 않게 사용자 행을 잠근 채 세고 넣는다.
"""
from __future__ import annotations

import hashlib
import logging
import uuid
from datetime import timedelta

from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core import clock
from app.core.config import get_settings
from app.models.models import DietAnalysisUsage, User

logger = logging.getLogger(__name__)


class DailyAnalysisLimitReached(Exception):
    """오늘 사진 분석 횟수를 다 썼다. 라우터가 429 `daily_limit` 로 옮긴다."""


class AnalysisInProgress(Exception):
    """같은 멱등키의 분석이 아직 끝나지 않았다(재전송). 라우터가 409 `in_progress` 로 옮긴다."""


#: 끼니를 남기지 못한 채 이만큼 지난 멱등키 줄은 버려진 것으로 본다 — 분석하던
#: 프로세스가 끝난 경우다. 같은 키의 다음 요청이 거두고 새로 분석한다([reserve]).
#: 인식기 대기(`recognizer_timeout_seconds`)에 보강·저장 시간을 더한 것보다 넉넉하다.
RESERVATION_STALE_AFTER = timedelta(minutes=5)

#: 멱등키로 잡은 줄의 id 머리. 키 없이 잡은 줄(`dau-<난수>`)과 겹치지 않는다.
_KEYED_PREFIX = "dau-k-"


def _keyed_id(user_id: str, idempotency_key: str) -> str:
    """회원·멱등키에서 정해지는 줄 id. 같은 키의 두 요청이 같은 줄을 가리킨다.

    멱등키는 회원 안에서만 유일하므로(`diet_entries` 의 제약과 같다) 회원 id 를 함께
    섞는다. 기본키라 같은 키의 줄이 둘 생길 수 없다.
    """
    digest = hashlib.sha256(f"{user_id}\x00{idempotency_key}".encode()).hexdigest()
    return f"{_KEYED_PREFIX}{digest[:48]}"


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


def reserve(db: Session, user_id: str, idempotency_key: str | None = None) -> str | None:
    """모델 호출 한 번을 오늘 몫에서 잡는다. 잡은 줄의 id 를 돌려준다. 커밋한다.

    상한을 넘으면 [DailyAnalysisLimitReached]. 상한이 꺼져 있고 멱등키도 없으면
    아무것도 쓰지 않고 None 이다.

    `idempotency_key` 가 있으면 그 키의 줄로 잡는다(#3354). 같은 키의 줄이 이미 있으면
    첫 요청이 아직 분석 중이라 [AnalysisInProgress] 다 — 세지도, 모델을 부르지도
    않는다. 오래 묵은 줄([RESERVATION_STALE_AFTER])은 버려진 것으로 보고 거둔 뒤 새로
    잡는다. 상한이 꺼진 환경에서도 키가 있으면 줄을 남긴다 — 재전송을 가리는 표시다.
    """
    limit = daily_limit()
    if limit <= 0 and not idempotency_key:
        return None
    # 같은 회원의 동시 요청이 둘 다 "아직 19번" 을 읽고 21번째를 넣지 않게 한다.
    # 같은 멱등키의 두 요청도 여기서 차례로 선다.
    db.execute(select(User.id).where(User.id == user_id).with_for_update())
    if idempotency_key:
        usage_id = _keyed_id(user_id, idempotency_key)
        # 묵었는지는 DB 시계로 본다 — `created_at` 을 찍은 것도 DB 시계다.
        db.execute(
            delete(DietAnalysisUsage).where(
                DietAnalysisUsage.id == usage_id,
                DietAnalysisUsage.created_at < func.now() - RESERVATION_STALE_AFTER,
            )
        )
        in_flight = db.scalar(
            select(DietAnalysisUsage.id).where(DietAnalysisUsage.id == usage_id)
        )
        if in_flight is not None:
            db.rollback()
            raise AnalysisInProgress("같은 사진을 분석하는 중이에요.")
    else:
        usage_id = f"dau-{uuid.uuid4().hex[:12]}"
    if limit > 0 and used_today(db, user_id) >= limit:
        db.rollback()
        raise DailyAnalysisLimitReached(
            "오늘 사진 분석 횟수를 다 썼어요. 직접 추가로 기록할 수 있어요."
        )
    db.add(DietAnalysisUsage(id=usage_id, user_id=user_id, kst_date=clock.today_iso()))
    db.commit()
    return usage_id


def settle(db: Session, usage_id: str | None) -> None:
    """끼니 없이 끝난 분석(음식을 못 찾은 사진)의 줄에서 멱등키를 뗀다. 커밋한다. (#3354)

    모델은 불렀으니 그 한 번은 오늘 몫에 남긴다. 다만 끼니가 없어 같은 키의 재전송을
    돌려줄 저장분이 없으므로, 줄을 키에 묶어 두면 그 키는 묵을 때까지 "분석 중" 으로
    보인다 — id 를 키와 무관한 값으로 바꿔 둔다. 실패해도 원래 응답을 가리지 않는다.
    """
    if usage_id is None or not usage_id.startswith(_KEYED_PREFIX):
        return
    try:
        db.execute(
            update(DietAnalysisUsage)
            .where(DietAnalysisUsage.id == usage_id)
            .values(id=f"dau-{uuid.uuid4().hex[:12]}")
        )
        db.commit()
    except SQLAlchemyError:
        db.rollback()
        logger.exception("사진 분석 사용량 정리 실패 (usage=%s)", usage_id)


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
