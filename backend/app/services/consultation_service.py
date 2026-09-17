from __future__ import annotations

import uuid
from datetime import date, datetime, timezone

from sqlalchemy import func, select, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.core.pagination import DEFAULT_PAGE
from app.models.models import (
    HealthProfile,
    ConsultationRequest,
    MemberGym,
    Notification,
    Place,
    TrainerClient,
    TrainerProfile,
    TrainerSchedule,
    User,
)
from app.schemas.consultation_api import (
    ConsultationAcceptOut,
    ConsultationCreate,
    ConsultationOut,
    ConsultationStatusFilter,
    TrainerConsultationOut,
)
from app.schemas.trainer_api import ScheduleSessionOut
from app.services import health_focus
from app.services import notification_service, trainer_service


class InvalidConsultationRequest(Exception):
    pass


class ConsultationTargetNotFound(Exception):
    pass


class DuplicatePendingConsultation(Exception):
    pass


class ConsultationNotFound(Exception):
    """내 앞으로 온 요청이 아니거나 존재하지 않음 — 라우터가 404 로 옮긴다.

    남의 요청을 403 이 아니라 404 로 돌리는 이유: 403 은 "그 id 의 요청이 존재한다"를
    알려 주어, id 를 훑는 것만으로 다른 트레이너의 상담 건수를 셀 수 있다.
    """


class ConsultationAlreadyDecided(Exception):
    """이미 승인·거절된 요청을 다시 처리하려 함 — 409."""


class ConsultationNotCancellable(Exception):
    """회원이 취소하려는 요청이 더 이상 대기 중이 아님 — 409."""


class MemberAlreadyCoached(Exception):
    """회원에게 이미 다른 트레이너의 활성 담당이 있음 — 409.

    `uq_trainer_client_active_member` partial unique index 가 DB 차원에서 막지만,
    그때는 IntegrityError 라 트레이너에게 보여 줄 말이 없다. 먼저 확인해서 이유를
    돌려준다.
    """


class ConsultationScheduleConflict(Exception):
    """승인하며 잡으려는 시간에 이미 다른 일정이 있음 — 409.

    `trainer_service.ScheduleSeriesConflict` 와 같은 모양이다 — 겹치는 세션을 들고
    다녀야 화면이 "OO님 일정과 겹쳐요" 를 그릴 수 있다.
    """

    def __init__(self, conflicts: list[ScheduleSessionOut]) -> None:
        super().__init__("겹치는 일정이 있습니다.")
        self.conflicts = conflicts


def _pending_query(member_id: str, payload: ConsultationCreate):
    """같은 트레이너에게 이미 보낸 대기 요청을 찾는 질의.

    `uq_consultation_requests_pending_trainer` 와 같은 조건이라, 이 질의가 비었는데도
    삽입이 제약에 걸리면 그건 경합이다(호출자가 다시 확인한다).
    """
    return select(ConsultationRequest).where(
        ConsultationRequest.member_id == member_id,
        ConsultationRequest.target_type == "trainer",
        ConsultationRequest.trainer_id == payload.trainer_id,
        ConsultationRequest.status == "pending",
    )


def _validate_target(db: Session, payload: ConsultationCreate) -> None:
    """상담을 받을 수 있는 트레이너인지 확인한다.

    헬스장(`Place.category == 'fitness'`)에 소속된 활성 트레이너만 대상이다 — 소속이
    없으면 승인 뒤 회원을 연결할 헬스장도 없다.
    """
    trainer = db.scalar(
        select(User)
        .join(TrainerProfile, TrainerProfile.trainer_id == User.id)
        .join(Place, Place.id == TrainerProfile.gym_id)
        .where(
            User.id == payload.trainer_id,
            User.role == "trainer",
            User.is_active.is_(True),
            Place.category == "fitness",
        )
    )
    if trainer is None:
        raise ConsultationTargetNotFound(
            "상담 가능한 트레이너를 찾을 수 없습니다."
        )


def create_consultation(
    db: Session, member_id: str, payload: ConsultationCreate
) -> ConsultationOut:
    if payload.preferred_date < clock.today():
        raise InvalidConsultationRequest("상담 희망일은 오늘 이후여야 합니다.")
    if not payload.data_sharing_consent:
        # 동의 없이 신청을 받아 두면, 트레이너가 수락하는 순간 회원이 동의한 적
        # 없는 기록이 넘어간다. (#1022)
        raise InvalidConsultationRequest(
            "식단·운동 기록 공유에 동의해야 상담을 신청할 수 있습니다."
        )

    _validate_target(db, payload)
    if db.scalar(_pending_query(member_id, payload)) is not None:
        raise DuplicatePendingConsultation("이미 대기 중인 상담 요청이 있습니다.")

    consultation = ConsultationRequest(
        id=f"consult-{uuid.uuid4().hex[:12]}",
        member_id=member_id,
        # 값은 하나뿐이지만 컬럼은 남아 있다 — 대기 중복을 막는 부분 유니크 인덱스
        # (`uq_consultation_requests_pending_trainer`)의 조건이 이 값을 본다.
        target_type="trainer",
        trainer_id=payload.trainer_id,
        exercise_goal=payload.exercise_goal,
        health_purpose_type=payload.health_purpose_type,
        health_purpose_detail=payload.health_purpose_detail,
        preferred_date=payload.preferred_date.isoformat(),
        preferred_time_slot=payload.preferred_time_slot,
        message=payload.message,
        status="pending",
        data_consent_at=_now(),
    )
    db.add(consultation)
    _notify_trainer_of_new_request(db, consultation, member_id)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if db.scalar(_pending_query(member_id, payload)) is not None:
            raise DuplicatePendingConsultation(
                "이미 대기 중인 상담 요청이 있습니다."
            ) from None
        raise
    db.refresh(consultation)
    return attach_target_names(db, [consultation])[0]


def _notify_trainer_of_new_request(
    db: Session, consultation: ConsultationRequest, member_id: str
) -> None:
    """새 상담 요청을 지정된 트레이너에게 알린다. 커밋은 호출자가 한다. (#503)

    알림이 없으면 인박스를 열어 보는 사람만 우연히 요청을 발견한다.
    """
    if consultation.trainer_id is None:
        return

    member_name = db.scalar(select(User.name).where(User.id == member_id)) or "회원"
    notification_service.queue_for_trainer(
        db,
        trainer_id=consultation.trainer_id,
        kind=notification_service.TRAINER_CONSULTATION_KIND,
        title="새 상담 요청이 도착했어요",
        body=f"{member_name} 회원 · {consultation.preferred_date}",
    )


def _notify_trainer_of_cancel(
    db: Session, consultation: ConsultationRequest, member_id: str
) -> None:
    """회원이 취소한 요청을 지정된 트레이너에게 알린다. 커밋은 호출자가 한다. (#1625)

    알림이 없으면 인박스와 배지에서 요청이 이유 없이 사라진다 — 트레이너는 자신이
    이미 처리한 것인지 회원이 취소한 것인지 구분할 수 없다. 같은 성격의 다른 동작
    (담당 요청 수락·거절, 예약 취소, 상담 승인·거절)은 모두 상대에게 알린다.

    `trainer_id` 가 비어 있는 옛 `target_type='gym'` 행에는 받을 사람이 없으므로
    만들지 않는다 — [_notify_trainer_of_new_request] 와 같은 이유다.
    """
    if consultation.trainer_id is None:
        return

    member_name = db.scalar(select(User.name).where(User.id == member_id)) or "회원"
    notification_service.queue_for_trainer(
        db,
        trainer_id=consultation.trainer_id,
        kind=notification_service.TRAINER_CONSULTATION_KIND,
        title="상담 요청이 취소됐어요",
        body=f"{member_name} 회원 · {consultation.preferred_date}",
    )


def attach_target_names(db: Session, rows: list[ConsultationRequest]) -> list[ConsultationOut]:
    """상담 목록에 대상 트레이너 이름을 붙인다. (#327)

    앱 목록 카드가 이름을 렌더하므로 id 만 주면 카드마다 트레이너 상세를 다시 조회해야
    한다. 한 번에 모아 읽어 N+1 을 피한다.
    """
    trainer_ids = {r.trainer_id for r in rows if r.trainer_id}
    trainer_names: dict[str, str] = {}
    trainer_gyms: dict[str, str] = {}
    if trainer_ids:
        trainer_names = {
            u.id: u.name
            for u in db.scalars(select(User).where(User.id.in_(trainer_ids))).all()
        }
        trainer_gyms = {
            trainer_id: gym_name or profile_name or ""
            for trainer_id, gym_name, profile_name in db.execute(
                select(TrainerProfile.trainer_id, Place.name, TrainerProfile.gym_name)
                .outerjoin(Place, Place.id == TrainerProfile.gym_id)
                .where(TrainerProfile.trainer_id.in_(trainer_ids))
            ).all()
        }

    out: list[ConsultationOut] = []
    for row in rows:
        item = ConsultationOut.model_validate(row)
        # 트레이너가 지워졌으면 이름은 None 으로 남는다 — 앱이 폴백 문구를 쓴다.
        item.trainer_name = trainer_names.get(row.trainer_id or "")
        item.trainer_gym_name = trainer_gyms.get(row.trainer_id or "") or None
        out.append(item)
    return out


def cancel_my_consultation(
    db: Session, member_id: str, consultation_id: str
) -> ConsultationOut:
    row = db.scalar(
        select(ConsultationRequest).where(
            ConsultationRequest.id == consultation_id,
            ConsultationRequest.member_id == member_id,
        )
    )
    if row is None:
        raise ConsultationNotFound()
    if row.status != "pending":
        raise ConsultationNotCancellable()
    row.status = "cancelled"
    row.decided_at = _now()
    row.decision_note = None
    _notify_trainer_of_cancel(db, row, member_id)
    db.commit()
    db.refresh(row)
    return attach_target_names(db, [row])[0]


def _apply_cursor(query, before: datetime | None, before_id: str | None):
    """`(created_at, id)` 복합 커서를 건다. (#980)

    시각만으로 자르지 않는 이유는 알림과 같다 — 같은 `created_at` 이 여러 건이면 그
    경계에서 요청이 빠지거나 겹친다. 상담은 회원이 여러 트레이너에게 연달아 보내는
    일이 있어 초 단위 동시각이 실제로 나온다.
    """
    if before is None:
        return query
    if before_id is not None:
        return query.where(
            tuple_(ConsultationRequest.created_at, ConsultationRequest.id)
            < (before, before_id)
        )
    return query.where(ConsultationRequest.created_at < before)


def list_my_consultations(
    db: Session,
    member_id: str,
    *,
    limit: int = DEFAULT_PAGE,
    before: datetime | None = None,
    before_id: str | None = None,
) -> list[ConsultationOut]:
    """내가 보낸 상담 요청 한 쪽(최신순). 기본 50건, 다음 쪽은 커서로 이어 받는다."""
    query = _apply_cursor(
        select(ConsultationRequest).where(
            ConsultationRequest.member_id == member_id
        ),
        before,
        before_id,
    )
    rows = list(
        db.scalars(
            query.order_by(
                ConsultationRequest.created_at.desc(),
                ConsultationRequest.id.desc(),
            ).limit(limit)
        ).all()
    )
    return attach_target_names(db, rows)


def get_my_consultation(
    db: Session, member_id: str, consultation_id: str
) -> ConsultationOut | None:
    row = db.scalar(
        select(ConsultationRequest).where(
            ConsultationRequest.id == consultation_id,
            ConsultationRequest.member_id == member_id,
        )
    )
    if row is None:
        return None
    return attach_target_names(db, [row])[0]


# ---------------------------------------------------------------------------
# 트레이너 측 — 인박스 조회와 승인·거절. (#467)
#
# 여기가 회원↔트레이너 관계가 성립하는 유일한 지점이다. 이전에는 `TrainerClient`
# 링크를 만드는 코드가 시드 스크립트뿐이어서, 실서비스에서 신규 회원이 트레이너를
# 가질 방법이 없었다.
# ---------------------------------------------------------------------------

#: 요청의 운동 목표 → 담당 링크의 초기 코칭 목표 문구. 트레이너가 나중에 고쳐 쓰는
#: 출발점이며, 비워 두면 로스터 카드의 목표 줄이 빈칸으로 뜬다.
#:
#: 여덟 목표는 건강 목표 문구를 **그대로** 쓴다 — 표를 따로 들고 있다가 `fitness`
#: 하나가 `체력 증진` 으로 남아 같은 값을 세 화면이 세 이름으로 불렀다(#1992).
#: 여기 더 적는 둘은 건강 목표에 대응이 없어 이 화면만 부르는 이름이다.
_GOAL_LABELS: dict[str, str] = {
    **health_focus.EXERCISE_GOAL_FOCUS,
    # 없앤 선택지지만 이미 저장된 요청에 남아 있다.
    "health": "건강 관리",
    "other": "상담 후 설정",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def trainer_gym_id(db: Session, trainer_id: str) -> str | None:
    """트레이너의 소속 헬스장 id. 소속이 없으면 None."""
    return db.scalar(
        select(TrainerProfile.gym_id).where(
            TrainerProfile.trainer_id == trainer_id
        )
    )


def _inbox_scope(trainer_id: str):
    """트레이너가 볼 수 있는 요청의 범위 — 나를 지정한 요청뿐이다.

    예전에는 "내 소속 헬스장으로 온 요청" 갈래가 하나 더 있어, 회원이 헬스장에 보낸
    문의가 소속 트레이너 전원의 인박스에 동시에 떴다. 이제 요청은 트레이너 한 사람을
    지정해서만 만들어지므로 갈래가 하나다. 남아 있는 옛 `target_type='gym'` 행은
    `trainer_id` 가 비어 있어 이 조건에 걸리지 않는다.
    """
    return ConsultationRequest.trainer_id == trainer_id


def _to_trainer_out(
    db: Session, rows: list[ConsultationRequest]
) -> list[TrainerConsultationOut]:
    """대상 이름 + 요청한 회원 이름을 붙여 인박스 카드 형태로 만든다.

    이름은 대상별로 한 번씩 모아 읽는다([attach_target_names] 와 같은 이유) — 카드마다
    회원을 다시 조회하면 목록 길이만큼 쿼리가 늘어난다.
    """
    if not rows:
        return []
    base = {item.id: item for item in attach_target_names(db, rows)}
    member_ids = {r.member_id for r in rows}
    member_names = {
        u.id: u.name
        for u in db.scalars(select(User).where(User.id.in_(member_ids))).all()
    }
    out: list[TrainerConsultationOut] = []
    for row in rows:
        # `decision_note` / `decided_at` 은 회원용 스키마가 이미 갖고 있어
        # model_dump() 에 실려 온다(#473). 여기서 다시 넘기면 중복 인자다.
        item = TrainerConsultationOut(
            **base[row.id].model_dump(),
            member_name=member_names.get(row.member_id),
            decided_by=row.decided_by,
        )
        out.append(item)
    return out


def list_for_trainer(
    db: Session,
    trainer_id: str,
    status: ConsultationStatusFilter = "pending",
    *,
    limit: int = DEFAULT_PAGE,
    before: datetime | None = None,
    before_id: str | None = None,
) -> list[TrainerConsultationOut]:
    """트레이너 인박스 한 쪽. 기본은 미처리(`pending`)만, 최신 요청이 위로 온다.

    기본값인 `pending` 은 처리하는 만큼 줄어 실무상 짧지만, `status=all` 은 그
    트레이너에게 들어온 요청 **전체**라 담당 기간에 비례해 자란다. 목록 쪽 나눔과
    무관하게 배지 수는 [pending_count_for_trainer] 가 DB 에서 따로 센다. (#980)
    """
    query = _apply_cursor(
        select(ConsultationRequest).where(_inbox_scope(trainer_id)),
        before,
        before_id,
    )
    if status != "all":
        query = query.where(ConsultationRequest.status == status)
    rows = list(
        db.scalars(
            query.order_by(
                ConsultationRequest.created_at.desc(),
                ConsultationRequest.id.desc(),
            ).limit(limit)
        ).all()
    )
    return _to_trainer_out(db, rows)


def pending_count_for_trainer(db: Session, trainer_id: str) -> int:
    """미처리 요청 수 — 인박스 배지용. 목록 전체를 만들지 않는다.

    배지는 페이지네이션과 무관하게 전체를 세므로 행을 가져와 파이썬에서 세면 곧
    전체 행 로드가 된다. 화면이 주기적으로 다시 읽는 경로라 DB 집계로 받는다 —
    트레이너 알림 미읽음 수(`app/api/v1/trainer.py`)와 같은 형태다. (#1629)
    """
    return (
        db.scalar(
            select(func.count())
            .select_from(ConsultationRequest)
            .where(
                _inbox_scope(trainer_id),
                ConsultationRequest.status == "pending",
            )
        )
        or 0
    )


def _require_inbox_row(
    db: Session, trainer_id: str, consultation_id: str, *, lock: bool = False
) -> ConsultationRequest:
    """인박스 범위 안의 상담 행. 없거나 남의 것이면 [ConsultationNotFound].

    [lock] 은 결정 경로 전용이다. 같은 요청에 승인 요청이 겹쳐 들어오면 잠금 없이는
    둘 다 `pending` 검사를 통과한 뒤 링크 삽입에서 제약에 걸린다(리뷰). 행을 잠가
    직렬화한다.
    """
    query = select(ConsultationRequest).where(
        ConsultationRequest.id == consultation_id,
        _inbox_scope(trainer_id),
    )
    if lock:
        query = query.with_for_update()
    row = db.scalar(query)
    if row is None:
        raise ConsultationNotFound("상담 요청을 찾을 수 없습니다.")
    return row


def _commit_decision(db: Session) -> None:
    """결정을 커밋한다. 경합으로 제약에 걸리면 '이미 처리됨'으로 수렴시킨다.

    행 잠금이 같은 상담의 동시 처리는 막지만, 회원이 **다른 상담 경로로** 동시에
    담당이 되는 경우까지는 막지 못한다 — 그때는 `uq_trainer_client_active_member`
    가 잡는다. IntegrityError 를 그대로 두면 앱에는 500 으로 보이고, 앱은 409 본문의
    문구를 보여 주도록 만들어져 있어 이유가 사라진다.
    """
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ConsultationAlreadyDecided("이미 처리된 상담 요청입니다.") from exc


def _notify(db: Session, *, user_id: str, title: str, body: str) -> None:
    """회원에게 처리 결과 알림을 남긴다(커밋은 호출자가 한다).

    승인·거절은 회원이 앱을 열어 보기 전에는 알 수 없는 변화라 알림이 결과 전달의
    유일한 경로다. 푸시 발송은 이번 범위 밖이며 여기서는 행만 남긴다.

    category 를 `system` 이 아니라 상담 결과로 밝히는 이유: 앱이 이 값으로 갈 곳을
    정한다. `system` 은 목적지가 없어, 승인 알림을 눌러도 담당 트레이너 화면으로
    갈 수 없었다(#636).

    수신 설정을 보지 않는 것은 의도다 — 내가 보낸 요청의 처리 결과는 끌 수 있는
    알림이 아니다. 그래서 `notification_service.queue` 가 아니라 여기서 직접 만든다.
    """
    db.add(
        Notification(
            id=f"noti-{uuid.uuid4().hex[:12]}",
            user_id=user_id,
            title=title,
            body=body,
            category=notification_service.MEMBER_CONSULTATION,
            read=False,
        )
    )


def link_member_gym(db: Session, member_id: str, gym_id: str | None) -> None:
    """담당이 생긴 회원을 트레이너의 헬스장에 연결한다(커밋 없음).

    이미 다른 헬스장에 연결돼 있으면 **건드리지 않는다** — 회원이 직접 고른 '내
    헬스장'을 승인이 말없이 옮기면 MY 탭이 이유 없이 바뀐다.

    담당이 생기는 경로가 둘이라(상담 수락, 트레이너의 담당 요청 수락 #919) 공개
    함수다. 규칙을 복사하면 한쪽만 고쳐지는 날이 온다.
    """
    if gym_id is None:
        return
    if db.get(MemberGym, member_id) is not None:
        return
    if db.scalar(select(Place.id).where(Place.id == gym_id)) is None:
        return
    db.add(MemberGym(member_id=member_id, gym_id=gym_id))


def _fill_member_focus_from_consultation(
    db: Session, member_id: str, exercise_goal: str | None
) -> None:
    """상담에서 고른 운동 목표를 회원 건강 목표로 옮긴다(커밋 없음). (#1818)

    트레이너 화면의 회원 목표는 회원 건강 목표를 읽는다. 상담으로 처음 연결된
    회원이 아직 목표를 고르지 않았으면, 방금 상담에 적은 목표가 가장 가까운 값이다.
    이미 고른 목표가 있으면 건드리지 않는다.
    """
    focus = health_focus.EXERCISE_GOAL_FOCUS.get(exercise_goal or "")
    if focus is None:
        return
    profile = db.scalar(select(HealthProfile).where(HealthProfile.user_id == member_id))
    if profile is None:
        profile = HealthProfile(user_id=member_id)
        db.add(profile)
    profile.conditions = health_focus.with_focus_if_missing(profile.conditions, focus)


def attach_member_to_trainer(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    goal: str = "",
    consented_at: datetime | None = None,
) -> None:
    """담당 링크를 만든다(커밋 없음). 활성 담당이 없는 회원에게만 부른다.

    과거에 담당했다가 휴면으로 내려간 링크가 있으면 **되살린다** — 새 행을 넣으면
    (trainer, member) 유일 제약에 걸리고, 지난 루틴·채팅 이력도 갈라진다.

    담당이 생기는 경로가 둘이라(상담 수락, 트레이너의 담당 요청 수락 #919) 공개
    함수다. 되살리기 규칙을 양쪽이 각자 들고 있으면 한쪽만 고쳐진다.
    """
    dormant = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    )
    if dormant is not None:
        dormant.active = True
        # 다시 담당이 되는 것도 새 연결이다 — 그때의 동의로 갱신한다. (#1022)
        if consented_at is not None:
            dormant.data_consent_at = consented_at
        return

    last_order = db.scalar(
        select(func.max(TrainerClient.sort_order)).where(
            TrainerClient.trainer_id == trainer_id
        )
    )
    db.add(
        TrainerClient(
            id=f"tc-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            goal=goal,
            active=True,
            data_consent_at=consented_at,
            sort_order=(last_order or 0) + 1,
        )
    )


def accept(
    db: Session,
    trainer_id: str,
    consultation_id: str,
    note: str | None = None,
    *,
    schedule_date: date | None = None,
    schedule_time: str | None = None,
    schedule_type: str | None = None,
    duration_minutes: int | None = None,
) -> ConsultationAcceptOut:
    """상담을 승인하고 담당 링크를 만든다.

    `pending` 에서만 진행한다. 회원에게 이미 다른 트레이너의 활성 담당이 있으면
    [MemberAlreadyCoached] — 회원당 활성 담당은 1명이라는 불변식
    (`uq_trainer_client_active_member`)을 IntegrityError 로 만나기 전에 막는다.

    상태 전이·링크 생성·헬스장 연결·알림을 **한 트랜잭션**으로 커밋한다. 나눠 커밋하면
    승인 표시만 남고 담당은 안 생긴 반쪽 상태가 생긴다.
    """
    row = _require_inbox_row(db, trainer_id, consultation_id, lock=True)
    if row.status != "pending":
        raise ConsultationAlreadyDecided("이미 처리된 상담 요청입니다.")

    existing = db.scalar(
        select(TrainerClient).where(
            TrainerClient.member_id == row.member_id,
            TrainerClient.active.is_(True),
        )
    )
    if existing is not None and existing.trainer_id != trainer_id:
        raise MemberAlreadyCoached("이미 다른 트레이너가 담당 중인 회원입니다.")

    # 담당 링크를 만들기 전에 겹침부터 본다 — 겹치면 아무것도 만들지 않는다
    # (링크도, 헬스장 연결도, 스케줄도). 화면이 승인 버튼 옆에 짚어 줄 수 있도록
    # 겹친 세션을 들고 다닌다.
    if schedule_date is not None:
        conflicts = trainer_service.conflicting_sessions(
            db, trainer_id, [(schedule_date.isoformat(), schedule_time or "00:00")]
        )
        if conflicts:
            raise ConsultationScheduleConflict(conflicts)

    if existing is None:
        attach_member_to_trainer(
            db,
            trainer_id,
            row.member_id,
            goal=_GOAL_LABELS.get(row.exercise_goal, ""),
            # 회원은 신청할 때 동의했고 연결은 지금 만들어진다 — 그 시각을
            # 옮겨 적는다. (#1022)
            consented_at=row.data_consent_at,
        )
        _fill_member_focus_from_consultation(db, row.member_id, row.exercise_goal)
    # 링크 생성 여부와는 별개 조건이다 — 이미 이 트레이너의 담당인 회원이 상담을
    # 새로 넣고 승인받는 경우에도 헬스장 연결은 이뤄져야 한다(리뷰).
    # 이미 연결된 회원에게는 no-op 이라 중복 호출이 무해하다.
    link_member_gym(db, row.member_id, trainer_gym_id(db, trainer_id))

    row.status = "accepted"
    row.decided_by = trainer_id
    row.decided_at = _now()
    row.decision_note = note

    # The schedule inbox sends all four values together (validated by the
    # request schema).  Keep this in the same transaction as the decision:
    # a request must never disappear from the inbox without its promised
    # calendar entry being created.
    schedule_id: str | None = None
    if schedule_date is not None:
        schedule_id = f"sched-{uuid.uuid4().hex[:12]}"
        db.add(
            TrainerSchedule(
                id=schedule_id,
                trainer_id=trainer_id,
                member_id=row.member_id,
                date=schedule_date.isoformat(),
                time=schedule_time or "00:00",
                client_name=db.scalar(
                    select(User.name).where(User.id == row.member_id)
                )
                or "신규 회원",
                type=schedule_type or "상담",
                duration_minutes=duration_minutes or 30,
                status="예정",
                note=row.message or "",
                program_json="[]",
                sort_order=0,
            )
        )

    trainer_name = db.scalar(select(User.name).where(User.id == trainer_id))
    _notify(
        db,
        user_id=row.member_id,
        title="상담 요청이 승인되었어요",
        body=(
            f"{trainer_name or '트레이너'} 트레이너가 담당으로 연결되었어요."
            if note is None
            else f"{trainer_name or '트레이너'} 트레이너가 담당으로 연결되었어요. {note}"
        ),
    )
    _commit_decision(db)
    db.refresh(row)
    consultation = _to_trainer_out(db, [row])[0]
    return ConsultationAcceptOut(
        **consultation.model_dump(),
        client_connected=True,
        schedule_created=schedule_id is not None,
        schedule_id=schedule_id,
    )


def reject(
    db: Session, trainer_id: str, consultation_id: str, note: str | None = None
) -> TrainerConsultationOut:
    """상담을 거절한다. 담당 링크는 만들지 않고 사유만 남긴다."""
    row = _require_inbox_row(db, trainer_id, consultation_id)
    if row.status != "pending":
        raise ConsultationAlreadyDecided("이미 처리된 상담 요청입니다.")

    row.status = "rejected"
    row.decided_by = trainer_id
    row.decided_at = _now()
    row.decision_note = note

    _notify(
        db,
        user_id=row.member_id,
        title="상담 요청이 반려되었어요",
        body=note or "다른 트레이너에게 상담을 요청해 보세요.",
    )
    _commit_decision(db)
    db.refresh(row)
    return _to_trainer_out(db, [row])[0]
