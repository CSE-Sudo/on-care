"""테스트 세션 동안 서비스 기준 '오늘'을 하나로 묶는 시계 고정 (#2940).

`client` 픽스처는 세션 범위라 앱 기동 시 시드가 **세션 시작 때 한 번** 돈다.
시드는 `clock.today()` 로 그날의 식단·수업·타임라인을 만들고, 테스트 본문과
엔드포인트는 요청 시점에 `clock.today()` 를 다시 읽는다. 실행이 KST 자정을
걸치면 두 '오늘'이 하루 어긋나 빈 목록·'어제' 라벨·개수 불일치가 난다.

[SessionClockPin] 은 `clock.now()` 를 대신해 **날짜는 세션 시작일로 두고
시·분·초는 실제 시계를 따른다.** 같은 날 안에서는 실제 시각을 그대로 돌려주므로
기존 테스트의 시간 비교는 달라지지 않는다.

운영 코드는 건드리지 않는다 — 테스트 conftest 가 세션 동안만 바꿔 끼운다.
자기 시각을 넣는 테스트(`monkeypatch.setattr(clock, "now", ...)`)는 그 위에
덮어쓰므로 그 값이 우선하고, 테스트가 끝나면 이 고정으로 돌아온다.
"""
from __future__ import annotations

from collections.abc import Callable
from datetime import date, datetime


class SessionClockPin:
    """날짜만 `start_date` 로 묶은 KST 시계.

    `source` 는 실제 시계(`clock.now` 원본)다. 자정 직전·직후를 검증하는
    테스트는 이 속성만 바꿔 실제 시각이 넘어간 상황을 재현한다.
    """

    def __init__(self, source: Callable[[], datetime]) -> None:
        self.source = source
        self.start_date: date = source().date()

    def now(self) -> datetime:
        current = self.source()
        if current.date() == self.start_date:
            return current
        # 날짜만 시작일로 되돌리고 시각·타임존은 그대로 둔다.
        return datetime.combine(self.start_date, current.timetz())
