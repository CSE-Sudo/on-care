"""트레이너 채팅에서 다음 PT 약속을 읽어 낸다. (#1061)

약속은 대화에서 잡힌다 — "다음 PT는 다음 주 수요일 오후 8시로 할게요!" 처럼.
그런데 그 말은 채팅 안에만 남아, 운동 탭의 `다음 PT 일정` 은 여전히 비어 있거나
지난 일정을 들고 있었다. 회원은 방금 잡은 약속을 확인하려고 대화를 거슬러
올라가야 했다.

**해석은 서버가 한다.** 앱과 트레이너웹이 각자 문장을 풀면 같은 대화에서 서로
다른 약속이 만들어진다.

**모르면 만들지 않는다.** 없는 약속을 지어내는 쪽이, 약속을 놓치는 쪽보다
나쁘다 — 회원이 엉뚱한 날에 헬스장에 간다. 그래서 세 가지가 **모두** 있어야
약속으로 본다: PT 를 가리키는 말, 풀 수 있는 날짜, 그리고 시각. 시각이 없으면
"수요일에 봐요" 같은 인사말과 구분되지 않는다.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date as date_type
from datetime import time as time_type
from datetime import timedelta

from app.core.week import monday_of

#: PT 를 가리키는 말. 이 말이 없으면 날짜·시각이 있어도 약속으로 보지 않는다 —
#: "내일 오전 10시에 약 드세요" 를 PT 로 만들면 안 된다.
_PT_WORDS = ("pt", "피티", "수업", "세션", "레슨")

#: 약속이 아니라 **묻는 말**이라는 신호. "수요일 어때요?" 는 아직 정해진 것이
#: 없다 — 한쪽이 제안했을 뿐이라 일정으로 굳히면 안 된다.
_ASKING = ("어때", "어떠", "괜찮", "가능하", "될까", "될까요", "?")

#: 취소·변경을 말하는 문장은 새 약속으로 읽지 않는다. 무엇을 지울지까지는 이
#: 단계에서 알 수 없어, 사람이 일정 화면에서 정리하도록 둔다.
_NEGATIVE = ("취소", "미루", "연기", "쉬어", "쉬는", "못 가", "못가", "어렵")

_WEEKDAYS = {"월": 0, "화": 1, "수": 2, "목": 3, "금": 4, "토": 5, "일": 6}

#: "낮 N시" 에서 이 시각 아래는 오후로 읽는다 — "낮 2시" 는 14시, "낮 11시" 는 11시.
_NOON_MORNING_HOUR = 7


@dataclass(frozen=True)
class ParsedSchedule:
    """읽어 낸 약속 — 날짜(`YYYY-MM-DD`)와 시각(`HH:MM`)."""

    date: str
    time: str


def _weekday_of(text: str) -> int | None:
    m = re.search(r"([월화수목금토일])\s*요일", text)
    return _WEEKDAYS[m.group(1)] if m else None


def _resolve_date(text: str, sent_on: date_type) -> date_type | None:
    """상대 표현은 **보낸 날**을 기준으로 푼다.

    "다음 주 수요일" 은 읽는 시점이 아니라 말한 시점에서 센 날이다. 나중에
    다시 계산하면 같은 문장이 매번 다른 날을 가리킨다.
    """
    # 1) 절대 날짜 — "8월 25일". 이미 지난 날짜면 내년으로 본다.
    m = re.search(r"(\d{1,2})\s*월\s*(\d{1,2})\s*일", text)
    if m:
        month, day = int(m.group(1)), int(m.group(2))
        try:
            found = date_type(sent_on.year, month, day)
        except ValueError:
            return None
        if found < sent_on:
            try:
                found = date_type(sent_on.year + 1, month, day)
            except ValueError:
                return None
        return found

    # 2) 오늘/내일/모레
    if "모레" in text:
        return sent_on + timedelta(days=2)
    if "내일" in text:
        return sent_on + timedelta(days=1)

    weekday = _weekday_of(text)
    if weekday is None:
        # 요일도 날짜도 없이 "오늘 8시" 만 남은 경우.
        return sent_on if "오늘" in text else None

    # 3) 요일 — 이번 주는 월요일 기준, 다음 주는 그 다음 월요일 기준이다.
    monday = monday_of(sent_on)
    if "다음 주" in text or "다음주" in text or "담주" in text:
        return monday + timedelta(days=7 + weekday)
    if "이번 주" in text or "이번주" in text:
        return monday + timedelta(days=weekday)
    # 4) 그냥 "수요일" — 보낸 날 이후 가장 가까운 그 요일이다. 오늘이 그 요일
    #    이면 오늘로 본다(시각이 뒤에 붙으므로 지난 시간인지는 여기서 따지지
    #    않는다).
    ahead = (weekday - sent_on.weekday()) % 7
    return sent_on + timedelta(days=ahead)


def _resolve_time(text: str) -> str | None:
    """오전/오후가 붙은 시각, 또는 24시간으로 적은 시각만 받는다.

    "7시" 처럼 오전·오후가 없는 한 자리 시각은 짐작하지 않는다. 저녁일 것
    같다는 이유로 19시로 굳히면, 아침 7시 수업이 12시간 밀린다.

    "낮" 은 한낮이다(#3241). "낮 2시" 는 14시이고, "낮 11시"·"낮 12시" 는 그대로
    둔다 — 보정이 없으면 "내일 낮 2시" 가 새벽 2시 일정이 된다.
    """
    m = re.search(r"(오전|오후|저녁|아침|낮)?\s*(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?", text)
    if m:
        marker, hour_s, minute_s = m.group(1), m.group(2), m.group(3)
        hour = int(hour_s)
        minute = int(minute_s or 0)
        if marker in ("오후", "저녁") and hour < 12:
            hour += 12
        elif marker == "낮" and hour < _NOON_MORNING_HOUR:
            hour += 12
        elif marker in ("오전", "아침") and hour == 12:
            hour = 0
        elif marker is None and hour < 13:
            # 오전·오후 없이 12시 이하면 어느 쪽인지 알 수 없다.
            return None
        if hour > 23 or minute > 59:
            return None
        return f"{hour:02d}:{minute:02d}"

    m = re.search(r"\b(\d{1,2}):(\d{2})\b", text)
    if m:
        hour, minute = int(m.group(1)), int(m.group(2))
        if hour > 23 or minute > 59:
            return None
        return f"{hour:02d}:{minute:02d}"
    return None


def parse_schedule(
    text: str, *, sent_on: date_type, sent_time: time_type | None = None
) -> ParsedSchedule | None:
    """[text] 에서 다음 PT 약속을 읽는다. 확실하지 않으면 None.

    [sent_on] 은 그 메시지를 보낸 날(KST)이고, [sent_time] 은 보낸 시각(KST)이다.
    보낸 시각을 주면 **이미 지난 시각**은 약속으로 보지 않는다(#3241) — 15시에
    "오늘 오전 9시 PT" 라고 적은 것은 지난 수업 이야기라 `예정` 으로 만들면 안 된다.
    """
    if not text:
        return None
    lowered = text.lower()
    if not any(word in lowered for word in _PT_WORDS):
        return None
    if any(word in text for word in _NEGATIVE):
        return None
    if any(word in text for word in _ASKING):
        return None

    when = _resolve_date(text, sent_on)
    if when is None:
        return None
    at = _resolve_time(text)
    if at is None:
        return None
    if (
        sent_time is not None
        and when == sent_on
        and at <= sent_time.strftime("%H:%M")
    ):
        return None
    return ParsedSchedule(date=when.isoformat(), time=at)
