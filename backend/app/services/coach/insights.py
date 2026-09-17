"""AI 챗봇 대화에서 통증·부정적 반응을 찾는다. (#1824)

트레이너 웹 채팅은 회원 메시지에서 통증(부위 포함)과 부정적 피드백을 짚어 준다
(`chat_context_insight.dart`). 담당 트레이너가 없는 회원이 쓰는 AI 챗봇에도 같은
기준으로 감지해, 회원이 AI 에게 한 "무릎이 아파요" 가 어디에도 남지 않는 일을 막는다.

**규칙은 트레이너 웹 감지와 같다.** 한쪽만 고치면 같은 문장을 두 채팅이 다르게
읽으므로, 낱말 경계 규칙(`목요일`·`목표` 의 `목` 오탐 방지 등)을 그대로 옮긴다.
진단이 아니라 **어떤 문장이 무엇을 말했는지** 짚는 결정론적 표시다.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import AiConversation, AiMessage

#: 감지 종류. 트레이너 웹 `ChatInsightKind` 와 같은 이름이다.
KIND_DISCOMFORT = "discomfort"
KIND_NEGATIVE = "negative_feedback"

#: 감지 기록을 모아 보는 기간(메시지 작성일 기준).
INSIGHT_WINDOW_DAYS = 30


@dataclass(frozen=True)
class Insight:
    """메시지 한 줄에서 찾은 신호. 부위는 찾지 못하면 None."""

    kind: str
    body_part: str | None = None


#: 부위 규칙. 한국어는 앞 음절이 한글이면 **다른 낱말의 꼬리**로 본다(`발목`의
#: `목`). 뒤쪽은 조사가 붙어야 하므로 그 음절로 시작하는 다른 낱말만 명시해 뺀다.
_BODY_PARTS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("무릎", re.compile(r"(?<![가-힣])무릎")),
    ("허리", re.compile(r"(?<![가-힣])허리(?!띠|춤)")),
    ("발목", re.compile(r"(?<![가-힣])발목")),
    ("어깨", re.compile(r"(?<![가-힣])어깨")),
    ("손목", re.compile(r"(?<![가-힣])손목(?!시계)")),
    # 목요일·목표·목적·목록·목소리·목도리·목걸이·목욕.
    ("목", re.compile(r"(?<![가-힣])목(?!요일|표|적|록|소리|도리|걸이|욕)")),
    ("Knee", re.compile(r"\bknees?\b")),
    ("Ankle", re.compile(r"\bankles?\b")),
    ("Shoulder", re.compile(r"\bshoulders?\b")),
    ("Wrist", re.compile(r"\bwrists?\b")),
    ("Neck", re.compile(r"\bnecks?\b")),
    # `back` 은 단어 경계만으로는 못 가른다("i'm back"). 소유격·위치어가 앞에
    # 오거나 통증어가 뒤에 붙어야 부위로 읽는다.
    (
        "Back",
        re.compile(
            r"\b(?:my|your|his|her|their|our|the|lower|upper|mid|middle)\s+backs?\b"
            r"|\bbacks?\s+(?:pain|ache|aches|injury)\b"
        ),
    ),
)

#: 통증 표현. 활용형과 경계 규칙을 함께 둔다(`아프리카`·`아파트` 는 통증이 아니다).
_DISCOMFORT: tuple[re.Pattern[str], ...] = tuple(
    re.compile(p)
    for p in (
        r"(?<![가-힣])아(?:프(?!리카|리칸|간)|파(?!트)|팠|픈|픔|픕)",
        r"통증",
        r"(?<![가-힣])당(?:기|겨|겼|김)",
        r"(?<![가-힣])불편",
        r"(?<![가-힣])저(?:리(?!\s*가)|려|렸|릿)",
        r"(?<![가-힣])쑤(?:시|셔|셨|신)",
        r"(?<![가-힣])(?:붓|부어|부었|부기)",
        r"(?<![가-힣])뻐근",
        r"\bpain(?:s|ful|fully)?\b",
        r"\bhurt(?:s|ing)?\b",
        r"\bsore(?:s|ness)?\b",
        r"\bdiscomforts?\b",
        r"\bstiff(?:ness)?\b",
        r"\bach(?:e|es|ed|ing|y)\b",
    )
)

#: 운동을 못 했다·힘들다는 보고. `마무리`·`아무리` 의 `무리` 는 걸러 낸다.
_NEGATIVE: tuple[re.Pattern[str], ...] = tuple(
    re.compile(p)
    for p in (
        r"너무\s*힘들",
        r"(?<![가-힣])못(?:\s|했|하|해)",
        r"(?<![가-힣])포기",
        r"(?<![가-힣])별로",
        r"(?<![가-힣])무리(?!수)",
        r"(?<![가-힣])부담",
        r"(?<![가-힣])지(?:쳐|쳤)",
        r"\btoo hard\b",
        r"\bcouldn'?t\b",
        r"\bcannot\b",
        r"\bgave up\b",
        r"\bexhausted\b",
    )
)


def detect(text: str) -> Insight | None:
    """회원 문장 하나에서 신호를 찾는다. 통증이 부정적 반응보다 먼저다."""
    lowered = (text or "").lower()
    if not lowered.strip():
        return None
    if any(p.search(lowered) for p in _DISCOMFORT):
        part = next((name for name, p in _BODY_PARTS if p.search(lowered)), None)
        return Insight(kind=KIND_DISCOMFORT, body_part=part)
    if any(p.search(lowered) for p in _NEGATIVE):
        return Insight(kind=KIND_NEGATIVE)
    return None


@dataclass(frozen=True)
class InsightRecord:
    """감지 기록 한 줄 — 어떤 메시지가 언제 무엇을 말했나."""

    message_id: str
    created_at: datetime
    kind: str
    body_part: str | None
    text: str


def recent_insights(
    db: Session, user_id: str, *, now: datetime | None = None
) -> list[InsightRecord]:
    """최근 [INSIGHT_WINDOW_DAYS] 일 동안 회원이 AI 챗봇에 쓴 메시지의 감지 기록, 최신순.

    감지 결과는 따로 저장하지 않고 대화에서 매번 계산한다 — 규칙이 바뀌면 지난
    기록에도 같은 규칙이 적용되고, 대화 보관 기간과 기록 기간이 어긋나지 않는다.

    회원이 치운 줄(`insight_dismissed`)은 건너뛴다(#1975). 규칙이 완벽할 수 없어
    `목요일`·`목표` 같은 말이 부위로 잡히는 일이 남는데, 그 오탐을 회원이 치울 수
    있어야 한다. 치우는 것은 감지뿐이고 메시지는 그대로 둔다.
    """
    cutoff = (now or clock.now()) - timedelta(days=INSIGHT_WINDOW_DAYS)
    rows = db.execute(
        select(AiMessage.id, AiMessage.content, AiMessage.created_at)
        .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
        .where(
            AiConversation.user_id == user_id,
            AiMessage.role == "user",
            AiMessage.created_at >= cutoff,
            AiMessage.insight_dismissed.is_(False),
        )
        .order_by(AiMessage.created_at.desc(), AiMessage.seq.desc())
    ).all()
    out: list[InsightRecord] = []
    for message_id, content, created_at in rows:
        found = detect(content)
        if found is None:
            continue
        out.append(
            InsightRecord(
                message_id=message_id,
                created_at=created_at,
                kind=found.kind,
                body_part=found.body_part,
                text=content,
            )
        )
    return out
