"""보안 감사 로그 — DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from uuid import uuid4


def test_login_and_register_events_are_audited(client, db_session):
    from sqlalchemy import select

    from app.models.models import AuditLog

    email = f"aud-{uuid4().hex[:8]}@oncare.com"
    reg = client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"})
    uid = reg.json()["id"]

    client.post("/v1/auth/login", data={"username": email, "password": "wrong-pw"})  # 실패
    client.post("/v1/auth/login", data={"username": email, "password": "test-pw-1234"})        # 성공

    db_session.expire_all()

    # 가입 감사
    regs = db_session.scalars(
        select(AuditLog).where(AuditLog.event == "auth.register", AuditLog.user_id == uid)
    ).all()
    assert len(regs) >= 1

    # 로그인 실패 감사(detail=시도 이메일의 가명값, success=False). 원문은 남기지
    # 않는다(#2911).
    from app.services.audit_email import masked_email

    fails = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == "auth.login",
            AuditLog.success.is_(False),
            AuditLog.detail == masked_email(email),
        )
    ).all()
    assert len(fails) >= 1
    assert all(email not in (row.detail or "") for row in fails)

    # 로그인 성공 감사(user_id 기록, success=True)
    oks = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == "auth.login",
            AuditLog.success.is_(True),
            AuditLog.user_id == uid,
        )
    ).all()
    assert len(oks) >= 1


def test_admin_upload_is_audited(client, db_session):
    from sqlalchemy import select

    from app.models.models import AuditLog, User

    email = f"aud-admin-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "a"})
    user = db_session.scalar(select(User).where(User.email == email))
    user.is_admin = True
    db_session.commit()
    token = client.post("/v1/auth/login", data={"username": email, "password": "test-pw-1234"}).json()["access_token"]

    client.post(
        "/v1/coach/documents/public",
        json={
            "content": "충분한 수면은 혈압 관리에 도움이 됩니다. 하루 7시간 이상을 권장합니다.",
            "title": "수면 팁",
            "domain": "general",
        },
        headers={"Authorization": f"Bearer {token}"},
    )

    db_session.expire_all()
    rows = db_session.scalars(
        select(AuditLog).where(
            AuditLog.event == "admin.public_doc_upload", AuditLog.user_id == user.id
        )
    ).all()
    assert len(rows) >= 1
