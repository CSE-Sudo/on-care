"""추천 개인운동 기반 운동 AI 맞춤 조언. (#2162)

운동 조언(`exercise_service.period_coach_message`)은 직접 기록한 운동만 보고
말해 왔다. 회원이 가장 먼저 알고 싶은 것은 "추천 운동 중 뭘 먼저 할까",
"뭐가 자꾸 빠지나" 인데, 그 재료는 트레이너(담당이 없으면 AI)가 걸어 둔 추천
목록과 날짜별 완료에 있다. 이 모듈은 그 둘로 기간마다 **분석 + 할 일** 한 마디를
만든다.

- 오늘: 아직 안 한 것 중 다음 운동과 그 뒤 순서. 다 했으면 칭찬.
- 이번 주: 한 추천 운동이 한 유형에 쏠렸는지. 고르게 했으면 칭찬. 이번 주가
  막 시작한 월·화에는 지난주를 돌아본다.
- 전체: 지금 목록이 걸린 동안 자주 빠진 부위(또는 운동). 잘 지켰으면 칭찬.

수치(완료율·유형 비율·빠진 횟수)는 규칙으로 세고, 문장은 그 값만 근거로 쓴다.
걸려 있는 추천이 없으면 None — 부르는 쪽이 직접 기록 기준 조언으로 돌아간다.

**운동은 이름으로 센다.** AI 추천은 날마다 새 줄로 만들어져 id 가 매일 다르다 —
id 로 세면 같은 운동이 날마다 다른 운동이 된다.

**한 문장 반(45자)을 넘기지 않는다**(#1574). 운동 이름은 트레이너가 자유롭게
적으므로, 문장마다 짧아지는 후보를 차례로 두고 한도 안에 드는 첫 문장을 쓴다.
마지막 후보는 이름 없이 수만 말해 늘 한도 안이다.

데모(`frontend/flutter/lib/core/demo/period_advice.dart`)가 같은 규칙을 같은
문장으로 재현한다. 한쪽을 고치면 다른 쪽도 함께 고친다 — 두 쪽이 같은지는
공유 사례(`frontend/flutter/test/core/demo/routine_advice_cases.json`)로 본다.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from typing import Protocol, Sequence

from app.services import exercise_types, period_window

#: 조언 한 마디의 상한 — 회원 앱·트레이너웹 카드 폭에 맞춘 값이다(#1574).
ADVICE_MAX_LEN = 45

#: 한 유형이 이 비율 이상이면 쏠렸다고 본다. 직접 기록 기준 조언과 같은 값이다.
_SKEW_SHARE = 0.8
#: 이 완료율 이상이면 칭찬한다.
_PRAISE_RATE = 0.8
#: 이 비율 이상, 이 횟수 이상 빠진 부위·운동만 "자주 빠졌다" 고 말한다.
_MISS_RATE = 0.5
_MISS_MIN = 2
#: 그리고 가장 덜 빠진 묶음보다 이만큼 더 빠져야 한다. 모두가 똑같이 빠졌으면
#: 한 부위를 짚는 것은 사실이 아니다 — 그때는 전체 완료율을 말한다.
_MISS_GAP = 0.2
#: 전체 조언이 빠진 운동을 말하려면 지금 목록이 이만큼(일) 걸려 있어야 한다.
_ALL_MIN_DAYS = 7


# --- 부위 판정 ----------------------------------------------------------------
#
# 추천 운동에는 부위 칸이 없다. 이름으로 판정한다 — 진단이 아니라 "어디를 쓰는
# 운동이 빠지나" 를 묶는 용도다. 부위 이름이 이름에 직접 적혀 있으면(`하체
# 스트레칭`) 그것을 먼저 믿고, 없을 때 동작 이름으로 짐작한다. 둘 다 없으면 None
# — 조언은 부위 대신 운동 이름을 그대로 말한다.

LOWER = "하체"
UPPER = "상체"
CORE = "코어"
FULL = "전신"

#: 이름에 직접 적힌 부위.
_PART_WORDS: tuple[tuple[str, tuple[str, ...]], ...] = (
    (FULL, ("전신",)),
    (LOWER, ("하체", "다리", "허벅지", "엉덩이", "둔근", "종아리")),
    (UPPER, ("상체", "어깨", "가슴", "팔")),
    (CORE, ("코어", "복근", "복부", "허리")),
)

#: 동작 이름으로 짐작하는 부위. `레그 프레스`·`레그 컬` 이 상체의 `프레스`·`컬`
#: 보다 먼저 잡히도록 하체를 앞에 둔다.
_PART_MOVES: tuple[tuple[str, tuple[str, ...]], ...] = (
    (FULL, ("버피", "burpee")),
    (
        LOWER,
        (
            "스쿼트", "런지", "브릿지", "레그", "카프", "데드리프트", "스텝업", "힙",
            "squat", "lunge", "bridge", "leg", "deadlift",
        ),
    ),
    (CORE, ("플랭크", "크런치", "윗몸", "버드독", "데드버그", "plank", "crunch", "core")),
    (
        UPPER,
        (
            "푸시업", "팔굽혀", "풀업", "턱걸이", "로우", "벤치", "프레스", "숄더",
            "풀다운", "컬", "딥스", "레이즈",
            "push", "pull", "row", "bench", "press", "shoulder", "curl",
        ),
    ),
)


def body_part_of(name: str) -> str | None:
    """운동 이름 → 부위(하체·상체·코어·전신). 모르면 None."""
    text = name.lower()
    for rules in (_PART_WORDS, _PART_MOVES):
        for part, keywords in rules:
            if any(k in text for k in keywords):
                return part
    return None


# --- 입력 모양 ----------------------------------------------------------------
#
# `trainer_service.RoutineDay` 를 그대로 받는다. 그 모듈이 이 서비스 계층을 읽으므로
# 여기서 들여오면 돌아 들어온다 — 필요한 필드만 약속으로 적는다.


class RoutineItemLike(Protocol):
    name: str
    type: str
    minutes: int
    done: bool
    completed_minutes: int | None


class RoutineDayLike(Protocol):
    date: date
    routines: Sequence[RoutineItemLike]


def fetch_start(period: str, today: date) -> date:
    """조언이 읽을 추천 목록의 시작일. 이번 주는 지난주까지 읽는다(월·화 회고)."""
    if period == period_window.PERIOD_TODAY:
        return today
    if period == period_window.PERIOD_WEEK:
        return today - timedelta(days=today.weekday() + 7)
    return today - timedelta(days=period_window.ALL_PERIOD_DAYS - 1)


# --- 문장 도구 ----------------------------------------------------------------


def _has_final_consonant(word: str) -> bool | None:
    """마지막 글자에 받침이 있나. 한글로 끝나지 않으면 None."""
    stripped = word.rstrip(" )]}")
    if not stripped:
        return None
    last = ord(stripped[-1])
    if not 0xAC00 <= last <= 0xD7A3:
        return None
    return (last - 0xAC00) % 28 != 0


def _josa(word: str, with_final: str, without_final: str) -> str:
    """받침에 맞는 조사를 붙인다. 판단할 수 없으면 `이(가)` 꼴로 둘 다 적는다."""
    final = _has_final_consonant(word)
    if final is None:
        return f"{word}{with_final}({without_final})"
    return word + (with_final if final else without_final)


def _first_fit(*candidates: str) -> str:
    """한도 안에 드는 첫 문장. 마지막 후보는 늘 짧게 둔다."""
    for text in candidates:
        if len(text) <= ADVICE_MAX_LEN:
            return text
    return candidates[-1]


def _type_code(item: RoutineItemLike) -> str:
    return exercise_types.normalize(item.type)


def _type_label(code: str) -> str:
    return exercise_types.label_for(code)


#: 유형을 고를 때의 차례 — 직접 기록 기준 조언의 `main_type` 과 같다.
_TYPE_ORDER = (
    exercise_types.CARDIO,
    exercise_types.STRENGTH,
    exercise_types.STRETCHING,
    exercise_types.OTHER,
)


@dataclass(frozen=True)
class _Tally:
    """셀 수 있는 추천 — 지난 날의 것 전부와 오늘 이미 한 것."""

    assigned: list[RoutineItemLike]
    done: list[RoutineItemLike]


def _tally(days: Sequence[RoutineDayLike], today: date, names: set[str] | None = None) -> _Tally:
    """오늘 아직 안 한 것은 빠진 것이 아니다 — 하루가 끝나지 않았다."""
    assigned: list[RoutineItemLike] = []
    done: list[RoutineItemLike] = []
    for day in days:
        for item in day.routines:
            if names is not None and item.name not in names:
                continue
            if day.date == today and not item.done:
                continue
            assigned.append(item)
            if item.done:
                done.append(item)
    return _Tally(assigned=assigned, done=done)


def _pct(part: float, whole: float) -> int:
    # `round()` 는 .5 를 짝수로 보낸다(12.5 → 12). 데모(Dart `round`)는 올리므로
    # 같은 수를 말하도록 둘 다 .5 를 올린다.
    return int(part * 100 / whole + 0.5) if whole else 0


# --- 기간별 조언 --------------------------------------------------------------


def coach_message(days: Sequence[RoutineDayLike], period: str) -> str | None:
    """추천 목록 기준 조언. 오늘 걸린 추천이 없으면 None. [days] 는 날짜순이고
    마지막 날이 오늘이다(`trainer_service.member_routine_days` 가 그렇게 준다)."""
    if not days or not days[-1].routines:
        return None
    if period == period_window.PERIOD_TODAY:
        return _today(days[-1])
    if period == period_window.PERIOD_WEEK:
        return _week(days)
    return _all(days)


def _today(day: RoutineDayLike) -> str:
    items = list(day.routines)
    pending = [i.name for i in items if not i.done]
    done = [i.name for i in items if i.done]
    if not pending:
        return f"오늘 추천 운동 {len(items)}개를 모두 마쳤어요. 잘했어요!"
    left = f"남은 추천 운동이 {len(pending)}개예요. 목록 순서대로 해 보세요."
    # 남은 것이 하나면 "순서" 가 없다 — 그 하나의 차례라고만 말한다.
    order = " → ".join(pending[:2]) if len(pending) >= 2 else None
    # 한글로 끝나지 않는 이름(`Squat`)에는 조사를 붙일 수 없다 — `Squat을(를)` 로
    # 적지 않고 마친 운동을 말하는 문장을 건너뛴다.
    if done and _has_final_consonant(done[-1]) is not None:
        finished = _josa(done[-1], "을", "를") + " 마쳤어요."
        return _first_fit(
            *((f"{finished} 다음은 {order} 순서로 해 보세요.",) if order else ()),
            f"{finished} 다음은 {pending[0]} 차례예요.",
            *((f"다음은 {order} 순서로 해 보세요.",) if order else ()),
            f"다음은 {pending[0]} 차례예요.",
            left,
        )
    if done:
        return _first_fit(
            *((f"다음은 {order} 순서로 해 보세요.",) if order else ()),
            f"다음은 {pending[0]} 차례예요.",
            left,
        )
    return _first_fit(
        *((f"오늘 추천 운동은 {order} 순서로 시작해 보세요.",) if order else ()),
        f"오늘은 {pending[0]}부터 시작해 보세요.",
        left,
    )


def _week(days: Sequence[RoutineDayLike]) -> str:
    today = days[-1].date
    monday = today - timedelta(days=today.weekday())
    this_week = [d for d in days if d.date >= monday]
    last_week = [d for d in days if monday - timedelta(days=7) <= d.date < monday]
    done_days = sum(1 for d in this_week if any(i.done for i in d.routines))
    # 주 초반(월·화)에 이번 주 한 날이 이틀이 안 되면 할 말이 없다 — 지난주를 돌아본다.
    looking_back = (
        today.weekday() <= 1
        and done_days < 2
        and bool(_tally(last_week, today).assigned)
    )
    tally = _tally(last_week if looking_back else this_week, today)
    when = "지난주" if looking_back else "이번 주"
    # 일요일에는 이번 주에 남은 날이 없다 — 다음 주를 말한다.
    sunday = today.weekday() == 6
    rest = "다음 주엔" if sunday else "남은 날엔"
    keep_going = "다음 주도 이어 가요." if sunday else "남은 날도 이어 가요."
    first_pending = next((i.name for i in days[-1].routines if not i.done), None)

    if not tally.done:
        if looking_back:
            return _first_fit(
                f"지난주엔 추천 운동을 못 했어요. 이번 주는 {first_pending}부터 해 봐요."
                if first_pending
                else "지난주엔 추천 운동을 못 했어요. 이번 주는 하나씩 해 봐요.",
                "지난주엔 추천 운동을 못 했어요. 이번 주는 하나씩 해 봐요.",
            )
        return _first_fit(
            f"이번 주엔 추천 운동을 아직 안 했어요. 오늘 {first_pending}부터 해 볼까요?",
            f"이번 주엔 추천 운동을 아직 안 했어요. {first_pending}부터 해 봐요.",
            "이번 주엔 추천 운동을 아직 안 했어요. 오늘 하나부터 해 봐요.",
        )

    # 유형 쏠림 — 한 추천 운동의 시간으로 센다. 목록에 한 유형만 걸려 있으면
    # 쏠림은 회원이 아니라 목록의 모양이라 짚지 않는다.
    minutes: dict[str, int] = {}
    for item in tally.done:
        code = _type_code(item)
        minutes[code] = minutes.get(code, 0) + (item.completed_minutes or item.minutes or 0)
    total = sum(minutes.values())
    listed_types = {_type_code(i) for i in tally.assigned}
    if total and len(tally.done) >= 2 and len(listed_types) >= 2:
        top = max(_TYPE_ORDER, key=lambda t: (minutes.get(t, 0), -_TYPE_ORDER.index(t)))
        if minutes.get(top, 0) / total >= _SKEW_SHARE:
            missing = _least_done_type(tally, exclude=top)
            share = _pct(minutes[top], total)
            top_label = _josa(_type_label(top), "이", "가")
            missing_label = _type_label(missing)
            # 한 유형만 했으면 "100%" 가 아니라 그 유형만 했다고 말한다.
            if share == 100:
                only = f"{when}엔 {_type_label(top)} 추천 운동만 했어요."
                next_step = "이번 주는" if looking_back else rest
                return _first_fit(f"{only} {next_step} {missing_label}부터 해 보세요.", only)
            if looking_back:
                return _first_fit(
                    f"지난주 추천 운동 중 {top_label} {share}%였어요. "
                    f"이번 주는 {missing_label}부터 해 보세요.",
                    f"지난주 추천 운동은 {top_label} {share}%였어요.",
                )
            return _first_fit(
                f"이번 주 추천 운동 중 {top_label} {share}%예요. "
                f"{rest} {missing_label}부터 해 보세요.",
                f"이번 주 추천 운동은 {top_label} {share}%예요.",
            )

    rate = len(tally.done) / len(tally.assigned)
    if rate >= _PRAISE_RATE:
        how = "고르게" if len({_type_code(i) for i in tally.done}) >= 2 else "꾸준히"
        if looking_back:
            return f"지난주 추천 운동을 {how} 해냈어요. 이번 주도 이어 가요!"
        return f"이번 주 추천 운동을 {how} 해냈어요. 이대로 이어 가요!"
    counts = f"{when} 추천 운동 {len(tally.assigned)}개 중 {len(tally.done)}개를 했어요."
    if looking_back:
        return _first_fit(f"{counts} 이번 주는 더 채워 봐요.", counts)
    if first_pending is None:
        return _first_fit(f"{counts} {keep_going}", counts)
    return _first_fit(
        f"{counts} 오늘 {first_pending}부터 이어 가요.",
        f"{counts} {keep_going}",
        counts,
    )


def _least_done_type(tally: _Tally, exclude: str) -> str:
    """걸려 있던 유형 중 완료율이 가장 낮은 것. 같으면 유산소 → 근력 → … 순."""
    listed: dict[str, int] = {}
    done: dict[str, int] = {}
    for item in tally.assigned:
        code = _type_code(item)
        listed[code] = listed.get(code, 0) + 1
        if item.done:
            done[code] = done.get(code, 0) + 1
    candidates = [t for t in _TYPE_ORDER if t in listed and t != exclude]
    return min(candidates, key=lambda t: (done.get(t, 0) / listed[t], _TYPE_ORDER.index(t)))


def _group_key(item: RoutineItemLike) -> str:
    """자주 빠진 것을 셀 묶음 — 부위, 모르면 운동 이름.

    스트레칭은 부위로 묶지 않는다. `어깨 관절 보호 스트레칭` 이 빠진 것을 "상체
    운동이 자주 빠졌어요" 라고 하면 회원은 상체 근력 운동을 떠올린다.
    """
    if _type_code(item) == exercise_types.STRETCHING:
        return item.name
    return body_part_of(item.name) or item.name


def _all(days: Sequence[RoutineDayLike]) -> str:
    today = days[-1].date
    current = [i.name for i in days[-1].routines]
    names = set(current)
    # 지금 목록이 걸린 동안 — 지금 목록의 운동이 처음 걸린 날부터 센다.
    since = next(d.date for d in days if any(i.name in names for i in d.routines))
    span = (today - since).days + 1
    if span < _ALL_MIN_DAYS:
        return f"추천 목록을 받은 지 {span}일째예요. 일주일 뒤 빠진 운동을 짚어 드릴게요."
    tally = _tally([d for d in days if d.date >= since], today, names)
    if not tally.done:
        # 한 번도 하지 않았으면 모든 묶음이 똑같이 빠져 짚을 곳이 없다 — "0% 해냈어요"
        # 대신 오늘 첫 운동을 권한다. 못 했다고 탓하지 않고 시작을 권한다.
        first_pending = next((i.name for i in days[-1].routines if not i.done), None)
        since_text = f"추천 목록을 받은 지 {span}일째예요."
        return _first_fit(
            *((f"{since_text} 오늘 {first_pending}부터 시작해 볼까요?",) if first_pending else ()),
            f"{since_text} 오늘 하나부터 시작해 봐요.",
        )

    # 부위로 묶는다. 부위를 모르면 운동 이름이 한 묶음이다. 같은 수면 지금 목록에서
    # 앞선 쪽 — 먼저 하도록 짜인 운동이 빠지는 편이 더 먼저 짚을 일이다.
    groups: dict[str, list[int]] = {}
    first_seen: dict[str, int] = {}
    for index, item in enumerate(days[-1].routines):
        first_seen.setdefault(_group_key(item), index)
    for item in tally.assigned:
        key = _group_key(item)
        counts = groups.setdefault(key, [0, 0])
        counts[0] += 1
        if item.done:
            counts[1] += 1
    least_missed = min((listed - done) / listed for listed, done in groups.values())
    missed = [
        (key, listed - done, (listed - done) / listed)
        for key, (listed, done) in groups.items()
        if listed - done >= _MISS_MIN
        and (listed - done) / listed >= _MISS_RATE
        and (listed - done) / listed - least_missed >= _MISS_GAP
    ]
    if missed:
        key, _, _ = max(
            missed, key=lambda m: (m[2], m[1], -first_seen.get(m[0], len(current)))
        )
        if key in (LOWER, UPPER, CORE, FULL):
            return _first_fit(
                f"추천 운동 중 {key} 운동이 자주 빠졌어요. {key} 운동을 먼저 해 볼까요?",
                f"{key} 추천 운동이 자주 빠졌어요. 먼저 하는 순서로 바꿔 볼까요?",
            )
        if _has_final_consonant(key) is None:
            return _first_fit(
                f"추천 운동 {key}, 자주 빠졌어요. 다음엔 먼저 해 볼까요?",
                f"{key}, 자주 빠졌어요. 먼저 해 볼까요?",
                "자주 빠진 추천 운동이 있어요. 목록 순서를 바꿔 볼까요?",
            )
        subject = _josa(key, "이", "가")
        return _first_fit(
            f"추천 운동 중 {subject} 자주 빠졌어요. 다음엔 먼저 해 볼까요?",
            f"{subject} 자주 빠졌어요. 먼저 해 볼까요?",
            "자주 빠진 추천 운동이 있어요. 목록 순서를 바꿔 볼까요?",
        )

    rate = len(tally.done) / len(tally.assigned)
    if rate >= _PRAISE_RATE:
        weeks = span // 7
        return f"추천 운동을 {weeks}주째 꾸준히 하고 있어요. 앞으로도 화이팅!"
    pct = _pct(len(tally.done), len(tally.assigned))
    return f"지금 추천 운동의 {pct}%를 했어요. 빠지는 날 없이 이어 가 봐요."
