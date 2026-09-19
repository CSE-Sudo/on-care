"""데모 트레이너의 예약 자리. (#2067)

상담 신청은 트레이너가 연 `1:1 PT` 자리를 고르는 방식이다(#1873). 그런데 시드가
트레이너·헬스장·회원만 채우고 자리를 만들지 않아, 새로 띄운 서버에서는 어느
트레이너를 골라도 "지금은 예약 가능한 상담 시간이 없어요" 만 보였다. 트레이너가
트레이너 웹에서 자리를 직접 열기 전까지는 상담을 신청할 수 없었다.

## 두 번 채운다

1. **기동할 때** — [seed_demo_slots]. 데모 트레이너마다 고를 자리를 깐다.
2. **자리 목록을 읽을 때** — [top_up_demo_slots]. 고를 자리가 하나도 없으면 같은
   규칙으로 다시 깐다.

기동할 때만 깔면 자리는 "기동한 날 기준 내일·모레" 에 묶인다. 재기동 없이 며칠
켜 둔 서버에서는 그 날짜가 지나 다시 빈다. 만료 정리(`expire_stale_requests`)와
같이 읽는 시점에 채워, 스케줄러 없이도 비지 않게 한다.

## 건드리지 않는 것

- **트레이너가 연 자리.** 고를 자리가 하나라도 있으면 아무것도 하지 않는다 — 데모
  트레이너가 트레이너 웹에서 연 자리만으로 보여 주고 싶을 때 섞이지 않는다.
- **윤재희(`trainer-yoon`).** 자리가 없는 상태(헬스장 전화 안내)도 데모에서 볼 수
  있어야 한다. 회원 앱 목업의 방침과 같다.
- **데모 트레이너가 아닌 계정.** 실제로 가입한 트레이너의 달력에 지어낸 자리를
  넣지 않는다. `SEED_DEMO_DATA` 가 꺼져 있으면 읽을 때도 채우지 않는다.
"""
from __future__ import annotations

import logging
from datetime import date, datetime, time, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.clock import SEOUL
from app.core.config import get_settings
from app.db.seed_gyms import TRAINER_IDS as GYM_TRAINER_IDS
from app.db.seed_trainer import TRAINER_ID
from app.db.session import SessionLocal
from app.models.models import TrainerReservationSlot, User
from app.services import reservation_service

logger = logging.getLogger(__name__)

#: 자리를 비워 두는 데모 트레이너. 빈 상태도 데모에서 보여야 한다.
EMPTY_DEMO_TRAINER_ID = "trainer-yoon"

#: 자리를 깔아 주는 데모 트레이너.
DEMO_SLOT_TRAINER_IDS: tuple[str, ...] = tuple(
    trainer_id
    for trainer_id in (TRAINER_ID, *GYM_TRAINER_IDS)
    if trainer_id != EMPTY_DEMO_TRAINER_ID
)

#: 한 번에 까는 자리 수. 둘이면 날짜가 다른 두 칩이 보여 "고른다" 가 읽힌다.
_SLOTS_PER_FILL = 2

#: 며칠 뒤까지 빈 시각을 찾을지. 앞쪽 자리가 잡혀 있으면 그 뒤로 민다.
_SEARCH_DAYS = 14

#: 자리 길이. 트레이너가 `1:1 PT` 자리를 열 때의 기본 길이와 같다.
_DURATION_MINUTES = 60

#: 날마다 번갈아 쓰는 시작 시각(서울). 홀수 날은 낮, 짝수 날은 저녁 — 내일
#: 13:00, 모레 19:30 부터 시작한다. 실 API E2E 가 쓰는 10:00·21:00 과 겹치지
#: 않게 둔다(같은 트레이너 달력을 함께 쓴다).
_DAY_TIME = time(13, 0)
_EVENING_TIME = time(19, 30)


def _candidates(today: date) -> list[datetime]:
    """내일부터 [_SEARCH_DAYS] 일 뒤까지, 하루 하나씩 번갈아 고른 시각."""
    return [
        datetime.combine(
            today + timedelta(days=offset),
            _DAY_TIME if offset % 2 else _EVENING_TIME,
            tzinfo=SEOUL,
        )
        for offset in range(1, _SEARCH_DAYS + 1)
    ]


def _slot_id(trainer_id: str, starts_at: datetime) -> str:
    """같은 트레이너·같은 시각이면 같은 id.

    읽을 때 채우므로 두 요청이 동시에 채울 수 있다. id 가 정해져 있으면 둘째 삽입이
    기본 키에 걸려 조용히 빠진다(`ON CONFLICT DO NOTHING`) — 같은 시각에 자리가
    두 개 생기지 않는다.
    """
    return f"slot-demo-{trainer_id}-{starts_at.astimezone(SEOUL):%Y%m%d%H%M}"


def top_up_demo_slots(
    db: Session,
    trainer_id: str,
    *,
    after: datetime,
    now: datetime | None = None,
) -> int:
    """데모 트레이너에게 고를 자리가 없으면 깐다. 만든 자리 수를 돌려준다.

    **커밋하지 않는다.** 읽는 쪽이 만료 정리와 함께 커밋한다.

    [after] 는 고를 수 있는 자리의 시작 하한이다 — 상담 폼과 같은 기준
    (`consultation_service.slot_visibility_cutoff`)을 넘겨야 "폼에 보이는 자리가
    하나도 없을 때" 를 정확히 가린다.
    """
    if trainer_id not in DEMO_SLOT_TRAINER_IDS:
        return 0
    if not get_settings().seed_demo_data:
        return 0
    if reservation_service.consultation_slots(db, trainer_id, after=after):
        return 0
    # 데모 트레이너 계정이 없는 DB(탈퇴했거나 시드 전)에는 깔 곳이 없다 — 외래 키에
    # 걸려 읽기 요청 전체가 실패하는 것보다 빈 목록이 낫다.
    trainer = db.get(User, trainer_id)
    if trainer is None or trainer.role != "trainer":
        return 0

    current = now or datetime.now(timezone.utc)
    taken = set(
        db.scalars(
            select(TrainerReservationSlot.starts_at).where(
                TrainerReservationSlot.trainer_id == trainer_id,
                TrainerReservationSlot.starts_at > current,
            )
        ).all()
    )
    taken_utc = {value.astimezone(timezone.utc) for value in taken}

    created = 0
    for starts_at in _candidates(current.astimezone(SEOUL).date()):
        if created >= _SLOTS_PER_FILL:
            break
        # 앞쪽 시각에 이미 자리가 있으면(잡혔거나 닫혔으면) 그 뒤로 민다. 그 자리를
        # 다시 열지 않는다 — 누군가 잡았거나 트레이너가 닫은 자리다.
        if starts_at <= after or starts_at.astimezone(timezone.utc) in taken_utc:
            continue
        inserted = db.scalar(
            insert(TrainerReservationSlot)
            .values(
                id=_slot_id(trainer_id, starts_at),
                trainer_id=trainer_id,
                starts_at=starts_at,
                duration_minutes=_DURATION_MINUTES,
                capacity=1,
                remaining=1,
                session_type=reservation_service.CONSULTATION_SESSION_TYPE,
                is_closed=False,
            )
            .on_conflict_do_nothing(index_elements=["id"])
            # 건너뛴 삽입을 세지 않으려면 돌려받은 행으로 센다 — 드라이버가
            # `ON CONFLICT` 문의 `rowcount` 를 -1 로 주는 경우가 있어 그 값으로
            # 세면 멈추지 않고 후보를 전부 깐다.
            .returning(TrainerReservationSlot.id)
        )
        if inserted is not None:
            created += 1
    return created


def seed_demo_slots() -> None:
    """기동할 때 데모 트레이너마다 고를 자리를 깐다(멱등).

    이미 고를 자리가 있는 트레이너는 건너뛴다 — 재기동할 때마다 쌓이지 않는다.
    """
    # 순환 import 를 피해 안에서 부른다 — 상담 서비스가 이 모듈을 쓴다.
    from app.services.consultation_service import slot_visibility_cutoff

    db: Session = SessionLocal()
    try:
        now = datetime.now(timezone.utc)
        created = sum(
            top_up_demo_slots(
                db, trainer_id, after=slot_visibility_cutoff(now), now=now
            )
            for trainer_id in DEMO_SLOT_TRAINER_IDS
        )
        # 동시 기동 경쟁은 `ON CONFLICT DO NOTHING` 이 이미 흡수했다. 여기서 나는
        # 오류는 진짜 오류라 다른 시드처럼 기동을 멈춘다.
        db.commit()
        if created:
            logger.info("데모 트레이너 예약 자리 %d개를 깔았습니다.", created)
    finally:
        db.close()
