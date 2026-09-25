"""
트레이너 도메인 서비스 — 로스터/식단/기록 집계.

핵심(진짜 데이터 공유): 고객의 영양소·나트륨 추세는 별도 복제본이 아니라
회원이 회원 앱에서 남긴 실제 DietEntry 를 집계한 값이다. 라우터는 얇게 두고 도메인
로직(집계·라벨링·계약 매핑)은 여기에 모은다.
"""
from __future__ import annotations

import hashlib
import json
import re
import uuid
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy import exists, func, or_, select, tuple_, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from pydantic import ValidationError

from app.core import clock
from app.core.pagination import DEFAULT_PAGE
from app.models.models import (
    ChatMessage, DietEntry, ExerciseSession, GymProfile, HealthProfile, Place, RoutineHistory,
    TrainerClient, TrainerClientMemo, TrainerProfile, TrainerProgramDraft,
    TrainerFollowUpTask, TrainerReportFeedback,
    TrainerReservation, TrainerReservationSlot, TrainerRoutine, TrainerSchedule,
    User,
)
from app.schemas.trainer_api import (
    ChatAttachmentOut, ChatMessageOut, ClientDietEntryOut, MemberCoachOut,
    PersonalRoutineItem,
    ProgramDraftExercise,
    ProgramDraftSession,
    ProgramItem, ProgramScheduleOut, ReportFeedbackOut, RoutineCompleteOut,
    RoutineHistoryOut,
    RoutineOut, ScheduleSessionOut, TrainerClientOut, TrainerClientStatusOut,
    TrainerFollowUpTaskOut,
    TrainerGymOut, TrainerMe, TrainerMemoOut, TrainerNotificationSettings,
    TrainerProgramDraftOut, TrainerProgramDraftSummary, WeeklyReportDayOut,
    WeeklyReportOut,
)
from app.services import health_focus
from app.services import (
    auto_routine_service,
    client_signals,
    diet_photo_service,
    exercise_activity,
    exercise_service,
    exercise_types,
    notification_service,
    points_coupon_service,
    points_service,
    routine_advice,
    routine_suggestion_service,
    schedule_parse,
    streak_shield_service,
)
from app.schemas.points_api import PointsOut
from app.services.coach import personal_ingest

# 일일 나트륨 목표(mg). 프론트 `sodiumTargetMg` 와 같은 값 — 리포트의
# '초과 N일'이 앱 화면의 경고와 어긋나면 안 된다.
SODIUM_TARGET_MG = 2000


class IdempotencyConflict(Exception):
    """같은 멱등키가 이미 다른 payload 에 사용됐다."""


def _today() -> date:
    return clock.today()


def today_iso() -> str:
    """오늘 날짜 YYYY-MM-DD (라우터 기본 날짜용)."""
    return _today().isoformat()


def _meal_kr(meal_type: str) -> str:
    """끼니 종류 → 트레이너 웹이 그리는 한국어 라벨.

    키는 회원 앱 `MealType.name` 이다(#1988 의 `lateNight` 포함). 모르는 값은
    접지 않고 그대로 돌려준다 — 간식으로 접으면 새 끼니가 조용히 낮의 간식과
    한 칸에 섞인다.
    """
    return {
        "breakfast": "아침",
        "lunch": "점심",
        "dinner": "저녁",
        "snack": "간식",
        "lateNight": "야식",
    }.get(meal_type, meal_type)


def relative_day_label(day: str) -> str:
    """YYYY-MM-DD → 오늘/어제/N일 전 (마지막 루틴 전송 라벨용)."""
    try:
        then = date.fromisoformat(day)
    except ValueError:
        return day
    delta = (_today() - then).days
    if delta <= 0:
        return "오늘"
    if delta == 1:
        return "어제"
    return f"{delta}일 전"


def history_date_label(day: str) -> str:
    """YYYY-MM-DD → 'M/D' (+ ' (오늘)'/' (어제)') 운동기록 라벨."""
    try:
        then = date.fromisoformat(day)
    except ValueError:
        return day
    label = f"{then.month}/{then.day}"
    delta = (_today() - then).days
    if delta == 0:
        label += " (오늘)"
    elif delta == 1:
        label += " (어제)"
    return label


def relative_time_label(ts: datetime) -> str:
    """채팅 최근시각 → 오늘이면 HH:MM, 어제면 '어제', 그 전이면 YYYY-MM-DD.

    카카오톡과 같은 규칙이다. 예전에는 "방금/N분 전/N시간 전/N일 전" 으로
    흘러간 시간을 셌는데, 며칠씩 지난 대화에서 트레이너가 알고 싶은 것은
    "얼마나 됐나" 가 아니라 **언제였나** 다 — 그건 운동·식단 기록과 맞춰
    보려면 날짜여야 한다.

    경계는 **KST 달력 날짜**로 가른다. 흘러간 초로 나누면 KST 새벽 1시에
    받은 메시지가 23시간 전이라는 이유로 '오늘' 이 아니게 된다.
    """
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    local = clock.to_seoul(ts)
    today = clock.to_seoul(datetime.now(timezone.utc)).date()
    days = (today - local.date()).days
    if days <= 0:
        return local.strftime("%H:%M")
    if days == 1:
        return "어제"
    return local.date().isoformat()


def _local_date_iso(ts: datetime) -> str:
    """tz-aware(또는 naive=UTC 가정) 시각 → KST 날짜 YYYY-MM-DD.

    created_at 은 UTC 로 저장되므로, '오늘/어제' 판정과 맞추려면 KST 날짜로 변환해야
    한다(안 그러면 KST 새벽엔 UTC 가 전날이라 '어제'로 어긋난다)."""
    return clock.to_seoul(ts).date().isoformat()


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


def _sodium_week(diet_rows: list[DietEntry], monday: date) -> list[int]:
    """이번 주(월→일) 일별 나트륨 합. 기록 없는 날은 0."""
    return [
        round(v) for v in _daily_week(diet_rows, monday, lambda e: e.sodium_mg)
    ]


def _calories_week(diet_rows: list[DietEntry], monday: date) -> list[int]:
    """이번 주(월→일) 일별 칼로리 합. 나트륨과 같은 창·같은 규칙이다. (#746)"""
    return [
        round(v)
        for v in _daily_week(diet_rows, monday, lambda e: e.total_calories)
    ]


def _sugar_week(diet_rows: list[DietEntry], monday: date) -> list[float]:
    """이번 주(월→일) 일별 당류 합.

    나트륨·칼로리와 달리 소수를 유지한다 — 당류는 6.3+8.5 처럼 소수로 쌓이고,
    반올림하면 같은 회원의 식단 탭 수치와 어긋난다(`sugar_g` 가 Float 인 이유와
    같다).
    """
    return [round(v, 1) for v in _daily_week(diet_rows, monday, lambda e: e.sugar_g)]


def _macro_week(
    diet_rows: list[DietEntry], monday: date, value: Callable[[DietEntry], float]
) -> list[float]:
    """이번 주(월→일) 일별 탄·단·지 합. 당류와 같이 소수를 유지한다.

    트레이너 화면의 `이번 달` 칼로리 막대를 탄단지로 쌓는 재료다(#944). 칼로리와
    같은 창·같은 규칙이라 x 축이 어긋나지 않는다.
    """
    return [round(v, 1) for v in _daily_week(diet_rows, monday, value)]


def _daily_week(
    diet_rows: list[DietEntry], monday: date, value: Callable[[DietEntry], float]
) -> list[float]:
    """이번 주(월→일) 일별 합. 기록 없는 날과 아직 오지 않은 날은 0.

    `week_completion` 과 **같은 창**이다. 오늘 기준 롤링 7일이 아니라 요일에
    고정한다 — 화면이 이 값을 요일 라벨과 함께 그리므로, 창이 굴러가면 금요일
    수치가 일요일 자리에 놓인다(#746).
    """
    by_date: dict[str, float] = {}
    for e in diet_rows:
        by_date[e.date] = by_date.get(e.date, 0) + value(e)
    return [
        by_date.get((monday + timedelta(days=off)).isoformat(), 0)
        for off in range(7)
    ]


def _week_completion(hist_rows: list[RoutineHistory], monday: date) -> list[int]:
    """이번 주(월→일) 일별 완료율. 같은 날 여러 기록이면 최댓값, 없으면 0."""
    by_date: dict[str, list[int]] = {}
    for h in hist_rows:
        by_date.setdefault(h.date, []).append(h.completion_rate)
    out: list[int] = []
    for i in range(7):
        vals = by_date.get((monday + timedelta(days=i)).isoformat())
        out.append(max(vals) if vals else 0)
    return out


def _week_days(
    rows: list[ExerciseSession], week: list[int]
) -> list[WeeklyReportDayOut]:
    """요일별 이행률 + 그날 **실제로 한** 운동(월→일).

    운동 이름은 회원의 운동 기록에서 온다 — 배정 목록이 아니다(#1288). 예전에는
    `routine_history` 를 읽었는데, 그 표에 쓰는 경로는 PT 세션 완료 하나뿐이라
    PT 한 날 말고는 요일 칸이 늘 비어 있었다. 배정 루틴 수행도 회원이 혼자 한
    운동도 전부 `exercise_sessions` 로 가므로, 읽을 곳은 여기다.

    **미수행(✗) 표시를 붙이지 않는다.** 배정에는 날짜가 없어 — `exercise_date`
    를 채우는 생성 경로가 없고 회원 목록에도 날짜 필터가 없다 — "그날 배정됐는데
    안 했다" 를 만들 수 없다. 그날 남은 기록만 적는다.

    [rows] 는 한 주치 기록이다. 운동 기록은 날짜가 아니라 (그 주 월요일, 요일)
    로 저장되므로 요일 라벨만으로 자리가 정해진다.
    """
    by_weekday: dict[int, list[str]] = {}
    for row in rows:
        if row.day_label not in exercise_service.WEEKDAY_LABELS:
            continue
        # 이름이 빈 기록은 그 컬럼이 생기기 전(#1276)의 것이다. 유형 라벨이라도
        # 적어야 그날 무엇을 했는지가 칸에서 통째로 사라지지 않는다.
        name = (row.name or "").strip() or exercise_types.normalize_ko(row.type)
        by_weekday.setdefault(
            exercise_service.WEEKDAY_LABELS.index(row.day_label), []
        ).append(name)
    return [
        WeeklyReportDayOut(
            completion=week[i] if i < len(week) else 0,
            exercises=by_weekday.get(i, []),
        )
        for i in range(7)
    ]


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


def _roster_active(link: TrainerClient) -> bool:
    """로스터 카드의 활성/휴면. (#707)

    두 조건을 모두 만족해야 활성이다 — 담당 관계가 살아 있고(`active`), 트레이너가
    휴면으로 내리지 않았을 것(`not dormant`). 담당이 해제된 과거 회원은 로스터에
    이력으로 남는데, 그 카드는 예나 지금이나 휴면으로 보여야 한다.
    """
    return link.active and not link.dormant


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
    monday = today - timedelta(days=today.weekday())
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
    gender_by_member: dict[str, str] = {}
    goal_by_member: dict[str, str] = {}
    for member_id, gender, conditions in db.execute(
        select(
            HealthProfile.user_id, HealthProfile.gender, HealthProfile.conditions
        ).where(HealthProfile.user_id.in_(member_ids))
    ).all():
        gender_by_member[member_id] = gender
        goal_by_member[member_id] = health_focus.focus_label(conditions)
    # PT 관리 신호(#2203) — 기준과 계산은 client_signals 한 곳에 있다.
    signals_by_member = client_signals.build_signals(db, trainer_id, list(links))

    out: list[TrainerClientOut] = []
    for link in links:
        member = members.get(link.member_id)
        if member is None:
            continue
        # 미등록 관계는 고객 관리의 이름·상태만 남긴다. 회원 원본 데이터는
        # 보존하되 트레이너에게 다시 노출하지 않는다.
        diet_rows = diet_by_member.get(link.member_id, []) if link.active else []
        calories, sodium_mg, sugar_g, carbs_g, protein_g, fat_g = _today_totals(
            diet_rows, today_str
        )
        last_msg = last_msg_by.get(link.member_id) if link.active else None
        last_rt = last_rt_by.get(link.member_id) if link.active else None

        out.append(TrainerClientOut(
            id=link.member_id,
            name=member.name,
            avatar=member.name[:1] if member.name else "?",
            gender=gender_by_member.get(link.member_id, ""),
            goal=goal_by_member.get(link.member_id, ""),
            last_message=last_msg.body if last_msg else "",
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
            week_completion=_week_completion(
                hist_by_member.get(link.member_id, []) if link.active else [], monday
            ),
            sodium_week=_sodium_week(diet_rows, monday),
            calories_week=_calories_week(diet_rows, monday),
            sugar_week=_sugar_week(diet_rows, monday),
            signals=signals_by_member.get(link.member_id, []),
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
            exercises=exercises,
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


# ---- 채팅 (트레이너↔회원, 양방향 공유 스레드) ----

def _hhmm(ts: datetime) -> str:
    """created_at → KST HH:MM."""
    return clock.to_seoul(ts).strftime("%H:%M")


def _sender_out(sender: str, viewer: str = "trainer") -> str:
    """저장값(trainer|member) → 뷰어 관점 라벨.

    트레이너 앱: 상대(member)는 'client'. 회원 앱: 자신(member)은 'me', 트레이너는 'trainer'.
    """
    if viewer == "member":
        return "me" if sender == "member" else "trainer"
    return "client" if sender == "member" else "trainer"


def _iso(ts: datetime) -> str:
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return ts.astimezone(timezone.utc).isoformat()


def build_chat_thread(
    db: Session, trainer_id: str, member_id: str,
    limit: int = 50, before: datetime | None = None, before_id: str | None = None,
    viewer: str = "trainer",
) -> list[ChatMessageOut]:
    """(trainer, member) 스레드 메시지(오래된→최신).

    무제한 로드를 막기 위해 기본 최신 `limit`건만 가져온다(리뷰 PR 251-#3). 이전 페이지는
    가장 오래된 메시지의 (created_at, id)를 (before, before_id) 커서로 넘겨 요청한다.
    같은 created_at 이 여러 건이어도 누락되지 않도록 (created_at, id) 복합 커서를 쓴다
    (리뷰 재-#1). 응답의 created_at 으로 클라이언트가 다음 커서를 만든다.
    """
    q = select(ChatMessage).where(
        ChatMessage.trainer_id == trainer_id, ChatMessage.member_id == member_id
    )
    if before is not None:
        if before_id is not None:
            # (created_at, id) < (before, before_id) — 동일 created_at 경계도 안전하게 통과
            q = q.where(
                tuple_(ChatMessage.created_at, ChatMessage.id) < (before, before_id)
            )
        else:
            q = q.where(ChatMessage.created_at < before)
    rows = list(db.scalars(
        q.order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc()).limit(limit)
    ).all())
    rows.reverse()  # 최신 limit건을 오래된→최신 순으로
    return [
        chat_message_out(r, viewer)
        for r in rows
    ]


def chat_message_out(msg: ChatMessage, viewer: str) -> ChatMessageOut:
    attachment = None
    if msg.attachment_type in ("pdf", "image") and msg.attachment_file_id:
        # 이름이 없는 첨부도 화면에는 무언가 적혀야 한다 — 종류별 기본값을 준다.
        fallback = (
            "weekly-report.pdf" if msg.attachment_type == "pdf" else "사진"
        )
        attachment = ChatAttachmentOut(
            type=msg.attachment_type,
            file_name=msg.attachment_file_name or fallback,
            file_id=msg.attachment_file_id,
            file_size=msg.attachment_file_size or 0,
            download_path=f"/chat/attachments/{msg.attachment_file_id}",
        )
    return ChatMessageOut(
        id=msg.id,
        sender=_sender_out(msg.sender, viewer),
        body=msg.body,
        time_label=_hhmm(msg.created_at),
        created_at=_iso(msg.created_at),
        attachment=attachment,
        emote_id=msg.emote_id,
        report_week_start=msg.report_week_start,
    )


def find_message_by_client_request(
    db: Session,
    trainer_id: str,
    member_id: str,
    sender: str,
    client_request_id: str,
) -> ChatMessage | None:
    return db.scalar(
        select(ChatMessage).where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.sender == sender,
            ChatMessage.client_request_id == client_request_id,
        )
    )


def _existing_message_out(
    message: ChatMessage, *, text: str, viewer: str
) -> ChatMessageOut:
    if message.body != text:
        raise IdempotencyConflict(
            "같은 client_request_id에 다른 메시지를 보낼 수 없습니다."
        )
    return chat_message_out(message, viewer)


#: 대화에서 읽어 낸 PT 의 종류·길이·표시. 길이는 트레이너 앱의 기본 한 시간을
#: 따른다 — 문장에 "몇 분" 까지 적히는 일은 드물어 짐작하지 않는다.
PT_SESSION_TYPE = "1:1 PT"
_CHAT_SCHEDULE_MINUTES = 60
_CHAT_SCHEDULE_NOTE = "대화에서 잡은 일정"


def _schedule_from_chat(
    db: Session, trainer_id: str, member_id: str, text: str, sent_at: datetime
) -> None:
    """트레이너가 대화에서 잡은 다음 PT 를 일정으로 남긴다. (#1061)

    약속은 대화에서 잡히는데 그 말이 채팅 안에만 남아, 회원 앱의 `다음 PT
    일정` 은 비어 있거나 지난 일정을 들고 있었다.

    **트레이너가 보낸 말만** 본다. 회원이 제안한 시간은 아직 약속이 아니다 —
    트레이너가 받아 주기 전에 일정으로 굳히면 오지 않을 시간을 잡아 둔다.

    같은 날 같은 시각의 일정이 이미 있으면 아무것도 하지 않는다. 트레이너가
    같은 약속을 두 번 말하는 것은 흔한 일이라, 그때마다 칸이 늘면 일정 화면이
    중복으로 찬다.
    """
    parsed = schedule_parse.parse_schedule(
        text, sent_on=clock.to_seoul(sent_at).date()
    )
    if parsed is None:
        return
    existing = db.scalar(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.date == parsed.date,
            TrainerSchedule.time == parsed.time,
        )
    )
    if existing is not None:
        return
    member_name = db.scalar(select(User.name).where(User.id == member_id))
    db.add(
        TrainerSchedule(
            id=f"sched-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            date=parsed.date,
            time=parsed.time,
            client_name=member_name or "",
            type=PT_SESSION_TYPE,
            duration_minutes=_CHAT_SCHEDULE_MINUTES,
            status="예정",
            # 어디서 온 일정인지 남긴다 — 사람이 만든 일정과 섞이면, 잘못
            # 읽은 약속을 나중에 가려낼 수 없다.
            note=_CHAT_SCHEDULE_NOTE,
            program_json="[]",
            sort_order=0,
        )
    )
    db.flush()


def send_message(
    db: Session, trainer_id: str, member_id: str, sender: str, text: str,
    viewer: str = "trainer", notify: str | None = None,
    client_request_id: str | None = None,
    attachment_type: str = "pdf",
    attachment_file_name: str | None = None,
    attachment_file_id: str | None = None,
    attachment_file_size: int | None = None,
    report_week_start: str | None = None,
    emote_id: str | None = None,
) -> ChatMessageOut:
    """스레드에 메시지 추가(sender: 'trainer'|'member'). 로스터 last_message 는
    build_roster 가 최신 메시지를 읽어 자동 반영하므로 별도 비정규화가 없다.

    [notify] 가 주어지면 그 종류로 회원 알림을 **같은 트랜잭션에** 얹는다(#489).
    종류를 호출자가 정하는 이유: 주간 리포트도 이 함수로 나가므로, 여기서 판단하면
    일반 메시지와 구분할 수 없다. [attachment_type] 도 같은 이유로 호출자가
    정한다 — 파일만 보고는 리포트인지 코칭 사진인지 알 수 없다(#921).

    회원이 보낸 메시지에는 **트레이너 알림**을 남긴다(#503). 사이드바 미읽음 배지는
    지금 보고 있을 때만 눈에 들어오고, 지나가면 다시 볼 자리가 없었다.
    """
    if client_request_id:
        existing = find_message_by_client_request(
            db, trainer_id, member_id, sender, client_request_id
        )
        if existing is not None:
            return _existing_message_out(existing, text=text, viewer=viewer)

    msg = ChatMessage(
        id=f"chat-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        sender=sender,
        body=text,
        client_request_id=client_request_id,
        # 첨부가 없으면 종류도 없다. 종류를 호출자가 정하는 이유는 파일만 보고는
        # 알 수 없기 때문이다 — 리포트 PDF(#778)와 코칭 사진(#921)이 같은 자리로
        # 들어온다.
        attachment_type=attachment_type if attachment_file_id else None,
        attachment_file_name=attachment_file_name,
        attachment_file_id=attachment_file_id,
        attachment_file_size=attachment_file_size,
        # 리포트 전송 안내인가 — 호출자가 정한다. 첨부와 마찬가지로 본문만
        # 보고는 알 수 없고, 리포트는 PDF 없이도 나간다(#1600).
        report_week_start=report_week_start,
        # 이모티콘 메시지(#2020). 본문은 이모티콘을 못 그리는 자리(알림·로스터의
        # 마지막 메시지)가 읽을 글이고, 그림은 이 id 가 고른다.
        emote_id=emote_id,
        created_at=datetime.now(timezone.utc),
    )
    db.add(msg)
    # 알림을 넣기 전에 DB 유니크 제약을 확인한다. 동시 재시도 중 진 요청이 여기서
    # 막혀야 회원·트레이너 알림도 한 번만 생성된다.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = find_message_by_client_request(
                db, trainer_id, member_id, sender, client_request_id
            )
            if existing is not None:
                return _existing_message_out(existing, text=text, viewer=viewer)
        raise

    if sender == "trainer":
        _schedule_from_chat(db, trainer_id, member_id, text, msg.created_at)

    if sender == "member":
        member_name = db.scalar(select(User.name).where(User.id == member_id))
        notification_service.queue_for_trainer(
            db,
            trainer_id=trainer_id,
            kind=notification_service.TRAINER_MESSAGE_KIND,
            title=f"{member_name or '회원'} 회원의 메시지",
            body=text,
        )
    if notify is not None and sender == "trainer":
        trainer_name = db.scalar(select(User.name).where(User.id == trainer_id))
        is_report = notify == notification_service.WEEKLY_REPORT
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notify,
            title=(
                "주간 리포트가 도착했어요"
                if is_report
                else f"{trainer_name or '트레이너'} 트레이너의 메시지"
            ),
            # 사진만 보낸 메시지는 본문이 비어 있다(#921). 알림 본문까지 비우면
            # 목록에 제목만 뜬 빈 줄이 남아, 무엇이 왔는지 알 수 없다.
            body=text or ("사진을 보냈어요" if attachment_file_id and attachment_type == "image" else text),
            # 리포트도 대화 스레드로 도착한다 — 별도 리포트 함이 없다. 목적지는
            # 같지만 갈래를 나눠 회원 앱이 리포트를 메시지와 다른 아이콘으로
            # 그린다(#2085).
            category=(
                notification_service.MEMBER_COACH_REPORT
                if is_report
                else notification_service.MEMBER_COACH_CHAT
            ),
        )
    db.commit()
    db.refresh(msg)
    out = chat_message_out(msg, viewer)
    # 적재는 응답을 다 만든 뒤에 한다(#580). 실패하면 personal_ingest 가 세션을
    # 롤백하는데, 그때 msg 가 만료돼 응답을 못 만들게 되면 적재 실패가 메시지
    # 발신 실패로 번진다. 커밋은 이미 끝났으니 롤백해도 메시지 자체는 남는다.
    personal_ingest.record_chat(
        db, member_id, sender=sender, text=text,
        date=clock.to_seoul(msg.created_at).date().isoformat(),
        source_ref=msg.id,
    )
    return out


def mark_thread_read(db: Session, trainer_id: str, member_id: str, reader: str) -> int:
    """reader 가 상대방이 보낸 미확인 메시지를 읽음 처리. 반환: 읽음 처리된 건수.

    reader='trainer' → 상대(member)가 보낸 미확인 메시지에 read_at 을 채운다.
    reader='member'  → 상대(trainer)가 보낸 미확인 메시지에 read_at 을 채운다.
    """
    other = "member" if reader == "trainer" else "trainer"
    result = db.execute(
        update(ChatMessage)
        .where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.sender == other,
            ChatMessage.read_at.is_(None),
        )
        .values(read_at=datetime.now(timezone.utc))
    )
    db.commit()
    return result.rowcount or 0


def unread_counts_for_trainer(db: Session, trainer_id: str) -> dict[str, int]:
    """트레이너 기준 회원별 미확인(회원이 보낸 read_at NULL) 메시지 수."""
    rows = db.execute(
        select(ChatMessage.member_id, func.count())
        .where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.sender == "member",
            ChatMessage.read_at.is_(None),
        )
        .group_by(ChatMessage.member_id)
    ).all()
    return {member_id: count for member_id, count in rows}


# ---- 회원 활성/휴면 관리 상태 (#707) ----

class ClientLinkDetached(Exception):
    """담당 관계가 이미 해제된 회원이다(라우터가 409 로 변환)."""


def remove_client(db: Session, link: TrainerClient) -> None:
    """담당 목록에서만 제거하고 회원이 보는 공유 데이터는 보존한다.

    관계 행이 사라지면 트레이너의 고객 기반 화면과 권한에서 제외된다. 스케줄,
    프로그램·루틴, 리포트, PT 이력과 대화 원본은 삭제하지 않으므로 회원 앱에서는
    기존 기록을 계속 볼 수 있다.

    담당이 끝나므로 회원의 PT 재등록 쿠폰을 취소하고 포인트를 돌려준다(#1787).
    """
    link.active = False
    points_coupon_service.cancel_renewal_coupons(db, link.member_id)
    db.commit()


def restore_client(db: Session, link: TrainerClient) -> None:
    """과거 담당 관계를 다시 등록 상태로 전환한다."""
    if link.active:
        return
    occupied = db.scalar(
        select(TrainerClient.id).where(
            TrainerClient.member_id == link.member_id,
            TrainerClient.active.is_(True),
        )
    )
    if occupied is not None:
        raise ClientLinkDetached("이미 다른 트레이너가 담당 중인 회원입니다.")
    link.active = True
    link.dormant = False
    db.commit()


def set_client_active(
    db: Session, link: TrainerClient, active: bool
) -> TrainerClientStatusOut:
    """담당 회원을 활성/휴면으로 전환한다.

    `dormant` 만 건드린다 — 담당 링크(`active`)·루틴·기록·식단·채팅은 그대로다.
    휴면 회원도 조회·채팅·루틴 배정이 전부 그대로 되고, 회원 앱에서 코치가
    사라지지도 않는다. 트레이너의 관리 표시일 뿐이다.

    이미 같은 상태면 아무것도 쓰지 않고 그 상태를 돌려준다 — 연타나 재시도가
    상태를 흔들지 않는다(멱등).

    담당이 이미 해제된 링크는 [ClientLinkDetached] 다. 여기서 `dormant` 를
    내려 봐야 로스터는 계속 휴면으로 보이므로(`_roster_active`), 성공으로
    응답하면 화면이 "저장했는데 그대로"가 된다. 담당 재배정은 이 기능의 범위가
    아니다.
    """
    if not link.active:
        raise ClientLinkDetached("담당 관계가 해제된 회원입니다.")
    if link.dormant is not (not active):
        link.dormant = not active
        db.commit()
        db.refresh(link)
    return TrainerClientStatusOut(
        member_id=link.member_id, active=_roster_active(link)
    )


# ---- 루틴 배정 (트레이너/AI → 회원, 양쪽에서 보이는 공유 데이터) ----

def delete_trainer_account(db: Session, trainer: User) -> None:
    """트레이너 탈퇴. 담당 회원에게 알린 뒤 계정을 지운다. (#505)

    **담당 회원이 남아 있어도 막지 않는다.** 막으면 담당이 있는 트레이너는 계정을
    영영 지울 수 없고, 그만두는 사람에게 "회원을 먼저 다 정리하라" 고 요구하는 것은
    현실적이지 않다. 대신 회원이 모르게 사라지지 않도록 알림을 남긴다 — 회원 앱의
    '내 담당 코치'가 어느 날 조용히 비어 있으면 앱이 고장 난 것으로 읽힌다.

    삭제 순서가 중요하다. `trainer_reservations` 는 회원·슬롯·일정을 모두
    **RESTRICT** 로 참조한다. 슬롯과 일정은 트레이너 삭제 시 CASCADE 로 지워지므로,
    예약 행을 먼저 치우지 않으면 그 CASCADE 가 FK 에서 막힌다.

    나머지(프로필·채팅·루틴·일정·슬롯·이력·알림)는 `users.id` CASCADE 가 처리한다.
    상담 요청의 `trainer_id`·`decided_by` 는 SET NULL 이라 요청 이력은 남는다.
    """
    member_ids = list(
        db.scalars(
            select(TrainerClient.member_id).where(
                TrainerClient.trainer_id == trainer.id
            )
        ).all()
    )

    # 이 트레이너의 슬롯에 걸린 예약을 먼저 치운다. 좌석을 되돌릴 필요는 없다 —
    # 슬롯 자체가 함께 사라진다.
    reservations = db.scalars(
        select(TrainerReservation)
        .join(
            TrainerReservationSlot,
            TrainerReservationSlot.id == TrainerReservation.slot_id,
        )
        .where(TrainerReservationSlot.trainer_id == trainer.id)
        .order_by(TrainerReservation.id)
        .with_for_update()
    ).all()
    booked_member_ids = {row.member_id for row in reservations}
    for reservation in reservations:
        db.delete(reservation)
    # RESTRICT 자식을 먼저 비운 뒤에야 트레이너 삭제의 CASCADE 가 성립한다.
    db.flush()

    # 지금 담당 중인 회원의 PT 재등록 쿠폰은 쓸 트레이너가 사라지므로 취소하고
    # 포인트를 돌려준다(#1787). 과거 담당(휴면 링크) 회원은 이미 해제 때 처리됐다.
    active_member_ids = db.scalars(
        select(TrainerClient.member_id).where(
            TrainerClient.trainer_id == trainer.id,
            TrainerClient.active.is_(True),
        )
    ).all()
    for member_id in active_member_ids:
        points_coupon_service.cancel_renewal_coupons(db, member_id)

    trainer_name = trainer.name or "트레이너"
    for member_id in member_ids:
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.TRAINER_MESSAGE,
            # 새 트레이너를 찾는 화면으로 보낸다.
            category=notification_service.MEMBER_CONSULTATION,
            title="담당 트레이너 연결이 해제되었어요",
            body=f"{trainer_name} 트레이너가 서비스를 떠났습니다. 새 트레이너를 찾아보세요.",
        )
    # 예약만 있고 담당은 아닌 회원에게도 알린다 — 잡아 둔 수업이 사라진다.
    for member_id in booked_member_ids - set(member_ids):
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.TRAINER_MESSAGE,
            category=notification_service.MEMBER_SCHEDULE,
            title="예약한 수업이 취소되었어요",
            body=f"{trainer_name} 트레이너가 서비스를 떠나 예약이 취소되었습니다.",
        )

    db.delete(trainer)
    db.commit()


#: 배정 행의 검토 상태. AI 후보는 pending 으로 들어와 트레이너 판단을 기다린다.
#:
#: 기본이 approved 인 이유는 하위 호환이다 — 이 값이 생기기 전의 배정은 모두
#: 트레이너가 보낸 것이므로 그대로 회원에게 보여야 한다.
ROUTINE_APPROVED = "approved"
ROUTINE_PENDING = "pending"
#: PT 일정에 붙여 두었고 아직 회원에게 보내지 않은 개인운동(#2223). 회원에게
#: 가는 것은 그 PT 를 완료할 때다(#2224). `pending` 과 나눠 두는 이유는 저쪽이
#: **트레이너가 승인할지 판단할 후보**라는 것이다 — 이쪽은 이미 정해진 운동이고,
#: 제안 검토 목록에 섞이면 트레이너가 같은 운동을 두 번 검토하게 된다.
ROUTINE_SCHEDULED = "scheduled"
ROUTINE_DISMISSED = "dismissed"
ROUTINE_STATUSES = frozenset(
    {ROUTINE_APPROVED, ROUTINE_PENDING, ROUTINE_SCHEDULED, ROUTINE_DISMISSED}
)

#: 전송 종류(#2223, #2225). 개인운동 행에 남겨 이력이 "무엇과 함께 갔는지" 를
#: 말할 수 있게 한다.
DELIVERY_PT_WITH_ROUTINE = "pt_with_routine"
DELIVERY_ROUTINE_ONLY = "routine_only"
DELIVERY_CANCELLED_ROUTINE_ONLY = "cancelled_routine_only"


def routine_active_on(day: date):
    """[day] 에 회원 목록에 걸려 있던 개인운동을 고르는 조건. (#2161)

    추천 개인운동은 매일 새로 체크하는 목록이다. 트레이너가 바꾸기 전까지 같은
    목록이 날마다 되풀이되므로, 어느 날의 목록은 "그날 걸려 있던 배정" 이다 —
    `active_from` 은 그날을 포함하고 `ended_on` 은 그날부터 없다.
    """
    iso = day.isoformat()
    return (
        TrainerRoutine.active_from <= iso,
        or_(TrainerRoutine.ended_on.is_(None), TrainerRoutine.ended_on > iso),
    )


def _completion_on(day: date):
    """[day] 하루의 배정 완료 기록을 고르는 조건. (#2161)

    운동 기록의 날짜는 `(week_start, day_label)` 이다. 완료는 배정 하나당 하루
    한 번이라(`uq_exercise_sessions_routine_day`) 이 조건과 배정 id 가 곧 한 행을
    가리킨다.
    """
    iso = day.isoformat()
    return (
        ExerciseSession.week_start == exercise_service.monday_of_str(iso),
        ExerciseSession.day_label == exercise_service.weekday_label_of(iso),
    )


def build_routines(
    db: Session,
    member_id: str,
    trainer_id: str | None,
    *,
    for_member: bool = False,
    day: date | None = None,
) -> list[RoutineOut]:
    """이 트레이너가 회원에게 배정한 루틴(정렬순) — [day] 에 걸려 있던 것과 그날 완료.

    [day] 를 주지 않으면 오늘이다. 추천 개인운동은 매일 미완료로 다시 시작하므로
    `completed` 는 **그날** 완료했는가다(#2161). 어제 한 운동이 오늘 체크된 채로
    보이지 않는다.

    [trainer_id] 가 None 이면 트레이너 없이 만들어진 자동 추천을 읽는다 —
    SQLAlchemy 가 `== None` 을 `IS NULL` 로 옮기므로 조건은 그대로 쓴다.

    [for_member] 는 이 목록이 회원에게 가는지를 말한다. 회원용이면 제안의 근거를
    싣지 않는다 — 트레이너의 판단 재료이기 때문이다(#790).

    한 프로그램의 세션들은 `sort_order` 를 연속으로 받으므로 이 정렬만으로
    세션 순서가 지켜진다 — 별도 그룹핑 없이 배열 순서가 곧 프로그램 순서다.
    """
    day = day or clock.today()
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            # 검토를 기다리는 후보와 거절된 후보는 '배정된 루틴'이 아니다.
            # 회원 화면은 물론 트레이너의 배정 목록에도 섞이면 안 된다 —
            # 검토는 전용 목록(list_routine_suggestions)에서 한다(#790).
            TrainerRoutine.status == ROUTINE_APPROVED,
            *routine_active_on(day),
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.created_at)
    ).all()
    routine_ids = [row.id for row in rows]
    completed = {}
    if routine_ids:
        completed = {
            row.assigned_routine_id: row
            for row in db.scalars(
                select(ExerciseSession).where(
                    ExerciseSession.assigned_routine_id.in_(routine_ids),
                    *_completion_on(day),
                )
            ).all()
        }
    return [
        _routine_out(
            db, row, completed.get(row.id), include_evidence=not for_member
        )
        for row in rows
    ]


class RoutineNotFound(Exception):
    """루틴이 없거나 이 트레이너·회원의 것이 아니다."""


def _day_start(day: str) -> datetime | None:
    """`YYYY-MM-DD` → 그날 0시. 형식이 틀리면 None.

    이 표는 시각 없이 날짜만 들고 있다. 받는 쪽은 시각을 버리고 날짜만 보므로
    (`historyInRange`) 0시로 세워도 뜻이 달라지지 않는다.
    """
    try:
        return datetime.fromisoformat(f"{day}T00:00:00")
    except ValueError:
        return None


def _owned_routine(
    db: Session,
    trainer_id: str | None,
    member_id: str,
    routine_id: str,
    *,
    include_ended: bool = False,
) -> TrainerRoutine:
    """이 트레이너가 이 회원에게 배정한 루틴. 아니면 [RoutineNotFound]. (#504)

    trainer_id 까지 조건에 넣는 이유: 한 회원이 여러 트레이너를 거쳐 왔을 수 있고,
    그때 남의 배정을 고칠 수 있으면 안 된다. 없는 것과 남의 것을 구분하지 않는
    것도 의도다 — 라우터가 둘 다 404 로 돌려 존재 여부를 드러내지 않는다.

    철회해 목록에서 내려온 배정(`ended_on`)도 없는 것으로 본다(#2161). 예전에는
    철회가 행을 지웠으니 같은 답이다. [include_ended] 는 오늘 이미 끝낸 완료를
    되돌릴 때처럼, 내려온 배정에 남은 기록을 다뤄야 하는 경우에만 켠다.
    """
    routine = db.scalar(
        select(TrainerRoutine).where(
            TrainerRoutine.id == routine_id,
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    )
    if routine is None or (not include_ended and _has_ended(routine)):
        raise RoutineNotFound("루틴을 찾을 수 없습니다.")
    return routine


def _has_ended(routine: TrainerRoutine) -> bool:
    """오늘 목록에 이미 없는 배정인가. (#2161)"""
    return routine.ended_on is not None and routine.ended_on <= clock.today_iso()


def _end_routine(db: Session, routine: TrainerRoutine) -> None:
    """배정을 오늘부터 목록에서 내린다 — 행은 지우지 않는다. (#2161)

    지난 날짜 화면은 그날 걸려 있던 목록과 완료 여부를 그대로 보여 준다. 행을
    지우면 그 목록이 통째로 사라져, 회원이 했던 날도 "아무것도 없었던 날" 이 된다.

    승인 전 후보·거절한 후보는 회원 목록에 걸린 적이 없으니 남길 날이 없다 —
    예전처럼 행째 지운다. 남겨 두면 검토 대기 목록에 철회한 후보가 섞인다.
    """
    if routine.status != ROUTINE_APPROVED:
        db.delete(routine)
        return
    routine.ended_on = max(clock.today_iso(), routine.active_from)


def update_routine(
    db: Session, trainer_id: str, member_id: str, routine_id: str,
    fields: dict,
) -> RoutineOut:
    """배정한 루틴을 고친다. 보낸 필드만 반영한다. (#504)

    **알림을 보내지 않는다.** 배정 알림이 오간 뒤 정정 알림까지 겹치면 회원
    알림함이 같은 루틴으로 채워진다. 회원 앱은 목록을 다시 읽을 때 고쳐진 값을
    본다.

    `sort_order` 는 건드리지 않는다 — 순서 변경은 별도 기능이고(범위 밖),
    수정하다 순서가 밀리면 회원이 보는 목록이 이유 없이 흔들린다.
    """
    routine = _owned_routine(db, trainer_id, member_id, routine_id)
    for field in ("name", "minutes", "type", "reason"):
        if field in fields:
            setattr(routine, field, fields[field])
    db.commit()
    db.refresh(routine)
    completion = db.scalar(
        select(ExerciseSession).where(
            ExerciseSession.assigned_routine_id == routine.id,
            *_completion_on(clock.today()),
        )
    )
    return _routine_out(db, routine, completion)


def delete_routine(
    db: Session, trainer_id: str, member_id: str, routine_id: str
) -> None:
    """배정한 루틴을 철회한다. 회원 앱에서도 사라진다. (#504)

    남은 루틴의 `sort_order` 는 다시 매기지 않는다. 정렬은 값의 크기 순서만
    쓰므로 중간이 비어도 순서가 유지되고, 다시 매기면 그 회원의 모든 루틴 행을
    건드려 동시에 배정 중인 요청과 부딪힌다.

    지난 기록(`routine_history`)은 건드리지 않는다 — 이미 수행한 운동의 이력이지
    배정의 일부가 아니다.

    행을 지우지 않고 오늘부터 목록에서 내린다(#2161). 회원의 지난 날짜 화면이
    그날 걸려 있던 목록을 되살려야 하기 때문이다. 두 번 철회하면 두 번째는
    404 다 — 예전처럼 이미 없는 배정이다.
    """
    routine = _owned_routine(db, trainer_id, member_id, routine_id)
    _end_routine(db, routine)
    db.commit()


class RoutineNotCancellable(Exception):
    """담당 트레이너가 배정한 루틴을 회원이 직접 지우려 했다. (#1020)"""


def delete_own_routine(db: Session, member_id: str, routine_id: str) -> None:
    """회원이 자기 개인 운동을 지운다. **담당 트레이너가 없을 때만.** (#1020)

    트레이너가 배정한 것을 회원이 조용히 없애면, 다음 상담에서 둘이 서로 다른
    기록을 보게 된다. 담당이 있는 회원에게는 취소가 트레이너의 일이다.

    담당 없이 AI 가 직접 추천한 개인운동(#782)은 승인할 사람이 없으므로 회원이
    스스로 물릴 수 있어야 한다 — 그러지 않으면 한 번 뜬 추천을 지울 방법이 없다.

    이미 수행한 기록은 남는다. 지우는 것은 **배정**이지 한 일이 아니다.
    """
    if get_member_trainer_id(db, member_id) is not None:
        raise RoutineNotCancellable(
            "담당 트레이너가 배정한 개인운동은 회원이 직접 취소할 수 없습니다."
        )
    routine = db.scalar(
        select(TrainerRoutine).where(
            TrainerRoutine.id == routine_id,
            TrainerRoutine.member_id == member_id,
        )
    )
    if routine is None or _has_ended(routine):
        raise RoutineNotFound("루틴을 찾을 수 없습니다.")
    # 트레이너 철회와 같다 — 지난 날짜에 걸려 있던 목록은 남긴다(#2161).
    _end_routine(db, routine)
    db.commit()


def _routine_out(
    db: Session,
    rt: TrainerRoutine,
    completion: ExerciseSession | None = None,
    *,
    include_evidence: bool = True,
) -> RoutineOut:
    """루틴 한 건의 응답.

    [include_evidence] 를 끄면 근거를 싣지 않는다 — 회원에게 가는 응답이다.
    근거(`최근 근력운동 비중 높음`)는 트레이너가 승인 여부를 판단하는 재료이지
    회원이 읽을 문구가 아니다. 화면이 감추는 것과 응답에 담지 않는 것은 다르다
    (#790).

    `db` 를 받는 이유는 예상 소모 칼로리 때문이다(#1312). 이 값은 루틴 이름과
    **그 회원의 체중**에서 나오므로, 유형·시간만 보던 때와 달리 조회가 필요하다.
    트레이너 화면의 읽기 전용 미리보기와 회원 화면의 값이 같아야 하니 계산은
    회원 앱과 같은 한 곳(`exercise_service.estimate`)을 쓴다.
    """
    intensity = getattr(rt, "intensity", None) or "moderate"
    estimated = exercise_service.estimate(
        db,
        name=rt.name,
        type_=rt.type,
        minutes=rt.minutes,
        intensity=intensity,
        weight_kg=exercise_service.member_weight_kg(db, rt.member_id),
        # 목록을 그릴 때마다 루틴 수만큼 외부 호출이 일어나면 트레이너 화면이
        # 멈춘다. 이름 해석은 회원이 저장할 때 이미 캐시에 들어가므로, 여기서는
        # 표 매칭과 캐시까지만 본다.
        use_ai=False,
    )
    return RoutineOut(
        id=rt.id, name=rt.name, minutes=rt.minutes, type=rt.type,
        exercise_date=getattr(rt, "exercise_date", None),
        intensity=intensity,
        sets=getattr(rt, "sets", None),
        reps=getattr(rt, "reps", None),
        hold_seconds=getattr(rt, "hold_seconds", None),
        weight=getattr(rt, "weight", None),
        # 예상 소모 칼로리 — 트레이너가 고른 강도로 계산한다. 회원이 수행을
        # 마치면 그때의 강도로 다시 계산한 값이 운동 기록에 남는다. (#996)
        calories=estimated.calories,
        calorie_source=estimated.source,
        reason=rt.reason, source=rt.source,
        program_name=rt.program_name,
        session_name=rt.session_name,
        session_order=rt.session_order,
        exercises=draft_exercises(rt.exercises_json),
        evidence=(
            suggestion_evidence(rt.evidence_json) if include_evidence else []
        ),
        completed=completion is not None,
        completed_at=completion.completed_at if completion is not None else None,
        completed_minutes=completion.minutes if completion is not None else None,
        completed_intensity=completion.intensity if completion is not None else None,
        # 개인 운동 회원 피드백은 없앴다(#1825). 응답 모양은 옛 앱을 위해 남긴다.
        member_note="",
        trainer_feedback=(
            completion.trainer_feedback if completion is not None else ""
        ),
        schedule_id=getattr(rt, "schedule_id", None),
        delivery_kind=getattr(rt, "delivery_kind", None),
        trainer_message=getattr(rt, "trainer_message", "") or "",
    )


#: 루틴의 한글 유형 → 운동 기록의 영문 코드. 옛 값도 함께 접힌다. (#996)
_ROUTINE_EXERCISE_TYPES = exercise_types.normalize



# ─────────────────────────────────── AI 개인운동 제안 검토 ───────────────────

class RoutineAlreadyReviewed(Exception):
    """이미 승인/거절된 제안을 다시 검토하려 했다."""


def create_routine_suggestion(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    name: str,
    minutes: int,
    type_: str,
    reason: str,
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
    weight: float | None = None,
    evidence: Sequence[str] | None = None,
    client_request_id: str | None = None,
) -> RoutineOut:
    """AI 개인운동 후보를 검토 대기(pending) 로 만든다.

    [assign_routine] 과 나눠 둔 이유: 배정은 회원에게 곧바로 닿는 행동이고 알림도
    나가지만, 후보는 아직 아무에게도 닿지 않는다. 알림은 승인 시점에 나간다 —
    트레이너가 보지도 않은 운동으로 회원이 먼저 알림을 받으면 안 된다(#790).
    """
    if client_request_id:
        existing = find_routine_by_client_request(
            db, trainer_id, member_id, client_request_id
        )
        if existing is not None:
            return _routine_out(db, existing)

    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order)).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    )
    rt = TrainerRoutine(
        id=f"rt-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        name=name,
        minutes=minutes,
        type=type_,
        # 세트·횟수·중량은 근력에만 남긴다 — 배정([assign_routine])과 같은
        # 규칙이다. 승인하면 이 행이 그대로 배정이 되므로 여기서 규칙이 갈리면
        # 승인 전후로 값이 달라진다. (#1321)
        sets=sets if type_ == "근력" else None,
        # 버티는 운동이면 초가 맞고 횟수는 비운다 — 한 세트를 두 단위로 적지
        # 않는다(#1969).
        reps=reps if type_ == "근력" and hold_seconds is None else None,
        hold_seconds=hold_seconds if type_ == "근력" else None,
        weight=round(weight, 1) if weight is not None and type_ == "근력" else None,
        reason=reason,
        source="ai",
        status=ROUTINE_PENDING,
        sort_order=(max_order or 0) + 1,
        evidence_json=json.dumps(list(evidence or []), ensure_ascii=False),
        client_request_id=client_request_id,
        created_at=clock.now(),
    )
    db.add(rt)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = find_routine_by_client_request(
                db, trainer_id, member_id, client_request_id
            )
            if existing is not None:
                return _routine_out(db, existing)
        raise
    db.commit()
    db.refresh(rt)
    return _routine_out(db, rt)


def list_routine_suggestions(
    db: Session, trainer_id: str, member_id: str
) -> list[RoutineOut]:
    """검토를 기다리는 AI 개인운동 제안. 승인·거절한 것은 빠진다.

    조회 자리에서 그날 후보를 준비한다(`routine_suggestion_service`). 트레이너가
    회원을 골라 생성을 요청해야만 후보가 생기면 관리 부담이 줄지 않는다 — AI 가
    먼저 준비하고 트레이너는 판단만 하는 것이 이 기능의 요구다(#790). 회원 조회가
    자동 추천을 준비하는 것(`build_member_routines`)과 같은 방식이다.
    """
    routine_suggestion_service.ensure_suggestions(db, trainer_id, member_id)
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == ROUTINE_PENDING,
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.created_at)
    ).all()
    return [_routine_out(db, row) for row in rows]


def _pending_suggestion(
    db: Session, trainer_id: str, suggestion_id: str
) -> TrainerRoutine:
    """검토할 수 있는 제안 하나. 남의 것·없는 것은 [RoutineNotFound].

    이미 처리된 제안은 [RoutineAlreadyReviewed] 로 나눈다 — 없는 것과 같은 답을
    주면, 두 번 눌렀을 때 트레이너가 "사라졌다" 로 읽는다. 실제로는 이미 반영됐다.
    """
    row = db.scalar(
        select(TrainerRoutine).where(
            TrainerRoutine.id == suggestion_id,
            TrainerRoutine.trainer_id == trainer_id,
        )
    )
    if row is None:
        raise RoutineNotFound("제안을 찾을 수 없습니다.")
    if row.status != ROUTINE_PENDING:
        raise RoutineAlreadyReviewed("이미 검토한 제안입니다.")
    return row


def approve_routine_suggestion(
    db: Session,
    trainer_id: str,
    suggestion_id: str,
    *,
    name: str | None = None,
    minutes: int | None = None,
    type_: str | None = None,
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
    weight: float | None = None,
    reason: str | None = None,
) -> RoutineOut:
    """제안을 승인해 회원에게 배정한다. 준 값이 있으면 그것으로 고쳐서 승인한다.

    새 행을 만들지 않고 이 행의 상태를 바꾼다. 후보와 배정이 같은 행이라
    회원 조회·완료 처리·프로그램 묶음이 지금 쓰는 경로를 그대로 지난다.
    """
    row = _pending_suggestion(db, trainer_id, suggestion_id)
    if name is not None:
        row.name = name
    if minutes is not None:
        row.minutes = minutes
    if type_ is not None:
        row.type = type_
    if reason is not None:
        row.reason = reason
    if sets is not None:
        row.sets = sets
    if reps is not None:
        row.reps = reps
    if hold_seconds is not None:
        row.hold_seconds = hold_seconds
    if weight is not None:
        row.weight = round(weight, 1)
    # 유형을 근력이 아닌 것으로 바꿔 승인하면 세트·횟수·중량을 지운다 — 남겨
    # 두면 유산소 배정이 세트를 들고 회원에게 간다. 판단 기준은 **고친 뒤의**
    # 유형이다. (#1321)
    if row.type != "근력":
        row.sets = None
        row.reps = None
        row.hold_seconds = None
        row.weight = None
    elif row.hold_seconds is not None:
        # 버티는 운동으로 승인하면 횟수를 지운다. (#1969)
        row.reps = None
    row.status = ROUTINE_APPROVED
    row.reviewed_at = clock.now()
    row.reviewed_by = trainer_id
    # 회원 목록에는 승인한 날부터 걸린다 — 후보로 기다린 날들에는 회원이 받은
    # 적이 없다(#2161).
    row.active_from = clock.today_iso()

    # 알림은 여기서 나간다 — 회원이 볼 수 있게 된 시점이 곧 알릴 시점이다.
    notification_service.queue(
        db,
        member_id=row.member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_ROUTINE,
        title="새 운동 루틴이 배정되었어요",
        body=f"{row.name} · " + _amount_label(
            row.type, minutes=row.minutes,
            sets=row.sets, reps=row.reps, hold_seconds=row.hold_seconds,
            weight=row.weight,
        ),
    )
    db.commit()
    db.refresh(row)
    return _routine_out(db, row)


def dismiss_routine_suggestion(
    db: Session, trainer_id: str, suggestion_id: str
) -> RoutineOut:
    """제안을 추천하지 않기로 한다. 회원 배정도 알림도 만들지 않는다."""
    row = _pending_suggestion(db, trainer_id, suggestion_id)
    row.status = ROUTINE_DISMISSED
    row.reviewed_at = clock.now()
    row.reviewed_by = trainer_id
    db.commit()
    db.refresh(row)
    return _routine_out(db, row)


def complete_assigned_routine(
    db: Session,
    trainer_id: str | None,
    member_id: str,
    routine_id: str,
    *,
    minutes: int,
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
    weight: float | None = None,
    intensity: str,
) -> RoutineCompleteOut:
    """배정 하나를 **오늘의** 회원 운동 기록 한 건으로 완료한다.

    추천 개인운동은 매일 새로 체크하는 목록이라 같은 배정을 날마다 한 번씩
    완료한다(#2161). `(배정, 그날)` 유일 제약이 더블 탭·재전송을 같은 기록으로
    모은다. 이름은 스냅샷이라 이후 배정 수정·철회에 흔들리지 않는다.

    지난 날짜는 완료할 수 없다 — 날짜를 받지 않고 늘 오늘로 적는다. 지난 날짜
    화면은 그날 무엇을 했는지 보여 주는 읽기 전용이다.

    포인트를 적립하고 그 결과를 응답에 싣는다(#1786). 재전송은
    새로 적립하지 않고 처음 완료할 때 받은 값을 돌려준다.
    """
    routine = _owned_routine(db, trainer_id, member_id, routine_id)
    # 승인되지 않은 후보는 회원에게 보이지도 않는다. id 를 알아내 직접 호출해도
    # 완료로 넘어가지 않게 여기서 막는다 — 조회만 거르면 경로가 하나 남는다(#790).
    if routine.status != ROUTINE_APPROVED:
        raise RoutineNotFound("루틴을 찾을 수 없습니다.")
    completed_at = clock.now()
    today = completed_at.date()
    existing = db.scalar(
        select(ExerciseSession).where(
            ExerciseSession.assigned_routine_id == routine_id,
            *_completion_on(today),
        )
    )
    if existing is not None:
        return _completion_out(
            db, routine, existing,
            _completion_points(db, routine, member_id, existing.id, award=False),
        )

    exercise_type = _ROUTINE_EXERCISE_TYPES(routine.type)
    # 회원이 실제로 한 수를 적지 않았으면 트레이너가 배정한 값이 남는다 —
    # 근력 배정에서 세트·횟수·중량이 통째로 비면, 그래프가 분에서 세트를 되짚어
    # 트레이너도 회원도 적은 적 없는 수를 그린다. (#1276, #1310)
    sets = sets if sets is not None else getattr(routine, "sets", None)
    reps = reps if reps is not None else getattr(routine, "reps", None)
    hold_seconds = (
        hold_seconds if hold_seconds is not None
        else getattr(routine, "hold_seconds", None)
    )
    weight = weight if weight is not None else getattr(routine, "weight", None)
    # 회원이 초로 적었으면 횟수는 뜻이 없다 — 배정에 남아 있던 옛 횟수가
    # 함께 따라오면 한 세트가 두 단위로 적힌다. (#1969)
    if hold_seconds is not None:
        reps = None
    assigned_estimate = exercise_service.estimate(
        db,
        name=routine.name,
        type_=exercise_type,
        minutes=minutes,
        intensity=intensity,
        weight_kg=exercise_service.member_weight_kg(db, member_id),
    )
    row = ExerciseSession(
        id=f"assigned-ex-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        week_start=exercise_service.monday_of_str(today.isoformat()),
        day_label=exercise_service.weekday_label_of(today.isoformat()),
        type=exercise_type,
        # 배정 이름이 곧 이 운동의 이름이다 — 회원이 따로 적지 않는다.
        name=routine.name,
        minutes=minutes,
        # 세트·횟수·중량은 근력에서만 남긴다. 수기 기록과 같은 규칙이라야
        # 그래프가 두 기록을 같은 축으로 읽는다. (#1276, #1310)
        sets=sets if exercise_type == exercise_types.STRENGTH else None,
        reps=reps if exercise_type == exercise_types.STRENGTH else None,
        hold_seconds=(
            hold_seconds if exercise_type == exercise_types.STRENGTH else None
        ),
        weight=(
            round(weight, 1)
            if weight is not None and exercise_type == exercise_types.STRENGTH
            else None
        ),
        # 이름·체중이 반영된 값이다. 회원이 수기로 적은 기록과 같은 계산을 써야
        # 같은 운동이 두 경로에서 다른 칼로리로 적히지 않는다(#1312).
        calories=assigned_estimate.calories,
        calorie_source=assigned_estimate.source,
        intensity=intensity,
        source="assigned_routine",
        assigned_routine_id=routine.id,
        assigned_trainer_id=trainer_id,
        assigned_routine_name=routine.name,
        # 개인 운동 피드백은 받지 않는다(#1825) — 불편은 채팅에서 감지한다.
        member_note="",
        completed_at=completed_at,
    )
    db.add(row)
    try:
        # 적립은 기록과 같은 트랜잭션이다(#1786). 먼저 flush 해, 더블 탭이 유니크
        # 제약에 걸리는 자리를 적립보다 앞에 둔다.
        db.flush()
        points = _completion_points(db, routine, member_id, row.id, award=True)
        # 완료 기록이 보호권으로 이어 붙인 날에 떨어지면(자정 무렵 보호와 겹친 완료)
        # 그 보호권을 되돌린다(#1788).
        streak_shield_service.refund_for_record(
            db, member_id, clock.to_seoul(completed_at).date()
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = db.scalar(
            select(ExerciseSession).where(
                ExerciseSession.assigned_routine_id == routine_id,
                *_completion_on(today),
            )
        )
        if existing is None:
            raise
        return _completion_out(
            db, routine, existing,
            _completion_points(db, routine, member_id, existing.id, award=False),
        )
    db.refresh(row)
    personal_ingest.refresh_exercise(db, member_id, session_id=row.id)
    return _completion_out(db, routine, row, points)


def _completion_points(
    db: Session,
    routine: TrainerRoutine,
    member_id: str,
    session_id: str,
    *,
    award: bool,
) -> points_service.PointsResult:
    """배정 완료로 받는 포인트. (#1786)

    AI 추천 루틴이든 트레이너 배정 루틴이든 `추천·배정 운동 완료` 한 규칙으로
    적립하고, 하루 한도를 함께 쓴다 — 그래서 [routine] 의 출처를 보지 않는다.
    [award] 가 거짓이면 이미 저장된 완료가 받은 값을 읽기만 한다(재전송 응답).
    """
    rule = points_service.ROUTINE_COMPLETE
    if award:
        return points_service.award(db, member_id, rule, session_id)
    return points_service.awarded_for(db, member_id, rule, session_id)


def _completion_out(
    db: Session,
    routine: TrainerRoutine,
    completion: ExerciseSession,
    points: points_service.PointsResult,
) -> RoutineCompleteOut:
    """완료 응답 — 루틴 한 건에 이번 적립 결과를 더한다."""
    return RoutineCompleteOut(
        **_routine_out(db, routine, completion).model_dump(),
        points=PointsOut.of(points),
    )


def uncomplete_assigned_routine(
    db: Session,
    trainer_id: str | None,
    member_id: str,
    routine_id: str,
) -> RoutineOut:
    """오늘의 완료 표시를 되돌린다 — 오늘 그 배정으로 만든 운동 기록을 지운다. (#1131)

    회원이 체크를 잘못 눌렀을 때 되돌릴 방법이 없으면, 하지 않은 운동이 주간
    시간·칼로리에 영원히 남는다. 완료는 배정 하나당 하루 기록 하나라(#2161)
    지울 대상도 하나다. 지난 날짜의 완료는 건드리지 않는다 — 지난 날짜 화면은
    읽기 전용이다.

    아직 완료하지 않은 배정에 대해서는 아무 일도 하지 않고 현재 상태를 돌려준다 —
    같은 요청을 두 번 보내도 결과가 같다.
    """
    # 오늘 철회된 배정이라도 오늘 남긴 완료는 되돌릴 수 있어야 한다.
    routine = _owned_routine(
        db, trainer_id, member_id, routine_id, include_ended=True
    )
    row = db.scalar(
        select(ExerciseSession).where(
            ExerciseSession.assigned_routine_id == routine_id,
            ExerciseSession.user_id == member_id,
            *_completion_on(clock.today()),
        )
    )
    if row is None:
        return _routine_out(db, routine, None)
    session_id = row.id
    # 이 완료로 받은 포인트를 회수한다 — 기록 삭제와 같은 트랜잭션이다(#1786).
    points_service.revoke(
        db, member_id, points_service.SOURCE_EXERCISE_SESSION, session_id
    )
    db.delete(row)
    db.commit()
    # 근거 문서도 함께 지운다 — 행이 사라지면 `_load` 가 None 을 돌려준다.
    personal_ingest.refresh_exercise(db, member_id, session_id=session_id)
    return _routine_out(db, routine, None)


def update_assigned_routine_feedback(
    db: Session,
    trainer_id: str,
    member_id: str,
    history_id: str,
    feedback: str,
) -> RoutineHistoryOut:
    """활성 담당 관계가 확인된 트레이너가 자신이 배정한 기록에 피드백한다.

    API 계층은 현재 활성 담당 관계를 먼저 확인하고, 여기서는 수행 스냅샷의
    배정 트레이너까지 일치하는지 추가로 검증한다(#638).
    """
    row = db.scalar(
        select(ExerciseSession).where(
            ExerciseSession.id == history_id,
            ExerciseSession.user_id == member_id,
            ExerciseSession.source == "assigned_routine",
            ExerciseSession.assigned_trainer_id == trainer_id,
        )
    )
    if row is None:
        raise RoutineNotFound("배정 루틴 수행 기록을 찾을 수 없습니다.")
    row.trainer_feedback = feedback.strip()
    db.commit()
    db.refresh(row)
    return _assigned_history_out(row)


def _assigned_history_out(row: ExerciseSession) -> RoutineHistoryOut:
    """배정 루틴 수행을 조회·수정 응답에서 공유하는 이력 계약으로 변환한다."""
    completed_at = row.completed_at or row.created_at
    # 라벨의 날짜는 [build_client_history] 와 같은 규칙을 쓴다(#1264). 두 곳이
    # 갈리면 같은 기록이 목록과 상세에서 다른 날로 보인다.
    day = (
        exercise_activity.activity_date_of(row)
        or clock.to_seoul(completed_at).date()
    ).isoformat()
    return RoutineHistoryOut(
        id=row.id,
        date_label=history_date_label(day),
        label=row.assigned_routine_name or "배정 루틴 수행",
        completion_rate=100,
        exercises=[
            f"{row.assigned_routine_name or row.type} · "
            + _amount_label(
                row.type, minutes=row.minutes,
                sets=row.sets, reps=row.reps, hold_seconds=row.hold_seconds,
            weight=row.weight,
            )
            + f" · {row.intensity}"
        ],
        # 개인 운동 회원 피드백은 없앴다(#1825). 옛 데이터가 있어도 내려보내지 않는다.
        client_feedback="",
        trainer_note=row.trainer_feedback,
        assigned_routine_id=row.assigned_routine_id,
        completed_at=completed_at,
    )


def find_routine_by_client_request(
    db: Session, trainer_id: str, member_id: str, client_request_id: str
) -> TrainerRoutine | None:
    return db.scalar(
        select(TrainerRoutine).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.client_request_id == client_request_id,
        )
    )


def assign_routine(
    db: Session, trainer_id: str, member_id: str,
    name: str, minutes: int, type_: str, reason: str, source: str,
    client_request_id: str | None = None,
    exercise_date: date | None = None,
    intensity: str = "moderate",
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
    weight: float | None = None,
) -> RoutineOut:
    """회원에게 루틴 배정. 로스터 last_routine 은 build_roster 가 최신 루틴을 읽어 반영.

    [client_request_id] 가 오면 그 전송 시도에 대해 멱등하다. 같은 키로 다시
    호출하면 새로 만들지 않고 먼저 저장된 배정을 그대로 돌려준다 — 전송 도중
    끊겨 클라이언트가 재시도해도 회원에게 루틴이 두 번 배정되지 않는다(#581).
    """
    if client_request_id:
        existing = find_routine_by_client_request(
            db, trainer_id, member_id, client_request_id
        )
        if existing is not None:
            return _routine_out(db, existing)

    # 이 회원 루틴들의 현재 최대 sort_order + 1 로 끝에 붙인다. timestamp 방식은 시드(0..n)와
    # 의미가 섞이고, 같은 초에 배정된 둘은 순서가 비결정적이었다(리뷰 #279).
    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order))
        .where(TrainerRoutine.trainer_id == trainer_id, TrainerRoutine.member_id == member_id)
    )
    rt = TrainerRoutine(
        id=f"rt-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        name=name,
        minutes=minutes,
        type=type_,
        exercise_date=exercise_date.isoformat() if exercise_date else None,
        intensity=intensity,
        # 세트·횟수·중량은 근력에만 남긴다 — 운동 기록과 같은 규칙이다.
        # (#1276, #1310)
        sets=sets if type_ == "근력" else None,
        # 버티는 운동이면 초가 맞고 횟수는 비운다 — 한 세트를 두 단위로 적지
        # 않는다(#1969).
        reps=reps if type_ == "근력" and hold_seconds is None else None,
        hold_seconds=hold_seconds if type_ == "근력" else None,
        weight=round(weight, 1) if weight is not None and type_ == "근력" else None,
        reason=reason,
        source=source,
        sort_order=(max_order or 0) + 1,
        client_request_id=client_request_id,
        created_at=datetime.now(timezone.utc),
    )
    db.add(rt)
    # 알림을 붙이기 **전에** 삽입을 flush 한다. 같은 키의 동시 요청 둘이 나란히 위
    # 조회를 통과하면 유니크 제약이 한쪽을 막는데, 그 충돌을 여기서 잡아야 진 쪽이
    # 알림까지 중복으로 쌓지 않는다(회원이 같은 배정 알림을 두 번 받지 않는다).
    # queue() 는 내부 조회를 하므로 그때 autoflush 로 터지면 이 지점을 지나친다.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = find_routine_by_client_request(
                db, trainer_id, member_id, client_request_id
            )
            if existing is not None:
                return _routine_out(db, existing)
        raise

    # 배정은 회원이 앱을 열기 전에는 알 수 없는 변화다(#489).
    notification_service.queue(
        db,
        member_id=member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_ROUTINE,
        title="새 운동 루틴이 배정되었어요",
        body=f"{name} · " + _amount_label(
            type_, minutes=minutes, sets=sets, reps=reps,
            hold_seconds=hold_seconds, weight=weight,
        ),
    )
    db.commit()
    db.refresh(rt)
    return _routine_out(db, rt)


def _session_summary(
    exercises: Sequence[ProgramDraftExercise],
) -> tuple[int, str, str]:
    """세션 하나를 루틴 한 건의 (분, 유형, 출처)로 요약한다. (#709)

    트레이너 웹이 단일 세션을 배정할 때 쓰던 규칙과 같다 — 분은 각 운동의
    `duration` 합, 유형은 가장 많은 유형, 출처는 AI 제안이 하나라도 있으면
    'ai'. 규칙을 서버로 옮긴 것은 세션이 여러 개가 되면서 클라이언트마다
    다르게 접히는 것을 막기 위해서다.

    근력은 시간을 적지 않으므로 세트에서 환산한다 — `_program_minutes_and_type`
    과 같은 값이라야 배정과 PT 완료가 같은 분을 센다(#1276).
    """
    minutes = 0
    counts: dict[str, int] = {}
    has_ai = False
    for exercise in exercises:
        if exercise.duration:
            minutes += exercise.duration
        elif exercise.type == "근력" and exercise.sets:
            minutes += round(
                exercise.sets * exercise_service.STRENGTH_MINUTES_PER_SET
            )
        counts[exercise.type] = counts.get(exercise.type, 0) + 1
        if exercise.source == "ai":
            has_ai = True
    type_ = max(counts, key=lambda t: counts[t]) if counts else "근력"
    return minutes, type_, ("ai" if has_ai else "trainer")


def _program_request_key(base: str, index: int) -> str:
    """세션별 멱등키. 프로그램 전체가 한 번의 전송 시도이므로 같은 base 를 쓴다.

    세션마다 키를 나누는 이유는 `(trainer, member, client_request_id)` 유니크
    제약 때문이다 — 같은 키로 여러 행을 만들 수 없다.
    """
    return f"{base}#{index}"


def assign_program(
    db: Session, trainer_id: str, member_id: str, *,
    name: str,
    sessions: Sequence[ProgramDraftSession],
    client_request_id: str | None = None,
    delivery_kind: str | None = None,
    trainer_message: str = "",
    start_date: date | None = None,
    active_days: int | None = None,
) -> list[RoutineOut]:
    """다중 세션 프로그램을 회원에게 배정한다. 세션 하나가 루틴 한 건이 된다. (#709)

    세션이 하나뿐이면 예전 단일 배정과 같은 모양이다 — 루틴 이름은 프로그램
    이름이고 `session_name` 이 비어 회원 화면에 없던 세션 라벨이 생기지 않는다.
    세션이 여럿이면 루틴 이름이 세션 이름이 되고 `program_name` 이 묶는다.

    [client_request_id] 가 오면 **프로그램 전체**에 대해 멱등하다. 재시도에 같은
    키를 다시 보내면 먼저 배정된 세션들을 그대로 돌려준다 — 중간까지 저장된
    상태에서 재시도해 세션이 반쯤 겹치는 일이 없다.

    알림은 프로그램당 한 번이다. 세션마다 보내면 회원 알림함이 한 번의 배정으로
    가득 찬다.

    [delivery_kind]·[trainer_message]·[start_date] 는 프로그램 만들기의
    `개인운동만` 전송이 쓴다(#2223) — PT 없이 한 주 분량을 한 묶음으로 보내고,
    이력이 그 전송을 `개인운동만` 으로 알아볼 수 있게 종류와 한마디를 남긴다.

    [active_days] 는 **이 배정이 회원 목록에 며칠간 걸려 있는가**다. 추천
    개인운동은 매일 새로 체크하는 목록이고 그 기간은 `active_from`~`ended_on`
    이 정하므로(#2161), `개인운동만` 은 7 을 보내 보낸 날부터 한 주만 걸어
    둔다. 비우면 트레이너가 철회할 때까지 걸려 있는 기존 배정이다.
    """
    if client_request_id:
        existing = _program_routines_for_request(
            db, trainer_id, member_id, client_request_id, len(sessions)
        )
        if existing:
            return [_routine_out(db, rt) for rt in existing]

    # 단일 배정과 같은 이유로 알림보다 먼저 flush 한다 — 동시 요청이 유니크
    # 제약에 걸리면 진 쪽이 알림까지 쌓지 않아야 한다.
    try:
        created = _add_program_routines(
            db, trainer_id, member_id,
            name=name, sessions=sessions, client_request_id=client_request_id,
            delivery_kind=delivery_kind,
            trainer_message=trainer_message,
            start_date=start_date,
            active_days=active_days,
        )
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = _program_routines_for_request(
                db, trainer_id, member_id, client_request_id, len(sessions)
            )
            if existing:
                return [_routine_out(db, rt) for rt in existing]
        raise
    db.commit()
    for rt in created:
        db.refresh(rt)
    return [_routine_out(db, rt) for rt in created]


def _program_routines_for_request(
    db: Session, trainer_id: str, member_id: str, client_request_id: str,
    session_count: int,
) -> list[TrainerRoutine]:
    """그 멱등키로 이미 배정된 세션 루틴들(세션 순서대로). 없으면 빈 목록."""
    return list(
        db.scalars(
            select(TrainerRoutine)
            .where(
                TrainerRoutine.trainer_id == trainer_id,
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.client_request_id.in_(
                    [
                        _program_request_key(client_request_id, index)
                        for index in range(session_count)
                    ]
                ),
            )
            .order_by(TrainerRoutine.session_order)
        ).all()
    )


def _add_program_routines(
    db: Session, trainer_id: str, member_id: str, *,
    name: str,
    sessions: Sequence[ProgramDraftSession],
    client_request_id: str | None,
    delivery_kind: str | None = None,
    trainer_message: str = "",
    start_date: date | None = None,
    active_days: int | None = None,
) -> list[TrainerRoutine]:
    """세션 루틴과 배정 알림을 세션에 올리고 flush 한다. 커밋은 호출부 몫이다.

    커밋하지 않는 이유는 `일정 추가`(#1580) 때문이다 — 배정과 일정 등록이 한
    트랜잭션이어야 둘 중 하나만 남는 반쪽 상태가 생기지 않는다. 유니크 제약
    위반은 flush 에서 [IntegrityError] 로 올라온다.

    [active_days] 가 오면 그만큼만 회원 목록에 걸어 둔다(#2223) — 배정한 날을
    1일로 세어 `ended_on` 을 찍는다. 비우면 철회할 때까지 걸려 있다(#2161).
    """
    multi = len(sessions) > 1
    today_iso = clock.today_iso()
    ended_on = (
        (clock.today() + timedelta(days=active_days)).isoformat()
        if active_days is not None
        else None
    )
    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order)).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    ) or 0
    now = datetime.now(timezone.utc)
    created: list[TrainerRoutine] = []
    for index, session in enumerate(sessions):
        minutes, type_, source = _session_summary(session.exercises)
        rt = TrainerRoutine(
            id=f"rt-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            name=(session.name or name) if multi else name,
            minutes=minutes,
            type=type_,
            reason=", ".join(e.name for e in session.exercises)[:200],
            source=source,
            program_name=name if multi else "",
            session_name=session.name if multi else "",
            session_order=index,
            exercises_json=json.dumps(
                [e.model_dump(mode="json") for e in session.exercises],
                ensure_ascii=False,
            ),
            sort_order=max_order + index + 1,
            client_request_id=(
                _program_request_key(client_request_id, index)
                if client_request_id
                else None
            ),
            exercise_date=start_date.isoformat() if start_date else None,
            active_from=today_iso,
            ended_on=ended_on,
            delivery_kind=delivery_kind,
            trainer_message=trainer_message,
            created_at=now,
        )
        db.add(rt)
        created.append(rt)
    db.flush()

    total_minutes = sum(rt.minutes for rt in created)
    notification_service.queue(
        db,
        member_id=member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_ROUTINE,
        title="새 운동 루틴이 배정되었어요",
        body=(
            f"{name} · 세션 {len(created)}개 · {total_minutes}분"
            if multi
            else f"{name} · {total_minutes}분"
        ),
    )
    return created


# ---- 회원별 트레이너 메모 (#706) ----

class MemoNotFound(Exception):
    """그 트레이너·회원 쌍에 그 id 의 메모가 없다(라우터가 404 로 변환)."""


def _memo_out(memo: TrainerClientMemo) -> TrainerMemoOut:
    return TrainerMemoOut(
        id=memo.id,
        body=memo.body,
        source=memo.source,
        insight_id=memo.insight_id,
        insight_kind=memo.insight_kind,
        created_at=memo.created_at,
        updated_at=memo.updated_at,
    )


#: 메모 목록이 한 번에 내려주는 최대 건수. 메모는 지워지지 않고 쌓이기만 하는
#: 데이터라, 오래 쓴 계정에서 응답이 무한정 커지는 것을 막는다(알림함과 같은 이유).
_MEMO_LIMIT = 100


def build_memos(db: Session, trainer_id: str, member_id: str) -> list[TrainerMemoOut]:
    """담당 회원에 대해 내가 남긴 메모(최신 먼저, 최대 [_MEMO_LIMIT]건).

    직접 쓴 메모와 채팅 인사이트 메모를 한 목록으로 돌려준다 — 회원 상세가
    출처와 무관하게 "이 회원에 대해 남긴 기록"을 한 곳에서 보여 준다.

    같은 시각에 만들어진 둘의 순서가 흔들리지 않게 id 로 tie-break 한다.
    """
    rows = db.scalars(
        select(TrainerClientMemo)
        .where(
            TrainerClientMemo.trainer_id == trainer_id,
            TrainerClientMemo.member_id == member_id,
        )
        .order_by(TrainerClientMemo.created_at.desc(), TrainerClientMemo.id.desc())
        .limit(_MEMO_LIMIT)
    ).all()
    return [_memo_out(m) for m in rows]


def find_memo_by_insight(
    db: Session, trainer_id: str, member_id: str, insight_id: str
) -> TrainerClientMemo | None:
    return db.scalar(
        select(TrainerClientMemo).where(
            TrainerClientMemo.trainer_id == trainer_id,
            TrainerClientMemo.member_id == member_id,
            TrainerClientMemo.insight_id == insight_id,
        )
    )


def create_memo(
    db: Session, trainer_id: str, member_id: str,
    body: str, source: str = "trainer",
    insight_id: str | None = None, insight_kind: str = "",
) -> TrainerMemoOut:
    """회원 메모를 남긴다.

    [insight_id] 가 오면 그 인사이트에 대해 멱등하다 — 채팅에서 같은 신호를 다시
    저장해도 새 메모를 만들지 않고 먼저 저장된 메모를 그대로 돌려준다. 로컬
    저장 시절 `insightId` 로 중복을 막던 의미를 서버에서 그대로 유지한다.
    """
    if insight_id:
        existing = find_memo_by_insight(db, trainer_id, member_id, insight_id)
        if existing is not None:
            return _memo_out(existing)

    now = datetime.now(timezone.utc)
    memo = TrainerClientMemo(
        id=f"memo-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        body=body,
        source=source,
        insight_id=insight_id,
        insight_kind=insight_kind,
        created_at=now,
        updated_at=now,
    )
    db.add(memo)
    # 같은 insight_id 로 동시에 들어온 두 요청이 나란히 위 조회를 통과하면 유니크
    # 제약이 한쪽을 막는다. 그 충돌을 여기서 잡아 먼저 저장된 쪽을 돌려준다 —
    # 클라이언트 입장에서는 어느 쪽이 이겼든 "이미 저장된 그 메모"가 나온다.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if insight_id:
            existing = find_memo_by_insight(db, trainer_id, member_id, insight_id)
            if existing is not None:
                return _memo_out(existing)
        raise
    db.commit()
    db.refresh(memo)
    return _memo_out(memo)


def _owned_memo(
    db: Session, trainer_id: str, member_id: str, memo_id: str
) -> TrainerClientMemo:
    """내가 이 회원에 대해 남긴 메모만 집는다.

    남의 메모와 없는 메모를 똑같이 다룬다 — 존재 여부를 드러내면 id 를 훑는 것만
    으로 다른 트레이너가 메모를 남겼다는 사실을 알 수 있다.
    """
    memo = db.scalar(
        select(TrainerClientMemo).where(
            TrainerClientMemo.id == memo_id,
            TrainerClientMemo.trainer_id == trainer_id,
            TrainerClientMemo.member_id == member_id,
        )
    )
    if memo is None:
        raise MemoNotFound("메모를 찾을 수 없습니다.")
    return memo


def update_memo(
    db: Session, trainer_id: str, member_id: str, memo_id: str, fields: dict
) -> TrainerMemoOut:
    """메모 본문을 고친다. 출처(`source`/`insight_id`)는 그대로 둔다."""
    memo = _owned_memo(db, trainer_id, member_id, memo_id)
    if "body" in fields:
        memo.body = fields["body"]
    memo.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(memo)
    return _memo_out(memo)


def delete_memo(db: Session, trainer_id: str, member_id: str, memo_id: str) -> None:
    """메모를 지운다.

    비활성 플래그를 두지 않고 실제로 지운다 — 트레이너 혼자 보는 개인 메모라
    '지웠는데 서버에 남아 있는' 상태가 UX 상 의미가 없다.
    """
    memo = _owned_memo(db, trainer_id, member_id, memo_id)
    db.delete(memo)
    db.commit()


# ---- 고객 후속 관리 할 일 (#869) ----
#
# 트레이너가 고객 상태를 보다 "며칠 뒤 다시 확인할 것"을 남겨 두는 최소 업무 큐다.
# 대시보드는 오늘 처리할 목록으로, 고객 상세는 그 고객의 미완료 목록으로 읽는다.

class FollowUpTaskNotFound(Exception):
    """그 트레이너에게 그 id 의 할 일이 없다(라우터가 404 로 변환)."""


#: 할 일 목록이 한 번에 내려주는 최대 건수. 완료한 항목까지 쌓이는 데이터라
#: 오래 쓴 계정에서 응답이 무한정 커지지 않게 자른다(메모 목록과 같은 이유).
_FOLLOW_UP_LIMIT = 100


def _follow_up_out(
    task: TrainerFollowUpTask, member_name: str = ""
) -> TrainerFollowUpTaskOut:
    return TrainerFollowUpTaskOut(
        id=task.id,
        member_id=task.member_id,
        member_name=member_name,
        title=task.title,
        due_date=task.due_date,
        status=task.status,
        context_type=task.context_type,
        created_at=task.created_at,
        updated_at=task.updated_at,
        completed_at=task.completed_at,
    )


def _follow_up_rows(
    db: Session,
    trainer_id: str,
    *,
    member_id: str | None = None,
    status: str | None = None,
    due_on_or_before: str | None = None,
) -> list[tuple[TrainerFollowUpTask, str]]:
    """할 일 행과 회원 이름을 함께 읽는다.

    이름을 붙여 내려주는 까닭은 대시보드가 "누구의 할 일인가"를 함께 보여 주기
    때문이다 — 화면이 할 일마다 회원을 다시 조회하면 목록 하나에 요청이 N 번 는다.

    정렬은 예정일 오름차순이다(지난 항목이 먼저 온다). 같은 날짜 안에서는 만든
    순서를 지키고, 같은 시각에 만들어진 둘은 id 로 tie-break 해 순서가 흔들리지
    않게 한다.
    """
    stmt = (
        select(TrainerFollowUpTask, User.name)
        .join(User, User.id == TrainerFollowUpTask.member_id)
        .where(TrainerFollowUpTask.trainer_id == trainer_id)
    )
    if member_id is not None:
        stmt = stmt.where(TrainerFollowUpTask.member_id == member_id)
    if status is not None:
        stmt = stmt.where(TrainerFollowUpTask.status == status)
    if due_on_or_before is not None:
        stmt = stmt.where(TrainerFollowUpTask.due_date <= due_on_or_before)
    stmt = stmt.order_by(
        TrainerFollowUpTask.due_date.asc(),
        TrainerFollowUpTask.created_at.asc(),
        TrainerFollowUpTask.id.asc(),
    ).limit(_FOLLOW_UP_LIMIT)
    return [(task, name or "") for task, name in db.execute(stmt).all()]


def build_client_follow_ups(
    db: Session, trainer_id: str, member_id: str, *, include_completed: bool = False
) -> list[TrainerFollowUpTaskOut]:
    """그 고객에 대해 내가 남긴 후속 관리 할 일(예정일 순).

    기본은 미완료만이다 — 고객 상세가 묻는 것은 "이 고객에게 남은 일이 무엇인가"
    이고, 완료 이력까지 섞으면 남은 일이 묻힌다.
    """
    rows = _follow_up_rows(
        db,
        trainer_id,
        member_id=member_id,
        status=None if include_completed else "pending",
    )
    return [_follow_up_out(task, name) for task, name in rows]


def build_due_follow_ups(db: Session, trainer_id: str) -> list[TrainerFollowUpTaskOut]:
    """오늘까지 처리해야 할 내 미완료 할 일.

    오늘 예정과 **기한이 지난** 미완료를 함께 돌려준다 — 지난 항목을 빼면 하루만
    지나도 화면에서 사라져, 놓치지 않으려고 만든 기능이 놓치는 경로가 된다.
    지난 항목이 예정일 오름차순의 앞에 오므로 화면이 따로 가르지 않아도 위에 쌓인다.
    """
    return [
        _follow_up_out(task, name)
        for task, name in _follow_up_rows(
            db, trainer_id, status="pending", due_on_or_before=clock.today_iso()
        )
    ]


def build_open_follow_ups(db: Session, trainer_id: str) -> list[TrainerFollowUpTaskOut]:
    """예정일과 무관하게 내 미완료 할 일 전체(예정일 순)."""
    return [
        _follow_up_out(task, name)
        for task, name in _follow_up_rows(db, trainer_id, status="pending")
    ]


def _find_follow_up_by_request(
    db: Session, trainer_id: str, client_request_id: str
) -> TrainerFollowUpTask | None:
    return db.scalar(
        select(TrainerFollowUpTask).where(
            TrainerFollowUpTask.trainer_id == trainer_id,
            TrainerFollowUpTask.client_request_id == client_request_id,
        )
    )


def create_follow_up(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    title: str,
    due_date: str,
    context_type: str = "general",
    client_request_id: str | None = None,
) -> TrainerFollowUpTaskOut:
    """담당 고객에 대한 후속 관리 할 일을 등록한다.

    [client_request_id] 가 오면 그 시도에 대해 멱등하다 — 응답을 못 받고 재시도한
    등록이 같은 할 일을 두 번 만들지 않는다(스케줄 생성과 같은 규약).
    """
    if client_request_id:
        existing = _find_follow_up_by_request(db, trainer_id, client_request_id)
        if existing is not None:
            return _follow_up_out(existing, _member_name(db, existing.member_id))

    now = datetime.now(timezone.utc)
    task = TrainerFollowUpTask(
        id=f"followup-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        title=title,
        due_date=due_date,
        status="pending",
        context_type=context_type,
        client_request_id=client_request_id,
        created_at=now,
        updated_at=now,
    )
    db.add(task)
    # 같은 멱등키로 동시에 들어온 두 요청이 나란히 위 조회를 통과하면 유니크 제약이
    # 한쪽을 막는다. 그 충돌을 여기서 잡아 먼저 저장된 쪽을 돌려준다.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = _find_follow_up_by_request(db, trainer_id, client_request_id)
            if existing is not None:
                return _follow_up_out(existing, _member_name(db, existing.member_id))
        raise
    db.commit()
    db.refresh(task)
    return _follow_up_out(task, _member_name(db, member_id))


def _member_name(db: Session, member_id: str) -> str:
    return db.scalar(select(User.name).where(User.id == member_id)) or ""


def _owned_follow_up(
    db: Session, trainer_id: str, task_id: str
) -> TrainerFollowUpTask:
    """내가 만든 할 일만 집는다.

    남의 할 일과 없는 할 일을 똑같이 다룬다 — 존재 여부를 드러내면 id 를 훑는
    것만으로 다른 트레이너의 업무가 있다는 사실을 알 수 있다(메모와 같은 규약).
    """
    task = db.scalar(
        select(TrainerFollowUpTask).where(
            TrainerFollowUpTask.id == task_id,
            TrainerFollowUpTask.trainer_id == trainer_id,
        )
    )
    if task is None:
        raise FollowUpTaskNotFound("할 일을 찾을 수 없습니다.")
    return task


def update_follow_up(
    db: Session, trainer_id: str, task_id: str, fields: dict
) -> TrainerFollowUpTaskOut:
    """할 일의 내용·예정일을 고친다. 상태는 완료 경로에서만 바뀐다."""
    task = _owned_follow_up(db, trainer_id, task_id)
    if "title" in fields:
        task.title = fields["title"]
    if "due_date" in fields:
        task.due_date = fields["due_date"]
    task.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(task)
    return _follow_up_out(task, _member_name(db, task.member_id))


def complete_follow_up(
    db: Session, trainer_id: str, task_id: str
) -> TrainerFollowUpTaskOut:
    """할 일을 완료로 넘긴다.

    이미 완료된 할 일에 같은 요청이 다시 와도 성공으로 돌려준다 — 대시보드에서
    두 번 눌렀거나 응답을 못 받고 재시도한 경우이고, 그때 409 를 주면 화면은
    이미 사라진 항목에 대해 오류를 띄운다. 완료 시각은 처음 한 번만 찍는다.
    """
    task = _owned_follow_up(db, trainer_id, task_id)
    if task.status != "completed":
        now = datetime.now(timezone.utc)
        task.status = "completed"
        task.completed_at = now
        task.updated_at = now
        db.commit()
        db.refresh(task)
    return _follow_up_out(task, _member_name(db, task.member_id))


# ---- 프로그램 초안 (#708) ----

class ProgramDraftNotFound(Exception):
    """그 트레이너에게 그 id 의 초안이 없다(라우터가 404 로 변환)."""


#: 근거 문구 하나의 길이 상한. 스키마
#: (`RoutineSuggestionCreateRequest.evidence`)와 같은 값이다 — 예전 행이나 손으로
#: 고친 값이 화면 한 줄을 넘기지 않게 읽는 쪽에서도 자른다.
_EVIDENCE_MAX_LEN = 40

#: 한 제안이 들고 다니는 근거 수 상한. 스키마와 같은 값이다.
_EVIDENCE_MAX_ITEMS = 4


def suggestion_evidence(evidence_json: str) -> list[str]:
    """제안의 근거 문구를 읽는다. 깨진 값이면 빈 목록이다. (#790)

    `draft_exercises` 와 같은 이유로 관대하다 — 근거 하나가 이상해서 제안 카드
    자체가 안 뜨면, 트레이너는 검토할 것이 있는지조차 알 수 없다.
    """
    try:
        raw = json.loads(evidence_json) if evidence_json else []
    except json.JSONDecodeError:
        return []
    if not isinstance(raw, list):
        return []
    return [
        item.strip()[:_EVIDENCE_MAX_LEN]
        for item in raw[:_EVIDENCE_MAX_ITEMS]
        if isinstance(item, str) and item.strip()
    ]


def draft_exercises(exercises_json: str) -> list[ProgramDraftExercise]:
    """저장된 운동 목록을 읽는다. 깨진 항목이 목록 전체를 막지 않는다.

    스키마가 거른 값만 저장되지만, 손으로 고쳤거나 예전 형식이 남은 항목 하나
    때문에 초안을 아예 못 여는 편이 더 나쁘다 — 읽을 수 있는 항목만 돌려준다.
    """
    try:
        raw = json.loads(exercises_json) if exercises_json else []
    except json.JSONDecodeError:
        return []
    return _validated_exercises(raw)


def _validated_exercises(raw: object) -> list[ProgramDraftExercise]:
    if not isinstance(raw, list):
        return []
    out: list[ProgramDraftExercise] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            out.append(ProgramDraftExercise.model_validate(item))
        except ValidationError:
            continue
    return out


def draft_sessions(sessions_json: str) -> list[ProgramDraftSession]:
    """저장된 세션 목록을 순서 그대로 읽는다. (#709)

    운동과 같은 이유로 관대하다 — 읽을 수 없는 세션 하나가 프로그램 전체를
    못 열게 만들면 안 된다.
    """
    try:
        raw = json.loads(sessions_json) if sessions_json else []
    except json.JSONDecodeError:
        return []
    if not isinstance(raw, list):
        return []
    out: list[ProgramDraftSession] = []
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            continue
        out.append(
            ProgramDraftSession(
                id=str(item.get("id") or f"session-{index + 1}"),
                name=str(item.get("name") or ""),
                exercises=_validated_exercises(item.get("exercises")),
            )
        )
    return out


def dump_draft_sessions(sessions: Sequence[ProgramDraftSession]) -> str:
    # mode="json" 이라야 날짜가 문자열로 나간다 — 파이썬 date 는 json 이 모른다.
    return json.dumps(
        [session.model_dump(mode="json") for session in sessions], ensure_ascii=False
    )


def _draft_out(draft: TrainerProgramDraft) -> TrainerProgramDraftOut:
    return TrainerProgramDraftOut(
        id=draft.id,
        name=draft.name,
        goal=draft.goal,
        period=draft.period,
        memo=draft.memo,
        sessions=draft_sessions(draft.sessions_json),
        created_at=draft.created_at,
        updated_at=draft.updated_at,
    )


#: 목록이 한 번에 내려주는 최대 초안 수. 초안은 지우지 않으면 쌓이기만 한다.
_PROGRAM_DRAFT_LIMIT = 100


def build_program_drafts(
    db: Session, trainer_id: str
) -> list[TrainerProgramDraftSummary]:
    """내가 저장한 프로그램 초안 목록(최근 수정 먼저).

    세션·운동 구성은 싣지 않는다 — 목록은 "무엇을 저장해 뒀나"만 보여 주고,
    편집기로 불러올 때 상세를 따로 읽는다.
    """
    rows = db.scalars(
        select(TrainerProgramDraft)
        .where(TrainerProgramDraft.trainer_id == trainer_id)
        .order_by(
            TrainerProgramDraft.updated_at.desc(), TrainerProgramDraft.id.desc()
        )
        .limit(_PROGRAM_DRAFT_LIMIT)
    ).all()
    out: list[TrainerProgramDraftSummary] = []
    for d in rows:
        sessions = draft_sessions(d.sessions_json)
        out.append(
            TrainerProgramDraftSummary(
                id=d.id,
                name=d.name,
                goal=d.goal,
                period=d.period,
                session_count=len(sessions),
                exercise_count=sum(len(s.exercises) for s in sessions),
                updated_at=d.updated_at,
            )
        )
    return out


def _owned_draft(
    db: Session, trainer_id: str, draft_id: str
) -> TrainerProgramDraft:
    """내가 저장한 초안만 집는다. 남의 초안과 없는 초안은 똑같이 404 다."""
    draft = db.scalar(
        select(TrainerProgramDraft).where(
            TrainerProgramDraft.id == draft_id,
            TrainerProgramDraft.trainer_id == trainer_id,
        )
    )
    if draft is None:
        raise ProgramDraftNotFound("저장된 프로그램을 찾을 수 없습니다.")
    return draft


def get_program_draft(
    db: Session, trainer_id: str, draft_id: str
) -> TrainerProgramDraftOut:
    return _draft_out(_owned_draft(db, trainer_id, draft_id))


def create_program_draft(
    db: Session, trainer_id: str, *,
    name: str, goal: str, period: str, memo: str,
    sessions: Sequence[ProgramDraftSession],
) -> TrainerProgramDraftOut:
    """프로그램 초안을 저장한다. 세션은 받은 순서 그대로 남는다."""
    now = datetime.now(timezone.utc)
    draft = TrainerProgramDraft(
        id=f"pgm-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        name=name,
        goal=goal,
        period=period,
        memo=memo,
        sessions_json=dump_draft_sessions(sessions),
        created_at=now,
        updated_at=now,
    )
    db.add(draft)
    db.commit()
    db.refresh(draft)
    return _draft_out(draft)


def update_program_draft(
    db: Session, trainer_id: str, draft_id: str, fields: dict
) -> TrainerProgramDraftOut:
    """저장된 초안을 고친다. 보낸 필드만 반영한다.

    `sessions` 는 통째로 교체한다 — 편집기가 항목 단위 diff 가 아니라 현재
    구성 전체를 들고 있다.
    """
    draft = _owned_draft(db, trainer_id, draft_id)
    for field in ("name", "goal", "period", "memo"):
        if field in fields:
            setattr(draft, field, fields[field])
    if "sessions" in fields:
        draft.sessions_json = dump_draft_sessions(
            [
                item
                if isinstance(item, ProgramDraftSession)
                else ProgramDraftSession.model_validate(item)
                for item in fields["sessions"]
            ]
        )
    draft.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(draft)
    return _draft_out(draft)


def delete_program_draft(db: Session, trainer_id: str, draft_id: str) -> None:
    """저장된 초안을 지운다. 배정된 루틴·스케줄은 건드리지 않는다 —
    초안에서 만들어진 뒤로는 서로 독립적인 데이터다."""
    draft = _owned_draft(db, trainer_id, draft_id)
    db.delete(draft)
    db.commit()


# ---- 스케줄 (트레이너 타임라인 + 예약→수업→기록 완료 루프) ----

#: `TrainerSchedule.status` 에 저장되는 계약값. 화면 문구처럼 보이지만 DB 에 그대로
#: 들어가고 앱(`ScheduleStatus`)도 이 문자열로 거른다 — 번역하거나 표기 체계를
#: 갈아 끼우면 기존 행이 어느 질의에도 걸리지 않는다.
SCHEDULE_UPCOMING = "예정"
SCHEDULE_DONE = "완료"
SCHEDULE_CANCELLED = "취소"
SCHEDULE_NO_SHOW = "노쇼"
SCHEDULE_GAP = "공백"

#: 더 이상 진행 상태가 바뀌지 않는 상태들. 여기 들어간 세션은 수정·완료·재취소가
#: 막힌다 — 완료된 PT 를 나중에 취소로 바꾸거나 취소한 PT 를 완료로 되돌리면
#: 이미 파생된 기록(운동 기록·이행률)과 어긋난다. (#871)
SCHEDULE_TERMINAL = frozenset(
    {SCHEDULE_DONE, SCHEDULE_CANCELLED, SCHEDULE_NO_SHOW}
)

#: 취소 주체. 트레이너 사정의 취소를 회원의 미이행으로 읽지 않으려면 남아야 한다.
CANCELLATION_SOURCES = frozenset({"member", "trainer", "other"})


class ScheduleError(ValueError):
    """스케줄 도메인 오류(라우터가 400 으로 변환)."""


class ScheduleConflict(Exception):
    """완료 세션 수정 등 상태 충돌(라우터가 409 로 변환)."""


def _program_items(program_json: str) -> list[ProgramItem]:
    try:
        raw = json.loads(program_json) if program_json else []
    except json.JSONDecodeError:
        raw = []
    out: list[ProgramItem] = []
    for m in raw:
        if not isinstance(m, dict):
            continue
        out.append(ProgramItem(
            name=str(m.get("name", "") or "-"),
            # 세트·횟수·중량·시간은 예전에 자유 문자열로 저장됐다.
            # LooseInt/LooseFloat 가 "10회"·"20kg" 에서 숫자를 되짚어 준다
            # (#1276, #1310).
            sets=m.get("sets"),
            reps=m.get("reps"),
            hold_seconds=m.get("hold_seconds"),
            weight=m.get("weight"),
            duration=m.get("duration"),
            date=m.get("date"),
            intensity=m.get("intensity") or "moderate",
            # 이 키가 없는 예전 행은 세션 구분 없는 목록으로 그대로 읽힌다(#709).
            session=str(m.get("session", "") or ""),
            # 이 키가 없는 예전 행은 기본값으로 읽힌다(#1233).
            type=m.get("type") or "근력",
        ))
    return out


def _program_item_label(item: ProgramItem) -> str:
    """이력 목록에 적히는 한 줄. 근력은 세트·횟수·중량, 나머지는 시간으로 읽는다.

    유형마다 재는 단위가 다르다(#1276) — 근력을 "30분"으로 적으면 트레이너가
    다음 무게를 정할 근거가 사라지고, 유산소를 "3세트"로 적으면 뜻이 없다.
    """
    if item.type == "근력":
        parts = [f"{item.sets}세트"] if item.sets else []
        # 버티는 운동은 회가 아니라 초로 읽는다 — `플랭크 3세트 60초`. 둘은
        # 배타라 한 줄에 함께 서지 않는다. (#1969)
        if item.hold_seconds:
            parts.append(f"{item.hold_seconds}초")
        elif item.reps:
            parts.append(f"{item.reps}회")
        # 맨몸 운동은 `0kg` 이다 — 두 앱의 중량 칸은 비울 수 없어(최솟값 0)
        # 근력이면 언제나 값을 하나 든다. 값이 아예 없는 것은 이 규칙이 서기
        # 전에 저장된 행뿐이라, 그때만 자리를 비운다.
        if item.weight is not None:
            parts.append(f"{item.weight:g}kg")
    else:
        parts = [f"{item.duration}분"] if item.duration else []
    return " ".join([item.name, *parts])


def _amount_label(
    type_: str,
    *,
    minutes: int,
    sets: int | None,
    reps: int | None,
    weight: float | None,
    hold_seconds: int | None = None,
) -> str:
    """운동 한 줄이 말하는 **양**. 근력은 세트·횟수·중량, 나머지는 시간이다.

    `_program_item_label` 과 같은 규칙이고(#1276), 프로그램이 아니라 배정 한 건을
    다루는 자리(알림 본문·배정 수행 이력)가 쓴다. 예전에는 그 두 곳이 유형과
    무관하게 `분` 으로 적어, 근력을 배정받은 회원의 알림이 `스쿼트 · 15분` 이라고
    말했다 — 무엇을 몇 번 하라는 것인지가 빠진 문장이다.

    근력인데 세트가 아예 없는 것은 이 칸이 생기기 전의 배정뿐이라, 그때만
    예전처럼 분으로 되돌아간다.

    유형은 두 어휘로 들어온다 — 트레이너 배정은 한글(`근력`), 회원 기록은 영문
    코드(`strength`)다. 한쪽만 보면 다른 쪽이 조용히 분으로 떨어지므로 정규화해서
    비교한다.
    """
    if exercise_types.normalize(type_) != exercise_types.STRENGTH or sets is None:
        return f"{minutes}분"
    parts = [f"{sets}세트"]
    # 버티는 운동은 초로 읽는다 — `플랭크 · 3세트 · 60초`. (#1969)
    if hold_seconds:
        parts.append(f"{hold_seconds}초")
    elif reps:
        parts.append(f"{reps}회")
    # 맨몸 운동은 `0kg` 이다 — 중량 칸을 비울 수 없으므로 0 도 적은 값이다.
    if weight is not None:
        parts.append(f"{weight:g}kg")
    return " · ".join(parts)


def _program_minutes_and_type(
    items: Sequence[ProgramItem],
) -> tuple[int, str | None]:
    """프로그램 항목들을 (총 분, 가장 많은 유형)으로 요약한다. (#1233)

    `_session_summary` 와 같은 규칙이다 — 분은 각 항목 `duration` 의 합,
    유형은 가장 많은 유형. 항목이 하나도 없으면 유형은 None 이라 호출부가
    기존 폴백(세션 유형 고정값)을 쓸 수 있다.

    근력 항목은 시간을 적지 않으므로 세트에서 환산한다 — 회원 기록이 세트를
    분으로 되짚는 것과 같은 값(세트당 3분)이라야 두 집계가 어긋나지 않는다.
    """
    minutes = 0
    counts: dict[str, int] = {}
    for item in items:
        if item.duration:
            minutes += item.duration
        elif item.type == "근력" and item.sets:
            minutes += round(item.sets * exercise_service.STRENGTH_MINUTES_PER_SET)
        counts[item.type] = counts.get(item.type, 0) + 1
    type_ = max(counts, key=lambda t: counts[t]) if counts else None
    return minutes, type_


def _schedule_out(s: TrainerSchedule) -> ScheduleSessionOut:
    return ScheduleSessionOut(
        id=s.id, date=s.date, time=s.time, client_name=s.client_name,
        type=s.type, duration_minutes=s.duration_minutes, status=s.status,
        note=s.note, program=_program_items(s.program_json),
        program_sent=s.program_sent_at is not None,
        cancelled_at=s.cancelled_at,
        cancellation_source=s.cancellation_source,
        cancellation_reason=s.cancellation_reason,
        no_show_at=s.no_show_at,
    )


def build_schedule(db: Session, trainer_id: str, day: str) -> list[ScheduleSessionOut]:
    """하루 타임라인(시간순, 공백 포함)."""
    return build_schedule_range(db, trainer_id, day, day)


def build_client_schedule(
    db: Session, trainer_id: str, member_id: str
) -> list[ScheduleSessionOut]:
    """한 고객의 전체 세션(날짜→시간 순), 기간 제한 없이.

    고객 상세의 루틴 이력이 쓴다. 넓은 날짜 구간으로 흉내내면 그 구간보다
    오래된 기록이 조용히 빠지고, 화면은 그걸 '기록 없음'으로 읽는다.
    행 수는 트레이너-고객 한 쌍의 세션 수라 자연히 작다.
    """
    rows = db.scalars(
        select(TrainerSchedule)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
        )
        .order_by(
            TrainerSchedule.date, TrainerSchedule.time, TrainerSchedule.sort_order
        )
    ).all()
    return [_schedule_out(s) for s in rows]


def build_schedule_range(
    db: Session,
    trainer_id: str,
    from_day: str,
    to_day: str,
    member_id: str | None = None,
) -> list[ScheduleSessionOut]:
    """[from_day, to_day] 구간의 슬롯을 날짜→시간 순으로.

    주 캘린더가 7일치를 한 번에 읽기 위한 것 — 하루짜리 조회를 요일마다
    반복하면 요청이 7배가 된다. `YYYY-MM-DD` 는 사전식 정렬이 곧 날짜순이라
    문자열 범위 비교로 충분하다.

    [member_id] 를 주면 그 고객의 세션만 (공백 슬롯은 자연히 빠진다 —
    배정된 회원이 없으므로).
    """
    conditions = [
        TrainerSchedule.trainer_id == trainer_id,
        TrainerSchedule.date >= from_day,
        TrainerSchedule.date <= to_day,
        or_(
            TrainerSchedule.member_id.is_(None),
            exists(
                select(TrainerClient.id).where(
                    TrainerClient.trainer_id == trainer_id,
                    TrainerClient.member_id == TrainerSchedule.member_id,
                    TrainerClient.active.is_(True),
                )
            ),
        ),
    ]
    if member_id is not None:
        conditions.append(TrainerSchedule.member_id == member_id)
    rows = db.scalars(
        select(TrainerSchedule)
        .where(*conditions)
        .order_by(
            TrainerSchedule.date, TrainerSchedule.time, TrainerSchedule.sort_order
        )
    ).all()
    return [_schedule_out(s) for s in rows]


#: booked_dates 조회 하한(일). 주간 스트립 도트용이라 과거 전체가 필요없다 — 시간이 갈수록
#: 결과가 무한정 커지는 것을 막는다(리뷰 #280). 문자열 날짜(YYYY-MM-DD)는 사전식 비교 가능.
_BOOKED_DATES_WINDOW_DAYS = 90


def booked_dates(db: Session, trainer_id: str) -> list[str]:
    """예약이 있는(공백 아닌) 날짜 목록 — 주간 스트립 도트용(최근 90일 이후)."""
    cutoff = (_today() - timedelta(days=_BOOKED_DATES_WINDOW_DAYS)).isoformat()
    rows = db.scalars(
        select(TrainerSchedule.date)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.status != "공백",
            TrainerSchedule.date >= cutoff,
            or_(
                TrainerSchedule.member_id.is_(None),
                exists(
                    select(TrainerClient.id).where(
                        TrainerClient.trainer_id == trainer_id,
                        TrainerClient.member_id == TrainerSchedule.member_id,
                        TrainerClient.active.is_(True),
                    )
                ),
            ),
        )
        .distinct()
    ).all()
    return sorted(rows)


def _get_owned_session(db: Session, trainer_id: str, session_id: str) -> TrainerSchedule | None:
    s = db.get(TrainerSchedule, session_id)
    if s is None or s.trainer_id != trainer_id:
        return None
    return s


def _is_reservation_schedule(db: Session, session_id: str) -> bool:
    """Return whether a member reservation owns this schedule row."""
    return db.scalar(
        select(TrainerReservation.id)
        .where(TrainerReservation.schedule_id == session_id)
        .limit(1)
    ) is not None


def _dump_program(
    program: Sequence[ProgramItem | Mapping[str, object]],
) -> str:
    """Serialize validated program items from create and partial-update paths.

    Schedule creation passes ``ProgramItem`` instances, while
    ``ScheduleUpdateRequest.model_dump()`` recursively converts the same items
    to dictionaries before calling the service.  Supporting both forms keeps
    the service boundary consistent for API and direct service callers.
    """
    items = [
        item.model_dump(mode="json") if isinstance(item, ProgramItem) else dict(item)
        for item in program
    ]
    # `default=str` 은 dict 로 온 쪽의 날짜를 위한 것이다 — 부분 수정 경로는
    # 이미 model_dump() 를 거쳐 date 객체를 담고 오는데, json 은 그걸 모른다.
    return json.dumps(items, ensure_ascii=False, default=str)


def _existing_schedule_out(
    session: TrainerSchedule,
    *,
    date: str,
    time: str,
    client_name: str,
    member_id: str | None,
    type_: str,
    duration_minutes: int,
    note: str,
    program_json: str,
) -> ScheduleSessionOut:
    same_payload = (
        session.date == date
        and session.time == time
        and session.client_name == client_name
        and session.member_id == member_id
        and session.type == type_
        and session.duration_minutes == duration_minutes
        and session.note == note
        and session.program_json == program_json
    )
    if not same_payload:
        raise IdempotencyConflict(
            "같은 client_request_id에 다른 스케줄을 생성할 수 없습니다."
        )
    return _schedule_out(session)


def create_session(
    db: Session, trainer_id: str, *, date: str, time: str, client_name: str,
    member_id: str | None, type_: str, duration_minutes: int, note: str,
    program: list[ProgramItem], client_request_id: str | None = None,
) -> ScheduleSessionOut:
    program_json = _dump_program(program)
    if client_request_id:
        existing = db.scalar(
            select(TrainerSchedule).where(
                TrainerSchedule.trainer_id == trainer_id,
                TrainerSchedule.client_request_id == client_request_id,
            )
        )
        if existing is not None:
            return _existing_schedule_out(
                existing,
                date=date,
                time=time,
                client_name=client_name,
                member_id=member_id,
                type_=type_,
                duration_minutes=duration_minutes,
                note=note,
                program_json=program_json,
            )

    # 같은 키의 동시 요청은 유니크 제약으로 하나만 통과시킨 뒤, 패배한 요청은
    # 승자의 행을 읽어 같은 결과를 반환한다. 알림은 flush 뒤라 중복되지 않는다.
    try:
        s = _add_session(
            db,
            trainer_id,
            date=date,
            time=time,
            client_name=client_name,
            member_id=member_id,
            type_=type_,
            duration_minutes=duration_minutes,
            note=note,
            program_json=program_json,
            client_request_id=client_request_id,
        )
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = db.scalar(
                select(TrainerSchedule).where(
                    TrainerSchedule.trainer_id == trainer_id,
                    TrainerSchedule.client_request_id == client_request_id,
                )
            )
            if existing is not None:
                return _existing_schedule_out(
                    existing,
                    date=date,
                    time=time,
                    client_name=client_name,
                    member_id=member_id,
                    type_=type_,
                    duration_minutes=duration_minutes,
                    note=note,
                    program_json=program_json,
                )
        raise
    db.commit()
    db.refresh(s)
    return _schedule_out(s)


def _add_session(
    db: Session, trainer_id: str, *, date: str, time: str, client_name: str,
    member_id: str | None, type_: str, duration_minutes: int, note: str,
    program_json: str, client_request_id: str | None,
) -> TrainerSchedule:
    """예정 일정과 그 알림을 세션에 올리고 flush 한다. 커밋은 호출부 몫이다.

    [_add_program_routines] 와 같은 이유로 커밋하지 않는다(#1580).
    """
    s = TrainerSchedule(
        id=f"sched-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        date=date,
        time=time,
        client_name=client_name,
        type=type_,
        duration_minutes=duration_minutes,
        status="예정",
        note=note,
        program_json=program_json,
        sort_order=0,
        client_request_id=client_request_id,
    )
    db.add(s)
    db.flush()

    # 회원 몫의 일정이 잡혔을 때만 알린다 — 가망 고객('신규 고객 · 상담')처럼
    # member_id 가 없는 슬롯은 알릴 대상 자체가 없다(#489).
    if member_id is not None:
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.EXERCISE,
            category=notification_service.MEMBER_SCHEDULE,
            title="새 일정이 등록되었어요",
            body=f"{date} {time} · {type_}",
        )
    return s


#: 한 번의 반복 설정으로 만들 수 있는 최대 회차. 주 2회면 반년, 주 1회면 1년치다.
#: 상한을 두는 까닭은 오입력 때문이다 — 종료일에 연도를 잘못 적으면 수백 건이
#: 조용히 생기고, 그것을 되돌리는 일은 한 건씩 지우는 것뿐이다(#870).
MAX_SERIES_OCCURRENCES = 52


class ScheduleSeriesConflict(Exception):
    """반복 생성이 기존 일정과 겹친다. 겹치는 회차 목록을 들고 다닌다. (#870)

    라우터가 409 로 바꾸고, 화면은 이 목록을 그대로 보여 준다 — "총 8회 중 1개가
    겹칩니다" 는 겹치는 회차를 짚어 줄 수 있어야 트레이너가 판단한다.
    """

    def __init__(self, conflicts: list[ScheduleSessionOut]) -> None:
        super().__init__("겹치는 일정이 있습니다.")
        self.conflicts = conflicts


def _series_id_for(trainer_id: str, client_request_id: str) -> str:
    """생성 시도 하나에 대응하는 결정론적 시리즈 id.

    회차마다 멱등키를 따로 두지 않는 까닭은 유니크 제약이 (trainer, key) 한 쌍
    이기 때문이다. 대신 키에서 시리즈 id 를 만들어, 재시도가 **이미 만든 시리즈를
    다시 찾아** 같은 결과를 돌려주게 한다.
    """
    digest = hashlib.sha256(f"{trainer_id}:{client_request_id}".encode()).hexdigest()
    return f"series-{digest[:20]}"


def series_occurrences(
    start: date, weekdays: Sequence[int], *, count: int | None, until: date | None
) -> list[date]:
    """반복 규칙이 만드는 날짜들.

    [weekdays] 는 ISO 요일(월=1 … 일=7)이다. 시작일이 고른 요일 중 하나면 그 날도
    첫 회차가 된다 — 트레이너가 오늘 잡으며 "매주 화요일" 을 고르면 오늘(화요일)이
    빠지는 편이 더 놀랍다.

    종료는 횟수(`count`) 또는 종료일(`until`) 중 하나다. 둘 다 없으면 빈 목록이라
    호출부가 검증을 건너뛴 채 무한히 만들 수 없다. 어느 쪽이든 [MAX_SERIES_OCCURRENCES]
    를 넘지 않는다.
    """
    picked = {day for day in weekdays if 1 <= day <= 7}
    if not picked or (count is None and until is None):
        return []
    limit = min(count or MAX_SERIES_OCCURRENCES, MAX_SERIES_OCCURRENCES)
    out: list[date] = []
    day = start
    # 종료일이 없으면 회차 수가 멈춰 세운다. 종료일이 있어도 상한을 함께 두어,
    # 먼 미래 날짜 하나가 수백 건을 만들지 않게 한다.
    horizon = until or (start + timedelta(days=7 * MAX_SERIES_OCCURRENCES))
    while day <= horizon and len(out) < limit:
        if day.isoweekday() in picked:
            out.append(day)
        day += timedelta(days=1)
    return out


def conflicting_sessions(
    db: Session, trainer_id: str, slots: Sequence[tuple[str, str]]
) -> list[ScheduleSessionOut]:
    """[slots]((date, time) 쌍)과 같은 자리에 이미 있는 세션.

    취소·노쇼는 겹침이 아니다 — 그 시간은 비어 있다(#871). 공백 슬롯도 마찬가지로
    "빈 시간" 이라는 표시일 뿐이라 자리를 차지하지 않는다.

    반복 생성 미리보기(`preview_recurring_sessions`)뿐 아니라 상담 승인
    (`consultation_service.accept`)도 같은 겹침 판정을 쓴다 — 한 슬롯짜리 목록을
    넘기면 단발 겹침 검사로도 쓸 수 있다.
    """
    if not slots:
        return []
    rows = db.scalars(
        select(TrainerSchedule)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            tuple_(TrainerSchedule.date, TrainerSchedule.time).in_(list(slots)),
            TrainerSchedule.status.in_((SCHEDULE_UPCOMING, SCHEDULE_DONE)),
        )
        .order_by(TrainerSchedule.date, TrainerSchedule.time)
    ).all()
    return [_schedule_out(row) for row in rows]


def preview_recurring_sessions(
    db: Session,
    trainer_id: str,
    *,
    start: str,
    time: str,
    weekdays: Sequence[int],
    count: int | None = None,
    until: str | None = None,
) -> tuple[list[str], list[ScheduleSessionOut]]:
    """저장 전에 보여 줄 (생성될 날짜들, 겹치는 기존 세션들).

    만들기 전에 확인시키는 까닭은 반복이 **한 번에 여러 건**을 만들기 때문이다.
    요일이나 종료일을 잘못 골랐을 때 되돌리는 비용이 한 건씩 지우는 일이라,
    그 전에 보여 주는 편이 싸다.
    """
    dates = series_occurrences(
        date.fromisoformat(start),
        weekdays,
        count=count,
        until=None if until is None else date.fromisoformat(until),
    )
    iso = [day.isoformat() for day in dates]
    return iso, conflicting_sessions(db, trainer_id, [(day, time) for day in iso])


def create_recurring_sessions(
    db: Session,
    trainer_id: str,
    *,
    start: str,
    time: str,
    weekdays: Sequence[int],
    client_name: str,
    member_id: str | None,
    type_: str,
    duration_minutes: int,
    note: str = "",
    count: int | None = None,
    until: str | None = None,
    client_request_id: str | None = None,
) -> list[ScheduleSessionOut]:
    """반복 규칙대로 PT 회차를 한 번에 만든다. (#870)

    **전부 만들거나 하나도 만들지 않는다.** 겹치는 회차가 있으면
    [ScheduleSeriesConflict] 로 멈춘다 — 겹친 것만 빼고 조용히 나머지를 만들면
    트레이너는 몇 회차가 생겼는지 화면을 세어 봐야 알 수 있고, 빠진 주는 나중에
    발견된다.

    [client_request_id] 를 주면 그 시도에 대해 멱등하다. 응답을 못 받고 재시도한
    등록이 같은 회차를 두 벌 만들면 회원 일정이 두 배가 된다.
    """
    series_id = (
        _series_id_for(trainer_id, client_request_id) if client_request_id else None
    )
    if series_id is not None:
        existing = db.scalars(
            select(TrainerSchedule)
            .where(
                TrainerSchedule.trainer_id == trainer_id,
                TrainerSchedule.series_id == series_id,
            )
            .order_by(TrainerSchedule.date, TrainerSchedule.time)
        ).all()
        if existing:
            return [_schedule_out(row) for row in existing]

    dates = series_occurrences(
        date.fromisoformat(start),
        weekdays,
        count=count,
        until=None if until is None else date.fromisoformat(until),
    )
    if not dates:
        raise ScheduleError("반복할 요일과 종료 기준을 지정해 주세요.")

    iso = [day.isoformat() for day in dates]
    conflicts = conflicting_sessions(db, trainer_id, [(day, time) for day in iso])
    if conflicts:
        raise ScheduleSeriesConflict(conflicts)

    program_json = _dump_program([])
    created: list[TrainerSchedule] = []
    for day in iso:
        row = TrainerSchedule(
            id=f"sched-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            date=day,
            time=time,
            client_name=client_name,
            type=type_,
            duration_minutes=duration_minutes,
            status=SCHEDULE_UPCOMING,
            note=note,
            program_json=program_json,
            sort_order=0,
            series_id=series_id,
        )
        db.add(row)
        created.append(row)
    try:
        db.flush()
    except IntegrityError:
        # 같은 키의 동시 요청 중 하나만 통과한다. 패배한 쪽은 승자가 만든 회차를
        # 읽어 같은 결과를 돌려준다(단건 생성과 같은 규약).
        db.rollback()
        if series_id is not None:
            existing = db.scalars(
                select(TrainerSchedule)
                .where(
                    TrainerSchedule.trainer_id == trainer_id,
                    TrainerSchedule.series_id == series_id,
                )
                .order_by(TrainerSchedule.date, TrainerSchedule.time)
            ).all()
            if existing:
                return [_schedule_out(row) for row in existing]
        raise

    # 회원에게는 회차마다 알리지 않는다. 8주치를 한 번에 잡으면 알림함이 같은
    # 문구 여덟 줄로 덮이고, 그 뒤의 다른 알림이 밀려난다 — 한 줄로 묶어 보낸다.
    if member_id is not None:
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.EXERCISE,
            category=notification_service.MEMBER_SCHEDULE,
            title="반복 일정이 등록되었어요",
            body=f"{iso[0]} ~ {iso[-1]} · {time} · {len(iso)}회",
        )
    db.commit()
    for row in created:
        db.refresh(row)
    return [_schedule_out(row) for row in created]


def _schedule_program_items(
    sessions: Sequence[ProgramDraftSession],
) -> list[ProgramItem]:
    """프로그램 세션들을 일정 한 건의 평면 항목으로 펼친다. (#709, #1580)

    세션 이름은 항목마다 붙는다 — 일정은 평면 목록이지만 이 값으로 다시 세션별로
    묶어 보여 줄 수 있다. 세션이 하나뿐이면 빈 문자열이라 예전 일정과 같은 모양이다.
    유형에 맞지 않는 칸은 [ProgramItem] 검증이 비운다(#1276).
    """
    multi = len(sessions) > 1
    return [
        ProgramItem(
            name=exercise.name,
            type=exercise.type,
            date=exercise.date,
            duration=exercise.duration,
            sets=exercise.sets,
            reps=exercise.reps,
            hold_seconds=exercise.hold_seconds,
            weight=exercise.weight,
            intensity=exercise.intensity,
            session=session.name if multi else "",
        )
        for session in sessions
        for exercise in session.exercises
    ]


class AttachTargetConflict(Exception):
    """프로그램을 붙일 기존 세션을 하나로 정할 수 없다(#1581).

    고른 시간대와 겹치는 예정 세션이 여럿인데 고르지 않았거나, 고른 세션이 더는
    후보가 아니다. 라우터가 409 와 함께 후보를 싣는다.
    """

    def __init__(self, message: str, candidates: Sequence[TrainerSchedule]):
        super().__init__(message)
        self.candidates = [_schedule_out(s) for s in candidates]


def _clock_minutes(value: str) -> int:
    """`HH:MM` 을 자정부터의 분으로. 형식이 다르면 ValueError."""
    hour, minute = value.split(":")
    return int(hour) * 60 + int(minute)


def _overlapping_planned_sessions(
    db: Session, trainer_id: str, member_id: str, *,
    date: str, time: str, duration_minutes: int,
) -> list[TrainerSchedule]:
    """고른 시간대와 겹치는 그 회원·그날의 예정 세션(시작 시각 순). (#1581)

    예전에는 시간과 상관없이 그날 가장 이른 예정 세션에 붙어, 같은 날 PT 가
    여럿이면 의도하지 않은 회차에 프로그램이 들어갔다. 겹침은 반열린 구간
    `[시작, 끝)` 끼리 본다 — 10:00–11:00 과 11:00–12:00 은 이어질 뿐 겹치지
    않는다. 길이가 0인 세션은 시작 1분으로 본다.
    """
    rows = db.scalars(
        select(TrainerSchedule)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.date == date,
            TrainerSchedule.status == "예정",
        )
        .order_by(TrainerSchedule.time, TrainerSchedule.id)
        .with_for_update()
    ).all()
    start = _clock_minutes(time)
    end = start + duration_minutes
    overlapping: list[TrainerSchedule] = []
    for row in rows:
        try:
            row_start = _clock_minutes(row.time)
        except ValueError:
            continue
        if start < row_start + max(row.duration_minutes, 1) and row_start < end:
            overlapping.append(row)
    return overlapping


def _schedule_request_key(base: str) -> str:
    """`일정 추가` 가 새로 만든 일정 행의 멱등키. 루틴 키(`#0`…)와 겹치지 않는다."""
    return f"{base}#schedule"


def _personal_request_key(base: str, index: int) -> str:
    """PT 에 붙인 개인운동 행의 멱등키. 세션 루틴(`#0`…)·일정(`#schedule`)과
    겹치지 않는다. (#2223)"""
    return f"{base}#routine{index}"


def _scheduled_routines_for_request(
    db: Session, trainer_id: str, member_id: str, client_request_id: str,
) -> list[TrainerRoutine]:
    """그 멱등키로 이미 붙여 둔 개인운동들(넣은 순서대로). 없으면 빈 목록."""
    return list(
        db.scalars(
            select(TrainerRoutine)
            .where(
                TrainerRoutine.trainer_id == trainer_id,
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.client_request_id.like(
                    f"{client_request_id}#routine%"
                ),
            )
            .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
        ).all()
    )


def _add_scheduled_routines(
    db: Session, trainer_id: str, member_id: str, *,
    items: Sequence[PersonalRoutineItem],
    schedule_id: str,
    exercise_date: str,
    client_request_id: str | None,
) -> list[TrainerRoutine]:
    """PT 일정에 붙는 개인운동을 세션에 올리고 flush 한다. 커밋은 호출부 몫이다. (#2223)

    `status=scheduled` 로 들어가므로 회원 조회(`build_routines`)에도 제안 검토
    목록(`list_routine_suggestions`)에도 잡히지 않는다 — 회원에게 가는 것은 그
    PT 를 완료할 때다(#2224). 그래서 **배정 알림도 여기서 보내지 않는다.**
    지금 알리면 회원은 아직 오지 않은 운동의 알림을 먼저 받는다.
    """
    if not items:
        return []
    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order)).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    ) or 0
    now = datetime.now(timezone.utc)
    created: list[TrainerRoutine] = []
    for index, item in enumerate(items):
        rt = TrainerRoutine(
            id=f"rt-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            name=item.name,
            minutes=item.minutes,
            type=item.type,
            exercise_date=exercise_date,
            intensity=item.intensity,
            # 세트·횟수·중량·초는 단일 배정과 같은 규칙으로 근력에만 남긴다
            # (#1276, #1310, #1969).
            sets=item.sets if item.type == "근력" else None,
            reps=(
                item.reps
                if item.type == "근력" and item.hold_seconds is None
                else None
            ),
            hold_seconds=item.hold_seconds if item.type == "근력" else None,
            weight=(
                round(item.weight, 1)
                if item.weight is not None and item.type == "근력"
                else None
            ),
            reason=item.reason,
            source=item.source,
            status=ROUTINE_SCHEDULED,
            schedule_id=schedule_id,
            delivery_kind=DELIVERY_PT_WITH_ROUTINE,
            sort_order=max_order + index + 1,
            client_request_id=(
                _personal_request_key(client_request_id, index)
                if client_request_id
                else None
            ),
            created_at=now,
        )
        db.add(rt)
        created.append(rt)
    db.flush()
    return created


def list_scheduled_routines(
    db: Session, trainer_id: str, schedule_id: str,
) -> list[RoutineOut]:
    """그 PT 일정에 붙어 있는(아직 보내지 않은) 개인운동. (#2223)

    일정 상세가 "이 PT 와 함께 갈 개인운동"을 보여 주는 데 쓴다(#2224). 이미
    보낸 뒤에는 상태가 `approved` 로 바뀌므로 이 목록에서 빠진다.
    """
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.schedule_id == schedule_id,
            TrainerRoutine.status == ROUTINE_SCHEDULED,
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
    ).all()
    return [_routine_out(db, row) for row in rows]


def _replayed_program_schedule(
    db: Session, trainer_id: str, member_id: str, *,
    client_request_id: str,
    routines: Sequence[TrainerRoutine],
    date: str,
    program_json: str,
) -> ProgramScheduleOut:  # noqa: D401
    """같은 멱등키로 이미 끝난 `일정 추가` 의 결과를 다시 만든다. (#1580)

    배정과 일정은 한 트랜잭션이라, 루틴이 있으면 일정도 이미 반영돼 있다. 새로
    만든 일정은 멱등키로 찾고, 기존 일정에 붙인 경우는 그 날짜에서 같은 구성을
    가진 일정으로 찾는다. 그 사이 트레이너가 일정을 고쳐 둘 다 없으면 무엇을
    돌려줘야 할지 알 수 없으므로 충돌로 알린다 — 다시 만들면 중복이 된다.
    """
    created = db.scalar(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.client_request_id == _schedule_request_key(client_request_id),
        )
    )
    attached: TrainerSchedule | None = None
    if created is None:
        attached = db.scalar(
            select(TrainerSchedule)
            .where(
                TrainerSchedule.trainer_id == trainer_id,
                TrainerSchedule.member_id == member_id,
                TrainerSchedule.date == date,
                TrainerSchedule.program_json == program_json,
            )
            .order_by(TrainerSchedule.time, TrainerSchedule.id)
            .limit(1)
        )
    session = created or attached
    if session is None:
        raise IdempotencyConflict(
            "이미 처리된 요청입니다. 일정을 확인한 뒤 새로 추가해 주세요."
        )
    return ProgramScheduleOut(
        routines=[_routine_out(db, rt) for rt in routines],
        session=_schedule_out(session),
        attached_to_existing=created is None,
        # 개인운동도 같은 트랜잭션에서 저장됐으므로 같은 키로 찾아 함께 돌려준다
        # — 재시도가 개인운동만 빠진 결과를 받으면 화면이 "안 붙었다"고 읽는다.
        personal_routines=[
            _routine_out(db, rt)
            for rt in _scheduled_routines_for_request(
                db, trainer_id, member_id, client_request_id
            )
        ],
    )


def assign_program_with_schedule(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    name: str,
    sessions: Sequence[ProgramDraftSession],
    date: str,
    time: str,
    duration_minutes: int,
    client_name: str,
    client_request_id: str | None = None,
    session_id: str | None = None,
    personal_routines: Sequence[PersonalRoutineItem] = (),
) -> ProgramScheduleOut | None:
    """프로그램을 회원에게 배정하고 PT 일정에 올린다 — 둘 다 되거나 둘 다 안 된다. (#1580)

    담당 링크 행을 잠가 한 트레이너·회원 쌍의 명령을 줄 세운다. 동시에 들어온
    두 요청이 같은 빈 일정을 보고 각자 일정을 만들지 못하고, 같은 멱등키의 재시도는
    앞 요청이 커밋한 루틴을 보고 결과만 돌려받는다.

    연결 대상은 고른 시간대와 겹치는 그날 예정 세션이다(#1581). 없으면 고른
    시간으로 새 일정을 만들고, 하나면 거기에 붙이며(고른 시간은 쓰지 않는다),
    여럿이면 [session_id] 로 고른 것에만 붙인다 — 고르지 않았거나 고른 것이
    후보가 아니면 [AttachTargetConflict]. 담당 고객이 아니면 None.

    [personal_routines] 는 이 PT 사이에 회원이 혼자 할 개인운동이다(#2223).
    같은 트랜잭션에서 그 일정에 붙여 두기만 하고 회원에게는 보내지 않는다 —
    보내는 것은 PT 완료 때다(#2224). 일정이 정해진 뒤에 넣어야 붙일 id 가
    있으므로 프로그램 루틴보다 나중에 만든다.
    """
    client_link = db.scalar(
        select(TrainerClient)
        .where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
        .with_for_update()
    )
    if client_link is None:
        return None

    program_json = _dump_program(_schedule_program_items(sessions))
    if client_request_id:
        replayed = _program_routines_for_request(
            db, trainer_id, member_id, client_request_id, len(sessions)
        )
        if replayed:
            return _replayed_program_schedule(
                db, trainer_id, member_id,
                client_request_id=client_request_id,
                routines=replayed,
                date=date,
                program_json=program_json,
            )

    candidates = _overlapping_planned_sessions(
        db, trainer_id, member_id,
        date=date, time=time, duration_minutes=duration_minutes,
    )
    target: TrainerSchedule | None
    if session_id is not None:
        target = next((s for s in candidates if s.id == session_id), None)
        if target is None:
            raise AttachTargetConflict(
                "고른 PT 일정이 더는 이 시간대의 예정 세션이 아닙니다. 다시 확인해 주세요.",
                candidates,
            )
    elif len(candidates) > 1:
        raise AttachTargetConflict(
            "고른 시간대와 겹치는 PT 일정이 여러 개입니다. 연결할 회차를 골라 주세요.",
            candidates,
        )
    else:
        target = candidates[0] if candidates else None
    routines = _add_program_routines(
        db, trainer_id, member_id,
        name=name, sessions=sessions, client_request_id=client_request_id,
    )
    if target is None:
        session = _add_session(
            db,
            trainer_id,
            date=date,
            time=time,
            client_name=client_name,
            member_id=member_id,
            type_="1:1 PT",
            duration_minutes=duration_minutes,
            note="",
            program_json=program_json,
            client_request_id=(
                _schedule_request_key(client_request_id) if client_request_id else None
            ),
        )
    else:
        target.program_json = program_json
        session = target
    personal = _add_scheduled_routines(
        db, trainer_id, member_id,
        items=personal_routines,
        schedule_id=session.id,
        # 개인운동은 그 PT 가 있는 날의 것이다 — 일정에 붙였는데 날짜가 다르면
        # 회원 화면에서 둘이 따로 떨어진다.
        exercise_date=session.date,
        client_request_id=client_request_id,
    )
    db.commit()
    for rt in routines:
        db.refresh(rt)
    for rt in personal:
        db.refresh(rt)
    db.refresh(session)
    return ProgramScheduleOut(
        routines=[_routine_out(db, rt) for rt in routines],
        session=_schedule_out(session),
        attached_to_existing=target is not None,
        personal_routines=[_routine_out(db, rt) for rt in personal],
    )


def _member_visible_slot(s: TrainerSchedule) -> tuple[str, str, str, int]:
    """회원이 약속을 지키려고 아는 값들. 이 넷 중 하나라도 달라지면 알린다.

    메모(`note`)·프로그램은 트레이너의 준비물이라 빠져 있다 — 그것까지 알리면
    알림함이 같은 일정으로 차고, 정작 시각이 바뀐 알림이 묻힌다. (#664)
    """
    return (s.date, s.time, s.type, s.duration_minutes)


def _slot_body(slot: tuple[str, str, str, int]) -> str:
    date, time, type_, _ = slot
    return f"{date} {time} · {type_}"


def _notify_schedule_changed(
    db: Session,
    *,
    session: TrainerSchedule,
    before_member_id: str | None,
    before_slot: tuple[str, str, str, int],
) -> None:
    """바뀐 일정을 회원에게 알린다. **커밋하지 않는다.**

    등록만 알리고 변경·취소를 알리지 않으면, 회원은 "새 일정이 등록되었어요" 를
    믿고 이미 옮겨진 시간에 나간다. 취소 알림이 등록 알림보다 중요하다. (#664)
    """
    after_slot = _member_visible_slot(session)

    if before_member_id == session.member_id:
        if session.member_id is None or before_slot == after_slot:
            return
        notification_service.queue(
            db,
            member_id=session.member_id,
            kind=notification_service.EXERCISE,
            category=notification_service.MEMBER_SCHEDULE,
            title="일정이 변경되었어요",
            body=_slot_body(after_slot),
        )
        return

    # 다른 회원에게 넘긴 일정. 넘겨받은 쪽만 알리면 원래 회원은 약속이 사라진
    # 줄 모른 채 그 시간에 나간다 — 양쪽 모두 알린다.
    if before_member_id is not None:
        notification_service.queue(
            db,
            member_id=before_member_id,
            kind=notification_service.EXERCISE,
            category=notification_service.MEMBER_SCHEDULE,
            title="일정이 취소되었어요",
            body=_slot_body(before_slot),
        )
    if session.member_id is not None:
        notification_service.queue(
            db,
            member_id=session.member_id,
            kind=notification_service.EXERCISE,
            category=notification_service.MEMBER_SCHEDULE,
            title="새 일정이 등록되었어요",
            body=_slot_body(after_slot),
        )


def update_session(
    db: Session, trainer_id: str, session_id: str, fields: dict
) -> ScheduleSessionOut | None:
    """예약 부분 수정. 소유 슬롯이 아니면 None(라우터 404).

    완료된 세션은 이미 회원 운동기록(RoutineHistory)으로 적재됐다. 이후 member_id·program·
    note 등을 바꾸면 스케줄과 기록이 어긋나므로(리뷰 재-#2), 완료 세션 수정은 409 로 거부한다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    # 회원에게 알릴지 판단하려면 **바꾸기 전** 값을 들고 있어야 한다. 넘긴
    # 일정의 취소 알림에는 옛 시각을 써야 회원이 어느 약속인지 안다.
    before_member_id = s.member_id
    before_slot = _member_visible_slot(s)
    # A reservation owns the booking coordinates and lifecycle, so changing
    # its time/member/type/duration through the general schedule API would
    # desynchronise the slot and remaining count. The trainer may still add
    # the PT plan and memo: those fields do not alter the reservation.
    if _is_reservation_schedule(db, session_id) and not set(fields).issubset(
        {"program", "note"}
    ):
        raise ScheduleConflict(
            "예약으로 생성된 일정은 일반 일정 화면에서 수정할 수 없습니다."
        )
    if s.status in SCHEDULE_TERMINAL:
        # 취소·노쇼도 "그때 무슨 일이 있었나" 를 남긴 기록이라 나중에 시간·회원을
        # 고쳐 쓰면 그 기록이 가리키는 약속이 달라진다(완료 세션과 같은 이유).
        raise ScheduleConflict(
            "완료·취소·노쇼로 마무리된 세션은 수정할 수 없습니다."
        )
    if "date" in fields:
        s.date = fields["date"]
    if "time" in fields:
        s.time = fields["time"]
    if "client_name" in fields:
        s.client_name = fields["client_name"]
    if "member_id" in fields:
        # 빈 문자열은 '배정 해제'로 해석 → NULL 로 저장(""는 users.id FK 위반이라 500 유발).
        s.member_id = fields["member_id"] or None
    if "type" in fields:
        s.type = fields["type"]
    if "duration_minutes" in fields:
        s.duration_minutes = fields["duration_minutes"]
    if "note" in fields:
        s.note = fields["note"]
    if "program" in fields and fields["program"] is not None:
        s.program_json = _dump_program(fields["program"])
    _notify_schedule_changed(
        db,
        session=s,
        before_member_id=before_member_id,
        before_slot=before_slot,
    )
    db.commit()
    db.refresh(s)
    return _schedule_out(s)


def delete_session(db: Session, trainer_id: str, session_id: str) -> bool:
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return False
    if _is_reservation_schedule(db, session_id):
        raise ScheduleConflict(
            "예약으로 생성된 일정은 일반 일정 화면에서 삭제할 수 없습니다."
        )
    # 완료 세션은 완료 시 파생된 기록을 갖는다 — 트레이너 이력(sched-hist-{id})과
    # 회원 운동 기록(sched-ex-{id}) 두 개다. 세션을 지우면 둘 다 함께 지워 고아
    # 레코드가 남지 않게 한다(완료 시 적재의 역연산). 회원 쪽을 빠뜨리면 회원의
    # 주간 집계에만 지워진 PT 가 계속 잡힌다.
    if s.status == "완료":
        hist = db.get(RoutineHistory, f"sched-hist-{s.id}")
        if hist is not None:
            db.delete(hist)
        derived = db.get(ExerciseSession, _derived_exercise_id(s.id))
        if derived is not None:
            db.delete(derived)
    # 그 PT 에 붙여 두었을 뿐 아직 회원에게 가지 않은 개인운동은 함께 지운다
    # (#2223). FK 는 `SET NULL` 이라 그냥 두면 일정만 사라지고 `status` 는
    # `scheduled` 인 채 남는데, 그런 행은 회원 목록에도 제안 목록에도 잡히지
    # 않고 붙은 일정으로도 찾을 수 없어 **아무도 못 보고 지우지도 못한다.**
    # 이미 회원에게 간 것(`approved`)은 건드리지 않는다 — 일정이 지워졌다고
    # 회원이 받은 운동이 사라지면 안 된다.
    for pending in db.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.schedule_id == s.id,
            TrainerRoutine.status == ROUTINE_SCHEDULED,
        )
    ).all():
        db.delete(pending)
    # 아직 오지 않은 약속만 알린다. 이미 끝난 PT 의 기록 정리까지 알리면 회원은
    # 지난 일을 취소 통보로 받는다. (#664)
    if s.member_id is not None and s.status == SCHEDULE_UPCOMING:
        notification_service.queue(
            db,
            member_id=s.member_id,
            kind=notification_service.EXERCISE,
            category=notification_service.MEMBER_SCHEDULE,
            title="일정이 취소되었어요",
            body=_slot_body(_member_visible_slot(s)),
        )
    db.delete(s)
    db.commit()
    return True


def reopen_session(
    db: Session, trainer_id: str, session_id: str, *, new_date: str
) -> ScheduleSessionOut | None:
    """완료 세션을 미래 날짜의 예정으로 되돌린다. (#1396)

    수정 화면에서 완료된 회차의 날짜를 앞으로 옮기며 "예정으로 바꿀까요?" 확인을
    거친 저장이 부르는 자리다 — 임의로 완료를 취소하는 일반 수정 경로는 아니다.
    완료가 남긴 파생 기록(트레이너 이력·회원 운동기록)은 [delete_session] 과
    같은 자리(id)를 지운다 — 그대로 두면 되돌린 뒤에도 "이미 했던 운동"으로
    남아 회원 집계가 거짓이 된다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if _is_reservation_schedule(db, session_id):
        raise ScheduleConflict(
            "예약으로 생성된 일정은 일반 일정 화면에서 되돌릴 수 없습니다."
        )
    if s.status != SCHEDULE_DONE:
        raise ScheduleConflict("완료된 세션만 예정으로 되돌릴 수 있습니다.")
    if new_date <= today_iso():
        raise ScheduleConflict("미래 날짜로만 되돌릴 수 있습니다.")

    hist = db.get(RoutineHistory, f"sched-hist-{s.id}")
    if hist is not None:
        db.delete(hist)
    derived = db.get(ExerciseSession, _derived_exercise_id(s.id))
    if derived is not None:
        db.delete(derived)

    s.date = new_date
    s.status = SCHEDULE_UPCOMING
    db.commit()
    db.refresh(s)
    return _schedule_out(s)


#: PT 완료가 파생시키는 회원 운동 기록의 종류. `TrainerSchedule.type` 은 화면용
#: 한국어 라벨('1:1 PT'|'상담')이고 `ExerciseSession.type` 은 계약 값이라 매핑이
#: 필요하다. 여기 없는 종류는 **운동이 아니므로 기록을 만들지 않는다** — 상담
#: 한 시간이 회원 주간 운동량으로 잡히면 집계가 거짓이 된다.
_SESSION_EXERCISE_TYPE = {"1:1 PT": "strength"}

#: 강도를 하나도 적지 않은(예전) 프로그램의 강도. PT 는 트레이너가 붙어서 끌고
#: 가는 시간이라 수기 입력의 '보통'보다 낮게 볼 이유가 없다.
_PT_INTENSITY = "moderate"


def _derived_exercise_id(session_id: str) -> str:
    """PT 완료가 파생시킨 운동 기록의 id — 슬롯 기준 결정론적.

    `sched-hist-{id}` 와 같은 이유다. 동시 완료나 재호출에도 같은 id 가 나와
    중복 행이 생기지 않는다.
    """
    return f"sched-ex-{session_id}"


def _schedule_day(day: str) -> date:
    """슬롯의 날짜. 값이 깨졌으면 오늘로 둔다(주차·요일 계산과 같은 폴백)."""
    try:
        return date.fromisoformat(day)
    except (TypeError, ValueError):
        return clock.today()


def _add_member_exercise_log(
    db: Session, s: TrainerSchedule
) -> ExerciseSession | None:
    """완료된 PT 세션을 회원 쪽 운동 기록으로 적재. 대상이 아니면 None.

    `RoutineHistory` 는 트레이너 화면 전용이라(`/trainer/clients/{id}/history`)
    회원 앱에서는 읽지 않는다. 회원의 운동 탭·홈 대시보드 주간 집계는 전부
    `ExerciseSession` 에서 나오므로, 두 곳 모두에 남겨야 회원이 받은 PT 가
    자기 기록에 잡힌다. (#499)
    """
    ex_type = _SESSION_EXERCISE_TYPE.get(s.type)
    if s.member_id is None or ex_type is None or s.duration_minutes <= 0:
        return None
    # 프로그램에 적힌 실제 운동 항목의 분·유형을 우선 쓴다 — 분을 하나도
    # 적지 않은(예전) 프로그램만 슬롯 전체 길이·고정 유형으로 되돌아간다(#1233).
    items = _program_items(s.program_json)
    program_minutes, program_type_ko = _program_minutes_and_type(items)
    minutes = program_minutes if program_minutes > 0 else s.duration_minutes
    if program_type_ko is not None:
        ex_type = exercise_types.normalize(program_type_ko)
    # 트레이너가 프로그램에 적어 둔 이름·세트·횟수·중량·강도를 회원 기록에도
    # 남긴다(#1276, #1310). 예전에는 분과 유형만 옮겨서, 회원 화면에는 무슨
    # 운동을 몇 회 몇 kg 로 했는지가 사라졌다.
    strength_items = [i for i in items if i.type == "근력"]
    sets = sum(i.sets for i in strength_items if i.sets) or None
    weights = [i.weight for i in strength_items if i.weight]
    # 횟수는 세트와 달리 더하지 않는다 — 한 세트당 수라 합계는 아무도 한 적 없는
    # 수가 된다. 중량과 같은 규칙으로 가장 많이 한 수를 그날의 기록으로 남긴다.
    rep_counts = [i.reps for i in strength_items if i.reps]
    # 버티는 종목의 홀드도 같은 규칙이다 — 합계는 아무도 버틴 적 없는 시간이라
    # 가장 오래 버틴 값을 그날의 기록으로 남긴다. (#1969)
    hold_counts = [i.hold_seconds for i in strength_items if i.hold_seconds]
    # 항목마다 강도가 다르면 세션 하나로 접을 값이 없다 — 그럴 때만 기본값이다.
    marked = {i.intensity for i in items}
    intensity = marked.pop() if len(marked) == 1 else _PT_INTENSITY
    # 주차·요일·완료 시각 셋 다 완료 시점이 아니라 **세션 날짜** 기준이다.
    # 지난 주 세션을 오늘 완료 처리해도 그 주의 집계로 들어가야 하는데,
    # `completed_at` 만 비워 두면 그 값을 읽는 자리에서는 오늘 한 운동이 된다.
    # 날짜 하나를 먼저 정하고 셋을 거기서 뽑는 이유는 값이 깨졌을 때다 — 따로
    # 계산하면 주차는 이번 주, 요일은 오늘 요일로 각각 흘러 서로 다른 날을
    # 가리킨다. (#1264)
    session_day = _schedule_day(s.date)
    # 한 세션에 여러 종목이면 이름 하나로 접히지 않는다. 그때 이름 해석을 태우면
    # `스쿼트, 데드리프트` 가 둘 중 하나로 붙어, 세션 전체의 칼로리가 한 종목의
    # 계수로 계산된다 — 종목이 하나일 때만 이름을 본다. (#1312)
    pt_estimate = exercise_service.estimate(
        db,
        name=items[0].name if len(items) == 1 else "",
        type_=ex_type,
        minutes=minutes,
        intensity=intensity,
        weight_kg=exercise_service.member_weight_kg(db, s.member_id),
    )
    row = ExerciseSession(
        id=_derived_exercise_id(s.id),
        user_id=s.member_id,
        week_start=exercise_service.monday_of_str(session_day.isoformat()),
        day_label=exercise_service.weekday_label_of(session_day.isoformat()),
        type=ex_type,
        name=", ".join(i.name for i in items),
        minutes=minutes,
        sets=sets if ex_type == exercise_types.STRENGTH else None,
        reps=(
            max(rep_counts)
            if rep_counts and not hold_counts
            and ex_type == exercise_types.STRENGTH
            else None
        ),
        hold_seconds=(
            max(hold_counts)
            if hold_counts and ex_type == exercise_types.STRENGTH
            else None
        ),
        # 여러 운동을 한 세션이면 가장 무거웠던 무게가 그날의 기록이다 —
        # 평균은 실제로 든 적 없는 값이라 다음 무게를 정할 근거가 못 된다.
        weight=max(weights) if weights and ex_type == exercise_types.STRENGTH else None,
        calories=pt_estimate.calories,
        calorie_source=pt_estimate.source,
        intensity=intensity,
        source="trainer_pt",
        completed_at=exercise_activity.noon(session_day),
    )
    db.add(row)
    # 보호권으로 이어 붙인 날의 PT 를 완료 처리하면 그날은 운동한 날이다 — 그
    # 보호권을 되돌린다(#1788). 트레이너 화면은 보호한 날을 모른다.
    streak_shield_service.refund_for_record(db, s.member_id, session_day)
    return row


def send_session_program(
    db: Session,
    trainer_id: str,
    session_id: str,
    *,
    client_request_id: str | None = None,
) -> ScheduleSessionOut | None:
    """완료한 세션의 프로그램을 그 회원에게 배정한다. (#822)

    수업을 마친 뒤 "오늘 이걸 했습니다" 를 회원 앱으로 넘기는 자리다. 새 배정
    경로를 만들지 않고 [assign_program] 을 그대로 쓴다 — 회원이 받는 모양이
    트레이너가 코칭 탭에서 보내던 것과 같아야, 회원 화면에 출처마다 다른 루틴이
    생기지 않는다.

    - 소유 슬롯 아님 → None(404).
    - 회원이 없는 슬롯(상담·공백) → ScheduleError(400): 보낼 상대가 없다.
    - 완료 전 → ScheduleError(400): 아직 한 것이 아니라 할 것이다.
    - 프로그램이 비었으면 → ScheduleError(400): 빈 루틴만 간다.
    - 이미 보냈으면 그대로 반환(멱등). 두 번 눌러도 회원 루틴이 겹치지 않는다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if not s.member_id:
        raise ScheduleError("회원이 연결되지 않은 일정입니다.")
    if s.status != "완료":
        raise ScheduleError("완료한 일정만 보낼 수 있습니다.")
    items = _program_items(s.program_json)
    if not items:
        raise ScheduleError("보낼 프로그램이 없습니다.")
    if s.program_sent_at is not None:
        return _schedule_out(s)  # 멱등 no-op

    # 일정의 프로그램 항목을 배정 계약의 운동으로 옮긴다. 두 계약이 같은 칸을
    # 쓰므로 값을 고쳐 담을 것이 없다(#1276). 세션은 하나다 — 회원 화면에 없던
    # 세션 라벨이 생기지 않는다.
    exercises = [
        ProgramDraftExercise(
            id=f"{s.id}#{index}",
            name=item.name,
            type=item.type,
            date=item.date,
            duration=item.duration,
            sets=item.sets,
            reps=item.reps,
            hold_seconds=item.hold_seconds,
            weight=item.weight,
            intensity=item.intensity,
        )
        for index, item in enumerate(items)
    ]
    assign_program(
        db,
        trainer_id,
        s.member_id,
        name=f"{s.date} {s.type}".strip() or s.date,
        sessions=[ProgramDraftSession(id=s.id, name="", exercises=exercises)],
        client_request_id=client_request_id,
    )
    # 배정이 커밋된 뒤에만 보낸 것으로 남긴다. 반대 순서면 배정에 실패한 세션이
    # 화면에서 '전송됨' 이 되어 다시 보낼 수 없다.
    s.program_sent_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(s)
    return _schedule_out(s)


def complete_session(
    db: Session, trainer_id: str, session_id: str, note: str
) -> ScheduleSessionOut | None:
    """예정→완료. 매칭된 회원이 있으면 트레이너 쪽 기록(RoutineHistory)과 회원 쪽
    기록(ExerciseSession)으로 함께 적재해 '예약→수업→기록' 루프를 닫는다.

    - 소유 슬롯 아님 → None(404).
    - 공백/미래 일정 → ScheduleError(400).
    - 이미 완료 → 그대로 반환(멱등, 중복 기록 없음).
    두 기록 모두 id 가 슬롯 기준 결정론적이라 동시/재호출에도 중복되지 않는다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if s.status == "공백":
        raise ScheduleError("빈 슬롯은 완료할 수 없습니다.")
    if s.date > _today().isoformat():
        raise ScheduleError("미래 일정은 완료할 수 없습니다.")
    if s.status == SCHEDULE_DONE:
        return _schedule_out(s)  # 멱등 no-op
    if s.status in SCHEDULE_TERMINAL:
        # 진행되지 않은 것으로 마무리한 세션을 완료로 되돌리면 하지 않은 PT 가
        # 회원 운동 기록으로 적재된다.
        raise ScheduleConflict(
            "취소·노쇼로 마무리된 세션은 완료할 수 없습니다."
        )

    # 조건부 전환(예정 → 완료). rowcount==1 인 호출만 '방금 전환한' 것이므로 그 호출만
    # 운동기록을 쓴다 — 동시 완료 요청이 둘 다 예정을 보고 중복 기록하는 것을 막는다.
    values: dict = {"status": "완료"}
    if note:
        values["note"] = note
    changed = db.execute(
        update(TrainerSchedule)
        .where(TrainerSchedule.id == session_id, TrainerSchedule.status == "예정")
        .values(**values)
    ).rowcount
    if changed != 1:
        db.commit()
        db.refresh(s)
        return _schedule_out(s)  # 동시 호출이 먼저 완료 처리함 — 기록 없이 현재 상태 반환

    exercise_log: ExerciseSession | None = None
    if s.member_id:
        program = _program_items(s.program_json)
        exercises = [_program_item_label(p) for p in program]
        db.add(RoutineHistory(
            id=f"sched-hist-{s.id}",
            member_id=s.member_id,
            trainer_id=trainer_id,
            date=s.date,
            kind_label="PT 세션 · 트레이너 지도",
            completion_rate=100,
            exercises_json=json.dumps(exercises, ensure_ascii=False),
            trainer_note=note,
        ))
        exercise_log = _add_member_exercise_log(db, s)
    db.commit()
    db.refresh(s)
    out = _schedule_out(s)
    if exercise_log is not None:
        # 회원 입장에서 PT 도 '내가 한 운동'이라 코치가 검색할 수 있어야 한다(#586).
        # 커밋 뒤에 부르는 이유는 record_chat 과 같다 — 적재 실패의 롤백이 응답을
        # 깨뜨리지 않도록, 값은 미리 뽑아 두고 응답도 이미 만들어 둔다.
        # PT 완료는 멱등하게 재호출될 수 있고 id 도 슬롯 기준 결정론적이라
        # (`_derived_exercise_id`), 교체로 두어야 문서가 겹쳐 쌓이지 않는다.
        personal_ingest.refresh_exercise(
            db, exercise_log.user_id, session_id=exercise_log.id
        )
    return out


def cancel_session(
    db: Session,
    trainer_id: str,
    session_id: str,
    *,
    source: str = "trainer",
    reason: str = "",
) -> ScheduleSessionOut | None:
    """예정 → 취소. 일정을 지우지 않고 **진행되지 않았다는 기록**으로 남긴다. (#871)

    삭제와 나누는 까닭이 이 함수의 전부다 — 삭제는 잘못 만든 데이터를 없애는 일이고,
    취소는 실제로 있었던 약속이 진행되지 않았다는 사실이다. 지워 버리면 나중에 회원의
    낮은 완료율이 본인의 미이행 때문인지 트레이너 사정 때문인지 구분할 수 없다.

    - 소유 슬롯 아님 → None(404).
    - 공백 슬롯 → ScheduleError(400): 취소할 약속이 없다.
    - 이미 취소 → 그대로 반환(멱등). 중복 클릭·재시도에 409 를 주면 화면은 이미
      취소한 일정에 대해 오류를 띄운다. 취소 시각과 주체는 처음 값을 지킨다.
    - 완료·노쇼 → ScheduleConflict(409): 다른 결말로 이미 마무리된 세션이다.
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if s.status == SCHEDULE_GAP:
        raise ScheduleError("빈 슬롯은 취소할 수 없습니다.")
    if s.status == SCHEDULE_CANCELLED:
        return _schedule_out(s)  # 멱등 no-op
    if s.status in SCHEDULE_TERMINAL:
        raise ScheduleConflict(
            "완료·노쇼로 마무리된 세션은 취소할 수 없습니다."
        )
    if source not in CANCELLATION_SOURCES:
        raise ScheduleError("취소 주체가 올바르지 않습니다.")

    # 조건부 전환(예정 → 취소). 동시에 들어온 취소·완료 요청 중 하나만 이긴다 —
    # rowcount 가 0 이면 그 사이에 다른 전이가 끝난 것이라 현재 상태를 그대로 준다.
    changed = db.execute(
        update(TrainerSchedule)
        .where(
            TrainerSchedule.id == session_id,
            TrainerSchedule.status == SCHEDULE_UPCOMING,
        )
        .values(
            status=SCHEDULE_CANCELLED,
            cancelled_at=datetime.now(timezone.utc),
            cancellation_source=source,
            cancellation_reason=reason[:200],
        )
    ).rowcount
    if changed != 1:
        db.commit()
        db.refresh(s)
        return _schedule_out(s)

    # 회원에게는 취소 사실만 간다 — 내부 사유는 트레이너가 보는 기록이다.
    # 삭제 경로와 같은 알림을 쓴다: 회원 입장에서 달라진 것은 "그 시간의 PT 가
    # 없어졌다" 하나뿐이고, 새 알림 종류를 만들 이유가 없다.
    if s.member_id is not None:
        notification_service.queue(
            db,
            member_id=s.member_id,
            kind=notification_service.EXERCISE,
            category=notification_service.MEMBER_SCHEDULE,
            title="일정이 취소되었어요",
            body=_slot_body(_member_visible_slot(s)),
        )
    db.commit()
    db.refresh(s)
    return _schedule_out(s)


def mark_session_no_show(
    db: Session, trainer_id: str, session_id: str
) -> ScheduleSessionOut | None:
    """예정 → 노쇼. 예약된 시간에 회원이 오지 않았다는 기록. (#871)

    취소와 따로 두는 까닭은 두 일이 다르기 때문이다 — 취소는 진행 전에 약속이
    거두어진 것이고, 노쇼는 약속이 그대로 있는데 회원이 오지 않은 것이다.

    회원 알림은 만들지 않는다. 오지 않은 사실을 앱 알림으로 통보하는 것은 이번
    범위의 결정이 아니고, 필요하면 정책을 따로 세운다.

    - 미래 일정 → ScheduleError(400): 아직 오지 않은 약속에 불참을 적을 수 없다.
    - 이미 노쇼 → 그대로 반환(멱등). 완료·취소 → ScheduleConflict(409).
    """
    s = _get_owned_session(db, trainer_id, session_id)
    if s is None:
        return None
    if s.status == SCHEDULE_GAP:
        raise ScheduleError("빈 슬롯은 노쇼 처리할 수 없습니다.")
    if s.date > _today().isoformat():
        raise ScheduleError("미래 일정은 노쇼 처리할 수 없습니다.")
    if s.status == SCHEDULE_NO_SHOW:
        return _schedule_out(s)  # 멱등 no-op
    if s.status in SCHEDULE_TERMINAL:
        raise ScheduleConflict(
            "완료·취소로 마무리된 세션은 노쇼 처리할 수 없습니다."
        )

    changed = db.execute(
        update(TrainerSchedule)
        .where(
            TrainerSchedule.id == session_id,
            TrainerSchedule.status == SCHEDULE_UPCOMING,
        )
        .values(status=SCHEDULE_NO_SHOW, no_show_at=datetime.now(timezone.utc))
    ).rowcount
    db.commit()
    db.refresh(s)
    if changed != 1:
        return _schedule_out(s)  # 동시 호출이 먼저 전이를 끝냄
    return _schedule_out(s)


# ---- 회원측 미러 (내 담당 코치 / 받은 루틴 / 채팅 / 내 세션) ----

def _active_link(db: Session, member_id: str) -> TrainerClient | None:
    """회원의 현재 담당(활성) 링크 — 가장 오래된 active 1건. 없으면 None.

    '현재 담당 코치 1명' 판정의 단일 소스. get_member_trainer_id / build_member_coach 등이
    각자 같은 쿼리를 중복하면 divergence 위험이 있어 여기로 모은다(리뷰 #281).
    """
    return db.scalar(
        select(TrainerClient)
        .where(TrainerClient.member_id == member_id, TrainerClient.active.is_(True))
        .order_by(TrainerClient.created_at)
        .limit(1)
    )


def get_member_trainer_id(db: Session, member_id: str) -> str | None:
    """회원의 현재 담당 트레이너 id. 활성(active) 링크만 인정하며 없으면 None.

    휴면(비활성) 링크는 '현재 담당'이 아니므로 제외한다(리뷰 재-#3) — 비활성 링크만
    가진 회원은 코치 조회/발신이 불가(404/빈 목록)해야 한다.
    """
    link = _active_link(db, member_id)
    return link.trainer_id if link is not None else None


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
    if links:
        points_coupon_service.cancel_renewal_coupons(db, member_id)
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


@dataclass(frozen=True)
class RoutineDayItem:
    """그날 걸려 있던 추천 개인운동 하나와 그날 했는지. (#2161)"""

    routine_id: str
    name: str
    #: 유산소|근력|스트레칭|기타 — 배정의 한글 유형 그대로다.
    type: str
    minutes: int
    #: 목록 순서. 트레이너가 정한 차례이자 "다음 운동" 을 셀 때의 기준이다.
    sort_order: int
    #: ai|trainer
    source: str
    done: bool
    #: 그날 완료로 남긴 분. 하지 않았으면 None.
    completed_minutes: int | None


@dataclass(frozen=True)
class RoutineDay:
    """하루치 추천 개인운동 — 그날 목록(정렬순)과 그날 완료. (#2161)"""

    date: date
    routines: list[RoutineDayItem]


def member_routine_days(
    db: Session, member_id: str, start: date, end: date
) -> list[RoutineDay]:
    """[start]~[end](양끝 포함)의 날마다 걸려 있던 추천 개인운동과 그날 완료. (#2161)

    추천 개인운동은 매일 새로 체크하는 목록이라, 기간을 되짚는 쪽(운동 AI 맞춤
    조언, #2162)은 날마다 "무엇이 걸려 있었고 무엇을 했나" 를 읽어야 한다 — 완료
    기록만 세면 안 한 날이 보이지 않는다.

    회원 화면(`build_member_routines`)과 같은 규칙이다: 지금의 담당 기준(담당이
    없으면 AI 자동 추천), 승인된 것만, 그날 걸려 있던 것만. 목록이 빈 날도 한
    칸을 차지한다 — 날짜가 빠지면 부르는 쪽이 "안 걸린 날" 과 "없는 날" 을 가를
    수 없다. 아직 오지 않은 날은 담지 않는다. 하루치 AI 추천을 새로 만들지 않는다
    — 읽기만 한다.

    쿼리는 기간 길이와 무관하게 둘이다(배정, 완료).
    """
    end = min(end, clock.today())
    if end < start:
        return []
    trainer_id = get_member_trainer_id(db, member_id)
    start_iso, end_iso = start.isoformat(), end.isoformat()
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == ROUTINE_APPROVED,
            # 기간과 겹치는 배정만 — 기간 안 어느 날이든 걸려 있었던 것.
            TrainerRoutine.active_from <= end_iso,
            or_(
                TrainerRoutine.ended_on.is_(None),
                TrainerRoutine.ended_on > start_iso,
            ),
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.created_at)
    ).all()
    done: dict[tuple[str, date], ExerciseSession] = {}
    if rows:
        for session in db.scalars(
            select(ExerciseSession).where(
                ExerciseSession.assigned_routine_id.in_([r.id for r in rows]),
                ExerciseSession.week_start
                >= exercise_service.monday_of_str(start_iso),
                ExerciseSession.week_start <= end_iso,
            )
        ).all():
            day = exercise_activity.activity_date_of(session)
            if day is not None and start <= day <= end:
                done[(session.assigned_routine_id, day)] = session

    days: list[RoutineDay] = []
    day = start
    while day <= end:
        iso = day.isoformat()
        items: list[RoutineDayItem] = []
        for row in rows:
            if row.active_from > iso or (
                row.ended_on is not None and row.ended_on <= iso
            ):
                continue
            completion = done.get((row.id, day))
            items.append(
                RoutineDayItem(
                    routine_id=row.id,
                    name=row.name,
                    type=row.type,
                    minutes=row.minutes,
                    sort_order=row.sort_order,
                    source=row.source,
                    done=completion is not None,
                    completed_minutes=(
                        completion.minutes if completion is not None else None
                    ),
                )
            )
        days.append(RoutineDay(date=day, routines=items))
        day += timedelta(days=1)
    return days


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


class RoutineDayInFuture(Exception):
    """아직 오지 않은 날의 개인운동 목록을 물었다. (#2161)"""


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
        raise RoutineDayInFuture("아직 오지 않은 날입니다.")
    trainer_id = get_member_trainer_id(db, member_id)
    if trainer_id is None:
        if day == today:
            auto_routine_service.ensure_auto_routines(db, member_id)
        return build_routines(db, member_id, None, for_member=True, day=day)
    return build_routines(db, member_id, trainer_id, for_member=True, day=day)


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
    return [_schedule_out(s) for s in rows]


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


# ---- 트레이너 프로필 ----

def _certifications(profile: TrainerProfile) -> list[str]:
    """자격증 JSON 을 방어적으로 디코드. 깨진 값은 빈 목록으로 (프로필 화면이
    500 으로 죽는 것보다 낫다)."""
    try:
        certs = json.loads(profile.certifications_json) if profile.certifications_json else []
    except json.JSONDecodeError:
        return []
    if not isinstance(certs, list) or not all(isinstance(c, str) for c in certs):
        return []
    return certs


def build_trainer_me(trainer: User, profile: TrainerProfile) -> TrainerMe:
    """`GET /trainer/me` 응답. 조회와 수정이 같은 표현을 쓰도록 분리."""
    return TrainerMe(
        id=trainer.id,
        name=trainer.name,
        email=trainer.email,
        phone=profile.phone,
        specialty=profile.specialty,
        career=f"{profile.career_years}년",
        intro=profile.intro,
        certifications=_certifications(profile),
        gym=TrainerGymOut(
            id=profile.gym_id,
            name=profile.gym_name,
            address=profile.gym_address,
            hours=profile.gym_hours,
            phone=profile.gym_phone,
        ),
    )


#: `TrainerMeUpdate` 가 받는 호환용 헬스장 문자열. 소속(`gym_id`)이 설정돼 있으면
#: 이 값들은 Place/GymProfile 에서 파생되므로 직접 수정할 수 없다(#452).
GYM_TEXT_FIELDS = ("gym_name", "gym_address", "gym_hours", "gym_phone")


class GymTextLockedByAffiliation(Exception):
    """소속이 설정된 프로필에서 호환 문자열만 따로 바꾸려 한 경우. (#452)"""


def update_trainer_profile(
    db: Session, trainer: User, profile: TrainerProfile, fields: dict
) -> TrainerMe:
    """보낸 필드만 반영한다. 자격증은 통째로 교체(부분 병합은 순서가 모호하다).

    `gym_id` 가 있으면 호환 문자열은 소속에서 파생된 값이라 여기서 못 고친다 —
    문자열만 바꾸면 소속과 화면이 어긋난다. `GymTextLockedByAffiliation` 을 올리고
    라우터가 409 로 돌려준다. 소속이 없는(레거시·해제) 프로필은 예전처럼 직접 적는다.
    """
    if profile.gym_id is not None and any(f in fields for f in GYM_TEXT_FIELDS):
        raise GymTextLockedByAffiliation

    if "certifications" in fields:
        certs = [c.strip() for c in (fields["certifications"] or []) if c.strip()]
        profile.certifications_json = json.dumps(certs, ensure_ascii=False)
    for column in ("phone", "specialty", "career_years", "intro", *GYM_TEXT_FIELDS):
        if column in fields:
            setattr(profile, column, fields[column])
    db.commit()
    db.refresh(profile)
    return build_trainer_me(trainer, profile)


# ---- 소속 헬스장 (#452) ----

def _apply_gym_texts(profile: TrainerProfile, place: Place | None, gym: GymProfile | None) -> None:
    """호환 문자열을 소속에서 파생시킨다 — 소속이 진실이고 문자열은 그 사본이다.

    트레이너 앱은 아직 `gym.{name,address,hours,phone}` 만 읽으므로, 소속을 바꿔도
    문자열이 그대로면 화면에는 예전 헬스장이 남는다. 해제(place=None)면 비운다 —
    떠난 헬스장의 이름을 남겨 두면 회원 쪽 코치 카드가 그 값으로 폴백한다
    (`_member_gym_out`).
    """
    if place is None:
        profile.gym_name = ""
        profile.gym_address = ""
        profile.gym_hours = ""
        profile.gym_phone = ""
        return
    # places.name(200) 이 trainer_profiles.gym_name(100) 보다 길다 — 넘치면 DB 가 막는다.
    profile.gym_name = place.name[:100]
    profile.gym_address = place.address[:300]
    # 영업시간·전화는 헬스장 부가 정보(GymProfile)에만 있다. 카카오에서 발견한
    # 헬스장은 부가 정보가 없어 빈 값이 정상이다.
    profile.gym_hours = (gym.weekday_hours if gym else "")[:50]
    profile.gym_phone = (gym.phone if gym else "")[:20]


def set_trainer_gym(
    db: Session, trainer: User, profile: TrainerProfile, gym_id: str
) -> TrainerMe | None:
    """소속 헬스장을 설정·변경한다. 유효한 헬스장이 아니면 None(라우터 404).

    `places` 에 있고 category 가 'fitness' 인 곳만 받는다 — 상담 대상 검증
    (`consultation_service._validate_target`)·헬스장 디렉터리와 같은 조건이라야
    소속을 설정한 트레이너가 회원 화면에 제대로 뜬다(#451, #443).
    """
    place = db.scalar(
        select(Place).where(Place.id == gym_id, Place.category == "fitness")
    )
    if place is None:
        return None

    profile.gym_id = place.id
    _apply_gym_texts(profile, place, db.get(GymProfile, place.id))
    db.commit()
    db.refresh(profile)
    return build_trainer_me(trainer, profile)


def clear_trainer_gym(db: Session, trainer: User, profile: TrainerProfile) -> TrainerMe:
    """소속 해제. 원래 없었어도 성공한다 — 해제는 두 번 눌러도 오류가 아니다.

    회원↔헬스장 링크(`member_gyms`)는 건드리지 않는다. 회원이 직접 연결한 헬스장은
    트레이너가 이적해도 회원의 선택으로 남는다(#444).
    """
    profile.gym_id = None
    _apply_gym_texts(profile, None, None)
    db.commit()
    db.refresh(profile)
    return build_trainer_me(trainer, profile)


# ---- 주간 리포트 ----

def week_start_of(day: date) -> date:
    """그 주의 월요일."""
    return day - timedelta(days=day.weekday())


def build_weekly_report(
    db: Session, trainer_id: str, member_id: str, week_start: date
) -> WeeklyReportOut:
    """담당 고객 한 명의 한 주.

    O2O 코칭에서 회원이 재등록하는 이유는 "좋아졌다"를 볼 수 있을 때다. 여기서
    쓰는 값은 전부 두 앱이 이미 공유하는 데이터(식단·운동기록·스케줄)이며 새로
    수집하는 것이 없다.
    """
    monday = week_start_of(week_start)
    sunday = monday + timedelta(days=6)
    monday_str, sunday_str = monday.isoformat(), sunday.isoformat()

    member = db.get(User, member_id)
    member_name = member.name if member else "고객"

    # 취소·노쇼는 세지 않는다(#871). `sessions_booked` 는 "이번 주에 잡혀 있던
    # 수업" 이고 리포트는 그 분모로 이행을 읽는다 — 진행되지 않은 약속을 분모에
    # 넣으면 트레이너 사정의 취소가 회원의 낮은 이행률로 보인다. 취소·노쇼
    # 자체에 패널티를 주는 지표는 이번 범위가 아니라 별도 정책이다.
    sessions = db.scalars(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.date >= monday_str,
            TrainerSchedule.date <= sunday_str,
            TrainerSchedule.status.in_((SCHEDULE_UPCOMING, SCHEDULE_DONE)),
        )
    ).all()
    booked = len(sessions)
    done = sum(1 for s in sessions if s.status == SCHEDULE_DONE)

    hist = db.scalars(
        select(RoutineHistory).where(
            RoutineHistory.member_id == member_id,
            RoutineHistory.date >= monday_str,
            RoutineHistory.date <= sunday_str,
            or_(RoutineHistory.trainer_id.is_(None), RoutineHistory.trainer_id == trainer_id),
        )
    ).all()
    week = _week_completion(hist, monday)
    # 요일 칸은 회원의 실제 운동 기록에서 만든다(#1288). 기록이 (그 주 월요일,
    # 요일) 로 저장되므로 월요일 하나로 한 주가 그대로 걸린다.
    exercise_rows = db.scalars(
        select(ExerciseSession)
        .where(
            ExerciseSession.user_id == member_id,
            ExerciseSession.week_start == monday_str,
        )
        # 한 날에 여럿이면 한 순서로 적는다 — 정렬을 두지 않으면 같은 주를 두 번
        # 열 때 칸 안의 줄 순서가 바뀐다.
        .order_by(ExerciseSession.completed_at, ExerciseSession.id)
    ).all()
    days = _week_days(list(exercise_rows), week)
    recorded = [d for d in week if d > 0]
    # 기록이 하나도 없으면 null — 0% 로 보고하면 "아무것도 안 했다"는 거짓말이 된다.
    completion_avg = round(sum(recorded) / len(recorded)) if recorded else None

    diet = db.scalars(
        select(DietEntry).where(
            DietEntry.user_id == member_id,
            DietEntry.date >= monday_str,
            DietEntry.date <= sunday_str,
        )
    ).all()
    diet_rows = list(diet)
    sodium_week = _sodium_week(diet_rows, monday)
    # 기록이 있는 날만 센다 — 아직 오지 않은 요일의 0 까지 나누면 주 초반
    # 평균이 실제보다 낮아진다(로스터의 `sodiumWeekAvg` 와 같은 규칙).
    recorded_sodium = [mg for mg in sodium_week if mg > 0]
    sodium_over_days = sum(1 for mg in sodium_week if mg > SODIUM_TARGET_MG)
    sodium_avg = (
        round(sum(recorded_sodium) / len(recorded_sodium)) if recorded_sodium else None
    )

    # 회원이 적어 둔 하루 목표. 없으면 null 로 두고 판정 쪽이 공통 상수로
    # 되돌아간다 — 여기서 상수를 채워 보내면 화면이 '이 회원의 목표'와
    # '기본값'을 구분할 수 없다(#1430).
    profile = db.scalars(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    ).first()

    report = WeeklyReportOut(
        member_id=member_id,
        member_name=member_name,
        calorie_target=profile.daily_calories if profile else None,
        sodium_target=profile.daily_sodium_mg if profile else None,
        sugar_target=profile.daily_sugar_g if profile else None,
        carbs_target=profile.daily_carbs_g if profile else None,
        protein_target=profile.daily_protein_g if profile else None,
        fat_target=profile.daily_fat_g if profile else None,
        week_start=monday_str,
        week_end=sunday_str,
        sessions_booked=booked,
        sessions_done=done,
        completion_avg=completion_avg,
        sodium_over_days=sodium_over_days,
        sodium_avg=sodium_avg,
        week_completion=week,
        days=days,
        sodium_week=sodium_week,
        calories_week=_calories_week(diet_rows, monday),
        sugar_week=_sugar_week(diet_rows, monday),
        carbs_week=_macro_week(diet_rows, monday, lambda e: e.carbs_g),
        protein_week=_macro_week(diet_rows, monday, lambda e: e.protein_g),
        fat_week=_macro_week(diet_rows, monday, lambda e: e.fat_g),
        message="",
    )
    return report.model_copy(update={"message": report_message(report)})


def report_message(report: WeeklyReportOut) -> str:
    """회원 채팅 스레드에 그대로 들어갈 본문.

    별도 리포트 함이 아니라 이미 읽고 있는 대화에 도착하도록 평문으로 쓴다 —
    시스템 덤프가 아니라 담당 트레이너가 쓴 말처럼 보여야 한다.

    리포트 요약 카드(`trainer_report_summary_service`)와 **역할이 다르다.**
    카드는 트레이너가 훑는 메모라 짧고 건조하다. 이 글은 회원이 받는 편지라
    문단으로 쓰고, 수치마다 그래서 무엇을 하면 되는지를 붙인다. 트레이너가
    손보지 않고 그대로 보내도 사람이 쓴 것으로 읽혀야 한다.

    기록이 없는 항목은 문장을 아예 뺀다 — '이행률 0%'는 거짓말이다.
    """
    start = date.fromisoformat(report.week_start)
    end = date.fromisoformat(report.week_end)
    good = (report.completion_avg or 0) >= 70 and report.sodium_over_days <= 2
    period = f"{start.month}월 {start.day}일 – {end.month}월 {end.day}일"

    paragraphs: list[str] = [
        # 첫 줄에 무슨 메시지인지가 있어야 한다 — 회원의 대화방에는 다른
        # 메시지도 함께 쌓인다.
        f"{report.member_name}님, {period} 주간 리포트 정리해서 보내드려요."
    ]

    workout: list[str] = []
    if report.completion_avg is not None:
        # `이번 주` 로 시작하지 않는다 — 지난 주 리포트에도 그대로 나가는
        # 문장이고, 어느 주인지는 첫 줄의 날짜 범위가 이미 말한다(#1177).
        workout.append(
            f"운동은 평균 {report.completion_avg}%로 잘 따라오셨어요."
            if report.completion_avg >= 70
            else f"운동 이행률은 평균 {report.completion_avg}%였어요. 많이 바쁘셨나 봐요."
        )
    skipped = _skipped_names(report)
    if skipped:
        workout.append(
            f"다만 {_topic(', '.join(skipped))} 건너뛰셨더라고요. 컨디션 때문이었다면 "
            "다음 세션 때 말씀해 주세요. 대체 동작으로 바꿔 둘게요."
        )
    if workout:
        paragraphs.append(" ".join(workout))

    diet: list[str] = []
    if report.sodium_avg is not None:
        # 평균과 초과일을 한 문장에 뒤섞지 않는다. `평균 1,916mg으로 목표를
        # 3일 넘겼어요` 는 평균이 목표를 넘긴 것처럼 읽힌다. 목표도 문장에
        # 박아 두지 않는다 — 기준이 바뀌면 문장만 옛말을 한다(#1177).
        diet.append(
            f"나트륨은 하루 평균 {report.sodium_avg:,}mg이었고, "
            f"목표({SODIUM_TARGET_MG:,}mg)를 넘긴 날이 "
            f"{report.sodium_over_days}일이었어요. 국물을 절반만 남기셔도 "
            "하루 400~500mg은 줄어듭니다."
            if report.sodium_over_days > 0
            else f"나트륨은 하루 평균 {report.sodium_avg:,}mg으로 "
            f"목표({SODIUM_TARGET_MG:,}mg) 안에서 잘 지키고 계세요."
        )
    recorded = [v for v in report.calories_week if v > 0]
    if recorded:
        diet.append(
            f"칼로리는 하루 평균 {round(sum(recorded) / len(recorded)):,}kcal이에요."
        )
    if diet:
        paragraphs.append(" ".join(diet))

    if len(paragraphs) == 1:
        # 인사말만 남았다 — 가리킬 '이 부분'이 없다. 기록이 없는 주에 격려부터
        # 하면 회원이 무엇을 하라는 말인지 알 수 없다.
        paragraphs.append(
            "이 주에는 남은 기록이 없어서 정리해 드릴 내용이 없네요. "
            "다음 주 시작을 같이 잡아 봐요."
        )
    else:
        paragraphs.append(
            "정말 잘하셨어요. 다음 주도 이 페이스 그대로 가요!"
            if good
            else "다음 주에는 이 부분만 같이 신경 써 봐요. 루틴은 제가 조정해서 올려둘게요."
        )
    return "\n\n".join(paragraphs)


def _topic(word: str) -> str:
    """`은`/`는` 을 받침에 맞춰 붙인다.

    `은(는)` 은 사람이 쓴 글로 읽히지 않는다 — 회원이 그대로 받는 문장이라
    기계가 쓴 티가 나는 자리를 남기지 않는다.
    """
    if not word:
        return word
    last = word[-1]
    has_batchim = "가" <= last <= "힣" and (ord(last) - 0xAC00) % 28 != 0
    return f"{word}{'은' if has_batchim else '는'}"


def _skipped_names(report: WeeklyReportOut) -> list[str]:
    """그 주에 건너뛴 운동 이름. 이행률이 왜 100%가 아닌지의 답이다.

    분량을 뗀 이름으로 묶는다 — 같은 스트레칭을 요일마다 건너뛰면 예전에는
    `하체 스트레칭 10분, 하체 스트레칭 5분, 하체 스트레칭 15분` 이 되어, 서로
    다른 운동 셋을 빠뜨린 것처럼 읽혔다(#1177).
    """
    names: list[str] = []
    for day in report.days:
        for line in day.exercises:
            if "✗" not in line:
                continue
            name = exercise_base_name(line)
            if name and name not in names:
                names.append(name)
    return names[:3]


#: 운동 이름 뒤에 붙는 그날의 분량(`하체 스트레칭 10분`, `벤치프레스 4세트 · 10회 · 40kg`).
_EXERCISE_AMOUNT_RE = re.compile(r"\s*\d+(?:\.\d+)?\s*(?:분|초|kg|km|회|세트)$")


def exercise_base_name(line: str) -> str:
    """운동 한 줄에서 분량 표기를 떼어 낸 이름.

    초안·요약이 운동을 **묶어 세는** 자리에서는 분량이 같은 운동을 서로 다른
    운동으로 갈라 놓는다. 앱의 `exerciseBaseName` 과 같은 규칙이다(#1177).
    """
    name = line.replace("✗", "").replace("✓", "").strip()
    head, sep, _ = name.partition("·")
    if sep:
        name = head.strip()
    return _EXERCISE_AMOUNT_RE.sub("", name).strip()


# ---- 리포트 피드백 초안 (#821) ----

def get_report_feedback(
    db: Session, trainer_id: str, member_id: str, week: date
) -> ReportFeedbackOut:
    """그 주에 저장해 둔 피드백 초안. 없으면 빈 본문으로 답한다.

    404 를 쓰지 않는 이유: 초안이 없는 것은 오류가 아니라 아직 쓰지 않은
    정상 상태다. 화면은 빈 본문을 받으면 자동 생성 문구를 그대로 쓴다.
    """
    row = _report_feedback_row(db, trainer_id, member_id, week)
    return ReportFeedbackOut(
        member_id=member_id,
        week_start=week.isoformat(),
        body=row.body if row else "",
        updated_at=row.updated_at if row else None,
    )


def save_report_feedback(
    db: Session, trainer_id: str, member_id: str, week: date, body: str
) -> ReportFeedbackOut:
    """그 주의 피드백 초안을 저장한다. 같은 주에 다시 저장하면 덮어쓴다.

    편집기가 항목 단위 diff 가 아니라 입력창의 현재 전체 문구를 들고 있으므로
    통째로 교체한다. 빈 문자열도 유효한 저장이다 — 트레이너가 지운 것을
    "저장한 적 없음" 으로 되돌리면 다음에 열 때 지운 문구가 되살아난다.
    """
    row = _report_feedback_row(db, trainer_id, member_id, week)
    now = datetime.now(timezone.utc)
    if row is None:
        row = TrainerReportFeedback(
            id=f"rfb-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            week_start=week.isoformat(),
            body=body,
            created_at=now,
            updated_at=now,
        )
        db.add(row)
    else:
        row.body = body
        row.updated_at = now
    db.commit()
    db.refresh(row)
    return ReportFeedbackOut(
        member_id=member_id,
        week_start=week.isoformat(),
        body=row.body,
        updated_at=row.updated_at,
    )


def _report_feedback_row(
    db: Session, trainer_id: str, member_id: str, week: date
) -> TrainerReportFeedback | None:
    return db.scalar(
        select(TrainerReportFeedback).where(
            TrainerReportFeedback.trainer_id == trainer_id,
            TrainerReportFeedback.member_id == member_id,
            TrainerReportFeedback.week_start == week.isoformat(),
        )
    )


# ---- 알림 수신 설정 ----

def build_notification_settings(
    profile: TrainerProfile,
) -> TrainerNotificationSettings:
    """`GET /trainer/me/settings` 응답."""
    return TrainerNotificationSettings(
        notify_new_message=profile.notify_new_message,
        notify_session_reminder=profile.notify_session_reminder,
        reminder_lead_minutes=profile.reminder_lead_minutes,
    )


def update_notification_settings(
    db: Session, profile: TrainerProfile, fields: dict
) -> TrainerNotificationSettings:
    """보낸 필드만 반영한다."""
    for column in (
        "notify_new_message",
        "notify_session_reminder",
        "reminder_lead_minutes",
    ):
        if column in fields:
            setattr(profile, column, fields[column])
    db.commit()
    db.refresh(profile)
    return build_notification_settings(profile)
