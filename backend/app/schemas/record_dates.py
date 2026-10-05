"""기록 날짜 공통 규칙 — 아직 오지 않은 날은 받지 않는다. (#3042)

먹지 않은 식사, 하지 않은 운동은 기록할 수 없다. 앞날을 받으면 오늘까지를 세는
평균·연속 기록·주간 챌린지가 미래 값을 함께 세고, 포인트 하루 한도는 적립 시점
기준이라 며칠 치 기록을 미리 넣어 적립을 앞당길 수 있다.

날짜 비교는 서버 시계(`app.core.clock`, KST)로 한다 — 클라이언트 시간대를 믿지
않는다. 식단(`diet_api`, 문자열 날짜)과 운동(`exercise_api`, `date` 타입)이 표기
검사는 각자 하고, 비교와 거절 문구는 여기 한 곳을 쓴다.
"""
from __future__ import annotations

from datetime import date

from app.core import clock

#: 앞날 거절 문구(422). 식단·운동이 같은 말을 한다.
FUTURE_DATE_MESSAGE = "date 는 오늘보다 뒤일 수 없어요."


def not_after_today(value: date) -> date:
    """`value` 가 오늘(KST)보다 뒤면 `ValueError`(→ 422)."""
    if value > clock.today():
        raise ValueError(FUTURE_DATE_MESSAGE)
    return value
