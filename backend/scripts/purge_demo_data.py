"""운영 DB 에 이미 심긴 데모 데이터를 지운다. (#2811)

예전에는 `SEED_DEMO_DATA` 기본값이 켜져 있어, 환경변수를 빠뜨린 채 띄운 서버가
데모 계정(김민수·담당 회원 15명)·데모 트레이너(김태오·가상 트레이너)·가상 헬스장·
데모 장소를 DB 에 심었다. 지금은 기본값이 꺼져 있고 운영에서는 켤 수도 없지만,
이미 심긴 행은 남는다. 이 스크립트가 그 행을 지운다.

지우는 대상은 `app.db.demo_ids` 가 모은 **시드 id 목록**뿐이다. 이름·이메일로
추측하지 않는다.

- 데모 사용자 행을 지우면 식단·운동·채팅·알림·포인트 등 그 사용자의 데이터는
  `users.id` 의 CASCADE 가 함께 지운다. 예약(`trainer_reservations`)만 RESTRICT 라
  먼저 지운다 — 데모 트레이너 자리에 실제 회원이 잡은 예약도 여기 포함되며,
  미리보기에 따로 센다.
- 데모 장소는 **실제 사용자가 참조하지 않을 때만** 지운다. 실제 트레이너가 소속으로
  고르거나 실제 회원이 내 헬스장으로 연결한 장소를 지우면 그 연결이 끊긴다.
  남긴 장소는 미리보기에 이유와 함께 나온다.
- 카카오에서 찾은 실재 업체 행은 대상이 아니다(`demo_ids.demo_place_ids` 참고).

자동으로 돌지 않는다. 삭제는 되돌릴 수 없어서 사람이 실행한다. 기본은 미리보기이고,
`--apply` 를 줘야 지운다.

    python -m scripts.purge_demo_data            # 지울 건수만 본다
    python -m scripts.purge_demo_data --apply    # 실제로 지운다

`DATABASE_URL` 이 가리키는 DB 에 그대로 적용된다. 먼저 DB 백업(Neon 브랜치 등)을
떠 두고, 미리보기 건수를 확인한 뒤 `--apply` 한다. 서버 설정은 `SEED_DEMO_DATA=false`
여야 한다 — 켜진 채 서버를 다시 띄우면 지운 데이터가 다시 심긴다.
"""
from __future__ import annotations

import argparse
from collections.abc import Iterable
from dataclasses import dataclass, field

from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session

from app.db.session import Base
from app.models.models import (
    MemberGym,
    Place,
    TrainerProfile,
    TrainerReservation,
    TrainerReservationSlot,
    User,
)


@dataclass
class PurgePlan:
    """지울 대상과 건수. 미리보기와 삭제가 같은 값을 쓴다."""

    user_ids: list[str]
    place_ids: list[str]
    #: 남기는 데모 장소 → 이유.
    kept_places: dict[str, str] = field(default_factory=dict)
    reservation_ids: list[str] = field(default_factory=list)
    #: 그중 실제(데모가 아닌) 회원의 예약 수.
    real_member_reservations: int = 0
    #: `users.id` 를 참조하는 표별 행 수(CASCADE·SET NULL 로 함께 바뀌는 행).
    dependent_rows: dict[str, int] = field(default_factory=dict)


def _user_fk_columns() -> Iterable[tuple[str, object]]:
    """`users.id` 를 참조하는 모든 (표 이름, 컬럼)."""
    for table in Base.metadata.sorted_tables:
        if table.name == "users":
            continue
        for column in table.columns:
            for fk in column.foreign_keys:
                if fk.column.table.name == "users":
                    yield table.name, column


def build_plan(
    db: Session, user_ids: Iterable[str], place_ids: Iterable[str]
) -> PurgePlan:
    """DB 에 실제로 있는 데모 행만 골라 계획을 세운다(아무것도 지우지 않는다)."""
    wanted_users = sorted(set(user_ids))
    present_users = list(
        db.scalars(select(User.id).where(User.id.in_(wanted_users))).all()
    )
    plan = PurgePlan(user_ids=sorted(present_users), place_ids=[])

    if present_users:
        reservations = db.execute(
            select(TrainerReservation.id, TrainerReservation.member_id)
            .join(
                TrainerReservationSlot,
                TrainerReservationSlot.id == TrainerReservation.slot_id,
            )
            .where(
                or_(
                    TrainerReservation.member_id.in_(present_users),
                    TrainerReservationSlot.trainer_id.in_(present_users),
                )
            )
        ).all()
        plan.reservation_ids = sorted(row.id for row in reservations)
        demo = set(present_users)
        plan.real_member_reservations = sum(
            1 for row in reservations if row.member_id not in demo
        )

        for table_name, column in _user_fk_columns():
            count = db.scalar(
                select(func.count()).select_from(column.table).where(
                    column.in_(present_users)
                )
            )
            if count:
                plan.dependent_rows[table_name] = (
                    plan.dependent_rows.get(table_name, 0) + count
                )

    demo_users = list(present_users)
    for place_id in sorted(set(place_ids)):
        if db.get(Place, place_id) is None:
            continue
        real_trainers = db.scalar(
            select(func.count())
            .select_from(TrainerProfile)
            .where(
                TrainerProfile.gym_id == place_id,
                TrainerProfile.trainer_id.not_in(demo_users),
            )
        )
        real_members = db.scalar(
            select(func.count())
            .select_from(MemberGym)
            .where(
                MemberGym.gym_id == place_id,
                MemberGym.member_id.not_in(demo_users),
            )
        )
        if real_trainers or real_members:
            plan.kept_places[place_id] = (
                f"실제 트레이너 소속 {real_trainers}명 · 실제 회원 연결 {real_members}명"
            )
            continue
        plan.place_ids.append(place_id)
    return plan


def apply_plan(db: Session, plan: PurgePlan) -> None:
    """계획대로 지우고 커밋한다. RESTRICT 인 예약을 먼저 지운다."""
    if plan.reservation_ids:
        db.execute(
            delete(TrainerReservation).where(
                TrainerReservation.id.in_(plan.reservation_ids)
            )
        )
    if plan.user_ids:
        db.execute(delete(User).where(User.id.in_(plan.user_ids)))
    if plan.place_ids:
        db.execute(delete(Place).where(Place.id.in_(plan.place_ids)))
    db.commit()


def _print_plan(plan: PurgePlan) -> None:
    print(f"데모 사용자: {len(plan.user_ids)}명")
    for user_id in plan.user_ids:
        print(f"  {user_id}")
    print(
        f"예약: {len(plan.reservation_ids)}건 "
        f"(그중 실제 회원의 예약 {plan.real_member_reservations}건)"
    )
    print("함께 지워지거나 비워지는 행(users.id 참조):")
    for table_name, count in sorted(plan.dependent_rows.items()):
        print(f"  {table_name}: {count}")
    print(f"데모 장소: {len(plan.place_ids)}곳")
    for place_id in plan.place_ids:
        print(f"  {place_id}")
    for place_id, reason in sorted(plan.kept_places.items()):
        print(f"  남김 {place_id} — {reason}")


def main() -> int:
    from app.db import demo_ids
    from app.db.session import SessionLocal

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="실제로 지운다. 없으면 건수만 출력한다.",
    )
    args = parser.parse_args()

    db = SessionLocal()
    try:
        plan = build_plan(db, demo_ids.demo_user_ids(), demo_ids.demo_place_ids())
        _print_plan(plan)
        if not args.apply:
            print("미리보기 — 지우지 않았습니다. 지우려면 --apply 를 붙입니다.")
            return 0
        apply_plan(db, plan)
        print("지웠습니다.")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
