"""새 비밀번호의 서버 기준. (#1555)

앞부분은 DB 없이 도는 순수 검사다(`check_new_password` 와 세 스키마). 뒤의
엔드포인트 검사는 `client` 픽스처를 쓰므로 로컬에서 DB 가 없으면 skip 되고
CI 에서 돈다.

확인하는 것:

* 앱 가입 화면(`AppInputRules.signUpPassword`)과 **같은 경계**에서 갈린다.
* 상한은 64자와 UTF-8 72바이트 두 가지다 — 한글·이모지는 64자 안에서도 72바이트를
  넘을 수 있다(bcrypt 가 앞 72바이트만 본다).
* 회원 가입·트레이너 가입·트레이너 비밀번호 변경이 **한 기준**을 쓴다.
* 422 의 `detail[].type` 에 앱이 읽을 코드가 실린다.
* 기준 이전에 만든 약한 비밀번호 계정은 **그대로 로그인된다.**
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from pydantic import ValidationError
from pydantic_core import PydanticCustomError

from app.schemas.trainer_api import TrainerPasswordChange
from app.schemas.user import TrainerRegister, UserRegister
from app.services.password_policy import (
    CODE_EMPTY,
    CODE_TOO_LONG,
    CODE_WEAK,
    PASSWORD_MAX_BYTES,
    PASSWORD_MAX_LENGTH,
    PASSWORD_MIN_LENGTH,
    check_new_password,
)

EMAIL_PREFIX = "pw-policy-"
GOOD = "oncare-pw-1234"

#: 한글 한 글자 = UTF-8 3바이트, 이모지 한 개 = 4바이트.
HANGUL = "가"
EMOJI = "\U0001F4AA"  # 💪


def _code_of(value: str) -> str | None:
    try:
        check_new_password(value)
    except PydanticCustomError as e:
        return e.type
    return None


# ---- 기준 값 (DB 불필요) ----


def test_policy_constants_match_the_app_rule():
    """앱 `AppInputRules` 의 상수와 같은 값이다. 한쪽만 바꾸면 기준이 갈라진다."""
    assert PASSWORD_MIN_LENGTH == 8
    assert PASSWORD_MAX_LENGTH == 64
    assert PASSWORD_MAX_BYTES == 72


# ---- 최소 길이·조합 ----


@pytest.mark.parametrize(
    "value",
    [
        "abcd1234",  # 딱 8자
        "a1234567",  # 영문 1자
        "1234567a",  # 영문이 끝에
        "A1B2C3D4",  # 대문자도 영문이다
        "oncare123",
        "pass word 12",  # 가운데 공백은 비밀번호의 일부
        "p@ss-w0rd!",  # 특수문자는 있어도 없어도 된다
    ],
)
def test_accepts_eight_or_more_with_letter_and_digit(value):
    assert check_new_password(value) == value


def test_empty_is_its_own_code():
    assert _code_of("") == CODE_EMPTY


@pytest.mark.parametrize(
    "value",
    [
        "abc1234",  # 7자
        "a1",
        "1",
        "12345678",  # 숫자만
        "123456789012",
        "abcdefgh",  # 영문만
        "abcdefghijkl",
        "!@#$%^&*",  # 특수문자만
        "        ",  # 공백만 8자
        " " * 20,
        "\t\t\t\t\t\t\t\t",
        "가나다라마바사아",  # 한글은 영문이 아니다
        "가나다라마바사1",
        "abcdefg１",  # 전각 숫자는 숫자로 치지 않는다(앱 `\d` 와 같게)
        "abcdefg١",  # 아라비아-인도 숫자도 마찬가지
        "ａｂｃｄｅｆ1",  # 전각 영문도 영문으로 치지 않는다
    ],
)
def test_rejects_short_or_missing_letter_or_digit(value):
    assert _code_of(value) == CODE_WEAK


def test_whitespace_is_not_trimmed():
    """앞뒤 공백을 잘라내지 않는다 — 앱이 친 그대로 보내고 로그인도 그대로 비교한다."""
    # 잘라내면 7자라 걸릴 값이지만, 공백까지 세어 9자로 통과한다.
    assert check_new_password(" abcd123 ") == " abcd123 "
    assert check_new_password(" abc1234") == " abc1234"


def test_leading_and_trailing_spaces_count_toward_length():
    assert _code_of("abc123 ") == CODE_WEAK  # 7자
    assert _code_of("abc123  ") is None  # 8자


# ---- 최대 길이 (글자 수) ----


def test_sixty_four_characters_pass():
    value = "a1" * 32
    assert len(value) == 64
    assert check_new_password(value) == value


def test_sixty_five_characters_fail():
    value = "a1" * 32 + "x"
    assert _code_of(value) == CODE_TOO_LONG


def test_far_over_the_limit_fails_with_the_same_code():
    assert _code_of("a1" * 500) == CODE_TOO_LONG


# ---- 최대 길이 (UTF-8 바이트) ----


def test_hangul_at_seventy_two_bytes_passes():
    # 한글 22자(66바이트) + 영문·숫자 6자 = 72바이트, 28자
    value = HANGUL * 22 + "abc123"
    assert len(value.encode("utf-8")) == 72
    assert check_new_password(value) == value


def test_hangul_at_seventy_three_bytes_fails():
    value = HANGUL * 22 + "abc1234"
    assert len(value.encode("utf-8")) == 73
    assert len(value) < PASSWORD_MAX_LENGTH  # 글자 수로는 한참 모자라다
    assert _code_of(value) == CODE_TOO_LONG


def test_hangul_over_by_a_whole_character_fails():
    # 한글 24자 = 72바이트, 영문·숫자를 더하면 넘친다
    value = HANGUL * 24 + "a1"
    assert len(value.encode("utf-8")) == 74
    assert _code_of(value) == CODE_TOO_LONG


def test_emoji_at_seventy_two_bytes_passes():
    # 이모지 16개(64바이트) + 8바이트 = 72
    value = EMOJI * 16 + "abcd1234"
    assert len(value.encode("utf-8")) == 72
    assert check_new_password(value) == value


def test_emoji_at_seventy_three_bytes_fails():
    value = EMOJI * 16 + "abcd12345"
    assert len(value.encode("utf-8")) == 73
    assert _code_of(value) == CODE_TOO_LONG


def test_emoji_counts_as_one_character_for_the_minimum():
    """글자 수는 코드 포인트로 센다 — 이모지 한 개가 두 글자로 세이지 않는다.

    UTF-16 으로 세면 아래 값이 9단위라 통과해 버린다. 앱도 `runes` 로 센다.
    """
    value = "abc12" + EMOJI * 2  # 코드 포인트 7개, UTF-16 9단위
    assert len(value) == 7
    assert _code_of(value) == CODE_WEAK
    assert _code_of(value + "x") is None


def test_too_long_wins_over_weak():
    """길이를 먼저 본다 — 너무 긴 값에 '더 길게 쓰라' 는 안내를 주지 않는다."""
    assert _code_of("a" * 65) == CODE_TOO_LONG
    assert _code_of(HANGUL * 30) == CODE_TOO_LONG


# ---- 세 스키마가 같은 기준을 쓴다 ----


def _register(password: str) -> dict:
    return {"email": "member@oncare.com", "password": password}


@pytest.mark.parametrize(
    ("password", "code"),
    [
        ("", CODE_EMPTY),
        ("abc1234", CODE_WEAK),
        ("12345678", CODE_WEAK),
        ("abcdefgh", CODE_WEAK),
        ("        ", CODE_WEAK),
        ("a1" * 32 + "x", CODE_TOO_LONG),
        (HANGUL * 22 + "abc1234", CODE_TOO_LONG),
    ],
)
def test_all_three_schemas_reject_the_same_values(password, code):
    cases = [
        lambda: UserRegister(**_register(password)),
        lambda: TrainerRegister(**_register(password)),
        lambda: TrainerPasswordChange(
            current_password="old-pw-1", new_password=password
        ),
    ]
    for build in cases:
        with pytest.raises(ValidationError) as info:
            build()
        errors = info.value.errors()
        assert [e["type"] for e in errors] == [code]
        assert errors[0]["loc"][-1] in {"password", "new_password"}


@pytest.mark.parametrize(
    "password", ["abcd1234", "a1" * 32, HANGUL * 22 + "abc123", " abcd123 "]
)
def test_all_three_schemas_accept_the_same_values(password):
    assert UserRegister(**_register(password)).password == password
    assert (
        TrainerRegister(**_register(password)).password
        == password
    )
    assert (
        TrainerPasswordChange(
            current_password="old", new_password=password
        ).new_password
        == password
    )


def test_current_password_is_not_held_to_the_new_rule():
    """지금 비밀번호는 기준 이전 것일 수 있다 — 막으면 바꿀 길이 없어진다."""
    change = TrainerPasswordChange(current_password="pw", new_password=GOOD)
    assert change.current_password == "pw"


def test_new_password_used_to_accept_digits_only():
    """전에는 8~200자만 봐서 숫자만 쓴 값도, 72바이트를 넘는 값도 받았다."""
    for value in ("12345678", "a1" * 100):
        with pytest.raises(ValidationError):
            TrainerPasswordChange(current_password="old", new_password=value)


def test_message_carries_the_limits():
    """문장은 한국어 안내용이다 — 앱은 코드로 자기 문구를 고르지만, 직접 호출한
    사람도 무엇이 틀렸는지 읽을 수 있어야 한다."""
    with pytest.raises(PydanticCustomError) as weak:
        check_new_password("abc")
    assert "8" in str(weak.value)
    with pytest.raises(PydanticCustomError) as long:
        check_new_password("a1" * 40)
    assert "64" in str(long.value) and "72" in str(long.value)


# ---- 엔드포인트 (DB 필요) ----


@pytest.fixture
def _cleanup(db_session):
    from app.models.models import HealthProfile, TrainerProfile, User

    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        db_session.query(HealthProfile).filter(
            HealthProfile.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.commit()


def _email() -> str:
    return f"{EMAIL_PREFIX}{uuid4().hex[:10]}@oncare.com"


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str, password: str):
    return client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )


def _detail_types(response) -> list[str]:
    return [item["type"] for item in response.json()["detail"]]


def _weak_account(db_session, *, role: str, password: str) -> str:
    """기준 이전에 만든 계정처럼, 스키마를 거치지 않고 약한 비밀번호로 넣는다."""
    from app.core.security import hash_password
    from app.models.models import TrainerProfile, User

    email = _email()
    user_id = f"{EMAIL_PREFIX}{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=user_id,
            email=email,
            name="기존 계정",
            hashed_password=hash_password(password),
            role=role,
        )
    )
    db_session.flush()
    if role == "trainer":
        db_session.add(
            TrainerProfile(
                trainer_id=user_id, specialty="퍼스널 트레이너", career_years=1
            )
        )
    db_session.commit()
    return email


# -- 회원 가입 --


@pytest.mark.parametrize(
    ("password", "code"),
    [
        ("", CODE_EMPTY),
        ("abc1234", CODE_WEAK),
        ("12345678", CODE_WEAK),
        ("abcdefgh", CODE_WEAK),
        ("        ", CODE_WEAK),
        ("a1" * 32 + "x", CODE_TOO_LONG),
        (HANGUL * 22 + "abc1234", CODE_TOO_LONG),
        (EMOJI * 16 + "abcd12345", CODE_TOO_LONG),
    ],
)
def test_member_register_rejects_with_a_code(client, _cleanup, password, code):
    email = _email()
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "정책 회원"},
    )
    assert r.status_code == 422, r.text
    assert _detail_types(r) == [code]
    assert r.json()["detail"][0]["loc"] == ["body", "password"]
    # 계정이 만들어지지 않았다 — 같은 이메일로 로그인되지 않는다(빈 값은 로그인
    # 폼에서 422, 나머지는 401).
    assert _login(client, email, password).status_code in {401, 422}


@pytest.mark.parametrize(
    "password",
    ["abcd1234", "a1" * 32, HANGUL * 22 + "abc123", EMOJI * 16 + "abcd1234", " abcd123 "],
)
def test_member_register_accepts_and_logs_in_with_the_exact_value(
    client, _cleanup, password
):
    email = _email()
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "정책 회원"},
    )
    assert r.status_code == 201, r.text
    assert _login(client, email, password).status_code == 200


def test_member_register_does_not_trim_the_password(client, _cleanup):
    """앞뒤 공백까지 비밀번호다 — 공백을 뺀 값으로는 로그인되지 않는다."""
    email = _email()
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": " abcd1234 ", "name": "공백"},
    )
    assert r.status_code == 201, r.text
    assert _login(client, email, " abcd1234 ").status_code == 200
    assert _login(client, email, "abcd1234").status_code == 401


def test_member_register_missing_password_is_still_422(client, _cleanup):
    r = client.post(
        "/v1/auth/register", json={"email": _email(), "name": "비밀번호 없음"}
    )
    assert r.status_code == 422, r.text
    assert _detail_types(r) == ["missing"]


# -- 트레이너 가입 --


@pytest.mark.parametrize(
    ("password", "code"),
    [
        ("", CODE_EMPTY),
        ("abc1234", CODE_WEAK),
        ("12345678", CODE_WEAK),
        ("a1" * 32 + "x", CODE_TOO_LONG),
        (HANGUL * 24 + "a1", CODE_TOO_LONG),
    ],
)
def test_trainer_register_rejects_with_a_code(
    client, _cleanup, password, code
):
    r = client.post(
        "/v1/auth/trainer/register",
        json={
            "email": _email(),
            "password": password,
            "name": "정책 트레이너",
        },
    )
    assert r.status_code == 422, r.text
    assert _detail_types(r) == [code]
    assert r.json()["detail"][0]["loc"] == ["body", "password"]


def test_trainer_register_can_retry_after_a_weak_password(client, _cleanup):
    """비밀번호에서 막히면 계정이 남지 않는다 — 고쳐서 같은 이메일로 다시 가입할 수 있다."""
    email = _email()
    weak = client.post(
        "/v1/auth/trainer/register",
        json={
            "email": email,
            "password": "12345678",
            "name": "정책 트레이너",
        },
    )
    assert weak.status_code == 422, weak.text

    ok = client.post(
        "/v1/auth/trainer/register",
        json={
            "email": email,
            "password": GOOD,
            "name": "정책 트레이너",
        },
    )
    assert ok.status_code == 201, ok.text
    token = _login(client, email, GOOD).json()["access_token"]
    assert client.get("/v1/trainer/me", headers=_auth(token)).status_code == 200


# -- 기존 계정 로그인 --


@pytest.mark.parametrize("password", ["pw", "12345678", "abcdefgh", "a" * 70])
def test_existing_member_with_a_weak_password_still_logs_in(
    client, db_session, _cleanup, password
):
    email = _weak_account(db_session, role="member", password=password)
    r = _login(client, email, password)
    assert r.status_code == 200, r.text
    assert r.json()["access_token"]


def test_existing_trainer_with_a_weak_password_still_logs_in(
    client, db_session, _cleanup
):
    email = _weak_account(db_session, role="trainer", password="pw")
    r = _login(client, email, "pw")
    assert r.status_code == 200, r.text
    me = client.get("/v1/trainer/me", headers=_auth(r.json()["access_token"]))
    assert me.status_code == 200, me.text


def test_wrong_password_is_still_401_not_422(client, db_session, _cleanup):
    """로그인은 기준을 보지 않는다 — 틀린 값은 형식과 무관하게 401 이다."""
    email = _weak_account(db_session, role="member", password="pw")
    assert _login(client, email, "x").status_code == 401
    assert _login(client, email, "").status_code in {401, 422}


def test_login_with_more_than_seventy_two_bytes_is_401_not_500(
    client, db_session, _cleanup
):
    """bcrypt 5 는 72바이트를 넘는 값을 ValueError 로 거절한다. 로그인은 그걸
    틀린 비밀번호로 다룬다 — 새 비밀번호는 그보다 길 수 없으므로 맞을 수가 없다."""
    email = _weak_account(db_session, role="member", password="pw")
    assert _login(client, email, "a1" * 40).status_code == 401
    assert _login(client, email, HANGUL * 30).status_code == 401
    assert _login(client, email, "pw").status_code == 200


# -- 트레이너 비밀번호 변경 --


@pytest.mark.parametrize(
    ("password", "code"),
    [
        ("", CODE_EMPTY),
        ("abc1234", CODE_WEAK),
        ("12345678", CODE_WEAK),
        ("abcdefgh", CODE_WEAK),
        ("        ", CODE_WEAK),
        ("a1" * 32 + "x", CODE_TOO_LONG),
        (HANGUL * 22 + "abc1234", CODE_TOO_LONG),
    ],
)
def test_trainer_password_change_rejects_with_a_code(
    client, db_session, _cleanup, password, code
):
    email = _weak_account(db_session, role="trainer", password="pw")
    token = _login(client, email, "pw").json()["access_token"]
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "pw", "new_password": password},
        headers=_auth(token),
    )
    assert r.status_code == 422, r.text
    assert _detail_types(r) == [code]
    assert r.json()["detail"][0]["loc"] == ["body", "new_password"]
    # 비밀번호는 그대로다.
    assert _login(client, email, "pw").status_code == 200


def test_weak_trainer_can_move_to_a_compliant_password(
    client, db_session, _cleanup
):
    """약한 비밀번호 계정이 현재 비밀번호로 확인받고 기준에 맞는 값으로 바꾼다."""
    email = _weak_account(db_session, role="trainer", password="pw")
    token = _login(client, email, "pw").json()["access_token"]
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "pw", "new_password": GOOD},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert _login(client, email, "pw").status_code == 401
    assert _login(client, email, GOOD).status_code == 200


@pytest.mark.parametrize("password", ["a1" * 32, HANGUL * 22 + "abc123"])
def test_trainer_password_change_accepts_the_upper_bounds(
    client, db_session, _cleanup, password
):
    email = _weak_account(db_session, role="trainer", password="pw")
    token = _login(client, email, "pw").json()["access_token"]
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "pw", "new_password": password},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert _login(client, email, password).status_code == 200


def test_trainer_password_change_bytes_after_seventy_two_matter(
    client, db_session, _cleanup
):
    """72바이트를 넘는 값을 받지 않으므로, 뒤를 바꾼 값으로 로그인되는 일이 없다."""
    email = _weak_account(db_session, role="trainer", password="pw")
    token = _login(client, email, "pw").json()["access_token"]
    too_long = "a1" * 36 + "tail"  # 76바이트
    r = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "pw", "new_password": too_long},
        headers=_auth(token),
    )
    assert r.status_code == 422, r.text
    assert _login(client, email, "a1" * 36 + "XXXX").status_code == 401


# ---- bcrypt 72바이트 (DB 불필요) ----


def test_verify_password_treats_over_seventy_two_bytes_as_a_mismatch():
    from app.core.security import BCRYPT_MAX_BYTES, hash_password, verify_password

    assert BCRYPT_MAX_BYTES == PASSWORD_MAX_BYTES
    hashed = hash_password("a1" * 36)  # 딱 72바이트
    assert verify_password("a1" * 36, hashed) is True
    # 72바이트까지 같고 뒤가 붙은 값 — 예전 bcrypt 는 잘라서 맞다고 했다.
    assert verify_password("a1" * 36 + "tail", hashed) is False
    assert verify_password(HANGUL * 25, hashed) is False


def test_every_accepted_password_can_be_hashed_and_verified():
    """기준을 통과한 값은 bcrypt 가 그대로 받는다 — 가입·변경이 500 이 되지 않는다."""
    from app.core.security import hash_password, verify_password

    for value in ("a1" * 32, HANGUL * 22 + "abc123", EMOJI * 16 + "abcd1234"):
        check_new_password(value)
        assert verify_password(value, hash_password(value)) is True
