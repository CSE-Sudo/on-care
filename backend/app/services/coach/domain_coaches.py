"""
도메인별 RAG 코치 (식단 / 운동).

흐름(도메인마다 동일):
  1) 사용자 최근 데이터로 질의문 구성
  2) retrieve_context() 로 [내 기록 + 공공 가이드라인] 컨텍스트 확보 (격리·도메인 필터 적용)
  3) LLM 에 system+user 프롬프트로 코칭 생성 (토큰 기록)
  4) 실패(키 없음/자료 없음/에러) 시 coach_service 의 규칙 기반으로 폴백

식단·운동을 각각 생성한 뒤 합치는 구조는 coach_service.build_feedback 에서.
AI 코치 채팅(coach/chat.py)은 같은 검색·LLM 계층(retrieve, get_coach_llm)을 따로 쓴다.

제목과 코칭 문장은 요청 언어(`Accept-Language`, #2297)로 만든다(#2707). 영어면
한국어 지시문 끝에 출력 언어 규칙만 덧붙인다 — 한국어 프롬프트는 그대로다.
"""
from __future__ import annotations
import logging
from collections.abc import Callable

from sqlalchemy.orm import Session

from app.core.locale import current_locale, localized
from app.db.session import release_connection
from app.schemas.misc_api import CoachSuggestion
from app.services.coach import grounding, prompt_safety
from app.services.coach.llm import get_coach_llm
from app.services.coach.rag import retrieve_context
# 규칙 기반(폴백)
from app.services.coach_service import (
    _diet_today_priority, _diet_weekly_or_default, _exercise_suggestion,
    diet_period_context,
)
from app.services.ai_log import log_ai_fallback

logger = logging.getLogger(__name__)

_DIET_SYSTEM = (
    # 대상 집단은 폐기된 스타트 단계의 것이었다(#2026).
    "당신은 온케어 회원의 식단을 돕는 전문 영양 코치입니다. "
    "제공된 '내 건강 기록'과 '참고 자료'에 근거해, 나트륨·당류 관리를 중심으로 "
    "영양소 섭취기준 관점의 조언을 2~3문장으로 친근하게 한국어로 제시하세요. "
    "근거 없는 단정은 피하고, 참고 자료가 있으면 그 권고를 반영하세요. "
    # 식단 조언도 자유 서술이라 "나트륨을 줄이면 당신 혈압이…" 로 새어 나갈 수
    # 있다. 세 코치 모두 같은 안내를 싣는다(#602).
    + grounding.UNTRACKED_METRIC_NOTICE + " "
    # 개인 문서에는 트레이너와 주고받은 대화도 검색되어 들어온다(#580).
    + prompt_safety.UNTRUSTED_QUOTE_GUARD + " "
    # 식단 기록 줄에는 회원이 적은 음식 이름이 들어 있다(#3090).
    + prompt_safety.FOOD_NAME_GUARD
)
_EXERCISE_SYSTEM = (
    # 위와 같은 이유로 대상 집단을 고쳤다(#2026).
    "당신은 온케어 회원의 운동을 돕는 코치입니다. "
    "제공된 '내 건강 기록'과 '참고 자료'에 근거해, 최근 운동량과 생활 습관에 맞는 "
    "운동 조언을 2~3문장으로 친근하게 한국어로 제시하세요. "
    # 예전에는 "혈압·혈당 관리에 도움이 되는" 이라고 지시했다. 그 수치를 재지
    # 않으므로 모델이 근거 없이 답하거나 일반론으로 흘렀다(#602).
    + grounding.UNTRACKED_METRIC_NOTICE + " "
    + prompt_safety.UNTRUSTED_QUOTE_GUARD + " "
    # 식단 코치와 같은 경계를 싣는다 — 검색 도메인이 바뀌어 식단 기록이 섞여도
    # 한쪽만 빠지지 않게(#3090).
    + prompt_safety.FOOD_NAME_GUARD
)

#: 영어 화면에서 요청했을 때 시스템 프롬프트 끝에 덧붙이는 출력 언어 규칙(#2707).
#: 검색 자료·기록 요약은 한국어 그대로 넘기고, 쓰는 언어만 바꾸게 한다.
_ENGLISH_OUTPUT_RULE = (
    " Output language: the member is using the app in English. Write the advice "
    "in natural English, ignoring the instruction above to write in Korean. Quote "
    "food or exercise names from the records as-is if you cite them, but write the "
    "surrounding sentences in English."
)


def _system_prompt(base: str) -> str:
    """요청 언어에 맞는 시스템 프롬프트. 한국어는 [base] 그대로다."""
    return base + _ENGLISH_OUTPUT_RULE if current_locale() == "en" else base


def _rag_suggestion(
    db: Session, user_id: str, *, domain: str, system_prompt: str,
    query: str, tag: str, title: str, fallback: CoachSuggestion,
    extra_context: str | Callable[[], str] = "",
) -> CoachSuggestion:
    try:
        context = retrieve_context(db, query, user_id=user_id, domain=domain)
        # extra_context(#933)는 계산된 요약(예: 이번 주 나트륨 평균)이라, 검색 문서가
        # 하나도 안 걸려도 그것만으로 코칭을 만들 수 있다 — 그래서 context 가 비어도
        # extra_context 가 있으면 폴백으로 빠지지 않는다. 콜러블로도 받는 이유는
        # 그 계산(추가 DB 조회)도 이 try 안에서 실패해야 규칙 폴백으로 빠진다는
        # 보장이 서기 때문이다 — 호출부에서 미리 계산해 인자로 넘기면 그 실패가
        # 이 함수 밖에서 터져 폴백을 건너뛴다.
        extra = extra_context() if callable(extra_context) else extra_context
        combined = "\n\n".join(part for part in (context, extra) if part)
        if not combined:
            return fallback  # 검색 자료도 기간 요약도 전혀 없으면 규칙 기반
        llm = get_coach_llm()
        ask = localized(
            "위 정보를 바탕으로 조언해 주세요.",
            "Please give advice based on the information above.",
        )
        user_prompt = f"{combined}\n\n{ask}"
        # LLM 을 기다리는 동안 DB 연결을 쥐지 않는다(#2836) — 여기까지는 읽기뿐이다.
        release_connection(db)
        result = llm.generate(_system_prompt(system_prompt), user_prompt)
        if not result.text.strip():
            return fallback
        return CoachSuggestion(tag=tag, title=title, body=result.text.strip())
    except Exception as exc:  # noqa: BLE001
        # 키 미설정/네트워크/모델 오류 → 안전하게 규칙 기반 폴백 (단, 로그는 남긴다).
        # 예외 메시지·스택은 남기지 않는다 — 프롬프트(회원 기록)가 실린다(#3090).
        log_ai_fallback(
            logger, f"{domain}_coach", "error", exc=exc, level=logging.ERROR,
            user_id=user_id,
        )
        return fallback

def diet_coach(db: Session, user_id: str) -> CoachSuggestion:
    # 오늘 기록이 없거나 오늘 자체가 초과면 그 사실이 코칭의 핵심이라, RAG 가
    # 다른 문구로 덮지 못하도록 아예 건너뛰고 바로 돌려준다(#933 CodeRabbit
    # 리뷰 반영). 그 외의 경우에만 검색·기간 요약을 근거로 LLM 코칭을 시도한다.
    #
    # 오늘 우선 여부는 여기서 **한 번만** 확인한다. 이 판단과 아래 폴백 계산이
    # 각자 따로 오늘 기록을 조회하면, 그 사이 새 기록이 들어와 두 조회가 다른
    # 결과를 낼 수 있다(TOCTOU) — 이 함수는 이미 None(우선순위 아님)을 확인했
    # 으므로, 그 판단을 다시 하는 `_diet_suggestion` 대신 `_diet_weekly_or_default`
    # 를 바로 쓴다(코드 리뷰 지적).
    priority = _diet_today_priority(db, user_id)
    if priority is not None:
        return priority
    fallback = _diet_weekly_or_default(db, user_id)
    return _rag_suggestion(
        db, user_id, domain="diet", system_prompt=_DIET_SYSTEM,
        query="최근 식단의 나트륨·당류 관리와 개선점",
        tag="diet", title=localized("오늘의 식단 코칭", "Today's diet coaching"),
        fallback=fallback,
        # 이번 주 집계는 위 fallback 계산과 별개로 여기서 한 번 더 조회된다.
        # try 밖(폴백)과 try 안(extra_context)이 같은 값을 나눠 쓰면, 그 조회의
        # 실패가 try 밖으로 새어 나가 이 함수 전체를 죽인다 — 같은 구간을 두 번
        # 쿼리하는 비용보다 장애 시 규칙 폴백 보장이 우선이다(#933 코드 리뷰).
        extra_context=lambda: diet_period_context(db, user_id),
    )


def exercise_coach(db: Session, user_id: str) -> CoachSuggestion:
    fallback = _exercise_suggestion(db, user_id)
    return _rag_suggestion(
        db, user_id, domain="exercise", system_prompt=_EXERCISE_SYSTEM,
        # 질의문도 실제 적재된 것으로 좁힌다 — 혈압·혈당으로 검색해 봐야 개인
        # 문서에는 없고, 엉뚱한 공공 문서만 상위로 끌어올린다(#602).
        query="이번 주 운동량과 최근 운동 기록을 바탕으로 한 운동 제안",
        tag="exercise",
        title=localized("오늘의 운동 코칭", "Today's workout coaching"),
        fallback=fallback,
    )
