"""알림 문장 틀. (#2302) DB 없이 돈다.

여기서 고정하는 것:

  * **한국어는 바이트 단위로 예전과 같다.** 틀로 옮기기 전 각 호출부가 직접 조립하던
    문장을 그대로 적어 두고 비교한다 — 저장되는 `title`·`body` 가 옛 앱·푸시가 읽는
    값이라, 한 글자라도 바뀌면 회귀다.
  * 영어 조립이 자연스러운 영어이고 한글이 섞이지 않는다(이름·사람이 쓴 글 제외).
  * 이름이 비었을 때 대신 적는 말이 언어마다 알맞다.
  * 모르는 틀·깨진 인자·틀 없는 옛 알림은 저장된 문장으로 돌아간다.
"""
from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path

import pytest

from app.core.clock import SEOUL
from app.services import health_focus, notification_service, notification_templates as nt
from app.services.trainer_service import _amount_label, _routine_notification_args

HANGUL = re.compile(r"[가-힣]")
STARTS = datetime(2026, 10, 1, 9, 5, tzinfo=SEOUL)


def _ko(code: str, args: dict, body: str = "") -> tuple[str, str]:
    cols = nt.columns(code, args, body=body)
    return cols["title"], cols["body"]


def _en(code: str, args: dict) -> tuple[str, str | None]:
    rendered = nt.render(code, args, "en")
    assert rendered is not None
    return rendered


# --------------------------------------------------------------------------
# 한국어 — 예전 문장과 바이트 단위로 같다
# --------------------------------------------------------------------------

# (틀, 인자, 사람이 쓴 본문, 예전 제목, 예전 본문). 예전 문장은 틀로 옮기기 전
# 호출부의 f-string 을 같은 값으로 풀어 적은 것이다.
LEGACY_KO: list[tuple[str, dict, str, str, str]] = [
    (
        nt.TRAINER_HEALTH_GOAL,
        {"member_name": "지수", "focus": ["근력 향상", "재활"]},
        "",
        "회원 건강 목표 변경",
        "지수 회원이 건강 목표를 바꿨어요: 근력 향상 · 재활",
    ),
    (
        nt.TRAINER_HEALTH_GOAL,
        {"member_name": "지수", "focus": []},
        "",
        "회원 건강 목표 변경",
        "지수 회원이 건강 목표를 바꿨어요: 목표 없음",
    ),
    (
        nt.TRAINER_MEMBER_RENAMED,
        {"old_name": "김지수", "new_name": "김지수B"},
        "",
        "회원 이름 변경",
        "김지수 회원이 이름을 바꿨어요: 김지수B",
    ),
    (
        nt.TRAINER_MEMBER_WITHDRAWN,
        {"member_name": "지수"},
        "",
        "회원 탈퇴",
        "지수 회원이 탈퇴했어요.",
    ),
    (
        nt.TRAINER_MEMBER_WITHDRAWN,
        {"member_name": ""},
        "",
        "회원 탈퇴",
        "이름 없는 회원이 탈퇴했어요.",
    ),
    (
        nt.TRAINER_MEMBER_DISCONNECTED,
        {"member_name": "지수"},
        "",
        "담당 연결 해제",
        "지수 회원이 담당 연결을 끊었어요.",
    ),
    (
        nt.TRAINER_MEMBER_DISCONNECTED,
        {"member_name": "   "},
        "",
        "담당 연결 해제",
        "이름 없는 회원이 담당 연결을 끊었어요.",
    ),
    (
        nt.TRAINER_CONSULT_REQUESTED,
        {"member_name": "지수", "preferred_date": "2026-10-01"},
        "",
        "새 상담 요청이 도착했어요",
        "지수 회원 · 2026-10-01",
    ),
    (
        nt.TRAINER_CONSULT_REQUESTED,
        {"member_name": "", "preferred_date": "2026-10-01"},
        "",
        "새 상담 요청이 도착했어요",
        "회원 회원 · 2026-10-01",
    ),
    (
        nt.TRAINER_CONSULT_CANCELLED,
        {"member_name": "지수", "preferred_date": "2026-10-01"},
        "",
        "상담 요청이 취소됐어요",
        "지수 회원 · 2026-10-01",
    ),
    (
        nt.TRAINER_INVITE_ACCEPTED,
        {"member_name": "지수"},
        "",
        "담당 요청이 수락되었어요",
        "지수 회원이 담당으로 연결되었어요.",
    ),
    (
        nt.TRAINER_INVITE_ACCEPTED,
        {"member_name": ""},
        "",
        "담당 요청이 수락되었어요",
        "회원 회원이 담당으로 연결되었어요.",
    ),
    (
        nt.TRAINER_INVITE_REJECTED,
        {"member_name": "지수"},
        "",
        "담당 요청이 거절되었어요",
        "지수 회원이 담당 요청을 거절했어요.",
    ),
    (
        nt.TRAINER_RESERVATION_BOOKED,
        {"member_name": "지수", "starts_at": STARTS.isoformat()},
        "",
        "새 예약이 들어왔어요",
        f"지수 회원 · {STARTS:%m월 %d일 %H:%M}",
    ),
    (
        nt.TRAINER_RESERVATION_CANCELLED,
        {"member_name": "지수", "starts_at": STARTS.isoformat()},
        "",
        "예약이 취소되었습니다",
        f"지수 회원 · {STARTS:%m월 %d일 %H:%M}",
    ),
    (
        nt.TRAINER_RESERVATION_CANCELLED,
        {"member_name": "지수", "starts_at": None},
        "",
        "예약이 취소되었습니다",
        "지수 회원",
    ),
    (
        nt.TRAINER_RESERVATION_CANCELLED,
        {"member_name": "", "starts_at": None},
        "",
        "예약이 취소되었습니다",
        " 회원",
    ),
    (
        nt.TRAINER_MEMBER_MESSAGE,
        {"member_name": "지수"},
        "오늘 운동 힘들었어요",
        "지수 회원의 메시지",
        "오늘 운동 힘들었어요",
    ),
    (
        nt.TRAINER_MEMBER_MESSAGE,
        {"member_name": ""},
        "안녕하세요",
        "회원 회원의 메시지",
        "안녕하세요",
    ),
    (
        nt.MEMBER_COACH_MESSAGE,
        {"trainer_name": "박코치", "report": False, "photo_only": False},
        "오늘 잘하셨어요",
        "박코치 트레이너의 메시지",
        "오늘 잘하셨어요",
    ),
    (
        nt.MEMBER_COACH_MESSAGE,
        {"trainer_name": "", "report": False, "photo_only": True},
        "",
        "트레이너 트레이너의 메시지",
        "사진을 보냈어요",
    ),
    (
        nt.MEMBER_COACH_MESSAGE,
        {"trainer_name": "박코치", "report": True, "photo_only": False},
        "이번 주 리포트입니다",
        "주간 리포트가 도착했어요",
        "이번 주 리포트입니다",
    ),
    (
        nt.MEMBER_COACH_MESSAGE,
        {"trainer_name": "박코치", "report": False, "photo_only": False},
        "",
        "박코치 트레이너의 메시지",
        "",
    ),
    (
        nt.MEMBER_ROUTINE_PROGRAM,
        {"name": "하체 프로그램", "sessions": 3, "minutes": 150, "multi": True},
        "",
        "새 운동 루틴이 배정되었어요",
        "하체 프로그램 · 세션 3개 · 150분",
    ),
    (
        nt.MEMBER_ROUTINE_PROGRAM,
        {"name": "하체 프로그램", "sessions": 1, "minutes": 50, "multi": False},
        "",
        "새 운동 루틴이 배정되었어요",
        "하체 프로그램 · 50분",
    ),
    (
        nt.MEMBER_TRAINER_CONNECTED,
        {"trainer_name": "박코치"},
        "",
        "트레이너와 연결됐어요",
        "박코치 트레이너가 담당 코치가 됐어요. 식단·운동 기록이 공유돼요.",
    ),
    (
        nt.MEMBER_TRAINER_CONNECTED,
        {"trainer_name": ""},
        "",
        "트레이너와 연결됐어요",
        "트레이너 트레이너가 담당 코치가 됐어요. 식단·운동 기록이 공유돼요.",
    ),
    (
        nt.MEMBER_COACH_INVITE,
        {"trainer_name": "박코치"},
        "",
        "담당 요청이 도착했어요",
        "박코치 트레이너가 담당 코치가 되기를 요청했어요.",
    ),
    (
        nt.MEMBER_HEALTH_GOAL,
        {"trainer_name": "박코치", "focus": ["자세 교정"]},
        "",
        "건강 목표가 바뀌었어요",
        "박코치 트레이너님이 건강 목표를 바꿨어요: 자세 교정",
    ),
    (
        nt.MEMBER_CONSULT_APPROVED,
        {"trainer_name": "박코치", "starts_at": STARTS.isoformat(), "note": None},
        "",
        "상담 요청이 승인되었어요",
        f"박코치 트레이너가 담당으로 연결되었어요. 첫 상담은 {STARTS:%m월 %d일 %H:%M} 입니다.",
    ),
    (
        nt.MEMBER_CONSULT_APPROVED,
        {"trainer_name": "", "starts_at": STARTS.isoformat(), "note": "편한 복장으로 오세요."},
        "",
        "상담 요청이 승인되었어요",
        f"트레이너 트레이너가 담당으로 연결되었어요. 첫 상담은 {STARTS:%m월 %d일 %H:%M} 입니다."
        " 편한 복장으로 오세요.",
    ),
    (
        nt.MEMBER_CONSULT_APPROVED,
        {"trainer_name": "박코치", "starts_at": STARTS.isoformat(), "note": ""},
        "",
        "상담 요청이 승인되었어요",
        f"박코치 트레이너가 담당으로 연결되었어요. 첫 상담은 {STARTS:%m월 %d일 %H:%M} 입니다. ",
    ),
    (
        nt.MEMBER_CONSULT_REJECTED,
        {"has_note": False},
        "",
        "상담 요청이 반려되었어요",
        "다른 트레이너에게 상담을 요청해 보세요.",
    ),
    (
        nt.MEMBER_CONSULT_REJECTED,
        {"has_note": True},
        "이번 달은 예약이 꽉 찼어요.",
        "상담 요청이 반려되었어요",
        "이번 달은 예약이 꽉 찼어요.",
    ),
    (
        nt.MEMBER_CONSULT_EXPIRED,
        {},
        "",
        "상담 신청이 만료되었어요",
        "트레이너가 시간 안에 확인하지 않았어요. 다른 시간으로 다시 신청해 보세요.",
    ),
    (
        nt.MEMBER_TRAINER_LEFT,
        {"trainer_name": "박코치"},
        "",
        "담당 트레이너 연결이 해제되었어요",
        "박코치 트레이너가 서비스를 떠났습니다. 새 트레이너를 찾아보세요.",
    ),
    (
        nt.MEMBER_TRAINER_LEFT,
        {"trainer_name": ""},
        "",
        "담당 트레이너 연결이 해제되었어요",
        "트레이너 트레이너가 서비스를 떠났습니다. 새 트레이너를 찾아보세요.",
    ),
    (
        nt.MEMBER_TRAINER_LEFT_BOOKING,
        {"trainer_name": "박코치"},
        "",
        "예약한 수업이 취소되었어요",
        "박코치 트레이너가 서비스를 떠나 예약이 취소되었습니다.",
    ),
]


@pytest.mark.parametrize(
    ("code", "args", "body", "title_ko", "body_ko"),
    LEGACY_KO,
    ids=[f"{row[0]}-{i}" for i, row in enumerate(LEGACY_KO)],
)
def test_korean_is_byte_identical_to_the_old_sentences(code, args, body, title_ko, body_ko):
    title, stored_body = _ko(code, args, body)
    assert title.encode() == title_ko.encode()
    assert stored_body.encode() == body_ko.encode()


def test_every_template_has_a_korean_regression_case():
    """새 틀을 더하면 여기에도 예전(또는 확정) 한국어 문장을 적어야 한다."""
    covered = {row[0] for row in LEGACY_KO} | {nt.MEMBER_ROUTINE_ASSIGNED}
    assert covered == nt.codes()


# 루틴 양은 `trainer_service._amount_label` 이 기준이다 — 두 규칙이 갈라지면 알림과
# 수행 이력이 같은 배정을 다르게 말한다.
AMOUNTS = [
    ("유산소", 30, None, None, None, None),
    ("cardio", 45, 3, 10, None, None),
    ("근력", 15, 3, 12, None, 40.0),
    ("strength", 15, 3, 12, None, 0.0),
    ("근력", 10, 3, None, 60, None),
    ("근력", 10, 4, 8, None, 22.5),
    ("근력", 20, None, 10, None, 30.0),
    ("스트레칭", 10, None, None, None, None),
    ("근력", 10, 1, 1, None, None),
]


@pytest.mark.parametrize(("type_", "minutes", "sets", "reps", "hold", "weight"), AMOUNTS)
def test_routine_amount_matches_the_trainer_service_rule(type_, minutes, sets, reps, hold, weight):
    args = _routine_notification_args(
        "스쿼트", type_, minutes=minutes, sets=sets, reps=reps,
        hold_seconds=hold, weight=weight,
    )
    title, body = _ko(nt.MEMBER_ROUTINE_ASSIGNED, args)
    legacy = "스쿼트 · " + _amount_label(
        type_, minutes=minutes, sets=sets, reps=reps, hold_seconds=hold, weight=weight
    )
    assert title == "새 운동 루틴이 배정되었어요"
    assert body.encode() == legacy.encode()
    # 영어에는 단위 한글이 남지 않는다(운동 이름은 데이터라 그대로다).
    _, body_en = _en(nt.MEMBER_ROUTINE_ASSIGNED, args)
    assert body_en.startswith("스쿼트 · ")
    assert not HANGUL.search(body_en.removeprefix("스쿼트 · "))


@pytest.mark.parametrize(
    ("type_", "minutes", "sets", "reps", "hold", "weight", "expected"),
    [
        ("유산소", 30, None, None, None, None, "30 min"),
        ("근력", 15, 3, 12, None, 40.0, "3 sets · 12 reps · 40 kg"),
        ("근력", 15, 1, 1, None, None, "1 set · 1 rep"),
        ("근력", 10, 3, None, 60, None, "3 sets · 60 sec"),
        ("strength", 15, 3, 12, None, 0.0, "3 sets · 12 reps · 0 kg"),
        ("근력", 10, 4, 8, None, 22.5, "4 sets · 8 reps · 22.5 kg"),
        ("근력", 20, None, 10, None, 30.0, "20 min"),
    ],
)
def test_routine_amount_in_english(type_, minutes, sets, reps, hold, weight, expected):
    args = _routine_notification_args(
        "Squat", type_, minutes=minutes, sets=sets, reps=reps,
        hold_seconds=hold, weight=weight,
    )
    assert _en(nt.MEMBER_ROUTINE_ASSIGNED, args) == (
        "New workout routine assigned",
        f"Squat · {expected}",
    )


# --------------------------------------------------------------------------
# 영어
# --------------------------------------------------------------------------

ENGLISH: list[tuple[str, dict, tuple[str, str | None]]] = [
    (
        nt.TRAINER_HEALTH_GOAL,
        {"member_name": "Alex", "focus": ["근력 향상", "재활"]},
        ("Member goals changed", "Alex changed their health goals: Build strength · Rehab"),
    ),
    (
        nt.TRAINER_HEALTH_GOAL,
        {"member_name": "Alex", "focus": []},
        ("Member goals changed", "Alex changed their health goals: none"),
    ),
    (
        nt.TRAINER_MEMBER_RENAMED,
        {"old_name": "Alex", "new_name": "Alexandra"},
        ("Member renamed", "Alex changed their name to Alexandra."),
    ),
    (
        nt.TRAINER_MEMBER_WITHDRAWN,
        {"member_name": "Alex"},
        ("Member account deleted", "Alex deleted their account."),
    ),
    (
        nt.TRAINER_MEMBER_WITHDRAWN,
        {"member_name": ""},
        ("Member account deleted", "A member deleted their account."),
    ),
    (
        nt.TRAINER_MEMBER_DISCONNECTED,
        {"member_name": "Alex"},
        ("Client disconnected", "Alex ended their connection with you."),
    ),
    (
        nt.TRAINER_CONSULT_REQUESTED,
        {"member_name": "Alex", "preferred_date": "2026-10-01"},
        ("New consultation request", "Alex · 2026-10-01"),
    ),
    (
        nt.TRAINER_CONSULT_REQUESTED,
        {"member_name": "", "preferred_date": "2026-10-01"},
        ("New consultation request", "Member · 2026-10-01"),
    ),
    (
        nt.TRAINER_CONSULT_CANCELLED,
        {"member_name": "Alex", "preferred_date": "2026-10-01"},
        ("Consultation request cancelled", "Alex · 2026-10-01"),
    ),
    (
        nt.TRAINER_INVITE_ACCEPTED,
        {"member_name": "Alex"},
        ("Coaching request accepted", "Alex is now your client."),
    ),
    (
        nt.TRAINER_INVITE_ACCEPTED,
        {"member_name": ""},
        ("Coaching request accepted", "A member is now your client."),
    ),
    (
        nt.TRAINER_INVITE_REJECTED,
        {"member_name": "Alex"},
        ("Coaching request declined", "Alex declined your coaching request."),
    ),
    (
        nt.TRAINER_RESERVATION_BOOKED,
        {"member_name": "Alex", "starts_at": STARTS.isoformat()},
        ("New booking", "Alex · 10/01 09:05"),
    ),
    (
        nt.TRAINER_RESERVATION_CANCELLED,
        {"member_name": "Alex", "starts_at": STARTS.isoformat()},
        ("Booking cancelled", "Alex · 10/01 09:05"),
    ),
    (
        nt.TRAINER_RESERVATION_CANCELLED,
        {"member_name": "", "starts_at": None},
        ("Booking cancelled", "Member"),
    ),
    (
        nt.TRAINER_MEMBER_MESSAGE,
        {"member_name": "Alex"},
        ("Message from Alex", None),
    ),
    (
        nt.TRAINER_MEMBER_MESSAGE,
        {"member_name": ""},
        ("Message from a member", None),
    ),
    (
        nt.MEMBER_COACH_MESSAGE,
        {"trainer_name": "Coach Park", "report": False, "photo_only": False},
        ("Message from Coach Park", None),
    ),
    (
        nt.MEMBER_COACH_MESSAGE,
        {"trainer_name": "", "report": False, "photo_only": True},
        ("Message from your trainer", "Sent a photo"),
    ),
    (
        nt.MEMBER_COACH_MESSAGE,
        {"trainer_name": "Coach Park", "report": True, "photo_only": False},
        ("Your weekly report is here", None),
    ),
    (
        nt.MEMBER_ROUTINE_PROGRAM,
        {"name": "Leg day", "sessions": 3, "minutes": 150, "multi": True},
        ("New workout routine assigned", "Leg day · 3 sessions · 150 min"),
    ),
    (
        nt.MEMBER_ROUTINE_PROGRAM,
        {"name": "Leg day", "sessions": 1, "minutes": 50, "multi": False},
        ("New workout routine assigned", "Leg day · 50 min"),
    ),
    (
        nt.MEMBER_TRAINER_CONNECTED,
        {"trainer_name": "Coach Park"},
        (
            "Connected with a trainer",
            "Coach Park is now your coach. Your meal and workout logs are shared.",
        ),
    ),
    (
        nt.MEMBER_COACH_INVITE,
        {"trainer_name": ""},
        ("Coaching request received", "A trainer wants to be your coach."),
    ),
    (
        nt.MEMBER_HEALTH_GOAL,
        {"trainer_name": "Coach Park", "focus": ["자세 교정", "혈압 관리"]},
        (
            "Your health goals changed",
            "Coach Park changed your health goals: Posture correction · Blood pressure care",
        ),
    ),
    (
        nt.MEMBER_CONSULT_APPROVED,
        {"trainer_name": "Coach Park", "starts_at": STARTS.isoformat(), "note": None},
        (
            "Consultation request approved",
            "You're now connected with Coach Park. Your first consultation is on 10/01 09:05.",
        ),
    ),
    (
        nt.MEMBER_CONSULT_APPROVED,
        {"trainer_name": "", "starts_at": STARTS.isoformat(), "note": "See you soon!"},
        (
            "Consultation request approved",
            "You're now connected with your trainer. Your first consultation is on"
            " 10/01 09:05. See you soon!",
        ),
    ),
    (
        nt.MEMBER_CONSULT_REJECTED,
        {"has_note": False},
        (
            "Consultation request declined",
            "Try requesting a consultation with another trainer.",
        ),
    ),
    (
        nt.MEMBER_CONSULT_REJECTED,
        {"has_note": True},
        ("Consultation request declined", None),
    ),
    (
        nt.MEMBER_CONSULT_EXPIRED,
        {},
        (
            "Consultation request expired",
            "The trainer didn't respond in time. Try requesting a different time.",
        ),
    ),
    (
        nt.MEMBER_TRAINER_LEFT,
        {"trainer_name": ""},
        ("Your trainer connection ended", "Your trainer has left the service. Find a new trainer."),
    ),
    (
        nt.MEMBER_TRAINER_LEFT_BOOKING,
        {"trainer_name": "Coach Park"},
        (
            "Your booked session was cancelled",
            "Coach Park left the service, so your booking was cancelled.",
        ),
    ),
]


@pytest.mark.parametrize(
    ("code", "args", "expected"),
    ENGLISH,
    ids=[f"{row[0]}-{i}" for i, row in enumerate(ENGLISH)],
)
def test_english_sentences(code, args, expected):
    assert _en(code, args) == expected


@pytest.mark.parametrize("code", sorted(nt.codes()))
def test_english_has_no_korean_left(code):
    """영어 문장에 한글이 남지 않는다 — 인자에 한글이 없으면 결과에도 없어야 한다."""
    args = {
        "member_name": "Alex",
        "trainer_name": "Coach Park",
        "old_name": "Alex",
        "new_name": "Sam",
        "name": "Squat",
        "focus": list(health_focus.FOCUS_OPTIONS[:2]),
        "preferred_date": "2026-10-01",
        "starts_at": STARTS.isoformat(),
        "sessions": 2,
        "minutes": 30,
        "multi": True,
        "strength": True,
        "sets": 3,
        "reps": 10,
        "weight": 20.0,
        "note": None,
        "photo_only": True,
    }
    title, body = _en(code, args)
    assert not HANGUL.search(title), title
    assert body is None or not HANGUL.search(body), body


@pytest.mark.parametrize("code", sorted(nt.codes()))
def test_empty_names_never_leave_a_dangling_space_in_english(code):
    # 이름 칸만 비운다. 운동 이름·옛 이름처럼 비울 수 없는 값은 채워 둔다.
    args = {
        "member_name": "",
        "trainer_name": "",
        "name": "Squat",
        "old_name": "Alex",
        "new_name": "Sam",
        "focus": [],
        "preferred_date": "2026-10-01",
        "starts_at": STARTS.isoformat(),
    }
    title, body = _en(code, args)
    for text in (title, body or ""):
        assert not text.startswith(" "), text
        assert "  " not in text, text


def test_every_focus_option_has_an_english_label():
    """건강 목표가 늘면 영어도 함께 는다 — 빠지면 영어 알림에 한국어 목표가 남는다."""
    args = {"member_name": "Alex", "focus": list(health_focus.FOCUS_OPTIONS)}
    _, body = _en(nt.TRAINER_HEALTH_GOAL, args)
    assert not HANGUL.search(body)
    assert body.count(" · ") == len(health_focus.FOCUS_OPTIONS) - 1


def test_unknown_focus_value_stays_as_it_was():
    args = {"member_name": "Alex", "focus": ["고혈압"]}
    assert _en(nt.TRAINER_HEALTH_GOAL, args)[1].endswith(": 고혈압")


# --------------------------------------------------------------------------
# 만들기
# --------------------------------------------------------------------------


def test_columns_keep_template_and_json_args():
    cols = nt.columns(nt.TRAINER_MEMBER_RENAMED, {"old_name": "가", "new_name": "나"})
    assert cols["template"] == nt.TRAINER_MEMBER_RENAMED
    assert cols["template_args"] == {"old_name": "가", "new_name": "나"}
    # JSON 칸에 들어가므로 직렬화할 수 있어야 한다.
    assert json.loads(json.dumps(cols["template_args"])) == cols["template_args"]


def test_columns_copy_the_args():
    """호출부가 넘긴 dict 를 나중에 고쳐도 저장된 인자는 그대로다."""
    args = {"member_name": "지수"}
    cols = nt.columns(nt.TRAINER_INVITE_ACCEPTED, args)
    args["member_name"] = "바뀜"
    assert cols["template_args"] == {"member_name": "지수"}


def test_columns_reject_an_unknown_template():
    with pytest.raises(ValueError):
        nt.columns("no_such_template", {})


def test_texts_needs_a_title_or_a_template():
    with pytest.raises(ValueError):
        notification_service.texts(title=None)


def test_texts_without_a_template_keeps_the_given_sentence():
    assert notification_service.texts(title="제목", body="본문") == {
        "title": "제목",
        "body": "본문",
    }


def test_texts_with_a_template_uses_the_template_title():
    cols = notification_service.texts(
        title=None,
        body="메시지",
        template=nt.TRAINER_MEMBER_MESSAGE,
        template_args={"member_name": "지수"},
    )
    assert cols == {
        "title": "지수 회원의 메시지",
        "body": "메시지",
        "template": nt.TRAINER_MEMBER_MESSAGE,
        "template_args": {"member_name": "지수"},
    }


def test_template_codes_fit_the_column():
    assert all(len(code) <= 40 for code in nt.codes())


# --------------------------------------------------------------------------
# 읽기
# --------------------------------------------------------------------------

STORED = {"title": "지수 회원의 메시지", "body": "안녕하세요"}


def test_korean_reads_the_stored_sentence_even_if_the_template_would_differ():
    """한국어는 저장된 문장이다 — 받은 순간의 문장을 다시 쓰지 않는다."""
    title, body = nt.localize(
        title="예전 제목", body="예전 본문",
        template=nt.TRAINER_MEMBER_MESSAGE, template_args={"member_name": "지수"},
        locale="ko",
    )
    assert (title, body) == ("예전 제목", "예전 본문")


def test_english_reads_the_template():
    assert nt.localize(
        **STORED, template=nt.TRAINER_MEMBER_MESSAGE,
        template_args={"member_name": "Alex"}, locale="en",
    ) == ("Message from Alex", "안녕하세요")


@pytest.mark.parametrize(
    ("template", "args"),
    [
        (None, None),  # 틀이 생기기 전의 알림
        ("no_such_template", {"member_name": "Alex"}),  # 이 서버가 모르는 틀
        (nt.TRAINER_RESERVATION_BOOKED, {"member_name": "A", "starts_at": "not-a-date"}),
        (nt.MEMBER_ROUTINE_PROGRAM, {"name": "x", "sessions": "many"}),
        (nt.TRAINER_HEALTH_GOAL, {"member_name": "A", "focus": 3}),
    ],
)
def test_english_falls_back_to_the_stored_sentence(template, args):
    assert nt.localize(**STORED, template=template, template_args=args, locale="en") == (
        STORED["title"],
        STORED["body"],
    )


def test_localize_defaults_to_the_request_locale(monkeypatch):
    from app.core import locale as locale_module

    token = locale_module._request_locale_ctx.set("en")
    try:
        assert nt.localize(
            **STORED, template=nt.TRAINER_MEMBER_MESSAGE,
            template_args={"member_name": "Alex"},
        )[0] == "Message from Alex"
    finally:
        locale_module._request_locale_ctx.reset(token)
    # 요청 밖(기본값)은 한국어 — 저장된 문장이다.
    assert nt.localize(
        **STORED, template=nt.TRAINER_MEMBER_MESSAGE, template_args={"member_name": "Alex"},
    ) == (STORED["title"], STORED["body"])


def test_render_tolerates_missing_args():
    """인자가 빠진 틀도 예외 없이 문장을 만든다(목록이 500 이 되지 않게)."""
    for code in nt.codes():
        assert nt.render(code, {}, "en") is not None
        assert nt.render(code, None, "ko") is not None


def test_render_unknown_or_empty_code_is_none():
    assert nt.render(None, {}, "en") is None
    assert nt.render("", {}, "en") is None
    assert nt.render("no_such_template", {}, "en") is None


# --------------------------------------------------------------------------
# 트레이너 웹과 같은 코드
# --------------------------------------------------------------------------

_TRAINER_TEXT = (
    Path(__file__).resolve().parents[2]
    / "frontend/flutter_trainer/lib/features/notifications/presentation/trainer_notification_text.dart"
)


@pytest.mark.skipif(not _TRAINER_TEXT.exists(), reason="프론트 소스가 없는 체크아웃")
def test_trainer_web_knows_every_trainer_template():
    """트레이너가 받는 틀은 트레이너 웹이 모두 ARB 로 조립한다.

    한쪽에만 더하면 트레이너 웹은 서버가 조립한 문장으로 돌아가 동작은 하지만,
    앱이 문구의 주인이라는 약속이 조용히 깨진다.
    """
    source = _TRAINER_TEXT.read_text(encoding="utf-8")
    trainer_codes = {code for code in nt.codes() if code.startswith("trainer_")}
    missing = {code for code in trainer_codes if f"'{code}'" not in source}
    assert missing == set()
