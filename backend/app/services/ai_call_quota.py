"""서버 전체·트레이너 계정의 하루 AI 호출 상한. (#3032)

회원 단위 한도(AI 코치 하루 횟수 `ai_chat_quota_service`, 사진 분석 하루 횟수
`diet_analysis_quota_service`)는 한 회원의 비용만 묶는다. 여기서는 그 위에 두 상한을
더한다.

- **전역**(`ai_global_calls_per_day`): 외부 LLM·비전 모델을 실제로 부르는 모든 기능의
  하루 합. 넘으면 [AiCapacityReached] — 규칙형 폴백이 있는 기능은 폴백으로, 없는
  기능(AI 코치 채팅·사진 분석)은 503 `ai_capacity` 로 답한다.
- **트레이너**(`trainer_ai_calls_per_day`): 한 트레이너의 고객 AI 코치·루틴 후보·리포트
  요약 합. 넘으면 [TrainerAiDailyLimitReached] — 429 `daily_limit` + `Retry-After`.

세는 규칙:

- 모델을 **부르기 직전에** 센다([acquire]). 키가 없어 모델을 부르지 않는 폴백은 세지
  않는다. 호출이 실패해도 돌려주지 않는다 — 공급자는 요청을 받은 뒤 실패해도 비용이
  나갈 수 있고, 이 값은 "하루에 몇 번까지 부를 수 있나"의 천장이다.
- `(kst_date, bucket)` 한 행을 `INSERT … ON CONFLICT DO UPDATE … WHERE calls < 상한`
  으로 더한다. 여러 인스턴스가 동시에 불러도 상한을 넘지 않는다.
- 요청의 DB 세션과 따로 짧은 세션을 쓴다. 호출처 대부분이 LLM 을 기다리기 전에 요청
  연결을 풀로 돌려준 뒤라(#2836), 그 트랜잭션을 다시 열거나 커밋하지 않기 위해서다.
- 날짜는 KST — 자정이 지나면 다시 열린다(회원 하루 한도와 같다).
"""
from __future__ import annotations

import logging
from datetime import datetime, time, timedelta

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core import clock, metrics
from app.core.config import get_settings
from app.models.models import AiCallUsage

logger = logging.getLogger(__name__)

#: 서버 전체 버킷 이름.
GLOBAL_BUCKET = "global"

#: 기능 키 — 메트릭 라벨로 쓴다. 카디널리티가 낮은 고정 값만 둔다.
FEATURE_COACH_CHAT = "coach_chat"
FEATURE_COACH_FEEDBACK = "coach_feedback"
FEATURE_ROUTINE_OPTIONS = "routine_options"
FEATURE_REPORT_SUMMARY = "report_summary"
FEATURE_DIET_PHOTO = "diet_photo"
FEATURE_DIET_ADVICE = "diet_advice"
FEATURE_DIET_RECOMMENDATION = "diet_recommendation"
FEATURE_DIET_MENU_PLAN = "diet_menu_plan"
FEATURE_EXERCISE_NAME = "exercise_name"


class AiCapacityReached(RuntimeError):
    """서버 전체의 오늘 AI 호출 상한을 다 썼다. 모델을 부르지 않았다."""

    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__("서버 전체 AI 하루 호출 상한 도달")
        self.retry_after_seconds = retry_after_seconds


class TrainerAiDailyLimitReached(RuntimeError):
    """이 트레이너의 오늘 AI 호출 상한을 다 썼다. 모델을 부르지 않았다."""

    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__("트레이너 AI 하루 호출 상한 도달")
        self.retry_after_seconds = retry_after_seconds


def global_limit() -> int:
    """서버 전체 하루 상한. 0 이거나 한도를 끈 환경이면 0(상한 없음)."""
    s = get_settings()
    if not s.rate_limit_enabled:
        return 0
    return max(s.ai_global_calls_per_day, 0)


def trainer_limit() -> int:
    """트레이너 한 계정의 하루 상한. 0 이거나 한도를 끈 환경이면 0(상한 없음)."""
    s = get_settings()
    if not s.rate_limit_enabled:
        return 0
    return max(s.trainer_ai_calls_per_day, 0)


def trainer_bucket(trainer_id: str) -> str:
    return f"trainer:{trainer_id}"


def seconds_until_reset(now: datetime | None = None) -> int:
    """다음 KST 자정까지 남은 초(`Retry-After`). 최소 1초."""
    current = clock.to_seoul(now) if now is not None else clock.now()
    midnight = datetime.combine(
        current.date() + timedelta(days=1), time.min, tzinfo=clock.SEOUL
    )
    return max(1, int((midnight - current).total_seconds()))


def _take(
    db: Session, day: str, bucket: str, trainer_id: str | None, limit: int
) -> bool:
    """버킷에 한 번을 더한다. 이미 상한이면 더하지 않고 False.

    충돌한 행이 `calls < limit` 일 때만 갱신하므로, 동시에 들어온 요청 둘이 모두
    "아직 한 자리 남음" 을 보고 상한을 넘기는 일이 없다(행 잠금 안에서 판정한다).
    """
    stmt = insert(AiCallUsage).values(
        kst_date=day, bucket=bucket, trainer_id=trainer_id, calls=1
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[AiCallUsage.kst_date, AiCallUsage.bucket],
        set_={"calls": AiCallUsage.calls + 1, "updated_at": func.now()},
        where=AiCallUsage.calls < limit,
    ).returning(AiCallUsage.calls)
    return db.execute(stmt).first() is not None


def _session() -> Session:
    from app.db.session import SessionLocal

    return SessionLocal()


def acquire(feature: str, *, trainer_id: str | None = None) -> None:
    """모델 호출 한 번을 오늘 몫에서 잡는다. 상한이 모두 꺼져 있으면 DB 를 보지 않는다.

    트레이너 상한을 먼저 본다 — 한 계정이 다 쓴 날에 서버 전체 몫까지 깎지 않게.
    전역 상한에 걸리면 같은 트랜잭션의 트레이너 몫도 되돌린다.
    """
    per_trainer = trainer_limit() if trainer_id else 0
    per_server = global_limit()
    if per_trainer <= 0 and per_server <= 0:
        return
    day = clock.today_iso()
    db = _session()
    try:
        if per_trainer > 0 and not _take(
            db, day, trainer_bucket(trainer_id or ""), trainer_id, per_trainer
        ):
            db.rollback()
            metrics.incr("ai_calls.rejected", reason="trainer_daily", feature=feature)
            logger.info(
                "트레이너 AI 하루 상한 도달 (feature=%s, trainer_id=%s, limit=%d)",
                feature, trainer_id, per_trainer,
            )
            raise TrainerAiDailyLimitReached(seconds_until_reset())
        if per_server > 0 and not _take(db, day, GLOBAL_BUCKET, None, per_server):
            db.rollback()
            metrics.incr("ai_calls.rejected", reason="global_cap", feature=feature)
            logger.warning(
                "서버 전체 AI 하루 상한 도달 (feature=%s, limit=%d)", feature, per_server
            )
            raise AiCapacityReached(seconds_until_reset())
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
    metrics.incr("ai_calls.acquired", feature=feature)


def used_today(bucket: str, db: Session | None = None) -> int:
    """오늘(KST) 그 버킷이 쓴 횟수. 운영 확인·테스트용."""
    own = db is None
    session = db or _session()
    try:
        row = session.get(AiCallUsage, (clock.today_iso(), bucket))
        return int(row.calls) if row is not None else 0
    finally:
        if own:
            session.close()
