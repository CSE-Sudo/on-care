"""채팅 발신·스케줄 생성의 재시도 멱등성 (#605)."""
from __future__ import annotations

import importlib
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import inspect, or_, select

from app.models.models import ChatMessage, Notification, TrainerSchedule

TRAINER = "trainer-demo"
MEMBER = "user-jisu"
OTHER_MEMBER = "user-7d4e9a2c5f18"
KEY_PREFIX = "idem605-"


def _trainer_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _member_token(client, email: str = "jisu@oncare.com") -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    ).json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _key() -> str:
    return f"{KEY_PREFIX}{uuid4().hex[:12]}"


def _schedule_body(
    key: str | None, *, note: str = "", time: str = "16:00"
) -> dict:
    body = {
        "date": "2026-12-31",
        "time": time,
        "client_name": "신규 상담",
        "type": "상담",
        "duration_minutes": 30,
        "note": note,
    }
    if key is not None:
        body["client_request_id"] = key
    return body


def _purge(db_session) -> None:
    db_session.rollback()
    db_session.query(Notification).filter(
        Notification.body.like(f"%{KEY_PREFIX}%")
    ).delete(synchronize_session=False)
    db_session.query(ChatMessage).filter(
        or_(
            ChatMessage.client_request_id.like(f"{KEY_PREFIX}%"),
            ChatMessage.body.like(f"{KEY_PREFIX}%"),
        )
    ).delete(synchronize_session=False)
    db_session.query(TrainerSchedule).filter(
        or_(
            TrainerSchedule.client_request_id.like(f"{KEY_PREFIX}%"),
            TrainerSchedule.note.like(f"{KEY_PREFIX}%"),
        )
    ).delete(synchronize_session=False)
    db_session.commit()


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    _purge(db_session)
    yield
    _purge(db_session)


def _chat_rows(db_session, key: str) -> list[ChatMessage]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(ChatMessage).where(ChatMessage.client_request_id == key)
        ).all()
    )


def _schedule_rows(db_session, key: str) -> list[TrainerSchedule]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(TrainerSchedule).where(
                TrainerSchedule.client_request_id == key
            )
        ).all()
    )


def test_migration_preserves_existing_rows(db_session, monkeypatch):
    migration = importlib.import_module(
        "migrations.versions.0031_create_action_request_ids"
    )
    schema = f"idem605_{uuid4().hex[:12]}"
    metadata = sa.MetaData(schema=schema)
    chat = sa.Table(
        "chat_messages",
        metadata,
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("trainer_id", sa.String(64), nullable=False),
        sa.Column("member_id", sa.String(64), nullable=False),
        sa.Column("sender", sa.String(20), nullable=False),
    )
    schedule = sa.Table(
        "trainer_schedule",
        metadata,
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("trainer_id", sa.String(64), nullable=False),
    )

    engine = db_session.get_bind()
    with engine.begin() as connection:
        connection.execute(sa.schema.CreateSchema(schema))
        try:
            metadata.create_all(connection)
            connection.execute(
                chat.insert(),
                [
                    {
                        "id": "old-chat-1",
                        "trainer_id": "trainer-a",
                        "member_id": "member-a",
                        "sender": "trainer",
                    },
                    {
                        "id": "old-chat-2",
                        "trainer_id": "trainer-b",
                        "member_id": "member-b",
                        "sender": "member",
                    },
                ],
            )
            connection.execute(
                schedule.insert(),
                [
                    {"id": "old-schedule-1", "trainer_id": "trainer-a"},
                    {"id": "old-schedule-2", "trainer_id": "trainer-b"},
                ],
            )
            connection.exec_driver_sql(f'SET LOCAL search_path TO "{schema}"')
            operations = Operations(MigrationContext.configure(connection))
            monkeypatch.setattr(migration, "op", operations)

            migration.upgrade()

            inspector = inspect(connection)
            chat_columns = {
                column["name"]: column
                for column in inspector.get_columns("chat_messages", schema=schema)
            }
            schedule_columns = {
                column["name"]: column
                for column in inspector.get_columns(
                    "trainer_schedule", schema=schema
                )
            }
            assert chat_columns["client_request_id"]["nullable"] is True
            assert schedule_columns["client_request_id"]["nullable"] is True
            assert "uq_chat_messages_client_request" in {
                constraint["name"]
                for constraint in inspector.get_unique_constraints(
                    "chat_messages", schema=schema
                )
            }
            assert "uq_trainer_schedule_client_request" in {
                constraint["name"]
                for constraint in inspector.get_unique_constraints(
                    "trainer_schedule", schema=schema
                )
            }
            assert connection.scalars(
                select(chat.c.id).order_by(chat.c.id)
            ).all() == ["old-chat-1", "old-chat-2"]
            assert connection.scalars(
                select(schedule.c.id).order_by(schedule.c.id)
            ).all() == ["old-schedule-1", "old-schedule-2"]

            migration.downgrade()
            inspector.clear_cache()
            assert "client_request_id" not in {
                column["name"]
                for column in inspector.get_columns("chat_messages", schema=schema)
            }
            assert "client_request_id" not in {
                column["name"]
                for column in inspector.get_columns(
                    "trainer_schedule", schema=schema
                )
            }
        finally:
            connection.execute(sa.schema.DropSchema(schema, cascade=True))


def test_trainer_chat_retry_returns_the_same_message(client, db_session):
    token = _trainer_token(client)
    key = _key()
    url = f"/v1/trainer/clients/{MEMBER}/chat"
    body = {"text": f"{KEY_PREFIX}trainer-retry", "client_request_id": key}

    first = client.post(url, json=body, headers=_headers(token))
    second = client.post(url, json=body, headers=_headers(token))

    assert first.status_code == second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    assert len(_chat_rows(db_session, key)) == 1
    db_session.expire_all()
    assert (
        db_session.query(Notification)
        .filter_by(body=f"{KEY_PREFIX}trainer-retry")
        .count()
        == 1
    )


def test_member_chat_retry_returns_the_same_message(client, db_session):
    token = _member_token(client)
    key = _key()
    body = {"text": f"{KEY_PREFIX}member-retry", "client_request_id": key}

    first = client.post("/v1/me/coach/chat", json=body, headers=_headers(token))
    second = client.post("/v1/me/coach/chat", json=body, headers=_headers(token))

    assert first.status_code == second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    assert len(_chat_rows(db_session, key)) == 1


def test_schedule_retry_returns_the_same_session(client, db_session):
    token = _trainer_token(client)
    key = _key()
    body = _schedule_body(key)

    first = client.post("/v1/trainer/schedule", json=body, headers=_headers(token))
    second = client.post("/v1/trainer/schedule", json=body, headers=_headers(token))

    assert first.status_code == second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    assert len(_schedule_rows(db_session, key)) == 1


@pytest.mark.parametrize(
    ("path", "first", "second"),
    [
        (
            f"/v1/trainer/clients/{MEMBER}/chat",
            {"text": f"{KEY_PREFIX}first"},
            {"text": f"{KEY_PREFIX}different"},
        ),
        (
            "/v1/trainer/schedule",
            _schedule_body(None),
            _schedule_body(None, note="다른 payload"),
        ),
    ],
)
def test_same_key_with_different_payload_is_conflict(client, path, first, second):
    token = _trainer_token(client)
    key = _key()
    first["client_request_id"] = key
    second["client_request_id"] = key

    created = client.post(path, json=first, headers=_headers(token))
    conflict = client.post(path, json=second, headers=_headers(token))

    assert created.status_code == 201
    assert conflict.status_code == 409


def test_different_keys_and_missing_keys_keep_creating(client, db_session):
    token = _trainer_token(client)
    first = client.post(
        "/v1/trainer/schedule",
        json=_schedule_body(_key()),
        headers=_headers(token),
    )
    # 같은 시간이면 겹침(#2284)으로 409 가 나므로 시각만 달리한다 — 여기서 보는
    # 것은 키가 다르거나 없을 때 멱등 재생으로 합쳐지지 않는다는 점이다.
    second = client.post(
        "/v1/trainer/schedule",
        json=_schedule_body(_key(), time="17:00"),
        headers=_headers(token),
    )
    third = client.post(
        "/v1/trainer/schedule",
        json=_schedule_body(None, note=f"{KEY_PREFIX}no-key", time="18:00"),
        headers=_headers(token),
    )
    fourth = client.post(
        "/v1/trainer/schedule",
        json=_schedule_body(None, note=f"{KEY_PREFIX}no-key", time="19:00"),
        headers=_headers(token),
    )

    assert {
        first.status_code,
        second.status_code,
        third.status_code,
        fourth.status_code,
    } == {201}
    assert len({first.json()["id"], second.json()["id"]}) == 2
    assert third.json()["id"] != fourth.json()["id"]

    chat_url = f"/v1/trainer/clients/{MEMBER}/chat"
    first_chat = client.post(
        chat_url, json={"text": f"{KEY_PREFIX}no-key"}, headers=_headers(token)
    )
    second_chat = client.post(
        chat_url, json={"text": f"{KEY_PREFIX}no-key"}, headers=_headers(token)
    )
    assert first_chat.status_code == second_chat.status_code == 201
    assert first_chat.json()["id"] != second_chat.json()["id"]
    db_session.expire_all()


def test_same_key_is_isolated_by_user_sender_and_operation(client, db_session):
    key = _key()
    trainer = _trainer_token(client)
    member = _member_token(client)
    other_member = _member_token(client, "minsu@oncare.com")

    trainer_chat = client.post(
        f"/v1/trainer/clients/{MEMBER}/chat",
        json={"text": f"{KEY_PREFIX}trainer", "client_request_id": key},
        headers=_headers(trainer),
    )
    member_chat = client.post(
        "/v1/me/coach/chat",
        json={"text": f"{KEY_PREFIX}member", "client_request_id": key},
        headers=_headers(member),
    )
    other_member_chat = client.post(
        "/v1/me/coach/chat",
        json={"text": f"{KEY_PREFIX}other-member", "client_request_id": key},
        headers=_headers(other_member),
    )
    schedule = client.post(
        "/v1/trainer/schedule",
        json=_schedule_body(key, note="작업격리"),
        headers=_headers(trainer),
    )

    assert {
        trainer_chat.status_code,
        member_chat.status_code,
        other_member_chat.status_code,
        schedule.status_code,
    } == {201}
    chat_rows = _chat_rows(db_session, key)
    assert len(chat_rows) == 3
    assert {(row.member_id, row.sender) for row in chat_rows} == {
        (MEMBER, "trainer"),
        (MEMBER, "member"),
        (OTHER_MEMBER, "member"),
    }
    assert len(_schedule_rows(db_session, key)) == 1


@pytest.mark.parametrize("operation", ["chat", "schedule"])
def test_concurrent_same_key_creates_one_row(client, db_session, operation):
    token = (
        _member_token(client)
        if operation == "chat"
        else _trainer_token(client)
    )
    key = _key()
    barrier = Barrier(2)
    chat_body = f"{KEY_PREFIX}concurrent"
    schedule_type = f"{KEY_PREFIX}schedule"

    def send():
        barrier.wait()
        if operation == "chat":
            return client.post(
                "/v1/me/coach/chat",
                json={"text": chat_body, "client_request_id": key},
                headers=_headers(token),
            )
        body = _schedule_body(key)
        body.update(
            {
                "client_name": "이지수",
                "member_id": MEMBER,
                "type": schedule_type,
            }
        )
        return client.post(
            "/v1/trainer/schedule",
            json=body,
            headers=_headers(token),
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = [
            future.result(timeout=15)
            for future in [pool.submit(send), pool.submit(send)]
        ]

    assert [response.status_code for response in responses] == [201, 201]
    assert len({response.json()["id"] for response in responses}) == 1
    rows = (
        _chat_rows(db_session, key)
        if operation == "chat"
        else _schedule_rows(db_session, key)
    )
    assert len(rows) == 1
    db_session.expire_all()
    expected_body = (
        chat_body
        if operation == "chat"
        else f"12월 31일 16:00 · {schedule_type}"
    )
    expected_user = TRAINER if operation == "chat" else MEMBER
    assert (
        db_session.query(Notification)
        .filter_by(user_id=expected_user, body=expected_body)
        .count()
        == 1
    )
