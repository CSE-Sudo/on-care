"""
AI 코치 서비스.

설계(사용자 요구사항 반영):
- 코칭을 '식단 코치'와 '운동 코치'로 도메인 분리해서 각각 생성한 뒤 합친다.
- STEP 7에서 각 도메인 코치를 RAG 기반으로 교체한다:
    * 검색 자료 = 개인 문서(환자 데이터, user_id=본인) + 공공 문서(user_id=NULL)
    * 식단 코치는 domain='diet' 자료를, 운동 코치는 domain='exercise' 자료를 위주로 검색
    * 다른 사용자의 개인 문서는 절대 섞이지 않음 (user_id 격리)

현재(STEP 6)는 RAG 전이라, 사용자의 실제 식단·운동 데이터를 읽어
'규칙 기반'으로 제안을 생성한다. 구조(도메인 분리)는 STEP 7과 동일하게 유지하므로
나중에 내부 구현만 LLM 호출로 바꾸면 된다.
"""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import DietEntry, ExerciseSession
from app.schemas.misc_api import AiCoachFeedback, CoachSuggestion
from app.services import diet_service
from app.services.exercise_service import monday_of_this_week_str

#: 이번 주에 나트륨 초과일이 이만큼 쌓이면 "계속 높았다" 패턴으로 본다. 하루이틀은
#: 우연일 수 있어 제외하고, 사흘부터는 오늘 하루가 괜찮아도 짚어줄 근거로 본다.
#: 기록일 대비 비율이 아니라 **절대 일수**다 — 이 주가 처음 기록을 시작한 주라도
#: (기록일이 적어도) 사흘 다 초과였다면 이미 패턴이다.
_SODIUM_PATTERN_MIN_DAYS = 3


def _week_bounds() -> tuple[str, str]:
    """이번 주(월~오늘, `YYYY-MM-DD`). 아직 오지 않은 날은 기록이 없어 의미가 없다."""
    today = clock.today()
    monday = today - timedelta(days=today.weekday())
    return monday.isoformat(), today.isoformat()


def _month_bounds() -> tuple[str, str]:
    """이번 달(1일~오늘, `YYYY-MM-DD`)."""
    today = clock.today()
    return today.replace(day=1).isoformat(), today.isoformat()


def _week_stats(db: Session, user_id: str) -> diet_service.DietPeriodStats:
    week_from, week_to = _week_bounds()
    return diet_service.period_stats(db, user_id, week_from, week_to)


def _month_stats(db: Session, user_id: str) -> diet_service.DietPeriodStats:
    month_from, month_to = _month_bounds()
    return diet_service.period_stats(db, user_id, month_from, month_to)


def diet_period_context(db: Session, user_id: str) -> str:
    """이번 주·이번 달 식단 누적 요약 — AI 코칭이 하루 스냅샷 대신 참고할 문장(#933).

    회원 앱 식단 탭의 `오늘/이번 주/이번 달` 과 같은 기간 개념을 코칭 경로에도
    준다. 벡터 검색(`coach/rag.py`)은 의미상 가까운 개별 기록 몇 건만 뽑아오므로
    "이번 주 평균 나트륨" 같은 계산된 값은 만들지 못한다 — 그 값을 이 함수가 낸다.
    """
    week = _week_stats(db, user_id)
    month = _month_stats(db, user_id)

    lines: list[str] = []
    if not week.empty:
        lines.append(
            f"- 이번 주 {week.days_logged}일 기록, "
            f"나트륨 권장량({diet_service.SODIUM_LIMIT_MG}mg) 초과 {week.days_over_sodium}일, "
            f"평균 나트륨 {week.avg_sodium_mg}mg"
        )
    if not month.empty:
        lines.append(
            f"- 이번 달 {month.days_logged}일 기록, "
            f"평균 칼로리 {month.avg_calories}kcal, 평균 당류 {month.avg_sugar_g}g"
        )
    if not lines:
        return ""
    return "[이번 주·이번 달 식단 요약]\n" + "\n".join(lines)


def _diet_today_priority(db: Session, user_id: str) -> CoachSuggestion | None:
    """오늘 기록이 없거나 오늘 자체가 초과인 "일일 우선" 메시지.

    이 둘은 RAG/LLM 근거가 있어도 절대 다른 문구로 덮이면 안 된다(#933) —
    "오늘 기록이 없다" 는 사실 자체가 코칭의 핵심인데, AI 가 일반론으로 갈아
    치우면 그 사실이 사용자에게 전달되지 않는다. `domain_coaches.diet_coach`
    가 이 값이 있으면 RAG 를 아예 건너뛰고 그대로 반환한다.

    None 이면 "일일 우선" 대상이 아니라는 뜻 — 주간 패턴 판단은 호출부가
    이어서 한다.

    호출부는 이 함수를 **한 번만** 불러야 한다. `diet_coach()` 와
    `_diet_suggestion()` 이 각자 따로 부르면, 그 사이 새 기록이 들어와(예:
    이 요청과 동시에 들어온 식단 기록 저장) 두 번째 호출이 첫 번째와 다른
    결과를 낼 수 있다 — RAG 경로는 "오늘 정상"으로 보고 진행했는데 폴백은
    "오늘 초과"를 반환하면, 성공한 RAG 응답이 그 초과 경고를 조용히 덮는다
    (코드 리뷰 지적).
    """
    today = clock.today_iso()
    rows = db.scalars(
        select(DietEntry).where(DietEntry.user_id == user_id).where(DietEntry.date == today)
    ).all()
    total_na = sum(r.sodium_mg for r in rows)

    if not rows:
        return CoachSuggestion(
            tag="diet", title="오늘 식단을 기록해 보세요",
            body="사진 한 장이면 칼로리와 나트륨을 분석해 드려요. 첫 끼니부터 시작해 볼까요?",
        )
    if total_na > diet_service.SODIUM_LIMIT_MG:
        return CoachSuggestion(
            tag="diet", title="나트륨 섭취가 많아요",
            body=f"오늘 나트륨이 약 {total_na}mg 으로 권장량을 넘었어요. "
                 "저녁은 국물을 남기고 채소를 늘려 균형을 맞춰봐요.",
        )
    return None


def _diet_weekly_or_default(db: Session, user_id: str) -> CoachSuggestion:
    """오늘이 "일일 우선" 대상이 아닐 때(정상)의 코칭 — 이번 주 나트륨 패턴 또는
    기본 문구.

    `_diet_today_priority()` 가 이미 None 을 반환했다고 가정하고 오늘 조회를
    다시 하지 않는다 — `diet_coach()` 가 오늘 판단을 한 번만 하도록 이 함수를
    따로 뗐다(위 TOCTOU 코멘트 참고).
    """
    # 오늘은 괜찮아도 이번 주 내내 나트륨이 높았다면 짚어준다(#933) — 하루만 보면
    # "오늘 안정적" 문구가 매번 반복되어, 거의 매일 초과하던 회원도 오늘 하루
    # 낮았다는 이유만으로 계속 잘하고 있다는 인상을 준다.
    week = _week_stats(db, user_id)
    # days_over_sodium 은 days_logged 를 넘을 수 없으니 기록일수 조건은 따로 안
    # 둔다 — 초과일이 기준을 채우면 기록일수는 이미 그만큼 채워진 것이다.
    if week.days_over_sodium >= _SODIUM_PATTERN_MIN_DAYS:
        return CoachSuggestion(
            tag="diet", title="이번 주 나트륨이 계속 높았어요",
            body=f"이번 주 기록한 {week.days_logged}일 중 {week.days_over_sodium}일 "
                 "나트륨이 권장량을 넘었어요. 오늘처럼 낮게 유지하는 날을 늘려봐요.",
        )
    return CoachSuggestion(
        tag="diet", title="식단 균형이 좋아요",
        body="오늘 나트륨 섭취가 안정적이에요. 이대로 꾸준히 유지해봐요!",
    )


def _diet_suggestion(db: Session, user_id: str) -> CoachSuggestion:
    """식단 도메인 코치 (STEP 7에서 RAG+LLM 으로 교체) — 규칙 기반 폴백 전체.

    오늘 우선 여부와 이번 주 패턴을 한 번에 판단하는 단독 진입점. `diet_coach()`
    는 오늘 조회를 한 번만 하려고 이 함수 대신 `_diet_today_priority()` +
    `_diet_weekly_or_default()` 를 직접 나눠 쓴다 — 이 함수는 그 조합과
    같은 결과를 낸다.
    """
    priority = _diet_today_priority(db, user_id)
    if priority is not None:
        return priority
    return _diet_weekly_or_default(db, user_id)


def _exercise_suggestion(db: Session, user_id: str) -> CoachSuggestion:
    """운동 도메인 코치 (STEP 7에서 RAG+LLM 으로 교체)."""
    week = monday_of_this_week_str()
    rows = db.scalars(
        select(ExerciseSession)
        .where(ExerciseSession.user_id == user_id)
        .where(ExerciseSession.week_start == week)
    ).all()
    total_min = sum(r.minutes for r in rows)

    if total_min == 0:
        return CoachSuggestion(
            tag="exercise", title="이번 주 운동을 시작해 보세요",
            body="가벼운 30분 걷기부터 시작하면 혈압·혈당 관리에 도움이 돼요.",
        )
    if total_min < 150:
        return CoachSuggestion(
            tag="exercise", title="조금만 더 움직여봐요",
            body=f"이번 주 {total_min}분 운동했어요. 주 150분을 목표로 가볍게 더해봐요.",
        )
    return CoachSuggestion(
        tag="exercise", title="운동량이 충분해요",
        body=f"이번 주 {total_min}분! 권장 운동량을 잘 채우고 있어요. 멋져요!",
    )


def _hydration_suggestion(db: Session, user_id: str) -> CoachSuggestion:
    """수분 제안 — 오늘 나트륨/시간대 기반 간단 규칙(고정 문구 대체).

    RAG/LLM 전까지 규칙 기반으로 개인화한다: 나트륨이 높으면 배출을 위해 물을
    더 권하고, 그렇지 않으면 시간대에 맞춰 다르게 안내한다.
    """
    today = clock.today_iso()
    total_na = sum(
        r.sodium_mg for r in db.scalars(
            select(DietEntry).where(DietEntry.user_id == user_id)
            .where(DietEntry.date == today)
        ).all()
    )
    if total_na > diet_service.SODIUM_LIMIT_MG:
        return CoachSuggestion(
            tag="hydration", title="물을 더 챙기세요",
            body=(
                f"오늘 나트륨이 {total_na}mg으로 높아요. "
                "물을 충분히 마시면 나트륨 배출에 도움이 됩니다."
            ),
        )
    hour = clock.now().hour
    if hour < 11:
        body = "아침 물 한 잔으로 하루를 시작해 보세요. 하루 6~8잔이 목표예요."
    elif hour < 18:
        body = "지금까지 물을 얼마나 드셨나요? 틈틈이 마셔 6~8잔을 채워요."
    else:
        body = "오늘 물 6~8잔을 채웠는지 확인해요. 자기 전 과한 수분은 피하세요."
    return CoachSuggestion(
        tag="hydration", title="수분 섭취 잊지 마세요", body=body,
    )


def build_feedback(db: Session, user_id: str, user_name: str) -> AiCoachFeedback:
    """
    도메인별 코치를 각각 호출해 합친다.

    STEP 7: 식단·운동 코치는 RAG 기반(domain_coaches)으로 동작.
    RAG 가 불가(키 미설정/자료 없음)하면 내부에서 STEP 6 규칙 기반으로 자동 폴백.
    """
    hour = clock.now().hour
    if hour < 11:
        greeting = f"{user_name}님, 좋은 아침이에요! 오늘도 건강하게 시작해봐요."
    elif hour < 18:
        greeting = f"{user_name}님, 오늘 하루도 잘 보내고 계신가요?"
    else:
        greeting = f"{user_name}님, 오늘 하루 어떠셨나요? 마무리도 건강하게요."

    # 지연 import (순환 참조 방지: domain_coaches 가 coach_service 를 import)
    from app.services.coach.domain_coaches import diet_coach, exercise_coach

    suggestions = [
        diet_coach(db, user_id),       # 식단 RAG 코치 (실패 시 규칙 폴백)
        exercise_coach(db, user_id),   # 운동 RAG 코치 (실패 시 규칙 폴백)
        _hydration_suggestion(db, user_id),  # 나트륨/시간대 기반 수분 제안
    ]
    return AiCoachFeedback(greeting=greeting, suggestions=suggestions)
