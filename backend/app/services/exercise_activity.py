"""운동 기록의 **논리 운동일** — 고객 앱이 보는 날짜 하나로 통일한다. (#1264)

회원 앱의 운동 화면과 트레이너 웹의 주간 운동 화면은 둘 다
`ExerciseSession.week_start + day_label` 을 그 기록의 날짜로 읽는다. 두 화면이
같은 집계(`exercise_service.build_current_week`)를 공유하므로 그것이 곧 제품의
날짜 계약이다.

반면 `created_at` 은 **DB 에 적재된 시각**이다. 과거 기록을 다시 시드하거나
늦게 입력하면 몇 주 전 운동도 방금 만들어진 행이 되어, 고객이 보는 날짜와
서버가 해석하는 날짜가 갈린다 — 김민수 데모는 35주치(245일)를 재시드할 때마다
모든 행의 `created_at` 이 재시드 시각이라, AI 가 35주 전 운동을 최근 운동으로
읽었다.

그래서 날짜의 기준을 하나로 둔다:

1. `week_start + day_label` 이 유효하면 그것이 논리 운동일이다.
2. 두 값이 깨진 옛 행은 `completed_at` 의 KST 날짜로 떨어뜨린다.
3. 그것도 없을 때만 마지막 호환 수단으로 `created_at` 의 KST 날짜를 쓴다.

`created_at` 은 감사·적재 시각일 뿐, 최근 활동 판단에 직접 쓰지 않는다.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta

from app.core import clock
from app.core.week import monday_of

#: 요일 라벨(월=0 … 일=6). `exercise_service.WEEKDAY_LABELS` 와 같은 순서다 —
#: 이 모듈은 모델·서비스 어느 쪽도 import 하지 않아야 순환이 생기지 않는다.
WEEKDAY_LABELS = ("월", "화", "수", "목", "금", "토", "일")


def activity_date_of(row) -> date | None:
    """[row] 의 논리 운동일. 셋 중 어느 것으로도 알 수 없으면 None.

    None 은 "날짜를 모른다" 이지 "오늘" 이 아니다 — 모르는 행을 오늘로 떨어뜨리면
    기간 집계가 조용히 부풀어, 아무 운동도 하지 않은 회원에게 최근 기록이 있는
    것처럼 보인다.
    """
    from_labels = _date_from_week_labels(
        getattr(row, "week_start", None), getattr(row, "day_label", None)
    )
    if from_labels is not None:
        return from_labels
    completed_at = getattr(row, "completed_at", None)
    if isinstance(completed_at, datetime):
        return clock.to_seoul(completed_at).date()
    created_at = getattr(row, "created_at", None)
    if isinstance(created_at, datetime):
        return clock.to_seoul(created_at).date()
    return None


def _date_from_week_labels(week_start, day_label) -> date | None:
    """`주 시작 + 요일 라벨` → 날짜. 둘 중 하나라도 깨졌으면 None."""
    if not isinstance(week_start, str) or not isinstance(day_label, str):
        return None
    try:
        monday = date.fromisoformat(week_start)
        offset = WEEKDAY_LABELS.index(day_label)
    except (ValueError, IndexError):
        return None
    return monday + timedelta(days=offset)


def recent_window(days: int, *, today: date | None = None) -> tuple[date, date]:
    """최근 [days] 일의 (시작, 끝). **오늘을 포함해 [days] 개 날짜**다.

    `오늘 - (days - 1)` 부터라는 뜻이다. 예전에는 `오늘 - days` 부터 세어 14일이
    실제로는 15개 날짜였다 — 경계가 하루 헐거우면 "최근 2주" 가 화면·서버마다
    다른 구간을 가리킨다.
    """
    end = today if today is not None else clock.today()
    return end - timedelta(days=max(days, 1) - 1), end


def in_window(day: date | None, window: tuple[date, date]) -> bool:
    """[day] 가 구간 안(양 끝 포함)인가. 날짜를 모르는 행은 밖으로 둔다."""
    if day is None:
        return False
    start, end = window
    return start <= day <= end


def week_starts_covering(start: date, end: date) -> list[str]:
    """[start, end] 에 걸치는 주의 월요일들(`YYYY-MM-DD`).

    조회를 좁히는 데 쓴다 — 전체 테이블을 읽으면 35주치 데모에서 245일이 매번
    끌려온다. 다만 이 목록만으로 거르지는 않는다: `week_start` 가 깨진 옛 행은
    여기에 걸리지 않으므로, 호출부가 `completed_at`·`created_at` 조건을 함께
    걸어 넓게 가져온 뒤 [activity_date_of] 로 최종 판정한다.
    """
    first = monday_of(start)
    last = monday_of(end)
    out: list[str] = []
    cursor = first
    while cursor <= last:
        out.append(cursor.isoformat())
        cursor += timedelta(days=7)
    return out


def start_of_day(day: date) -> datetime:
    """KST 자정(tz-aware). `completed_at`·`created_at` 비교의 하한이다."""
    return datetime.combine(day, time.min, tzinfo=clock.SEOUL)


def noon(day: date) -> datetime:
    """그날 KST 정오. 날짜만 아는 기록에 시각을 채울 때 쓴다.

    자정이 아니라 정오인 이유는 타임존이 어긋난 채 읽혀도 날짜가 넘어가지 않기
    때문이다 — UTC 로 읽으면 자정은 전날이 된다.
    """
    return datetime.combine(day, time(12, 0), tzinfo=clock.SEOUL)
