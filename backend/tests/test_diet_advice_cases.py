"""식단 AI 맞춤 조언 공유 사례 — 서버 쪽. (#2255)

서버와 데모(`core/demo/diet_advice.dart`)·앱 한국어 ARB 가 **같은 사례 파일**을 읽어 같은
규칙 한 줄·다음 할 일·한국어 문장을 내는지 본다. 규칙이나 문장을 바꾸면
`scripts/gen_diet_advice_cases.py` 를 다시 돌려 파일을 고친다.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

from app.services import diet_advice_copy as copy

_ROOT = Path(__file__).resolve().parents[2]
_CASES = json.loads(
    (_ROOT / "frontend/flutter/test/core/demo/diet_advice_cases.json").read_text(encoding="utf-8")
)

_spec = importlib.util.spec_from_file_location(
    "gen_diet_advice_cases", _ROOT / "backend/scripts/gen_diet_advice_cases.py"
)
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)


@pytest.mark.parametrize("case", _CASES["cases"], ids=[c["name"] for c in _CASES["cases"]])
def test_server_matches_the_shared_cases(case):
    assert gen.RUN[case["period"]](case) == case["expected"]


@pytest.mark.parametrize("case", _CASES["cases"], ids=[c["name"] for c in _CASES["cases"]])
def test_cases_fit_the_card(case):
    expected = case["expected"]
    analysis = copy.Line(key=expected["analysis"]["key"], params=expected["analysis"]["params"])
    action = expected["action"]
    action_line = copy.Line(key=action["key"], params=action["params"]) if action else None
    assert len(copy.message(analysis, action_line)) <= 45


def test_demo_plan_is_the_servers_rules_plan():
    """데모의 고정 메뉴 리스트는 서버가 기록 없는 회원에게 만드는 카탈로그 리스트다."""
    assert _CASES["demo_plan"] == gen.DEMO_PLAN


def test_renderings_cover_every_key_and_match_the_server():
    keys = {row["key"] for row in _CASES["renderings"]}
    assert keys == set(copy.KEYS)
    for row in _CASES["renderings"]:
        assert copy.line(row["key"], **row["params"]).text == row["text"]
