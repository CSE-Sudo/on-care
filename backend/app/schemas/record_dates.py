"""기록 날짜 공통 규칙 — 아직 오지 않은 날은 받지 않는다. (#3042)

식단 기록은 여기에 하한(작년 1월 1일, [not_before_floor])을 더한다(#3354).

먹지 않은 식사, 하지 않은 운동은 기록할 수 없다. 앞날을 받으면 오늘까지를 세는
평균·연속 기록·주간 챌린지가 미래 값을 함께 세고, 포인트 하루 한도는 적립 시점
기준이라 며칠 치 기록을 미리 넣어 적립을 앞당길 수 있다.

날짜 비교는 서버 시계(`app.core.clock`, KST)로 한다 — 클라이언트 시간대를 믿지
않는다. 식단(`diet_api`, 문자열 날짜)과 운동(`exercise_api`, `date` 타입)이 표기
검사는 각자 하고, 비교와 거절 문구는 여기 한 곳을 쓴다.
"""
from __future__ import annotations

import re
from datetime import date

from app.core import clock

#: 계약 날짜 표기 `YYYY-MM-DD`. ASCII 숫자만 — `\d` 는 다른 문자권 숫자도 받는다.
_YMD = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
#: 계약 시각 표기 `HH:MM`(24시간, 두 자리).
_HHMM = re.compile(r"([01][0-9]|2[0-3]):[0-5][0-9]")


def parse_ymd(value: str) -> date:
    """`YYYY-MM-DD` 한 가지 표기만 날짜로 읽는다. 아니면 `ValueError`. (#3243)

    `date.fromisoformat`(3.11+)은 `20261005`·`2026-W40-1` 같은 다른 ISO 표기도 받는다.
    그 원문이 그대로 저장되면 날짜 칸의 문자열 범위 조회·정렬·비교가 어긋난다 — 같은
    날짜가 두 문자열로 남는다. 형태를 먼저 맞춘 뒤 달력에 있는 날인지 본다.
    """
    if not isinstance(value, str) or not _YMD.fullmatch(value):
        raise ValueError("날짜는 YYYY-MM-DD 형식이어야 합니다.")
    return date.fromisoformat(value)


def is_hhmm(value: str) -> bool:
    """`HH:MM`(두 자리 24시간) 표기인가. `9:5`·`24:00` 은 아니다. (#3243)"""
    return isinstance(value, str) and _HHMM.fullmatch(value) is not None

#: 앞날 거절 문구(422). 식단·운동이 같은 말을 한다.
FUTURE_DATE_MESSAGE = "date 는 오늘보다 뒤일 수 없어요."


def not_after_today(value: date) -> date:
    """`value` 가 오늘(KST)보다 뒤면 `ValueError`(→ 422)."""
    if value > clock.today():
        raise ValueError(FUTURE_DATE_MESSAGE)
    return value


#: 하한 거절 문구(422). 식단의 사진 분석·직접 입력·수정이 같은 말을 한다.
TOO_OLD_DATE_MESSAGE = "date 는 작년 1월 1일보다 앞설 수 없어요."


def record_floor() -> date:
    """기록을 남길 수 있는 가장 이른 날 — 작년(KST) 1월 1일. 앱의 날짜 고르기 범위와 같다."""
    return date(clock.today().year - 1, 1, 1)


def not_before_floor(value: date) -> date:
    """`value` 가 [record_floor] 보다 앞서면 `ValueError`(→ 422). (#3354)

    사진 분석에만 있던 하한(#2849)을 식단 기록의 세 길이 함께 쓴다. 한 길만 열려
    있으면 아주 오래된 날짜가 그 길로 들어와, 기간 그래프의 시작점(첫 기록 날짜)과
    전체 통계가 수십 년 전으로 늘어난다.
    """
    if value < record_floor():
        raise ValueError(TOO_OLD_DATE_MESSAGE)
    return value
