"""트레이너가 AI 후보 가운데 골라 회원에게 추천하는 메뉴. (#2378)

흐름은 **AI 가 후보를 내고 → 트레이너가 확정하고 → 회원은 앱 홈에서 받는다**.

  * 후보는 회원의 4주 추천 메뉴 리스트(`diet_menu_plan`, #2250)에서 고른다. 리스트는
    AI 가 최근 4주 기록(평균 섭취와 목표의 차이·자주 먹은 음식·직전 추천)을 보고 이미
    만들어 둔 것이라, **트레이너가 후보를 보고 넘겨도 AI 를 새로 부르지 않는다**.
  * 순서는 회원의 급한 태그(`needs_of` — 4주 평균이 목표에서 벗어난 것)에 맞는 메뉴가
    먼저다. 급한 태그가 없으면 채울 점이 없다고 보고 후보를 주지 않는다.
  * 트레이너가 확정한 메뉴는 회원당 한 건이다. 회원이 그 메뉴를 기록하면 즉시 해소돼
    홈에서 내려간다. 트레이너가 다시 고르거나 담당이 끝나도 내려간다.

리스트는 회원 언어로 만들어져 있다. 트레이너 조회가 자기 언어로 `get_plan` 을 부르면
언어가 바뀌었다며 회원 리스트를 새로 만들어 버리므로, 저장된 리스트의 언어를 그대로
쓴다(리스트가 아예 없을 때만 요청 언어로 한 번 만든다).
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core import clock
from app.data import diet_menu_catalog as catalog
from app.models.models import DietEntry, DietTrainerPick, TrainerClient, User
from app.services import data_consent_service
from app.services import diet_coach_inputs as inputs
from app.services import diet_menu_plan

STATUS_ACTIVE = "active"
STATUS_RESOLVED = "resolved"


class PickNotInPlan(ValueError):
    """고른 메뉴가 지금 후보 리스트에 없다."""


@dataclass(frozen=True)
class Candidate:
    menu: diet_menu_plan.PlanMenu
    #: 회원의 급한 태그를 채우는 메뉴인가 — 이유 문장이 "부족해요" 로 갈지 가른다.
    urgent: bool


@dataclass(frozen=True)
class Candidates:
    needs: list[str]
    basis_days: int
    items: list[Candidate]


def norm(name: str) -> str:
    """메뉴 이름 비교용 — 띄어쓰기·대소문자를 무시한다."""
    return diet_menu_plan.norm_name(name)


def _slot_rank(slot: str) -> int:
    return catalog.SLOTS.index(slot) if slot in catalog.SLOTS else len(catalog.SLOTS)


def _plan(db: Session, member_id: str, *, lang: str) -> diet_menu_plan.MenuPlan:
    row = diet_menu_plan._latest(db, member_id)
    return diet_menu_plan.get_plan(db, member_id, lang=row.lang if row else lang)


def candidates(
    db: Session, member_id: str, *, lang: str = "ko", exclude: set[str] = frozenset()
) -> Candidates:
    """급한 태그를 채우는 메뉴부터. 급한 태그가 없으면 빈 목록이다."""
    today = clock.today()
    profile = inputs.load_profile(db, member_id)
    start = today - timedelta(days=diet_menu_plan.PLAN_DAYS - 1)
    recent = inputs.digest(inputs.entries_between(db, member_id, start, today))
    needs = diet_menu_plan.needs_of(recent, inputs.targets_of(profile))
    if not needs:
        return Candidates(needs=[], basis_days=recent.days_logged, items=[])

    plan = _plan(db, member_id, lang=lang)
    menus = [
        m for m in plan.items if diet_menu_plan.norm_name(m.name) not in exclude
    ]
    tag_order = needs + [t for t in catalog.TAGS if t not in needs]

    def rank(m: diet_menu_plan.PlanMenu) -> tuple[int, int]:
        tag = tag_order.index(m.tag) if m.tag in tag_order else len(tag_order)
        return (tag, _slot_rank(m.slot))

    ordered = sorted(menus, key=rank)
    return Candidates(
        needs=needs,
        basis_days=recent.days_logged,
        items=[Candidate(menu=m, urgent=m.tag in needs) for m in ordered],
    )


def _eaten_since(db: Session, member_id: str, name: str, since: datetime) -> datetime | None:
    """`since` 뒤에 기록한 끼니에 그 메뉴가 들어 있으면 그 기록 시각.

    이름은 띄어쓰기·대소문자를 무시하고 **기록한 음식 이름이 메뉴 이름을 품는지**로
    본다(`닭가슴살 샐러드` ← `닭가슴살샐러드 도시락`). 거꾸로(메뉴가 음식을 품는지)는
    보지 않는다 — `현미밥 정식` 을 추천했는데 `밥` 만 적어도 먹은 것이 된다.
    """
    target = diet_menu_plan.norm_name(name)
    if not target:
        return None
    rows = db.scalars(
        select(DietEntry)
        .where(DietEntry.user_id == member_id)
        .where(DietEntry.date >= clock.to_seoul(since).date().isoformat())
        .where(DietEntry.created_at >= since)
        .order_by(DietEntry.created_at)
    ).all()
    for entry in rows:
        if any(target in diet_menu_plan.norm_name(f) for f in inputs.food_names(entry)):
            return entry.created_at
    return None


def _refresh(db: Session, pick: DietTrainerPick) -> DietTrainerPick:
    """추천 중인 메뉴를 회원이 먹었으면 해소로 돌린다(커밋한다)."""
    if pick.resolved_at is None:
        eaten = _eaten_since(db, pick.member_id, pick.name, pick.confirmed_at)
        if eaten is not None:
            pick.resolved_at = eaten
            db.commit()
    return pick


def current(db: Session, member_id: str, trainer_id: str) -> DietTrainerPick | None:
    """이 트레이너가 이 회원에게 확정한 추천. 다른 트레이너의 것은 없는 것으로 본다."""
    pick = db.scalar(select(DietTrainerPick).where(DietTrainerPick.member_id == member_id))
    if pick is None or pick.trainer_id != trainer_id:
        return None
    return _refresh(db, pick)


def status_of(pick: DietTrainerPick) -> str:
    return STATUS_RESOLVED if pick.resolved_at is not None else STATUS_ACTIVE


def confirm(
    db: Session,
    member_id: str,
    trainer_id: str,
    *,
    name: str,
    slot: str,
    lang: str = "ko",
) -> DietTrainerPick:
    """후보 하나를 확정한다. 지금 리스트에 없는 메뉴는 받지 않는다.

    트레이너가 이름을 직접 적어 추천하는 길은 일부러 두지 않았다. PT 트레이너의 일은
    운동 지도가 중심이고 끼니별 식단 추천은 거의 하지 않는다 — 메뉴를 짓는 일은 회원
    기록을 읽은 AI 가 맡고, 트레이너는 권할지만 정한다. 리스트 밖 이름을 받으면 이유
    태그·영양 추정도 없는 메뉴가 회원 홈에 뜬다.
    """
    plan = _plan(db, member_id, lang=lang)
    wanted = diet_menu_plan.norm_name(name)
    menu = next(
        (m for m in plan.items
         if m.slot == slot and diet_menu_plan.norm_name(m.name) == wanted),
        None,
    )
    if menu is None:
        raise PickNotInPlan(name)

    pick = db.scalar(select(DietTrainerPick).where(DietTrainerPick.member_id == member_id))
    if pick is None:
        pick = DietTrainerPick(id=f"dietpick-{uuid.uuid4().hex[:16]}", member_id=member_id)
        db.add(pick)
    pick.trainer_id = trainer_id
    pick.slot = menu.slot
    pick.name = menu.name
    pick.tag = menu.tag
    pick.keyword = menu.keyword
    pick.confirmed_at = clock.now()
    pick.resolved_at = None
    db.commit()
    return pick


def clear(db: Session, member_id: str, trainer_id: str) -> None:
    """담당이 끝날 때 그 트레이너의 추천을 지운다. 커밋은 부른 쪽이 한다."""
    db.execute(
        delete(DietTrainerPick)
        .where(DietTrainerPick.member_id == member_id)
        .where(DietTrainerPick.trainer_id == trainer_id)
    )


def for_member(db: Session, member_id: str) -> tuple[DietTrainerPick, str] | None:
    """회원 홈에 띄울 추천과 트레이너 이름. 해소됐거나 담당이 끝났으면 None.

    담당 해제는 `clear` 가 지우지만, 회원 쪽 해제·동의 철회처럼 다른 길로 링크가
    내려가도 새지 않도록 여기서도 살아 있는 링크를 확인한다.
    """
    pick = db.scalar(select(DietTrainerPick).where(DietTrainerPick.member_id == member_id))
    if pick is None:
        return None
    link = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == pick.trainer_id,
            TrainerClient.member_id == member_id,
        )
    )
    if link is None or not link.active or data_consent_service.blocks_access(link):
        return None
    pick = _refresh(db, pick)
    if pick.resolved_at is not None:
        return None
    trainer = db.get(User, pick.trainer_id)
    return pick, (trainer.name if trainer is not None else "")
