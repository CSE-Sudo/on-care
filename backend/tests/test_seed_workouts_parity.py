"""트레이너 웹 데모와 실서버 시드가 같은 운동 표를 쓰는지 (#3003). DB 없이 돈다.

두 시드가 각자 표를 들고 있어 한쪽만 고치면 같은 회원의 같은 날을 두 환경이 다른
운동으로 말한다. 데모 표(`seed_clients.dart` 의 `aiRoutine`, `seed_workouts.dart`)를
읽어 백엔드 표(`app/db/seed_workouts.py`)와 견준다.
"""
from __future__ import annotations

import re
from pathlib import Path

from app.db import seed_workouts

_STORAGE = (
    Path(__file__).resolve().parents[2]
    / "frontend" / "flutter_trainer" / "lib" / "core" / "storage"
)

_ROUTINE_RE = re.compile(
    r"_Routine\(\s*'([^']+)',\s*(\d+),\s*'([^']+)',\s*'([^']*)'((?:,\s*\w+:\s*[^,)]+)*)\s*,?\s*\)"
)
_NAMED_RE = re.compile(r"(\w+):\s*('?[^,')]+'?)")


def _demo_routines() -> dict[int, list[tuple]]:
    text = (_STORAGE / "seed_clients.dart").read_text(encoding="utf-8")
    out: dict[int, list[tuple]] = {}
    for block in text.split("\n  _Client(\n")[1:]:
        number = int(re.search(r"^    id: (\d+),", block, re.M).group(1))
        start = block.find("aiRoutine: <_Routine>[")
        if start < 0:
            continue
        end = block.index("\n    ],", start)
        rows = []
        for m in _ROUTINE_RE.finditer(block[start:end]):
            named = {k: v.strip("'") for k, v in _NAMED_RE.findall(m.group(5) or "")}
            rows.append((
                m.group(1),
                int(m.group(2)),
                m.group(3),
                int(named.get("sets", 0)),
                int(named.get("reps", 0)),
                int(named.get("holdSeconds", 0)),
                float(named.get("weight", 0)),
                named.get("intensity", "moderate"),
            ))
        out[number] = rows
    return out


def test_member_routines_match_the_demo():
    demo = _demo_routines()
    for member_id, number in seed_workouts.MEMBER_NO.items():
        server = [
            (
                r.name, r.minutes, r.type, r.sets or 0, r.reps or 0,
                r.hold_seconds or 0, float(r.weight or 0), r.intensity,
            )
            for r in seed_workouts.ROUTINES[member_id]
        ]
        assert demo.get(number) == server, member_id


def test_member_logs_and_pt_programs_match_the_demo():
    text = (_STORAGE / "seed_workouts.dart").read_text(encoding="utf-8")
    logs = text[text.index("_memberLogs ="):text.index("_ptPrograms =")]
    for member_id, entries in seed_workouts.MEMBER_LOGS.items():
        number = seed_workouts.MEMBER_NO[member_id]
        assert f"      {number}: <(int, Map<String, Object?>)>[" in logs, member_id
        for weekday, exercise in entries:
            assert re.search(
                rf"\(\s*{weekday},\s*<String, Object\?>\{{\s*'name': '{exercise.name}',"
                rf"\s*'type': '{exercise.type}',\s*'minutes': {exercise.minutes},"
                rf"\s*'intensity': '{exercise.intensity}',",
                logs,
            ), (member_id, exercise.name)
    programs = text[text.index("_ptPrograms ="):]
    for member_id, program in seed_workouts.PT_PROGRAMS.items():
        number = seed_workouts.MEMBER_NO[member_id]
        block = programs[programs.index(f"      {number}: <Map<String, Object?>>["):]
        block = block[:block.index("\n      ],")]
        names = re.findall(r"'name': '([^']+)'", block)
        assert names == [e.name for e in program], member_id
        for e in program:
            assert re.search(
                rf"'name': '{e.name}',\s*'type': '{e.type}',\s*'minutes': {e.minutes},",
                block,
            ), (member_id, e.name)


def test_performed_off_matches_the_demo():
    """처방과 다른 강도로 한 날(#3263)의 회원·운동·강도가 데모 `_performedOff` 와 같다."""
    text = (_STORAGE / "seed_workouts.dart").read_text(encoding="utf-8")
    block = text[text.index("const Map<int, (int, String)> _performedOff"):]
    block = block[:block.index("\n};")]
    demo = {
        int(m.group(1)): (int(m.group(2)), m.group(3))
        for m in re.finditer(r"^\s*(\d+): \((\d+), '(\w+)'\),", block, re.M)
    }
    server = {
        seed_workouts.MEMBER_NO[member_id]: off
        for member_id, off in seed_workouts.PERFORMED_OFF.items()
    }
    assert demo == server
    assert server, "처방과 다르게 한 날이 하나도 없으면 `수행 …` 태그를 보일 날이 없다"
    for member_id, (order, intensity) in seed_workouts.PERFORMED_OFF.items():
        # 처방과 같은 강도면 태그가 서지 않는다.
        assert seed_workouts.ROUTINES[member_id][order].intensity != intensity


def test_performed_off_day_is_the_latest_day_with_that_routine():
    from datetime import date

    done = {
        date(2026, 8, 18): 3,
        date(2026, 8, 19): 3,
        # 스쿼트(둘째)까지 못 한 날은 고르지 않는다.
        date(2026, 8, 20): 1,
    }
    off_day = seed_workouts.performed_off_day("user-jisu", done)
    assert off_day == date(2026, 8, 19)
    assert seed_workouts.performed_intensity(
        "user-jisu", 1, date(2026, 8, 19), off_day, "moderate"
    ) == "high"
    # 같은 날 다른 운동, 다른 날 같은 운동은 처방 그대로다.
    assert seed_workouts.performed_intensity(
        "user-jisu", 0, date(2026, 8, 19), off_day, "high"
    ) == "high"
    assert seed_workouts.performed_intensity(
        "user-jisu", 1, date(2026, 8, 18), off_day, "moderate"
    ) == "moderate"
    # 표에 없는 회원은 늘 처방 그대로다.
    assert seed_workouts.performed_off_day("user-sungho", done) is None
