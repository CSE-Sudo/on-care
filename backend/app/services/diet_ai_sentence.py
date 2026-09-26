"""식단 AI 맞춤 조언의 **AI 한 문장** — 원인 메뉴를 짚거나 구체적인 대안을 준다. (#2253)

회의 결정 3번의 역할 분담:

| 부분 | 담당 |
| --- | --- |
| 1,800mg·300kcal·단백질 8g 같은 수치 | 규칙(정확해야 한다) |
| "짬뽕 때문", "케이크가 컸음" 같은 원인 메뉴 | AI |
| "구운 생선", "바나나 1개" 같은 구체적 대안 | AI |

그래서 이 문장에는 **수치를 쓰지 못하게 한다.** 프롬프트로 막고, 응답을 검사해 규칙이
계산하지 않은 수(mg·kcal·g·%, 8 이상의 수)가 있으면 버린다. "주 3회", "달걀 2개"
같은 작은 횟수는 대안의 일부라 허용한다.

길이 한도를 넘거나 수치가 섞이면 한 번 다시 받고, 그래도 안 되면 None — 호출부가
규칙 대체 문장을 쓴다. AI 는 품질을 올리는 층이지 가용성의 전제가 아니다.
"""
from __future__ import annotations

import json
import logging
import re
import threading
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout

from app.core import metrics
from app.services.coach.llm import DEFAULT_THINKING_BUDGET, get_coach_llm
from app.services.coach.prompt_safety import FOOD_NAME_GUARD, TRAINER_DIET_GUARD
from app.services.diet_advice_copy import plain

logger = logging.getLogger(__name__)

#: 짧은 문장 하나라 오래 기다리지 않는다. 식단 탭 카드가 이 응답을 기다린다.
LLM_TIMEOUT_SEC = 8.0
LLM_MAX_CONCURRENCY = 4
#: 한 번 더 받아 보는 횟수. 길이·수치 검사에 걸리면 다시 받는다.
MAX_ATTEMPTS = 2

#: 카드의 두 문장 한도. 한국어는 한 문장 반(#1574), 영어는 같은 폭에 드는 길이다.
CARD_MAX = {"ko": 45, "en": 90}
#: 규칙 한 줄이 아무리 길어도 AI 문장에 남겨 둘 최소 길이.
MIN_SENTENCE = {"ko": 16, "en": 32}
#: 허용하는 작은 횟수의 상한("주 3회", "달걀 2개").
SMALL_COUNT_MAX = 7

_executor = ThreadPoolExecutor(
    max_workers=LLM_MAX_CONCURRENCY, thread_name_prefix="diet-advice-llm"
)
_llm_slots = threading.BoundedSemaphore(LLM_MAX_CONCURRENCY)

_NUMBER = re.compile(r"\d[\d,.]*")
#: 수 뒤에 오면 규칙이 계산할 수치로 보는 단위. 영문 단위는 낱말 경계까지 본다 —
#: "2 glasses" 의 g 를 그램으로 읽지 않도록.
_MEASURE_UNIT = re.compile(r"(?:(?:mg|kcal|cal|g)(?![a-z])|%|㎎|킬로|칼로리|그램|밀리)")


class LLMBusyError(RuntimeError):
    """동시 호출 한도가 차서 AI 를 부르지 않았다."""


def sentence_limit(lang: str, analysis_text: str) -> int:
    """규칙 한 줄 뒤에 남는 길이. 영어는 앱이 문장을 다시 그려 서버가 정확히 모르므로
    고정 폭을 쓴다."""
    if lang == "en":
        return CARD_MAX["en"] - 40
    return max(MIN_SENTENCE["ko"], CARD_MAX["ko"] - len(plain(analysis_text)) - 1)


def has_measure(text: str) -> bool:
    """규칙이 계산할 수치(단위가 붙은 수, 8 이상의 수)가 들어 있는가."""
    for m in _NUMBER.finditer(text):
        raw = m.group().rstrip(",.")
        try:
            value = float(raw.replace(",", ""))
        except ValueError:
            return True
        tail = text[m.end():].lstrip().lower()
        if _MEASURE_UNIT.match(tail):
            return True
        if value != int(value) or value > SMALL_COUNT_MAX:
            return True
    return False


def clean(raw: str) -> str:
    """응답 JSON 또는 맨 문장 → 한 문장. 따옴표·줄바꿈을 걷는다."""
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else ""
        text = text.rsplit("```", 1)[0].strip()
    try:
        data = json.loads(text)
        if isinstance(data, dict):
            text = str(data.get("sentence", ""))
    except ValueError:
        pass
    text = " ".join(text.split()).strip().strip('"“”\'')
    # 굵게 표시는 두 곳까지만 — 더 많으면 강조가 아니다.
    if text.count("**") > 4 or text.count("**") % 2:
        text = plain(text)
    return text


def valid(text: str, limit: int) -> bool:
    return bool(text) and len(plain(text)) <= limit and not has_measure(text)


def build_prompt(
    *,
    lang: str,
    limit: int,
    finding: str,
    records: list[str],
    notes: list[str],
    goal: str,
) -> tuple[str, str]:
    language = "영어(English)" if lang == "en" else "한국어"
    system = (
        "너는 PT(개인 트레이닝)를 받는 회원의 식단을 돕는 영양 코치다. 규칙이 찾아낸 "
        "[분석] 한 가지를 보고, 그 뒤에 붙일 **다음 할 일 한 문장**을 쓴다.\n"
        "규칙:\n"
        "1. [기록]에서 원인이 된 메뉴를 짚거나, 바꿔 먹을 구체적인 음식을 권한다"
        "(예: 짬뽕 국물은 반만, 건더기 위주로요 / 요거트나 삶은 달걀이라도 드세요).\n"
        f"2. 한 문장, {language}, 공백 포함 {limit}자 이내. 존댓말(해요체).\n"
        "3. **수치를 쓰지 않는다.** mg·kcal·g·% 같은 양은 이미 [분석]이 말했다. "
        "'주 3회', '달걀 2개' 같은 작은 횟수만 쓸 수 있다.\n"
        "4. 메뉴·음식 이름은 **로 감쌀 수 있다(두 곳까지).\n"
        "5. 의학적 진단·치료를 단정하지 않는다.\n"
        f"{TRAINER_DIET_GUARD}\n{FOOD_NAME_GUARD}\n"
        'JSON 만 출력한다: {"sentence":"..."}'
    )
    lines = [f"[분석] {finding}", f"[목표] {goal or '정보 없음'}", "", "[기록]"]
    lines += [f"- {r}" for r in records] or ["- 없음"]
    lines += ["", "[트레이너 메시지]"]
    lines += [f"- 트레이너: {n}" for n in notes] or ["- 없음"]
    return system, "\n".join(lines)


def _call_llm(system: str, user: str) -> str:
    if not _llm_slots.acquire(blocking=False):
        raise LLMBusyError("LLM 동시 호출 한도 초과")

    def _call():
        try:
            return get_coach_llm().generate(
                system, user, json_mode=True,
                thinking_budget=DEFAULT_THINKING_BUDGET,
                timeout_seconds=LLM_TIMEOUT_SEC,
            )
        finally:
            _llm_slots.release()

    return _executor.submit(_call).result(timeout=LLM_TIMEOUT_SEC).text


def generate(
    *,
    lang: str,
    analysis_text: str,
    finding: str,
    records: list[str],
    notes: list[str],
    goal: str,
    metric: str,
) -> str | None:
    """AI 한 문장. 실패·검사 탈락이면 None."""
    limit = sentence_limit(lang, analysis_text)
    system, user = build_prompt(
        lang=lang, limit=limit, finding=finding, records=records, notes=notes, goal=goal,
    )
    for _ in range(MAX_ATTEMPTS):
        try:
            text = clean(_call_llm(system, user))
        except LLMBusyError:
            metrics.incr(f"{metric}.fallback", reason="busy")
            return None
        except FutureTimeout:
            metrics.incr(f"{metric}.fallback", reason="timeout")
            logger.warning("%s LLM timeout (%.1fs)", metric, LLM_TIMEOUT_SEC)
            return None
        except Exception:  # noqa: BLE001 - AI 장애 종류와 무관하게 카드는 떠야 한다
            metrics.incr(f"{metric}.fallback", reason="error")
            logger.warning("%s LLM 실패", metric, exc_info=True)
            return None
        if valid(text, limit):
            metrics.incr(f"{metric}.generated", by="llm")
            return text
        logger.info("%s LLM 문장 검사 탈락: %r", metric, text)
    metrics.incr(f"{metric}.fallback", reason="invalid")
    return None
