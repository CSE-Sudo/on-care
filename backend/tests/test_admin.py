"""관리자 권한 — 공공문서 업로드 보호.

- 관리자는 기동 설정(ADMIN_EMAILS)이 아니라 운영 스크립트로만 정한다(#3037,
  `test_grant_admin_script`).
- 엔드포인트 보호(201/403/401)는 DB 필요(로컬 skip, CI 실행).
- 적재 실패 응답이 내부 예외 문자열을 싣지 않는지도 여기서 본다(#1556).
"""
from __future__ import annotations

from uuid import uuid4


def test_admin_emails_no_longer_promote_on_startup():
    """기동 코드에 이메일로 관리자를 올리는 경로가 없다(#3037).

    예전에는 그 주소로 먼저 가입한 사람이 다음 배포 때 관리자가 됐다.
    """
    import inspect

    from app.core.config import Settings
    from app.db import init_db

    assert not hasattr(init_db, "_promote_admins")
    assert not hasattr(init_db, "admin_promotion_targets")
    assert "is_admin = True" not in inspect.getsource(init_db)
    assert not hasattr(Settings, "admin_email_set")


def _register_login(client, email: str) -> str:
    client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"})
    return client.post("/v1/auth/login", data={"username": email, "password": "test-pw-1234"}).json()["access_token"]


def test_admin_can_upload_public_doc(client, db_session):
    from sqlalchemy import select

    from app.models.models import User

    email = f"admin-{uuid4().hex[:8]}@oncare.com"
    token = _register_login(client, email)

    # 관리자로 지정(운영에선 scripts/grant_admin.py, #3037)
    user = db_session.scalar(select(User).where(User.email == email))
    user.is_admin = True
    db_session.commit()

    r = client.post(
        "/v1/coach/documents/public",
        json={
            "content": "물을 충분히 마시면 혈압 관리에 도움이 됩니다. 하루 6잔 이상을 권장합니다.",
            "domain": "general",
            "title": "수분 섭취 팁",
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 201, r.text
    assert r.json()["ingested_chunks"] >= 1


def test_non_admin_is_forbidden(client):
    email = f"user-{uuid4().hex[:8]}@oncare.com"
    token = _register_login(client, email)
    r = client.post(
        "/v1/coach/documents/public",
        json={"content": "test", "title": "t"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 403


def test_unauthenticated_is_rejected(client):
    # require_admin 은 데모 폴백을 쓰지 않으므로 토큰 없으면 401
    r = client.post("/v1/coach/documents/public", json={"content": "test", "title": "t"})
    assert r.status_code == 401


def _promote_admin(client, db_session) -> str:
    """관리자 토큰 하나. (운영에서는 scripts/grant_admin.py 로 지정한다, #3037)"""
    from sqlalchemy import select

    from app.models.models import User

    email = f"admin-{uuid4().hex[:8]}@oncare.com"
    token = _register_login(client, email)
    user = db_session.scalar(select(User).where(User.email == email))
    user.is_admin = True
    db_session.commit()
    return token


#: 예외 문자열에 섞일 수 있는 내부 정보를 대신하는 표식.
SECRET = "postgresql://oncare:pw@db.internal:5432/oncare"


def test_ingest_failure_hides_internal_exception_text(client, db_session, monkeypatch):
    """적재 실패 응답에 예외 문자열이 실리지 않는다. (#1556)

    SDK·DB·파일 경로 오류의 문자열이 그대로 detail 에 들어가던 자리다.
    """
    from app.api.v1 import coach_docs

    def _boom(*args, **kwargs):
        raise ValueError(SECRET)

    monkeypatch.setattr(coach_docs, "ingest_document", _boom)
    token = _promote_admin(client, db_session)

    r = client.post(
        "/v1/coach/documents/public",
        json={"content": "문서 본문", "domain": "general", "title": "t"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert r.status_code == 502, r.text
    assert SECRET not in r.text
    assert r.json()["detail"] == "문서를 적재하지 못했어요."
    # 서버 로그와 상관지을 수단은 남아 있어야 한다.
    assert r.headers.get("X-Request-ID")


def test_embedding_unavailable_hides_internal_exception_text(
    client, db_session, monkeypatch
):
    """임베딩 불가(503)도 마찬가지 — 설정 값이 섞일 수 있다."""
    from app.api.v1 import coach_docs

    def _boom(*args, **kwargs):
        raise RuntimeError(SECRET)

    monkeypatch.setattr(coach_docs, "ingest_document", _boom)
    token = _promote_admin(client, db_session)

    r = client.post(
        "/v1/coach/documents/public",
        json={"content": "문서 본문", "domain": "general", "title": "t"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert r.status_code == 503, r.text
    assert SECRET not in r.text
