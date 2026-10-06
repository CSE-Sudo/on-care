"""규칙 기반 운동 코치 폴백은 앱이 재지 않는 지표를 근거로 들지 않는다. (#3251)

LLM 이 없을 때 회원에게 나가는 문장이 "혈압·혈당 관리에 도움" 이라고 했다. 앱은 혈압·
혈당을 기록하지 않으므로(#602, `coach/grounding.py`) 근거 없는 말이 된다.
"""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.core import locale as locale_mod
from app.services import coach_service
from app.services.coach.grounding import mentions_untracked_metric


class _NoRows:
    def scalars(self, _query):
        return SimpleNamespace(all=lambda: [])


@pytest.mark.parametrize("lang", ["ko", "en"])
def test_empty_week_fallback_does_not_cite_untracked_metrics(lang):
    token = locale_mod._request_locale_ctx.set(lang)
    try:
        suggestion = coach_service._exercise_suggestion(_NoRows(), "user-x")
    finally:
        locale_mod._request_locale_ctx.reset(token)

    text = f"{suggestion.title} {suggestion.body}"
    assert not mentions_untracked_metric(text)
    assert "blood" not in text.lower()
