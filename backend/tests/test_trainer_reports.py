"""회원의 트레이너 신고와 운영자의 신고·계정 관리. (#3008)

트레이너 운영자 승인 절차를 없앴으므로 소속 사칭·부적절한 메시지는 회원 신고로
드러나고, 운영자가 트레이너 웹 `신고·계정 관리` 화면에서 처리한다.

여기서 보는 것:

  * `POST /trainers/{id}/reports` — 회원만, 사유 셋(기타는 메모 필수), 메모 200자.
  * 같은 트레이너를 처리 전에 다시 신고하면 409 `report_already_open`, 처리 뒤엔 다시 된다.
  * 없는 트레이너·회원 id 404, 트레이너 403, 미인증 401.
  * 운영자 목록(`open`·`closed`·`all`)에 신고한 회원이 실리지 않는다. 관리자만.
  * 처리(조치함·넘김) 한 번만, 감사 로그에 남는다.
  * 운영 트레이너 목록 — 이름·이메일 검색, 정지 상태 필터, 처리 전 신고 수와 정렬.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from uuid import uuid4

from sqlalchemy import select

from app.models.models import AuditLog, User
from tests.test_trainer_no_approval import (  # noqa: F401 — 자동 정리 픽스처
    _admin,
    _auth,
    _cleanup,
    _gym,
    _login,
    _member,
    _seeded_trainer,
)


def _report(client, token: str, trainer_id: str, **body):
    payload = {"reason": "impersonation", "memo": ""}
    payload.update(body)
    return client.post(
        f"/v1/trainers/{trainer_id}/reports", headers=_auth(token), json=payload
    )


def _trainer(db_session) -> User:
    trainer, _ = _seeded_trainer(db_session, _gym(db_session))
    return trainer


def _reports(client, admin_token: str, status: str = "open") -> list[dict]:
    response = client.get(
        f"/v1/admin/trainer-reports?status={status}", headers=_auth(admin_token)
    )
    assert response.status_code == 200, response.text
    return response.json()


def _close(client, admin_token: str, report_id: str, outcome: str):
    return client.post(
        f"/v1/admin/trainer-reports/{report_id}/close",
        headers=_auth(admin_token),
        json={"outcome": outcome},
    )


# ---------------------------------------------------------------------------
# 회원 신고
# ---------------------------------------------------------------------------


def test_member_reports_a_trainer(client, db_session):
    trainer = _trainer(db_session)
    _, member_token = _member(client)

    response = _report(
        client, member_token, trainer.id, reason="inappropriate_message", memo=" 욕설 "
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "open"
    assert body["id"]
    assert body["created_at"]


def test_reporting_the_same_trainer_twice_is_409(client, db_session):
    trainer = _trainer(db_session)
    _, member_token = _member(client)
    assert _report(client, member_token, trainer.id).status_code == 201

    again = _report(client, member_token, trainer.id, reason="other", memo="또")

    assert again.status_code == 409
    assert again.json()["detail"]["code"] == "report_already_open"


def test_other_members_can_report_the_same_trainer(client, db_session):
    trainer = _trainer(db_session)
    _, first = _member(client)
    _, second = _member(client)

    assert _report(client, first, trainer.id).status_code == 201
    assert _report(client, second, trainer.id).status_code == 201


def test_report_again_after_it_is_closed(client, db_session):
    trainer = _trainer(db_session)
    _, member_token = _member(client)
    _, admin_token = _admin(client, db_session)
    report_id = _report(client, member_token, trainer.id).json()["id"]
    assert _close(client, admin_token, report_id, "dismissed").status_code == 200

    assert _report(client, member_token, trainer.id).status_code == 201


def test_other_reason_needs_a_memo(client, db_session):
    trainer = _trainer(db_session)
    _, member_token = _member(client)

    assert _report(client, member_token, trainer.id, reason="other").status_code == 422
    assert (
        _report(client, member_token, trainer.id, reason="other", memo="   ").status_code
        == 422
    )


def test_memo_is_capped_and_reason_is_closed_set(client, db_session):
    trainer = _trainer(db_session)
    _, member_token = _member(client)

    assert (
        _report(client, member_token, trainer.id, memo="가" * 201).status_code == 422
    )
    assert _report(client, member_token, trainer.id, reason="spam").status_code == 422


def test_report_unknown_or_non_trainer_is_404(client, db_session):
    member_id, member_token = _member(client)
    other_id, _ = _member(client)

    assert _report(client, member_token, f"nobody-{uuid4().hex[:8]}").status_code == 404
    assert _report(client, member_token, other_id).status_code == 404
    assert _report(client, member_token, member_id).status_code == 404


def test_only_members_report(client, db_session):
    trainer = _trainer(db_session)
    _, other_email = _seeded_trainer(db_session, _gym(db_session))
    trainer_token = _login(client, other_email)

    assert _report(client, trainer_token, trainer.id).status_code == 403
    assert (
        client.post(
            f"/v1/trainers/{trainer.id}/reports",
            json={"reason": "impersonation", "memo": ""},
        ).status_code
        == 401
    )


# ---------------------------------------------------------------------------
# 운영자 신고 목록·처리
# ---------------------------------------------------------------------------


def test_admin_sees_open_reports_without_the_reporter(client, db_session):
    trainer = _trainer(db_session)
    member_id, member_token = _member(client)
    _, admin_token = _admin(client, db_session)
    report_id = _report(
        client, member_token, trainer.id, reason="other", memo="소속이 달라요"
    ).json()["id"]

    row = next(r for r in _reports(client, admin_token) if r["id"] == report_id)

    assert row["trainer_id"] == trainer.id
    assert row["trainer_name"] == trainer.name
    assert row["trainer_email"] == trainer.email
    assert row["trainer_is_active"] is True
    assert row["reason"] == "other"
    assert row["memo"] == "소속이 달라요"
    assert row["status"] == "open"
    assert row["resolved_at"] is None
    assert member_id not in str(row)
    assert not any(key.startswith("reporter") for key in row)


def test_admin_report_list_filters_by_status(client, db_session):
    trainer = _trainer(db_session)
    _, first = _member(client)
    _, second = _member(client)
    _, admin_token = _admin(client, db_session)
    open_id = _report(client, first, trainer.id).json()["id"]
    closed_id = _report(client, second, trainer.id).json()["id"]
    assert _close(client, admin_token, closed_id, "resolved").status_code == 200

    open_ids = {r["id"] for r in _reports(client, admin_token, "open")}
    closed_ids = {r["id"] for r in _reports(client, admin_token, "closed")}
    all_ids = {r["id"] for r in _reports(client, admin_token, "all")}

    assert open_id in open_ids and closed_id not in open_ids
    assert closed_id in closed_ids and open_id not in closed_ids
    assert {open_id, closed_id} <= all_ids
    assert (
        client.get(
            "/v1/admin/trainer-reports?status=bogus", headers=_auth(admin_token)
        ).status_code
        == 422
    )


def test_report_admin_routes_are_admin_only(client, db_session):
    trainer = _trainer(db_session)
    _, member_token = _member(client)
    report_id = _report(client, member_token, trainer.id).json()["id"]

    assert (
        client.get("/v1/admin/trainer-reports", headers=_auth(member_token)).status_code
        == 403
    )
    assert _close(client, member_token, report_id, "resolved").status_code == 403
    assert client.get("/v1/admin/trainer-reports").status_code == 401
    assert (
        client.get("/v1/admin/trainers", headers=_auth(member_token)).status_code == 403
    )


def test_close_once_and_unknown_is_404(client, db_session):
    trainer = _trainer(db_session)
    _, member_token = _member(client)
    _, admin_token = _admin(client, db_session)
    report_id = _report(client, member_token, trainer.id).json()["id"]

    closed = _close(client, admin_token, report_id, "resolved")
    assert closed.status_code == 200, closed.text
    assert closed.json()["status"] == "resolved"
    assert closed.json()["resolved_at"] is not None

    assert _close(client, admin_token, report_id, "dismissed").status_code == 409
    assert _close(client, admin_token, f"trp-{uuid4().hex[:12]}", "resolved").status_code == 404
    assert _close(client, admin_token, report_id, "open").status_code == 422


def test_close_is_audited(client, db_session):
    trainer = _trainer(db_session)
    _, member_token = _member(client)
    admin_id, admin_token = _admin(client, db_session)
    report_id = _report(client, member_token, trainer.id).json()["id"]
    assert _close(client, admin_token, report_id, "dismissed").status_code == 200

    details = db_session.scalars(
        select(AuditLog.detail).where(
            AuditLog.event == "admin.trainer_report_close",
            AuditLog.user_id == admin_id,
            AuditLog.target_user_id == trainer.id,
        )
    ).all()
    assert f"{report_id}:dismissed" in details


# ---------------------------------------------------------------------------
# 운영 트레이너 목록
# ---------------------------------------------------------------------------


def test_admin_trainer_search_and_state(client, db_session):
    trainer = _trainer(db_session)
    _, admin_token = _admin(client, db_session)
    token = trainer.email.split("@")[0][-8:]

    found = client.get(
        f"/v1/admin/trainers?q={token.upper()}", headers=_auth(admin_token)
    )
    assert found.status_code == 200, found.text
    assert [r["trainer_id"] for r in found.json()] == [trainer.id]
    assert found.json()[0]["is_active"] is True

    suspended = client.post(
        f"/v1/admin/users/{trainer.id}/suspend", headers=_auth(admin_token)
    )
    assert suspended.status_code == 200, suspended.text

    active_ids = {
        r["trainer_id"]
        for r in client.get(
            f"/v1/admin/trainers?q={token}&state=active", headers=_auth(admin_token)
        ).json()
    }
    suspended_ids = {
        r["trainer_id"]
        for r in client.get(
            f"/v1/admin/trainers?q={token}&state=suspended", headers=_auth(admin_token)
        ).json()
    }
    assert trainer.id not in active_ids
    assert trainer.id in suspended_ids
    assert (
        client.get("/v1/admin/trainers?state=bogus", headers=_auth(admin_token)).status_code
        == 422
    )


def test_admin_trainer_list_counts_open_reports_first(client, db_session):
    quiet = _trainer(db_session)
    reported = _trainer(db_session)
    _, first = _member(client)
    _, second = _member(client)
    _, admin_token = _admin(client, db_session)
    assert _report(client, first, reported.id).status_code == 201
    assert _report(client, second, reported.id).status_code == 201

    rows = client.get(
        "/v1/admin/trainers?q=verify-test-seeded", headers=_auth(admin_token)
    ).json()
    by_id = {r["trainer_id"]: r for r in rows}

    assert by_id[reported.id]["open_reports"] == 2
    assert by_id[quiet.id]["open_reports"] == 0
    order = [r["trainer_id"] for r in rows]
    assert order.index(reported.id) < order.index(quiet.id)


def test_admin_trainer_search_escapes_like_wildcards(client, db_session):
    _trainer(db_session)
    _, admin_token = _admin(client, db_session)

    rows = client.get(
        "/v1/admin/trainers?q=verify%25test", headers=_auth(admin_token)
    ).json()

    assert rows == []
