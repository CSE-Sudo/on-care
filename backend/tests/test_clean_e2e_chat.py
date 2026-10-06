"""채팅 E2E 정리 스크립트는 마커를 글자 그대로 찾는다. (#3251)

`LIKE` 에 마커를 그대로 넣으면 `--marker %`·`_` 가 와일드카드가 되어 그 DB 의 채팅
전체와 채팅 RAG 문서가 지워졌다.

빈 마커 거절은 DB 없이, 삭제 범위는 DB 로 확인한다(로컬 skip, CI 실행).
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import delete, select

from app.db.init_db import DEMO_USER_ID
from app.db.seed_trainer import TRAINER_ID
from app.models.models import ChatMessage
from scripts import clean_e2e_chat


def test_blank_marker_is_refused_before_touching_the_db(capsys):
    assert clean_e2e_chat.main(["--marker", "   "]) == 2
    assert "중단" in capsys.readouterr().err


def test_purge_refuses_an_empty_marker():
    with pytest.raises(ValueError):
        clean_e2e_chat.purge(None, "")  # type: ignore[arg-type]


@pytest.fixture
def messages(db_session):
    tag = uuid4().hex[:8]
    bodies = {
        "plain": f"t3251 평범한 메시지 {tag}",
        "marked": f"t3251 e2e%_{tag} 마커가 든 메시지",
    }
    ids = {}
    for key, body in bodies.items():
        row = ChatMessage(
            id=f"chat-t3251-{key}-{tag}", trainer_id=TRAINER_ID, member_id=DEMO_USER_ID,
            sender="member", body=body,
        )
        db_session.add(row)
        ids[key] = row.id
    db_session.commit()
    yield tag, ids
    db_session.rollback()
    db_session.execute(delete(ChatMessage).where(ChatMessage.id.in_(ids.values())))
    db_session.commit()


def _left(db_session, ids):
    db_session.expire_all()
    return set(db_session.scalars(
        select(ChatMessage.id).where(ChatMessage.id.in_(ids.values()))
    ))


@pytest.mark.parametrize("wildcard", ["t3251%{tag}", "t3251_평범한%{tag}"])
def test_wildcard_markers_do_not_match_other_messages(db_session, messages, wildcard):
    """와일드카드로 읽으면 테스트 메시지에 걸리는 마커다. 글자 그대로면 아무것도 없다.

    `%`·`_` 한 글자 마커는 쓰지 않는다 — 글자 그대로 든 다른 테스트의 채팅까지 지운다.
    """
    tag, ids = messages
    chats, _ = clean_e2e_chat.purge(db_session, wildcard.format(tag=tag))
    assert chats == 0
    assert _left(db_session, ids) == set(ids.values())


def test_marker_with_wildcard_characters_matches_itself_only(db_session, messages):
    tag, ids = messages
    chats, _ = clean_e2e_chat.purge(db_session, f"e2e%_{tag}")
    assert chats == 1
    assert _left(db_session, ids) == {ids["plain"]}
