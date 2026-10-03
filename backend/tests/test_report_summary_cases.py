"""주간 리포트 요약 판정 공유 사례 — 서버 쪽. (#2906)

서버(`trainer_report_summary_service.watchpoints`)와 트레이너 웹 데모
(`report_summary.dart` 의 `summaryWatchpoints`)가 **같은 파일**
(`shared/oncare_rules/vectors/report_summary_cases.json`)을 읽어 같은 기준값과
같은 판정을 갖는지 본다. 기준이나 판정을 바꾸면
`scripts/gen_report_summary_cases.py` 를 다시 돌려 파일을 고친다.

DB 없이 돈다.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location(
    "gen_report_summary_cases",
    _ROOT / "backend/scripts/gen_report_summary_cases.py",
)
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)
_FILE = json.loads(gen.OUT.read_text(encoding="utf-8"))


def test_the_shared_file_is_up_to_date() -> None:
    """기준값과 사례가 서버와 같다 — 판정을 바꾸고 파일을 다시 만들지 않으면 깨진다."""
    assert _FILE == json.loads(json.dumps(gen.build(), ensure_ascii=False))


@pytest.mark.parametrize("case", _FILE["cases"], ids=[c["name"] for c in _FILE["cases"]])
def test_server_matches_the_shared_cases(case: dict) -> None:
    assert gen.run(case) == case["expected"]


def test_cases_cover_every_watchpoint_kind() -> None:
    """사례가 모든 주의 종류를 한 번은 지난다 — 종류를 더하면 사례도 더한다."""
    seen = {w["kind"] for c in _FILE["cases"] for w in c["expected"]["watchpoints"]}
    assert seen == {"completion", "skipped", "sodium", "sugar", "calories", "macro"}
