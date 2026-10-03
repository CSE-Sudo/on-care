"""주 시작(월요일) 계산의 단일 정의 (#2908).

서비스·시드·라우터가 `day - timedelta(days=day.weekday())` 를 저마다 적던 것을
여기 하나로 모은다. 회원 앱·트레이너 웹의 공용 `mondayOf`
(`shared/oncare_ui/lib/src/dates/wire_date.dart`) 와 같은 규칙이다.
"""

from __future__ import annotations

from datetime import date, timedelta


def monday_of(day: date) -> date:
    """`day` 가 속한 주의 월요일. 월요일이면 그대로 돌려준다."""
    return day - timedelta(days=day.weekday())
