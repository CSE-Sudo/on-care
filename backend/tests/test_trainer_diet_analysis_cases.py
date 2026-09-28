"""트레이너 웹 `식단 분석` 공유 사례 — 서버 쪽. (#2379)

서버와 트레이너 웹 데모(`diet_analysis_rules.dart`)·트레이너 웹 ARB 가 **같은 사례
파일**을 읽어 같은 문장 키·값과 같은 문장을 내는지 본다. 규칙이나 문장을 바꾸면
`scripts/gen_trainer_diet_analysis_cases.py` 를 다시 돌려 파일을 고친다.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location(
    "gen_trainer_diet_analysis_cases",
    _ROOT / "backend/scripts/gen_trainer_diet_analysis_cases.py",
)
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)
_CASES = json.loads(gen.OUT.read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", _CASES["cases"], ids=[c["name"] for c in _CASES["cases"]])
def test_server_matches_the_shared_cases(case):
    assert gen.RUN[case["period"]](case) == case["expected"]


def test_the_shared_file_is_up_to_date():
    """사례 목록과 문장이 스크립트와 같다 — 규칙을 바꾸고 파일을 다시 만들지 않으면 깨진다."""
    assert _CASES == json.loads(json.dumps(gen.build(), ensure_ascii=False))


def test_cases_cover_every_key():
    seen = {s["key"] for c in _CASES["cases"] for s in c["expected"]["sentences"]}
    rendered = {r["key"] for r in _CASES["renderings"]}
    # 사례가 모든 키를 지나지는 않아도, 렌더링 표는 모든 키를 담는다.
    assert rendered == set(gen.svc.KEYS)
    assert seen <= rendered
