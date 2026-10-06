"""트레이너가 AI 후보 가운데 골라 회원에게 추천하는 식단. (#2378)

보는 것:

1. 담당 회원만 — 남의 회원·해제된 담당·동의 철회는 같은 404.
2. 후보는 회원의 4주 추천 메뉴 리스트에서 급한 태그를 채우는 메뉴부터다. 조회는
   AI 를 새로 부르지 않고, 트레이너 언어로 회원 리스트를 다시 만들지 않는다.
3. 확정하면 회원 홈 추천 응답의 `trainer_pick` 이 된다. 바꾸기는 같은 행을 덮는다.
4. 회원이 그 메뉴를 기록하면 즉시 해소돼 홈에서 내려간다.
5. 담당을 해제하면 추천도 내려간다.
"""
from __future__ import annotations

import json
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select, text

from app.core import clock
from app.core.security import create_access_token
from app.data import diet_menu_catalog as catalog
from app.models.models import (
    DietEntry,
    DietMenuPlan,
    DietTrainerPick,
    HealthProfile,
    TrainerClient,
    User,
)
from app.services import diet_menu_plan

GUARD_DETAIL = "담당 회원을 찾을 수 없어요."
#: 끼니마다 돌려 쓰는 태그. 나트륨·단백질 메뉴가 끼니마다 섞인다.
_TAGS = (
    catalog.TAG_FIBER_HIGH,
    catalog.TAG_PROTEIN_HIGH,
    catalog.TAG_SODIUM_LOW,
    catalog.TAG_CALORIE_LOW,
    catalog.TAG_SUGAR_LOW,
)


def _h(user_id: str, lang: str = "ko") -> dict[str, str]:
    return {
        "Authorization": f"Bearer {create_access_token(user_id)}",
        "Accept-Language": lang,
    }


def _payload() -> str:
    items = []
    for slot, n in catalog.SLOT_COUNTS.items():
        for i in range(n):
            tag = _TAGS[i % len(_TAGS)]
            items.append({
                "slot": slot, "name": f"{slot} {tag} {i}", "tag": tag,
                "keyword": "키워드", "kcal": 400, "protein_g": 30, "sodium_mg": 500,
            })
    return json.dumps({"items": items}, ensure_ascii=False)


class _FakeLLM:
    def __init__(self) -> None:
        self.calls = 0

    def __call__(self, system: str, user: str) -> str:
        self.calls += 1
        return _payload()


@dataclass
class Pair:
    trainer_id: str
    member_id: str
    link_id: str

    @property
    def base(self) -> str:
        return f"/v1/trainer/clients/{self.member_id}/diet-recommendations"


def _make_pair(db_session) -> Pair:
    suffix = uuid4().hex[:10]
    pair = Pair(f"pick-trainer-{suffix}", f"pick-member-{suffix}", f"tc-{suffix}")
    db_session.add_all([
        User(id=pair.trainer_id, email=f"{pair.trainer_id}@oncare.com",
             name="추천 트레이너", hashed_password="unused", role="trainer"),
        User(id=pair.member_id, email=f"{pair.member_id}@oncare.com",
             name="추천 회원", hashed_password="unused", role="member"),
    ])
    db_session.flush()
    db_session.add(HealthProfile(user_id=pair.member_id, daily_protein_g=90))
    db_session.add(TrainerClient(
        id=pair.link_id, trainer_id=pair.trainer_id, member_id=pair.member_id, active=True,
    ))
    db_session.commit()
    return pair


def _cleanup(db_session, pair: Pair) -> None:
    db_session.rollback()
    ids = [pair.trainer_id, pair.member_id]
    for table in ("diet_trainer_picks", "diet_menu_plans", "diet_entries"):
        column = "member_id" if table == "diet_trainer_picks" else "user_id"
        db_session.execute(text(f"DELETE FROM {table} WHERE {column} = ANY(:ids)"), {"ids": ids})
    db_session.execute(text("DELETE FROM health_profiles WHERE user_id = ANY(:ids)"), {"ids": ids})
    db_session.execute(text("DELETE FROM trainer_clients WHERE id = :id"), {"id": pair.link_id})
    db_session.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": ids})
    db_session.commit()


@pytest.fixture()
def pair(db_session) -> Iterator[Pair]:
    created = _make_pair(db_session)
    try:
        yield created
    finally:
        _cleanup(db_session, created)


@pytest.fixture()
def llm(monkeypatch) -> _FakeLLM:
    fake = _FakeLLM()
    monkeypatch.setattr(diet_menu_plan, "_call_llm", fake)
    return fake


def _log(db_session, member_id: str, day, food: str, *, protein=20, sodium=1900) -> None:
    db_session.add(DietEntry(
        id=f"diet-{uuid4().hex[:12]}", user_id=member_id, date=day.isoformat(),
        meal_type="lunch",
        foods_json=json.dumps([{"name": food, "calories": 600}], ensure_ascii=False),
        total_calories=600, protein_g=protein, sodium_mg=sodium, sugar_g=5,
    ))
    db_session.commit()


def _salty_low_protein_week(db_session, member_id: str) -> None:
    """최근 7일 — 나트륨이 목표 근처, 단백질은 목표(90g)에 한참 모자란다."""
    today = clock.today()
    for i in range(1, 8):
        _log(db_session, member_id, today - timedelta(days=i), "김치찌개")


def _confirm(client, pair: Pair, menu: dict):
    return client.put(
        pair.base, headers=_h(pair.trainer_id),
        json={"slot": menu["slot"], "name": menu["name"]},
    )


def _member_pick(client, pair: Pair):
    r = client.get("/v1/diet/recommendations?use_llm=false", headers=_h(pair.member_id))
    assert r.status_code == 200, r.text
    return r.json()["trainer_pick"]


# ── 권한 ─────────────────────────────────────────────────────────────────


def test_other_trainers_member_is_not_found(client, db_session, pair, llm):
    other = _make_pair(db_session)
    try:
        r = client.get(pair.base, headers=_h(other.trainer_id))
        assert r.status_code == 404 and r.json()["detail"] == GUARD_DETAIL
        r = client.put(pair.base, headers=_h(other.trainer_id), json={"slot": "lunch", "name": "x"})
        assert r.status_code == 404 and r.json()["detail"] == GUARD_DETAIL
    finally:
        _cleanup(db_session, other)


def test_detached_or_revoked_member_is_not_found(client, db_session, pair, llm):
    link = db_session.get(TrainerClient, pair.link_id)
    link.data_consent_revoked_at = clock.now()
    link.data_consent_at = None
    db_session.commit()
    r = client.get(pair.base, headers=_h(pair.trainer_id))
    assert r.status_code == 404 and r.json()["detail"] == GUARD_DETAIL

    link.data_consent_revoked_at = None
    link.active = False
    db_session.commit()
    r = client.get(pair.base, headers=_h(pair.trainer_id))
    assert r.status_code == 404 and r.json()["detail"] == GUARD_DETAIL


# ── 후보 ─────────────────────────────────────────────────────────────────


def test_no_need_means_no_candidates(client, db_session, pair, llm):
    r = client.get(pair.base, headers=_h(pair.trainer_id))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["needs"] == [] and body["candidates"] == [] and body["pick"] is None
    # 채울 점이 없으면 리스트도 열지 않는다 — AI 를 부를 까닭이 없다.
    assert llm.calls == 0


def test_candidates_put_urgent_tags_first(client, db_session, pair, llm):
    _salty_low_protein_week(db_session, pair.member_id)
    body = client.get(pair.base, headers=_h(pair.trainer_id)).json()

    assert body["needs"][:2] == [catalog.TAG_SODIUM_LOW, catalog.TAG_PROTEIN_HIGH]
    assert body["basis_days"] == 7
    cands = body["candidates"]
    assert len(cands) == sum(catalog.SLOT_COUNTS.values())
    urgent = [c for c in cands if c["urgent"]]
    # 급한 태그의 메뉴가 먼저, 그 안에서는 급한 순서 → 끼니 순서.
    assert cands[: len(urgent)] == urgent
    assert [c["tag"] for c in urgent[:2]] == [catalog.TAG_SODIUM_LOW] * 2
    assert urgent[0]["slot"] == catalog.SLOT_BREAKFAST
    assert all(c["tag"] in body["needs"] for c in urgent)


def test_reading_candidates_does_not_call_ai_or_flip_member_language(
    client, db_session, pair, llm
):
    _salty_low_protein_week(db_session, pair.member_id)
    diet_menu_plan.get_plan(db_session, pair.member_id, lang="ko")
    assert llm.calls == 1

    r = client.get(pair.base, headers=_h(pair.trainer_id, lang="en"))
    assert r.status_code == 200, r.text
    assert llm.calls == 1  # 저장된 리스트를 읽기만 한다
    db_session.expire_all()
    rows = db_session.scalars(
        select(DietMenuPlan).where(DietMenuPlan.user_id == pair.member_id)
    ).all()
    assert [row.lang for row in rows] == ["ko"]


# ── 확정 ─────────────────────────────────────────────────────────────────


def test_confirm_shows_on_member_home_and_leaves_candidates(client, db_session, pair, llm):
    _salty_low_protein_week(db_session, pair.member_id)
    first = client.get(pair.base, headers=_h(pair.trainer_id)).json()["candidates"][0]

    r = _confirm(client, pair, first)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["pick"]["name"] == first["name"]
    assert body["pick"]["status"] == "active"
    assert first["name"] not in [c["name"] for c in body["candidates"]]

    home = _member_pick(client, pair)
    assert home == {
        "slot": first["slot"], "name": first["name"], "tag": first["tag"],
        "keyword": first["keyword"], "trainer_name": "추천 트레이너",
    }


def test_confirm_again_replaces_the_pick(client, db_session, pair, llm):
    _salty_low_protein_week(db_session, pair.member_id)
    cands = client.get(pair.base, headers=_h(pair.trainer_id)).json()["candidates"]
    _confirm(client, pair, cands[0])
    r = _confirm(client, pair, cands[1])
    assert r.json()["pick"]["name"] == cands[1]["name"]
    db_session.expire_all()
    rows = db_session.scalars(
        select(DietTrainerPick).where(DietTrainerPick.member_id == pair.member_id)
    ).all()
    assert len(rows) == 1
    assert _member_pick(client, pair)["name"] == cands[1]["name"]


def test_menu_outside_the_list_is_rejected(client, db_session, pair, llm):
    _salty_low_protein_week(db_session, pair.member_id)
    client.get(pair.base, headers=_h(pair.trainer_id))
    r = client.put(pair.base, headers=_h(pair.trainer_id),
                   json={"slot": "dinner", "name": "지어낸 메뉴"})
    assert r.status_code == 422
    assert _member_pick(client, pair) is None


# ── 해소·해제 ─────────────────────────────────────────────────────────────


def test_eating_the_menu_resolves_the_pick(client, db_session, pair, llm):
    _salty_low_protein_week(db_session, pair.member_id)
    first = client.get(pair.base, headers=_h(pair.trainer_id)).json()["candidates"][0]
    _confirm(client, pair, first)

    # 다른 음식은 해소가 아니다.
    _log(db_session, pair.member_id, clock.today(), "김치찌개")
    assert _member_pick(client, pair) is not None

    # 띄어쓰기가 달라도, 앞뒤에 말이 붙어도 그 메뉴다.
    eaten = first["name"].replace(" ", "") + " 도시락"
    _log(db_session, pair.member_id, clock.today(), eaten)
    assert _member_pick(client, pair) is None
    pick = client.get(pair.base, headers=_h(pair.trainer_id)).json()["pick"]
    assert pick["status"] == "resolved" and pick["resolved_at"]


def test_food_logged_before_confirming_does_not_resolve(client, db_session, pair, llm):
    _salty_low_protein_week(db_session, pair.member_id)
    first = client.get(pair.base, headers=_h(pair.trainer_id)).json()["candidates"][0]
    _log(db_session, pair.member_id, clock.today(), first["name"])
    _confirm(client, pair, first)
    assert _member_pick(client, pair) is not None


def test_detaching_removes_the_pick(client, db_session, pair, llm):
    _salty_low_protein_week(db_session, pair.member_id)
    first = client.get(pair.base, headers=_h(pair.trainer_id)).json()["candidates"][0]
    _confirm(client, pair, first)

    r = client.delete(f"/v1/trainer/clients/{pair.member_id}", headers=_h(pair.trainer_id))
    assert r.status_code == 204, r.text
    assert _member_pick(client, pair) is None
    db_session.expire_all()
    assert db_session.scalar(
        select(DietTrainerPick).where(DietTrainerPick.member_id == pair.member_id)
    ) is None


def test_revoked_consent_hides_the_pick_from_home(client, db_session, pair, llm):
    _salty_low_protein_week(db_session, pair.member_id)
    first = client.get(pair.base, headers=_h(pair.trainer_id)).json()["candidates"][0]
    _confirm(client, pair, first)

    db_session.expire_all()
    link = db_session.get(TrainerClient, pair.link_id)
    link.data_consent_revoked_at = clock.now()
    link.data_consent_at = None
    db_session.commit()
    assert _member_pick(client, pair) is None


# ── 회원 쪽 해제 ──────────────────────────────────────────────────────────


def _relink(db_session, pair: Pair) -> None:
    """같은 트레이너와 다시 연결됐다 — 새 동의로 링크가 살아난다."""
    db_session.expire_all()
    link = db_session.get(TrainerClient, pair.link_id)
    link.active = True
    link.data_consent_at = clock.now()
    db_session.commit()


@pytest.mark.parametrize("path", ["/v1/me/coach/trainer", "/v1/me/coach"])
def test_member_releasing_the_trainer_drops_the_pick(client, db_session, pair, llm, path):
    """회원이 트레이너만(`/me/coach/trainer`) 또는 헬스장째(`/me/coach`) 끊어도 추천을
    지운다 — 트레이너가 해제할 때(`remove_client`)와 같다. 남겨 두면 같은 트레이너와
    다시 연결될 때 끊기 전의 추천이 회원 홈에 되살아난다."""
    _salty_low_protein_week(db_session, pair.member_id)
    first = client.get(pair.base, headers=_h(pair.trainer_id)).json()["candidates"][0]
    _confirm(client, pair, first)
    assert _member_pick(client, pair) is not None

    r = client.delete(path, headers=_h(pair.member_id))
    assert r.status_code == 204, r.text
    db_session.expire_all()
    assert db_session.scalar(
        select(DietTrainerPick).where(DietTrainerPick.member_id == pair.member_id)
    ) is None

    _relink(db_session, pair)
    assert _member_pick(client, pair) is None
    assert client.get(pair.base, headers=_h(pair.trainer_id)).json()["pick"] is None
