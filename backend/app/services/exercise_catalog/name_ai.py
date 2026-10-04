"""자유 입력 운동 이름 → 참조표 종목 하나. AI 는 **이름 해석만** 한다. (#1312)

## 왜 칼로리를 묻지 않나

모델에게 `러닝머신 30분 몇 kcal` 을 물으면 같은 질문에 매번 다른 답이 온다. 그
값이 기록으로 남으면 주간 합계·트레이너 리포트·목표 달성률이 함께 흔들리고,
표를 한 곳으로 모은 취지(#1131)가 무너진다.

그래서 역할을 나눈다 — **이름은 AI, 숫자는 표.** 모델은 후보 목록에서 종목 하나를
고르고 확신도를 붙일 뿐이고, 소모 칼로리는 그 종목의 계수와 회원 체중에서
결정적으로 나온다. 식단이 "무엇인지는 인식기, 수치는 공공 DB" 로 나눈 것과 같다.

## 폴백 규약

인식기·장소 검색과 같다. 키가 없거나 호출이 실패하거나 답을 못 읽으면 **조용히
None** 을 돌려주고, 부르는 쪽이 유형 표로 떨어진다. 이름 해석은 저장의 전제가
아니다 — 외부 의존이 없는 환경에서도 운동 기록은 저장돼야 한다.

## 호출 시점

폼이 조작될 때마다가 아니라 **이름 입력이 끝난 시점 한 번**이다. 그리고 한 번
해석한 이름은 캐시되므로(`exercise_name_matches`), 같은 이름을 두 번 묻지 않는다.
"""
from __future__ import annotations

import json
import logging

from app.core.config import get_settings

log = logging.getLogger(__name__)

#: 출력 토큰 상한(#3032). `{"match": …, "confidence": …}` 한 줄이면 충분하다.
LLM_MAX_OUTPUT_TOKENS = 256

_PROMPT = """너는 운동 기록 앱의 분류기다. 사용자가 적은 운동 이름을 아래 종목 목록 중 하나로 접어라.

종목 목록:
{catalog}

사용자가 적은 이름: "{name}"

규칙:
- 목록에 있는 종목 이름을 **그대로** 골라라. 목록에 없는 이름을 지어내지 마라.
- 표기가 달라도 같은 운동이면 고른다("런닝머신" → "러닝머신", "싸이클" → "자전거").
- 어떤 종목인지 알 수 없거나("오늘 운동", "PT"), 여러 종목이 섞여 있으면 match 를 null 로 둬라.
- confidence 는 0.0~1.0. 확신이 없으면 낮게 준다. 억지로 고르지 마라.
- 소모 칼로리를 계산하지 마라. 종목을 고르는 것이 전부다.

아래 JSON 스키마로만 응답한다. 설명·마크다운·코드블록 없이 순수 JSON 만 출력한다.
{{"match": "종목 이름 또는 null", "confidence": 0.0~1.0}}"""


def _client_and_model():
    """Gemini 클라이언트. 키가 없으면 None — 부르는 쪽이 폴백한다."""
    settings = get_settings()
    if not settings.exercise_name_ai or not settings.gemini_api_key:
        return None, ""
    from google import genai
    from google.genai import types

    client = genai.Client(
        api_key=settings.gemini_api_key,
        http_options=types.HttpOptions(
            timeout=int(settings.gemini_timeout_seconds * 1000)
        ),
    )
    return client, settings.gemini_model


def resolve_name(name: str, candidates: list[str]) -> tuple[str, float] | None:
    """`name` 을 `candidates` 중 하나로. 못 고르면 None.

    돌려주는 이름은 **후보 목록에 실제로 있는 값**임을 여기서 확인한다 — 모델이
    목록에 없는 종목을 지어내면 매칭 단계에서 조용히 폴백하는 대신 여기서 버린다.
    """
    if not name.strip() or not candidates:
        return None

    client, model = _client_and_model()
    if client is None:
        return None

    from app.services import ai_call_quota
    from app.services.coach.llm import gemini_truncated
    from app.services.coach.llm_base import output_cap

    try:
        # 서버 전체 하루 상한(#3032). 넘으면 다른 실패와 같이 유형 표로 떨어진다.
        ai_call_quota.acquire(ai_call_quota.FEATURE_EXERCISE_NAME)
    except ai_call_quota.AiCapacityReached:
        log.info("서버 AI 하루 상한 도달 — 운동 이름은 유형 표로 폴백합니다.")
        return None
    except Exception:  # noqa: BLE001 — 세기 실패로 운동 저장을 막지 않는다
        log.warning("AI 호출 상한 확인 실패 — 유형 표로 폴백합니다.", exc_info=True)
        return None

    try:
        from google.genai import types

        response = client.models.generate_content(
            model=model,
            contents=_PROMPT.format(
                catalog="\n".join(f"- {c}" for c in candidates), name=name.strip()
            ),
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                # 같은 이름에 같은 종목이 나오게. 캐시가 값을 굳혀 주지만, 캐시가
                # 비워진 뒤에도 같은 답이 나오는 편이 낫다.
                temperature=0.0,
                max_output_tokens=output_cap(LLM_MAX_OUTPUT_TOKENS),
            ),
        )
        if gemini_truncated(response):
            raise ValueError("운동 이름 해석 응답이 출력 상한에 걸려 끊김")
        data = json.loads(response.text or "{}")
    except Exception:  # noqa: BLE001 — 어떤 실패든 폴백이 답이다
        log.warning("운동 이름 해석 실패 — 유형 표로 폴백합니다.", exc_info=True)
        return None

    matched = data.get("match")
    if not isinstance(matched, str) or matched not in candidates:
        return None
    try:
        confidence = float(data.get("confidence") or 0)
    except (TypeError, ValueError):
        return None
    return matched, max(0.0, min(1.0, confidence))
