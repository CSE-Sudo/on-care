"""알림 문장 틀 — 문장과 함께 틀 코드·인자를 저장한다. (#2302)

**저장**: 알림을 만들 때 한국어 문장(`title`·`body`)과 함께 틀 코드(`template`)와
인자(`template_args`)를 남긴다([columns]). 문장은 틀이 조립한 것이다.

**읽기**: 목록 API 는 **저장된 문장을 그대로** 준다. 틀 문구를 나중에 다듬어도
이미 받은 알림은 받은 순간의 문장으로 남는다(`name_change` 의 원칙과 같다).

- 트레이너 웹은 응답의 `template`·`args` 로 ARB 문장을 직접 조립한다(앱이 문구의
  주인이다). 앱이 모르는 틀이면 응답의 `title`·`body` 를 쓴다.
- 회원 앱은 응답의 `title`·`body` 를 그대로 그린다.

인자에는 **문장과 무관한 값**만 담는다 — 이름·날짜·수량·건강 목표 저장 값. 회원이나
트레이너가 직접 쓴 글(메시지 본문·반려 사유)은 틀에 넣지 않고 저장할 `body` 로
따로 받는다(렌더러가 본문으로 ``None`` 을 돌려준다).
"""
from __future__ import annotations

from collections.abc import Callable, Mapping
from datetime import date, datetime, timedelta
from typing import Any

from app.services.exercise_duration import format_duration, seconds_or_minutes

Args = Mapping[str, Any]
#: (제목, 본문). 본문이 ``None`` 이면 저장된 본문을 그대로 쓴다.
Rendered = tuple[str, "str | None"]
_Renderer = Callable[[Args], Rendered]

# --------------------------------------------------------------------------
# 틀 코드. `notifications.template` 이 `String(40)` 이라 40자를 넘기면 안 된다.
# 트레이너 웹(`trainer_notification_text.dart`)이 같은 코드를 읽는다 — 이름을
# 바꾸면 이미 저장된 알림을 트레이너 웹이 저장된 문장으로 그린다.
# --------------------------------------------------------------------------

# 트레이너가 받는 알림.
TRAINER_HEALTH_GOAL = "trainer_health_goal"
#: 회원이 건강상태·주의사항을 고쳤다(#2619). 글은 싣지 않는다 — 알림 미리보기에
#: 건강 정보가 드러나지 않게, 트레이너 웹이 누르면 글이 있는 창을 바로 연다.
TRAINER_HEALTH_NOTES = "trainer_health_notes"
TRAINER_MEMBER_RENAMED = "trainer_member_renamed"
TRAINER_MEMBER_WITHDRAWN = "trainer_member_withdrawn"
TRAINER_MEMBER_DISCONNECTED = "trainer_member_disconnected"
TRAINER_CONSULT_REQUESTED = "trainer_consult_requested"
TRAINER_CONSULT_CANCELLED = "trainer_consult_cancelled"
TRAINER_CONSULT_WITHDRAWN = "trainer_consult_withdrawn"
TRAINER_INVITE_ACCEPTED = "trainer_invite_accepted"
TRAINER_INVITE_REJECTED = "trainer_invite_rejected"
TRAINER_RESERVATION_BOOKED = "trainer_reservation_booked"
TRAINER_RESERVATION_CANCELLED = "trainer_reservation_cancelled"
TRAINER_MEMBER_MESSAGE = "trainer_member_message"
#: 담당 회원이 주간 피드백(컨디션·운동 강도·통증)을 냈다(#3026).
TRAINER_MEMBER_WEEKLY_FEEDBACK = "trainer_member_weekly_feedback"

# 트레이너가 한 일로 회원이 받는 알림.
MEMBER_COACH_MESSAGE = "member_coach_message"
MEMBER_ROUTINE_ASSIGNED = "member_routine_assigned"
MEMBER_ROUTINE_PROGRAM = "member_routine_program"
MEMBER_TRAINER_CONNECTED = "member_trainer_connected"
MEMBER_COACH_INVITE = "member_coach_invite"
MEMBER_HEALTH_GOAL = "member_health_goal"
MEMBER_CONSULT_APPROVED = "member_consult_approved"
MEMBER_CONSULT_REJECTED = "member_consult_rejected"
MEMBER_CONSULT_EXPIRED = "member_consult_expired"
#: 상담 요청을 받은 트레이너가 확인하기 전에 탈퇴했다(#3241).
MEMBER_CONSULT_TRAINER_LEFT = "member_consult_trainer_left"
MEMBER_TRAINER_LEFT = "member_trainer_left"
MEMBER_TRAINER_LEFT_BOOKING = "member_trainer_left_booking"
MEMBER_TRAINER_DISCONNECTED = "member_trainer_disconnected"

# 일정·포인트 — 트레이너 일정 변경과 회원 혜택으로 회원이 받는 알림.
MEMBER_SCHEDULE_ADDED = "member_schedule_added"
MEMBER_SCHEDULE_CHANGED = "member_schedule_changed"
MEMBER_SCHEDULE_CANCELLED = "member_schedule_cancelled"
MEMBER_SCHEDULE_SERIES = "member_schedule_series"
MEMBER_COUPON_EXPIRING = "member_coupon_expiring"
MEMBER_COUPON_CANCELLED = "member_coupon_cancelled"
MEMBER_CHALLENGE_RESULT = "member_challenge_result"
#: 트레이너가 회원 PT 를 완료 처리했다 / 완료 PT 에 처음 피드백을 적었다(#3027).
MEMBER_PT_COMPLETED = "member_pt_completed"
MEMBER_PT_FEEDBACK = "member_pt_feedback"

_TEMPLATES: dict[str, _Renderer] = {}


def _template(code: str) -> Callable[[_Renderer], _Renderer]:
    def register(fn: _Renderer) -> _Renderer:
        if len(code) > 40:  # pragma: no cover — 코드를 잘못 더하면 import 때 막힌다
            raise ValueError(f"틀 코드가 40자를 넘습니다: {code}")
        _TEMPLATES[code] = fn
        return fn

    return register


def codes() -> frozenset[str]:
    """등록된 틀 코드. 테스트가 앱과 같은 집합인지 확인하는 데 쓴다."""
    return frozenset(_TEMPLATES)


# --------------------------------------------------------------------------
# 인자 조각
# --------------------------------------------------------------------------

#: 목표 한 줄의 구분자. `health_focus.FOCUS_LABEL_SEPARATOR` 와 같다.
_FOCUS_SEPARATOR = " · "


def _text(args: Args, key: str) -> str:
    """인자의 글자 값. 없거나 ``None`` 이면 빈 문자열."""
    value = args.get(key)
    return "" if value is None else str(value)


def _focus_label(args: Args) -> str:
    """건강 목표 한 줄. 저장 값(`health_focus.FOCUS_OPTIONS`)이 곧 화면 말이다."""
    focus = [str(f) for f in (args.get("focus") or [])]
    if not focus:
        return "목표 없음"
    return _FOCUS_SEPARATOR.join(focus)


def _when(args: Args, key: str = "starts_at") -> str | None:
    """서울 벽시계 시각 → `10월 1일 09:00`. 없으면 ``None``.

    날짜는 0 을 채우지 않고 시각은 24시간제(#3120).
    """
    raw = args.get(key)
    if not raw:
        return None
    moment = datetime.fromisoformat(str(raw))
    return f"{moment.month}월 {moment.day}일 {moment:%H:%M}"


def _day(raw: str) -> str:
    """`2026-10-01` → `10월 1일`. 날짜로 읽히지 않으면 받은 그대로 둔다."""
    try:
        day = date.fromisoformat(raw)
    except ValueError:
        return raw
    return f"{day.month}월 {day.day}일"


def _seconds(args: Args) -> int:
    """인자의 운동 시간(초). `seconds` 가 없는 옛 알림은 분 × 60 으로 읽는다. (#2546)"""
    seconds = args.get("seconds")
    return seconds_or_minutes(
        None if seconds is None else int(seconds), int(args.get("minutes") or 0)
    )


def _amount(args: Args) -> str:
    """배정 한 건의 양. `trainer._common._amount_label` 과 같은 문장이다."""
    sets = args.get("sets")
    reps = args.get("reps")
    hold = args.get("hold_seconds")
    weight = args.get("weight")
    if not args.get("strength") or sets is None:
        # 시간은 초까지 적는다 — `45초`·`1시간 30분`. (#2546)
        return format_duration(_seconds(args))
    parts = [f"{sets}세트"]
    if hold:
        parts.append(f"{hold}초")
    elif reps:
        parts.append(f"{reps}회")
    # 맨몸 운동(0)은 중량을 적지 않는다. (#2533)
    if weight is not None and float(weight) > 0:
        parts.append(f"{float(weight):g}kg")
    return " · ".join(parts)


# --------------------------------------------------------------------------
# 트레이너가 받는 알림
# --------------------------------------------------------------------------


@_template(TRAINER_HEALTH_GOAL)
def _trainer_health_goal(args: Args) -> Rendered:
    name = _text(args, "member_name")
    label = _focus_label(args)
    return "회원 건강 목표가 바뀌었어요", f"{name} 회원이 건강 목표를 바꿨어요: {label}"


@_template(TRAINER_HEALTH_NOTES)
def _trainer_health_notes(args: Args) -> Rendered:
    name = _text(args, "member_name")
    with_focus = bool(args.get("with_focus"))
    what = "건강 목표와 건강상태·주의사항을" if with_focus else "건강상태·주의사항을"
    return "회원 주의사항이 바뀌었어요", f"{name} 회원이 {what} 바꿨어요"


@_template(TRAINER_MEMBER_RENAMED)
def _trainer_member_renamed(args: Args) -> Rendered:
    old, new = _text(args, "old_name"), _text(args, "new_name")
    return "회원 이름이 바뀌었어요", f"{old} 회원이 이름을 바꿨어요: {new}"


@_template(TRAINER_MEMBER_WITHDRAWN)
def _trainer_member_withdrawn(args: Args) -> Rendered:
    name = _text(args, "member_name").strip()
    return "회원이 탈퇴했어요", f"{name or '이름 없는'} 회원이 탈퇴했어요."


def _cancelled_sessions(args: Args) -> int:
    """담당 해제로 함께 취소한 일정 수(#2589). 없는 옛 알림은 0 으로 읽는다."""
    try:
        return max(int(args.get("cancelled_sessions") or 0), 0)
    except (TypeError, ValueError):
        return 0


@_template(TRAINER_MEMBER_DISCONNECTED)
def _trainer_member_disconnected(args: Args) -> Rendered:
    name = _text(args, "member_name").strip()
    cancelled = _cancelled_sessions(args)
    body = f"{name or '이름 없는'} 회원이 담당 연결을 해제했어요."
    if cancelled:
        body += f" 남은 일정 {cancelled}건은 취소됐어요."
    return "담당 연결이 해제됐어요", body


@_template(TRAINER_CONSULT_REQUESTED)
def _trainer_consult_requested(args: Args) -> Rendered:
    name, day = _text(args, "member_name"), _day(_text(args, "preferred_date"))
    return "새 상담 요청이 도착했어요", f"{name or '회원'} 회원 · {day}"


@_template(TRAINER_CONSULT_CANCELLED)
def _trainer_consult_cancelled(args: Args) -> Rendered:
    name, day = _text(args, "member_name"), _day(_text(args, "preferred_date"))
    return "상담 요청이 취소됐어요", f"{name or '회원'} 회원 · {day}"


@_template(TRAINER_CONSULT_WITHDRAWN)
def _trainer_consult_withdrawn(args: Args) -> Rendered:
    # 회원이 탈퇴해 대기 중이던 요청이 함께 사라졌다(#1632). 이름이 비면 탈퇴
    # 알림(`trainer_member_withdrawn`)과 같은 말을 대신 적는다.
    name, day = _text(args, "member_name").strip(), _day(_text(args, "preferred_date"))
    return "회원 탈퇴로 상담 요청이 취소됐어요", f"{name or '이름 없는'} 회원 · {day}"


@_template(TRAINER_INVITE_ACCEPTED)
def _trainer_invite_accepted(args: Args) -> Rendered:
    name = _text(args, "member_name")
    return "담당 요청이 수락됐어요", f"{name or '회원'} 회원이 담당으로 연결됐어요."


@_template(TRAINER_INVITE_REJECTED)
def _trainer_invite_rejected(args: Args) -> Rendered:
    name = _text(args, "member_name")
    return "담당 요청이 거절됐어요", f"{name or '회원'} 회원이 담당 요청을 거절했어요."


@_template(TRAINER_RESERVATION_BOOKED)
def _trainer_reservation_booked(args: Args) -> Rendered:
    name = _text(args, "member_name")
    when = _when(args)
    return "새 예약이 들어왔어요", f"{name} 회원 · {when}"


@_template(TRAINER_RESERVATION_CANCELLED)
def _trainer_reservation_cancelled(args: Args) -> Rendered:
    name = _text(args, "member_name")
    when = _when(args)
    body = f"{name} 회원 · {when}" if when is not None else f"{name} 회원"
    return "예약이 취소됐어요", body


@_template(TRAINER_MEMBER_MESSAGE)
def _trainer_member_message(args: Args) -> Rendered:
    name = _text(args, "member_name")
    # 본문은 회원이 쓴 메시지 그대로다. 사진만 보낸 메시지는 본문이 비어 있어
    # 대신 적는 말이 있다(#1665) — 트레이너 발신 사진(#921)과 같은 규칙이다.
    photo_only = bool(args.get("photo_only"))
    return f"{name or '회원'} 회원의 메시지", "사진을 보냈어요" if photo_only else None


#: 회원 주간 피드백 저장 값 → 화면 말. 회원 앱 입력 시트의
#: `weekCondition*`·`weekIntensity*` 와 같은 말이다 — 회원이 고른 말 그대로
#: 트레이너에게 보인다(#3116). 트레이너 웹 `reportsMemberFeedback*` 도 같다.
#: 저장 값 목록은 `trainer.weekly_feedback` 의 `_WEEKLY_FEEDBACK_*` 와 같다.
_FEEDBACK_CONDITION: dict[str, str] = {
    "great": "아주 좋았어요",
    "good": "좋았어요",
    "ok": "보통이었어요",
    "tired": "지쳤어요",
    "bad": "많이 안 좋았어요",
}
_FEEDBACK_INTENSITY: dict[str, str] = {
    "too_easy": "너무 쉬웠어요",
    "right": "딱 맞았어요",
    "hard": "조금 힘들었어요",
    "too_hard": "너무 힘들었어요",
}


def _feedback_label(table: dict[str, str], value: str) -> str:
    """저장 값 → 화면 말. 모르는 값은 받은 그대로 둔다 — 사라지는 것보다 낫다."""
    return table.get(value, value)


@_template(TRAINER_MEMBER_WEEKLY_FEEDBACK)
def _trainer_member_weekly_feedback(args: Args) -> Rendered:
    """회원 주간 피드백 도착(#3026).

    통증이 있으면 제목이 달라진다 — 다음 PT 프로그램을 바꿔야 할 수 있는 답이라
    알림함에서 먼저 눈에 띄어야 한다. **아픈 곳(회원이 쓴 글)은 싣지 않는다**:
    건강 정보가 알림 미리보기에 드러나지 않게 하는 `trainer_health_notes`(#2619)와
    같은 규칙이고, 누르면 그 글이 있는 '피드백' 탭이 바로 열린다.
    """
    name = _text(args, "member_name")
    pain = bool(args.get("pain"))
    revised = bool(args.get("revised"))
    condition = _feedback_label(_FEEDBACK_CONDITION, _text(args, "condition"))
    intensity = _feedback_label(_FEEDBACK_INTENSITY, _text(args, "intensity"))
    # 빠진 값은 칸째 뺀다 — `컨디션  · ` 처럼 빈 칸이 남지 않게.
    parts: list[str] = []
    if condition:
        parts.append(f"컨디션 {condition}")
    if intensity:
        parts.append(f"운동 강도 {intensity}")
    if pain:
        parts.append("통증 있음")
    body = " · ".join(parts)
    who = f"{name} 회원이" if name else "회원이"
    if pain:
        title = f"{who} 통증을 알렸어요"
    elif revised:
        title = f"{who} 주간 피드백을 수정했어요"
    else:
        title = f"{who} 주간 피드백을 보냈어요"
    return title, body


# --------------------------------------------------------------------------
# 트레이너가 한 일로 회원이 받는 알림
# --------------------------------------------------------------------------


@_template(MEMBER_COACH_MESSAGE)
def _member_coach_message(args: Args) -> Rendered:
    name = _text(args, "trainer_name")
    report = bool(args.get("report"))
    # 사진만 보낸 메시지는 본문이 비어 있어 대신 적는 말이 있다(#921). 글이 있으면
    # 트레이너가 쓴 글 그대로다.
    photo_only = bool(args.get("photo_only"))
    title = "주간 리포트가 도착했어요" if report else f"{name or '트레이너'} 트레이너의 메시지"
    return title, "사진을 보냈어요" if photo_only else None


@_template(MEMBER_ROUTINE_ASSIGNED)
def _member_routine_assigned(args: Args) -> Rendered:
    name = _text(args, "name")
    amount = _amount(args)
    # 한 건 배정은 개인운동이다 — 회원 앱 채팅 안내(`개인운동을 받았어요`)와
    # 운동 탭 목록(`추천 개인운동`)이 같은 이름으로 부른다(#3107).
    return "새 개인운동이 왔어요", f"{name} · {amount}"


@_template(MEMBER_ROUTINE_PROGRAM)
def _member_routine_program(args: Args) -> Rendered:
    name = _text(args, "name")
    sessions = int(args.get("sessions") or 0)
    # 합계는 서버가 초로 더해 둔 값이다 — 여기서 한 번만 접는다. (#2546)
    duration = format_duration(_seconds(args))
    multi = bool(args.get("multi"))
    # `개인운동만` 을 여럿 보내면 운동 하나가 세션 하나다(#2581). 프로그램 이름
    # (예전 `이번 주 개인운동`)과 `세션 N개` 는 개인운동 묶음에 맞지 않는다.
    routine_only = bool(args.get("routine_only")) and multi
    # 미래 시작일로 보낸 개인운동(#2656) — 알림은 지금 가지만 회원 목록에는
    # 그날부터 뜬다. 제목이 그날을 말해야 오늘 열어 보고 헷갈리지 않는다.
    starts_on = _starts_on(args)
    # 제목은 무엇을 받았는지 말한다 — 개인운동이면 `개인운동`, 아니면 PT
    # 프로그램이다(#3107). `personal` 이 없는 예전 알림은 `routine_only` 로 가린다.
    personal = bool(args.get("personal")) or bool(args.get("routine_only"))
    if routine_only:
        body = f"개인운동 {sessions}개 · {duration}"
    elif multi:
        body = f"{name} · 세션 {sessions}개 · {duration}"
    else:
        body = f"{name} · {duration}"
    if starts_on is not None:
        return f"{starts_on.month}/{starts_on.day}부터 할 개인운동이 왔어요", body
    return ("새 개인운동이 왔어요" if personal else "새 PT 프로그램이 왔어요"), body


def _starts_on(args: Args) -> date | None:
    """`starts_on`(YYYY-MM-DD) → 날짜. 없거나 깨졌으면 None. (#2656)"""
    raw = args.get("starts_on")
    if not isinstance(raw, str):
        return None
    try:
        return date.fromisoformat(raw)
    except ValueError:
        return None


@_template(MEMBER_TRAINER_CONNECTED)
def _member_trainer_connected(args: Args) -> Rendered:
    name = _text(args, "trainer_name")
    return (
        "트레이너와 연결됐어요",
        f"{name or '트레이너'} 트레이너가 담당 트레이너가 됐어요. 식단·운동 기록이 공유돼요.",
    )


@_template(MEMBER_COACH_INVITE)
def _member_coach_invite(args: Args) -> Rendered:
    name = _text(args, "trainer_name")
    return (
        "담당 요청이 도착했어요",
        f"{name or '트레이너'} 트레이너가 담당 트레이너가 되기를 요청했어요.",
    )


@_template(MEMBER_HEALTH_GOAL)
def _member_health_goal(args: Args) -> Rendered:
    name = _text(args, "trainer_name")
    label = _focus_label(args)
    return "건강 목표가 바뀌었어요", f"{name} 트레이너가 건강 목표를 바꿨어요: {label}"


@_template(MEMBER_CONSULT_APPROVED)
def _member_consult_approved(args: Args) -> Rendered:
    name = _text(args, "trainer_name")
    when = _when(args)
    # 트레이너가 적은 한마디는 뒤에 그대로 붙인다. 빈 한마디도
    # 예전처럼 한 칸 띄워 붙인다 — `None` 만 "적지 않음" 이다.
    note = args.get("note")
    # 수락은 상담 일정 확정이지 담당 연결이 아니다(#2584) — 연결은 상담 뒤
    # 6자리 코드로 한다. 예전 문구("담당으로 연결되었어요")는 등록까지 끝난 것처럼 읽혔다.
    body = (
        f"{name or '트레이너'} 트레이너와의 상담이 확정됐어요. "
        f"상담 일시: {when}"
    )
    title = "상담 요청이 승인됐어요"
    return title, body if note is None else f"{body} {note}"


@_template(MEMBER_CONSULT_REJECTED)
def _member_consult_rejected(args: Args) -> Rendered:
    # 반려 사유를 적었으면 본문은 그 사유 그대로다.
    has_note = bool(args.get("has_note"))
    return (
        "상담 요청이 거절됐어요",
        None if has_note else "다른 트레이너에게 상담을 신청해 보세요.",
    )


@_template(MEMBER_CONSULT_EXPIRED)
def _member_consult_expired(args: Args) -> Rendered:
    return (
        "상담 요청이 만료됐어요",
        "트레이너가 시간 안에 확인하지 않았어요. 다른 시간으로 다시 신청해 보세요.",
    )


@_template(MEMBER_CONSULT_TRAINER_LEFT)
def _member_consult_trainer_left(args: Args) -> Rendered:
    name = _text(args, "trainer_name")
    return (
        "상담 요청이 취소되었어요",
        f"{name or '트레이너'} 트레이너가 서비스를 떠나 상담 요청이 취소되었어요. "
        "다른 트레이너에게 요청해 보세요.",
    )


@_template(MEMBER_TRAINER_LEFT)
def _member_trainer_left(args: Args) -> Rendered:
    name = _text(args, "trainer_name")
    return (
        "담당 트레이너 연결이 해제됐어요",
        f"{name or '트레이너'} 트레이너가 서비스를 떠났어요. 새 트레이너를 찾아보세요.",
    )


@_template(MEMBER_TRAINER_DISCONNECTED)
def _member_trainer_disconnected(args: Args) -> Rendered:
    """트레이너가 담당을 해제했다(#2589). 남은 PT 를 취소했으면 그 수를 함께 전한다.

    일정마다 취소 알림을 보내지 않는다 — 반복 PT 수만큼 쏟아지므로 이 한 건이 대신한다.
    """
    name = _text(args, "trainer_name").strip()
    cancelled = _cancelled_sessions(args)
    body = f"{name or '담당'} 트레이너와 담당 연결이 해제됐어요."
    if cancelled:
        body += f" 남은 PT 일정 {cancelled}건도 취소됐어요."
    return "담당 트레이너 연결이 해제됐어요", body


@_template(MEMBER_TRAINER_LEFT_BOOKING)
def _member_trainer_left_booking(args: Args) -> Rendered:
    name = _text(args, "trainer_name")
    return (
        "예약한 PT가 취소됐어요",
        f"{name or '트레이너'} 트레이너가 서비스를 떠나 예약이 취소됐어요.",
    )


# --------------------------------------------------------------------------
# PT 완료·피드백 — 트레이너가 마친 PT를 회원에게 (#3027)
# --------------------------------------------------------------------------


def _session_number(args: Args) -> int | None:
    """완료 PT 의 회차(`trainer._common._done_pt_numbers` 와 같은 번호). 없으면 ``None``."""
    try:
        n = int(args.get("session_number") or 0)
    except (TypeError, ValueError):
        return None
    return n if n > 0 else None


@_template(MEMBER_PT_COMPLETED)
def _member_pt_completed(args: Args) -> Rendered:
    """PT 완료. 본문은 트레이너 피드백이 있으면 그 글 그대로다."""
    name = _text(args, "trainer_name").strip()
    n = _session_number(args)
    has_note = bool(args.get("has_note"))
    who = f"{name or '담당'} 트레이너와"
    title = f"{who} {n}회차 PT를 마쳤어요" if n else f"{who} PT를 마쳤어요"
    return title, None if has_note else "운동 기록에 남겼어요"


@_template(MEMBER_PT_FEEDBACK)
def _member_pt_feedback(args: Args) -> Rendered:
    """완료한 PT 에 트레이너가 처음 피드백을 적었다. 본문은 그 글 그대로다."""
    return "트레이너 피드백이 도착했어요", None


# --------------------------------------------------------------------------
# 일정 — 트레이너가 잡고 바꾼 회원 일정
# --------------------------------------------------------------------------


def _slot(args: Args) -> str:
    """`10월 1일 09:00 · 1:1 PT`. 시각과 일정 종류는 저장된 모양 그대로다.

    일정 종류 저장 값은 트레이너 웹 `SessionType` 과 같다.
    """
    return f"{_day(_text(args, 'date'))} {_text(args, 'time')} · {_text(args, 'type')}"


@_template(MEMBER_SCHEDULE_ADDED)
def _member_schedule_added(args: Args) -> Rendered:
    return "새 일정이 등록됐어요", _slot(args)


@_template(MEMBER_SCHEDULE_CHANGED)
def _member_schedule_changed(args: Args) -> Rendered:
    return "일정이 변경됐어요", _slot(args)


@_template(MEMBER_SCHEDULE_CANCELLED)
def _member_schedule_cancelled(args: Args) -> Rendered:
    return "일정이 취소됐어요", _slot(args)


@_template(MEMBER_SCHEDULE_SERIES)
def _member_schedule_series(args: Args) -> Rendered:
    time = _text(args, "time")
    first, last = _day(_text(args, "first")), _day(_text(args, "last"))
    count = int(args["count"])
    return "반복 일정이 등록됐어요", f"{first} ~ {last} · {time} · {count}회"


# --------------------------------------------------------------------------
# 포인트 — 쿠폰과 주간 챌린지
# --------------------------------------------------------------------------

#: 취소된 쿠폰의 제목. 항목마다 다르다.
_COUPON_CANCELLED_TITLE: dict[str, str] = {
    "pt_renewal": "PT 재등록 할인 쿠폰이 취소됐어요",
    "diet_tray": "식판 수령 쿠폰이 취소됐어요",
    "locker_month": "개인 락커 쿠폰이 취소됐어요",
}

#: 쿠폰이 취소된 까닭 코드 → 문장 앞말.
_COUPON_CANCEL_REASON: dict[str, str] = {
    "trainer": "담당 트레이너 연결이 해제되어",
    "gym": "헬스장 연결이 해제되어",
    # 헬스장 혜택 제공을 멈춤(#2822) — `scripts/cancel_gym_benefit_coupons.py`.
    "service": "헬스장 혜택 제공을 잠시 멈추게 되어",
}


def _benefit(args: Args) -> str:
    """혜택 이름 — 교환 당시 문구(`benefit` 인자)다."""
    return _text(args, "benefit")


@_template(MEMBER_COUPON_EXPIRING)
def _member_coupon_expiring(args: Args) -> Rendered:
    benefit = _benefit(args)
    days = int(args["days"])
    last_day = date.fromisoformat(str(args["last_day"]))
    when = (
        f"{benefit} 쿠폰은 오늘까지 쓸 수 있어요."
        if days == 0
        else f"{benefit} 쿠폰이 {days}일 뒤({last_day.month}월 {last_day.day}일) 만료돼요."
    )
    return "쿠폰이 곧 만료돼요", f"{when} 만료되면 포인트는 돌려받을 수 없어요."


@_template(MEMBER_COUPON_CANCELLED)
def _member_coupon_cancelled(args: Args) -> Rendered:
    ko_title = _COUPON_CANCELLED_TITLE[_text(args, "item")]
    ko_reason = _COUPON_CANCEL_REASON[_text(args, "reason")]
    benefit = _benefit(args)
    refunded = args.get("refunded")
    if refunded is None:
        return ko_title, f"{ko_reason} {benefit} 쿠폰을 취소했어요."
    return ko_title, f"{ko_reason} {benefit} 쿠폰을 취소하고 {int(refunded):,}P를 돌려드렸어요."


@_template(MEMBER_CHALLENGE_RESULT)
def _member_challenge_result(args: Args) -> Rendered:
    start = date.fromisoformat(str(args["week_start"]))
    end = start + timedelta(days=6)
    goal, reward = int(args["goal"]), int(args["reward"])
    succeeded = bool(args["succeeded"])
    period = f"{start.month}월 {start.day}일 ~ {end.month}월 {end.day}일"
    if succeeded:
        return (
            f"주간 챌린지 성공! {reward:,}P를 받았어요",
            f"{period} 목표 {goal}회를 채워 {reward:,}P를 돌려받았어요.",
        )
    return (
        "주간 챌린지 목표를 채우지 못했어요",
        f"{period} 목표 {goal}회 중 {int(args['days'])}회 운동해 "
        f"건 {int(args['stake']):,}P는 사라졌어요. "
        "다음 주 월·화요일에 다시 참가할 수 있어요.",
    )


# --------------------------------------------------------------------------
# 만들기·읽기
# --------------------------------------------------------------------------


def render(code: str | None, args: Args | None) -> Rendered | None:
    """틀을 문장으로 조립한다. 모르는 틀이거나 인자가 깨졌으면 ``None``.

    저장된 틀·인자가 저장된 문장과 같은 말을 내는지 확인하는 데 쓴다.
    """
    if not code:
        return None
    renderer = _TEMPLATES.get(code)
    if renderer is None:
        return None
    try:
        return renderer(args or {})
    except (TypeError, ValueError, AttributeError, KeyError):
        return None


def columns(code: str, args: Args, *, body: str = "") -> dict[str, Any]:
    """새 알림 행에 넣을 `title`·`body`·`template`·`template_args`.

    `title`·`body` 는 틀이 조립한 문장이다. 틀의 본문이 ``None``(사람이 쓴 글)이면
    [body] 를 그대로 쓴다.

    모르는 틀이면 ``ValueError`` — 저장만 되고 아무도 조립하지 못하는 알림을 만들지
    않게, 만드는 쪽에서 바로 드러낸다.
    """
    if code not in _TEMPLATES:
        raise ValueError(f"등록되지 않은 알림 틀: {code}")
    stored_args = dict(args)
    title, rendered_body = _TEMPLATES[code](stored_args)
    return {
        "title": title,
        "body": body if rendered_body is None else rendered_body,
        "template": code,
        "template_args": stored_args,
    }
