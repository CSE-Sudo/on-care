"""
STEP 6 스키마 — 일정 / 알림 / 장소 / AI 코치.
프론트 계약(_scheduleEvents, _notifications, _placesNearby, _aiCoachFeedback) 정렬.
"""
from __future__ import annotations

import re
from datetime import date as _date, datetime
from typing import Literal, Optional
from pydantic import BaseModel, Field, field_validator

from app.schemas.partial_update import PartialUpdate

# 회원 일정 카테고리 허용값(프론트 계약).
ScheduleCategory = Literal["hospital", "exercise", "meal", "medication", "other"]
_HEX_COLOR = r"^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?$"
# 계약 형식은 정확히 YYYY-MM-DD. date.fromisoformat 는 3.11+ 에서 basic ISO(20260726)·
# 주 날짜(2026-W30-7)까지 받으므로 형식을 먼저 좁힌다.
_YMD_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _valid_ymd(v: str) -> str:
    if not _YMD_RE.fullmatch(v):
        raise ValueError("유효한 날짜(YYYY-MM-DD)가 아닙니다.")
    try:
        _date.fromisoformat(v)  # 2026-02-30 등 달력상 불가능한 값 거부
    except ValueError as e:
        raise ValueError("유효한 날짜(YYYY-MM-DD)가 아닙니다.") from e
    return v


def _valid_hhmm_or_empty(v: str) -> str:
    if v == "":
        return v  # 시간 미지정(종일) 허용
    try:
        datetime.strptime(v, "%H:%M")  # 25:99 등 거부
    except ValueError as e:
        raise ValueError("유효한 시간(HH:MM)이 아닙니다.") from e
    return v


# ---- 일정 ----
class NotificationAction(BaseModel):
    """알림에서 바로 갈 수 있는 액션(카테고리에서 파생). 프론트가 target 으로 이동."""
    label: str         # "기록하러 가기"
    target: str        # 프론트 라우트 힌트: schedule|dashboard


class NotificationOut(BaseModel):
    id: str
    title: str
    body: str
    category: str      # reminder|health_check|achievement|system
    read: bool
    created_at: datetime
    time_ago: str
    action: NotificationAction | None = None


# ---- 장소 ----
class PlaceOut(BaseModel):
    id: str
    name: str
    category: str      # medical|fitness|healthy_food|pharmacy
    address: str
    distance_meters: int
    lat: Optional[float]
    lng: Optional[float]


# ---- AI 코치 ----
class CoachSuggestion(BaseModel):
    tag: str           # diet|exercise|hydration|...
    title: str
    body: str


class AiCoachFeedback(BaseModel):
    greeting: str
    suggestions: list[CoachSuggestion]


# ---- AI 코치 챗봇 (대화형) ----
class ChatTurn(BaseModel):
    role: str          # user | coach
    content: str


class ChatRequest(BaseModel):
    message: str
    # 직전 대화(선택). 이제 서버가 대화를 저장하므로 보내지 않아도 맥락이 이어진다.
    # 서버에 저장분이 없을 때만 쓰인다(목업→실 서버 전환 클라이언트 호환).
    history: list[ChatTurn] = []


class ChatInsightOut(BaseModel):
    """회원 메시지 한 줄에서 찾은 통증·부정적 반응 표시. (#1824)"""
    kind: str                      # discomfort | negative_feedback
    body_part: str | None = None   # 통증일 때 찾은 부위(무릎·허리…)


class ChatReply(BaseModel):
    reply: str
    sources: list[str] = []        # 답변 근거로 쓰인 공공 가이드라인 제목
    #: 방금 보낸 회원 메시지의 감지 결과. 없으면 null (#1824).
    user_insight: ChatInsightOut | None = None


class ChatMessageOut(BaseModel):
    """저장된 대화 한 줄. sources 는 그 답변의 근거 문서 제목."""
    role: str                      # user | coach
    content: str
    sources: list[str] = []
    created_at: datetime
    #: 회원 메시지의 통증·부정적 반응 감지. 코치 답변이나 신호가 없으면 null (#1824).
    insight: ChatInsightOut | None = None


class ChatHistory(BaseModel):
    messages: list[ChatMessageOut] = []


class ChatInsightRecordOut(BaseModel):
    """감지 기록 한 줄 — AI 챗봇 오른쪽 위 감지 기록 창의 항목. (#1824)"""
    message_id: str
    created_at: datetime
    kind: str
    body_part: str | None = None
    text: str


class ChatInsightList(BaseModel):
    """최근 30일 감지 기록(최신순)과 기록 기간(일)."""
    window_days: int
    insights: list[ChatInsightRecordOut] = []
