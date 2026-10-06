"""AI 루틴 C안 — 지난 PT 흐름상 **이번 차례** 프로그램(#3282).

A·B안이 회원 분석으로 새로 짜는 안이라면, C안은 트레이너가 지금까지 PT 에서
돌려 온 프로그램 가운데 이번에 할 차례인 것을 골라 최근 상태에 맞게 고친 안이다.

* **차례는 규칙이 정한다.** 최근 완료한 PT 의 프로그램을 운동 구성으로 묶는다.
  두 번 이상 반복된 프로그램이 둘 이상이면 순환으로 보고 그중 가장 오래 안 한
  것을 이번 차례로 본다. PT 가 늘 분할로 진행되지는 않는다 — 전신·서킷처럼
  반복이 보이지 않으면 가장 최근 프로그램을 이어 가며 고친다. 기록이 없으면
  전신 기본 프로그램으로 시작한다 — C안은 늘 있다.
* **고치는 것은 AI 가 기본이다.** 기준 프로그램과 회원 분석을 함께 넘겨 통증
  부위·완료율·생성 조건에 맞게 고치게 한다. AI 가 실패하거나 데모일 때는 아래
  [rule_plan_c] 가 같은 기준으로 규칙만큼 고친다.

판단은 한국어 운동 이름으로 하고(`routine_ai` 와 같은 이유, #2301), 문장만 요청
언어로 쓴다. 트레이너가 적은 운동 이름은 옮기지 않는다.

트레이너 웹 데모(`demo_next_pt.dart`)도 같은 규칙이다 — 바꾸면 함께 바꾼다.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from app.core.locale import Locale, localized
from app.services import routine_ai

#: 차례를 볼 최근 완료 PT 수. 주 1~2회 PT 면 한두 달이다.
NEXT_PT_LOOKBACK = 8

#: 기록이 없을 때 시작하는 전신 기본 프로그램(#3282). PT 가 늘 분할로 진행되지
#: 않는다 — 주 1~2회·초보·체중 관리 회원은 전신이 가장 흔해, 특정 부위 분할의
#: 첫날보다 전신이 무난한 출발점이다. (이름, 유형, 세트, 횟수, 분).
_START_PROGRAM: tuple[tuple[str, str, int | None, int | None, int], ...] = (
    ("스쿼트", "근력", 3, 12, 8),
    ("푸시업", "근력", 3, 10, 8),
    ("밴드 로우", "근력", 3, 12, 8),
    ("플랭크", "근력", 3, None, 6),
    ("저강도 걷기", "유산소", None, None, 10),
)

_EN_START_NAMES = {"푸시업": "Push-up", "밴드 로우": "Band row"}

#: 근력 한 세트를 분으로 어림한다 — 기록에 시간이 없는 근력 줄의 길이.
_MINUTES_PER_SET = 3

#: 완료율에 따라 근력 세트를 한 칸 옮기는 문턱. A·B 의 상향 판단(60%)보다
#: 높게 둔다 — C안은 이미 트레이너가 짠 양이라 쉽게 올리지 않는다.
_STEP_UP_RATE = 80
_STEP_DOWN_RATE = 50
_MIN_SETS = 2
_MAX_SETS = 6


@dataclass(frozen=True)
class PtItem:
    """지난 PT 프로그램의 운동 한 줄."""

    name: str
    type: str
    sets: int | None = None
    reps: int | None = None
    weight: float | None = None
    minutes: int | None = None


@dataclass(frozen=True)
class PtSession:
    """완료한 PT 한 회의 날짜와 프로그램."""

    day: date
    items: tuple[PtItem, ...]


@dataclass(frozen=True)
class NextPt:
    """이번 차례 판단 결과 — C안의 기준 프로그램과 근거."""

    #: `rotation`(기록에서 고름) · `continue`(한 가지만 반복) · `start`(기록 없음).
    kind: str
    label: str
    items: tuple[PtItem, ...]
    #: 카드·판단 결과에 그대로 보이는 차례 근거.
    basis: str
    #: 차례를 본 완료 PT 수.
    session_count: int = 0
    #: 고른 프로그램을 마지막으로 한 날로부터 지난 날 수. 기록이 없으면 None.
    days_ago: int | None = None


def _start_name(name: str, locale: Locale) -> str:
    if locale == "en" and name in _EN_START_NAMES:
        return _EN_START_NAMES[name]
    return routine_ai.exercise_name(name, locale)


def _signature(items: tuple[PtItem, ...]) -> frozenset[str]:
    """프로그램의 정체 — 근력 운동 이름 묶음, 근력이 없으면 전체 이름.

    마무리 유산소·스트레칭은 날마다 비슷해 프로그램을 가르지 못한다.
    """
    strength = frozenset(i.name for i in items if i.type == "근력")
    return strength or frozenset(i.name for i in items)


def _label(items: tuple[PtItem, ...]) -> str:
    strength = [i.name for i in items if i.type == "근력"] or [i.name for i in items]
    return " · ".join(strength[:2])


def choose_next(
    sessions: list[PtSession], *, today: date, locale: Locale = "ko"
) -> NextPt:
    """[sessions](최신 먼저) 에서 이번 차례를 고른다. 비어 있으면 전신 기본으로 시작."""
    sessions = [s for s in sessions if s.items][:NEXT_PT_LOOKBACK]
    if not sessions:
        items = tuple(
            PtItem(
                name=_start_name(name, locale),
                type=type_,
                sets=sets,
                reps=reps,
                minutes=minutes,
            )
            for name, type_, sets, reps, minutes in _START_PROGRAM
        )
        return NextPt(
            kind="start",
            label=localized("전신 기본", "Full-body starter", locale),
            items=items,
            basis=localized(
                "PT 기록이 아직 없어 전신 기본 프로그램으로 시작해요",
                "No PT records yet — starting with a full-body basic program",
                locale,
            ),
        )

    # 프로그램마다 마지막으로 한 회차(가장 최근 쪽 위치)와 한 횟수를 센다.
    last_seen: dict[frozenset[str], int] = {}
    times: dict[frozenset[str], int] = {}
    for index, session in enumerate(sessions):
        signature = _signature(session.items)
        last_seen.setdefault(signature, index)
        times[signature] = times.get(signature, 0) + 1
    count = len(sessions)

    # 두 번 이상 한 프로그램이 둘 이상이어야 순환이다. 매번 구성이 다른
    # 전신·서킷 PT 에서 가장 오래된 회차를 "차례" 로 고르면 근거 없는 차례가 된다.
    repeated = [sig for sig, n in times.items() if n >= 2]
    if len(repeated) >= 2:
        signature = max(repeated, key=lambda sig: last_seen[sig])
        chosen = sessions[last_seen[signature]]
        label = _label(chosen.items)
        days = (today - chosen.day).days
        return NextPt(
            kind="rotation",
            label=label,
            items=chosen.items,
            basis=localized(
                f"최근 {count}회에서 번갈아 한 프로그램 {len(repeated)}가지 중 "
                f"'{label}'을 가장 오래 안 했어요({days}일 전) → 이번 차례",
                f"Of the {len(repeated)} programs alternated over the last {count} "
                f"sessions, '{label}' was done longest ago ({days} days) → up next",
                locale,
            ),
            session_count=count,
            days_ago=days,
        )

    # 순환이 보이지 않으면 가장 최근 PT 를 이어 가며 고친다.
    latest = sessions[0]
    label = _label(latest.items)
    if count == 1:
        basis = localized(
            f"지난 PT 1회의 프로그램({label})을 이어 가요",
            f"Continuing the program from the last PT ({label})",
            locale,
        )
    elif len(last_seen) == 1:
        basis = localized(
            f"최근 {count}회 같은 프로그램({label})을 이어 와서 같은 흐름을 유지해요",
            f"The last {count} sessions repeated the same program ({label}) "
            "— keeping that flow",
            locale,
        )
    else:
        basis = localized(
            f"최근 {count}회에서 번갈아 하는 프로그램이 보이지 않아 "
            f"지난 PT({label})를 이어 가요",
            f"No alternating programs over the last {count} sessions — "
            f"continuing the last PT ({label})",
            locale,
        )
    return NextPt(
        kind="continue",
        label=label,
        items=latest.items,
        basis=basis,
        session_count=count,
        days_ago=(today - latest.day).days,
    )


def _item_minutes(item: PtItem) -> int:
    if item.minutes:
        return item.minutes
    if item.type == "근력":
        return (item.sets or 3) * _MINUTES_PER_SET
    return 5


def _caution_part(name: str, cautions: list[str]) -> str | None:
    """[name] 이 부담을 주는 주의 부위. 없으면 None."""
    for part in cautions:
        if routine_ai._avoids(name, [part]):
            return part
    return None


def _fit_minutes(minutes: list[int], cap: int) -> list[int]:
    """합이 [cap] 을 넘으면 비례로 줄인다. 각 줄 1분 이상, 합은 정확히 [cap]."""
    total = sum(minutes)
    if total <= cap:
        return minutes
    scaled = [max(1, (m * cap) // total) for m in minutes]
    # 내림으로 남은 분은 긴 줄부터 하나씩 돌려준다.
    order = sorted(range(len(minutes)), key=lambda i: -minutes[i])
    i = 0
    while sum(scaled) < cap:
        scaled[order[i % len(order)]] += 1
        i += 1
    while sum(scaled) > cap:
        j = order[i % len(order)]
        if scaled[j] > 1:
            scaled[j] -= 1
        i += 1
    return scaled


def rule_plan_c(
    next_pt: NextPt,
    *,
    available_minutes: int,
    intensity_preference: str,
    avg_completion_rate: int,
    cautions: list[str],
    escalate: bool,
    locale: Locale = "ko",
) -> dict:
    """[next_pt] 의 기준 프로그램을 규칙만큼 고친 C안(AI 실패·데모용).

    * 주의 부위에 부담이 큰 운동은 저충격 대안으로 바꾼다(A·B 와 같은 표).
    * 완료율이 높으면 근력 세트를 한 칸 올리고, 낮으면 내린다. 판단이 어려운
      상태(`escalate`)면 올리지 않는다.
    * 생성 조건의 최대 시간을 넘으면 운동별 시간을 비례로 줄인다.
    """
    changes: list[str] = []
    names: list[str] = []
    rows: list[dict] = []
    for item in next_pt.items:
        part = _caution_part(item.name, cautions)
        if part is not None:
            alt_name, alt_type = (
                routine_ai._STRETCH if item.type == "근력" else routine_ai._CARDIO_EASY
            )
            alt = routine_ai.exercise_name(alt_name, locale)
            if alt in names:
                alt_name, alt_type = routine_ai._CARDIO_EASY
                alt = routine_ai.exercise_name(alt_name, locale)
            changes.append(
                localized(
                    f"{item.name} → {alt}({part})",
                    f"{item.name} → {alt} ({routine_ai._EN_CAUTION_PARTS.get(part, part)})",
                    locale,
                )
            )
            names.append(alt)
            rows.append({"name": alt, "type": alt_type, "minutes": _item_minutes(item)})
            continue
        row: dict = {"name": item.name, "type": item.type, "minutes": _item_minutes(item)}
        if item.type == "근력":
            if item.sets:
                row["sets"] = item.sets
            if item.reps:
                row["reps"] = item.reps
            if item.weight:
                row["weight"] = item.weight
        names.append(item.name)
        rows.append(row)

    strength = [r for r in rows if r["type"] == "근력" and r.get("sets")]
    if strength and avg_completion_rate >= _STEP_UP_RATE and not escalate:
        moved = [r for r in strength if r["sets"] < _MAX_SETS]
        for r in moved:
            r["sets"] += 1
        if moved:
            changes.append(
                localized(
                    f"근력 세트 +1(완료율 {avg_completion_rate}%)",
                    f"Strength sets +1 ({avg_completion_rate}% completion)",
                    locale,
                )
            )
    elif strength and avg_completion_rate < _STEP_DOWN_RATE:
        moved = [r for r in strength if r["sets"] > _MIN_SETS]
        for r in moved:
            r["sets"] -= 1
        if moved:
            changes.append(
                localized(
                    f"근력 세트 -1(완료율 {avg_completion_rate}%)",
                    f"Strength sets −1 ({avg_completion_rate}% completion)",
                    locale,
                )
            )

    before = sum(r["minutes"] for r in rows)
    fitted = _fit_minutes([r["minutes"] for r in rows], available_minutes)
    for r, m in zip(rows, fitted):
        r["minutes"] = m
    after = sum(fitted)
    if after < before:
        changes.append(
            localized(
                f"총 {before}분 → {after}분(최대 {available_minutes}분 조건)",
                f"Total {before} → {after} min (up to {available_minutes} min)",
                locale,
            )
        )

    intensity = "보통" if escalate else routine_ai._B_LABEL.get(intensity_preference, "보통")
    # 차례 근거(`basis`)와 바꾼 점(`changes`)은 카드에 따로 서므로 되풀이하지
    # 않는다 — 규칙형이 무엇을 기준으로 고쳤는지만 짧게 적는다.
    rationale = (
        localized(
            "지난 PT 프로그램을 기준으로 주의 부위·완료율·시간 조건만 반영했어요.",
            "Based on the past PT program, adjusted only for cautions, "
            "completion and the time limit.",
            locale,
        )
        if changes
        else localized(
            "지난 PT 프로그램을 그대로 이어 가요.",
            "Continues the past PT program as is.",
            locale,
        )
    )
    return {
        "key": "C",
        "label": next_pt.label[:50],
        "total_minutes": after,
        "intensity": intensity,
        "exercises": rows,
        "reason": localized(
            "지난 PT 흐름상 이번 차례인 프로그램",
            "The program that comes next in the recent PT flow",
            locale,
        ),
        "rationale": routine_ai._clip_rationale(rationale),
        "basis": next_pt.basis,
        "changes": changes,
    }


def finding(next_pt: NextPt, locale: Locale = "ko") -> dict:
    """판단 결과(#3280)에 싣는 차례 한 줄."""
    if next_pt.kind == "start":
        return {
            "kind": "rotation",
            "finding": localized("PT 기록 없음", "No PT records", locale),
            "source": localized("PT 기록", "PT records", locale),
            "action": localized(
                "C안은 전신 기본 프로그램으로 시작",
                "Plan C starts with a full-body basic program",
                locale,
            ),
        }
    source = localized(
        f"PT 기록 · 최근 {next_pt.session_count}회",
        f"PT records · last {next_pt.session_count} sessions",
        locale,
    )
    if next_pt.kind == "continue":
        text = localized(
            f"이어 갈 지난 PT: {next_pt.label}",
            f"Last PT to continue: {next_pt.label}",
            locale,
        )
    else:
        text = localized(
            f"가장 오래 안 한 프로그램: {next_pt.label}({next_pt.days_ago}일 전)",
            f"Done longest ago: {next_pt.label} ({next_pt.days_ago} days)",
            locale,
        )
    return {
        "kind": "rotation",
        "finding": text[:120],
        "source": source,
        "action": localized(
            "C안: 이번 차례 프로그램을 최근 상태에 맞게 조정",
            "Plan C: adjusts this program to the latest condition",
            locale,
        ),
    }
