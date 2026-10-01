"""#2771 리포트 PDF 전송의 메시지는 필수다 (DB required).

예전에는 `message` 가 비었거나 공백뿐이면 서버가 한국어 기본 문장
("이번 주 리포트입니다.")으로 바꿔 저장했다. 서버는 트레이너·회원의 언어를
몰라, 영어로 쓰는 회원에게도 한국어 문장이 나갔다. 이제 빈 문구는 422 로
거절하고 아무것도 저장하지 않는다. 같은 `client_request_id` 의 멱등 규칙(같은
본문 재시도는 한 번, 다른 본문은 409)은 그대로다(#2773 회귀 확인).
"""
from __future__ import annotations

from uuid import uuid4

import pytest

PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n"
URL = "/v1/trainer/clients/user-jisu/report/send-pdf"


@pytest.fixture(autouse=True)
def _pdf_dir(tmp_path, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "report_pdf_storage_dir", str(tmp_path))


def _token(client) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _post(client, token: str, data: dict[str, str]):
    return client.post(
        URL,
        headers={"Authorization": f"Bearer {token}"},
        data={"week_start": "2026-08-03", **data},
        files={"pdf": ("weekly.pdf", PDF, "application/pdf")},
    )


def _pdf_bodies(client, token: str) -> list[str]:
    thread = client.get(
        "/v1/trainer/clients/user-jisu/chat?limit=100",
        headers={"Authorization": f"Bearer {token}"},
    ).json()
    return [m["body"] for m in thread if (m.get("attachment") or {}).get("type") == "pdf"]


@pytest.mark.parametrize("message", ["", "   ", "\n\t "])
def test_blank_message_is_refused_and_nothing_is_stored(client, message):
    token = _token(client)
    before = _pdf_bodies(client, token)

    response = _post(
        client,
        token,
        {"message": message, "client_request_id": f"blank-{uuid4().hex[:12]}"},
    )

    assert response.status_code == 422, response.text
    assert _pdf_bodies(client, token) == before


def test_missing_message_is_refused(client):
    token = _token(client)
    before = _pdf_bodies(client, token)

    response = _post(client, token, {"client_request_id": f"none-{uuid4().hex[:12]}"})

    assert response.status_code == 422, response.text
    assert _pdf_bodies(client, token) == before


def test_no_korean_default_sentence_is_made_up(client):
    token = _token(client)
    before = _pdf_bodies(client, token).count("이번 주 리포트입니다.")

    _post(client, token, {"message": " ", "client_request_id": f"ko-{uuid4().hex[:12]}"})

    assert _pdf_bodies(client, token).count("이번 주 리포트입니다.") == before


def test_message_is_trimmed_and_stored(client):
    token = _token(client)

    response = _post(
        client,
        token,
        {"message": "  Great week!  ", "client_request_id": f"ok-{uuid4().hex[:12]}"},
    )

    assert response.status_code == 201, response.text
    assert response.json()["body"] == "Great week!"


def test_same_key_same_message_is_one_send(client):
    token = _token(client)
    key = f"retry-{uuid4().hex[:12]}"

    first = _post(client, token, {"message": "같은 글", "client_request_id": key})
    again = _post(client, token, {"message": "같은 글", "client_request_id": key})

    assert first.status_code == 201, first.text
    assert again.status_code == 201, again.text
    assert again.json()["id"] == first.json()["id"]


def test_same_key_different_message_is_409(client):
    token = _token(client)
    key = f"conflict-{uuid4().hex[:12]}"

    first = _post(client, token, {"message": "처음 글", "client_request_id": key})
    changed = _post(client, token, {"message": "고친 글", "client_request_id": key})

    assert first.status_code == 201, first.text
    assert changed.status_code == 409, changed.text


def test_new_key_with_changed_message_is_sent(client):
    """앱은 문구가 바뀌면 새 키를 쓴다(#2773) — 서버는 새 전송으로 받는다."""
    token = _token(client)

    first = _post(
        client, token, {"message": "처음 글", "client_request_id": f"a-{uuid4().hex[:12]}"}
    )
    changed = _post(
        client, token, {"message": "고친 글", "client_request_id": f"b-{uuid4().hex[:12]}"}
    )

    assert first.status_code == 201, first.text
    assert changed.status_code == 201, changed.text
    assert changed.json()["id"] != first.json()["id"]
