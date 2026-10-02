"""채팅 사진은 저장 전에 메타데이터(EXIF 촬영 위치 등)를 털어 낸다. (#2829)

받은 바이트를 그대로 저장하던 시절에는 휴대폰 사진의 GPS 좌표가 상대에게
그대로 넘어갔다. 회원→트레이너, 트레이너→회원 두 방향 모두 같은 정리를 거치는지,
디코딩할 수 없는 파일은 저장하지 않고 415 인지, 이미 쌓인 파일을 다시 쓰는
스크립트가 동작하는지 본다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

import io
from uuid import uuid4

import pytest
from PIL import Image

from app.core.security import hash_password
from app.models.models import (
    ChatMessage,
    Notification,
    TrainerClient,
    TrainerProfile,
    User,
)
from app.services import chat_image_storage

EMAIL_PREFIX = "chatexif-test-"
PASSWORD = "chatexif-pw-1234"
GPS_TAG = 0x8825
ORIENTATION_TAG = 0x0112


def _gps_jpeg(*, size=(300, 200), orientation: int | None = None) -> bytes:
    exif = Image.Exif()
    exif[GPS_TAG] = {1: "N", 2: (37.0, 33.0, 59.0), 3: "E", 4: (126.0, 58.0, 41.0)}
    exif[0x010F] = "PhoneMaker"
    if orientation is not None:
        exif[ORIENTATION_TAG] = orientation
    buffer = io.BytesIO()
    Image.new("RGB", size, (220, 40, 40)).save(buffer, format="JPEG", exif=exif)
    return buffer.getvalue()


def _open(data: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(data))
    image.load()
    return image


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


def _pair(client, db_session) -> tuple[str, str, str, str]:
    """(member_id, member_token, trainer_id, trainer_token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "위치 회원"},
    )
    assert response.status_code == 201, response.text
    member_id = response.json()["id"]
    member_token = _login(client, email)

    suffix = uuid4().hex[:10]
    trainer_email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"chatexif-trainer-{suffix}",
        email=trainer_email,
        name="위치 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id))
    db_session.add(
        TrainerClient(
            id=f"tc-chatexif-{suffix}",
            trainer_id=trainer.id,
            member_id=member_id,
            active=True,
        )
    )
    db_session.commit()
    return member_id, member_token, trainer.id, _login(client, trainer_email)


def _member_sends(client, token: str, data: bytes, name: str = "meal.jpg"):
    return client.post(
        "/v1/me/coach/chat/image",
        files={"image": (name, data, "image/jpeg")},
        data={"message": "점심 사진이에요"},
        headers=_auth(token),
    )


def _trainer_sends(client, token: str, member_id: str, data: bytes):
    return client.post(
        f"/v1/trainer/clients/{member_id}/chat/image",
        files={"image": ("pose.jpg", data, "image/jpeg")},
        data={"message": "자세 사진"},
        headers=_auth(token),
    )


def _download(client, token: str, file_id: str) -> bytes:
    response = client.get(f"/v1/chat/attachments/{file_id}", headers=_auth(token))
    assert response.status_code == 200, response.text
    return response.content


# ---- 두 방향 모두 위치가 사라진다 ----


def test_the_trainer_downloads_the_members_photo_without_location(
    client, db_session
):
    _, member_token, _, trainer_token = _pair(client, db_session)

    sent = _member_sends(client, member_token, _gps_jpeg())
    assert sent.status_code == 201, sent.text
    attachment = sent.json()["attachment"]

    data = _download(client, trainer_token, attachment["file_id"])
    stored = _open(data)
    assert not dict(stored.getexif())
    assert b"PhoneMaker" not in data
    # 크기는 상대가 실제로 받는 파일의 크기다.
    assert attachment["file_size"] == len(data)


def test_the_member_downloads_the_trainers_photo_without_location(
    client, db_session
):
    member_id, member_token, _, trainer_token = _pair(client, db_session)

    sent = _trainer_sends(client, trainer_token, member_id, _gps_jpeg())
    assert sent.status_code == 201, sent.text

    data = _download(client, member_token, sent.json()["attachment"]["file_id"])
    assert not dict(_open(data).getexif())


def test_a_portrait_photo_arrives_upright(client, db_session):
    _, member_token, _, trainer_token = _pair(client, db_session)

    sent = _member_sends(
        client, member_token, _gps_jpeg(size=(300, 200), orientation=6)
    )
    assert sent.status_code == 201, sent.text

    stored = _open(
        _download(client, trainer_token, sent.json()["attachment"]["file_id"])
    )
    assert stored.size == (200, 300)
    assert ORIENTATION_TAG not in stored.getexif()


def test_a_transparent_png_stays_transparent(client, db_session):
    _, member_token, _, trainer_token = _pair(client, db_session)
    buffer = io.BytesIO()
    Image.new("RGBA", (6, 6), (0, 0, 0, 0)).save(buffer, format="PNG")

    sent = client.post(
        "/v1/me/coach/chat/image",
        files={"image": ("cut.png", buffer.getvalue(), "image/png")},
        headers=_auth(member_token),
    )
    assert sent.status_code == 201, sent.text

    response = client.get(
        f"/v1/chat/attachments/{sent.json()['attachment']['file_id']}",
        headers=_auth(trainer_token),
    )
    assert response.headers["content-type"] == "image/png"
    assert _open(response.content).getpixel((0, 0))[3] == 0


# ---- 읽을 수 없는 파일 ----


@pytest.mark.parametrize(
    "data",
    [
        b"\xff\xd8\xff\xe0" + b"\x00" * 64,
        b"\x89PNG\r\n\x1a\n" + b"0" * 64,
    ],
    ids=["jpeg-magic-only", "png-magic-only"],
)
def test_a_file_with_only_the_magic_number_is_refused(client, db_session, data):
    member_id, member_token, trainer_id, trainer_token = _pair(client, db_session)

    from_member = _member_sends(client, member_token, data)
    from_trainer = _trainer_sends(client, trainer_token, member_id, data)

    assert from_member.status_code == 415, from_member.text
    assert from_trainer.status_code == 415, from_trainer.text
    db_session.expire_all()
    # 메시지도, 파일도 남지 않는다.
    assert (
        db_session.query(ChatMessage)
        .filter(
            ChatMessage.member_id == member_id,
            ChatMessage.trainer_id == trainer_id,
        )
        .count()
        == 0
    )


def test_a_truncated_photo_is_refused(client, db_session):
    _, member_token, _, _ = _pair(client, db_session)

    response = _member_sends(client, member_token, _gps_jpeg(size=(400, 400))[:400])

    assert response.status_code == 415


# ---- 이미 쌓인 파일 재처리 ----


def test_the_backfill_script_cleans_files_saved_before_the_fix(client, db_session):
    from scripts import sanitize_chat_images

    member_id, _, trainer_id, trainer_token = _pair(client, db_session)
    raw = _gps_jpeg()
    # #2829 이전처럼 정리 없이 저장한 파일.
    stored = chat_image_storage.save(raw, sanitize=False)
    message = ChatMessage(
        id=f"chatexif-msg-{uuid4().hex[:10]}",
        trainer_id=trainer_id,
        member_id=member_id,
        sender="member",
        body="옛 사진",
        attachment_type="image",
        attachment_file_name="old.jpg",
        attachment_file_id=stored.file_id,
        attachment_file_size=len(raw),
    )
    db_session.add(message)
    db_session.commit()

    # 점검만 — 아무것도 바꾸지 않는다.
    assert sanitize_chat_images.main([]) == 0
    opened, _ = chat_image_storage.open_image(stored.file_id)
    assert opened.read_all() == raw

    assert sanitize_chat_images.main(["--apply"]) == 0

    opened, media_type = chat_image_storage.open_image(stored.file_id)
    cleaned = opened.read_all()
    assert media_type == "image/jpeg"
    assert not dict(_open(cleaned).getexif())
    db_session.expire_all()
    refreshed = db_session.get(ChatMessage, message.id)
    assert refreshed.attachment_file_size == len(cleaned)
    # 식별자가 그대로라 대화의 내려받기 경로도 그대로다.
    assert _download(client, trainer_token, stored.file_id) == cleaned
