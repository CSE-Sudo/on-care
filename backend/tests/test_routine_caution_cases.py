"""루틴 주의 규칙 공유 표·사례 — 서버 쪽. (#2906)

서버 규칙형 A/B(`routine_ai`)와 트레이너 웹 데모(`demo_routine_rules.dart`)가
**같은 파일**(`shared/oncare_rules/vectors/routine_caution_cases.json`)을 읽어
같은 표와 같은 판단을 갖는지 본다. 표나 판단을 바꾸면
`scripts/gen_routine_caution_cases.py` 를 다시 돌려 파일을 고친다.

DB 없이 돈다.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location(
    "gen_routine_caution_cases",
    _ROOT / "backend/scripts/gen_routine_caution_cases.py",
)
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)
_FILE = json.loads(gen.OUT.read_text(encoding="utf-8"))
_CASES = _FILE["cases"]
svc = gen.svc


def test_the_shared_file_is_up_to_date() -> None:
    """표와 사례가 서버와 같다 — 서버 표를 바꾸고 파일을 다시 만들지 않으면 깨진다."""
    assert _FILE == json.loads(json.dumps(gen.build(), ensure_ascii=False))


@pytest.mark.parametrize("case", _CASES["detect"])
def test_detection_matches_the_shared_cases(case: dict) -> None:
    assert svc.cautions_in(case["conditions"], case["messages"]) == case["cautions"]
    assert (
        svc.needs_professional_check(case["conditions"], case["messages"])
        is case["needs_professional_check"]
    )


@pytest.mark.parametrize("case", _CASES["avoids"])
def test_avoids_matches_the_shared_cases(case: dict) -> None:
    assert svc._avoids(case["name"], case["cautions"]) is case["avoids"]


@pytest.mark.parametrize("case", _CASES["safe_parts"])
def test_safe_parts_matches_the_shared_cases(case: dict) -> None:
    parts = [tuple(p) for p in case["parts"]]
    assert [list(p) for p in svc._safe_parts(parts, case["cautions"])] == case["result"]


@pytest.mark.parametrize("case", _CASES["guess_type"])
def test_guess_type_matches_the_shared_cases(case: dict) -> None:
    assert svc._guess_type(case["name"]) == case["type"]


@pytest.mark.parametrize("case", _CASES["caution_suffix"])
def test_caution_suffix_matches_the_shared_cases(case: dict) -> None:
    for locale in ("ko", "en"):
        assert (
            svc._caution_suffix(case["cautions"], case["escalate"], locale)
            == case[locale]
        )


def test_cases_touch_every_caution_part() -> None:
    """사례가 표의 모든 부위를 한 번은 찾아낸다 — 부위를 더하면 사례도 더한다."""
    found = {part for c in _CASES["detect"] for part in c["cautions"]}
    assert found == {rule["part"] for rule in _FILE["tables"]["caution_rules"]}


def test_running_spelled_runeng_is_avoided_for_knee_caution() -> None:
    """트레이너가 `런닝` 이라고 적어도 AI 개인운동이 달리기 계열을 뺀다(#3215)."""
    plan_a, plan_b = svc.rule_based_plans(
        goal="체력 향상",
        sodium_today_mg=1500,
        avg_completion_rate=80,
        available_minutes=40,
        intensity_preference="high",
        trainer_note="",
        frequent_exercises=["런닝 30분", "플랭크"],
        conditions="무릎 통증으로 런닝 자제",
    )
    names = [item["name"] for plan in (plan_a, plan_b) for item in plan["exercises"]]
    assert names
    assert not any(token in name for name in names for token in ("런닝", "러닝", "달리기"))
