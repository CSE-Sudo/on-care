"""홈 코칭 시트 카드 = 규칙 제목·첫 문장 + `이번 주` 긴 문장. (#3549)

시트는 AI 를 부르지 않고, 식단·운동 탭 `이번 주` 조언이 받아 둔 긴 문장을 잇는다.
수치는 규칙 첫 문장이 말하고, 긴 문장이 없으면 규칙 카드를 그대로 쓴다.
"""
from __future__ import annotations

import pytest

from app.schemas.misc_api import CoachSuggestion
from app.services import coach_service

DETAIL = "이번 주는 걷기를 꾸준히 이어 갔어요. 남은 날에는 가벼운 근력 운동을 한 번 더해 보세요."


@pytest.mark.parametrize(
    "body, lead",
    [
        ("이번 주 유산소 40분 운동했어요. 주 150분을 목표로 가볍게 더해봐요.",
         "이번 주 유산소 40분 운동했어요."),
        ("이번 주 유산소 160분! 목표 운동량을 잘 채우고 있어요. 멋져요!",
         "이번 주 유산소 160분!"),
        # 수 안의 쉼표·점은 문장 끝이 아니다.
        ("오늘 나트륨이 약 2,500mg으로 목표를 넘었어요. 저녁은 국물을 남겨요.",
         "오늘 나트륨이 약 2,500mg으로 목표를 넘었어요."),
        ("마침표 없는 문장", "마침표 없는 문장"),
    ],
)
def test_lead_is_the_first_sentence(body, lead):
    assert coach_service._lead(body) == lead


def test_detail_follows_the_rule_lead_and_keeps_the_title():
    card = CoachSuggestion(
        tag="exercise", title="조금만 더 움직여봐요",
        body="이번 주 유산소 40분 운동했어요. 주 150분을 목표로 가볍게 더해봐요.",
    )
    joined = coach_service._with_detail(card, DETAIL)
    assert joined.tag == "exercise"
    assert joined.title == "조금만 더 움직여봐요"
    assert joined.body == f"이번 주 유산소 40분 운동했어요. {DETAIL}"


@pytest.mark.parametrize("detail", [None, ""])
def test_without_a_detail_the_rule_card_stays(detail):
    card = CoachSuggestion(tag="diet", title="식단 균형이 좋아요", body="오늘 나트륨 섭취가 안정적이에요. 이대로 꾸준히 유지해봐요!")
    assert coach_service._with_detail(card, detail) == card


def test_a_failing_week_advice_does_not_break_the_sheet(monkeypatch):
    """`이번 주` 조언이 예외를 내도 시트는 규칙 카드로 뜬다."""
    from app.services import diet_week_advice, exercise_week_ai

    def _boom(*_a, **_k):
        raise RuntimeError("테스트: 조언 실패")

    class _Db:
        rolled_back = 0

        def rollback(self):
            self.rolled_back += 1

    monkeypatch.setattr(diet_week_advice, "week_advice", _boom)
    monkeypatch.setattr(exercise_week_ai, "week_ai", _boom)
    db = _Db()
    assert coach_service._diet_week_detail(db, "u") is None
    assert coach_service._exercise_week_detail(db, "u") is None
    assert db.rolled_back == 2
