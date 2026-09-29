"""트레이너별 프로그램 템플릿 CRUD. (#920)

가장 중요하게 보는 것은 **시작 구성이 저장된 행이 아니라는 점**이다. 저장된
템플릿이 없는 트레이너에게만 보이고, 자기 것이 하나라도 생기면 사라진다 —
그래야 "지웠는데 되살아난다" 가 생기지 않는다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

import json
from uuid import uuid4

import pytest

from app.core.security import hash_password
from app.models.models import TrainerProfile, TrainerProgramTemplate, User
from app.services import trainer_program_template_service as service

EMAIL_PREFIX = "template-test-"
PASSWORD = "template-pw-1234"


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        db_session.query(TrainerProgramTemplate).filter(
            TrainerProgramTemplate.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _trainer(client, db_session) -> tuple[User, str]:
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"template-trainer-{suffix}",
        email=email,
        name="템플릿 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.commit()
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return trainer, response.json()["access_token"]


def _create(client, token: str, name: str = "내 블록") -> dict:
    response = client.post(
        "/v1/trainer/program-templates",
        json={
            "name": name,
            "goal": "체중 감량 · 초급",
            "exercises": [
                {"name": "인터벌 유산소", "minutes": 20, "type": "유산소"},
                {"name": "코어 서킷", "minutes": 10, "type": "근력"},
            ],
        },
        headers=_auth(token),
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_a_new_trainer_starts_with_the_bundled_set(client, db_session):
    _, token = _trainer(client, db_session)

    response = client.get("/v1/trainer/program-templates", headers=_auth(token))

    assert response.status_code == 200, response.text
    rows = response.json()
    assert [row["name"] for row in rows] == [
        "혈압 관리 기본",
        "체중 감량 순환",
        "하체 근력 A",
    ]
    # 시작 구성은 저장된 행이 아니다 — id 로 그것을 알 수 있어야 화면이
    # 지우기·고치기를 내밀지 않는다.
    assert all(row["id"].startswith(service.STARTER_PREFIX) for row in rows)
    assert (
        db_session.query(TrainerProgramTemplate)
        .filter(TrainerProgramTemplate.trainer_id.isnot(None))
        .filter(TrainerProgramTemplate.id.like("starter%"))
        .count()
        == 0
    )


def test_saving_one_template_replaces_the_starter_set(client, db_session):
    _, token = _trainer(client, db_session)

    _create(client, token)

    rows = client.get(
        "/v1/trainer/program-templates", headers=_auth(token)
    ).json()
    assert [row["name"] for row in rows] == ["내 블록"]


def test_a_saved_template_keeps_its_exercises_in_order(client, db_session):
    _, token = _trainer(client, db_session)

    created = _create(client, token)

    assert [item["name"] for item in created["exercises"]] == [
        "인터벌 유산소",
        "코어 서킷",
    ]
    assert created["exercises"][0]["type"] == "유산소"


def test_a_strength_template_keeps_sets_reps_and_weight(client, db_session):
    """근력 블록은 세트·횟수·중량을 그대로 되돌려준다. (#1310)

    중량은 예전에 계약에 자리가 없어 앱이 보낸 값이 조용히 버려졌다.
    """
    _, token = _trainer(client, db_session)

    response = client.post(
        "/v1/trainer/program-templates",
        json={
            "name": "하체 근력 A",
            "exercises": [
                {
                    "name": "스쿼트",
                    "minutes": 30,
                    "type": "근력",
                    "sets": 4,
                    "reps": 12,
                    "weight": 62.5,
                }
            ],
        },
        headers=_auth(token),
    )

    assert response.status_code == 201, response.text
    item = response.json()["exercises"][0]
    assert (item["sets"], item["reps"], item["weight"]) == (4, 12, 62.5)


def test_a_template_saved_with_legacy_text_reads_as_numbers(client, db_session):
    """`"10회"`·`"20kg"` 로 저장된 옛 블록도 열린다 — 숫자만 되짚는다. (#1310)"""
    trainer, token = _trainer(client, db_session)
    db_session.add(
        TrainerProgramTemplate(
            id=f"tpl-{uuid4().hex[:8]}",
            trainer_id=trainer.id,
            name="옛 블록",
            goal="",
            exercises_json=json.dumps(
                [
                    {
                        "name": "데드리프트",
                        "minutes": 30,
                        "type": "근력",
                        "sets": 3,
                        "reps": "10회",
                        "weight": "20kg",
                    }
                ],
                ensure_ascii=False,
            ),
        )
    )
    db_session.commit()

    response = client.get("/v1/trainer/program-templates", headers=_auth(token))

    assert response.status_code == 200, response.text
    item = response.json()[0]["exercises"][0]
    assert (item["sets"], item["reps"], item["weight"]) == (3, 10, 20.0)


def test_a_template_keeps_exercise_seconds(client, db_session):
    """편집기에서 시·분·초로 적은 운동이 템플릿에서도 초로 남는다. (#2521)"""
    _, token = _trainer(client, db_session)

    response = client.post(
        "/v1/trainer/program-templates",
        json={
            "name": "초 블록",
            "exercises": [
                {"name": "버피", "type": "유산소", "duration_seconds": 45},
                {"name": "걷기", "type": "유산소", "duration_seconds": 5415},
            ],
        },
        headers=_auth(token),
    )
    assert response.status_code == 201, response.text

    listed = client.get("/v1/trainer/program-templates", headers=_auth(token))
    items = listed.json()[0]["exercises"]
    assert [(i["duration_seconds"], i["minutes"]) for i in items] == [
        (45, 1),
        (5415, 90),
    ]


def test_a_minutes_only_template_reads_as_seconds(client, db_session):
    """초 칸이 생기기 전에 저장된 템플릿은 분 × 60 으로 읽힌다. (#2521)"""
    trainer, token = _trainer(client, db_session)
    db_session.add(
        TrainerProgramTemplate(
            id=f"tpl-{uuid4().hex[:8]}",
            trainer_id=trainer.id,
            name="옛 블록",
            goal="",
            exercises_json='[{"name": "걷기", "minutes": 20, "type": "유산소"}]',
        )
    )
    db_session.commit()

    response = client.get("/v1/trainer/program-templates", headers=_auth(token))

    assert response.status_code == 200, response.text
    item = response.json()[0]["exercises"][0]
    assert (item["duration_seconds"], item["minutes"]) == (1200, 20)


def test_editing_replaces_the_exercise_list_wholesale(client, db_session):
    _, token = _trainer(client, db_session)
    created = _create(client, token)

    response = client.put(
        f"/v1/trainer/program-templates/{created['id']}",
        json={
            "name": "고친 블록",
            "exercises": [{"name": "걷기", "minutes": 30, "type": "걷기"}],
        },
        headers=_auth(token),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["name"] == "고친 블록"
    assert [item["name"] for item in body["exercises"]] == ["걷기"]
    # 보내지 않은 필드는 그대로다.
    assert body["goal"] == "체중 감량 · 초급"


def test_deleting_the_last_template_brings_the_starter_set_back(client, db_session):
    """지우면 '아무것도 저장하지 않은 트레이너' 로 돌아간다.

    시작 구성이 되살아나는 것이 아니라, 애초에 저장된 적 없는 값이라 다시
    보이는 것이다. 빈 화면으로 두면 이 기능이 무엇인지 알 수 없다.
    """
    _, token = _trainer(client, db_session)
    created = _create(client, token)

    deleted = client.delete(
        f"/v1/trainer/program-templates/{created['id']}", headers=_auth(token)
    )

    assert deleted.status_code == 200, deleted.text
    rows = client.get(
        "/v1/trainer/program-templates", headers=_auth(token)
    ).json()
    assert all(row["id"].startswith(service.STARTER_PREFIX) for row in rows)


def test_templates_are_private_to_their_trainer(client, db_session):
    _, owner_token = _trainer(client, db_session)
    _, stranger_token = _trainer(client, db_session)
    created = _create(client, owner_token, name="남의 블록")

    # 남의 목록에는 보이지 않고,
    rows = client.get(
        "/v1/trainer/program-templates", headers=_auth(stranger_token)
    ).json()
    assert all(row["name"] != "남의 블록" for row in rows)

    # 직접 집어도 존재조차 드러내지 않는다.
    edited = client.put(
        f"/v1/trainer/program-templates/{created['id']}",
        json={"name": "가로채기"},
        headers=_auth(stranger_token),
    )
    assert edited.status_code == 404
    removed = client.delete(
        f"/v1/trainer/program-templates/{created['id']}",
        headers=_auth(stranger_token),
    )
    assert removed.status_code == 404


def test_a_starter_id_cannot_be_edited(client, db_session):
    """시작 구성은 저장된 행이 아니라 고칠 대상이 없다.

    화면은 '고치기' 대신 '내 템플릿으로 저장' 을 내밀지만, 그 규약을 서버가
    한 번 더 지킨다.
    """
    _, token = _trainer(client, db_session)

    response = client.put(
        f"/v1/trainer/program-templates/{service.STARTER_PREFIX}0",
        json={"name": "고쳐보기"},
        headers=_auth(token),
    )

    assert response.status_code == 404


def test_a_template_needs_at_least_one_exercise(client, db_session):
    _, token = _trainer(client, db_session)

    response = client.post(
        "/v1/trainer/program-templates",
        json={"name": "빈 블록", "goal": "", "exercises": []},
        headers=_auth(token),
    )

    assert response.status_code == 422


def test_an_unknown_exercise_type_is_refused(client, db_session):
    _, token = _trainer(client, db_session)

    response = client.post(
        "/v1/trainer/program-templates",
        json={
            "name": "이상한 블록",
            "exercises": [{"name": "무언가", "minutes": 10, "type": "필라테스"}],
        },
        headers=_auth(token),
    )

    assert response.status_code == 422


def test_the_save_limit_is_enforced(client, db_session):
    trainer, token = _trainer(client, db_session)
    for index in range(service.TEMPLATE_LIMIT):
        db_session.add(
            TrainerProgramTemplate(
                id=f"tpl-limit-{index}-{uuid4().hex[:6]}",
                trainer_id=trainer.id,
                name=f"블록 {index}",
                goal="",
                exercises_json='[{"name": "걷기", "minutes": 10, "type": "걷기"}]',
            )
        )
    db_session.commit()

    response = client.post(
        "/v1/trainer/program-templates",
        json={
            "name": "하나 더",
            "exercises": [{"name": "걷기", "minutes": 10, "type": "걷기"}],
        },
        headers=_auth(token),
    )

    assert response.status_code == 409
