"""회원의 기록을 개인 RAG 문서로 적재(best-effort).

지금 적재하는 것: 식단 기록(`record_diet`), 트레이너↔회원 채팅(`record_chat`, #580),
운동 세션(`record_exercise`, #586).

혈압·혈당은 여기 없고 앞으로도 없다 — 입력이 번거로워 **제품에서 빼기로 한 항목**이다
(그래서 `vitals` 테이블도 엔드포인트도 없다). 적재를 깜빡한 게 아니므로 나중에
"운동은 있는데 혈압은 왜 없지" 로 다시 열지 말 것. 코치 프롬프트가 혈압·혈당을
전제로 말하던 것도 함께 정리했다(#2026).
적재해 두면 회원 앱 AI 코치의 두 경로(홈 피드백 카드·챗봇)가 retrieve 를 통해
자동으로 근거로 쓴다 — 코치 쪽 코드를 건드리지 않아도 된다.

원칙: 적재 실패(임베딩 오류 등)가 절대 원 기록 저장이나 응답을 깨뜨리지 않는다.
실패 시 조용히 넘어가고 세션을 롤백해 정리한다. RAG_AUTO_INGEST=false 로 끌 수 있다.
"""
from __future__ import annotations

import json
import logging
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.services import exercise_types
from app.services.coach import prompt_safety
from app.services.coach.rag import (
    ensure_personal_text,
    ingest_personal_text,
    purge_personal,
    replace_personal_text,
)

log = logging.getLogger(__name__)


def _safe(
    db: Session, user_id: str, text: str, *, domain: str, source: str,
    source_ref: str | None = None, once: bool = False,
) -> None:
    if not get_settings().rag_auto_ingest or not user_id or not text.strip():
        return
    try:
        # 이미 적재된 기록이면 건너뛴다(#604). 확인과 삽입을 한 트랜잭션으로 묶는
        # ensure_personal_text 를 쓴다 — 밖에서 has_personal_doc 로 보고 따로 넣으면
        # 두 인스턴스가 동시에 기동할 때 같은 기록의 청크가 두 벌 들어간다.
        if once and source_ref:
            ensure_personal_text(
                db, user_id, text, domain=domain, source=source,
                source_ref=source_ref, title="",
            )
            return
        ingest_personal_text(
            db, user_id, text, domain=domain, source=source, title="",
            source_ref=source_ref,
        )
    except Exception as e:  # noqa: BLE001 — 적재 실패가 원 기록을 깨면 안 됨
        log.warning("개인 RAG 적재 실패(무시): %s", e)
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass


def forget(db: Session, user_id: str, source_ref: str) -> None:
    """기록이 삭제되면 그 근거 문서도 지운다(#603, best-effort).

    남겨 두면 코치가 사용자가 지운 기록을 계속 근거로 든다 — 사용자 입장에서는
    지운 것이 되살아나는 셈이다.
    """
    if not get_settings().rag_auto_ingest or not user_id or not source_ref:
        return
    try:
        purge_personal(db, user_id, source_ref)
    except Exception as e:  # noqa: BLE001 — 정리 실패가 삭제 응답을 깨면 안 됨
        log.warning("개인 RAG 문서 삭제 실패(무시): %s", e)
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass


#: 이 길이 미만은 적재하지 않는다. 대화의 절반 이상은 "넵", "감사합니다" 같은
#: 정형 응답이라 임베딩 비용만 쓰고 검색 상위에 잡음으로 올라온다.
CHAT_MIN_LENGTH = 6

#: 길이 조건은 넘지만 내용이 없는 상용구. 공백·문장부호를 지운 뒤 비교한다.
_CHAT_BOILERPLATE = frozenset({
    "네알겠습니다", "넵알겠습니다", "감사합니다", "감사해요", "고맙습니다",
    "확인했습니다", "확인했어요", "알겠습니다", "알겠어요", "좋습니다",
    "좋아요", "수고하셨습니다", "수고하세요", "안녕하세요", "잘부탁드립니다",
})


def _chat_is_ingestable(text: str) -> bool:
    """적재할 가치가 있는 발화인가 — 길이와 상용구로만 판단한다.

    의미 판정(증상 언급인지)은 하지 않는다. 그건 검색 단계가 할 일이고, 여기서
    걸러 버리면 나중에 근거가 되었을 발화를 되살릴 방법이 없다.
    """
    stripped = text.strip()
    if len(stripped) < CHAT_MIN_LENGTH:
        return False
    squashed = "".join(ch for ch in stripped if ch.isalnum())
    return squashed not in _CHAT_BOILERPLATE


def record_chat(
    db: Session, member_id: str, *, sender: str, text: str, date: str,
    source_ref: str | None = None, once: bool = False,
) -> None:
    """트레이너↔회원 채팅 한 줄을 회원의 개인 문서로 적재한다(#580).

    소유자는 항상 **회원**이다(`user_id=member_id`). 트레이너가 보낸 말도 회원의
    맥락이고, 회원 앱 AI 코치는 `user_id` 로만 검색하기 때문이다. 트레이너 쪽
    코칭 질의도 검색 스코프가 담당 회원이라 같은 문서를 본다.

    발화자를 본문에 함께 박는 이유: 검색 결과는 `content` 만 프롬프트로 나가므로
    (`coach/chat.py:_format_context`), 여기서 라벨을 넣지 않으면 모델이 트레이너의
    지시를 회원의 증상 호소로 오인한다.

    도메인은 'general' 이다 — 무릎 통증 한 마디가 식단 코치와 운동 코치 양쪽에서
    검색되어야 하는데, retrieve 는 'general' 을 항상 후보에 포함한다.
    """
    if not _chat_is_ingestable(text):
        return
    speaker = prompt_safety.speaker_label(sender)
    _safe(
        db, member_id, f"{date} 대화 — {speaker}: {text.strip()}",
        domain="general", source="chat", source_ref=source_ref, once=once,
    )


#: 운동 타입/강도의 한국어 라벨. 검색 질의도 답변도 한국어라 저장 코드값(cardio,
#: light …)을 그대로 넣으면 임베딩이 질의와 겉돈다.
#: 표준 어휘 네 가지로 적는다 (#996). 옛 값으로 저장된 기록도 같은 라벨로
#: 적재돼야 질의("스트레칭 운동 얼마나 했지")가 한 덩이로 걸린다.
_EXERCISE_TYPE_KR = exercise_types.label_for
_EXERCISE_INTENSITY_KR = {"light": "낮음", "moderate": "보통", "high": "높음"}


def exercise_text(
    *, date: str, exercise_type: str, minutes: int, calories: int,
    intensity: str,
) -> str:
    """운동 세션 한 건의 문서 본문. 적재와 갱신이 같은 문구를 쓰게 한 곳에 둔다."""
    return (
        f"{date} 운동 기록: "
        f"{_EXERCISE_TYPE_KR(exercise_type)} {minutes}분, "
        f"{calories}kcal, 강도 {_EXERCISE_INTENSITY_KR.get(intensity, intensity)}."
    )


def diet_text(
    *, date: str, foods: list[dict], total_calories: int, sodium_mg: int,
    sugar_g: float,
) -> str:
    """식단 기록 한 건의 문서 본문.

    dict 이 아닌 항목은 건너뛴다. 저장된 JSON 이 늘 dict 목록이라는 보장이 없고,
    여기서 터지면 갱신이 조용히 실패해 옛 근거가 남는다.
    """
    names = ", ".join(
        f["name"] for f in foods
        if isinstance(f, dict) and isinstance(f.get("name"), str) and f["name"]
    ) or "식단"
    return (
        f"{date} 식단 기록: {names}. "
        # 당류는 float 이라 그대로 찍으면 29.497999999999998 이 근거 문장에
        # 들어간다 — 소수 한 자리로 끊는다(#1564).
        f"총 {total_calories}kcal, 나트륨 {sodium_mg}mg, 당류 {sugar_g:.1f}g."
    )


def record_exercise(
    db: Session, user_id: str, *, date: str, exercise_type: str, minutes: int,
    calories: int, intensity: str, source_ref: str | None = None,
    once: bool = False,
) -> None:
    """운동 세션 한 건을 개인 문서로 적재한다(#586).

    운동 코치(`domain_coaches.exercise_coach`)는 `domain="exercise"` 로 검색하는데
    지금까지 개인 문서가 하나도 없어, 프롬프트가 운동 조언을 지시해도 근거가 공공
    가이드라인뿐이었다.

    회원이 직접 남긴 기록과 PT 완료로 파생된 기록을 모두 받는다 — 회원 입장에서는
    둘 다 '내가 한 운동'이고, 주간 집계도 이미 둘을 합쳐서 보여준다(#499).
    """
    text = exercise_text(
        date=date, exercise_type=exercise_type, minutes=minutes,
        calories=calories, intensity=intensity,
    )
    _safe(
        db, user_id, text, domain="exercise", source="exercise",
        source_ref=source_ref, once=once,
    )


def record_diet(
    db: Session, user_id: str, *, date: str, foods: list[dict],
    total_calories: int, sodium_mg: int, sugar_g: float,
    source_ref: str | None = None, once: bool = False,
) -> None:
    text = diet_text(
        date=date, foods=foods, total_calories=total_calories,
        sodium_mg=sodium_mg, sugar_g=sugar_g,
    )
    _safe(
        db, user_id, text, domain="diet", source="diet",
        source_ref=source_ref, once=once,
    )


def _safe_replace(
    db: Session, user_id: str, *, domain: str, source: str, source_ref: str,
    load_text,
) -> None:
    """교체도 best-effort 다 — 실패가 원 기록 수정을 되돌리면 안 된다."""
    if not get_settings().rag_auto_ingest or not user_id or not source_ref:
        return
    try:
        replace_personal_text(
            db, user_id, domain=domain, source=source, source_ref=source_ref,
            load_text=load_text, title="",
        )
    except Exception as e:  # noqa: BLE001 — 적재 실패가 원 기록을 깨면 안 됨
        log.warning("개인 RAG 문서 갱신 실패(무시): %s", e)
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass


def refresh_exercise(db: Session, user_id: str, *, session_id: str) -> None:
    """운동 기록이 바뀌었을 때 그 근거 문서를 현재 행에 맞춘다 (#603, #614).

    값을 받지 않고 **잠금 안에서 행을 다시 읽는다.** 호출자가 읽은 값을 넘기면,
    두 수정이 역순으로 적재될 때 옛 값이 최종 문서로 남는다 — DB 는 45분인데
    코치는 30분을 근거로 답하게 된다.
    """
    from app.models.models import ExerciseSession

    def _load() -> str | None:
        row = db.scalar(
            select(ExerciseSession).where(
                ExerciseSession.id == session_id,
                ExerciseSession.user_id == user_id,
            )
        )
        if row is None:
            return None  # 그 사이 지워졌다 — 근거도 지운다.
        return exercise_text(
            date=exercise_session_date(row), exercise_type=row.type,
            minutes=row.minutes, calories=row.calories, intensity=row.intensity,
        )

    _safe_replace(
        db, user_id, domain="exercise", source="exercise",
        source_ref=session_id, load_text=_load,
    )


def refresh_diet(db: Session, user_id: str, *, entry_id: str) -> None:
    """식단 기록이 바뀌었을 때 그 근거 문서를 현재 행에 맞춘다 (#603, #614)."""
    from app.models.models import DietEntry

    def _load() -> str | None:
        row = db.scalar(
            select(DietEntry).where(
                DietEntry.id == entry_id, DietEntry.user_id == user_id
            )
        )
        if row is None:
            return None
        return diet_text(
            date=row.date, foods=_entry_foods(row.foods_json),
            total_calories=row.total_calories, sodium_mg=row.sodium_mg,
            sugar_g=row.sugar_g,
        )

    _safe_replace(
        db, user_id, domain="diet", source="diet", source_ref=entry_id,
        load_text=_load,
    )


def _entry_foods(foods_json: str | None) -> list[dict]:
    """저장된 foods_json → 음식 dict 목록. 깨진 값은 걸러 낸다.

    최상위가 리스트여도 항목이 문자열·숫자일 수 있다. 그대로 넘기면 `diet_text` 가
    `f.get(...)` 에서 터지고, 그 예외를 `_safe_replace` 가 삼켜 **근거가 옛 값으로
    남는다** — 수정했는데 코치는 여전히 이전 수치로 답한다. 조용히 실패하는 경로라
    여기 파싱 경계에서 dict 만 남긴다.
    """
    try:
        value = json.loads(foods_json or "[]")
    except (TypeError, ValueError):
        return []
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def exercise_session_date(row) -> str:
    """세션의 논리 운동일. 규칙은 [exercise_activity.activity_date_of] 하나다.

    적재 문구에 날짜를 넣으려면 되돌려야 한다 — "월요일" 만 적으면 몇 주 전
    기록도 똑같이 보여 코치가 최근 것과 구분하지 못한다.
    """
    from app.services import exercise_activity

    day = exercise_activity.activity_date_of(row)
    return day.isoformat() if day is not None else str(row.week_start)
