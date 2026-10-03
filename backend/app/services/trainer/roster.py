"""트레이너 도메인 — 고객 로스터·식단·기록 집계.

고객의 영양소·나트륨 추세는 별도 복제본이 아니라 회원이 회원 앱에서 남긴 실제
DietEntry 를 집계한 값이다.
"""
from __future__ import annotations

import json
from collections import defaultdict
from datetime import timedelta
from typing import Any

from sqlalchemy import or_, select, tuple_
from sqlalchemy.orm import Session

from app.core import clock
from app.core.pagination import DEFAULT_PAGE
from app.core.week import monday_of
from app.models.models import (
    ChatMessage, DietEntry, ExerciseSession, HealthProfile,
    RoutineHistory,
    TrainerClient, TrainerRoutine, User,
)
from app.schemas.trainer_api import (
    ClientDietEntryOut, RoutineHistoryOut,
    TrainerClientOut,
)
from app.services import health_focus
from app.services import (
    client_signals,
    data_consent_service,
    diet_photo_service,
    exercise_activity,
    profile_format,
    trainer_verification_service,
)
from app.services.trainer._common import (
    _assigned_history_out,
    _calories_week,
    _day_start,
    _iso_day_or_none,
    _local_date_iso,
    _meal_kr,
    _roster_active,
    _roster_preview,
    _sodium_week,
    _sugar_week,
    _today,
    _week_completion,
    history_date_label,
    history_exercise_line,
    history_kind_code,
    parse_history_exercise,
    relative_day_label,
    relative_time_label,
)
from app.services.trainer.routines import (
    routine_active_on,
)


def _today_totals(
    diet_rows: list[DietEntry], today_str: str
) -> tuple[int, int, float, float, float, float]:
    calories = sodium_mg = 0
    sugar_g = carbs_g = protein_g = fat_g = 0.0
    for e in diet_rows:
        if e.date == today_str:
            calories += e.total_calories
            sodium_mg += e.sodium_mg
            sugar_g += e.sugar_g
            carbs_g += e.carbs_g
            protein_g += e.protein_g
            fat_g += e.fat_g
    return calories, sodium_mg, sugar_g, carbs_g, protein_g, fat_g


def _latest_by_member(
    db: Session, model, trainer_id: str, member_ids: list[str], *where
):
    """(trainer, member) 스레드별 최신 1건을 member_id → row 로. [where] 는 추가 조건.

    Postgres DISTINCT ON 으로 회원당 1행만 DB 에서 반환한다 — 오래된 메시지/루틴이
    아무리 많아도 반환 행 수는 회원 수 이하다(전체 로드 후 Python 선별 금지, 리뷰 PR 250-#2).
    """
    rows = db.scalars(
        select(model)
        .where(
            model.trainer_id == trainer_id, model.member_id.in_(member_ids), *where
        )
        # DISTINCT ON (member_id) + 최신순 → 회원별 최신 1건. ORDER BY 선두는
        # distinct 컬럼(member_id)이어야 한다.
        .order_by(model.member_id, model.created_at.desc())
        .distinct(model.member_id)
    ).all()
    return {r.member_id: r for r in rows}


class RosterCursorNotFound(Exception):
    """로스터 커서가 가리키는 회원이 그 트레이너의 명단에 없음 — 라우터가 422 로 옮긴다."""


def build_roster(
    db: Session,
    trainer_id: str,
    *,
    limit: int = DEFAULT_PAGE,
    after_id: str | None = None,
) -> list[TrainerClientOut]:
    """트레이너의 담당 고객 로스터 한 쪽. 각 카드의 영양 지표는 회원 실데이터에서 집계.

    쿼리는 고객 수와 무관하게 상수개(배치)로 유지하고, 식단/기록은 필요한 창(최근 7일 /
    이번 주)만 로드한다(N+1·무제한 이력 로드 방지, 리뷰 PR 250-#3). 쿼리 수는 상수라도
    **한 쿼리가 읽는 양**은 인원수만큼 자라므로 한 번에 주는 건수에 상한을 둔다. (#980)

    커서는 트레이너가 정한 순서를 그대로 따라 오름차순이고, 받은 마지막 카드의 **회원
    id** 하나다(`after_id`) — 정렬키인 `sort_order` 는 카드에 실리지 않으므로 그 자리를
    여기서 찾는다. 명단에 없는 id 면 [RosterCursorNotFound].

    tie-break 를 `created_at` 이 아니라 회원 id 로 둔다 — `sort_order` 가 같은 링크
    사이의 순서만 바뀌며, 담당 링크는 만들 때마다 `max(sort_order) + 1` 을 받아 같은
    값이 겹치는 일 자체가 드물다.
    """
    query = select(TrainerClient).where(TrainerClient.trainer_id == trainer_id)
    if after_id is not None:
        anchor = db.execute(
            select(TrainerClient.sort_order, TrainerClient.member_id).where(
                TrainerClient.trainer_id == trainer_id,
                TrainerClient.member_id == after_id,
            )
        ).first()
        if anchor is None:
            raise RosterCursorNotFound("이어 받을 자리를 찾을 수 없습니다.")
        query = query.where(
            tuple_(TrainerClient.sort_order, TrainerClient.member_id) > tuple(anchor)
        )
    links = db.scalars(
        query.order_by(TrainerClient.sort_order, TrainerClient.member_id).limit(limit)
    ).all()
    if not links:
        return []
    member_ids = [l.member_id for l in links]

    today = _today()
    today_str = today.isoformat()
    monday = monday_of(today)
    week_ago_str = (today - timedelta(days=6)).isoformat()
    monday_str = monday.isoformat()

    # 식단(오늘 합계 + 이번 주 추이) — 전 고객 배치, 날짜 한정. 월요일은 항상
    # `today - 6` 이후라 이 창 하나로 이번 주 월→일을 모두 덮는다.
    diet_by_member: dict[str, list[DietEntry]] = defaultdict(list)
    for e in db.scalars(
        select(DietEntry).where(
            DietEntry.user_id.in_(member_ids), DietEntry.date >= week_ago_str
        )
    ).all():
        diet_by_member[e.user_id].append(e)

    # 이번 주 운동기록(완료율용) — 트레이너 소유(PT) or 자율(NULL)만, 날짜 한정.
    # 타 트레이너의 기록은 제외한다(메모 노출 방지, 리뷰 PR 250-#1).
    hist_by_member: dict[str, list[RoutineHistory]] = defaultdict(list)
    for h in db.scalars(
        select(RoutineHistory).where(
            RoutineHistory.member_id.in_(member_ids),
            RoutineHistory.date >= monday_str,
            or_(RoutineHistory.trainer_id.is_(None), RoutineHistory.trainer_id == trainer_id),
        )
    ).all():
        hist_by_member[h.member_id].append(h)

    last_msg_by = _latest_by_member(db, ChatMessage, trainer_id, member_ids)
    # 철회해 내려온 배정은 로스터의 "최근 루틴" 이 아니다(#2161) — 예전에는
    # 철회가 행을 지웠으므로 같은 결과다.
    last_rt_by = _latest_by_member(
        db, TrainerRoutine, trainer_id, member_ids,
        *routine_active_on(clock.today()),
    )
    members = {
        m.id: m for m in db.scalars(select(User).where(User.id.in_(member_ids))).all()
    }
    # 성별은 로스터 카드가 이름 옆에 적는 값이다. 내려 주지 않던 시절에는 앱이
    # 회원 id 로 값을 지어내 화면마다·모드마다 다른 성별이 떴다(#960). 한 번의
    # 배치 조회로 읽고, 저장된 적이 없는 회원은 빈 문자열로 둔다.
    # 이름 아래 목표는 회원이 고른 건강 목표다(#1818) — 같은 행에서 함께 읽는다.
    # 나이도 같은 행의 생년월일에서 센다(#2728) — 내려 주지 않던 시절에는 앱이
    # 회원 id 로 나이를 지어냈다.
    gender_by_member: dict[str, str] = {}
    goal_by_member: dict[str, str] = {}
    age_by_member: dict[str, int | None] = {}
    today_for_age = clock.today()
    for member_id, gender, conditions, birth_date in db.execute(
        select(
            HealthProfile.user_id,
            HealthProfile.gender,
            HealthProfile.conditions,
            HealthProfile.birth_date,
        ).where(HealthProfile.user_id.in_(member_ids))
    ).all():
        gender_by_member[member_id] = gender
        goal_by_member[member_id] = health_focus.focus_label(conditions)
        age_by_member[member_id] = profile_format.age_on(birth_date, today_for_age)
    # PT 관리 신호(#2203) — 기준과 계산은 client_signals 한 곳에 있다.
    signals_by_member = client_signals.build_signals(db, trainer_id, list(links))
    # 반려된 트레이너는 담당 회원의 이름·연결 상태만 본다(#3009). 수치·미리보기는
    # 동의 철회와 같은 방식으로 비운다 — 무엇이 잠겼는지는 알 수 있어야 한다.
    approved = trainer_verification_service.is_approved(db, trainer_id)

    out: list[TrainerClientOut] = []
    for link in links:
        member = members.get(link.member_id)
        if member is None:
            continue
        # 미등록 관계는 고객 관리의 이름·상태만 남긴다. 회원 원본 데이터는
        # 보존하되 트레이너에게 다시 노출하지 않는다. 동의가 철회된 뒤 새 동의
        # 없이 살아 있는 링크도 같다(#1631).
        readable = (
            approved
            and link.active
            and not data_consent_service.blocks_access(link)
        )
        diet_rows = diet_by_member.get(link.member_id, []) if readable else []
        calories, sodium_mg, sugar_g, carbs_g, protein_g, fat_g = _today_totals(
            diet_rows, today_str
        )
        last_msg = last_msg_by.get(link.member_id) if readable else None
        last_rt = last_rt_by.get(link.member_id) if readable else None

        out.append(TrainerClientOut(
            id=link.member_id,
            name=member.name,
            avatar=member.name[:1] if member.name else "?",
            # 성별·나이·건강 목표도 동의 범위의 신체·건강 정보다(#2814). 해제·철회
            # 관계에 남기면 철회 뒤 회원이 바꾼 새 목표까지 트레이너에게 흘러간다.
            gender=gender_by_member.get(link.member_id, "") if readable else "",
            age=age_by_member.get(link.member_id) if readable else None,
            goal=goal_by_member.get(link.member_id, "") if readable else "",
            last_message=_roster_preview(last_msg),
            last_time=relative_time_label(last_msg.created_at) if last_msg else "-",
            last_message_at=last_msg.created_at if last_msg else None,
            active=_roster_active(link),
            registered=link.active,
            calories=calories,
            sodium_mg=sodium_mg,
            sugar_g=sugar_g,
            carbs_g=carbs_g,
            protein_g=protein_g,
            fat_g=fat_g,
            last_routine=(
                relative_day_label(_local_date_iso(last_rt.created_at))
                if last_rt else "-"
            ),
            last_routine_date=(
                _local_date_iso(last_rt.created_at) if last_rt else None
            ),
            week_completion=_week_completion(
                hist_by_member.get(link.member_id, []) if readable else [], monday
            ),
            sodium_week=_sodium_week(diet_rows, monday),
            calories_week=_calories_week(diet_rows, monday),
            sugar_week=_sugar_week(diet_rows, monday),
            signals=signals_by_member.get(link.member_id, []) if readable else [],
        ))
    return out


def _food_names(foods_json: str | None) -> list[str]:
    """저장된 `foods_json` → 표시용 음식 이름 목록.

    항목이 딕셔너리라는 보장이 없다. 실제로 `["김치찌개", 42, null]` 처럼 문자열·숫자가
    섞여 저장된 기록이 있고, 예전에는 `f.get("name")` 이 그 자리에서 AttributeError 를
    내 **그 날짜 식단 조회 전체가 500** 이 됐다(#724). 회원 앱 경로
    (`diet_service.load_foods`)는 같은 값을 받아도 죽지 않아, 한 기록인데 트레이너 쪽만
    터졌다.

    문자열은 이름으로 살린다 — 버리면 트레이너 화면에서 끼니 내용이 통째로 빈다.
    이름을 만들 수 없는 나머지(숫자·null 등)는 건너뛴다.
    """
    try:
        foods = json.loads(foods_json) if foods_json else []
    except json.JSONDecodeError:
        return []
    if not isinstance(foods, list):
        return []

    names: list[str] = []
    for food in foods:
        if isinstance(food, dict):
            name = food.get("name")
        elif isinstance(food, str):
            name = food
        else:
            continue
        if isinstance(name, str) and name.strip():
            names.append(name.strip())
    return names


def _foods(foods_json: str | None) -> list[dict[str, Any]]:
    """끼니의 음식별 영양. 회원 API 가 흘려 보내는 것과 같은 배열이다. (#1166)

    깨진 값은 빈 목록으로 본다 — 트레이너 화면은 그때 `items` 한 줄로 떨어져
    예전과 같이 읽힌다.
    """
    try:
        parsed = json.loads(foods_json or "[]")
    except (TypeError, ValueError):
        return []
    if not isinstance(parsed, list):
        return []
    return [item for item in parsed if isinstance(item, dict)]


def build_client_diet(db: Session, member_id: str, day: str) -> list[ClientDietEntryOut]:
    """회원의 특정 날짜 식단(회원 실데이터)을 고객 식단 서브탭 형태로."""
    rows = db.scalars(
        select(DietEntry)
        .where(DietEntry.user_id == member_id, DietEntry.date == day)
        .order_by(DietEntry.created_at, DietEntry.id)
    ).all()

    # 사진은 id 만 한 번에 읽는다(바이트는 사진 라우트에서만 흐른다). (#699)
    photo_ids = diet_photo_service.photo_ids_for_entries(db, [r.id for r in rows])

    out: list[ClientDietEntryOut] = []
    for r in rows:
        items = ", ".join(_food_names(r.foods_json))
        photo_id = photo_ids.get(r.id)
        out.append(ClientDietEntryOut(
            id=r.id,
            meal=_meal_kr(r.meal_type),
            items=items,
            # 회원 앱 끼니 카드와 같은 재료를 그대로 넘긴다(#1166). 이름만 이어
            # 붙인 `items` 로는 같은 500kcal 이 밥에서 왔는지 기름에서 왔는지
            # 트레이너가 알 수 없다.
            time_label=r.time_label or "",
            foods=_foods(r.foods_json),
            calories=r.total_calories,
            sodium_mg=r.sodium_mg,
            sugar_g=r.sugar_g,
            carbs_g=r.carbs_g,
            protein_g=r.protein_g,
            fat_g=r.fat_g,
            photo_url=client_photo_url(member_id, photo_id) if photo_id else None,
        ))
    return out


def client_photo_url(member_id: str, photo_id: str) -> str:
    """담당 트레이너가 보는 고객 끼니 사진 경로(API base 기준 상대 경로).

    회원 경로(`/diet/photos/{id}`)와 다른 이유는 접근 판정이 다르기 때문이다.
    이 경로는 `member_id` 를 지나가므로 라우터가 담당 링크를 먼저 확인하고,
    사진이 그 회원의 것인지까지 본다.
    """
    return f"/trainer/clients/{member_id}/diet/photos/{photo_id}"


def build_client_history(
    db: Session, member_id: str, trainer_id: str, limit: int = 60
) -> list[RoutineHistoryOut]:
    """회원의 운동 완료 기록(최신순).

    이 트레이너에게 보이는 기록만 반환한다: 자율 운동(trainer_id NULL) + 이 트레이너가
    지도한 세션(trainer_id == 본인). 타 트레이너가 작성한 메모(trainer_note)는 노출하지
    않는다(리뷰 PR 250-#1). 오래된 이력 무제한 로드를 막기 위해 limit 로 제한.
    """
    rows = db.scalars(
        select(RoutineHistory)
        .where(
            RoutineHistory.member_id == member_id,
            or_(RoutineHistory.trainer_id.is_(None), RoutineHistory.trainer_id == trainer_id),
        )
        .order_by(RoutineHistory.date.desc(), RoutineHistory.created_at.desc())
        .limit(limit)
    ).all()

    assigned_rows = db.scalars(
        select(ExerciseSession).where(
            ExerciseSession.user_id == member_id,
            ExerciseSession.source == "assigned_routine",
            ExerciseSession.assigned_trainer_id == trainer_id,
        )
        .order_by(ExerciseSession.completed_at.desc(), ExerciseSession.created_at.desc())
        .limit(limit)
    ).all()

    dated: list[tuple[str, float, RoutineHistoryOut]] = []
    for r in rows:
        try:
            exercises = json.loads(r.exercises_json) if r.exercises_json else []
        except json.JSONDecodeError:
            exercises = []
        dated.append((r.date, clock.to_seoul(r.created_at).timestamp(), RoutineHistoryOut(
            id=r.id,
            date_label=history_date_label(r.date),
            label=r.kind_label,
            completion_rate=r.completion_rate,
            exercises=[history_exercise_line(e) for e in exercises],
            date=_iso_day_or_none(r.date),
            kind=history_kind_code(r.kind_label),
            exercise_items=[parse_history_exercise(e) for e in exercises],
            client_feedback=r.client_feedback,
            trainer_note=r.trainer_note,
            # 배정 수행(`_assigned_history_out`)은 완료 시각을 함께 내려보내는데
            # 이 갈래만 비워 두고 있었다. 받는 쪽은 그 값으로 기록을 날짜에
            # 붙이므로, 비어 오면 화면에서 통째로 빠진다 — 이 표는 날짜를
            # 갖고 있으니(`date`) 그날로 채운다. (#1114, #1025)
            completed_at=_day_start(r.date),
        )))
    for r in assigned_rows:
        completed_at = r.completed_at or r.created_at
        # 이력이 붙는 날짜는 회원 화면과 같은 논리 운동일이다 — 완료 시각만
        # 보면 지난 주 수행을 오늘 고친 기록이 오늘로 올라온다. (#1264)
        day = (
            exercise_activity.activity_date_of(r)
            or clock.to_seoul(completed_at).date()
        ).isoformat()
        dated.append(
            (
                day,
                clock.to_seoul(completed_at).timestamp(),
                _assigned_history_out(r),
            )
        )
    dated.sort(key=lambda item: (item[0], item[1]), reverse=True)
    return [item[2] for item in dated[:limit]]
