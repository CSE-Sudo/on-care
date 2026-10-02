"""동시 요청의 유일 제약 위반 409·목록 N+1·오류 형식·감사 로그 이메일. (#2911)

1. 같은 새 이메일로 프로필을 바꾸는 요청이 겹치면 한쪽은 409 다(500 아님).
2. 같은 회원의 담당 복구·담당 요청 수락·연결 코드가 겹치면 한쪽은 409 다.
3. 일정 개인운동 목록의 쿼리 수가 행 수에 비례해 늘지 않는다.
4. 객체 `detail` 은 모두 `code` 를 단다.
5. 감사 로그에 실패한 가입·로그인 이메일 원문이 남지 않는다.

경쟁은 **선검사 조회를 건너뛰게 해** 재현한다 — 두 요청이 동시에 조회를 통과한
상태와 같다. DB 가 필요한 것은 로컬에서 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

import ast
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import pytest
from sqlalchemy import event, false, select

from app.core.security import hash_password
from app.models.models import (
    AuditLog,
    HealthProfile,
    MemberGym,
    MemberPairingCode,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    TrainerRoutine,
    TrainerSchedule,
    User,
)
from app.services import trainer_client_invite_service
from app.services.trainer import client_status as trainer_client_status_service
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import schedule as trainer_schedule_service
from app.services.audit_email import PREFIX, masked_email

EMAIL_PREFIX = "race2911-"
PLACE_PREFIX = "race2911-place-"
PASSWORD = "race2911-pw-1234"
APP_DIR = Path(__file__).resolve().parents[1] / "app"


# ---------------------------------------------------------------------------
# 공통
# ---------------------------------------------------------------------------


@pytest.fixture
def cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        for model, column in (
            (TrainerRoutine, TrainerRoutine.member_id),
            (MemberPairingCode, MemberPairingCode.member_id),
            (Notification, Notification.user_id),
            (MemberGym, MemberGym.member_id),
            (HealthProfile, HealthProfile.user_id),
        ):
            db_session.query(model).filter(column.in_(user_ids)).delete(
                synchronize_session=False
            )
        db_session.query(TrainerSchedule).filter(
            TrainerSchedule.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerClientInvite).filter(
            (TrainerClientInvite.trainer_id.in_(user_ids))
            | (TrainerClientInvite.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerClient).filter(
            (TrainerClient.trainer_id.in_(user_ids))
            | (TrainerClient.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(MemberGym).filter(
        MemberGym.gym_id.like(f"{PLACE_PREFIX}%")
    ).delete(synchronize_session=False)
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
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


def _member(client) -> tuple[str, str, str]:
    """회원 하나. (id, email, token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "경쟁 회원",
            "phone": "010-1234-5678",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], email, _login(client, email)


def _trainer(db_session) -> str:
    suffix = uuid4().hex[:10]
    place = Place(
        id=f"{PLACE_PREFIX}{suffix}",
        name="경쟁 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    trainer = User(
        id=f"race2911-trainer-{suffix}",
        email=f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com",
        name="경쟁 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=place.id))
    db_session.commit()
    return trainer.id


def _link(db_session, trainer_id: str, member_id: str, *, active: bool) -> TrainerClient:
    link = TrainerClient(
        id=f"race2911-link-{uuid4().hex[:10]}",
        trainer_id=trainer_id,
        member_id=member_id,
        active=active,
        data_consent_at=datetime.now(timezone.utc),
    )
    db_session.add(link)
    db_session.commit()
    return link


def _skip_select(module, monkeypatch) -> None:
    """[module] 의 `select` 가 아무 행도 찾지 못하게 한다 — 선검사 우회."""
    real = module.select

    def never(*args, **kwargs):
        return real(*args, **kwargs).where(false())

    monkeypatch.setattr(module, "select", never)


def _active_trainers(db_session, member_id: str) -> list[str]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(TrainerClient.trainer_id).where(
                TrainerClient.member_id == member_id,
                TrainerClient.active.is_(True),
            )
        ).all()
    )


# ---------------------------------------------------------------------------
# 1. 이메일 변경 경쟁
# ---------------------------------------------------------------------------


def test_profile_email_race_is_409_not_500(client, db_session, cleanup, monkeypatch):
    from app.api.v1 import users as users_router

    _, taken_email, _ = _member(client)
    member_id, own_email, token = _member(client)
    _skip_select(users_router, monkeypatch)

    response = client.put(
        "/v1/users/me", json={"email": taken_email}, headers=_auth(token)
    )

    assert response.status_code == 409, response.text
    assert response.json() == {"detail": "이미 사용 중인 이메일입니다."}
    db_session.expire_all()
    assert db_session.get(User, member_id).email == own_email


def test_profile_email_race_keeps_other_fields_unsaved(
    client, db_session, cleanup, monkeypatch
):
    """409 는 요청 전체를 되돌린다 — 이메일만 빠지고 이름만 바뀌지 않는다."""
    from app.api.v1 import users as users_router

    _, taken_email, _ = _member(client)
    member_id, _, token = _member(client)
    _skip_select(users_router, monkeypatch)

    response = client.put(
        "/v1/users/me",
        json={"email": taken_email, "name": "바뀌면 안 됨"},
        headers=_auth(token),
    )

    assert response.status_code == 409, response.text
    db_session.expire_all()
    assert db_session.get(User, member_id).name == "경쟁 회원"


def test_profile_email_change_still_works(client, db_session, cleanup):
    member_id, _, token = _member(client)
    new_email = f"{EMAIL_PREFIX}moved-{uuid4().hex[:8]}@oncare.com"

    response = client.put(
        "/v1/users/me", json={"email": new_email}, headers=_auth(token)
    )

    assert response.status_code == 200, response.text
    assert response.json()["email"] == new_email


def test_profile_email_precheck_is_still_409(client, cleanup):
    _, taken_email, _ = _member(client)
    _, _, token = _member(client)

    response = client.put(
        "/v1/users/me", json={"email": taken_email}, headers=_auth(token)
    )

    assert response.status_code == 409, response.text


# ---------------------------------------------------------------------------
# 2. 담당 복구·수락·연결 코드 경쟁
# ---------------------------------------------------------------------------


def test_restore_race_raises_link_detached(client, db_session, cleanup, monkeypatch):
    member_id, _, _ = _member(client)
    holder = _trainer(db_session)
    restorer = _trainer(db_session)
    _link(db_session, holder, member_id, active=True)
    stale = _link(db_session, restorer, member_id, active=False)
    _skip_select(trainer_client_status_service, monkeypatch)

    with pytest.raises(trainer_common_service.ClientLinkDetached):
        trainer_client_status_service.restore_client(db_session, stale)

    assert _active_trainers(db_session, member_id) == [holder]


def test_restore_without_race_still_works(client, db_session, cleanup):
    member_id, _, _ = _member(client)
    restorer = _trainer(db_session)
    stale = _link(db_session, restorer, member_id, active=False)

    trainer_client_status_service.restore_client(db_session, stale)

    assert _active_trainers(db_session, member_id) == [restorer]


def test_invite_accept_race_is_member_already_coached(
    client, db_session, cleanup, monkeypatch
):
    member_id, _, _ = _member(client)
    holder = _trainer(db_session)
    inviter = _trainer(db_session)
    invite = TrainerClientInvite(
        id=f"tci-{uuid4().hex[:12]}",
        trainer_id=inviter,
        member_id=member_id,
        status="pending",
    )
    db_session.add(invite)
    db_session.commit()
    invite_id = invite.id
    _link(db_session, holder, member_id, active=True)
    _skip_select(trainer_client_invite_service, monkeypatch)

    with pytest.raises(trainer_client_invite_service.MemberAlreadyCoached):
        trainer_client_invite_service.accept(
            db_session, member_id, invite_id, data_sharing_consent=True
        )

    assert _active_trainers(db_session, member_id) == [holder]
    # 실패한 수락은 요청을 그대로 둔다.
    assert db_session.get(TrainerClientInvite, invite_id).status == "pending"


def test_pairing_redeem_race_is_409_and_keeps_the_code(
    client, db_session, cleanup, monkeypatch
):
    member_id, _, member_token = _member(client)
    holder = _trainer(db_session)
    redeemer = _trainer(db_session)
    code_response = client.post(
        "/v1/users/me/pairing-code", headers=_auth(member_token)
    )
    assert code_response.status_code == 200, code_response.text
    code = code_response.json()["code"]
    _link(db_session, holder, member_id, active=True)
    # 담당 확인을 통과한 상태 — 조회 사이에 다른 트레이너가 먼저 연결됐다.
    monkeypatch.setattr(
        trainer_client_invite_service, "_active_trainer_id", lambda db, _id: None
    )

    with pytest.raises(trainer_client_invite_service.MemberAlreadyCoached):
        trainer_client_invite_service.redeem_pairing_code(
            db_session, redeemer, code
        )

    assert _active_trainers(db_session, member_id) == [holder]
    assert (
        db_session.query(MemberPairingCode)
        .filter(MemberPairingCode.code == code)
        .count()
        == 1
    )


# ---------------------------------------------------------------------------
# 3. 일정 개인운동 목록 N+1
# ---------------------------------------------------------------------------


def _schedule_with_routines(db_session, trainer_id: str, member_id: str, count: int) -> str:
    schedule = TrainerSchedule(
        id=f"race2911-s-{uuid4().hex[:10]}",
        trainer_id=trainer_id,
        member_id=member_id,
        date="2026-10-01",
        time="10:00",
        client_name="경쟁 회원",
        duration_minutes=60,
    )
    db_session.add(schedule)
    db_session.flush()
    for index in range(count):
        db_session.add(
            TrainerRoutine(
                id=f"race2911-r-{uuid4().hex[:10]}",
                trainer_id=trainer_id,
                member_id=member_id,
                name="N+1 확인 걷기",
                minutes=30,
                type="유산소",
                schedule_id=schedule.id,
                delivery_kind="pt_with_routine",
                status="scheduled",
                sort_order=index,
                active_from="2026-10-01",
            )
        )
    db_session.commit()
    return schedule.id


def _set_goal_and_weight(db_session, member_id: str) -> None:
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        profile = HealthProfile(user_id=member_id)
        db_session.add(profile)
    profile.conditions = "혈압 관리"
    profile.weight_kg = 70.0
    db_session.commit()


def _count_queries(db_session, fn) -> int:
    engine = db_session.get_bind()
    seen: list[str] = []

    def listener(conn, cursor, statement, params, context, executemany):
        seen.append(statement)

    event.listen(engine, "before_cursor_execute", listener)
    try:
        fn()
    finally:
        event.remove(engine, "before_cursor_execute", listener)
    return len(seen)


def test_scheduled_routine_list_queries_do_not_grow_with_rows(
    client, db_session, cleanup
):
    member_id, _, _ = _member(client)
    trainer_id = _trainer(db_session)
    _set_goal_and_weight(db_session, member_id)
    one = _schedule_with_routines(db_session, trainer_id, member_id, 1)
    many = _schedule_with_routines(db_session, trainer_id, member_id, 6)

    # 운동 참조표 캐시 같은 첫 호출 비용을 먼저 치른다.
    trainer_schedule_service.list_scheduled_routines(db_session, trainer_id, one)
    db_session.expire_all()
    single = _count_queries(
        db_session,
        lambda: trainer_schedule_service.list_scheduled_routines(db_session, trainer_id, one),
    )
    db_session.expire_all()
    multiple = _count_queries(
        db_session,
        lambda: trainer_schedule_service.list_scheduled_routines(db_session, trainer_id, many),
    )

    assert multiple == single


def test_scheduled_routine_list_still_fills_effect_from_goals(
    client, db_session, cleanup
):
    """한 번 읽은 목표로도 효과 문구는 회원 목표를 따른다."""
    member_id, _, _ = _member(client)
    trainer_id = _trainer(db_session)
    _set_goal_and_weight(db_session, member_id)
    schedule_id = _schedule_with_routines(db_session, trainer_id, member_id, 3)

    rows = trainer_schedule_service.list_scheduled_routines(db_session, trainer_id, schedule_id)

    assert [row.effect for row in rows] == ["혈압 관리에 도움"] * 3
    single = trainer_common_service._routine_out(
        db_session, db_session.get(TrainerRoutine, rows[0].id)
    )
    # 한 건 응답(조회를 그때그때 하는 길)과 목록 응답이 같은 값이다.
    assert single.effect == rows[0].effect
    assert single.calories == rows[0].calories


# ---------------------------------------------------------------------------
# 4. 오류 응답 형식
# ---------------------------------------------------------------------------


def _object_details() -> list[tuple[str, int, ast.Dict]]:
    found: list[tuple[str, int, ast.Dict]] = []
    for path in APP_DIR.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            name = getattr(node.func, "id", None) or getattr(node.func, "attr", None)
            if name != "HTTPException":
                continue
            for keyword in node.keywords:
                if keyword.arg == "detail" and isinstance(keyword.value, ast.Dict):
                    found.append((str(path.relative_to(APP_DIR)), node.lineno, keyword.value))
    return found


def test_every_object_detail_carries_a_code():
    """객체 `detail` 은 화면이 분기하라고 주는 것이다 — `code` 없이는 분기할 수 없다."""
    found = _object_details()
    assert found, "객체 detail 을 하나도 찾지 못했다 — 검사가 빈 채로 통과하면 안 된다"
    missing = [
        f"{path}:{line}"
        for path, line, value in found
        if not any(
            isinstance(key, ast.Constant) and key.value == "code" for key in value.keys
        )
    ]
    assert missing == []


def test_overlap_detail_has_code_and_message():
    exc = trainer_schedule_service.ScheduleOverlap([], "겹쳐요")
    detail = trainer_schedule_service.overlap_detail(exc)
    assert detail["code"] == trainer_schedule_service.SCHEDULE_OVERLAP_CODE
    assert detail["message"] == "겹쳐요"


def test_attach_target_conflict_has_a_code():
    assert trainer_schedule_service.AttachTargetConflict.code == "attach_target_conflict"


# ---------------------------------------------------------------------------
# 5. 감사 로그 이메일
# ---------------------------------------------------------------------------


def test_masked_email_is_stable_and_not_the_original():
    raw = "someone@example.com"
    masked = masked_email(raw)
    assert masked.startswith(PREFIX)
    assert "someone" not in masked and "example.com" not in masked
    assert masked == masked_email(raw)
    # 대소문자·앞뒤 공백만 다른 입력은 같은 대상이다.
    assert masked == masked_email("  SomeOne@Example.com ")
    assert masked != masked_email("other@example.com")


def test_masked_email_of_nothing_is_empty():
    assert masked_email("") == ""
    assert masked_email("   ") == ""
    assert masked_email(None) == ""


def test_masked_email_depends_on_the_server_secret(monkeypatch):
    """키 없는 해시면 흔한 주소 목록으로 원문을 맞출 수 있다."""
    from app.core import config

    before = masked_email("someone@example.com")
    settings = config.get_settings()
    monkeypatch.setattr(settings, "jwt_secret", "another-secret-for-test-only")

    assert masked_email("someone@example.com") != before


def _failed_audits(db_session, event_name: str) -> list[AuditLog]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(AuditLog).where(
                AuditLog.event == event_name, AuditLog.success.is_(False)
            )
        ).all()
    )


def test_failed_login_audit_has_no_raw_email(client, db_session, cleanup):
    email = f"{EMAIL_PREFIX}nobody-{uuid4().hex[:8]}@oncare.com"

    response = client.post(
        "/v1/auth/login", data={"username": email, "password": "wrong-pw-1234"}
    )

    assert response.status_code == 401
    rows = _failed_audits(db_session, "auth.login")
    assert any(row.detail == masked_email(email) for row in rows)
    assert all(email not in (row.detail or "") for row in rows)


def test_duplicate_register_audit_has_no_raw_email(client, db_session, cleanup):
    _, email, _ = _member(client)

    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "중복"},
    )

    assert response.status_code == 409
    rows = _failed_audits(db_session, "auth.register")
    assert any(row.detail == masked_email(email) for row in rows)
    assert all(email not in (row.detail or "") for row in rows)
