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
