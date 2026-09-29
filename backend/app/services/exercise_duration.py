"""운동 시간(초)을 읽는 말로 — `45초` · `30분` · `1시간 30분 15초`. (#2546)

트레이너가 시·분·초로 적은 시간이 초(`duration_seconds`)로 남는데(#2221), 서버가
그 시간을 글로 적는 자리(기록 문장·알림·AI 코치 근거)는 분으로 반올림해 `45초` 를
`1분` 으로 적었다. 그 자리들이 모두 이 함수를 쓴다.

0 인 단위는 뺀다 — 딱 떨어지는 30분은 예전(`30분`)과 같은 모양이고, 초를 적었을
때만 길어진다. 회원 앱 `formatDurationParts`·트레이너 웹 `formatExerciseDuration`
과 같은 규칙이고 단위 표기도 같다(`1 hr 30 min 15 sec`).
"""
from __future__ import annotations

from app.core.locale import Locale

_UNITS: dict[Locale, tuple[str, str, str]] = {
    "ko": ("{}시간", "{}분", "{}초"),
    "en": ("{} hr", "{} min", "{} sec"),
}


def format_duration(seconds: int, locale: Locale = "ko") -> str:
    """초 → `1시간 30분 15초`. 0 이하는 `0분` 이다."""
    total = max(0, int(seconds))
    hours_fmt, minutes_fmt, seconds_fmt = _UNITS[locale]
    parts: list[str] = []
    if total // 3600:
        parts.append(hours_fmt.format(total // 3600))
    if total % 3600 // 60:
        parts.append(minutes_fmt.format(total % 3600 // 60))
    if total % 60:
        parts.append(seconds_fmt.format(total % 60))
    return " ".join(parts) if parts else minutes_fmt.format(0)


def seconds_or_minutes(duration_seconds: int | None, minutes: int | None) -> int:
    """초가 있으면 초, 없으면 분 × 60. 초 칸이 생기기 전(#2221)의 행을 읽는 규칙이다."""
    if duration_seconds is not None:
        return duration_seconds
    return (minutes or 0) * 60
