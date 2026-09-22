"""AI 코치 챗봇 응답 생성.

RAG(retrieve)로 개인+공공 근거를 모아 LLM 으로 대화형 답변을 생성한다.
LLM 키가 없거나 실패하면 검색 기반(추출형) 답변으로 폴백해, 키 없이도 근거 있는 응답을 준다.
검색(임베딩) 자체가 실패해도 같은 폴백으로 내려간다 — 외부 장애가 코치 전체 장애가 되지 않게(#1543).
개인/공공 격리·도메인 필터는 retrieve 가 이미 보장한다.
"""

from __future__ import annotations

import logging
from collections import Counter

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import HealthProfile
from app.services.coach import grounding, insights, prompt_safety
from app.services.coach.llm import get_coach_llm
from app.services.coach.rag import retrieve
from app.services.coach_service import diet_period_context

_SYSTEM = (
    # 대상 집단을 스타트 단계의 `고혈압·당뇨 위험군` 으로 소개하고 있었다(#2026).
    # 그 타깃은 폐기됐고, 혈압·혈당은 제품에서 뺀 항목이라 앱이 재지도 않는다 —
    # 프롬프트가 그렇게 시작하면 모델이 재지 않는 지표를 전제로 답한다.
    "당신은 온케어의 AI 건강 코치 '온이'입니다. 담당 트레이너 없이 혼자 관리하는 "
    "회원의 식단·운동을 돕습니다. "
    "제공된 '내 건강 기록'과 '참고 자료(공공 가이드라인)'에 근거해 "
    f"{grounding.GROUNDED_TOPIC_PHRASE} 관리를 "
    "중심으로 친근하고 구체적으로 한국어로 답하세요. 2~4문장으로 간결하게, 근거 없는 단정이나 의학적 "
    "진단은 피하고, 증상이 심각해 보이면 전문의 상담을 권하세요. "
    # 감지 요약을 어떻게 쓸지 적어 둔다(#1973). 없으면 요약을 넣어도 모델이
    # 그냥 지나친다 — 통증을 알고도 그 부위 운동을 그대로 권하게 된다.
    "'최근 이야기한 불편'이 있으면 그 부위에 힘이 실리는 동작은 권하지 말고 대안을 "
    "제시하세요. 같은 부위가 되풀이되면 전문가 확인을 권하되, 진단하거나 원인을 "
    "단정하지는 마세요. "
    # 안 재는 지표를 근거 있는 것처럼 말하지 않게 한다(#602).
    + grounding.UNTRACKED_METRIC_NOTICE + " "
    # '내 건강 기록'에는 트레이너와 주고받은 대화도 섞여 들어온다(#580).
    + prompt_safety.UNTRUSTED_QUOTE_GUARD
)

logger = logging.getLogger(__name__)

_MAX_HISTORY = 6


def _format_context(hits: dict) -> str:
    lines: list[str] = []
    if hits["personal"]:
        lines.append("[내 건강 기록]")
        lines += [f"- {d.content}" for d in hits["personal"]]
    if hits["public"]:
        lines.append("[참고 자료]")
        for d in hits["public"]:
            tag = f"({d.title}) " if d.title else ""
            lines.append(f"- {tag}{d.content}")
    return "\n".join(lines).strip()


def _build_user_prompt(context: str, history: list, message: str) -> str:
    parts: list[str] = []
    if context:
        parts.append(context)
    if history:
        convo = [
            f"{'사용자' if getattr(t, 'role', '') == 'user' else '온이'}: {getattr(t, 'content', '')}"
            for t in history[-_MAX_HISTORY:]
        ]
        parts.append("[이전 대화]\n" + "\n".join(convo))
    parts.append(f"사용자 질문: {message}\n\n온이로서 위 정보를 바탕으로 답해 주세요.")
    return "\n\n".join(parts)


def _profile_context(db: Session, user_id: str) -> str:
    profile = db.scalar(select(HealthProfile).where(HealthProfile.user_id == user_id))
    if profile is None:
        return ""
    values = [
        f"성별: {profile.gender or '미입력'}",
        f"키: {profile.height_cm or '미입력'}cm",
        f"체중: {profile.weight_kg or '미입력'}kg",
        f"건강 상태: {profile.conditions or '미입력'}",
        f"회원 목표: {profile.goals or '미입력'}",
        f"주간 운동 횟수 목표: {profile.weekly_workout_goal if profile.weekly_workout_goal is not None else '미입력'}",
        f"주간 운동 시간 목표: {profile.weekly_exercise_minutes_goal if profile.weekly_exercise_minutes_goal is not None else '미입력'}분",
        f"주간 소모 칼로리 목표: {profile.weekly_burn_goal if profile.weekly_burn_goal is not None else '미입력'}kcal",
    ]
    return "[현재 회원 프로필과 목표]\n- " + "\n- ".join(values)


def _insight_context(db: Session, user_id: str) -> str:
    """최근 30일 대화에서 찾은 통증·부정적 반응 요약. (#1973)

    감지는 여태 **화면에만** 쓰였다. 답변 컨텍스트에는 최근 대화 몇 건만 들어가,
    그 창을 넘어가면 지난주에 무릎이 아프다고 한 회원에게 오늘 무릎에 부담이 가는
    운동을 그대로 권할 수 있었다.

    회원이 치운 줄은 `recent_insights` 가 이미 건너뛴다(#1975) — 기록 창에서
    지운 오탐이 답변에 남지 않는다.

    문장이 아니라 **부위와 횟수**만 준다. 회원이 쓴 원문은 개인 RAG 가 이미
    싣고 있고, 여기서 또 넣으면 같은 말이 프롬프트에 두 번 들어간다.
    """
    records = insights.recent_insights(db, user_id)
    if not records:
        return ""
    discomfort: Counter[str] = Counter()
    negative = 0
    for record in records:
        if record.kind == insights.KIND_DISCOMFORT:
            discomfort[record.body_part or "부위 미상"] += 1
        else:
            negative += 1
    lines = [
        f"- {part}: {count}회"
        for part, count in discomfort.most_common()
    ]
    if negative:
        lines.append(f"- 운동이 힘들다고 말한 적: {negative}회")
    window = insights.INSIGHT_WINDOW_DAYS
    return f"[최근 {window}일 이야기한 불편]\n" + "\n".join(lines)


def _fallback_reply(hits: dict) -> str:
    """LLM 없이 검색 결과만으로 만드는 근거 기반 답변."""
    pub = hits["public"]
    if pub:
        top = pub[0]
        lead = f"'{top.title}' 자료에 따르면, " if top.title else ""
        return f"{lead}{top.content} 더 궁금한 점이 있으면 편하게 물어봐 주세요!"
    if hits["personal"]:
        return "최근 기록을 보면 꾸준히 관리하고 계세요. 식단과 운동 중 어떤 부분이 궁금하신가요?"
    # 안내 문구도 실제로 답할 수 있는 것만 권한다 — 혈압·혈당을 물으라고 해 놓고
    # 기록이 없어 일반론만 돌려주면 그 자리에서 신뢰를 잃는다(#602).
    return "식단·운동 관리에 대해 물어봐 주시면 온이가 도와드릴게요!"


def _safe_retrieve(db: Session, user_id: str, message: str) -> dict:
    """검색 실패를 폴백 경계 **안**으로 끌어온다 (#1543).

    검색은 질의 임베딩부터 한다. 임베딩 provider 가 timeout·429·이상 응답으로
    실패하면 여기서 예외가 올라오는데, 그 호출이 `try` 밖에 있으면 생성 실패에는
    걸려 있는 규칙 기반 폴백에 닿지 못하고 엔드포인트가 그대로 500 을 낸다 —
    임베딩 서비스 장애 하나가 회원·트레이너 AI 코치 전체 장애가 된다.

    근거 없이 답하는 것이 답하지 못하는 것보다 낫다. 빈 hit 을 돌려주면 뒤의
    경로가 그대로 이어진다 — LLM 이 살아 있으면 프로필·기간 요약만으로 답하고,
    그것도 실패하면 규칙 기반 문구로 내려간다.
    """
    try:
        return retrieve(db, message, user_id=user_id, domain=None)
    except Exception:  # noqa: BLE001 — 임베딩/DB 오류 → 근거 없이 계속
        logger.exception(
            "RAG 검색 실패 (user_id=%s) → 근거 없이 폴백 응답 생성", user_id
        )
        # 검색이 DB 쪽에서 깨졌다면 세션이 실패한 트랜잭션에 갇힌다. 그대로 두면
        # 폴백 답변은 만들어도 호출부의 대화 저장이 다시 터져 결국 500 이 된다.
        # 이 시점까지 이 함수는 읽기만 했으므로 되돌릴 쓰기도 없다.
        try:
            db.rollback()
        except Exception:  # noqa: BLE001 — 정리 실패까지 응답을 깨뜨리진 않는다
            logger.exception("검색 실패 후 세션 롤백 실패 (user_id=%s)", user_id)
        return {"personal": [], "public": []}


def answer(
    db: Session,
    user_id: str,
    message: str,
    history: list | None = None,
) -> tuple[str, list[str], bool]:
    """(답변 텍스트, 근거 공공문서 제목들, LLM 이 답했는가) 반환.

    세 번째 값이 거짓이면 검색 기반 대체 답이다 — 회원 챗봇의 하루 한도는 LLM 이
    답한 대화만 센다(#2145).
    """
    history = history or []
    hits = _safe_retrieve(db, user_id, message)
    sources = list(dict.fromkeys(d.title for d in hits["public"] if d.title))

    try:
        llm = get_coach_llm()
        # 이번 주·이번 달 식단 요약(#933)도 함께 준다 — retrieve 는 의미상 가까운
        # 개별 기록 몇 건만 뽑아오므로 "이번 주 평균 나트륨" 같은 질문에는
        # 계산된 값이 따로 필요하다.
        context = "\n\n".join(
            part
            for part in (
                _profile_context(db, user_id),
                # 프로필 바로 뒤다 — 오늘 무엇을 권할지 정하기 전에 알아야 하는
                # 값이라, 검색 결과보다 앞에 둔다(#1973).
                _insight_context(db, user_id),
                diet_period_context(db, user_id),
                _format_context(hits),
            )
            if part
        )
        prompt = _build_user_prompt(context, history, message)
        text = llm.generate(_SYSTEM, prompt).text.strip()
        if text:
            return text, sources, True
    except Exception:  # noqa: BLE001 — 키 미설정/네트워크/모델 오류 → 검색 기반 폴백
        pass
    return _fallback_reply(hits), sources, False
