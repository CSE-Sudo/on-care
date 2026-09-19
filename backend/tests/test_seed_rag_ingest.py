"""시드 기록의 개인 RAG 적재 (#604).

적재는 원래 실시간 API 경로에서만 일어났다. 시드는 테이블에 직접 insert 하므로
데모 계정에는 개인 문서가 없었고, 회원 앱 AI 코치가 시드 식단·운동·대화를 근거로
쓰지 못했다 — 기록이 있는데도 일반론이 나왔다.
"""
from __future__ import annotations

import pytest
from sqlalchemy import delete, select

from app.db import seed_member_data
from app.db.session import SessionLocal
from app.models.models import (
    ChatMessage,
    CoachDocument,
    DietEntry,
    ExerciseSession,
    User,
)
from app.services.coach.rag import has_personal_doc


def _seed_member_ids(db) -> list[str]:
    """시드 식단이 붙어 있는 회원들 — 적재 대상이 실제로 있는 계정."""
    rows = db.scalars(
        select(DietEntry.user_id).where(DietEntry.id.like("seed-%")).distinct()
    ).all()
    return sorted(rows)


def test_seeded_records_become_personal_documents(client, db_session):
    """기동 시드가 이미 돌았으므로 문서가 붙어 있어야 한다."""
    members = _seed_member_ids(db_session)
    assert members, "시드된 식단이 있어야 이 테스트가 의미를 갖는다"

    entry = db_session.scalar(
        select(DietEntry)
        .where(DietEntry.user_id == members[0], DietEntry.id.like("seed-%"))
        .limit(1)
    )

    assert has_personal_doc(db_session, members[0], entry.id)


@pytest.mark.parametrize(
    ("model", "domain"),
    [(DietEntry, "diet"), (ExerciseSession, "exercise")],
)
def test_each_seeded_kind_lands_in_its_own_domain(client, db_session, model, domain):
    """운동이 diet 도메인에 들어가면 식단 코치가 엉뚱한 근거를 검색한다."""
    owner_col = model.user_id
    row = db_session.scalar(
        select(model).where(model.id.like("seed-%")).limit(1)
    )
    if row is None:
        pytest.skip(f"{model.__name__} 시드가 없다")

    doc = db_session.scalar(
        select(CoachDocument)
        .where(
            CoachDocument.source_ref == row.id,
            CoachDocument.user_id == getattr(row, owner_col.key),
        )
        .limit(1)
    )

    assert doc is not None
    assert doc.domain == domain


def test_seeded_chat_is_owned_by_the_member(client, db_session):
    """트레이너가 보낸 말도 회원 소유 문서다 — 회원 코치가 user_id 로만 검색한다."""
    msg = db_session.scalar(
        select(ChatMessage)
        .where(ChatMessage.id.like("seed-%"), ChatMessage.sender == "trainer")
        .limit(1)
    )
    if msg is None:
        pytest.skip("트레이너 발신 시드 대화가 없다")

    doc = db_session.scalar(
        select(CoachDocument).where(CoachDocument.source_ref == msg.id).limit(1)
    )

    assert doc is not None
    assert doc.user_id == msg.member_id
    assert "트레이너:" in doc.content


def _doc_count(db, user_id: str) -> int:
    return len(
        db.scalars(
            select(CoachDocument.id).where(CoachDocument.user_id == user_id)
        ).all()
    )


def test_re_running_the_seed_does_not_duplicate_documents(client, db_session):
    """기동할 때마다 다시 임베딩하면 같은 내용이 여러 벌 검색 상위를 차지한다."""
    member_id = _seed_member_ids(db_session)[0]
    before = _doc_count(db_session, member_id)
    assert before > 0, "첫 기동에서 이미 적재돼 있어야 한다"

    seed_member_data.ingest_seeded_documents()
    db_session.expire_all()

    assert _doc_count(db_session, member_id) == before


def test_the_sweep_covers_the_extended_roster(client, db_session):
    """확장 회원(4~15)의 기록은 `seed_roster_metrics` 가 만든다 (#572).

    적재를 `seed_member_health_data` 안에서 부르면 그 시점에 아직 없어서 첫 기동에
    통째로 빠지고, 재기동해야 채워졌다. 실제로 그렇게 나왔다.
    """
    members = _seed_member_ids(db_session)
    assert len(members) > 3, "확장 로스터가 시드돼 있어야 이 테스트가 의미를 갖는다"

    without_docs = [m for m in members if _doc_count(db_session, m) == 0]

    assert without_docs == []


def test_the_member_coach_can_now_retrieve_a_seeded_record(client, db_session):
    """이 이슈의 목적 — 데모에서 "이번 주 운동 어땠어?" 에 기록이 잡혀야 한다."""
    from app.services.coach.rag import retrieve

    session = db_session.scalar(
        select(ExerciseSession).where(ExerciseSession.id.like("seed-%")).limit(1)
    )
    if session is None:
        pytest.skip("운동 시드가 없다")

    hits = retrieve(
        db_session, "이번 주 운동 얼마나 했나요",
        user_id=session.user_id, domain="exercise",
    )

    assert hits["personal"], "적재 전에는 개인 근거가 0건이었다"


def test_only_seeded_rows_are_swept(client, db_session, monkeypatch):
    """사용자가 앱에서 남긴 기록은 실시간 경로가 이미 적재했다.

    #603 이전에 적재된 문서는 `source_ref` 가 NULL 이라 멱등 판정에 걸리지 않으므로,
    전체를 훑으면 그런 기록이 두 벌씩 검색된다.

    적재 판정을 항상 False 로 만들어 sweep 이 실제로 무엇을 훑는지 본다 — 그러지
    않으면 기동 시드가 이미 전부 적재해 둔 탓에 잡히는 게 하나도 없고, 빈 목록에
    대한 all(...) 이 True 라 필터를 검증하지 못한다(CodeRabbit PR#612 리뷰).
    """
    member_id = _seed_member_ids(db_session)[0]

    # 시드가 아닌 회원 기록을 하나 심는다 — 필터가 이걸 건너뛰어야 한다.
    from app.models.models import ExerciseSession

    db_session.add(
        ExerciseSession(
            id="user-made-not-seed-1", user_id=member_id,
            week_start="2026-08-10", day_label="월", type="cardio",
            minutes=30, calories=200, intensity="moderate",
        )
    )
    db_session.commit()

    captured: list[str | None] = []
    monkeypatch.setattr(seed_member_data, "has_personal_doc", lambda *a, **k: False)
    for name in ("record_diet", "record_exercise", "record_chat"):
        monkeypatch.setattr(
            seed_member_data.personal_ingest, name,
            lambda db, uid, **kw: captured.append(kw.get("source_ref")),
        )

    seed_member_data._ingest_member_documents(db_session, member_id)

    assert captured, "적재 판정을 껐으므로 시드 기록이 잡혀야 한다"
    assert all(ref and ref.startswith("seed-") for ref in captured)
    assert "user-made-not-seed-1" not in captured


def test_the_sweep_is_skippable(client, db_session, monkeypatch):
    """실 임베딩 키로 처음 띄우면 기동이 그만큼 길어진다 — 끌 수 있어야 한다."""
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "seed_rag_ingest", False)
    called: list[str] = []
    monkeypatch.setattr(
        seed_member_data,
        "_ingest_member_documents",
        lambda db, member_id: called.append(member_id) or 0,
    )

    seed_member_data._ingest_seeded_documents(db_session, {"user-7d4e9a2c5f18"})

    assert called == []


# ---- 적재의 원자성 (CodeRabbit PR#612 리뷰) ----

def test_ensure_checks_and_inserts_inside_one_lock(client, db_session):
    """확인과 삽입이 갈라지면 동시 기동이 같은 기록을 두 벌 넣는다.

    확인을 밖에서 하고 삽입을 따로 부르면, 두 인스턴스가 모두 "없다"를 보고 각자
    넣는다. 유니크 제약으로는 못 막는다 — 청킹 때문에 한 기록이 여러 행이라
    (user_id, source_ref) 는 원래 중복이다.
    """
    from app.services.coach.rag import ensure_personal_text

    user_id = "user-7d4e9a2c5f18"
    ref = "ensure-probe-1"

    first = ensure_personal_text(
        db_session, user_id, "2026-08-11 운동 기록: 걷기 30분.",
        domain="exercise", source="exercise", source_ref=ref,
    )
    second = ensure_personal_text(
        db_session, user_id, "2026-08-11 운동 기록: 걷기 30분.",
        domain="exercise", source="exercise", source_ref=ref,
    )

    assert first > 0, "처음에는 적재돼야 한다"
    assert second == 0, "두 번째 호출은 아무것도 넣지 않는다"
    assert _doc_count_for_ref(db_session, ref) == first


def test_ensure_does_not_embed_when_the_record_is_already_indexed(
    client, db_session, monkeypatch
):
    """이미 있으면 임베딩을 부르지 않는다 — 기동마다 전량 재임베딩하면 의미가 없다."""
    from app.services.coach import rag

    user_id = "user-7d4e9a2c5f18"
    ref = "ensure-probe-2"
    rag.ensure_personal_text(
        db_session, user_id, "2026-08-11 운동 기록: 걷기 30분.",
        domain="exercise", source="exercise", source_ref=ref,
    )

    def _boom(*_a, **_k):
        raise AssertionError("이미 적재된 기록에 임베딩을 불렀다")

    monkeypatch.setattr(rag, "get_embedder", _boom)

    assert rag.ensure_personal_text(
        db_session, user_id, "2026-08-11 운동 기록: 걷기 30분.",
        domain="exercise", source="exercise", source_ref=ref,
    ) == 0


def _doc_count_for_ref(db, ref: str) -> int:
    return len(
        db.scalars(
            select(CoachDocument.id).where(CoachDocument.source_ref == ref)
        ).all()
    )


def test_ingest_survives_rows_deleted_by_another_session(client, db_session, monkeypatch):
    """적재 도중 다른 세션이 시드 행을 지워도 기동이 죽지 않는다. (#1919)

    적재는 한 건마다 커밋한다. 커밋은 세션에 실린 ORM 객체를 만료시키므로, 미리
    읽어 둔 행을 들고 반복하면 다음 속성 접근이 행을 다시 가져온다 — 그 사이
    **다른 세션이** 지운 행이면 `ObjectDeletedError` 가 나고, 적재가 아니라
    `init_db` 가 죽는다.

    다른 세션이어야 한다는 것이 요점이다. 같은 세션이 지우면 그 객체는 식별
    맵에서 밀려나 조용히 옛 값을 쓰지만, 남의 삭제는 이 세션이 모르는 채 남아
    있다가 만료 뒤 되읽을 때 터진다.

    **전용 회원을 만들어 쓴다.** `db_session` 은 테스트마다 롤백하지 않아서,
    진짜 시드 회원의 행을 지우면 뒤따르는 테스트가 시드가 사라진 DB 를 보게
    된다.
    """
    member_id = "user-1919-probe"
    db_session.add(User(id=member_id, email=f"{member_id}@example.com", name="적재 프로브"))
    # 기록이 이 회원을 참조하므로 먼저 내보낸다 — `DietEntry.user_id` 는 관계가
    # 아니라 그냥 FK 칼럼이라 SQLAlchemy 가 순서를 정해 주지 않는다.
    db_session.flush()
    for n in range(3):
        db_session.add(
            DietEntry(
                id=f"seed-diet-{member_id}-{n}",
                user_id=member_id,
                date="2026-09-01",
                meal_type="lunch",
                foods_json='[{"name": "밥", "calories": 300}]',
                total_calories=300,
            )
        )
    db_session.commit()

    seen: list[str | None] = []

    def _delete_elsewhere_then_commit(db, uid, **kw):
        seen.append(kw.get("source_ref"))
        if len(seen) == 1:
            other = SessionLocal()
            try:
                other.execute(
                    delete(DietEntry).where(DietEntry.user_id == member_id)
                )
                other.commit()
            finally:
                other.close()
        # 실제 적재 경로가 하는 일 — 이 커밋이 남은 객체를 만료시킨다.
        db.commit()

    monkeypatch.setattr(seed_member_data, "has_personal_doc", lambda *a, **k: False)
    for name in ("record_diet", "record_exercise", "record_chat"):
        monkeypatch.setattr(
            seed_member_data.personal_ingest, name, _delete_elsewhere_then_commit
        )

    try:
        # 고치기 전에는 두 번째 행을 읽는 자리에서 ObjectDeletedError 가 났다.
        seed_member_data._ingest_member_documents(db_session, member_id)
        assert len(seen) == 3, "행이 사라져도 이미 뽑아 둔 값으로 셋 다 적재해야 한다"
    finally:
        # 회원을 지우면 남은 기록도 CASCADE 로 함께 사라진다.
        db_session.execute(delete(User).where(User.id == member_id))
        db_session.commit()
