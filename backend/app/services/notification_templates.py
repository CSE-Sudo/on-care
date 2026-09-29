"""알림 문장 틀 — 코드와 인자로 저장하고 읽는 쪽 언어로 조립한다. (#2302)

알림은 만든 순간의 한국어 문장(`Notification.title`·`body`)만 저장했다. 영어 화면을
고른 트레이너·회원도 알림함에서는 한국어를 읽었다 — 문장이 DB 에 박혀 있어 요청
언어(`Accept-Language`)를 알아도 바꿀 수 없었다.

**저장**: 알림을 만들 때 틀 코드(`template`)와 인자(`template_args`)를 함께 남긴다.
`title`·`body` 에는 지금까지와 **바이트 단위로 같은** 한국어 문장을 계속 적는다 —
틀을 모르는 옛 앱·푸시·틀이 생기기 전의 알림이 그 문장을 그대로 쓴다.

**읽기**: 규칙은 하나다 — *저장된 틀과 인자를 읽는 쪽 언어로 조립하고, 조립할 수
없으면 저장된 문장을 쓴다.*

- 트레이너 웹은 응답의 `template`·`args` 로 ARB 문장을 직접 조립한다(앱이 문구의
  주인이다). 앱이 모르는 틀이면 응답의 `title`·`body` 를 쓴다.
- 회원 앱은 알림 문구를 서버에서 받아 그대로 그린다. 그래서 목록 API 가 요청 언어로
  조립한 `title`·`body` 를 준다([localize]). 트레이너 목록도 같은 값을 주므로, 새 틀을
  아직 모르는 트레이너 웹 빌드도 알맞은 언어로 보인다.
- 한국어는 조립하지 않고 **저장된 문장을 그대로** 준다. 틀 문구를 나중에 다듬어도
  이미 받은 알림은 받은 순간의 문장으로 남는다(`name_change` 의 원칙과 같다).

인자에는 **언어와 무관한 값**만 담는다 — 이름·날짜·수량·건강 목표 저장 값. 회원이나
트레이너가 직접 쓴 글(메시지 본문·반려 사유)은 번역할 수 없으므로 저장된 `body` 를
그대로 쓴다(렌더러가 본문으로 ``None`` 을 돌려준다).
"""
from __future__ import annotations

from collections.abc import Callable, Mapping
from datetime import date, datetime, timedelta
from typing import Any

from app.core.locale import Locale, current_locale
from app.services.exercise_duration import format_duration, seconds_or_minutes

Args = Mapping[str, Any]
#: (제목, 본문). 본문이 ``None`` 이면 저장된 본문을 그대로 쓴다.
Rendered = tuple[str, "str | None"]
_Renderer = Callable[[Args, Locale], Rendered]

# --------------------------------------------------------------------------
# 틀 코드. `notifications.template` 이 `String(40)` 이라 40자를 넘기면 안 된다.
# 트레이너 웹(`trainer_notification_text.dart`)이 같은 코드를 읽는다 — 이름을
# 바꾸면 이미 저장된 알림이 저장된 한국어로 되돌아간다.
# --------------------------------------------------------------------------

# 트레이너가 받는 알림.
TRAINER_HEALTH_GOAL = "trainer_health_goal"
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

#: 건강 목표 저장 값(`health_focus.FOCUS_OPTIONS`) → 영어. 트레이너 웹·회원 앱
#: ARB 의 `healthFocus*` 영어 문구와 같다. 저장 값이 한국어라 한국어는 그대로 쓴다.
_FOCUS_EN: dict[str, str] = {
    "체중 감량": "Weight loss",
    "근력 향상": "Build strength",
    "체력 강화": "Improve fitness",
    "자세 교정": "Posture correction",
    "재활": "Rehab",
    "식습관 개선": "Better eating habits",
    "운동 습관": "Exercise habit",
    "혈압 관리": "Blood pressure care",
}

#: 목표 한 줄의 구분자. `health_focus.FOCUS_LABEL_SEPARATOR` 와 같다.
_FOCUS_SEPARATOR = " · "


def _text(args: Args, key: str) -> str:
    """인자의 글자 값. 없거나 ``None`` 이면 빈 문자열."""
    value = args.get(key)
    return "" if value is None else str(value)


def _focus_label(args: Args, locale: Locale) -> str:
    focus = [str(f) for f in (args.get("focus") or [])]
    if not focus:
        return "목표 없음" if locale == "ko" else "none"
    if locale == "ko":
        return _FOCUS_SEPARATOR.join(focus)
    # 모르는 값(옛 질환명 등)은 받은 그대로 둔다 — 사라지는 것보다 낫다.
    return _FOCUS_SEPARATOR.join(_FOCUS_EN.get(f, f) for f in focus)


def _when(args: Args, locale: Locale, key: str = "starts_at") -> str | None:
    """서울 벽시계 시각 → `10월 01일 09:00` / `10/01 09:00`. 없으면 ``None``."""
    raw = args.get(key)
    if not raw:
        return None
    moment = datetime.fromisoformat(str(raw))
    if locale == "ko":
        return f"{moment:%m월 %d일 %H:%M}"
    return f"{moment:%m/%d %H:%M}"


def _plural(n: int, one: str, many: str) -> str:
    return f"{n} {one if n == 1 else many}"


def _seconds(args: Args) -> int:
    """인자의 운동 시간(초). `seconds` 가 없는 옛 알림은 분 × 60 으로 읽는다. (#2546)"""
    seconds = args.get("seconds")
    return seconds_or_minutes(
        None if seconds is None else int(seconds), int(args.get("minutes") or 0)
    )


def _amount(args: Args, locale: Locale) -> str:
    """배정 한 건의 양. 한국어는 `trainer_service._amount_label` 과 같은 문장이다."""
    sets = args.get("sets")
    reps = args.get("reps")
    hold = args.get("hold_seconds")
    weight = args.get("weight")
    if not args.get("strength") or sets is None:
        # 시간은 초까지 적는다 — `45초`·`1 hr 30 min`. (#2546)
        return format_duration(_seconds(args), locale)
    if locale == "ko":
        parts = [f"{sets}세트"]
        if hold:
            parts.append(f"{hold}초")
        elif reps:
            parts.append(f"{reps}회")
        # 맨몸 운동(0)은 중량을 적지 않는다 — 두 언어가 같다. (#2533)
        if weight is not None and float(weight) > 0:
            parts.append(f"{float(weight):g}kg")
        return " · ".join(parts)
    parts = [_plural(int(sets), "set", "sets")]
    if hold:
        parts.append(f"{hold} sec")
    elif reps:
        parts.append(_plural(int(reps), "rep", "reps"))
    if weight is not None and float(weight) > 0:
        parts.append(f"{float(weight):g} kg")
    return " · ".join(parts)


# --------------------------------------------------------------------------
# 트레이너가 받는 알림
# --------------------------------------------------------------------------


@_template(TRAINER_HEALTH_GOAL)
def _trainer_health_goal(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "member_name")
    label = _focus_label(args, locale)
    if locale == "ko":
        return "회원 건강 목표 변경", f"{name} 회원이 건강 목표를 바꿨어요: {label}"
    return "Member goals changed", f"{name or 'A member'} changed their health goals: {label}"


@_template(TRAINER_MEMBER_RENAMED)
def _trainer_member_renamed(args: Args, locale: Locale) -> Rendered:
    old, new = _text(args, "old_name"), _text(args, "new_name")
    if locale == "ko":
        return "회원 이름 변경", f"{old} 회원이 이름을 바꿨어요: {new}"
    return "Member renamed", f"{old} changed their name to {new}."


@_template(TRAINER_MEMBER_WITHDRAWN)
def _trainer_member_withdrawn(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "member_name").strip()
    if locale == "ko":
        return "회원 탈퇴", f"{name or '이름 없는'} 회원이 탈퇴했어요."
    return "Member account deleted", f"{name or 'A member'} deleted their account."


def _cancelled_sessions(args: Args) -> int:
    """담당 해제로 함께 취소한 일정 수(#2589). 없는 옛 알림은 0 으로 읽는다."""
    try:
        return max(int(args.get("cancelled_sessions") or 0), 0)
    except (TypeError, ValueError):
        return 0


@_template(TRAINER_MEMBER_DISCONNECTED)
def _trainer_member_disconnected(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "member_name").strip()
    cancelled = _cancelled_sessions(args)
    if locale == "ko":
        body = f"{name or '이름 없는'} 회원이 담당 연결을 끊었어요."
        if cancelled:
            body += f" 남은 일정 {cancelled}건은 취소됐어요."
        return "담당 연결 해제", body
    body = f"{name or 'A member'} ended their connection with you."
    if cancelled:
        body += (
            f" {_plural(cancelled, 'remaining session was', 'remaining sessions were')}"
            " cancelled."
        )
    return "Client disconnected", body


@_template(TRAINER_CONSULT_REQUESTED)
def _trainer_consult_requested(args: Args, locale: Locale) -> Rendered:
    name, day = _text(args, "member_name"), _text(args, "preferred_date")
    if locale == "ko":
        return "새 상담 요청이 도착했어요", f"{name or '회원'} 회원 · {day}"
    return "New consultation request", f"{name or 'Member'} · {day}"


@_template(TRAINER_CONSULT_CANCELLED)
def _trainer_consult_cancelled(args: Args, locale: Locale) -> Rendered:
    name, day = _text(args, "member_name"), _text(args, "preferred_date")
    if locale == "ko":
        return "상담 요청이 취소됐어요", f"{name or '회원'} 회원 · {day}"
    return "Consultation request cancelled", f"{name or 'Member'} · {day}"


@_template(TRAINER_CONSULT_WITHDRAWN)
def _trainer_consult_withdrawn(args: Args, locale: Locale) -> Rendered:
    # 회원이 탈퇴해 대기 중이던 요청이 함께 사라졌다(#1632). 이름이 비면 탈퇴
    # 알림(`trainer_member_withdrawn`)과 같은 말을 대신 적는다.
    name, day = _text(args, "member_name").strip(), _text(args, "preferred_date")
    if locale == "ko":
        return "회원 탈퇴로 상담 요청이 취소됐어요", f"{name or '이름 없는'} 회원 · {day}"
    return (
        "Consultation request cancelled: member account deleted",
        f"{name or 'A member'} · {day}",
    )


@_template(TRAINER_INVITE_ACCEPTED)
def _trainer_invite_accepted(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "member_name")
    if locale == "ko":
        return "담당 요청이 수락되었어요", f"{name or '회원'} 회원이 담당으로 연결되었어요."
    return "Coaching request accepted", f"{name or 'A member'} is now your client."


@_template(TRAINER_INVITE_REJECTED)
def _trainer_invite_rejected(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "member_name")
    if locale == "ko":
        return "담당 요청이 거절되었어요", f"{name or '회원'} 회원이 담당 요청을 거절했어요."
    return "Coaching request declined", f"{name or 'A member'} declined your coaching request."


@_template(TRAINER_RESERVATION_BOOKED)
def _trainer_reservation_booked(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "member_name")
    when = _when(args, locale)
    if locale == "ko":
        return "새 예약이 들어왔어요", f"{name} 회원 · {when}"
    return "New booking", f"{name or 'Member'} · {when}"


@_template(TRAINER_RESERVATION_CANCELLED)
def _trainer_reservation_cancelled(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "member_name")
    when = _when(args, locale)
    if locale == "ko":
        body = f"{name} 회원 · {when}" if when is not None else f"{name} 회원"
        return "예약이 취소되었습니다", body
    who = name or "Member"
    return "Booking cancelled", f"{who} · {when}" if when is not None else who


@_template(TRAINER_MEMBER_MESSAGE)
def _trainer_member_message(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "member_name")
    # 본문은 회원이 쓴 메시지 그대로다. 사진만 보낸 메시지는 본문이 비어 있어
    # 대신 적는 말이 있다(#1665) — 트레이너 발신 사진(#921)과 같은 규칙이다.
    photo_only = bool(args.get("photo_only"))
    if locale == "ko":
        return f"{name or '회원'} 회원의 메시지", "사진을 보냈어요" if photo_only else None
    return f"Message from {name or 'a member'}", "Sent a photo" if photo_only else None


# --------------------------------------------------------------------------
# 트레이너가 한 일로 회원이 받는 알림
# --------------------------------------------------------------------------


@_template(MEMBER_COACH_MESSAGE)
def _member_coach_message(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "trainer_name")
    report = bool(args.get("report"))
    # 사진만 보낸 메시지는 본문이 비어 있어 대신 적는 말이 있다(#921). 글이 있으면
    # 트레이너가 쓴 글 그대로다.
    photo_only = bool(args.get("photo_only"))
    if locale == "ko":
        title = "주간 리포트가 도착했어요" if report else f"{name or '트레이너'} 트레이너의 메시지"
        return title, "사진을 보냈어요" if photo_only else None
    title = "Your weekly report is here" if report else f"Message from {name or 'your trainer'}"
    return title, "Sent a photo" if photo_only else None


@_template(MEMBER_ROUTINE_ASSIGNED)
def _member_routine_assigned(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "name")
    amount = _amount(args, locale)
    if locale == "ko":
        return "새 운동 루틴이 배정되었어요", f"{name} · {amount}"
    return "New workout routine assigned", f"{name} · {amount}"


@_template(MEMBER_ROUTINE_PROGRAM)
def _member_routine_program(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "name")
    sessions = int(args.get("sessions") or 0)
    # 합계는 서버가 초로 더해 둔 값이다 — 여기서 한 번만 접는다. (#2546)
    duration = format_duration(_seconds(args), locale)
    multi = bool(args.get("multi"))
    if locale == "ko":
        body = (
            f"{name} · 세션 {sessions}개 · {duration}" if multi else f"{name} · {duration}"
        )
        return "새 운동 루틴이 배정되었어요", body
    body = (
        f"{name} · {_plural(sessions, 'session', 'sessions')} · {duration}"
        if multi
        else f"{name} · {duration}"
    )
    return "New workout routine assigned", body


@_template(MEMBER_TRAINER_CONNECTED)
def _member_trainer_connected(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "trainer_name")
    if locale == "ko":
        return (
            "트레이너와 연결됐어요",
            f"{name or '트레이너'} 트레이너가 담당 코치가 됐어요. 식단·운동 기록이 공유돼요.",
        )
    return (
        "Connected with a trainer",
        f"{name or 'Your trainer'} is now your coach. Your meal and workout logs are shared.",
    )


@_template(MEMBER_COACH_INVITE)
def _member_coach_invite(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "trainer_name")
    if locale == "ko":
        return (
            "담당 요청이 도착했어요",
            f"{name or '트레이너'} 트레이너가 담당 코치가 되기를 요청했어요.",
        )
    return "Coaching request received", f"{name or 'A trainer'} wants to be your coach."


@_template(MEMBER_HEALTH_GOAL)
def _member_health_goal(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "trainer_name")
    label = _focus_label(args, locale)
    if locale == "ko":
        return "건강 목표가 바뀌었어요", f"{name} 트레이너님이 건강 목표를 바꿨어요: {label}"
    return (
        "Your health goals changed",
        f"{name or 'Your trainer'} changed your health goals: {label}",
    )


@_template(MEMBER_CONSULT_APPROVED)
def _member_consult_approved(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "trainer_name")
    when = _when(args, locale)
    # 트레이너가 적은 한마디는 번역하지 않고 뒤에 그대로 붙인다. 빈 한마디도
    # 예전처럼 한 칸 띄워 붙인다 — `None` 만 "적지 않음" 이다.
    note = args.get("note")
    if locale == "ko":
        body = (
            f"{name or '트레이너'} 트레이너가 담당으로 연결되었어요. "
            f"첫 상담은 {when} 입니다."
        )
    else:
        body = (
            f"You're now connected with {name or 'your trainer'}. "
            f"Your first consultation is on {when}."
        )
    title = "상담 요청이 승인되었어요" if locale == "ko" else "Consultation request approved"
    return title, body if note is None else f"{body} {note}"


@_template(MEMBER_CONSULT_REJECTED)
def _member_consult_rejected(args: Args, locale: Locale) -> Rendered:
    # 반려 사유를 적었으면 본문은 그 사유 그대로다.
    has_note = bool(args.get("has_note"))
    if locale == "ko":
        return (
            "상담 요청이 반려되었어요",
            None if has_note else "다른 트레이너에게 상담을 요청해 보세요.",
        )
    return (
        "Consultation request declined",
        None if has_note else "Try requesting a consultation with another trainer.",
    )


@_template(MEMBER_CONSULT_EXPIRED)
def _member_consult_expired(args: Args, locale: Locale) -> Rendered:
    if locale == "ko":
        return (
            "상담 신청이 만료되었어요",
            "트레이너가 시간 안에 확인하지 않았어요. 다른 시간으로 다시 신청해 보세요.",
        )
    return (
        "Consultation request expired",
        "The trainer didn't respond in time. Try requesting a different time.",
    )


@_template(MEMBER_TRAINER_LEFT)
def _member_trainer_left(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "trainer_name")
    if locale == "ko":
        return (
            "담당 트레이너 연결이 해제되었어요",
            f"{name or '트레이너'} 트레이너가 서비스를 떠났습니다. 새 트레이너를 찾아보세요.",
        )
    return (
        "Your trainer connection ended",
        f"{name or 'Your trainer'} has left the service. Find a new trainer.",
    )


@_template(MEMBER_TRAINER_DISCONNECTED)
def _member_trainer_disconnected(args: Args, locale: Locale) -> Rendered:
    """트레이너가 담당을 해제했다(#2589). 남은 PT 를 취소했으면 그 수를 함께 전한다.

    일정마다 취소 알림을 보내지 않는다 — 반복 PT 수만큼 쏟아지므로 이 한 건이 대신한다.
    """
    name = _text(args, "trainer_name").strip()
    cancelled = _cancelled_sessions(args)
    if locale == "ko":
        body = f"{name or '담당'} 트레이너와 담당 연결이 끊어졌어요."
        if cancelled:
            body += f" 남은 PT 일정 {cancelled}건도 취소됐어요."
        return "담당 트레이너 연결 해제", body
    body = f"Your connection with {name or 'your trainer'} has ended."
    if cancelled:
        body += (
            f" {_plural(cancelled, 'remaining PT session was', 'remaining PT sessions were')}"
            " cancelled too."
        )
    return "Trainer connection ended", body


@_template(MEMBER_TRAINER_LEFT_BOOKING)
def _member_trainer_left_booking(args: Args, locale: Locale) -> Rendered:
    name = _text(args, "trainer_name")
    if locale == "ko":
        return (
            "예약한 수업이 취소되었어요",
            f"{name or '트레이너'} 트레이너가 서비스를 떠나 예약이 취소되었습니다.",
        )
    return (
        "Your booked session was cancelled",
        f"{name or 'Your trainer'} left the service, so your booking was cancelled.",
    )


# --------------------------------------------------------------------------
# 일정 — 트레이너가 잡고 바꾼 회원 일정
# --------------------------------------------------------------------------

#: 일정 종류 저장 값 → 영어. 저장 값은 트레이너 웹 `SessionType` 과 같다. 모르는
#: 값(트레이너가 직접 적은 종류)은 받은 그대로 둔다.
_SESSION_TYPE_EN: dict[str, str] = {
    "1:1 PT": "1:1 PT",
    "상담": "Consultation",
}


def _slot(args: Args, locale: Locale) -> str:
    """`2026-10-01 09:00 · 1:1 PT`. 날짜·시각은 저장된 모양 그대로다."""
    type_ = _text(args, "type")
    if locale != "ko":
        type_ = _SESSION_TYPE_EN.get(type_, type_)
    return f"{_text(args, 'date')} {_text(args, 'time')} · {type_}"


@_template(MEMBER_SCHEDULE_ADDED)
def _member_schedule_added(args: Args, locale: Locale) -> Rendered:
    title = "새 일정이 등록되었어요" if locale == "ko" else "New session scheduled"
    return title, _slot(args, locale)


@_template(MEMBER_SCHEDULE_CHANGED)
def _member_schedule_changed(args: Args, locale: Locale) -> Rendered:
    title = "일정이 변경되었어요" if locale == "ko" else "Session rescheduled"
    return title, _slot(args, locale)


@_template(MEMBER_SCHEDULE_CANCELLED)
def _member_schedule_cancelled(args: Args, locale: Locale) -> Rendered:
    title = "일정이 취소되었어요" if locale == "ko" else "Session cancelled"
    return title, _slot(args, locale)


@_template(MEMBER_SCHEDULE_SERIES)
def _member_schedule_series(args: Args, locale: Locale) -> Rendered:
    first, last, time = _text(args, "first"), _text(args, "last"), _text(args, "time")
    count = int(args["count"])
    if locale == "ko":
        return "반복 일정이 등록되었어요", f"{first} ~ {last} · {time} · {count}회"
    return (
        "Recurring sessions scheduled",
        f"{first} ~ {last} · {time} · {_plural(count, 'session', 'sessions')}",
    )


# --------------------------------------------------------------------------
# 포인트 — 쿠폰과 주간 챌린지
# --------------------------------------------------------------------------

#: 쿠폰 항목 id → 영어 혜택 이름. 한국어는 인자 `benefit`(교환 당시 문구)을 쓴다.
#: 모르는 항목은 저장된 한국어 문구로 돌아간다.
_BENEFIT_EN: dict[str, str] = {
    "pt_renewal": "₩30,000 off PT re-registration",
    "locker_month": "free personal locker for 1 month",
    "diet_tray": "standard meal tray for photo analysis",
}

#: 취소된 쿠폰의 제목. 항목마다 다르다.
_COUPON_CANCELLED_TITLE: dict[str, tuple[str, str]] = {
    "pt_renewal": ("재등록 쿠폰이 취소됐어요", "PT re-registration coupon cancelled"),
    "diet_tray": ("식판 수령 쿠폰이 취소됐어요", "Meal tray coupon cancelled"),
    "locker_month": ("락커 쿠폰이 취소됐어요", "Locker coupon cancelled"),
}

#: 쿠폰이 취소된 까닭 코드 → (한국어 앞말, 영어 까닭).
_COUPON_CANCEL_REASON: dict[str, tuple[str, str]] = {
    "trainer": ("담당 트레이너 연결이 해제되어", "your trainer connection ended"),
    "gym": ("헬스장 연결이 해제되어", "your gym connection ended"),
}


def _benefit(args: Args, locale: Locale) -> str:
    benefit = _text(args, "benefit")
    if locale == "ko":
        return benefit
    return _BENEFIT_EN.get(_text(args, "item"), benefit)


@_template(MEMBER_COUPON_EXPIRING)
def _member_coupon_expiring(args: Args, locale: Locale) -> Rendered:
    benefit = _benefit(args, locale)
    days = int(args["days"])
    last_day = date.fromisoformat(str(args["last_day"]))
    if locale == "ko":
        when = (
            f"{benefit} 쿠폰은 오늘까지 쓸 수 있어요."
            if days == 0
            else f"{benefit} 쿠폰이 {days}일 뒤({last_day.month}월 {last_day.day}일) 만료돼요."
        )
        return "쿠폰이 곧 만료돼요", f"{when} 만료되면 포인트는 돌려받을 수 없어요."
    when = (
        f"Your {benefit} coupon expires today."
        if days == 0
        else (
            f"Your {benefit} coupon expires in {_plural(days, 'day', 'days')} "
            f"({last_day.month}/{last_day.day})."
        )
    )
    return (
        "Coupon expiring soon",
        f"{when} Points can't be refunded once it expires.",
    )


@_template(MEMBER_COUPON_CANCELLED)
def _member_coupon_cancelled(args: Args, locale: Locale) -> Rendered:
    ko_title, en_title = _COUPON_CANCELLED_TITLE[_text(args, "item")]
    ko_reason, en_reason = _COUPON_CANCEL_REASON[_text(args, "reason")]
    benefit = _benefit(args, locale)
    refunded = args.get("refunded")
    if locale == "ko":
        if refunded is None:
            return ko_title, f"{ko_reason} {benefit} 쿠폰을 취소했어요."
        return ko_title, f"{ko_reason} {benefit} 쿠폰을 취소하고 {int(refunded):,}P를 돌려드렸어요."
    body = f"Your {benefit} coupon was cancelled because {en_reason}."
    if refunded is not None:
        body += f" We refunded {int(refunded):,}P."
    return en_title, body


@_template(MEMBER_CHALLENGE_RESULT)
def _member_challenge_result(args: Args, locale: Locale) -> Rendered:
    start = date.fromisoformat(str(args["week_start"]))
    end = start + timedelta(days=6)
    goal, reward = int(args["goal"]), int(args["reward"])
    succeeded = bool(args["succeeded"])
    if locale == "ko":
        period = f"{start.month}월 {start.day}일~{end.month}월 {end.day}일"
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
    period = f"{start.month}/{start.day}–{end.month}/{end.day}"
    if succeeded:
        return (
            f"Weekly challenge complete! You earned {reward:,}P",
            f"You reached your goal of {_plural(goal, 'workout', 'workouts')} "
            f"for {period} and got {reward:,}P back.",
        )
    return (
        "Weekly challenge goal not reached",
        f"You logged {int(args['days'])} of {_plural(goal, 'workout', 'workouts')} "
        f"for {period}, "
        f"so the {int(args['stake']):,}P you staked is gone. "
        "You can join again next Monday or Tuesday.",
    )


# --------------------------------------------------------------------------
# 만들기·읽기
# --------------------------------------------------------------------------


def render(code: str | None, args: Args | None, locale: Locale) -> Rendered | None:
    """틀을 [locale] 로 조립한다. 모르는 틀이거나 인자가 깨졌으면 ``None``.

    ``None`` 이면 호출부가 저장된 문장을 쓴다 — 깨진 인자 하나가 알림 목록 전체를
    500 으로 만들면 안 된다.
    """
    if not code:
        return None
    renderer = _TEMPLATES.get(code)
    if renderer is None:
        return None
    try:
        return renderer(args or {}, locale)
    except (TypeError, ValueError, AttributeError, KeyError):
        return None


def columns(code: str, args: Args, *, body: str = "") -> dict[str, Any]:
    """새 알림 행에 넣을 `title`·`body`·`template`·`template_args`.

    `title`·`body` 는 한국어로 조립한다 — 지금까지 저장하던 문장과 같다. 틀의 본문이
    ``None``(사람이 쓴 글)이면 [body] 를 그대로 쓴다.

    모르는 틀이면 ``ValueError`` — 저장만 되고 아무도 조립하지 못하는 알림을 만들지
    않게, 만드는 쪽에서 바로 드러낸다.
    """
    if code not in _TEMPLATES:
        raise ValueError(f"등록되지 않은 알림 틀: {code}")
    stored_args = dict(args)
    title, rendered_body = _TEMPLATES[code](stored_args, "ko")
    return {
        "title": title,
        "body": body if rendered_body is None else rendered_body,
        "template": code,
        "template_args": stored_args,
    }


def localize(
    *,
    title: str,
    body: str,
    template: str | None,
    template_args: Args | None,
    locale: Locale | None = None,
) -> tuple[str, str]:
    """목록 응답에 실을 제목·본문. [locale] 을 생략하면 요청 언어다.

    - 한국어는 저장된 문장을 그대로 준다(받은 순간의 문장).
    - 틀이 없는(옛) 알림, 모르는 틀, 인자가 깨진 틀도 저장된 문장이다.
    - 틀의 본문이 ``None`` 이면 본문은 저장된 것 그대로다(사람이 쓴 글).
    """
    lang = locale or current_locale()
    if lang == "ko":
        return title, body
    rendered = render(template, template_args, lang)
    if rendered is None:
        return title, body
    new_title, new_body = rendered
    return new_title, body if new_body is None else new_body
