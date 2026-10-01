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
from app.core.locale import Locale, current_locale
from app.models.models import (
    ChatMessage,
    DietEntry,
    HealthProfile,
    MemberWeeklyFeedback,
    RoutineHistory,
    TrainerClient,
    TrainerClientMemo,
    TrainerRoutine,
    TrainerSchedule,
)
from app.schemas.trainer_api import (
    ROUTINE_CHAT_MAX_MESSAGES,
    ROUTINE_CONSULT_MEMO_MAX,
    ROUTINE_DEFAULT_SOURCES,
    ROUTINE_INSIGHT_MEMO_DAYS,
    ROUTINE_INSIGHT_MEMO_MAX,
    ROUTINE_PT_FEEDBACK_MAX,
    ROUTINE_TRAINER_MEMO_MAX,
    ROUTINE_WEEKLY_FEEDBACK_MAX,
    RecommendationStatus,
    RoutineIntensityPreference,
    RoutineOptionAnalysisOut,
    RoutineOptionPlanOut,
    RoutineOptionsOut,
    RoutineContextSource,
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

#: 운동 기록 줄 끝의 수행 표시(#2714). 안 한 운동은 반복으로 세지 않는다.
_SKIPPED_MARK = "✗"
#: 한 운동 표시·괄호 메모가 시작되는 곳 — 그 앞까지가 이름이다.
_DONE_OR_NOTE_RE = re.compile(r"[✓(]")


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

#: 트레이너가 고를 수 있는 나머지 자료의 창(일, KST 달력일, 오늘 포함)(#2587).
#: 건수 상한은 스키마가 단일 출처다.
#:
#: 상담 메모만 30일이다. 상담은 PT 보다 드물어 등록 상담이 2~4주 전인 경우가
#: 흔하고, 14일로 좁히면 대부분 비어 켜도 들어가는 것이 없다.
PT_FEEDBACK_LOOKBACK_DAYS = 14
CONSULT_MEMO_LOOKBACK_DAYS = 30
TRAINER_MEMO_LOOKBACK_DAYS = 14

#: 상담 일정의 종류값. 같은 `trainer_schedule.note` 라도 상담이면 메모, 나머지는
#: PT 피드백이다(#2574 용어 규칙).
CONSULT_SCHEDULE_TYPE = "상담"

#: 주간 피드백 선택지 → 프롬프트에 쓰는 말. 저장값(영문 코드)을 그대로 넘기면
#: 모델이 `too_hard` 를 과부하 신호로 읽을지 장담할 수 없다.
_WEEKLY_CONDITION_LABELS = {
    "great": "아주 좋음", "good": "좋음", "ok": "보통", "tired": "피곤", "bad": "나쁨",
}
_WEEKLY_INTENSITY_LABELS = {
    "too_easy": "너무 쉬움", "right": "적당함", "hard": "힘듦", "too_hard": "너무 힘듦",
}

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
4. member_analysis.trainer_memos·pt_feedbacks·consult_memos (트레이너가 예전에 남긴 메모와 PT 피드백)
5. member_analysis.weekly_feedback (회원이 남긴 주간 피드백의 컨디션·강도·통증)
6. member_analysis.recent_messages 의 통증·컨디션 언급
member_analysis.sources 는 트레이너가 이번 생성에 넣기로 고른 자료입니다. 목록이
비어 있으면 고르지 않았거나 기록이 없는 것이니 내용을 추정하지 마세요.
weekly_feedback 의 강도가 "너무 힘듦" 이거나 컨디션이 "피곤"·"나쁨" 이면 운동량을
올리지 마세요.
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
- "template": 개인 데이터를 분석한 것처럼 표현하지 마세요. goal
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
    + "\n"
    + prompt_safety.TRAINER_RECORD_GUARD
    + "\n"
    + prompt_safety.MEMBER_FEEDBACK_GUARD
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

#: 영어 화면에서 요청했을 때 시스템 프롬프트 끝에 덧붙이는 출력 언어 규칙(#2301).
#:
#: 한국어 프롬프트는 한 글자도 바꾸지 않는다 — 지금까지 검증한 한국어 출력이 그대로
#: 남아야 한다. 영어는 같은 지시 위에 "쓰는 언어만 바꾸라" 를 얹는다. `intensity`·
#: `type` 은 스키마 Literal(한국어 계약값)이라 번역하면 422 로 떨어져 규칙형 폴백이
#: 되므로, 번역하지 말라고 못 박는다. `reason` 은 승인하면 회원에게 가는 트레이너
#: 명의의 안내문이라 트레이너가 읽고 보내는 언어(= 요청 언어)로 쓴다.
_ENGLISH_OUTPUT_RULE = """
Output language: the trainer is using the app in English.
Write every free-text value in natural English: plan label, exercises[].name,
reason and rationale. Ignore the "한국어 이름" hint in the JSON example above.
Do NOT translate "intensity" or exercises[].type — they are contract values and
must be exactly one of the Korean values listed in the JSON example.
Quote member data (messages, memos, exercise names from records) as-is when you
cite it, but write the surrounding sentence in English.
"""


def system_prompt(locale: Locale = "ko") -> str:
    """요청 언어에 맞는 시스템 프롬프트. 한국어는 [_SYSTEM_PROMPT] 그대로다(#2301)."""
    if locale == "en":
        return _SYSTEM_PROMPT + _ENGLISH_OUTPUT_RULE
    return _SYSTEM_PROMPT


def _exercise_name(item: object) -> str:
    """완료 기록 한 줄에서 세트/횟수를 뗀 운동 이름만 남긴다.

    `RoutineHistory.exercises_json` 은 `"레그프레스 3세트"` 처럼 이름 뒤에 자유
    텍스트가 붙는다. 숫자가 시작되는 지점부터는 이름이 아니라고 본다.

    끝의 수행 표시와 괄호 메모도 뗀다(#2714) — `"걷기 ✓ (10분만)"` 은 `걷기` 다.
    **안 한 운동(`✗`)은 빈 이름**이라 반복으로 세지 않는다. 떼지 않던 동안에는
    `"데드리프트 ✗"` 가 그 이름대로 세어져, 하지 않은 운동이 "최근 자주 수행한
    운동" 으로 A안에 들어갔다.
    """
    if isinstance(item, dict):
        text = str(item.get("name", ""))
    elif isinstance(item, str):
        text = item
    else:
        return ""
    if _SKIPPED_MARK in text:
        return ""
    text = _DONE_OR_NOTE_RE.split(text, maxsplit=1)[0]
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
            TrainerClient.active.is_(True),
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

    # 트레이너가 고른 자료만 읽는다(#2587). 끈 자료는 조회 자체를 하지 않는다 —
    # 읽어 두고 프롬프트에서만 빼면, 폴백이나 응답 분석으로 새어 나갈 길이 남는다.
    sources = _resolve_sources(request)

    return RoutineOptionAnalysisOut(
        # 코칭 목표는 회원이 고른 건강 목표다(#1818).
        goal=health_focus.focus_label(profile.conditions if profile is not None else None),
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
        insight_memos=(
            _recent_insight_memos(db, trainer_id, member_id, today_date)
            if "chat_insight" in sources
            else []
        ),
        sources=sources,
        pt_feedbacks=(
            _recent_schedule_notes(
                db, trainer_id, member_id, today_date, consult=False
            )
            if "pt_feedback" in sources
            else []
        ),
        consult_memos=(
            _recent_schedule_notes(
                db, trainer_id, member_id, today_date, consult=True
            )
            if "consult_memo" in sources
            else []
        ),
        trainer_memos=(
            _recent_trainer_memos(db, trainer_id, member_id, today_date)
            if "trainer_memo" in sources
            else []
        ),
        weekly_feedback=(
            _recent_weekly_feedback(db, link, today_date)
            if "weekly_feedback" in sources
            else []
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

    손으로 쓴 메모(`source='trainer'`)는 [_recent_trainer_memos] 가 따로 읽는다 —
    트레이너가 둘을 따로 켜고 끈다(#2587).
    """
    return _recent_memos(
        db, trainer_id, member_id, today_date,
        sources=("chat_insight",),
        lookback_days=INSIGHT_MEMO_LOOKBACK_DAYS,
        limit=INSIGHT_MEMO_MAX,
    )


def _recent_trainer_memos(
    db: Session, trainer_id: str, member_id: str, today_date: date,
) -> list[str]:
    """최근 14일(KST) 트레이너가 손으로 쓴 메모(#2519, #2587).

    회원 상세에서 쓴 메모와 운동 탭 기록 카드에서 남긴 메모(`exercise_memo`,
    #2332)가 함께 든다 — 둘 다 트레이너가 직접 적은 기록이고, 화면의 선택지도
    `직접 쓴 메모` 하나다.

    수업 시간 조정처럼 운동과 무관한 기록도 섞이는 자리라, 프롬프트는 이 목록을
    지시가 아니라 참고 기록으로 받는다(`prompt_safety.TRAINER_RECORD_GUARD`).
    """
    return _recent_memos(
        db, trainer_id, member_id, today_date,
        sources=("trainer", "exercise_memo"),
        lookback_days=TRAINER_MEMO_LOOKBACK_DAYS,
        limit=ROUTINE_TRAINER_MEMO_MAX,
    )


#: 메모 분류(#2622) → 프롬프트에 붙이는 이름. 메모 창 칩과 같은 말이다.
_MEMO_CATEGORY_LABELS = {
    "exercise": "운동",
    "diet": "식단",
    "pain": "통증·부상",
    "life": "생활·일정",
}


def _recent_memos(
    db: Session,
    trainer_id: str,
    member_id: str,
    today_date: date,
    *,
    sources: tuple[str, ...],
    lookback_days: int,
    limit: int,
) -> list[str]:
    """본인이 남긴 회원 메모 중 [sources] 의 최근 것을 `"MM.dd 본문"` 줄로(최신 먼저).

    분류가 있는 메모는 `"MM.dd [통증·부상] 본문"` 처럼 분류를 앞에 붙인다(#2622) —
    AI 가 운동과 무관한 일정 메모를 운동 지시로 읽지 않게 돕는다.

    `created_at` 은 timestamptz 라 KST 자정을 실제 시각으로 환산해 비교한다 —
    [_recent_chat_lines] 와 같은 이유다.
    """
    since = datetime.combine(
        today_date - timedelta(days=lookback_days - 1),
        time_of_day.min,
        tzinfo=clock.SEOUL,
    )
    rows = db.execute(
        select(
            TrainerClientMemo.created_at,
            TrainerClientMemo.body,
            TrainerClientMemo.category,
        )
        .where(
            TrainerClientMemo.trainer_id == trainer_id,
            TrainerClientMemo.member_id == member_id,
            TrainerClientMemo.source.in_(sources),
            TrainerClientMemo.created_at >= since,
        )
        # 목록 계약(`build_memos`)과 같은 정렬이라 화면과 순서가 어긋나지 않는다.
        .order_by(TrainerClientMemo.created_at.desc(), TrainerClientMemo.id.desc())
        .limit(limit)
    ).all()

    lines: list[str] = []
    for created_at, body, category in rows:
        text = _clip(body)
        if not text:
            continue
        local = created_at.astimezone(clock.SEOUL)
        label = _MEMO_CATEGORY_LABELS.get(category or "")
        prefix = f"[{label}] " if label else ""
        lines.append(f"{local:%m.%d} {prefix}{text}")
    return lines


def _recent_schedule_notes(
    db: Session,
    trainer_id: str,
    member_id: str,
    today_date: date,
    *,
    consult: bool,
) -> list[str]:
    """일정의 글을 `"MM.dd 본문"` 줄로(최신 먼저)(#2587).

    같은 `trainer_schedule.note` 라도 상담 일정이면 상담 메모, 나머지는 PT
    피드백이다. 둘을 섞으면 끈 상담 메모가 PT 피드백으로 들어간다.

    * PT 피드백 — 최근 14일, **완료한** 일정만. 예정 일정의 글은 아직 준비 중인
      말이라 지난 수업의 피드백이 아니다.
    * 상담 메모 — 최근 30일, 상태를 가리지 않는다. 상담 전에 적어 둔 준비
      메모도 트레이너가 넣기로 고른 자료다.

    둘 다 오늘 이후 날짜는 뺀다. 날짜 컬럼이 `YYYY-MM-DD` 문자열이라 사전순
    비교가 곧 날짜 비교다.
    """
    lookback = CONSULT_MEMO_LOOKBACK_DAYS if consult else PT_FEEDBACK_LOOKBACK_DAYS
    since = today_date - timedelta(days=lookback - 1)
    query = select(TrainerSchedule.date, TrainerSchedule.note).where(
        TrainerSchedule.trainer_id == trainer_id,
        TrainerSchedule.member_id == member_id,
        TrainerSchedule.date >= since.isoformat(),
        TrainerSchedule.date <= today_date.isoformat(),
        TrainerSchedule.note != "",
    )
    if consult:
        query = query.where(TrainerSchedule.type == CONSULT_SCHEDULE_TYPE)
        limit = ROUTINE_CONSULT_MEMO_MAX
    else:
        query = query.where(
            TrainerSchedule.type != CONSULT_SCHEDULE_TYPE,
            TrainerSchedule.status == "완료",
        )
        limit = ROUTINE_PT_FEEDBACK_MAX
    rows = db.execute(
        query.order_by(
            TrainerSchedule.date.desc(),
            TrainerSchedule.time.desc(),
            TrainerSchedule.id.desc(),
        ).limit(limit)
    ).all()

    lines: list[str] = []
    for day, note in rows:
        text = _clip(note)
        if not text:
            continue
        lines.append(f"{day[5:7]}.{day[8:10]} {text}")
    return lines


def _recent_weekly_feedback(
    db: Session, link: TrainerClient, today_date: date,
) -> list[str]:
    """이번 주와 지난주의 회원 주간 피드백 한 줄씩(최신 주 먼저)(#2587).

    주간 피드백은 트레이너가 아니라 회원의 행이다. 그래서 담당이 바뀐 회원은
    이전 트레이너에게 쓴 피드백이 남아 있을 수 있다 — 이 링크의 동의 시각
    (`data_consent_at`, 담당이 시작될 때 적힌다)이 든 주부터만 읽는다. 동의
    시각이 없는 옛 링크는 가를 기준이 없어 두 주를 그대로 읽는다.
    """
    this_week = today_date - timedelta(days=today_date.weekday())
    weeks = [this_week, this_week - timedelta(days=7)]
    if link.data_consent_at is not None:
        started = link.data_consent_at.astimezone(clock.SEOUL).date()
        first_week = started - timedelta(days=started.weekday())
        weeks = [week for week in weeks if week >= first_week]
    if not weeks:
        return []
    rows = db.scalars(
        select(MemberWeeklyFeedback)
        .where(
            MemberWeeklyFeedback.user_id == link.member_id,
            MemberWeeklyFeedback.week_start.in_([w.isoformat() for w in weeks]),
        )
        .order_by(MemberWeeklyFeedback.week_start.desc())
        .limit(ROUTINE_WEEKLY_FEEDBACK_MAX)
    ).all()

    lines: list[str] = []
    for row in rows:
        parts = [
            f"{row.week_start[5:7]}.{row.week_start[8:10]} 주",
            "컨디션 " + _WEEKLY_CONDITION_LABELS.get(row.condition, row.condition),
            "강도 " + _WEEKLY_INTENSITY_LABELS.get(row.intensity, row.intensity),
        ]
        if row.pain_area:
            pain = f"통증 {_clip(row.pain_area)}"
            if row.pain_on:
                pain += f"({row.pain_on[5:7]}.{row.pain_on[8:10]})"
            parts.append(pain)
        note = _clip(row.note)
        if note:
            parts.append(f"한 줄 피드백: {note}")
        lines.append(" · ".join(parts))
    return lines


def _clip(text: str | None) -> str:
    """사람이 쓴 글 한 건을 앞뒤 공백 없이, [CHAT_MAX_CHARS] 에서 자른다.

    한 건이 프롬프트를 독차지하지 않게 하는 상한이다. 자료마다 같은 값을 쓴다.
    """
    value = (text or "").strip()
    if len(value) > CHAT_MAX_CHARS:
        return value[:CHAT_MAX_CHARS] + "…"
    return value


def _resolve_sources(request: RoutineOptionsRequest) -> list[RoutineContextSource]:
    """이번 생성에 넣을 자료. 보내지 않았으면 기본값, 보냈으면 그 값 그대로다.

    순서는 스키마의 기본값 순서가 아니라 고정된 표 순서로 맞추고 중복은
    지운다 — 같은 선택이 늘 같은 분석을 내야 응답을 비교할 수 있다.
    """
    chosen = (
        ROUTINE_DEFAULT_SOURCES if request.sources is None else request.sources
    )
    order: tuple[RoutineContextSource, ...] = (
        "pt_feedback", "consult_memo", "trainer_memo", "chat_insight", "weekly_feedback",
    )
    return [source for source in order if source in chosen]


def _fallback_signals(analysis: RoutineOptionAnalysisOut) -> list[str]:
    """규칙 폴백이 주의사항으로 읽을 트레이너 쪽 글(#1655, #2587).

    분석에는 트레이너가 고른 자료만 들어 있으므로, 끈 자료는 여기에도 없다.
    """
    return [
        *analysis.insight_memos,
        *analysis.trainer_memos,
        *analysis.pt_feedbacks,
        *analysis.consult_memos,
        *analysis.weekly_feedback,
    ]


def build_rule_options(
    analysis: RoutineOptionAnalysisOut,
    request: RoutineOptionsRequest,
    locale: Locale = "ko",
) -> RoutineOptionsOut:
    """LLM 실패 시 공용 결정형 생성기로 동일 계약을 반환한다.

    [locale] 은 이름·사유·근거 문장의 언어다 — AI 가 죽은 주에도 영어 화면에는
    영어 후보가 나와야 한다(#2301).
    """
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
        # 트레이너가 켠 나머지 자료(직접 쓴 메모·PT 피드백·주간 피드백의 통증)도
        # 같은 자리로 읽는다(#2587). 끈 자료는 분석에 없으니 여기에도 없다.
        insight_memos=_fallback_signals(analysis),
        locale=locale,
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


def _call_llm(prompt: str, system: str = _SYSTEM_PROMPT):
    """LLM 호출 + 타임아웃. 실패는 호출부가 잡아 규칙 폴백으로 내린다.

    [system] 은 부르는 쪽이 요청 언어로 골라 넘긴다(#2301). 워커 스레드에서는
    요청 컨텍스트(`current_locale`)가 보이지 않으므로 여기서 다시 읽지 않는다.

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
                system, prompt,
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
    locale: Locale = "ko",
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
    result = _call_llm(prompt, system_prompt(locale))
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
    # 출력 언어는 요청한 트레이너의 화면 언어다(#2301). 워커 스레드로 넘어가기 전에
    # 요청 컨텍스트에서 한 번 읽어 AI·폴백 양쪽에 같은 값을 쓴다.
    locale = current_locale()
    fallback = build_rule_options(analysis, request, locale)
    started = time.monotonic()
    had_chat = bool(analysis.recent_messages)
    try:
        options = _generate_with_llm(analysis, request, locale)
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
