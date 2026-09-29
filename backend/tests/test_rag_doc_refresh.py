"""기록을 고치면 코치가 보는 근거도 함께 바뀐다 (#603).

적재가 생성 시에만 일어나던 동안, 기록을 수정해도 옛 수치 문서가 남았다. 그렇다고
수정 때마다 덧붙이면 더 나쁘다 — 옛 값과 새 값이 **동시에** 검색되어, 코치가 어느
쪽을 근거로 들지 알 수 없다.
"""
from __future__ import annotations

import pytest
from sqlalchemy import func, select

from app.models.models import CoachDocument
from app.services.coach import rag
from tests.exercise_helpers import post_exercise


def _member_token(client) -> str:
    r = client.post(
        "/v1/auth/login",
        data={"username": "minsu@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _docs_for(db_session, ref: str) -> list[CoachDocument]:
    return list(
        db_session.scalars(
            select(CoachDocument).where(CoachDocument.source_ref == ref)
        ).all()
    )


# ---- purge (순수 경로) ----

def test_purge_removes_every_chunk_of_one_record(client, db_session):
    """청킹 때문에 기록 하나가 문서 여러 개일 수 있다 — 단건 삭제로는 부족하다."""
    long_text = "회원 상태 메모. " * 400
    rag.ingest_personal_text(
        db_session, "user-7d4e9a2c5f18", long_text,
        domain="general", source="test", source_ref="ref-purge-1",
    )
    assert len(_docs_for(db_session, "ref-purge-1")) >= 1

    removed = rag.purge_personal(db_session, "user-7d4e9a2c5f18", "ref-purge-1")

    assert removed >= 1
    assert _docs_for(db_session, "ref-purge-1") == []


def test_purge_is_scoped_to_the_owner(client, db_session):
    """참조 id 가 겹치더라도 남의 문서를 지울 수 있는 경로를 열어 두지 않는다."""
    rag.ingest_personal_text(
        db_session, "user-7d4e9a2c5f18", "내 기록", domain="general", source="test",
        source_ref="ref-shared",
    )

    removed = rag.purge_personal(db_session, "someone-else", "ref-shared")

    assert removed == 0
    assert len(_docs_for(db_session, "ref-shared")) == 1
    rag.purge_personal(db_session, "user-7d4e9a2c5f18", "ref-shared")


# ---- 운동: 생성 → 수정 → 삭제 ----

def test_editing_a_session_replaces_the_evidence(client, db_session):
    token = _member_token(client)
    created = post_exercise(
        client,
        headers=_headers(token),
        json={"type": "walking", "minutes": 25, "calories": 90, "intensity": "light"},
    )
    assert created.status_code == 201, created.text
    session_id = created.json()["id"]
    assert any("25분" in d.content for d in _docs_for(db_session, session_id))

    updated = client.put(
        f"/v1/exercise/sessions/{session_id}",
        headers=_headers(token),
        json={"type": "walking", "minutes": 45, "calories": 160, "intensity": "moderate"},
    )

    assert updated.status_code == 200, updated.text
    db_session.expire_all()
    docs = _docs_for(db_session, session_id)
    # 새 값이 있고, 옛 값이 남아 있지 않다.
    assert any("45분" in d.content for d in docs)
    assert all("25분" not in d.content for d in docs)


def test_deleting_a_session_forgets_its_evidence(client, db_session):
    """지운 기록으로 코치가 계속 조언하면 지운 것이 되살아나는 셈이다."""
    token = _member_token(client)
    created = post_exercise(
        client,
        headers=_headers(token),
        json={"type": "yoga", "minutes": 20, "calories": 60, "intensity": "light"},
    )
    session_id = created.json()["id"]
    assert _docs_for(db_session, session_id)

    gone = client.delete(
        f"/v1/exercise/sessions/{session_id}", headers=_headers(token)
    )

    assert gone.status_code == 200, gone.text
    db_session.expire_all()
    assert _docs_for(db_session, session_id) == []


def test_repeated_edits_do_not_pile_up_documents(client, db_session):
    token = _member_token(client)
    created = post_exercise(
        client,
        headers=_headers(token),
        json={"type": "cardio", "minutes": 10, "calories": 50, "intensity": "light"},
    )
    session_id = created.json()["id"]

    for minutes in (20, 30, 40):
        client.put(
            f"/v1/exercise/sessions/{session_id}",
            headers=_headers(token),
            json={
                "type": "cardio", "minutes": minutes, "calories": 50,
                "intensity": "light",
            },
        )

    db_session.expire_all()
    docs = _docs_for(db_session, session_id)
    assert len(docs) == 1
    assert "40분" in docs[0].content


# ---- 식단: 수정 → 삭제 ----

def _log_meal(db_session, user_id: str = "user-7d4e9a2c5f18") -> str:
    """식단은 사진 분석(`POST /diet/analyze`)으로만 생기므로 서비스로 직접 만든다.

    검증 대상은 수정·삭제 경로이지 업로드가 아니다. 여기서 이미지를 태우면 인식기
    스텁까지 끌고 들어와 테스트가 무엇을 재는지 흐려진다.
    """
    from app.schemas.diet import DietAnalysis, RecognizedFood
    from app.services import diet_service

    entry, _ = diet_service.save_analyzed_entry(
        db_session,
        user_id,
        "lunch",
        DietAnalysis(
            engine="test",
            foods=[
                RecognizedFood(
                    name="김치찌개", calories=600, sodium_mg=1800, sugar_g=5.0
                )
            ],
            total_calories=600,
            total_sodium_mg=1800,
            total_sugar_g=5.0,
        ),
        None,
    )
    return entry.id


def test_editing_a_meal_replaces_the_evidence(client, db_session):
    token = _member_token(client)
    entry_id = _log_meal(db_session)
    assert any("1800mg" in d.content for d in _docs_for(db_session, entry_id))

    r = client.put(
        f"/v1/diet/entries/{entry_id}",
        headers=_headers(token),
        json={"sodium_mg": 900},
    )

    assert r.status_code == 200, r.text
    db_session.expire_all()
    docs = _docs_for(db_session, entry_id)
    assert any("900mg" in d.content for d in docs)
    # 나트륨을 정정했는데 코치가 옛 수치로 조언하면 정정한 의미가 없다.
    assert all("1800mg" not in d.content for d in docs)


def test_deleting_a_meal_forgets_its_evidence(client, db_session):
    token = _member_token(client)
    entry_id = _log_meal(db_session)
    assert _docs_for(db_session, entry_id)

    r = client.delete(f"/v1/diet/entries/{entry_id}", headers=_headers(token))

    assert r.status_code == 200, r.text
    db_session.expire_all()
    assert _docs_for(db_session, entry_id) == []


# ---- 교체의 원자성 (CodeRabbit PR#607 리뷰) ----

def test_a_failed_embedding_leaves_the_old_documents_intact(
    client, db_session, monkeypatch
):
    """임베딩이 실패해도 기존 근거가 사라지면 안 된다.

    예전엔 purge 를 먼저 커밋하고 ingest 를 따로 커밋해서, 그 사이에 임베딩이
    실패하면 기존 청크를 되살릴 방법이 없었다.
    """
    user_id = "user-7d4e9a2c5f18"
    ref = "atomicity-probe-1"
    rag.replace_personal_text(
        db_session, user_id, domain="exercise", source="exercise", source_ref=ref,
        load_text=lambda: "2026-08-11 운동 기록: 걷기 30분.",
    )
    before = [d.content for d in _docs_for(db_session, ref)]
    assert before, "먼저 적재돼 있어야 이 테스트가 의미를 갖는다"

    class _BrokenEmbedder:
        def embed(self, chunks):
            raise RuntimeError("embedder down")

    monkeypatch.setattr(rag, "get_embedder", lambda *a, **k: _BrokenEmbedder())

    try:
        rag.replace_personal_text(
            db_session, user_id, domain="exercise", source="exercise",
            source_ref=ref,
            load_text=lambda: "2026-08-11 운동 기록: 걷기 45분.",
        )
    except RuntimeError:
        pass
    db_session.rollback()
    db_session.expire_all()

    assert [d.content for d in _docs_for(db_session, ref)] == before


def test_replacing_never_exposes_a_moment_with_no_evidence(client, db_session):
    """삭제와 삽입이 한 트랜잭션이어야 한다 — 따로 커밋하면 근거가 빈 순간이 생긴다."""
    user_id = "user-7d4e9a2c5f18"
    ref = "atomicity-probe-2"
    rag.replace_personal_text(
        db_session, user_id, domain="exercise", source="exercise", source_ref=ref,
        load_text=lambda: "2026-08-11 운동 기록: 걷기 30분.",
    )

    # 커밋 직전에 세션이 들고 있는 새 문서 수를 기록한다. 세션은 autoflush=False 라
    # SELECT 로는 대기 중인 삽입이 안 보이므로 `session.new` 를 직접 본다.
    pending_at_commit: list[int] = []
    original = db_session.commit

    def _counting_commit():
        pending_at_commit.append(
            sum(isinstance(obj, CoachDocument) for obj in db_session.new)
        )
        original()

    db_session.commit = _counting_commit  # type: ignore[method-assign]
    try:
        rag.replace_personal_text(
            db_session, user_id, domain="exercise", source="exercise",
            source_ref=ref,
            load_text=lambda: "2026-08-11 운동 기록: 걷기 45분.",
        )
    finally:
        db_session.commit = original  # type: ignore[method-assign]

    # 커밋은 한 번뿐이고, 그 한 번에 삭제와 새 문서가 함께 실린다.
    assert len(pending_at_commit) == 1
    assert pending_at_commit[0] > 0
    db_session.expire_all()
    assert "45분" in _docs_for(db_session, ref)[0].content


def test_emptying_a_record_clears_its_evidence(client, db_session):
    """기록이 비워진 것도 반영해야 할 변화다 — 옛 문서가 남으면 안 된다."""
    user_id = "user-7d4e9a2c5f18"
    ref = "atomicity-probe-3"
    rag.replace_personal_text(
        db_session, user_id, domain="exercise", source="exercise", source_ref=ref,
        load_text=lambda: "2026-08-11 운동 기록: 걷기 30분.",
    )
    assert _docs_for(db_session, ref)

    rag.replace_personal_text(
        db_session, user_id, domain="exercise", source="exercise",
        source_ref=ref, load_text=lambda: "   ",
    )
    db_session.expire_all()

    assert _docs_for(db_session, ref) == []


# ---- 회귀 방어 ----

def test_public_documents_keep_a_null_reference(client, db_session):
    """공공 문서는 원본 기록이 없다 — 참조가 붙으면 개인 정리 로직에 걸린다."""
    count = db_session.scalar(
        select(func.count())
        .select_from(CoachDocument)
        .where(
            CoachDocument.user_id.is_(None),
            CoachDocument.source_ref.isnot(None),
        )
    )
    assert count == 0


# ---- 최신성 보장 (#614) ----

def test_a_late_arriving_refresh_still_writes_the_current_row(client, db_session):
    """늦게 도착한 갱신이 옛 값을 되살리면 안 된다.

    두 수정이 이렇게 엇갈릴 수 있다:
        A: 30분 커밋 → B: 45분 커밋 → B 적재(45) → **A 적재**
    A 가 자기가 읽은 30분을 쓰면 DB 는 45분인데 근거는 30분이 된다. 갱신이 잠금
    안에서 행을 다시 읽으므로, 늦게 도착한 A 도 45분을 써야 한다.
    """
    from app.models.models import ExerciseSession
    from app.services.coach import personal_ingest

    token = _member_token(client)
    created = post_exercise(
        client,
        headers=_headers(token),
        json={"type": "walking", "minutes": 30, "calories": 100, "intensity": "light"},
    )
    assert created.status_code == 201, created.text
    session_id = created.json()["id"]

    row = db_session.scalar(
        select(ExerciseSession).where(ExerciseSession.id == session_id)
    )
    user_id = row.user_id

    # DB 를 45분으로 바꾼다 — "B 가 이미 커밋한" 상태.
    row.minutes = 45
    db_session.commit()

    # 이제 "A 의 늦은 적재" 가 도착한다. 30분을 넘겨 줄 방법이 없다 — 갱신은
    # id 만 받고 행을 다시 읽는다.
    personal_ingest.refresh_exercise(db_session, user_id, session_id=session_id)
    db_session.expire_all()

    contents = [d.content for d in _docs_for(db_session, session_id)]
    assert contents, "갱신 후 근거가 있어야 한다"
    assert all("45분" in c for c in contents)
    assert not any("30분" in c for c in contents)


def test_refreshing_a_deleted_record_clears_its_evidence(client, db_session):
    """원본이 사라졌으면 근거도 사라져야 한다 — 지운 기록이 되살아나면 안 된다."""
    from app.models.models import ExerciseSession
    from app.services.coach import personal_ingest

    token = _member_token(client)
    created = post_exercise(
        client,
        headers=_headers(token),
        json={"type": "yoga", "minutes": 20, "calories": 60, "intensity": "moderate"},
    )
    session_id = created.json()["id"]
    row = db_session.scalar(
        select(ExerciseSession).where(ExerciseSession.id == session_id)
    )
    user_id = row.user_id
    assert _docs_for(db_session, session_id)

    db_session.delete(row)
    db_session.commit()

    personal_ingest.refresh_exercise(db_session, user_id, session_id=session_id)
    db_session.expire_all()

    assert _docs_for(db_session, session_id) == []


# ---- 깨진 foods_json (CodeRabbit PR#616 리뷰) ----

def test_a_malformed_food_list_still_refreshes_the_evidence(client, db_session):
    """항목이 dict 이 아니어도 갱신은 끝나야 한다.

    예전엔 diet_text 가 `f.get(...)` 에서 터지고 _safe_replace 가 그 예외를 삼켜,
    수정했는데도 **옛 수치 문서가 그대로 남았다**. 조용히 실패하는 경로라 화면에서
    알아챌 방법이 없다.
    """
    from app.models.models import DietEntry
    from app.services.coach import personal_ingest

    entry_id = _log_meal(db_session)
    assert any("1800mg" in d.content for d in _docs_for(db_session, entry_id))

    row = db_session.scalar(select(DietEntry).where(DietEntry.id == entry_id))
    # 항목이 문자열·숫자인 목록. 저장된 JSON 이 늘 dict 목록이라는 보장은 없다.
    row.foods_json = '["김치찌개", 42, null]'
    row.sodium_mg = 900
    db_session.commit()

    personal_ingest.refresh_diet(db_session, row.user_id, entry_id=entry_id)
    db_session.expire_all()

    docs = _docs_for(db_session, entry_id)
    assert docs, "갱신이 삼켜지면 옛 문서만 남는다"
    assert any("900mg" in d.content for d in docs)
    assert all("1800mg" not in d.content for d in docs)


@pytest.mark.parametrize(
    "raw",
    ['["문자열만"]', "[1, 2, 3]", '{"not": "a list"}', "{{{ 깨진 json", "", "null"],
)
def test_broken_food_json_never_raises(raw):
    """파싱 경계에서 걸러 내므로 어떤 값이 와도 본문 생성이 죽지 않는다."""
    from app.services.coach import personal_ingest

    foods = personal_ingest._entry_foods(raw)

    assert isinstance(foods, list)
    assert all(isinstance(f, dict) for f in foods)
    # 본문 생성까지 통과해야 갱신이 끝난다.
    assert personal_ingest.diet_text(
        date="2026-08-11", foods=foods, total_calories=1, sodium_mg=1, sugar_g=1.0
    )


# ---- 완료 순서 역전 (CodeRabbit PR#619 리뷰) ----

def test_the_older_refresh_finishing_last_still_leaves_the_latest_value(
    client, db_session
):
    """먼저 시작한 갱신이 **마지막에 끝나도** 최종 근거는 DB 최신값이어야 한다.

    앞선 테스트는 "잠금 안에서 다시 읽는다"는 메커니즘만 본다. 진짜 위험한 순서는
    이것이다:

        A 호출(행=30) → B 호출(행=45) → B 적재(45) → **A 적재**

    A 가 호출 시점의 30 을 들고 있으면 마지막 쓰기가 30 이 되어, DB 는 45 인데
    코치는 30 을 근거로 답한다. 그래서 A 를 **잠금에 들어가기 직전에** 세워 둔다 —
    값을 들고 다니던 설계와 다시 읽는 설계가 갈리는 지점이 정확히 거기다.
    """
    import threading

    from app.db.session import SessionLocal
    from app.models.models import ExerciseSession
    from app.services.coach import personal_ingest

    token = _member_token(client)
    created = post_exercise(
        client,
        headers=_headers(token),
        json={"type": "walking", "minutes": 30, "calories": 100, "intensity": "light"},
    )
    assert created.status_code == 201, created.text
    session_id = created.json()["id"]
    user_id = db_session.scalar(
        select(ExerciseSession.user_id).where(ExerciseSession.id == session_id)
    )

    original_replace = personal_ingest.replace_personal_text
    at_the_gate = threading.Event()  # A 가 잠금 직전까지 왔다
    let_a_go = threading.Event()     # B 가 끝난 뒤 A 를 들여보낸다
    first_call = threading.Lock()
    seen = {"first": False}

    def _gated_replace(*args, **kwargs):
        with first_call:
            is_a = not seen["first"]
            seen["first"] = True
        if is_a:
            # A 만 세운다. 이 지점은 잠금·재조회 **이전**이라, 값을 미리 읽어 두는
            # 설계였다면 A 는 이미 30 을 손에 쥔 상태다.
            at_the_gate.set()
            assert let_a_go.wait(timeout=30), "A 를 들여보내지 못했다"
        return original_replace(*args, **kwargs)

    personal_ingest.replace_personal_text = _gated_replace  # type: ignore[assignment]
    errors: list[BaseException] = []

    def _refresh_in_own_session() -> None:
        db = SessionLocal()
        try:
            personal_ingest.refresh_exercise(db, user_id, session_id=session_id)
        except BaseException as exc:  # noqa: BLE001 - 스레드 예외를 본체로 옮긴다
            errors.append(exc)
        finally:
            db.close()

    try:
        a = threading.Thread(target=_refresh_in_own_session, daemon=True)
        a.start()
        assert at_the_gate.wait(timeout=30), "A 가 잠금 직전까지 오지 못했다"

        # A 가 멈춰 있는 사이 행이 45 로 바뀐다.
        writer = SessionLocal()
        try:
            row = writer.scalar(
                select(ExerciseSession).where(ExerciseSession.id == session_id)
            )
            row.minutes = 45
            writer.commit()
        finally:
            writer.close()

        # B 를 **끝까지** 돌린다. 여기서 문서는 45 가 된다.
        b = threading.Thread(target=_refresh_in_own_session, daemon=True)
        b.start()
        b.join(timeout=60)
        assert not b.is_alive(), "B 가 끝나지 않았다"

        # 이제 A 가 마지막으로 쓴다.
        let_a_go.set()
        a.join(timeout=60)
        assert not a.is_alive(), "A 가 끝나지 않았다"
    finally:
        personal_ingest.replace_personal_text = original_replace  # type: ignore[assignment]
        let_a_go.set()

    assert not errors, f"갱신 중 예외: {errors!r}"

    db_session.expire_all()
    contents = [d.content for d in _docs_for(db_session, session_id)]
    assert contents, "겹쳐 돌린 뒤 근거가 사라지면 안 된다"
    assert all("45분" in c for c in contents), contents
    assert not any("30분" in c for c in contents), contents
