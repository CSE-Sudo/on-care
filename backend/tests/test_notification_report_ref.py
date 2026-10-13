"""리포트 알림이 가리키는 리포트(`NotificationOut.report`). (#3344)

리포트 알림은 대화 맨 아래로만 보냈다 — 그 뒤 메시지가 쌓이면 회원이 리포트 카드를
찾아 올라가야 했다. 리포트를 보낼 때 주와 메시지를 문장 틀 인자에 남기고, 응답이 그
값을 `report` 칸으로 준다. 목적지 값(`action.target`)은 `coach_chat` 그대로다 —
이미 배포된 앱은 모르는 목적지 값을 받으면 아무 데도 가지 않는다.

DB 없이 행 하나로 응답을 만드는 규칙만 본다.
"""
from __future__ import annotations

from datetime import datetime, timezone

import pytest

from app.api.v1.notifications import _report_for, notification_out
from app.models.models import Notification
from app.services import notification_service, notification_templates


def _row(
    *,
    category: str = notification_service.MEMBER_COACH_REPORT,
    args: dict | None = None,
    template: str | None = notification_templates.MEMBER_COACH_MESSAGE,
) -> Notification:
    return Notification(
        id="noti-report-ref",
        user_id="user-report-ref",
        title="주간 리포트가 도착했어요",
        body="이번 주 잘하셨어요",
        category=category,
        read=False,
        template=template,
        template_args=args,
        created_at=datetime.now(timezone.utc),
    )


def _report_args(**extra: object) -> dict:
    return {"trainer_name": "민준", "report": True, "photo_only": False, **extra}


def test_report_row_carries_week_and_message():
    row = _row(args=_report_args(week_start="2026-10-05", message_id="chat-abc"))

    report = _report_for(row)

    assert report is not None
    assert report.week_start == "2026-10-05"
    assert report.message_id == "chat-abc"


def test_week_without_a_message_still_points_at_the_week():
    """메시지 식별자가 없어도 주만으로 그 주 리포트를 찾을 수 있다."""
    row = _row(args=_report_args(week_start="2026-10-05"))

    report = _report_for(row)

    assert report is not None
    assert report.week_start == "2026-10-05"
    assert report.message_id is None


@pytest.mark.parametrize("message_id", ["", 7, None, ["chat-abc"]])
def test_unreadable_message_id_is_dropped(message_id):
    row = _row(args=_report_args(week_start="2026-10-05", message_id=message_id))

    report = _report_for(row)

    assert report is not None
    assert report.message_id is None


@pytest.mark.parametrize(
    "args",
    [
        None,
        {},
        # 주가 실리기 전에 쌓인 리포트 알림.
        _report_args(),
        _report_args(message_id="chat-abc"),
        _report_args(week_start=None),
        _report_args(week_start=20261005),
        _report_args(week_start=""),
        _report_args(week_start="garbage"),
        _report_args(week_start="2026-13-40"),
    ],
)
def test_rows_without_a_readable_week_have_no_report(args):
    assert _report_for(_row(args=args)) is None


def test_other_categories_never_carry_a_report():
    """같은 인자가 실려 있어도 리포트 갈래가 아니면 주지 않는다."""
    args = _report_args(week_start="2026-10-05", message_id="chat-abc")
    for category in (
        notification_service.MEMBER_COACH_CHAT,
        notification_service.MEMBER_ROUTINE,
        "system",
    ):
        assert _report_for(_row(category=category, args=args)) is None


def test_response_keeps_the_chat_target_and_adds_the_report():
    """목적지 값은 그대로 `coach_chat` 이고 `report` 칸만 더해진다."""
    row = _row(args=_report_args(week_start="2026-10-05", message_id="chat-abc"))

    out = notification_out(row)

    assert out.action is not None
    assert out.action.target == "coach_chat"
    assert out.action.target in notification_service.MEMBER_ACTION_TARGETS
    assert out.report is not None
    assert out.report.model_dump() == {
        "week_start": "2026-10-05",
        "message_id": "chat-abc",
    }
    # 제목은 저장된 문장 그대로이고, 문장 틀은 새 인자를 몰라도 같은 제목을 만든다.
    assert out.title == "주간 리포트가 도착했어요"
    rendered = notification_templates.render(row.template, row.template_args)
    assert rendered is not None
    assert rendered[0] == "주간 리포트가 도착했어요"


def test_old_report_row_serializes_with_an_empty_report():
    out = notification_out(_row(args=None, template=None))

    assert out.report is None
    assert out.action is not None
    assert out.action.target == "coach_chat"
    assert out.model_dump()["report"] is None
