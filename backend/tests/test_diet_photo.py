"""끼니 사진 저장·조회 (#699). DB 필요(로컬 skip, CI 실행).

회원이 올린 사진이 저장되고, 회원과 **담당 트레이너만** 같은 사진을 본다.
남의 사진은 주소를 알아도 열리지 않고, 끼니나 계정이 사라지면 사진도 사라진다.
"""
from __future__ import annotations

import io
from uuid import uuid4

import pytest
from sqlalchemy import delete, select

_TRAINER_EMAIL = "trainer@oncare.com"
_PASSWORD = "oncare123"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    res = client.post(
        "/v1/auth/login", data={"username": email, "password": _PASSWORD}
    )
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


def _photo_bytes(size: tuple[int, int] = (2400, 1600), fmt: str = "JPEG") -> bytes:
    """진짜 이미지 바이트. 다른 식단 테스트가 쓰는 가짜 JPEG 은 디코딩되지 않아
    사진 경로를 지나가지 못한다."""
    from PIL import Image

    image = Image.new("RGB", size, (120, 180, 90))
    buffer = io.BytesIO()
    image.save(buffer, format=fmt)
    return buffer.getvalue()


@pytest.fixture()
def member(client, db_session):
    """이 스위트 전용 회원 + 담당 링크.

    시드 회원(user-jisu)에 끼니를 붙이면 그 회원의 하루 합계를 고정값으로
    단언하는 트레이너 테스트가 흔들린다. 사진 테스트는 자기 회원을 만들어 쓴다.
    """
    from app.core.security import hash_password
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import TrainerClient, User

    suffix = uuid4().hex[:8]
    member_id = f"user-photo-{suffix}"
    email = f"photo-{suffix}@oncare.test"
    db_session.add(
        User(
            id=member_id,
            email=email,
            name="사진 회원",
            role="member",
            hashed_password=hash_password(_PASSWORD),
        )
    )
    db_session.flush()
    db_session.add(
        TrainerClient(
            id=f"link-photo-{suffix}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            goal="",
            sort_order=900,
        )
    )
    db_session.commit()
    try:
        yield member_id, email
    finally:
        db_session.execute(
            delete(TrainerClient).where(TrainerClient.member_id == member_id)
        )
        db_session.execute(delete(User).where(User.id == member_id))
        db_session.commit()


@pytest.fixture()
def member_token(client, member) -> str:
    return _login(client, member[1])


def _analyze(client, token: str, image: bytes, meal_type: str = "lunch"):
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", image, "image/jpeg")},
        data={"meal_type": meal_type},
        headers=_auth(token),
    )


# ---- 축소·재인코딩 (DB 없이) ----


def test_downscale_shrinks_the_long_edge_and_reencodes_as_jpeg():
    from app.services.diet_photo_service import _downscale_to_jpeg

    data, width, height = _downscale_to_jpeg(_photo_bytes((2400, 1600)))

    assert max(width, height) == 1024
    assert (width, height) == (1024, 683)  # 3:2 비율 유지
    assert data[:2] == b"\xff\xd8"  # JPEG SOI
    # 휴대폰 사진 한 장이 카드 한 장 크기로 떨어져야 공유 DB 에 둘 수 있다.
    assert len(data) < 400_000


def test_downscale_leaves_a_small_photo_alone():
    from app.services.diet_photo_service import _downscale_to_jpeg

    _, width, height = _downscale_to_jpeg(_photo_bytes((640, 480)))

    assert (width, height) == (640, 480)


def test_downscale_drops_exif_so_a_photo_does_not_carry_its_location():
    """끼니 사진을 트레이너와 공유하는 것이 촬영 위치를 공유하는 뜻이면 안 된다."""
    from PIL import Image

    from app.services.diet_photo_service import _downscale_to_jpeg

    source = Image.new("RGB", (800, 600), (10, 20, 30))
    exif = Image.Exif()
    exif[0x8825] = {1: "N", 2: (37.0, 30.0, 0.0)}  # GPSInfo
    buffer = io.BytesIO()
    source.save(buffer, format="JPEG", exif=exif)

    data, _, _ = _downscale_to_jpeg(buffer.getvalue())

    with Image.open(io.BytesIO(data)) as stored:
        assert not dict(stored.getexif())


def test_unreadable_bytes_do_not_raise():
    from app.services.diet_photo_service import _downscale_to_jpeg

    assert _downscale_to_jpeg(b"not an image at all") is None


# ---- 저장·조회 ----


def test_analyze_stores_the_photo_and_the_member_can_read_it(client, member_token):
    from app.models.models import DietPhoto

    res = _analyze(client, member_token, _photo_bytes())
    assert res.status_code == 200, res.text
    body = res.json()
    photo_url = body["photo_url"]
    assert photo_url and photo_url.startswith("/diet/photos/")

    image = client.get(f"/v1{photo_url}", headers=_auth(member_token))
    assert image.status_code == 200
    assert image.headers["content-type"] == "image/jpeg"
    assert image.content[:2] == b"\xff\xd8"
    # 사적인 이미지는 공유 캐시에 남으면 안 된다.
    assert "private" in image.headers["cache-control"]

    photo_id = photo_url.rsplit("/", 1)[-1]
    from app.db.session import SessionLocal

    with SessionLocal() as db:
        stored = db.scalar(select(DietPhoto).where(DietPhoto.id == photo_id))
        assert stored is not None
        assert stored.entry_id == body["entry_id"]
        assert stored.byte_size == len(image.content)


def test_the_day_view_carries_the_photo_of_the_meal_that_has_one(client, member_token):
    # 사진이 붙지 않은 끼니도 한 건 만든다 — 사진 저장(#699) 이전 기록·직접 기록이
    # 그렇다. 읽을 수 없는 사진은 이제 분석 전에 415 라(#3041) 직접 기록으로 만든다.
    without = client.post(
        "/v1/diet/entries",
        json={"meal_type": "breakfast", "foods": [{"name": "바나나"}]},
        headers=_auth(member_token),
    )
    assert without.status_code == 201, without.text
    without_id = without.json()["id"]
    res = _analyze(client, member_token, _photo_bytes(), meal_type="snack")
    assert res.status_code == 200, res.text
    entry_id, photo_url = res.json()["entry_id"], res.json()["photo_url"]

    day = client.get("/v1/diet/days/today", headers=_auth(member_token))
    assert day.status_code == 200
    entries = {e["id"]: e for e in day.json()["entries"]}
    assert entries[entry_id]["photo_url"] == photo_url
    assert entries[without_id]["photo_url"] is None


def test_an_unreadable_photo_is_refused_before_anything_is_recorded(client, member_token):
    """매직 넘버만 맞춘 파일은 인식 전에 415 — 끼니도 사진도 남지 않는다(#3041)."""
    before = client.get("/v1/diet/days/today", headers=_auth(member_token)).json()
    res = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", b"\xff\xd8\xff\xe0 not really a jpeg", "image/jpeg")},
        data={"meal_type": "dinner"},
        headers=_auth(member_token),
    )

    assert res.status_code == 415, res.text
    after = client.get("/v1/diet/days/today", headers=_auth(member_token)).json()
    assert len(after["entries"]) == len(before["entries"])


def test_a_meal_is_still_recorded_when_storing_its_photo_fails(
    client, member_token, monkeypatch
):
    """사진 저장이 실패해도 끼니 기록은 남는다 — 사진은 기록의 부속이다."""
    from app.services import diet_photo_service

    monkeypatch.setattr(diet_photo_service, "_downscale_to_jpeg", lambda _data: None)
    res = _analyze(client, member_token, _photo_bytes(), meal_type="dinner")

    assert res.status_code == 200, res.text
    assert res.json()["entry_id"]
    assert res.json()["photo_url"] is None


def test_another_member_cannot_open_someone_elses_photo(client, member_token):
    photo_url = _analyze(client, member_token, _photo_bytes()).json()["photo_url"]

    other = _login(client, "sungho@oncare.com")
    stolen = client.get(f"/v1{photo_url}", headers=_auth(other))

    assert stolen.status_code == 404


# ---- 트레이너 조회 ----


def test_the_assigned_trainer_sees_the_same_photo(client, member, member_token):
    member_id, _ = member
    photo_url = _analyze(client, member_token, _photo_bytes()).json()["photo_url"]
    member_image = client.get(f"/v1{photo_url}", headers=_auth(member_token)).content

    trainer = _login(client, _TRAINER_EMAIL)
    meals = client.get(
        f"/v1/trainer/clients/{member_id}/diet", headers=_auth(trainer)
    )
    assert meals.status_code == 200, meals.text
    trainer_urls = [m["photo_url"] for m in meals.json() if m["photo_url"]]
    assert trainer_urls, "트레이너 식단 응답에 사진 경로가 없습니다"

    photo_id = photo_url.rsplit("/", 1)[-1]
    mine = next(u for u in trainer_urls if u.endswith(photo_id))
    assert mine == f"/trainer/clients/{member_id}/diet/photos/{photo_id}"

    image = client.get(f"/v1{mine}", headers=_auth(trainer))
    assert image.status_code == 200
    assert image.content == member_image
    assert "private" in image.headers["cache-control"]


def test_a_trainer_cannot_read_the_photo_of_someone_not_their_client(
    client, member, member_token, db_session
):
    """담당이 아닌 회원의 사진은 404 — 사진 id 를 알아도 열리지 않는다."""
    from app.core.security import hash_password
    from app.models.models import TrainerProfile, User

    photo_url = _analyze(client, member_token, _photo_bytes()).json()["photo_url"]
    photo_id = photo_url.rsplit("/", 1)[-1]

    email = f"stranger-{uuid4().hex[:8]}@oncare.test"
    stranger_id = f"trainer-stranger-{uuid4().hex[:8]}"
    db_session.add(
        User(
            id=stranger_id,
            email=email,
            name="남의 트레이너",
            role="trainer",
            hashed_password=hash_password(_PASSWORD),
        )
    )
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=stranger_id, gym_name="다른 헬스장"))
    db_session.commit()

    try:
        token = _login(client, email)
        # 담당 링크가 없다 → 고객 자체가 없는 것으로 보인다.
        assert client.get(
            f"/v1/trainer/clients/{member[0]}/diet/photos/{photo_id}",
            headers=_auth(token),
        ).status_code == 404
    finally:
        db_session.execute(
            delete(TrainerProfile).where(TrainerProfile.trainer_id == stranger_id)
        )
        db_session.execute(delete(User).where(User.id == stranger_id))
        db_session.commit()


def test_a_trainer_cannot_borrow_a_client_link_to_read_another_members_photo(
    client, member_token
):
    """담당 고객 경로에 **다른 회원의** 사진 id 를 끼워 넣어도 열리지 않는다."""
    photo_id = _analyze(client, member_token, _photo_bytes()).json()[
        "photo_url"
    ].rsplit("/", 1)[-1]

    trainer = _login(client, _TRAINER_EMAIL)
    borrowed = client.get(
        f"/v1/trainer/clients/user-jisu/diet/photos/{photo_id}",
        headers=_auth(trainer),
    )

    assert borrowed.status_code == 404


# ---- 정리 ----


def test_deleting_the_meal_deletes_its_photo(client, member_token):
    from app.db.session import SessionLocal
    from app.models.models import DietPhoto

    body = _analyze(client, member_token, _photo_bytes()).json()
    photo_id = body["photo_url"].rsplit("/", 1)[-1]

    deleted = client.delete(
        f"/v1/diet/entries/{body['entry_id']}", headers=_auth(member_token)
    )
    assert deleted.status_code == 200

    with SessionLocal() as db:
        assert db.scalar(select(DietPhoto).where(DietPhoto.id == photo_id)) is None


def test_deleting_the_account_deletes_the_photos(client, db_session):
    """탈퇴하면 사진도 함께 사라진다 — 남기면 주인 없는 바이트가 쌓인다."""
    from app.core.security import hash_password
    from app.models.models import DietPhoto, User

    email = f"photo-leaver-{uuid4().hex[:8]}@oncare.test"
    member_id = f"user-photo-leaver-{uuid4().hex[:8]}"
    db_session.add(
        User(
            id=member_id,
            email=email,
            name="탈퇴 예정",
            role="member",
            hashed_password=hash_password(_PASSWORD),
        )
    )
    db_session.commit()

    token = _login(client, email)
    photo_id = _analyze(client, token, _photo_bytes()).json()["photo_url"].rsplit(
        "/", 1
    )[-1]

    gone = client.delete("/v1/users/me", headers=_auth(token))
    assert gone.status_code == 200, gone.text

    db_session.expire_all()
    assert db_session.scalar(select(DietPhoto).where(DietPhoto.id == photo_id)) is None


def test_a_meal_photo_over_the_pixel_cap_is_never_stored(
    client, member_token, monkeypatch
):
    """펼칠 픽셀이 상한을 넘는 사진은 펼치지도 저장하지도 않는다. (#3040)

    서버 오류가 아니다. 저장 단계에서 걸리면 끼니는 사진 없이 남고, 인식 전 정리
    단계(#3041)에서 걸리면 415 로 끝난다 — 어느 쪽이든 사진은 남지 않는다.
    """
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "max_image_decode_pixels", 100_000)
    res = _analyze(client, member_token, _photo_bytes((2400, 1600), fmt="PNG"))

    assert res.status_code in (200, 415), res.text
    if res.status_code == 200:
        assert res.json()["entry_id"]
        assert res.json()["photo_url"] is None


def test_a_large_jpeg_meal_photo_is_reduced_while_decoding(
    client, member_token, monkeypatch
):
    """JPEG 은 축소 디코딩한 크기로 센다 — 같은 상한에서도 사진이 저장된다. (#3040)"""
    from app.core.config import get_settings

    # 원본 3200×2400(768만 픽셀)이지만 1/2 로 펼치면 192만이다.
    monkeypatch.setattr(get_settings(), "max_image_decode_pixels", 2_000_000)
    res = _analyze(client, member_token, _photo_bytes((3200, 2400)))

    assert res.status_code == 200, res.text
    assert res.json()["photo_url"]
