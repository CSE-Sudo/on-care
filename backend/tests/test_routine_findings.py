"""AI 루틴 후보의 판단 결과(#3280).

분석(`analysis`)은 판단에 넣은 값이고, 판단 결과(`findings`)는 서버 규칙이 그
값에서 찾은 신호와 반영 방향이다. 규칙형 생성과 같은 규칙으로 센다.
"""
from __future__ import annotations

from app.schemas.trainer_api import RoutineOptionAnalysisOut, RoutineOptionsRequest
from app.services import routine_ai
from app.services.trainer_routine_options_service import (
    build_findings,
    build_rule_options,
)


def _analysis(**overrides) -> RoutineOptionAnalysisOut:
    base = {
        "goal": "체중 감량",
        "sodium_today_mg": 1500,
        "sodium_over_target": False,
        "avg_completion_rate": 70,
        "latest_routine": "",
        "note": "",
    }
    base.update(overrides)
    return RoutineOptionAnalysisOut(**base)


def _kinds(findings) -> list[str]:
    return [f.kind for f in findings]


def test_knee_mention_in_chat_becomes_caution_with_source():
    findings = build_findings(
        _analysis(recent_messages=["회원: 무릎이 가볍게 당겨요", "트레이너: 쉬어요"])
    )
    caution = next(f for f in findings if f.kind == "caution")
    assert "무릎" in caution.finding
    assert caution.source == "최근 대화"
    assert "러닝" in caution.action


def test_memo_date_is_carried_into_source():
    findings = build_findings(_analysis(pt_feedbacks=["10.06 허리 디스크 주의"]))
    caution = next(f for f in findings if f.kind == "caution")
    assert caution.source == "PT 피드백 · 10.06"


def test_escalation_keyword_is_reported():
    findings = build_findings(_analysis(recent_messages=["회원: 운동 중 흉통이 있었어요"]))
    assert "escalation" in _kinds(findings)


def test_pattern_member_reports_repeated_exercises_only():
    findings = build_findings(
        _analysis(
            frequent_exercises=["걷기", "플랭크"],
            history_session_count=35,
            analysis_period_days=42,
            sodium_today_mg=4000,
            sodium_over_target=True,
            avg_completion_rate=30,
        )
    )
    # 반복 패턴이 있으면 규칙형도 나트륨·완료율로 가르지 않는다.
    assert _kinds(findings) == ["pattern"]
    assert findings[0].source == "운동 기록 · 최근 42일 35회"


def test_template_member_reports_sodium_and_adherence():
    findings = build_findings(
        _analysis(sodium_today_mg=4000, sodium_over_target=True, avg_completion_rate=40)
    )
    assert _kinds(findings) == ["sodium", "adherence"]


def test_findings_follow_locale():
    findings = build_findings(
        _analysis(recent_messages=["회원: 무릎이 아파요"]), locale="en"
    )
    caution = next(f for f in findings if f.kind == "caution")
    assert caution.finding == "Mentions knee discomfort"
    assert caution.source == "Recent chat"


def test_rule_options_carry_findings():
    options = build_rule_options(
        _analysis(recent_messages=["회원: 발목을 삐었어요"]),
        RoutineOptionsRequest(available_minutes=30, intensity_preference="moderate"),
    )
    assert "caution" in _kinds(options.findings)


def test_findings_match_rule_cautions():
    """판단 결과의 주의 부위는 규칙형이 실제로 피하는 부위와 같다."""
    messages = ["회원: 어깨가 결려요", "회원: 허리도 뻐근해요"]
    findings = build_findings(_analysis(recent_messages=messages))
    parts = [f.finding.split(" ")[0] for f in findings if f.kind == "caution"]
    assert parts == routine_ai.cautions_in("", messages)
