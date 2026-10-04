"""회원별 트레이너 메모 — 계약·중복 방지·소유권 경계. (#706) DB 필요."""
from __future__ import annotations

from uuid import uuid4

import pytest


MEMBER_ID = "user-jisu"


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login",
        data={"username": email, "password": "oncare123"},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


@pytest.fixture()
def trainer_token(client) -> str:
    return _login(client, "trainer@oncare.com")


def _create_memo(client, token: str, **payload) -> dict:
    """메모 하나를 만들고 응답 본문을 돌려준다.

    상태 확인 없이 바로 `.json()` 을 쓰면 생성이 4xx 로 실패했을 때 뒤에서
    `KeyError` 가 나고 실패 이유가 로그에 남지 않는다.
    """
    response = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(token),
        json=payload,
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.fixture()
def cleanup_memos(client, db_session):
    """테스트가 만든 메모만 지운다 — 데모 시드 메모는 건드리지 않는다."""
    created: list[str] = []
    yield created
    from app.models.models import TrainerClientMemo

    for memo_id in created:
        memo = db_session.get(TrainerClientMemo, memo_id)
        if memo is not None:
            db_session.delete(memo)
    db_session.commit()


def test_memo_create_read_update_contract(client, trainer_token, cleanup_memos):
    """작성 → 조회 → 수정이 같은 메모를 가리킨다(다시 조회해도 유지)."""
    body = f"무릎 통증 경과 관찰 {uuid4().hex[:6]}"
    memo = _create_memo(client, trainer_token, body=body)
    cleanup_memos.append(memo["id"])
    assert memo["body"] == body
    assert memo["source"] == "trainer"
    assert memo["insight_id"] is None

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    )
    assert listed.status_code == 200, listed.text
    assert memo["id"] in [item["id"] for item in listed.json()]

    updated = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
        headers=_headers(trainer_token),
        json={"body": f"{body} (수정)"},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["body"] == f"{body} (수정)"
    # 출처는 수정 대상이 아니다.
    assert updated.json()["source"] == "trainer"

    # 재조회해도 수정본이 남는다 — 서버가 실제로 저장했다는 확인.
    reread = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    ).json()
    stored = next(item for item in reread if item["id"] == memo["id"])
    assert stored["body"] == f"{body} (수정)"


def test_memo_delete_removes_it_from_the_list(
    client, trainer_token, cleanup_memos
):
    created = _create_memo(
        client, trainer_token, body=f"삭제 대상 {uuid4().hex[:6]}"
    )
    # 삭제 단정이 먼저 실패해도 이 메모가 DB 에 남아 다른 테스트의 목록·정렬을
    # 흔들지 않도록 정리 대상에 올려 둔다.
    cleanup_memos.append(created["id"])

    deleted = client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
    )
    assert deleted.status_code == 200, deleted.text

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    ).json()
    assert created["id"] not in [item["id"] for item in listed]

    # 이미 지운 메모를 다시 지우면 404(없는 메모와 같다).
    again = client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
    )
    assert again.status_code == 404


def test_same_chat_insight_saved_twice_keeps_one_memo(
    client, trainer_token, cleanup_memos
):
    """채팅 인사이트는 insight_id 로 멱등하다 — 반복 저장해도 메모가 늘지 않는다."""
    insight_id = f"msg-{uuid4().hex[:8]}:discomfort"
    payload = {
        "body": "무릎이 아파요",
        "source": "chat_insight",
        "insight_id": insight_id,
        "insight_kind": "discomfort",
    }
    first = _create_memo(client, trainer_token, **payload)
    cleanup_memos.append(first["id"])

    second = _create_memo(client, trainer_token, **payload)
    assert second["id"] == first["id"]

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    ).json()
    same_insight = [item for item in listed if item["insight_id"] == insight_id]
    assert len(same_insight) == 1
    assert same_insight[0]["insight_kind"] == "discomfort"


def test_chat_insight_and_manual_memos_share_one_list(
    client, trainer_token, cleanup_memos
):
    """회원 상세 목록이 두 출처를 함께 보여 준다 — 같은 데이터 소스."""
    manual = _create_memo(
        client, trainer_token, body=f"직접 작성 {uuid4().hex[:6]}"
    )
    cleanup_memos.append(manual["id"])
    insight = _create_memo(
        client,
        trainer_token,
        body="어깨가 결려요",
        source="chat_insight",
        insight_id=f"msg-{uuid4().hex[:8]}:discomfort",
        insight_kind="discomfort",
    )
    cleanup_memos.append(insight["id"])

    listed = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
    ).json()
    ids = [item["id"] for item in listed]
    assert manual["id"] in ids
    assert insight["id"] in ids
    # 최신 먼저 — 나중에 저장한 인사이트 메모가 직접 작성 메모보다 앞에 온다.
    assert ids.index(insight["id"]) < ids.index(manual["id"])


def test_blank_memo_is_rejected(client, trainer_token, cleanup_memos):
    blank = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(trainer_token),
        json={"body": "   "},
    )
    assert blank.status_code == 400

    created = _create_memo(client, trainer_token, body="내용 있음")
    cleanup_memos.append(created["id"])
    empty_update = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
        json={},
    )
    assert empty_update.status_code == 400
    blank_update = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
        json={"body": " "},
    )
    assert blank_update.status_code == 400
    # 명시적 null 은 422(부분 수정 규약 #495).
    null_update = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/memos/{created['id']}",
        headers=_headers(trainer_token),
        json={"body": None},
    )
    assert null_update.status_code == 422


def test_mismatched_source_and_insight_id_are_rejected(client, trainer_token):
    """출처와 중복 방지 키가 어긋난 조합은 422 다.

    키 없는 인사이트 메모는 반복 저장 때마다 늘어나고, 직접 쓴 메모가
    `insight_id` 를 가지면 그 인사이트의 유니크 키를 대신 차지한다.
    """
    missing_key = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(trainer_token),
        json={"body": "무릎이 아파요", "source": "chat_insight"},
    )
    assert missing_key.status_code == 422

    stray_key = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(trainer_token),
        json={
            "body": "직접 작성",
            "source": "trainer",
            "insight_id": f"msg-{uuid4().hex[:8]}:discomfort",
        },
    )
    assert stray_key.status_code == 422

    unknown_source = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/memos",
        headers=_headers(trainer_token),
        json={"body": "출처 미상", "source": "legacy"},
    )
    assert unknown_source.status_code == 422


def test_unassigned_trainer_cannot_touch_member_memos(
    client, db_session, trainer_token
):
    """담당 관계가 없는 트레이너는 조회·수정·삭제 모두 404 다."""
    from app.core.security import create_access_token
    from app.models.models import User

    memo = _create_memo(
        client, trainer_token, body=f"남이 보면 안 되는 메모 {uuid4().hex[:6]}"
    )

    other_trainer_id = f"trainer-{uuid4().hex[:10]}"
    other_trainer = User(
        id=other_trainer_id,
        email=f"{other_trainer_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other_trainer)
    db_session.commit()
    other_headers = _headers(create_access_token(other_trainer_id))
    try:
        assert client.get(
            f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=other_headers
        ).status_code == 404
        assert client.post(
            f"/v1/trainer/clients/{MEMBER_ID}/memos",
            headers=other_headers,
            json={"body": "몰래 쓰기"},
        ).status_code == 404
        assert client.put(
            f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
            headers=other_headers,
            json={"body": "몰래 고치기"},
        ).status_code == 404
        assert client.delete(
            f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
            headers=other_headers,
        ).status_code == 404
    finally:
        db_session.delete(other_trainer)
        db_session.commit()
        client.delete(
            f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
            headers=_headers(trainer_token),
        )


def test_assigned_trainer_cannot_touch_another_members_memo(
    client, db_session, trainer_token
):
    """담당 회원이 여럿이어도 메모는 회원별로 갈린다 — 경로의 회원이 달라지면 404."""
    roster = client.get(
        "/v1/trainer/clients", headers=_headers(trainer_token)
    ).json()
    other_member = next(
        item["id"] for item in roster if item["id"] != MEMBER_ID
    )

    memo = _create_memo(
        client, trainer_token, body=f"회원 경계 확인 {uuid4().hex[:6]}"
    )
    try:
        crossed = client.put(
            f"/v1/trainer/clients/{other_member}/memos/{memo['id']}",
            headers=_headers(trainer_token),
            json={"body": "다른 회원 경로로 수정"},
        )
        assert crossed.status_code == 404
        assert memo["id"] not in [
            item["id"]
            for item in client.get(
                f"/v1/trainer/clients/{other_member}/memos",
                headers=_headers(trainer_token),
            ).json()
        ]
    finally:
        client.delete(
            f"/v1/trainer/clients/{MEMBER_ID}/memos/{memo['id']}",
            headers=_headers(trainer_token),
        )


def test_member_cannot_reach_trainer_memos(client):
    """회원 앱에서 트레이너 메모에 닿을 수 없다(범위 밖 기능)."""
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    denied = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(token)
    )
    assert denied.status_code == 403


# ---- 운동 기록 메모 (#2332) ----


def _exercise_rows(db_session):
    """트레이너 화면에 보이는 PT 이력·배정 수행과, 보이지 않는 남의 PT 이력을 만든다."""
    from app.models.models import ExerciseSession, RoutineHistory
    from app.services.exercise_service import WEEKDAY_LABELS, monday_of_this_week_str
    from app.services.trainer._common import PT_HISTORY_KIND_LABEL

    suffix = uuid4().hex[:8]
    mine = RoutineHistory(
        id=f"test-hist-{suffix}",
        member_id=MEMBER_ID,
        trainer_id="trainer-demo",
        date="2026-09-23",
        kind_label=PT_HISTORY_KIND_LABEL,
        completion_rate=100,
        exercises_json="[]",
    )
    theirs = RoutineHistory(
        id=f"test-hist-other-{suffix}",
        member_id=MEMBER_ID,
        trainer_id=None,
        date="2026-09-22",
        kind_label="AI 개인운동",
        completion_rate=100,
        exercises_json="[]",
    )
    assigned = ExerciseSession(
        id=f"test-assigned-{suffix}",
        user_id=MEMBER_ID,
        week_start=monday_of_this_week_str(),
        day_label=WEEKDAY_LABELS[0],
        type="strength",
        minutes=10,
        calories=50,
        intensity="moderate",
        source="assigned_routine",
        assigned_trainer_id="trainer-demo",
        assigned_routine_name="코어 강화",
    )
    rows = [mine, theirs, assigned]
    db_session.add_all(rows)
    db_session.commit()
    return rows


def test_exercise_memo_fills_its_source_from_the_record(
    client, db_session, trainer_token, cleanup_memos
):
    """기록 카드에서 남긴 메모는 서버가 그 기록에서 갈래·날짜·이름을 채운다."""
    pt, personal, assigned = _exercise_rows(db_session)
    try:
        pt_memo = _create_memo(
            client, trainer_token,
            body="스쿼트 무릎 안쪽 모임", source="exercise_memo", ref_id=pt.id,
        )
        cleanup_memos.append(pt_memo["id"])
        assert pt_memo["source"] == "exercise_memo"
        assert pt_memo["ref_kind"] == "pt_session"
        assert pt_memo["ref_id"] == pt.id
        assert pt_memo["ref_date"] == "2026-09-23"
        # 고정 이름은 앱이 번역하므로 저장하지 않는다.
        assert pt_memo["ref_name"] == ""

        personal_memo = _create_memo(
            client, trainer_token,
            body="AI 개인운동 강도 적당", source="exercise_memo", ref_id=personal.id,
        )
        cleanup_memos.append(personal_memo["id"])
        assert personal_memo["ref_kind"] == "personal"
        assert personal_memo["ref_name"] == ""

        assigned_memo = _create_memo(
            client, trainer_token,
            body="플랭크 자세 무너짐", source="exercise_memo", ref_id=assigned.id,
        )
        cleanup_memos.append(assigned_memo["id"])
        assert assigned_memo["ref_kind"] == "personal"
        assert assigned_memo["ref_name"] == "코어 강화"
        assert assigned_memo["ref_date"]

        # 날짜로 가리키면 그날 운동 기록 전체에 단 메모다(#2508).
        day_memo = _create_memo(
            client, trainer_token,
            body="혼자 걷기 꾸준함", source="exercise_memo", ref_date="2026-09-21",
        )
        cleanup_memos.append(day_memo["id"])
        assert day_memo["ref_kind"] == "day"
        assert day_memo["ref_id"] is None
        assert day_memo["ref_date"] == "2026-09-21"

        # 오늘 상자(개인운동·회원 추가)는 날짜와 함께 어느 상자인지 보낸다.
        for kind in ("personal", "member_log"):
            boxed = _create_memo(
                client, trainer_token,
                body="상자 메모", source="exercise_memo",
                ref_date="2026-09-21", ref_kind=kind,
            )
            cleanup_memos.append(boxed["id"])
            assert boxed["ref_kind"] == kind
            assert boxed["ref_id"] is None
            assert boxed["ref_date"] == "2026-09-21"

        # 직접 쓴 메모와 한 목록에 섞여 나온다.
        listed = client.get(
            f"/v1/trainer/clients/{MEMBER_ID}/memos", headers=_headers(trainer_token)
        ).json()
        ids = {item["id"] for item in listed}
        assert {pt_memo["id"], assigned_memo["id"], day_memo["id"]} <= ids
    finally:
        for row in (pt, personal, assigned):
            db_session.delete(row)
        db_session.commit()


def test_exercise_memo_rejects_records_the_trainer_cannot_see(
    client, db_session, trainer_token
):
    """남이 지도한 PT·없는 기록·오지 않은 날은 404 — 있는지 없는지를 가르지 않는다."""
    from app.models.models import RoutineHistory, User

    other_trainer_id = f"trainer-{uuid4().hex[:10]}"
    other = User(
        id=other_trainer_id,
        email=f"{other_trainer_id}@oncare.com",
        name="다른 트레이너",
        hashed_password="unused",
        role="trainer",
    )
    db_session.add(other)
    db_session.commit()
    foreign = RoutineHistory(
        id=f"test-hist-foreign-{uuid4().hex[:8]}",
        member_id=MEMBER_ID,
        trainer_id=other_trainer_id,
        date="2026-09-20",
        kind_label="PT 세션 · 트레이너 지도",
        completion_rate=100,
        exercises_json="[]",
    )
    db_session.add(foreign)
    db_session.commit()
    url = f"/v1/trainer/clients/{MEMBER_ID}/memos"
    try:
        for ref in (
            {"ref_id": foreign.id},
            {"ref_id": f"missing-{uuid4().hex[:8]}"},
            {"ref_date": "2999-01-01"},
        ):
            response = client.post(
                url,
                headers=_headers(trainer_token),
                json={"body": "안 돼야 한다", "source": "exercise_memo", **ref},
            )
            assert response.status_code == 404, (ref, response.text)
    finally:
        db_session.delete(foreign)
        db_session.delete(other)
        db_session.commit()


def test_exercise_memo_needs_exactly_one_record_link(client, trainer_token):
    """운동 기록 메모는 기록 하나를 가리켜야 하고, 다른 출처는 기록을 가리킬 수 없다."""
    url = f"/v1/trainer/clients/{MEMBER_ID}/memos"
    for payload in (
        {"source": "exercise_memo"},
        {"source": "exercise_memo", "ref_id": "x", "ref_date": "2026-09-21"},
        {"source": "trainer", "ref_id": "x"},
        {"source": "chat_insight", "insight_id": "i-1", "ref_date": "2026-09-21"},
        {"source": "exercise_memo", "ref_date": "2026-09-21", "insight_id": "i-2"},
        {"source": "exercise_memo", "ref_id": "x", "ref_kind": "personal"},
    ):
        response = client.post(
            url, headers=_headers(trainer_token), json={"body": "메모", **payload}
        )
        assert response.status_code == 422, (payload, response.text)


def test_memo_body_is_capped_at_500_chars(client, trainer_token, cleanup_memos):
    """메모는 기억해 둘 한두 줄이다 — 500자까지 받고 넘으면 422(#2516, #2618)."""
    url = f"/v1/trainer/clients/{MEMBER_ID}/memos"
    ok = _create_memo(client, trainer_token, body="가" * 500)
    cleanup_memos.append(ok["id"])
    too_long = client.post(
        url, headers=_headers(trainer_token), json={"body": "가" * 501}
    )
    assert too_long.status_code == 422, too_long.text
    edited = client.put(
        f"{url}/{ok['id']}", headers=_headers(trainer_token), json={"body": "나" * 501}
    )
    assert edited.status_code == 422, edited.text


def test_manual_memo_category_is_saved_and_editable(
    client, trainer_token, cleanup_memos
):
    """직접 쓴 메모는 분류를 골라 남기고, 수정에서 바꾸거나 지운다(#2622)."""
    url = f"/v1/trainer/clients/{MEMBER_ID}/memos"
    plain = _create_memo(client, trainer_token, body="분류 없음")
    cleanup_memos.append(plain["id"])
    # 고르지 않은 메모는 지금처럼 빈 분류다(태그 `직접 작성`).
    assert plain["category"] == ""

    memo = _create_memo(client, trainer_token, body="허리 디스크 이력", category="pain")
    cleanup_memos.append(memo["id"])
    assert memo["category"] == "pain"

    changed = client.put(
        f"{url}/{memo['id']}", headers=_headers(trainer_token), json={"category": "life"}
    )
    assert changed.status_code == 200, changed.text
    # 분류만 바꿔도 본문은 그대로다.
    assert changed.json()["category"] == "life"
    assert changed.json()["body"] == "허리 디스크 이력"

    cleared = client.put(
        f"{url}/{memo['id']}", headers=_headers(trainer_token), json={"category": ""}
    )
    assert cleared.status_code == 200, cleared.text
    assert cleared.json()["category"] == ""

    listed = client.get(url, headers=_headers(trainer_token)).json()
    assert next(m for m in listed if m["id"] == memo["id"])["category"] == ""


def test_memo_category_outside_the_list_is_rejected(
    client, trainer_token, cleanup_memos
):
    """허용 밖 분류는 작성·수정 모두 422 다(#2622)."""
    url = f"/v1/trainer/clients/{MEMBER_ID}/memos"
    bad = client.post(
        url, headers=_headers(trainer_token), json={"body": "x", "category": "sleep"}
    )
    assert bad.status_code == 422, bad.text
    memo = _create_memo(client, trainer_token, body="분류 수정 대상")
    cleanup_memos.append(memo["id"])
    bad_edit = client.put(
        f"{url}/{memo['id']}", headers=_headers(trainer_token), json={"category": "sleep"}
    )
    assert bad_edit.status_code == 422, bad_edit.text
    null_edit = client.put(
        f"{url}/{memo['id']}", headers=_headers(trainer_token), json={"category": None}
    )
    assert null_edit.status_code == 422, null_edit.text


def test_source_decides_the_category_of_other_memos(
    client, db_session, trainer_token, cleanup_memos
):
    """운동 기록 메모는 늘 운동, 채팅 감지 메모는 분류가 없다 — 바꿀 수도 없다(#2622)."""
    url = f"/v1/trainer/clients/{MEMBER_ID}/memos"
    exercise = _create_memo(
        client, trainer_token,
        body="걷기 꾸준함", source="exercise_memo", ref_date="2026-09-21",
    )
    cleanup_memos.append(exercise["id"])
    assert exercise["category"] == "exercise"

    # 메모 창에서 `운동` 을 고르고 기록을 이은 경우도 같은 메모가 된다.
    picked = _create_memo(
        client, trainer_token,
        body="걷기 속도 올리기", source="exercise_memo", ref_date="2026-09-21",
        category="exercise",
    )
    cleanup_memos.append(picked["id"])
    assert picked["category"] == "exercise"
    assert picked["ref_kind"] == "day"

    wrong = client.post(
        url, headers=_headers(trainer_token),
        json={"body": "x", "source": "exercise_memo", "ref_date": "2026-09-21",
              "category": "diet"},
    )
    assert wrong.status_code == 422, wrong.text

    insight_with_category = client.post(
        url, headers=_headers(trainer_token),
        json={"body": "x", "source": "chat_insight",
              "insight_id": f"cat-{uuid4().hex[:8]}", "category": "pain"},
    )
    assert insight_with_category.status_code == 422, insight_with_category.text

    locked = client.put(
        f"{url}/{exercise['id']}", headers=_headers(trainer_token),
        json={"category": "diet"},
    )
    assert locked.status_code == 400, locked.text
    # 지금 값을 그대로 싣고 와 본문만 고치는 것은 된다.
    same = client.put(
        f"{url}/{exercise['id']}", headers=_headers(trainer_token),
        json={"category": "exercise", "body": "걷기 꾸준함 (수정)"},
    )
    assert same.status_code == 200, same.text
    assert same.json()["category"] == "exercise"


def test_category_memo_still_hides_records_the_trainer_cannot_see(
    client, trainer_token
):
    """메모 창에서 기록을 이을 때도 기존 권한 규칙이다 — 보이지 않는 기록은 404(#2622).

    남의 PT 이력 404 는 위 `test_exercise_memo_rejects_records_the_trainer_cannot_see`
    가 본다. 여기서는 분류를 함께 보내도 같은 길을 타는지만 본다.
    """
    for ref in ({"ref_id": f"missing-{uuid4().hex[:8]}"}, {"ref_date": "2999-01-01"}):
        response = client.post(
            f"/v1/trainer/clients/{MEMBER_ID}/memos",
            headers=_headers(trainer_token),
            json={"body": "x", "source": "exercise_memo", "category": "exercise", **ref},
        )
        assert response.status_code == 404, (ref, response.text)
