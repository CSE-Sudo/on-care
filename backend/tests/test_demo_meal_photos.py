"""데모 끼니 사진 시드(#3307).

목업은 앱 번들의 데모 사진을 그리고, 실서버는 `diet_photos` 의 사진을 내준다. 시드가
사진을 넣지 않으면 실서버의 김민수 식단은 회원 앱·트레이너 웹 모두 대체 이모지로만
보인다. DB 가 필요한 테스트는 CI 의 Postgres 에서 돈다(client 픽스처가 시드를 먼저 돌림).
"""
from __future__ import annotations

from pathlib import Path

from app.core import clock
from app.db.demo_fixture import load_fixture
from app.db.seed_member_data import DEMO_PHOTO_DIR

_MEMBER_ID = "user-7d4e9a2c5f18"
_PASSWORD = "oncare123"
_SEED_PREFIX = "seed-fix-diet-"

#: 목업이 그리는 원본(회원 앱 번들). 백엔드는 같은 파일을 한 벌 더 갖고 있다.
APP_PHOTO_DIR = (
    Path(__file__).resolve().parents[2] / "frontend/flutter/assets/demo/images"
)


def _fixture_assets() -> set[str]:
    fixture = load_fixture()
    return {
        Path(meal.photo_asset).name
        for day in fixture.days_for(clock.today())
        for meal in day.meals
        if meal.photo_asset
    }


def _login(client, email: str) -> dict:
    res = client.post(
        "/v1/auth/login", data={"username": email, "password": _PASSWORD}
    )
    assert res.status_code == 200, res.text
    return {"Authorization": f"Bearer {res.json()['access_token']}"}


def test_every_fixture_photo_has_a_backend_copy():
    missing = [name for name in _fixture_assets() if not (DEMO_PHOTO_DIR / name).is_file()]
    assert not missing, f"backend/app/db/demo_photos 에 없는 사진: {missing}"


def test_backend_copies_match_the_app_bundle():
    # 손으로 고치지 말 것 — 앱 번들(assets/demo/images)에서 그대로 복사한다.
    for name in _fixture_assets():
        assert (DEMO_PHOTO_DIR / name).read_bytes() == (APP_PHOTO_DIR / name).read_bytes(), name


def _seeded_day(db_session) -> str:
    """시드 끼니가 남아 있는 날 하나(가장 최근).

    다른 테스트가 같은 회원의 오늘 끼니를 지우거나 더한다 — 시드를 다시 깔고, DB 에
    실제로 남은 시드 끼니의 날짜로 본다.
    """
    from sqlalchemy import select

    from app.db.seed_member_data import seed_member_health_data
    from app.models.models import DietEntry

    seed_member_health_data()
    db_session.expire_all()
    day = db_session.scalar(
        select(DietEntry.date)
        .where(
            DietEntry.user_id == _MEMBER_ID,
            DietEntry.id.like(f"{_SEED_PREFIX}%"),
        )
        .order_by(DietEntry.date.desc())
        .limit(1)
    )
    assert day, "시드 끼니가 없습니다."
    return day


def test_member_sees_the_demo_photos(client, db_session):
    date = _seeded_day(db_session)
    headers = _login(client, "minsu@oncare.com")
    day = client.get(f"/v1/diet/days/{date}", headers=headers)
    assert day.status_code == 200, day.text
    # 다른 테스트가 같은 회원에게 사진 없는 끼니를 더할 수 있다 — 시드 끼니만 본다.
    entries = [e for e in day.json()["entries"] if e["id"].startswith(_SEED_PREFIX)]
    assert entries, f"{date} 시드 끼니가 없습니다."
    assert all(e["photo_url"] for e in entries), entries

    image = client.get(f"/v1{entries[0]['photo_url']}", headers=headers)
    assert image.status_code == 200
    assert image.headers["content-type"] == "image/jpeg"
    assert image.content[:2] == b"\xff\xd8"


def test_trainer_sees_the_same_demo_photos(client, db_session):
    date = _seeded_day(db_session)
    headers = _login(client, "trainer@oncare.com")
    res = client.get(
        f"/v1/trainer/clients/{_MEMBER_ID}/diet",
        params={"date": date},
        headers=headers,
    )
    assert res.status_code == 200, res.text
    entries = [e for e in res.json() if e["id"].startswith(_SEED_PREFIX)]
    assert entries, f"트레이너가 보는 {date} 시드 끼니가 없습니다."
    assert all(e["photo_url"] for e in entries), entries

    image = client.get(f"/v1{entries[0]['photo_url']}", headers=headers)
    assert image.status_code == 200
    assert image.headers["content-type"] == "image/jpeg"


def test_reseeding_does_not_duplicate_photos(client, db_session):
    from sqlalchemy import func, select

    from app.db.seed_member_data import seed_member_health_data
    from app.models.models import DietPhoto

    def count() -> int:
        return db_session.scalar(
            select(func.count())
            .select_from(DietPhoto)
            .where(DietPhoto.user_id == _MEMBER_ID, DietPhoto.id.like("seedpic-%"))
        )

    # 다른 테스트가 시드 행을 지웠을 수 있어 첫 재시드는 그것을 채운다. 그 뒤로는
    # 다시 돌려도 사진이 늘지 않아야 한다.
    seed_member_health_data()
    db_session.expire_all()
    before = count()
    assert before > 0
    seed_member_health_data()
    db_session.expire_all()
    assert count() == before
