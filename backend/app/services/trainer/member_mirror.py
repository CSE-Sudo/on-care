"""트레이너 도메인 — 회원측 미러(내 담당 코치 / 받은 루틴 / 채팅 / 내 세션)."""
from __future__ import annotations

import json
from datetime import date

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import (
    ChatMessage, HealthProfile,
    TrainerClient, TrainerProfile, TrainerRoutine, TrainerSchedule,
    User,
)
from app.schemas.trainer_api import (
    MemberCoachOut,
    RoutineOut, ScheduleSessionOut, TrainerGymOut, UpcomingRoutinesOut,
)
from app.services import health_focus
from app.services import (
    auto_routine_service,
    data_consent_service,
    diet_coach_inputs,
    diet_trainer_pick,
    points_coupon_service,
    routine_advice,
)
from app.services.trainer._common import (
    DELIVERY_ROUTINE_ONLY,
    ROUTINE_APPROVED,
    RoutineDay,
    RoutineDayInFuture,
    SCHEDULE_DONE,
    _active_link,
    _cancel_sessions_on_detach,
    _done_pt_numbers,
    _schedule_out,
    get_member_trainer_id,
    member_routine_days,
    routine_sent_on,
)
from app.services.trainer.routines import (
    build_routines,
)


# ---- 회원측 미러 (내 담당 코치 / 받은 루틴 / 채팅 / 내 세션) ----


def _deactivate_coach_links(db: Session, member_id: str) -> bool:
    """활성 담당 링크를 전부 휴면으로 내린다(커밋 없음). 내린 게 있으면 True.

    링크 행을 지우지 않고 `active=False` 로 내린다 — 지난 코칭 기록(루틴·채팅·일정)이
    링크를 참조하므로 삭제하면 이력이 끊긴다. 비활성 링크는 `_active_link` 가 제외해
    이후 조회는 '담당 없음'으로 동작한다.

    **전부** 내리는 이유: partial unique index 가 회원당 1건을 강제하지만, 정합성이
    깨져 여러 건이 남은 경우 첫 건만 끄면 get_member_trainer_id() 가 계속 다른 링크를
    반환해 "해제했는데 그대로"가 된다(리뷰 지적).

    담당이 끝나면 PT 재등록 쿠폰을 취소하고 포인트를 돌려준다(#1787) — 헬스장
    해제·트레이너만 해제 두 경로가 모두 여기를 지난다.
    """
    links = db.scalars(
        select(TrainerClient).where(
            TrainerClient.member_id == member_id,
            TrainerClient.active.is_(True),
        )
    ).all()
    for link in links:
        link.active = False
        # 담당 해제 = 데이터 공유 동의 철회(#1631).
        data_consent_service.revoke(link, by=data_consent_service.BY_MEMBER)
        # 아직 시작하지 않은 PT 도 함께 거둔다(#2589). 회원이 스스로 끊었으니
        # 회원에게 따로 알리지 않고, 트레이너에게는 해제 알림이 취소 수를 함께
        # 전한다(`member_departure.notify_trainer`).
        _cancel_sessions_on_detach(
            db, link.trainer_id, link.member_id, source="member"
        )
        # 그 트레이너가 확정해 둔 식단 추천도 내린다 — 트레이너가 해제할 때
        # (`remove_client`)와 같다. 남겨 두면 같은 트레이너와 다시 연결될 때 끊기
        # 전의 추천이 회원 홈에 되살아난다(#2442).
        diet_trainer_pick.clear(db, member_id, link.trainer_id)
    if links:
        points_coupon_service.cancel_renewal_coupons(db, member_id)
        # 끊은 트레이너의 메시지로 만든 식단 AI 조언·추천 메뉴를 내려놓는다(#1631).
        diet_coach_inputs.forget_trainer_notes(db, member_id)
    return bool(links)


def disconnect_member_gym(db: Session, member_id: str) -> bool:
    """회원이 헬스장 연결을 끊는다 — 담당 트레이너도 함께 끊긴다.

    떠난 헬스장의 트레이너를 담당으로 남겨 둘 수는 없다. 앱의 mock 도 같은 규칙이고
    (`MockGymRepository.disconnectMyGym`), MY 탭의 헬스장 휴지통이 이 경로다.
    둘 중 하나라도 끊었으면 True.

    두 해제를 **한 트랜잭션**으로 커밋한다. 각자 커밋하면 뒤 단계가 실패했을 때
    헬스장만 사라지고 담당은 살아 있는 반쪽 상태가 남는다.
    """
    from app.services import gym_service

    unlinked_gym = gym_service.unlink_member_gym(db, member_id)
    unlinked_trainer = _deactivate_coach_links(db, member_id)
    db.commit()
    return unlinked_gym or unlinked_trainer


def disconnect_member_coach(db: Session, member_id: str) -> bool:
    """회원이 담당 트레이너 연결을 끊는다 — 헬스장 연결은 그대로 둔다.

    끊었으면 True, 원래 없었으면 False.

    회원 일방으로 끊을 수 있게 두는 이유: 앱의 MY 탭이 이미 해제 버튼을 제공하고,
    트레이너 승인을 기다리게 하면 회원이 관계를 벗어날 방법이 없어진다. 트레이너
    로스터에서는 즉시 사라진다.
    """
    deactivated = _deactivate_coach_links(db, member_id)
    db.commit()
    return deactivated


def _member_gym_out(db: Session, member_id: str, profile: TrainerProfile) -> TrainerGymOut:
    """코치 요약에 실을 헬스장 — **회원 링크가 진실**이고, 트레이너 소속은 폴백이다.

    회원이 트레이너와 다른 헬스장에 연결돼 있을 수 있으므로(트레이너 이적 등) 먼저
    회원 링크를 본다. 링크가 없는 회원은 마이그레이션 백필 전 데이터이거나 담당만
    있고 헬스장 연결이 아직 없는 경우라, 예전처럼 트레이너 소속을 보여 준다 —
    갑자기 빈 카드가 되는 것보다 낫다.
    """
    from app.services import gym_service

    gym = gym_service.get_member_gym(db, member_id)
    if gym is not None:
        return TrainerGymOut(
            id=gym.id,
            name=gym.name,
            address=gym.address,
            # TrainerGymOut.hours 는 한 줄이다. 카드가 평일 영업시간을 보여 주므로
            # 주말 시간까지 합치지 않는다(트레이너 프로필의 gym_hours 와 같은 값).
            hours=gym.weekday_hours or "",
            phone=gym.phone or "",
        )
    return TrainerGymOut(
        id=profile.gym_id,
        name=profile.gym_name, address=profile.gym_address,
        hours=profile.gym_hours, phone=profile.gym_phone,
    )


def build_member_coach(db: Session, member_id: str) -> MemberCoachOut | None:
    """회원의 '내 담당 코치' 요약. 활성 담당이 없으면 None(라우터 404)."""
    link = _active_link(db, member_id)
    if link is None:
        return None
    trainer = db.get(User, link.trainer_id)
    profile = db.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == link.trainer_id)
    )
    if trainer is None or profile is None:
        return None
    return MemberCoachOut(
        trainer_id=trainer.id,
        name=trainer.name,
        specialty=profile.specialty,
        career=f"{profile.career_years}년",
        intro=profile.intro,
        gym=_member_gym_out(db, member_id, profile),
        # 트레이너가 따로 적던 문장이 아니라 회원이 고른 건강 목표다(#1818).
        goal=health_focus.focus_label(
            db.scalar(
                select(HealthProfile.conditions).where(
                    HealthProfile.user_id == member_id
                )
            )
        ),
    )


def advice_routine_days(db: Session, member_id: str, period: str) -> list[RoutineDay]:
    """운동 AI 맞춤 조언이 읽는 추천 개인운동 — 기간에 맞는 날들. (#2162)

    회원 앱(`/exercise/advice`)과 트레이너웹이 이 함수 하나를 함께 쓴다 — 읽는
    구간이 갈리면 같은 회원의 같은 기간을 두고 두 화면이 다른 말을 한다.

    담당이 없는 회원의 오늘 AI 추천은 운동 탭을 열 때 만들어진다. 조언이 먼저
    불리면 오늘 칸이 비어 "추천이 없는 회원" 으로 읽히므로 여기서도 준비한다.
    """
    today = clock.today()
    if get_member_trainer_id(db, member_id) is None:
        auto_routine_service.ensure_auto_routines(db, member_id)
    return member_routine_days(
        db, member_id, routine_advice.fetch_start(period, today), today
    )


def build_member_routines(
    db: Session, member_id: str, day: date | None = None
) -> list[RoutineOut]:
    """회원이 받은 개인운동 — [day](기본 오늘)에 걸려 있던 목록과 그날 완료.

    담당 트레이너가 있으면 그 트레이너가 배정한 것(승인된 것만, #790).
    담당이 없으면 AI 가 안전 범위에서 직접 준비한 것(#782) — 예전에는 이 경우
    늘 빈 목록이라, 트레이너 없는 회원은 운동 탭에서 받을 것이 아무것도 없었다.

    지난 날짜(#2161)는 **지금의 담당 기준**으로 읽는다 — 그 트레이너가 그날 걸어
    둔 목록이다. 하루치 AI 추천을 준비하는 일은 오늘에만 한다. 지난 날을 열었다고
    그날 추천을 새로 만들면, 회원이 받은 적 없는 목록이 "그날 안 한 운동" 으로
    보인다. 아직 오지 않은 날은 [RoutineDayInFuture] — 체크할 목록이 없다.
    """
    today = clock.today()
    day = day or today
    if day > today:
        raise RoutineDayInFuture("아직 오지 않은 날이에요.")
    trainer_id = get_member_trainer_id(db, member_id)
    if trainer_id is None:
        if day == today:
            auto_routine_service.ensure_auto_routines(db, member_id)
        return build_routines(db, member_id, None, for_member=True, day=day)
    return build_routines(db, member_id, trainer_id, for_member=True, day=day)


def build_member_upcoming_routines(
    db: Session, member_id: str
) -> UpcomingRoutinesOut | None:
    """아직 시작하지 않은 개인운동 한 묶음 — 없으면 None. (#3106)

    지금 담당이 보낸 승인된 `개인운동만` 중 시작일이 오늘보다 뒤인 것이다. 시작일이
    되면 그날 목록([build_member_routines])으로 넘어가 여기서는 빠진다. 다른
    트레이너가 보낸 것·아직 보내지 않은 것·거절된 후보는 승인된 지금 담당의 배정이
    아니라 들지 않는다.

    시작 전에 다른 것으로 다시 보내 하루도 걸리지 못하는 줄(`ended_on <=
    active_from`, #2656)은 뺀다. 그래도 둘 이상이면 가장 최근에 보낸 묶음이다.
    """
    trainer_id = get_member_trainer_id(db, member_id)
    if trainer_id is None:
        return None
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == ROUTINE_APPROVED,
            TrainerRoutine.delivery_kind == DELIVERY_ROUTINE_ONLY,
            TrainerRoutine.active_from > clock.today().isoformat(),
            or_(
                TrainerRoutine.ended_on.is_(None),
                TrainerRoutine.ended_on > TrainerRoutine.active_from,
            ),
        )
        .order_by(TrainerRoutine.created_at.desc(), TrainerRoutine.sort_order.desc())
    ).all()
    if not rows:
        return None
    newest = rows[0]
    group = sorted(
        (r for r in rows if r.active_from == newest.active_from),
        key=lambda r: (r.sort_order, r.created_at),
    )
    return UpcomingRoutinesOut(
        starts_on=date.fromisoformat(newest.active_from),
        sent_on=routine_sent_on(newest),
        names=[name for r in group for name in _exercise_names(r)],
    )


def _exercise_names(row: TrainerRoutine) -> list[str]:
    """배정 한 줄에 든 운동 이름. 세션 하나로 보낸 묶음은 줄 이름이 묶음 이름이라
    (`이번 주 개인운동`) 실린 운동에서 읽는다. 읽을 수 없으면 줄 이름이다."""
    try:
        items = json.loads(row.exercises_json or "[]")
    except ValueError:
        items = []
    names = [
        str(e.get("name")).strip()
        for e in items
        if isinstance(e, dict) and str(e.get("name") or "").strip()
    ]
    return names or [row.name]


#: 회원 세션 목록 상한 — 시간이 지나며 누적되는 PT 세션을 최근 것 위주로 잘라 응답 크기를 묶는다.
_MEMBER_SESSIONS_LIMIT = 100


def build_member_sessions(db: Session, member_id: str) -> list[ScheduleSessionOut]:
    """회원의 PT 세션(현재 활성 담당 트레이너의 스케줄에서 매칭된 것), 최신순(최근 100건).

    routines 와 동일하게 **활성 트레이너로 스코프**한다 — member_id 로만 조회하면 코치
    재배정 후에도 이전 트레이너가 만든 세션이 계속 보인다(stale). 활성 담당이 없으면 빈 목록.
    """
    trainer_id = get_member_trainer_id(db, member_id)
    if trainer_id is None:
        return []
    rows = db.scalars(
        select(TrainerSchedule)
        .where(
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.trainer_id == trainer_id,
        )
        .order_by(TrainerSchedule.date.desc(), TrainerSchedule.time.desc())
        .limit(_MEMBER_SESSIONS_LIMIT)
    ).all()
    numbers = _done_pt_numbers(db, member_id, trainer_id)
    return [_member_schedule_out(s, numbers.get(s.id)) for s in rows]


def _member_schedule_out(
    s: TrainerSchedule, session_number: int | None = None
) -> ScheduleSessionOut:
    """회원에게 내보내는 세션 — `note` 는 **완료된 PT** 것만 싣는다(#2515).

    `note` 한 칸이 PT 일정에서는 회원에게 보내는 트레이너 피드백이고, 상담 일정에서는
    트레이너만 보는 상담 기록(메모)이다. 트레이너 응답(`_schedule_out`)을 그대로 쓰면
    예정 PT 에 미리 적어 둔 글과 상담 기록까지 회원에게 간다. 회원 앱도 완료 PT 에서만
    그리므로, 그 밖의 `note` 는 여기서 비운다.
    """
    out = _schedule_out(s)
    if s.status != SCHEDULE_DONE or s.type == "상담":
        out.note = ""
    # 상담 요청 내용은 트레이너 카드용이다 — 회원은 `내 상담 요청` 에서 본다(#2584).
    out.consultation = None
    out.session_number = session_number
    return out


def member_unread_count(db: Session, trainer_id: str, member_id: str) -> int:
    """회원 기준 미확인(트레이너가 보낸 read_at NULL) 메시지 수."""
    return db.scalar(
        select(func.count())
        .select_from(ChatMessage)
        .where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.sender == "trainer",
            ChatMessage.read_at.is_(None),
        )
    ) or 0
