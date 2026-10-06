"""트레이너 도메인 — 채팅(트레이너↔회원, 양방향 공유 스레드)."""
from __future__ import annotations

import json
import uuid
from collections.abc import Sequence
from datetime import datetime, timezone

from sqlalchemy import func, select, tuple_, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.core.locale import current_locale
from app.models.models import (
    ChatMessage, Notification,
    TrainerClient, TrainerSchedule,
    User,
)
from app.schemas.trainer_api import (
    ChatAttachmentOut, ChatMessageOut, RoutineDeliveryCardOut,
)
from app.services import (
    data_consent_service,
    notification_service,
    notification_templates,
    schedule_parse,
)
from app.services.coach import personal_ingest
from app.services.trainer._common import (
    IdempotencyConflict,
    _iso,
)


# ---- 채팅 (트레이너↔회원, 양방향 공유 스레드) ----


def _hhmm(ts: datetime) -> str:
    """created_at → KST HH:MM."""
    return clock.to_seoul(ts).strftime("%H:%M")


def _sender_out(sender: str, viewer: str = "trainer") -> str:
    """저장값(trainer|member) → 뷰어 관점 라벨.

    트레이너 앱: 상대(member)는 'client'. 회원 앱: 자신(member)은 'me', 트레이너는 'trainer'.
    """
    if viewer == "member":
        return "me" if sender == "member" else "trainer"
    return "client" if sender == "member" else "trainer"


def build_chat_thread(
    db: Session, trainer_id: str, member_id: str,
    limit: int = 50, before: datetime | None = None, before_id: str | None = None,
    viewer: str = "trainer",
) -> list[ChatMessageOut]:
    """(trainer, member) 스레드 메시지(오래된→최신).

    무제한 로드를 막기 위해 기본 최신 `limit`건만 가져온다(리뷰 PR 251-#3). 이전 페이지는
    가장 오래된 메시지의 (created_at, id)를 (before, before_id) 커서로 넘겨 요청한다.
    같은 created_at 이 여러 건이어도 누락되지 않도록 (created_at, id) 복합 커서를 쓴다
    (리뷰 재-#1). 응답의 created_at 으로 클라이언트가 다음 커서를 만든다.
    """
    q = select(ChatMessage).where(
        ChatMessage.trainer_id == trainer_id, ChatMessage.member_id == member_id
    )
    if before is not None:
        if before_id is not None:
            # (created_at, id) < (before, before_id) — 동일 created_at 경계도 안전하게 통과
            q = q.where(
                tuple_(ChatMessage.created_at, ChatMessage.id) < (before, before_id)
            )
        else:
            q = q.where(ChatMessage.created_at < before)
    rows = list(db.scalars(
        q.order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc()).limit(limit)
    ).all())
    rows.reverse()  # 최신 limit건을 오래된→최신 순으로
    return [
        chat_message_out(r, viewer)
        for r in rows
    ]


def chat_message_out(msg: ChatMessage, viewer: str) -> ChatMessageOut:
    attachment = None
    if msg.attachment_type in ("pdf", "image") and msg.attachment_file_id:
        # 이름이 없는 첨부도 화면에는 무언가 적혀야 한다 — 종류별 기본값을 준다.
        fallback = (
            "weekly-report.pdf" if msg.attachment_type == "pdf" else "사진"
        )
        attachment = ChatAttachmentOut(
            type=msg.attachment_type,
            file_name=msg.attachment_file_name or fallback,
            file_id=msg.attachment_file_id,
            file_size=msg.attachment_file_size or 0,
            download_path=f"/chat/attachments/{msg.attachment_file_id}",
        )
    return ChatMessageOut(
        id=msg.id,
        sender=_sender_out(msg.sender, viewer),
        body=msg.body,
        time_label=_hhmm(msg.created_at),
        created_at=_iso(msg.created_at),
        attachment=attachment,
        emote_id=msg.emote_id,
        report_week_start=msg.report_week_start,
        routine_delivery=_routine_delivery_out(msg.routine_delivery_json),
    )


def _routine_delivery_out(raw: str | None) -> RoutineDeliveryCardOut | None:
    """저장한 루틴 전송 안내 JSON → 응답. 깨진 값은 안내가 없는 것으로 읽는다."""
    if not raw:
        return None
    try:
        data = json.loads(raw)
        return RoutineDeliveryCardOut(**data)
    except (TypeError, ValueError):
        return None


#: 루틴 전송 안내 카드가 이름으로 적는 운동 수. 나머지는 개수로 접는다.
_DELIVERY_CARD_NAMES = 3


def post_routine_delivery(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    kind: str,
    program_names: Sequence[str] = (),
    routine_names: Sequence[str] = (),
) -> None:
    """회원에게 운동을 보낸 일을 채팅에 안내로 남긴다(커밋 없음). (#2672)

    알림은 "지금 왔다" 를 알리고 지나가지만, 채팅은 두 사람이 함께 보는
    기록이다 — "어제 보낸 루틴 해 보셨어요?" 가 그 전송 바로 아래에 이어진다.
    주간 리포트 전송 안내(#1600)와 같은 자리·같은 규칙(트레이너가 보낸 메시지라
    회원에게 안 읽음으로 잡힌다)이다. 알림은 따로 그대로 간다.

    본문은 안내 카드를 그리지 못하는 자리(로스터·대화 목록의 마지막 메시지)가
    읽는 한 줄이고, 카드는 [routine_delivery_json] 으로 두 앱이 화면 언어에
    맞춰 그린다.
    """
    names = [*program_names, *routine_names]
    if not names:
        return
    shown = ", ".join(names[:_DELIVERY_CARD_NAMES])
    more = len(names) - _DELIVERY_CARD_NAMES
    if current_locale() == "en":
        body = f"Sent a workout: {shown}" + (f" and {more} more" if more > 0 else "")
    else:
        body = f"운동을 보냈어요: {shown}" + (f" 외 {more}개" if more > 0 else "")
    send_message(
        db,
        trainer_id,
        member_id,
        "trainer",
        body,
        routine_delivery={
            "kind": kind,
            "program_names": list(program_names),
            "routine_names": list(routine_names),
        },
        commit=False,
    )


def find_message_by_client_request(
    db: Session,
    trainer_id: str,
    member_id: str,
    sender: str,
    client_request_id: str,
) -> ChatMessage | None:
    return db.scalar(
        select(ChatMessage).where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.sender == sender,
            ChatMessage.client_request_id == client_request_id,
        )
    )


def _existing_message_out(
    message: ChatMessage, *, text: str, viewer: str
) -> ChatMessageOut:
    if message.body != text:
        raise IdempotencyConflict(
            "같은 client_request_id에 다른 메시지를 보낼 수 없어요."
        )
    return chat_message_out(message, viewer)


#: 대화에서 읽어 낸 PT 의 종류·길이·표시. 길이는 트레이너 앱의 기본 한 시간을
#: 따른다 — 문장에 "몇 분" 까지 적히는 일은 드물어 짐작하지 않는다.
PT_SESSION_TYPE = "1:1 PT"


_CHAT_SCHEDULE_MINUTES = 60


_CHAT_SCHEDULE_NOTE = "대화에서 잡은 일정"


def _schedule_from_chat(
    db: Session, trainer_id: str, member_id: str, text: str, sent_at: datetime
) -> None:
    """트레이너가 대화에서 잡은 다음 PT 를 일정으로 남긴다. (#1061)

    약속은 대화에서 잡히는데 그 말이 채팅 안에만 남아, 회원 앱의 `다음 PT
    일정` 은 비어 있거나 지난 일정을 들고 있었다.

    **트레이너가 보낸 말만** 본다. 회원이 제안한 시간은 아직 약속이 아니다 —
    트레이너가 받아 주기 전에 일정으로 굳히면 오지 않을 시간을 잡아 둔다.

    같은 날 같은 시각의 일정이 이미 있으면 아무것도 하지 않는다. 트레이너가
    같은 약속을 두 번 말하는 것은 흔한 일이라, 그때마다 칸이 늘면 일정 화면이
    중복으로 찬다. 취소·노쇼로 끝난 일정은 그 시간을 차지하지 않으므로 같은 약속을
    다시 잡는 것을 막지 않는다(#3241).

    다른 일정과 시간이 겹치면 만들지 않는다(#3241) — 일정 화면·예약이 모두 막는
    이중 예약을 채팅만 지나가게 둘 수 없다. 메시지 전송은 그대로 성공한다: 읽어 낸
    약속은 덤이고, 겹친 시간은 트레이너가 일정 화면에서 정리한다.
    """
    # `schedule` 이 이 모듈을 불러 쓰므로 여기서 불러온다.
    from app.services.trainer import schedule as trainer_schedule_service

    local_sent_at = clock.to_seoul(sent_at)
    parsed = schedule_parse.parse_schedule(
        text, sent_on=local_sent_at.date(), sent_time=local_sent_at.time()
    )
    if parsed is None:
        return
    existing = db.scalar(
        select(TrainerSchedule.id).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.date == parsed.date,
            TrainerSchedule.time == parsed.time,
            TrainerSchedule.status.in_(trainer_schedule_service._OCCUPYING_STATUSES),
        )
    )
    if existing is not None:
        return
    try:
        trainer_schedule_service.ensure_no_overlap(
            db,
            trainer_id,
            date=parsed.date,
            time=parsed.time,
            duration_minutes=_CHAT_SCHEDULE_MINUTES,
        )
    except trainer_schedule_service.ScheduleOverlap:
        return
    member_name = db.scalar(select(User.name).where(User.id == member_id))
    db.add(
        TrainerSchedule(
            id=f"sched-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            date=parsed.date,
            time=parsed.time,
            client_name=member_name or "",
            type=PT_SESSION_TYPE,
            duration_minutes=_CHAT_SCHEDULE_MINUTES,
            status="예정",
            # 어디서 온 일정인지 남긴다 — 사람이 만든 일정과 섞이면, 잘못
            # 읽은 약속을 나중에 가려낼 수 없다.
            note=_CHAT_SCHEDULE_NOTE,
            program_json="[]",
            sort_order=0,
        )
    )
    db.flush()


def send_message(
    db: Session, trainer_id: str, member_id: str, sender: str, text: str,
    viewer: str = "trainer", notify: str | None = None,
    client_request_id: str | None = None,
    attachment_type: str = "pdf",
    attachment_file_name: str | None = None,
    attachment_file_id: str | None = None,
    attachment_file_size: int | None = None,
    report_week_start: str | None = None,
    emote_id: str | None = None,
    routine_delivery: dict[str, object] | None = None,
    commit: bool = True,
) -> ChatMessageOut:
    """스레드에 메시지 추가(sender: 'trainer'|'member'). 로스터 last_message 는
    build_roster 가 최신 메시지를 읽어 자동 반영하므로 별도 비정규화가 없다.

    [notify] 가 주어지면 그 종류로 회원 알림을 **같은 트랜잭션에** 얹는다(#489).
    종류를 호출자가 정하는 이유: 주간 리포트도 이 함수로 나가므로, 여기서 판단하면
    일반 메시지와 구분할 수 없다. [attachment_type] 도 같은 이유로 호출자가
    정한다 — 파일만 보고는 리포트인지 코칭 사진인지 알 수 없다(#921).

    회원이 보낸 메시지에는 **트레이너 알림**을 남긴다(#503). 사이드바 미읽음 배지는
    지금 보고 있을 때만 눈에 들어오고, 지나가면 다시 볼 자리가 없었다.
    """
    if client_request_id:
        existing = find_message_by_client_request(
            db, trainer_id, member_id, sender, client_request_id
        )
        if existing is not None:
            return _existing_message_out(existing, text=text, viewer=viewer)

    msg = ChatMessage(
        id=f"chat-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        sender=sender,
        body=text,
        client_request_id=client_request_id,
        # 첨부가 없으면 종류도 없다. 종류를 호출자가 정하는 이유는 파일만 보고는
        # 알 수 없기 때문이다 — 리포트 PDF(#778)와 코칭 사진(#921)이 같은 자리로
        # 들어온다.
        attachment_type=attachment_type if attachment_file_id else None,
        attachment_file_name=attachment_file_name,
        attachment_file_id=attachment_file_id,
        attachment_file_size=attachment_file_size,
        # 리포트 전송 안내인가 — 호출자가 정한다. 첨부와 마찬가지로 본문만
        # 보고는 알 수 없고, 리포트는 PDF 없이도 나간다(#1600).
        report_week_start=report_week_start,
        # 이모티콘 메시지(#2020). 본문은 이모티콘을 못 그리는 자리(알림·로스터의
        # 마지막 메시지)가 읽을 글이고, 그림은 이 id 가 고른다.
        emote_id=emote_id,
        # 루틴 전송 안내(#2672) — 호출자가 정한다.
        routine_delivery_json=(
            json.dumps(routine_delivery, ensure_ascii=False)
            if routine_delivery
            else None
        ),
        created_at=datetime.now(timezone.utc),
    )
    db.add(msg)
    # 알림을 넣기 전에 DB 유니크 제약을 확인한다. 동시 재시도 중 진 요청이 여기서
    # 막혀야 회원·트레이너 알림도 한 번만 생성된다.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = find_message_by_client_request(
                db, trainer_id, member_id, sender, client_request_id
            )
            if existing is not None:
                return _existing_message_out(existing, text=text, viewer=viewer)
        raise

    # 전송 안내는 트레이너가 쓴 글이 아니다 — 일정 문구로 읽지 않는다.
    if sender == "trainer" and routine_delivery is None:
        _schedule_from_chat(db, trainer_id, member_id, text, msg.created_at)

    if sender == "member":
        member_name = db.scalar(select(User.name).where(User.id == member_id))
        member_args: dict[str, object] = {"member_name": member_name or ""}
        # 회원도 사진만 보낼 수 있다(#1665). 트레이너 알림이 제목만 남은 빈 줄이
        # 되지 않게 표시를 싣는다. 글 메시지의 인자는 예전 그대로 둔다 — 이미
        # 저장된 알림과 같은 모양이어야 앱이 한 규칙으로 읽는다.
        if not text and attachment_file_id and attachment_type == "image":
            member_args["photo_only"] = True
        notification_service.queue_for_trainer(
            db,
            trainer_id=trainer_id,
            kind=notification_service.TRAINER_MESSAGE_KIND,
            template=notification_templates.TRAINER_MEMBER_MESSAGE,
            template_args=member_args,
            body=text,
            # 보낸 회원을 남겨야 알림을 눌렀을 때 그 회원 대화로 가고, 대화를
            # 읽으면 이 알림도 함께 읽음 처리할 수 있다(#2291).
            subject_id=member_id,
        )
    if notify is not None and sender == "trainer":
        trainer_name = db.scalar(select(User.name).where(User.id == trainer_id))
        is_report = notify == notification_service.WEEKLY_REPORT
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notify,
            template=notification_templates.MEMBER_COACH_MESSAGE,
            template_args={
                "trainer_name": trainer_name or "",
                "report": is_report,
                # 사진만 보낸 메시지는 본문이 비어 있다(#921). 알림 본문까지 비우면
                # 목록에 제목만 뜬 빈 줄이 남아, 무엇이 왔는지 알 수 없다.
                "photo_only": not text
                and bool(attachment_file_id)
                and attachment_type == "image",
            },
            body=text,
            # 리포트도 대화 스레드로 도착한다 — 별도 리포트 함이 없다. 목적지는
            # 같지만 갈래를 나눠 회원 앱이 리포트를 메시지와 다른 아이콘으로
            # 그린다(#2085).
            category=(
                notification_service.MEMBER_COACH_REPORT
                if is_report
                else notification_service.MEMBER_COACH_CHAT
            ),
        )
    # 다른 저장과 한 트랜잭션으로 묶는 호출자(루틴 전송 안내, #2672)는 커밋을
    # 스스로 한다. 안내는 대화가 아니라 개인화 적재(RAG)에도 싣지 않는다.
    if not commit:
        db.flush()
        return chat_message_out(msg, viewer)
    db.commit()
    db.refresh(msg)
    out = chat_message_out(msg, viewer)
    # 적재는 응답을 다 만든 뒤에 한다(#580). 실패하면 personal_ingest 가 세션을
    # 롤백하는데, 그때 msg 가 만료돼 응답을 못 만들게 되면 적재 실패가 메시지
    # 발신 실패로 번진다. 커밋은 이미 끝났으니 롤백해도 메시지 자체는 남는다.
    personal_ingest.record_chat(
        db, member_id, sender=sender, text=text,
        date=clock.to_seoul(msg.created_at).date().isoformat(),
        source_ref=msg.id,
    )
    return out


def mark_thread_read(db: Session, trainer_id: str, member_id: str, reader: str) -> int:
    """reader 가 상대방이 보낸 미확인 메시지를 읽음 처리. 반환: 읽음 처리된 건수.

    reader='trainer' → 상대(member)가 보낸 미확인 메시지에 read_at 을 채운다.
    reader='member'  → 상대(trainer)가 보낸 미확인 메시지에 read_at 을 채운다.
    """
    other = "member" if reader == "trainer" else "trainer"
    result = db.execute(
        update(ChatMessage)
        .where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.sender == other,
            ChatMessage.read_at.is_(None),
        )
        .values(read_at=datetime.now(timezone.utc))
    )
    if reader == "trainer":
        # 대화를 읽었으면 그 회원이 보낸 메시지 알림도 확인한 것이다(#2291).
        # 전에는 채팅만 읽음이 되고 알림은 미읽음으로 남아, 이미 본 메시지가
        # 알림 배지에 계속 걸려 있었다. 보낸 회원이 기록되지 않은 옛 알림은
        # 누구의 것인지 알 수 없어 건드리지 않는다 — 알림함에서 직접 읽는다.
        db.execute(
            update(Notification)
            .where(
                Notification.user_id == trainer_id,
                Notification.category == notification_service.TRAINER_MESSAGE_KIND,
                Notification.subject_id == member_id,
                Notification.read.is_(False),
            )
            .values(read=True)
        )
    db.commit()
    return result.rowcount or 0


def unread_counts_for_trainer(db: Session, trainer_id: str) -> dict[str, int]:
    """트레이너 기준 회원별 미확인(회원이 보낸 read_at NULL) 메시지 수.

    **지금 담당 중이고 동의가 유효한 링크**의 회원만 센다(#2868). 읽음 처리
    (`POST /trainer/clients/{id}/chat/read`)는 `_require_client` 로 그런 링크를
    요구하므로, 해제·동의 철회 회원을 세면 트레이너가 지울 수 없는 배지가 남고
    "예전에 담당했던 회원" 이 숫자로 드러난다. 메시지 행은 그대로 두므로
    재등록(새 동의 포함)하면 남은 안읽음이 다시 보인다.
    """
    rows = db.execute(
        select(ChatMessage.member_id, func.count())
        .join(
            TrainerClient,
            (TrainerClient.trainer_id == ChatMessage.trainer_id)
            & (TrainerClient.member_id == ChatMessage.member_id),
        )
        .where(
            data_consent_service.open_link_clause(),
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.sender == "member",
            ChatMessage.read_at.is_(None),
        )
        .group_by(ChatMessage.member_id)
    ).all()
    return {member_id: count for member_id, count in rows}
