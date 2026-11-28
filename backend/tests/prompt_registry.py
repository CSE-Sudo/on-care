"""LLM 을 부르는 프롬프트 목록 — 프롬프트 공통 규칙 테스트가 함께 쓴다 (#1642).

대상 소개·의학적 조언 금지·어투처럼 "모든 프롬프트가 같은 문구를 싣는가" 를 보는
테스트가 각자 목록을 들면, 새 프롬프트를 한쪽에만 더해도 티가 나지 않는다. 목록을
여기 한 곳에 두고, 새 프롬프트를 만들면 여기에 더한다.
"""
from __future__ import annotations

from app.services import (
    diet_ai_sentence,
    diet_coach_inputs,
    diet_menu_plan,
    diet_recommendation_service,
    trainer_report_summary_service,
    trainer_routine_options_service,
)
from app.services.coach import chat as coach_chat
from app.services.coach import domain_coaches
from app.services.exercise_catalog import name_ai
from app.services.recognizer import gemini as gemini_recognizer
from app.services.recognizer import litellm_vision


def _diet_sentence() -> str:
    system, _ = diet_ai_sentence.build_prompt(
        limit=40, finding="이번 주 나트륨을 3일 넘겼다.",
        records=["월 점심: 짬뽕"], notes=[], goal="체중 감량",
    )
    return system


def _diet_menu_plan() -> str:
    system, _ = diet_menu_plan.build_prompt(
        profile=None,
        targets=diet_coach_inputs.DietTargets(2000, 80, 2000, 50),
        recent=diet_coach_inputs.DietDigest(0, 0, 0, 0, 0, {}, []),
        needs=[], notes=[], previous=(),
    )
    return system


def _diet_recommendation() -> str:
    ctx = diet_recommendation_service.NutritionContext(
        days_with_data=3, avg_sodium_mg=2850, avg_sugar_g=10.0,
        avg_calories=1500, avg_protein_g=60.0, sodium_limit_mg=2000,
        sugar_limit_g=50, calorie_limit=2000, conditions="", goals="",
        signals=("sodium_high",),
    )
    system, _ = diet_recommendation_service._build_prompt(ctx)
    return system


#: 회원에게 가는 답을 만드는 프롬프트. 담당 트레이너가 있든 없든 나간다.
MEMBER_PROMPTS = {
    "diet_coach": lambda: domain_coaches._DIET_SYSTEM,
    "exercise_coach": lambda: domain_coaches._EXERCISE_SYSTEM,
    "diet_sentence": _diet_sentence,
    "diet_menu_plan": _diet_menu_plan,
    "diet_recommendation": _diet_recommendation,
    # 두 엔진은 같은 문자열을 쓴다(`recognizer/prompt.py`). 엔진 모듈을 거쳐 읽어야
    # 한쪽이 다시 자기 프롬프트를 들었을 때 잡힌다.
    "recognizer_gemini": lambda: gemini_recognizer._PROMPT,
    "recognizer_litellm": lambda: litellm_vision._PROMPT,
}

#: LLM 을 부르는 프롬프트 전부. 새 프롬프트를 만들면 여기에 더한다.
ALL_PROMPTS = {
    **MEMBER_PROMPTS,
    "coach_chat": lambda: coach_chat._SYSTEM,
    "routine_options": lambda: trainer_routine_options_service._SYSTEM_PROMPT,
    "report_summary": lambda: trainer_report_summary_service._SYSTEM_PROMPT,
    "exercise_name": lambda: name_ai._PROMPT,
}

#: 문장을 만드는 프롬프트 — 운동 이름 분류만 빠진다. 그쪽은 종목 이름 하나를 고를 뿐
#: 문장을 쓰지 않고, 결과가 후보 목록 안의 이름일 때만 받아들인다.
SENTENCE_PROMPTS = {k: v for k, v in ALL_PROMPTS.items() if k != "exercise_name"}

#: 회원에게 그대로 보이는 **문장**을 쓰는 프롬프트. 식단 계획(메뉴 이름·키워드)과
#: 루틴 후보(`reason` 은 명사로 끝나는 짧은 라벨)는 문장을 쓰지 않아 빠진다.
MEMBER_SENTENCE_PROMPTS = {
    **{k: v for k, v in MEMBER_PROMPTS.items() if k != "diet_menu_plan"},
    "coach_chat": ALL_PROMPTS["coach_chat"],
}
