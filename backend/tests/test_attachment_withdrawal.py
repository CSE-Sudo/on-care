"""탈퇴하면 채팅 첨부 파일도 지워지고, 운영 저장소에서도 첨부가 열린다. (#2817)

여기서 보는 것:

- 회원 탈퇴: 회원이 올린 사진과 트레이너가 보낸 사진·리포트 PDF 가 저장소에서
  사라진다(스레드 행이 CASCADE 로 사라지므로 남기면 고아 파일이다).
- 트레이너 탈퇴: 그 트레이너의 스레드 첨부가 사라진다.
- **남의 스레드 파일은 건드리지 않는다.**
- 저장소가 S3 여도 다운로드는 서버가 권한을 확인한 뒤 흘려보낸다 — 업로드한
  인스턴스와 다른 저장소 객체(새 클라이언트)에서 읽어도 열린다. 권한 없는 사람은 404.

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
from app.services import attachment_store, chat_image_storage, report_pdf_storage
from tests.fake_s3 import FakeS3

EMAIL_PREFIX = "attwd-test-"
PASSWORD = "attwd-pw-1234"
PDF = b"%PDF-1.4\n" + b"0" * 64 + b"\n%%EOF"


def _png() -> bytes:
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00"))
        + chunk(b"IEND", b"")
    )


@pytest.fixture(autouse=True)
def _isolated_storage(tmp_path, monkeypatch):
    """테스트마다 빈 로컬 저장소. 운영 저장소 테스트는 아래에서 S3 로 바꾼다."""
    settings = get_settings()
    monkeypatch.setattr(settings, "attachment_storage", "local")
    monkeypatch.setattr(settings, "chat_image_storage_dir", str(tmp_path / "images"))
    monkeypatch.setattr(settings, "report_pdf_storage_dir", str(tmp_path / "pdfs"))


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
        db_session.query(ChatMessage).filter(
            ChatMessage.member_id.in_(user_ids) | ChatMessage.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerClient).filter(
            TrainerClient.member_id.in_(user_ids) | TrainerClient.trainer_id.in_(user_ids)
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


def _member(client) -> tuple[str, str]:
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "첨부 회원"},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _trainer(client, db_session, member_id: str) -> tuple[str, str]:
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"attwd-trainer-{suffix}",
        email=email,
        name="첨부 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id))
    db_session.add(
        TrainerClient(
            id=f"tc-attwd-{suffix}",
            trainer_id=trainer.id,
            member_id=member_id,
            active=True,
        )
    )
    db_session.commit()
    return trainer.id, _login(client, email)


def _member_sends_photo(client, token: str) -> str:
    response = client.post(
        "/v1/me/coach/chat/image",
        files={"image": ("meal.png", _png(), "image/png")},
        data={"message": "점심"},
        headers=_auth(token),
    )
    assert response.status_code == 201, response.text
    return response.json()["attachment"]["file_id"]


def _trainer_sends_photo(client, token: str, member_id: str) -> str:
    response = client.post(
        f"/v1/trainer/clients/{member_id}/chat/image",
        files={"image": ("form.png", _png(), "image/png")},
        data={"message": "자세 참고"},
        headers=_auth(token),
    )
    assert response.status_code == 201, response.text
    return response.json()["attachment"]["file_id"]


def _trainer_report_pdf(db_session, trainer_id: str, member_id: str) -> str:
    """리포트 PDF 메시지 — 저장소에 바이트를 쓰고 행을 직접 넣는다."""
    file_id = report_pdf_storage.save(PDF)
    db_session.add(
        ChatMessage(
            id=f"attwd-msg-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            sender="trainer",
            body="이번 주 리포트",
            attachment_type="pdf",
            attachment_file_name="weekly-report.pdf",
            attachment_file_id=file_id,
            attachment_file_size=len(PDF),
        )
    )
    db_session.commit()
    return file_id


def _image_exists(file_id: str) -> bool:
    try:
        chat_image_storage.open_image(file_id)[0].read_all()
    except FileNotFoundError:
        return False
    return True


def _pdf_exists(file_id: str) -> bool:
    try:
        report_pdf_storage.open_pdf(file_id).read_all()
    except FileNotFoundError:
        return False
    return True


# ---- 탈퇴 ----


def test_member_withdrawal_deletes_every_attachment_in_their_threads(
    client, db_session
):
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session, member_id)
    mine = _member_sends_photo(client, member_token)
    theirs = _trainer_sends_photo(client, trainer_token, member_id)
    report = _trainer_report_pdf(db_session, trainer_id, member_id)
    assert _image_exists(mine) and _image_exists(theirs) and _pdf_exists(report)

    gone = client.request(
        "DELETE", "/v1/users/me", json={"current_password": PASSWORD},
        headers=_auth(member_token),
    )

    assert gone.status_code == 200, gone.text
    assert not _image_exists(mine)
    # 트레이너가 회원에게 보낸 것도 회원의 기록이라 함께 파기된다.
    assert not _image_exists(theirs)
    assert not _pdf_exists(report)


def test_trainer_withdrawal_deletes_attachments_in_their_threads(client, db_session):
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session, member_id)
    mine = _trainer_sends_photo(client, trainer_token, member_id)
    from_member = _member_sends_photo(client, member_token)
    report = _trainer_report_pdf(db_session, trainer_id, member_id)

    gone = client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_auth(trainer_token),
    )

    assert gone.status_code == 200, gone.text
    assert not _image_exists(mine)
    assert not _pdf_exists(report)
    # 스레드 행이 CASCADE 로 사라져 회원 사진도 열 경로가 없다 — 고아로 남기지 않는다.
    assert not _image_exists(from_member)


def test_withdrawal_leaves_other_threads_alone(client, db_session):
    leaving_id, leaving_token = _member(client)
    _trainer(client, db_session, leaving_id)
    staying_id, staying_token = _member(client)
    _trainer(client, db_session, staying_id)
    leaving_photo = _member_sends_photo(client, leaving_token)
    staying_photo = _member_sends_photo(client, staying_token)

    client.request(
        "DELETE", "/v1/users/me", json={"current_password": PASSWORD},
        headers=_auth(leaving_token),
    )

    assert not _image_exists(leaving_photo)
    assert _image_exists(staying_photo)


def test_withdrawal_succeeds_even_if_the_store_cannot_delete(
    client, db_session, monkeypatch
):
    """파일 삭제가 실패해도 계정 삭제는 끝난다 — 실패는 로그로 남겨 다시 지운다."""
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    _member_sends_photo(client, member_token)

    def broken(file_id: str) -> None:
        raise attachment_store.StoreError("down")

    monkeypatch.setattr(chat_image_storage, "delete", broken)

    gone = client.request(
        "DELETE", "/v1/users/me", json={"current_password": PASSWORD},
        headers=_auth(member_token),
    )

    assert gone.status_code == 200, gone.text
    db_session.expire_all()
    assert db_session.get(User, member_id) is None


# ---- 운영 저장소(S3)에서 내려받기 ----


@pytest.fixture
def s3_bucket(monkeypatch):
    """업로드와 다운로드가 서로 다른 클라이언트를 쓴다 — 다른 인스턴스 흉내."""
    bucket: dict = {}
    monkeypatch.setattr(
        attachment_store, "_s3_client", lambda region, endpoint: FakeS3(bucket)
    )
    settings = get_settings()
    monkeypatch.setattr(settings, "attachment_storage", "s3")
    monkeypatch.setattr(settings, "attachment_s3_bucket", "oncare-test")
    return bucket


def test_attachments_open_from_object_storage(client, db_session, s3_bucket, tmp_path):
    member_id, member_token = _member(client)
    _, trainer_token = _trainer(client, db_session, member_id)
    file_id = _member_sends_photo(client, member_token)

    # 컨테이너 디스크에는 아무것도 없다 — 재배포로 비어도 상관없다.
    assert not any((tmp_path / "images").glob("*"))
    assert [key for _, key in s3_bucket] == [
        f"chat-attachments/chat-images/{file_id}.png"
    ]

    for token in (member_token, trainer_token):
        response = client.get(f"/v1/chat/attachments/{file_id}", headers=_auth(token))
        assert response.status_code == 200, response.text
        assert response.headers["content-type"] == "image/png"
        assert response.headers["cache-control"] == "private, no-store"
        # 저장 전에 메타데이터를 털고 다시 인코딩하므로(#2829) 바이트는 보낸 것과
        # 다를 수 있다 — 버킷에 있는 그 파일을 내려 준다.
        assert response.content == s3_bucket[
            ("oncare-test", f"chat-attachments/chat-images/{file_id}.png")
        ][0]


def test_report_pdf_downloads_from_object_storage(client, db_session, s3_bucket):
    member_id, member_token = _member(client)
    trainer_id, _ = _trainer(client, db_session, member_id)
    file_id = _trainer_report_pdf(db_session, trainer_id, member_id)

    response = client.get(f"/v1/chat/attachments/{file_id}", headers=_auth(member_token))

    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "application/pdf"
    assert response.headers["content-length"] == str(len(PDF))
    assert response.headers["content-disposition"].startswith("attachment;")
    assert response.content == PDF


def test_object_storage_download_still_checks_permission(
    client, db_session, s3_bucket
):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    _, stranger_token = _member(client)
    file_id = _member_sends_photo(client, member_token)

    response = client.get(
        f"/v1/chat/attachments/{file_id}", headers=_auth(stranger_token)
    )

    assert response.status_code == 404


def test_missing_object_is_a_404_not_a_500(client, db_session, s3_bucket):
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    file_id = _member_sends_photo(client, member_token)
    s3_bucket.clear()

    response = client.get(f"/v1/chat/attachments/{file_id}", headers=_auth(member_token))

    assert response.status_code == 404


def test_korean_file_names_survive_the_header(client, db_session, s3_bucket):
    member_id, member_token = _member(client)
    trainer_id, _ = _trainer(client, db_session, member_id)
    file_id = _trainer_report_pdf(db_session, trainer_id, member_id)
    row = db_session.query(ChatMessage).filter_by(attachment_file_id=file_id).one()
    row.attachment_file_name = "주간리포트.pdf"
    db_session.commit()

    response = client.get(f"/v1/chat/attachments/{file_id}", headers=_auth(member_token))

    assert response.status_code == 200
    assert "filename*=utf-8''" in response.headers["content-disposition"]


def test_storage_outage_is_a_503_not_a_404(client, db_session, s3_bucket, monkeypatch):
    """저장소 장애는 '없음'과 구분한다 — 앱이 다시 시도할 수 있어야 한다."""
    member_id, member_token = _member(client)
    _trainer(client, db_session, member_id)
    file_id = _member_sends_photo(client, member_token)
    broken = FakeS3(s3_bucket)
    broken.fail_with = "InternalError"
    monkeypatch.setattr(attachment_store, "_s3_client", lambda region, endpoint: broken)

    response = client.get(f"/v1/chat/attachments/{file_id}", headers=_auth(member_token))

    assert response.status_code == 503
