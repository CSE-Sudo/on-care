"""회원 실데이터를 바탕으로 트레이너용 맞춤 루틴 후보를 생성한다.

설정된 코치 LLM(OpenAI/Gemini/LiteLLM)을 우선 호출하고, 키 미설정·네트워크
오류·잘못된 JSON 응답이면 결정론적인 규칙 기반 후보로 폴백한다.
"""
from __future__ import annotations

import json
import logging
import re
import threading
import time
# `time` 은 stdlib 모듈로 두고(경과 시간 측정), 자정 시각은 별칭으로 받는다.
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from datetime import time as time_of_day

from pydantic import ValidationError
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.services import health_focus
from app.core import clock, metrics
from app.models.models import (
    ChatMessage,
    DietEntry,
    HealthProfile,
    RoutineHistory,
    TrainerClient,
    TrainerClientMemo,
    TrainerRoutine,
)
from app.schemas.trainer_api import (
    ROUTINE_CHAT_MAX_MESSAGES,
    ROUTINE_INSIGHT_MEMO_DAYS,
    ROUTINE_INSIGHT_MEMO_MAX,
    RecommendationStatus,
    RoutineIntensityPreference,
    RoutineOptionAnalysisOut,
    RoutineOptionPlanOut,
    RoutineOptionsOut,
    RoutineOptionsRequest,
)
from app.services import exercise_types, routine_ai
from app.services.coach import prompt_safety
from app.services.coach.llm import DEFAULT_THINKING_BUDGET, get_coach_llm

logger = logging.getLogger(__name__)


#: 개인화 분석에 쓰는 최근 기간(일) — 약 6주. 이보다 넓히면 오래된 루틴이
#: 지금의 습관인 것처럼 잡히고, 좁히면 격주 세션 패턴을 놓친다(#776).
HISTORY_LOOKBACK_DAYS = 42

#: 이 미만이면 판단할 개인 패턴이 없다 — 목표 기반 기본값을 쓴다.
MIN_SESSIONS_FOR_LEARNING = 2
#: 이 이상 + 서로 다른 주에 걸쳐 있고 + 반복된 운동이 있어야 "패턴이 있다"고 본다.
MIN_SESSIONS_FOR_PERSONALIZED = 6
MIN_DISTINCT_WEEKS_FOR_PERSONALIZED = 3
MIN_REPEAT_FOR_PERSONALIZED = 3

#: 기록이 없을 때 쓰는 기본 조건. 회원 앱 최초 추천 문구와 맞춰 30분/보통으로 둔다.
DEFAULT_AVAILABLE_MINUTES = 30
DEFAULT_INTENSITY: RoutineIntensityPreference = "moderate"

#: `exercises_json` 한 줄에서 운동 이름을 뽑는다 — 완료 기록은
#: `"레그프레스 3세트"` 처럼 이름 뒤에 세트/횟수가 자유 텍스트로 붙는다(모델
#: docstring 참고). 숫자가 시작되는 지점 앞까지만 이름으로 본다.
_TRAILING_COUNT_RE = re.compile(r"\s*\d.*$")


@dataclass
class _HistoryAnalysis:
    """회원의 최근 운동 기록에서 뽑은 개인화 판단 재료(#776)."""

    status: RecommendationStatus = "template"
    session_count: int = 0
    frequent_exercises: list[str] = field(default_factory=list)
    suggested_available_minutes: int | None = None
    suggested_intensity: RoutineIntensityPreference | None = None


class LLMBusyError(RuntimeError):
    """LLM 동시 호출 한도가 차서 호출을 시도조차 하지 않았음을 알린다.

    "실패"와 구분해야 로그에서 장애와 포화를 헷갈리지 않는다.
    """


#: LLM 응답을 기다리는 최대 시간(초).
#:
#: 생성 왕복이 실측 3~6초다(#579, 근거는 `config.py` 의 `routine_options_per_minute`
#: 주석). 최악 실측의 두 배를 여유로 잡았다 — 6초에 바짝 붙이면 정상 호출이
#: 산발적으로 잘려 트레이너가 이유 없이 규칙형을 받는다.
#:
#: 상한이 있다는 것 자체가 요점이다. 이 값이 없으면 끊어 주는 건 SDK 의 HTTP
#: 타임아웃뿐인데 Gemini 30초, OpenAI/LiteLLM 60초라 워커 하나가 그만큼 묶인다.
LLM_TIMEOUT_SEC = 12.0

#: 사고 예산. 지연을 지배하는 값이라 호출부마다 따로 두지 않는다(#579).
LLM_THINKING_BUDGET = DEFAULT_THINKING_BUDGET

#: 동시에 진행할 LLM 호출 수.
LLM_MAX_CONCURRENCY = 4

#: 왜 식단 추천(`diet_recommendation_service`)과 같은 코드를 공통 헬퍼로 뽑지 않았나.
#:
#: 1. **풀을 공유하면 안 된다.** 헬퍼 하나에 executor·세마포어를 두면 홈 화면
#:    추천이 몰릴 때 트레이너 루틴 생성이 같이 굶는다. 서로 무관한 기능이 서로의
#:    포화에 끌려가는 건 중복을 없앤 대가로 치르기엔 비싸다.
#: 2. 호출부마다 인스턴스를 만드는 헬퍼라면 1 은 피하지만, 그러려면 식단 쪽을 함께
#:    고쳐야 한다. 그쪽 포화 테스트가 모듈 전역 `_llm_slots` 를 monkeypatch 하고
#:    있어 테스트까지 따라 바뀐다 — 루틴 경로 버그를 고치는 이슈가 이미 검증된
#:    코드를 건드리는 범위로 번진다.
#: 3. 두 경로는 튜닝이 다르다(여긴 12초, 식단은 6초). 값이 갈리면 공통화의 이득도
#:    그만큼 줄어든다.
#:
#: 세 번째 호출부가 생기면 그때 인스턴스형 헬퍼로 뽑는 편이 낫다.
_executor = ThreadPoolExecutor(
    max_workers=LLM_MAX_CONCURRENCY, thread_name_prefix="routine-options-llm"
)

#: 진행 중인 LLM 호출 수를 워커 수로 제한한다.
#:
#: `future.result(timeout=...)` 은 **기다리기를 포기할 뿐 작업을 취소하지 않는다.**
#: 그래서 느린 호출이 몰리면 워커가 전부 묶이고 이후 submit 은 무한 큐에 쌓인다.
#: 그 상태에서는 새 요청이 LLM 을 불러 보지도 못한 채 큐에서 타임아웃까지 기다렸다
#: 폴백한다 — 규칙형만 나오면서 응답만 매번 느려진다.
#: 빈 자리가 없으면 기다리지 않고 곧장 규칙 폴백으로 내려간다.
_llm_slots = threading.BoundedSemaphore(LLM_MAX_CONCURRENCY)

#: 프롬프트에 싣는 최근 대화 범위. 넓히면 오래된 통증 호소가 이미 나은 뒤에도
#: 계속 루틴을 눌러 버리고, 좁히면 지난주 부상이 사라진다.
CHAT_LOOKBACK_DAYS = 14

#: 프롬프트에 싣는 최대 대화 수(최신 우선). 스키마가 단일 출처다.
CHAT_MAX_MESSAGES = ROUTINE_CHAT_MAX_MESSAGES

#: 발화 한 줄의 길이 상한. 긴 상담 메시지 하나가 프롬프트를 독차지하지 않게 자른다.
CHAT_MAX_CHARS = 200

#: 채팅 감지 메모를 읽는 창과 건수. 스키마가 단일 출처다(#1655).
INSIGHT_MEMO_LOOKBACK_DAYS = ROUTINE_INSIGHT_MEMO_DAYS
INSIGHT_MEMO_MAX = ROUTINE_INSIGHT_MEMO_MAX

# JSON 예시의 중괄호가 본문에 그대로 들어가므로 f-string 을 쓰지 않고 이어 붙인다.
_SYSTEM_PROMPT = (
    """\
당신은 만성질환 위험군을 돕는 전문 운동 코치입니다.
제공된 회원 분석과 트레이너 조건만 사용해 서로 다른 맞춤 루틴 두 개를 만드세요.
의학적 진단이나 치료를 단정하지 말고, 통증·부상 메모가 있으면 저충격 대안을 우선하세요.

안전이 먼저입니다. 아래 순서로 반영하세요.
1. member_analysis.conditions (질환·통증·부상 등 운동 시 주의사항)
2. member_analysis.note (트레이너가 직접 적은 메모)
3. member_analysis.insight_memos (트레이너가 채팅 감지에서 남긴 최근 7일 메모)
4. member_analysis.recent_messages 의 통증·컨디션 언급
conditions 나 note 에 특정 부위의 통증·부상·질환이 적혀 있으면 그 부위에 부담이
가는 동작을 빼고 저충격 대안으로 바꾸세요. 판단이 어려운 상태(가슴 통증, 호흡
곤란, 최근 수술 등)면 강도를 올리지 말고 rationale 에 전문가 확인이 필요하다고
적으세요.
gender·height_cm·weight_kg·주간 운동 목표는 **운동 강도·시간·구성**을 정할 때만
쓰고, 그 자체를 제한으로 해석하지 마세요. 값이 비어 있으면 추정하지 말고 그
값을 쓰지 않은 채로 구성하세요.
recent_messages 에 통증·불편 언급이 있으면 해당 부위에 부담이 가는 운동을 피하고,
왜 그렇게 구성했는지 rationale 에 그 발화를 근거로 적으세요.
insight_memos 는 트레이너가 채팅 감지에서 직접 남긴 메모입니다. 같은 부위가 여러
날 반복되면 일회성 컨디션이 아니라 이어지는 신호로 보고, 그 부위의 부하를 낮춘
구성을 우선하세요. 반영했다면 rationale 에 날짜와 함께 적으세요.
rationale 에는 어떤 회원 데이터가 이 구성에 영향을 줬는지(주의사항·메모·발화·
목표·이행률 중 실제로 쓴 것)를 적으세요. 다만 회원에게 보이는 reason 에는
민감한 건강 정보를 그대로 옮기지 말고 운동 구성만 짧게 적으세요.

member_analysis.recommendation_status 에 따라 두 계획의 성격을 다르게 하세요.
- "template": 개인 데이터를 분석한 것처럼 표현하지 마세요. member_goal/goal
  기준의 일반적인 추천이며, rationale 에 그 사실을 명시하세요.
- "learning": frequent_exercises 가 있으면 최대한 유지하고 부족한 부분만 보완하세요.
  아직 반복 패턴이라 부르기엔 이르다는 점을 rationale 에 남기세요.
- "personalized": frequent_exercises 를 근거로 plan_a 는 "기존 패턴 유지형"
  (이름 그대로 두거나 유사한 라벨)으로 그 운동들을 최대한 유지하고, plan_b 는
  "점진적 강화형"으로 같은 핵심 운동을 유지하되 운동량/강도만 소폭 높이세요.
  rationale 에 history_session_count·analysis_period_days·반복된 운동 이름을
  구체적으로 인용하세요.
"""
    + prompt_safety.UNTRUSTED_QUOTE_GUARD
    + "\n"
    + prompt_safety.TRAINER_NOTE_GUARD
    + """

반드시 설명이나 마크다운 없이 아래 JSON 객체만 반환하세요.
{
  "plan_a": {
    "key": "A",
    "label": "짧고 직관적인 한국어 이름",
    "total_minutes": 30,
    "intensity": "낮음|보통|높음",
    "exercises": [
      {"name": "운동명", "minutes": 15, "type": "걷기|유산소|근력|요가|스트레칭|기타"}
    ],
    "reason": "회원에게 보여줄 짧은 추천 이유",
    "rationale": "트레이너가 확인할 데이터 근거"
  },
  "plan_b": {
    "key": "B",
    "label": "짧고 직관적인 한국어 이름",
    "total_minutes": 30,
    "intensity": "낮음|보통|높음",
    "exercises": [
      {"name": "운동명", "minutes": 15, "type": "걷기|유산소|근력|요가|스트레칭|기타"}
    ],
    "reason": "회원에게 보여줄 짧은 추천 이유",
    "rationale": "트레이너가 확인할 데이터 근거"
  }
}
각 plan의 total_minutes는 exercises의 minutes 합과 정확히 같아야 합니다.
"""
)


def _exercise_name(item: object) -> str:
    """완료 기록 한 줄에서 세트/횟수를 뗀 운동 이름만 남긴다.

    `RoutineHistory.exercises_json` 은 `"레그프레스 3세트"` 처럼 이름 뒤에 자유
    텍스트가 붙는다. 숫자가 시작되는 지점부터는 이름이 아니라고 본다.
    """
    if isinstance(item, dict):
        text = str(item.get("name", ""))
    elif isinstance(item, str):
        text = item
    else:
        return ""
    return _TRAILING_COUNT_RE.sub("", text).strip()


def _guess_intensity(exercise_type: str) -> RoutineIntensityPreference:
    """마지막으로 배정한 루틴의 운동 타입으로 강도 선호를 대강 짐작한다."""
    code = exercise_types.normalize(exercise_type)
    if code == exercise_types.STRENGTH:
        return "high"
    if code == exercise_types.STRETCHING:
        return "low"
    return "moderate"


def _analyze_routine_history(
    db: Session,
    trainer_id: str,
    member_id: str,
    today_date: date,
    latest_approved: TrainerRoutine | None,
) -> _HistoryAnalysis:
    """최근 완료 기록에서 개인화 가능 여부·반복 운동·기본 조건을 뽑는다(#776).

    임계값은 명시적 규칙이다 — "패턴이 있다"를 AI 가 판단하지 않는다(이슈의
    요구사항). 세션 수·주 분산·반복 횟수 셋을 모두 만족해야 personalized 다 —
    하나만 봐서는 우연히 몰아 한 3일과 몇 주에 걸친 습관을 구분할 수 없다.

    `latest_approved` 는 반드시 승인된(회원에게 실제로 나간) 루틴이어야 한다 —
    검토 대기중이거나 반려된 후보의 시간·강도가 다음 생성의 기본값으로 새면
    안 된다.
    """
    since = (today_date - timedelta(days=HISTORY_LOOKBACK_DAYS - 1)).isoformat()
    rows = db.execute(
        select(RoutineHistory.date, RoutineHistory.exercises_json).where(
            RoutineHistory.member_id == member_id,
            RoutineHistory.date >= since,
            or_(
                RoutineHistory.trainer_id.is_(None),
                RoutineHistory.trainer_id == trainer_id,
            ),
        )
    ).all()

    session_count = len(rows)
    distinct_weeks = {
        date.fromisoformat(history_date).isocalendar()[:2]
        for history_date, _exercises in rows
    }

    name_counts: Counter[str] = Counter()
    for _history_date, exercises_json in rows:
        try:
            items = json.loads(exercises_json or "[]")
        except (TypeError, ValueError):
            continue
        if not isinstance(items, list):
            continue
        for item in items:
            name = _exercise_name(item)
            if name:
                name_counts[name] += 1

    frequent = [name for name, count in name_counts.most_common() if count >= 2][:3]

    if (
        session_count >= MIN_SESSIONS_FOR_PERSONALIZED
        and len(distinct_weeks) >= MIN_DISTINCT_WEEKS_FOR_PERSONALIZED
        and max(name_counts.values(), default=0) >= MIN_REPEAT_FOR_PERSONALIZED
    ):
        status: RecommendationStatus = "personalized"
    elif session_count >= MIN_SESSIONS_FOR_LEARNING:
        status = "learning"
    else:
        status = "template"

    suggested_minutes = None
    suggested_intensity = None
    if (
        status != "template"
        and latest_approved is not None
        and latest_approved.minutes > 0
    ):
        suggested_minutes = min(180, max(10, latest_approved.minutes))
        suggested_intensity = _guess_intensity(latest_approved.type)

    return _HistoryAnalysis(
        status=status,
        session_count=session_count,
        frequent_exercises=frequent,
        suggested_available_minutes=suggested_minutes,
        suggested_intensity=suggested_intensity,
    )


def build_member_analysis(
    db: Session,
    trainer_id: str,
    member_id: str,
    request: RoutineOptionsRequest,
) -> RoutineOptionAnalysisOut:
    """소유 링크와 회원의 최근 식단·운동·배정 데이터를 하나의 분석으로 집계."""
    link = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    )
    if link is None:
        raise ValueError("담당 고객을 찾을 수 없습니다.")

    # 오늘과 28일 창을 같은 스냅샷에서 뽑는다 — 따로 읽으면 KST 자정 사이에
    # 한 응답의 '오늘 나트륨'과 '최근 4주 이행률'이 다른 날을 기준으로 잡힌다.
    today_date = clock.today()
    today = today_date.isoformat()
    sodium = int(
        db.scalar(
            select(func.coalesce(func.sum(DietEntry.sodium_mg), 0)).where(
                DietEntry.user_id == member_id,
                DietEntry.date == today,
            )
        )
        or 0
    )

    since = (today_date - timedelta(days=27)).isoformat()
    completion = db.scalar(
        select(func.avg(RoutineHistory.completion_rate)).where(
            RoutineHistory.member_id == member_id,
            RoutineHistory.date >= since,
            or_(
                RoutineHistory.trainer_id.is_(None),
                RoutineHistory.trainer_id == trainer_id,
            ),
        )
    )

    latest = db.scalar(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
        .order_by(TrainerRoutine.created_at.desc(), TrainerRoutine.id.desc())
        .limit(1)
    )
    # `latest`(위)는 표시용 latest_routine 라벨이라 상태를 안 가린다 — 이력엔
    # "이런 걸 준 적 있다"는 사실 자체가 의미 있다. 반면 조건 자동 설정은
    # 회원에게 실제로 나간 값이어야 한다. approved 가 아니면(검토 대기중인
    # AI 후보, 반려된 제안) 아직 아무 근거도 아니다 — 그 시간·강도가 조건에
    # 새면 트레이너가 승인도 안 한 후보가 다음 생성을 조종하게 된다.
    latest_approved = db.scalar(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == "approved",
        )
        .order_by(TrainerRoutine.created_at.desc(), TrainerRoutine.id.desc())
        .limit(1)
    )
    profile = db.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    sodium_target = (
        profile.daily_sodium_mg
        if profile is not None and profile.daily_sodium_mg is not None
        else 2000
    )

    history = _analyze_routine_history(
        db, trainer_id, member_id, today_date, latest_approved
    )

    return RoutineOptionAnalysisOut(
        # 코칭 목표는 회원이 고른 건강 목표다(#1818).
        goal=health_focus.focus_label(profile.conditions if profile is not None else None),
        member_goal=profile.goals if profile is not None else "",
        conditions=profile.conditions if profile is not None else "",
        gender=profile.gender if profile is not None else "",
        height_cm=profile.height_cm if profile is not None else None,
        weight_kg=profile.weight_kg if profile is not None else None,
        weekly_workout_goal=(
            profile.weekly_workout_goal if profile is not None else None
        ),
        weekly_exercise_minutes_goal=(
            profile.weekly_exercise_minutes_goal if profile is not None else None
        ),
        weekly_burn_goal=profile.weekly_burn_goal if profile is not None else None,
        sodium_today_mg=sodium,
        sodium_over_target=sodium > sodium_target,
        avg_completion_rate=round(float(completion or 0)),
        latest_routine=latest.name if latest is not None else "-",
        note=request.trainer_note.strip(),
        recent_messages=_recent_chat_lines(db, trainer_id, member_id, today_date),
        insight_memos=_recent_insight_memos(
            db, trainer_id, member_id, today_date
        ),
        recommendation_status=history.status,
        history_session_count=history.session_count,
        analysis_period_days=HISTORY_LOOKBACK_DAYS,
        frequent_exercises=history.frequent_exercises,
        suggested_available_minutes=history.suggested_available_minutes,
        suggested_intensity=history.suggested_intensity,
    )


def _recent_chat_lines(
    db: Session, trainer_id: str, member_id: str, today_date: date,
) -> list[str]:
    """최근 트레이너↔회원 대화를 발화자 라벨이 붙은 줄로 만든다(오래된→최신).

    회원 앱 AI 코치는 같은 대화를 RAG(`personal_ingest.record_chat`)로 받지만,
    이 경로는 RAG 를 쓰지 않고 실데이터를 직접 집계하므로 여기서 따로 읽는다.

    양쪽 발화를 모두 싣고 라벨로 구분한다. 트레이너의 "이번 주는 하체 빼시죠" 도
    루틴 구성의 근거인데, 라벨이 없으면 모델이 그 말을 회원의 증상 호소로 읽는다.
    """
    # created_at 은 timestamptz 다. 식단처럼 문자열 date 컬럼이 아니므로 KST
    # 자정을 실제 시각으로 환산해 비교한다 — 날짜로 캐스팅해 비교하면 인덱스도
    # 못 타고, 드라이버가 파라미터를 varchar 로 넘겨 타입 비교가 깨진다.
    since = datetime.combine(
        today_date - timedelta(days=CHAT_LOOKBACK_DAYS - 1),
        time_of_day.min,
        tzinfo=clock.SEOUL,
    )
    rows = db.execute(
        select(ChatMessage.sender, ChatMessage.body)
        .where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.created_at >= since,
        )
        # 최신 N건을 고른 뒤 시간순으로 되돌린다 — 잘려 나가야 할 건 오래된 쪽이다.
        .order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc())
        .limit(CHAT_MAX_MESSAGES)
    ).all()

    lines: list[str] = []
    for sender, body in reversed(rows):
        text = (body or "").strip()
        if not text:
            continue
        if len(text) > CHAT_MAX_CHARS:
            text = text[:CHAT_MAX_CHARS] + "…"
        lines.append(f"{prompt_safety.speaker_label(sender)}: {text}")
    return lines


def _recent_insight_memos(
    db: Session, trainer_id: str, member_id: str, today_date: date,
) -> list[str]:
    """최근 7일(KST)의 채팅 감지 메모를 `"MM.dd 요약"` 줄로 만든다(최신 먼저).

    프로그램 탭 분석 박스가 보여 주는 것과 **같은 목록**이다(#1655) — 화면에
    없는 메모가 생성에만 반영되면 트레이너는 왜 그렇게 나왔는지 알 수 없고,
    반대면 보여 준 근거가 무시된다.

    손으로 쓴 메모(`source='trainer'`)는 뺀다. 그쪽은 수업 시간 조정처럼 운동
    구성과 무관한 기록이 섞이는 자리이고, 자동으로 프로그램에 반영하겠다고
    약속한 적도 없다.

    `created_at` 은 timestamptz 라 KST 자정을 실제 시각으로 환산해 비교한다 —
    [_recent_chat_lines] 와 같은 이유다.
    """
    since = datetime.combine(
        today_date - timedelta(days=INSIGHT_MEMO_LOOKBACK_DAYS - 1),
        time_of_day.min,
        tzinfo=clock.SEOUL,
    )
    rows = db.execute(
        select(TrainerClientMemo.created_at, TrainerClientMemo.body)
        .where(
            TrainerClientMemo.trainer_id == trainer_id,
            TrainerClientMemo.member_id == member_id,
            TrainerClientMemo.source == "chat_insight",
            TrainerClientMemo.created_at >= since,
        )
        # 목록 계약(`build_memos`)과 같은 정렬이라 화면과 순서가 어긋나지 않는다.
        .order_by(TrainerClientMemo.created_at.desc(), TrainerClientMemo.id.desc())
        .limit(INSIGHT_MEMO_MAX)
    ).all()

    lines: list[str] = []
    for created_at, body in rows:
        text = (body or "").strip()
        if not text:
            continue
        if len(text) > CHAT_MAX_CHARS:
            text = text[:CHAT_MAX_CHARS] + "…"
        local = created_at.astimezone(clock.SEOUL)
        lines.append(f"{local:%m.%d} {text}")
    return lines


def build_rule_options(
    analysis: RoutineOptionAnalysisOut,
    request: RoutineOptionsRequest,
) -> RoutineOptionsOut:
    """LLM 실패 시 공용 결정형 생성기로 동일 계약을 반환한다."""
    plan_a, plan_b = routine_ai.rule_based_plans(
        goal=analysis.goal,
        sodium_today_mg=analysis.sodium_today_mg,
        avg_completion_rate=analysis.avg_completion_rate,
        available_minutes=request.available_minutes,
        intensity_preference=request.intensity_preference,
        trainer_note=analysis.note,
        frequent_exercises=analysis.frequent_exercises,
        # LLM 이 죽은 주에도 안전 주의사항은 지켜야 한다(#1440). 건강 프로필의
        # 주의사항과 최근 대화의 통증 언급을 함께 넘긴다 — 트레이너 메모에 다시
        # 적혀 있지 않아도 폴백이 그 부위를 피한다.
        conditions=analysis.conditions,
        recent_messages=analysis.recent_messages,
        # 트레이너가 감지에서 남긴 메모도 같은 주의사항으로 읽는다(#1655) —
        # LLM 이 죽은 주라고 해서 "무릎 불편 감지" 를 못 본 척할 수는 없다.
        insight_memos=analysis.insight_memos,
    )
    return RoutineOptionsOut(
        analysis=analysis,
        plan_a=RoutineOptionPlanOut.model_validate(plan_a),
        plan_b=RoutineOptionPlanOut.model_validate(plan_b),
        generated_by="rule",
    )


class RoutineContractError(ValueError):
    """LLM 응답이 계약을 어겼다 — 공급자는 살아 있고, 볼 곳은 프롬프트·스키마다.

    `ValueError` 를 통째로 계약 위반으로 잡으면 안 된다. `get_coach_llm()` 은
    COACH_LLM 값이 오타면 `ValueError("알 수 없는 코치 LLM: ...")` 를 던지는데
    (`coach/llm.py`), 그건 설정 문제라 프롬프트를 아무리 손봐도 안 고쳐진다.
    계약 위반만 이 타입으로 좁혀 `reason=contract` 와 `reason=infra` 를 가른다.
    """


def _decode_json_object(text: str) -> dict:
    """LLM이 실수로 붙인 코드펜스·설명 앞뒤를 제거하고 첫 JSON 객체만 읽는다."""
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        raise RoutineContractError("LLM 응답에 JSON 객체가 없습니다.")
    try:
        parsed = json.loads(text[start : end + 1])
    except json.JSONDecodeError as exc:
        raise RoutineContractError(f"LLM 응답 JSON 파싱 실패: {exc}") from exc
    if not isinstance(parsed, dict):
        raise RoutineContractError("LLM 응답은 JSON 객체여야 합니다.")
    return parsed


def _call_llm(prompt: str):
    """LLM 호출 + 타임아웃. 실패는 호출부가 잡아 규칙 폴백으로 내린다.

    빈 워커가 없으면 큐에서 기다리지 않고 즉시 실패시킨다(`_llm_slots` 주석 참고).
    기다려 봐야 타임아웃이고, 그동안 요청 스레드만 붙잡아 두기 때문이다.

    응답 파싱은 일부러 이 밖에 둔다 — 워커 안에서 파싱하면 계약 위반이 `Future`
    를 통해 올라와, 호출부의 `except (ValidationError, RoutineContractError)` 와
    타임아웃을 구분하는 자리가 흐려진다.
    """
    # 자리를 딴 세마포어 **인스턴스**를 지역에 붙잡아 둔다. 워커가 전역을 다시 읽으면,
    # 그 사이 전역이 교체됐을 때(테스트의 monkeypatch 가 그렇게 한다) 잡지도 않은
    # 세마포어를 풀어 준다 — 원래 자리는 영영 안 돌아오고, 교체된 쪽은 초기값을 넘겨
    # `BoundedSemaphore` 가 ValueError 를 던진다.
    slots = _llm_slots
    if not slots.acquire(blocking=False):
        raise LLMBusyError("LLM 동시 호출 한도 초과 — 규칙 폴백")

    def _call():
        try:
            # json_mode 와 사고 예산은 **반드시 함께** 넘긴다. 기본값(사고 켜짐)으로는
            # 이 짧은 JSON 하나에도 10초 이상 걸려 클라이언트가 먼저 끊고 규칙형만
            # 보게 된다. json_mode 만 켜면 오히려 더 느려진다(실측은 coach/llm.py).
            return get_coach_llm().generate(
                _SYSTEM_PROMPT, prompt,
                json_mode=True,
                thinking_budget=LLM_THINKING_BUDGET,
            )
        finally:
            # 타임아웃으로 호출부가 떠난 뒤라도 작업이 끝나면 자리를 반드시 돌려준다.
            slots.release()

    try:
        future = _executor.submit(_call)
    except RuntimeError:
        # 스케줄링 자체가 실패하면 워커가 돌지 않아 위 `finally` 도 없다. 여기서
        # 돌려주지 않으면 실패 한 번마다 동시 호출 한도가 영구히 1씩 줄어, 끝내
        # 모든 요청이 포화로 떨어진다(인터프리터 종료 중 submit 이 이 경로다).
        slots.release()
        raise
    return future.result(timeout=LLM_TIMEOUT_SEC)


def _generate_with_llm(
    analysis: RoutineOptionAnalysisOut,
    request: RoutineOptionsRequest,
) -> RoutineOptionsOut:
    prompt = json.dumps(
        {
            "member_analysis": analysis.model_dump(),
            "available_minutes": request.available_minutes,
            "intensity_preference": request.intensity_preference,
            "trainer_note": request.trainer_note.strip(),
        },
        ensure_ascii=False,
    )
    result = _call_llm(prompt)
    payload = _decode_json_object(result.text)
    payload["analysis"] = analysis.model_dump()
    payload["generated_by"] = "ai"
    options = RoutineOptionsOut.model_validate(payload)
    if (
        options.plan_a.total_minutes > request.available_minutes
        or options.plan_b.total_minutes > request.available_minutes
    ):
        raise RoutineContractError("LLM 루틴 시간이 요청 가능한 시간을 초과했습니다.")
    return options


def _resolve_conditions(
    analysis: RoutineOptionAnalysisOut, request: RoutineOptionsRequest,
) -> RoutineOptionsRequest:
    """트레이너가 조건을 비워 두면 분석값(또는 기본값)으로 채운다(#776).

    트레이너가 값을 보냈으면 그 값이 항상 이긴다 — 자동 설정은 빈 입력을
    채울 뿐, 트레이너의 명시적 선택을 덮어쓰지 않는다.
    """
    minutes = request.available_minutes
    if minutes is None:
        minutes = analysis.suggested_available_minutes or DEFAULT_AVAILABLE_MINUTES
    intensity = request.intensity_preference
    if intensity is None:
        intensity = analysis.suggested_intensity or DEFAULT_INTENSITY
    if minutes == request.available_minutes and intensity == request.intensity_preference:
        return request
    return request.model_copy(
        update={"available_minutes": minutes, "intensity_preference": intensity}
    )


def generate_routine_options(
    db: Session,
    trainer_id: str,
    member_id: str,
    request: RoutineOptionsRequest,
) -> RoutineOptionsOut:
    analysis = build_member_analysis(db, trainer_id, member_id, request)
    request = _resolve_conditions(analysis, request)
    fallback = build_rule_options(analysis, request)
    started = time.monotonic()
    had_chat = bool(analysis.recent_messages)
    try:
        options = _generate_with_llm(analysis, request)
    except LLMBusyError:
        # 포화 — 장애가 아니다. 부르지 않았으니 stack trace 도 남길 게 없다.
        # 이 값이 자주 오르면 늘릴 것은 타임아웃이 아니라 동시성 한도다.
        _record(started, reason="busy", had_chat_context=had_chat)
        logger.info(
            "맞춤 루틴 LLM 포화 — 규칙 기반 폴백 사용 (trainer_id=%s, member_id=%s)",
            trainer_id, member_id,
        )
        return fallback
    except FutureTimeout:
        # 공급자가 살아는 있는데 제 시간에 못 준다. 계약 위반도 인프라 장애도
        # 아니라서 따로 센다 — 셋을 섞으면 "프롬프트를 볼지, 한도를 올릴지,
        # 공급자를 볼지"를 지표에서 가릴 수 없다.
        _record(started, reason="timeout", had_chat_context=had_chat)
        logger.warning(
            "맞춤 루틴 LLM 타임아웃(%.1fs) — 규칙 기반 폴백 사용 "
            "(trainer_id=%s, member_id=%s)",
            LLM_TIMEOUT_SEC, trainer_id, member_id,
        )
        return fallback
    except (ValidationError, RoutineContractError) as exc:
        # 계약 위반 — 공급자는 살아 있는데 응답이 규격에 안 맞는다. 프롬프트나
        # 스키마를 손볼 신호라 인프라 장애와 섞으면 안 된다.
        # 넓은 ValueError 가 아니라 이 두 타입만 잡는다 — COACH_LLM 오타 같은
        # 설정 오류도 ValueError 라, 그것까지 계약 위반으로 세면 지표가 엉킨다.
        _record(started, reason="contract", had_chat_context=had_chat)
        logger.warning(
            "맞춤 루틴 LLM 계약 위반 — 규칙 기반 폴백 사용 "
            "(trainer_id=%s, member_id=%s): %s",
            trainer_id, member_id, exc,
        )
        return fallback
    except Exception:  # noqa: BLE001 — 키 미설정·설정 오타·네트워크·5xx, 우리 쪽 버그
        # 이쪽은 stack trace 를 남긴다. 예전엔 한 덩어리로 삼켜서, 스키마 필드
        # 이름을 잘못 쓴 버그도 조용히 규칙형으로 내려가 아무도 몰랐다.
        _record(started, reason="infra", had_chat_context=had_chat)
        logger.exception(
            "맞춤 루틴 LLM 호출 실패 — 규칙 기반 폴백 사용 "
            "(trainer_id=%s, member_id=%s)",
            trainer_id, member_id,
        )
        return fallback

    _record(started, reason=None, had_chat_context=had_chat)
    return options


def _record(
    started: float, *, reason: str | None, had_chat_context: bool,
) -> None:
    """생성 결과를 계측한다(#583).

    소요 시간은 성공·실패 모두 남긴다 — 타임아웃으로 폴백하는 경우 '얼마나 오래
    기다렸는지'가 #584 의 타임아웃 값을 정하는 근거다.
    """
    metrics.observe_ms(
        "routine_options.llm_ms", (time.monotonic() - started) * 1000
    )
    if reason:
        metrics.incr("routine_options.generated", by="rule")
        metrics.incr("routine_options.fallback", reason=reason)
        return
    metrics.incr("routine_options.generated", by="ai")
    # 성공했을 때만 센다 — 규칙형은 채팅을 읽지 않으므로, 폴백까지 세면 이 지표가
    # "채팅 근거가 AI 에 닿았다"는 질문에 거짓으로 답한다(#580 이 실환경에서
    # 도는지 확인하려고 만든 카운터다).
    if had_chat_context:
        metrics.incr("routine_options.with_chat_context")
