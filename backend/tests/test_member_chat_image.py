"""회원이 담당 트레이너에게 보내는 사진. (#1665)

트레이너는 사진을 보낼 수 있었지만(#921) 회원은 받기만 했다. 식사·자세·인바디
결과지처럼 코칭에 바로 쓰이는 사진을 회원이 보낼 길이 없으면, 사진만큼은 개인
메신저로 오가 코칭 기록이 두 곳으로 갈라진다.

여기서 보는 것:

- 트레이너 발신과 **같은 규약**인가 — 바이트로 형식 판정, 용량 상한, 멱등.
- **받는 사람이 있을 때만** 보내지는가 — 담당 트레이너가 없거나 링크가 끊겼으면 404.
- 스레드의 **두 사람만** 내려받는가.
- 트레이너에게 **새 메시지 알림**이 남고, 사진만 보낸 메시지도 무엇이 왔는지 읽히는가.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

import struct
import zlib
from uuid import uuid4

import pytest

from app.core.config import get_settings
from app.core.security import hash_password
from app.models.models import (
    ChatMessage,
    Notification,
    TrainerClient,
    TrainerProfile,
    User,
)
from app.services import chat_image_storage, notification_templates as nt

EMAIL_PREFIX = "memberimg-test-"
PASSWORD = "memberimg-pw-1234"
EN = {"Accept-Language": "en"}


def _png(width: int = 1, height: int = 1) -> bytes:
    """가장 작은 유효 PNG. 저장소의 픽스처 파일에 기대지 않게 여기서 만든다."""

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + b"\x00\x00\x00" * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 32
WEBP = b"RIFF\x00\x00\x00\x00WEBPVP8 " + b"\x00" * 16


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        for row in (
            db_session.query(ChatMessage.attachment_file_id)
            .filter(ChatMessage.member_id.in_(user_ids))
            .all()
        ):
            if row[0]:
                chat_image_storage.delete(row[0])
        db_session.query(ChatMessage).filter(
            ChatMessage.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerClient).filter(
            TrainerClient.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(Notification).filter(
            Notification.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _member(client, name: str = "사진 회원") -> tuple[str, str]:
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": name},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _trainer(client, db_session, member_id: str | None, *, active: bool = True):
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"memberimg-trainer-{suffix}",
        email=email,
        name="사진 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id))
    if member_id is not None:
        db_session.add(
            TrainerClient(
                id=f"tc-memberimg-{suffix}",
                trainer_id=trainer.id,
                member_id=member_id,
                active=active,
            )
        )
    db_session.commit()
    return trainer, _login(client, email)


def _send(
    client,
    token: str,
    data: bytes = b"",
    *,
    name: str = "meal.png",
    content_type: str = "image/png",
    message: str | None = "점심 사진이에요",
    key: str | None = None,
    headers: dict[str, str] | None = None,
):
    form: dict[str, str] = {}
    if message is not None:
        form["message"] = message
    if key is not None:
        form["client_request_id"] = key
    return client.post(
        "/v1/me/coach/chat/image",
        files={"image": (name, data or _png(), content_type)},
        data=form,
        headers={**_auth(token), **(headers or {})},
    )


def _trainer_notifications(db_session, trainer_id: str) -> list[Notification]:
    db_session.expire_all()
    return (
        db_session.query(Notification)
        .filter(Notification.user_id == trainer_id)
        .all()
    )


# ---- 보내기 ----


def test_the_trainer_receives_the_members_photo_in_the_same_thread(
    client, db_session
):
    member_id, member_token = _member(client)
    trainer, trainer_token = _trainer(client, db_session, member_id)

    sent = _send(client, member_token)

    assert sent.status_code == 201, sent.text
    body = sent.json()
    # 보낸 사람 관점: 회원에게 이 메시지는 `me` 다.
    assert body["sender"] == "me"
    assert body["body"] == "점심 사진이에요"
    attachment = body["attachment"]
    assert attachment["type"] == "image"
    assert attachment["file_name"] == "meal.png"
    assert attachment["file_size"] == len(_png())
    assert attachment["download_path"] == f"/chat/attachments/{attachment['file_id']}"

    thread = client.get(
        f"/v1/trainer/clients/{member_id}/chat", headers=_auth(trainer_token)
    )
    assert thread.status_code == 200, thread.text
    received = thread.json()[-1]
    # 트레이너 관점: 회원이 보낸 것은 `client` 다 — 상대 말풍선으로 그린다.
    assert received["sender"] == "client"
    assert received["attachment"]["type"] == "image"
    assert received["attachment"]["file_id"] == attachment["file_id"]


def test_the_member_sees_their_own_photo_in_their_thread(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    file_id = _send(client, member_token).json()["attachment"]["file_id"]

    thread = client.get("/v1/me/coach/chat", headers=_auth(member_token))

    assert thread.status_code == 200, thread.text
    mine = thread.json()[-1]
    assert mine["sender"] == "me"
    assert mine["attachment"]["file_id"] == file_id


def test_the_message_is_stored_as_the_members(client, db_session):
    member_id, member_token = _member(client)
    trainer, _ = _trainer(client, db_session, member_id)

    sent = _send(client, member_token).json()

    db_session.expire_all()
    row = db_session.get(ChatMessage, sent["id"])
    assert row is not None
    assert row.sender == "member"
    assert row.trainer_id == trainer.id
    assert row.member_id == member_id
    assert row.attachment_type == "image"
    assert row.read_at is None


def test_a_photo_can_be_sent_without_a_message(client, db_session):
    """사진만 보내는 것이 자연스러운 경우가 많다 — 식사 사진에 설명은 없어도 된다."""
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = _send(client, member_token, message=None)

    assert response.status_code == 201, response.text
    assert response.json()["body"] == ""


def test_surrounding_whitespace_in_the_message_is_trimmed(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = _send(client, member_token, message="  저녁이에요  \n")

    assert response.status_code == 201, response.text
    assert response.json()["body"] == "저녁이에요"


@pytest.mark.parametrize(
    ("data", "media_type"),
    [(JPEG, "image/jpeg"), (WEBP, "image/webp")],
    ids=["jpeg", "webp"],
)
def test_jpeg_and_webp_are_accepted_as_well(client, db_session, data, media_type):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    sent = _send(client, member_token, data, name="photo", content_type=media_type)

    assert sent.status_code == 201, sent.text
    file_id = sent.json()["attachment"]["file_id"]
    download = client.get(
        f"/v1/chat/attachments/{file_id}", headers=_auth(member_token)
    )
    assert download.status_code == 200, download.text
    assert download.headers["content-type"] == media_type


def test_the_trainer_can_answer_with_a_photo_in_the_same_thread(
    client, db_session
):
    """양방향이 한 스레드다 — 회원 사진과 트레이너 사진이 섞여 쌓인다."""
    member_id, member_token = _member(client)
    _, trainer_token = _trainer(client, db_session, member_id)

    _send(client, member_token)
    reply = client.post(
        f"/v1/trainer/clients/{member_id}/chat/image",
        files={"image": ("pose.png", _png(), "image/png")},
        headers=_auth(trainer_token),
    )

    assert reply.status_code == 201, reply.text
    thread = client.get("/v1/me/coach/chat", headers=_auth(member_token)).json()
    photos = [row["sender"] for row in thread if row["attachment"]]
    assert photos == ["me", "trainer"]


# ---- 형식·용량 ----


def test_the_declared_content_type_is_not_believed(client, db_session):
    """`image/png` 라고 적힌 실행 파일은 이미지가 아니다."""
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = _send(client, member_token, b"MZ\x90\x00 not an image", name="evil.png")

    assert response.status_code == 415


def test_a_pdf_is_not_accepted_as_a_photo(client, db_session):
    """일반 파일은 받지 않는다 — 이 대화의 첨부는 사진이다."""
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = _send(
        client,
        member_token,
        b"%PDF-1.4\n%%EOF",
        name="inbody.pdf",
        content_type="application/pdf",
    )

    assert response.status_code == 415


def test_an_svg_is_not_accepted(client, db_session):
    """스크립트를 품을 수 있는 형식은 이름이 이미지여도 받지 않는다."""
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = _send(
        client,
        member_token,
        b"<svg xmlns='http://www.w3.org/2000/svg'/>",
        name="photo.svg",
        content_type="image/svg+xml",
    )

    assert response.status_code == 415


def test_a_photo_over_the_size_limit_is_refused(client, db_session, monkeypatch):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    photo = _png()
    monkeypatch.setattr(get_settings(), "max_chat_image_bytes", len(photo) - 1)

    response = _send(client, member_token, photo)

    assert response.status_code == 413
    db_session.expire_all()
    assert (
        db_session.query(ChatMessage)
        .filter(ChatMessage.member_id == member_id)
        .count()
        == 0
    )


def test_a_photo_exactly_at_the_size_limit_is_accepted(
    client, db_session, monkeypatch
):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    photo = _png()
    monkeypatch.setattr(get_settings(), "max_chat_image_bytes", len(photo))

    response = _send(client, member_token, photo)

    assert response.status_code == 201, response.text


def test_a_refused_photo_leaves_no_message_behind(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    _send(client, member_token, b"not an image")

    db_session.expire_all()
    assert (
        db_session.query(ChatMessage)
        .filter(ChatMessage.member_id == member_id)
        .count()
        == 0
    )


def test_a_long_file_name_is_cut_to_fit(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = _send(client, member_token, name=f"{'가' * 300}.png")

    assert response.status_code == 201, response.text
    assert len(response.json()["attachment"]["file_name"]) == 255


def test_a_path_in_the_file_name_is_not_kept(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = _send(client, member_token, name="../../etc/meal.png")

    assert response.status_code == 201, response.text
    assert response.json()["attachment"]["file_name"] == "meal.png"


def test_an_overlong_message_is_refused(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = _send(client, member_token, message="가" * 1001)

    assert response.status_code == 422


def test_a_request_without_a_file_is_refused(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    response = client.post(
        "/v1/me/coach/chat/image",
        data={"message": "사진이 빠졌어요"},
        headers=_auth(member_token),
    )

    assert response.status_code == 422


# ---- 멱등 ----


def test_a_retry_with_the_same_key_does_not_send_twice(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    key = uuid4().hex

    first = _send(client, member_token, key=key)
    second = _send(client, member_token, key=key)

    assert first.status_code == 201, first.text
    assert second.status_code == 201, second.text
    assert first.json()["id"] == second.json()["id"]
    # 재시도의 응답도 보낸 사람 관점이다.
    assert second.json()["sender"] == "me"
    thread = client.get("/v1/me/coach/chat", headers=_auth(member_token)).json()
    assert len([row for row in thread if row["attachment"]]) == 1


def test_a_retry_does_not_notify_the_trainer_twice(client, db_session):
    member_id, member_token = _member(client)
    trainer, _ = _trainer(client, db_session, member_id)
    key = uuid4().hex

    _send(client, member_token, key=key)
    _send(client, member_token, key=key)

    assert len(_trainer_notifications(db_session, trainer.id)) == 1


def test_the_same_key_with_a_different_message_is_a_conflict(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    key = uuid4().hex

    _send(client, member_token, key=key, message="첫 번째")
    response = _send(client, member_token, key=key, message="두 번째")

    assert response.status_code == 409


def test_a_key_already_used_for_a_text_message_is_a_conflict(client, db_session):
    """같은 키로 글을 보낸 뒤 사진을 보내면 다른 메시지다 — 글이 사진으로 둔갑하지 않는다."""
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    key = uuid4().hex
    text = client.post(
        "/v1/me/coach/chat",
        json={"text": "같은 말", "client_request_id": key},
        headers=_auth(member_token),
    )
    assert text.status_code == 201, text.text

    response = _send(client, member_token, key=key, message="같은 말")

    assert response.status_code == 409


def test_the_same_key_is_separate_per_sender(client, db_session):
    """멱등키는 보낸 사람마다 따로다 — 트레이너가 쓴 키와 겹쳐도 회원 사진은 나간다."""
    member_id, member_token = _member(client)
    _, trainer_token = _trainer(client, db_session, member_id)
    key = uuid4().hex
    trainer_sent = client.post(
        f"/v1/trainer/clients/{member_id}/chat/image",
        files={"image": ("pose.png", _png(), "image/png")},
        data={"client_request_id": key},
        headers=_auth(trainer_token),
    )
    assert trainer_sent.status_code == 201, trainer_sent.text

    mine = _send(client, member_token, key=key, message=None)

    assert mine.status_code == 201, mine.text
    assert mine.json()["id"] != trainer_sent.json()["id"]


# ---- 받는 사람 ----


def test_a_member_without_a_trainer_cannot_send(client, db_session):
    _, member_token = _member(client)

    response = _send(client, member_token)

    assert response.status_code == 404


def test_a_member_whose_link_ended_cannot_send(client, db_session):
    """링크가 휴면이면 담당이 아니다 — 끊긴 트레이너에게 사진이 쌓이지 않는다."""
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id, active=False)

    response = _send(client, member_token)

    assert response.status_code == 404
    db_session.expire_all()
    assert (
        db_session.query(ChatMessage)
        .filter(ChatMessage.member_id == member_id)
        .count()
        == 0
    )


def test_a_trainer_account_cannot_use_the_member_route(client, db_session):
    member_id, _ = _member(client)
    _, trainer_token = _trainer(client, db_session, member_id)

    response = _send(client, trainer_token)

    assert response.status_code == 403


def test_an_anonymous_request_is_refused(client):
    response = client.post(
        "/v1/me/coach/chat/image",
        files={"image": ("meal.png", _png(), "image/png")},
    )

    assert response.status_code == 401


def test_the_photo_goes_to_the_current_trainer_only(client, db_session):
    """예전 담당 트레이너(휴면 링크)에게는 가지 않고 지금 담당에게만 간다."""
    member_id, member_token = _member(client)
    old_trainer, old_token = _trainer(client, db_session, member_id, active=False)
    current, current_token = _trainer(client, db_session, member_id)

    sent = _send(client, member_token)

    assert sent.status_code == 201, sent.text
    db_session.expire_all()
    row = db_session.get(ChatMessage, sent.json()["id"])
    assert row.trainer_id == current.id
    file_id = sent.json()["attachment"]["file_id"]
    assert (
        client.get(
            f"/v1/chat/attachments/{file_id}", headers=_auth(old_token)
        ).status_code
        == 404
    )
    assert (
        client.get(
            f"/v1/chat/attachments/{file_id}", headers=_auth(current_token)
        ).status_code
        == 200
    )


# ---- 내려받기 권한 ----


def test_both_sides_of_the_thread_can_download_it(client, db_session):
    member_id, member_token = _member(client)
    _, trainer_token = _trainer(client, db_session, member_id)
    file_id = _send(client, member_token).json()["attachment"]["file_id"]

    for token in (member_token, trainer_token):
        response = client.get(
            f"/v1/chat/attachments/{file_id}", headers=_auth(token)
        )
        assert response.status_code == 200, response.text
        assert response.headers["content-type"] == "image/png"
        assert response.content == _png()
        # 사진은 대화 안에서 그려야 한다 — 내려받기로 처리되면 스레드에
        # 아무것도 보이지 않는다.
        assert "inline" in response.headers["content-disposition"]


def test_another_member_cannot_download_it(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    _, stranger_token = _member(client)
    file_id = _send(client, member_token).json()["attachment"]["file_id"]

    response = client.get(
        f"/v1/chat/attachments/{file_id}", headers=_auth(stranger_token)
    )

    # 존재 여부조차 알려 주지 않는다.
    assert response.status_code == 404


def test_another_trainer_cannot_download_it(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    other_member_id, _ = _member(client)
    _, other_trainer_token = _trainer(client, db_session, other_member_id)
    file_id = _send(client, member_token).json()["attachment"]["file_id"]

    response = client.get(
        f"/v1/chat/attachments/{file_id}", headers=_auth(other_trainer_token)
    )

    assert response.status_code == 404


def test_the_trainer_loses_access_when_the_link_ends(client, db_session):
    """담당이 끝난 트레이너는 회원이 보낸 사진을 더는 열 수 없다."""
    member_id, member_token = _member(client)
    trainer, trainer_token = _trainer(client, db_session, member_id)
    file_id = _send(client, member_token).json()["attachment"]["file_id"]

    db_session.query(TrainerClient).filter(
        TrainerClient.trainer_id == trainer.id
    ).update({TrainerClient.active: False}, synchronize_session=False)
    db_session.commit()

    trainer_view = client.get(
        f"/v1/chat/attachments/{file_id}", headers=_auth(trainer_token)
    )
    member_view = client.get(
        f"/v1/chat/attachments/{file_id}", headers=_auth(member_token)
    )
    assert trainer_view.status_code == 404
    # 회원 본인의 기록은 담당이 끝나도 회원의 것이다.
    assert member_view.status_code == 200


# ---- 알림 ----


def test_the_trainer_is_notified_of_the_new_message(client, db_session):
    member_id, member_token = _member(client, name="민지")
    trainer, _ = _trainer(client, db_session, member_id)

    _send(client, member_token)

    [row] = _trainer_notifications(db_session, trainer.id)
    assert row.category == "message"
    assert row.title == "민지 회원의 메시지"
    # 글이 있으면 회원이 쓴 글 그대로다.
    assert row.body == "점심 사진이에요"
    assert row.template == nt.TRAINER_MEMBER_MESSAGE
    # 글 메시지의 인자는 예전 모양 그대로다.
    assert row.template_args == {"member_name": "민지"}
    # 알림을 누르면 그 회원 대화로 간다(#2291).
    assert row.subject_id == member_id
    assert row.read is False


def test_a_photo_only_message_still_says_something_in_the_notification(
    client, db_session
):
    """본문이 빈 메시지의 알림은 제목만 남는다 — 무엇이 왔는지 알 수 없다."""
    member_id, member_token = _member(client, name="민지")
    trainer, _ = _trainer(client, db_session, member_id)

    _send(client, member_token, message=None)

    [row] = _trainer_notifications(db_session, trainer.id)
    assert row.body == "사진을 보냈어요"
    assert row.template_args == {"member_name": "민지", "photo_only": True}


def test_the_trainer_inbox_speaks_english_for_a_photo_only_message(
    client, db_session
):
    member_id, member_token = _member(client, name="Alex")
    _, trainer_token = _trainer(client, db_session, member_id)
    _send(client, member_token, message=None)

    inbox = client.get(
        "/v1/trainer/notifications", headers={**_auth(trainer_token), **EN}
    )

    assert inbox.status_code == 200, inbox.text
    [row] = [n for n in inbox.json() if n["subject_id"] == member_id]
    assert row["title"] == "Message from Alex"
    assert row["body"] == "Sent a photo"
    assert row["args"] == {"member_name": "Alex", "photo_only": True}


def test_the_trainer_can_turn_message_notifications_off(client, db_session):
    member_id, member_token = _member(client)
    trainer, _ = _trainer(client, db_session, member_id)
    db_session.query(TrainerProfile).filter(
        TrainerProfile.trainer_id == trainer.id
    ).update({TrainerProfile.notify_new_message: False}, synchronize_session=False)
    db_session.commit()

    sent = _send(client, member_token)

    assert sent.status_code == 201, sent.text
    assert _trainer_notifications(db_session, trainer.id) == []


def test_the_member_is_not_notified_of_their_own_photo(client, db_session):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)

    def count() -> int:
        db_session.expire_all()
        return (
            db_session.query(Notification)
            .filter(Notification.user_id == member_id)
            .count()
        )

    before = count()
    _send(client, member_token)

    assert count() == before


def test_the_photo_counts_as_unread_for_the_trainer(client, db_session):
    member_id, member_token = _member(client)
    _, trainer_token = _trainer(client, db_session, member_id)

    _send(client, member_token)

    unread = client.get("/v1/trainer/chat/unread", headers=_auth(trainer_token))
    assert unread.status_code == 200, unread.text
    assert unread.json().get(member_id) == 1


# ---- 로스터 미리보기 ----


def _roster_row(client, trainer_token: str, member_id: str, headers=None) -> dict:
    roster = client.get(
        "/v1/trainer/clients", headers={**_auth(trainer_token), **(headers or {})}
    )
    assert roster.status_code == 200, roster.text
    [row] = [r for r in roster.json() if r["id"] == member_id]
    return row


def test_the_roster_preview_says_photo_for_a_photo_only_message(
    client, db_session
):
    """빈 미리보기로 두면 회원이 사진을 보낸 직후 목록에서 무엇이 왔는지 모른다."""
    member_id, member_token = _member(client)
    _, trainer_token = _trainer(client, db_session, member_id)

    _send(client, member_token, message=None)

    assert _roster_row(client, trainer_token, member_id)["last_message"] == "사진"
    assert (
        _roster_row(client, trainer_token, member_id, EN)["last_message"] == "Photo"
    )


def test_the_roster_preview_keeps_the_text_sent_with_a_photo(client, db_session):
    member_id, member_token = _member(client)
    _, trainer_token = _trainer(client, db_session, member_id)

    _send(client, member_token, message="점심 사진이에요")

    assert (
        _roster_row(client, trainer_token, member_id)["last_message"]
        == "점심 사진이에요"
    )


# ---- 알림 문장 ----


@pytest.mark.parametrize(
    ("locale", "expected"),
    [
        ("ko", ("민지 회원의 메시지", "사진을 보냈어요")),
        ("en", ("Message from Alex", "Sent a photo")),
    ],
)
def test_the_template_fills_the_body_of_a_photo_only_message(locale, expected):
    name = "민지" if locale == "ko" else "Alex"
    assert (
        nt.render(
            nt.TRAINER_MEMBER_MESSAGE,
            {"member_name": name, "photo_only": True},
            locale,
        )
        == expected
    )


def test_the_template_leaves_a_text_message_body_alone():
    assert nt.render(
        nt.TRAINER_MEMBER_MESSAGE, {"member_name": "Alex"}, "en"
    ) == ("Message from Alex", None)
    assert nt.columns(
        nt.TRAINER_MEMBER_MESSAGE,
        {"member_name": "민지", "photo_only": True},
        body="",
    )["body"] == "사진을 보냈어요"
