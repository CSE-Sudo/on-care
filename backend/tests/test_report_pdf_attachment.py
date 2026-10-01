"""#778 weekly report PDF attachment end-to-end API checks (DB required)."""
from __future__ import annotations

from uuid import uuid4

import pytest


PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n"


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _send(client, token: str, **overrides):
    request_id = overrides.pop("request_id", f"pdf-test-{uuid4().hex[:12]}")
    file = overrides.pop("file", ("weekly.pdf", PDF, "application/pdf"))
    return client.post(
        "/v1/trainer/clients/user-jisu/report/send-pdf",
        headers=_headers(token),
        data={
            "week_start": "2026-08-03",
            "message": "이번 주 리포트입니다.",
            "client_request_id": request_id,
            **overrides,
        },
        files={"pdf": file},
    )


def test_send_pdf_stores_metadata_and_both_threads_parse_it(client, tmp_path, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))
    trainer_token = _login(client, "trainer@oncare.com")
    response = _send(client, trainer_token)
    assert response.status_code == 201, response.text
    attachment = response.json()["attachment"]
    assert attachment["type"] == "pdf"
    assert attachment["file_name"] == "weekly.pdf"
    assert attachment["file_size"] == len(PDF)
    assert (tmp_path / f'{attachment["file_id"]}.pdf').read_bytes() == PDF

    trainer_thread = client.get(
        "/v1/trainer/clients/user-jisu/chat", headers=_headers(trainer_token)
    ).json()
    assert any(message.get("attachment", {}).get("file_id") == attachment["file_id"]
               for message in trainer_thread if message.get("attachment"))

    member_token = _login(client, "jisu@oncare.com")
    member_thread = client.get(
        "/v1/me/coach/chat", headers=_headers(member_token)
    ).json()
    assert any(message.get("attachment", {}).get("file_id") == attachment["file_id"]
               for message in member_thread if message.get("attachment"))

    download = client.get(
        f'/v1{attachment["download_path"]}', headers=_headers(member_token)
    )
    assert download.status_code == 200
    assert download.headers["content-type"].startswith("application/pdf")
    assert download.content == PDF


def test_text_message_remains_attachment_free(client):
    token = _login(client, "trainer@oncare.com")
    response = client.post(
        "/v1/trainer/clients/user-jisu/chat",
        headers=_headers(token),
        json={"text": "기존 텍스트 메시지"},
    )
    assert response.status_code == 201
    assert response.json()["attachment"] is None


def test_pdf_send_rejects_wrong_member_type_and_size(client, monkeypatch):
    from app.core.config import get_settings

    token = _login(client, "trainer@oncare.com")
    assert _send(client, token, file=("note.txt", b"hello", "text/plain")).status_code == 415
    assert _send(
        client, token, file=("fake.pdf", b"not really a pdf", "application/pdf")
    ).status_code == 415
    assert client.post(
        "/v1/trainer/clients/user-nobody/report/send-pdf",
        headers=_headers(token),
        data={"week_start": "2026-08-03", "message": "이번 주 리포트입니다."},
        files={"pdf": ("weekly.pdf", PDF, "application/pdf")},
    ).status_code == 404

    monkeypatch.setattr(get_settings(), "max_report_pdf_bytes", 8)
    assert _send(client, token).status_code == 413


def test_pdf_download_requires_owner_or_assigned_trainer(client, tmp_path, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))
    trainer_token = _login(client, "trainer@oncare.com")
    attachment = _send(client, trainer_token).json()["attachment"]
    url = f'/v1{attachment["download_path"]}'
    assert client.get(url).status_code == 401
    other_member_token = _login(client, "sungho@oncare.com")
    assert client.get(url, headers=_headers(other_member_token)).status_code == 404
    assert client.get(url, headers=_headers(trainer_token)).status_code == 200


def test_storage_failure_leaves_no_message(client, db_session, monkeypatch):
    from app.models.models import ChatMessage
    from app.services import report_pdf_storage

    request_id = f"pdf-fail-{uuid4().hex[:12]}"
    monkeypatch.setattr(
        report_pdf_storage,
        "save",
        lambda _: (_ for _ in ()).throw(report_pdf_storage.PdfStorageError("failed")),
    )
    token = _login(client, "trainer@oncare.com")
    response = _send(client, token, request_id=request_id)
    assert response.status_code == 500
    assert db_session.query(ChatMessage).filter(
        ChatMessage.client_request_id == request_id
    ).count() == 0


def test_pdf_send_rejects_inactive_assignment(client, db_session):
    from app.models.models import TrainerClient

    link = db_session.query(TrainerClient).filter(
        TrainerClient.trainer_id == "trainer-demo",
        TrainerClient.member_id == "user-jisu",
    ).one()
    link.active = False
    db_session.commit()

    try:
        token = _login(client, "trainer@oncare.com")
        assert _send(client, token).status_code == 404
    finally:
        link.active = True
        db_session.commit()


def test_report_pdf_storage_uses_opaque_identifier(tmp_path, monkeypatch):
    from app.core.config import get_settings
    from app.services import report_pdf_storage

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))
    file_id = report_pdf_storage.save(PDF)
    assert len(file_id) == 32
    assert report_pdf_storage.path_for(file_id).read_bytes() == PDF
    with pytest.raises(FileNotFoundError):
        report_pdf_storage.path_for("../outside")
    report_pdf_storage.delete(file_id)
    assert not (tmp_path / f"{file_id}.pdf").exists()
