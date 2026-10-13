"""코칭 시트 피드백의 회원별 캐시·무효화·하루 상한·회원 전용 권한. (#3351) DB 필요(로컬 skip, CI 실행).

`GET /ai-coach/feedback` 은 호출 한 번에 모델을 최대 두 번 부르는데 캐시도 회원별
제한도 없었다. 여기서 보는 것:

* 같은 날·같은 언어로 다시 부르면 모델을 부르지 않는다. 인사말은 매번 새로 만든다.
* 식단·운동 기록이 바뀌면 그 회원의 캐시만 버린다 — 다음 요청이 새 기록을 말한다.
* 판정 기준인 회원 목표(나트륨·주간 유산소, #3350)가 바뀌어도 버린다. 포인트처럼
  카드와 무관한 프로필 변경은 캐시를 건드리지 않는다.
* 캐시 시간이 지나거나 날(KST)이 바뀌거나 언어가 다르면 새로 만든다.
* 하루 상한을 넘으면 오류가 아니라 규칙 기반 카드다. 날이 바뀌면 다시 열린다.
* 만드는 사이에 기록이 바뀌면 그 응답은 캐시에 남기지 않는다.
* 트레이너 계정·토큰 없는 요청은 받지 않는다.
"""
from __future__ import annotations

from datetime import timedelta
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.core import clock
from app.core.config import get_settings
from app.core.security import create_access_token, hash_password
from app.core.week import monday_of
from sqlalchemy import select

from app.models.models import (
    CoachFeedbackState,
    DietEntry,
    ExerciseSession,
    HealthProfile,
    User,
)
from app.services import coach_feedback_service
from app.services.coach import domain_coaches

pytest.importorskip("fastapi")

EN = {"Accept-Language": "en"}
_AI_BODY = "저녁 식사 뒤 20분 걸어 보세요."
_NO_DIET_TITLE = "오늘 식단을 기록해 보세요"


class _CountingLLM:
    """부른 횟수를 세고 정해진 문장을 돌려준다. `on_call` 은 모델을 기다리는 사이의 일이다."""

    def __init__(self) -> None:
        self.calls = 0
        self.on_call = None

    def generate(self, system_prompt: str, user_prompt: str):
        self.calls += 1
        if self.on_call is not None:
            self.on_call()
        return SimpleNamespace(text=_AI_BODY)


@pytest.fixture
def llm(monkeypatch) -> _CountingLLM:
    stub = _CountingLLM()
    monkeypatch.setattr(domain_coaches, "get_coach_llm", lambda *_a, **_k: stub)
    # 검색 자료가 없으면 모델을 부르지 않고 폴백한다 — 자료가 있는 것처럼 둔다.
    monkeypatch.setattr(
        domain_coaches, "retrieve_context", lambda *_a, **_k: "[참고 자료]\n- 걷기"
    )
    return stub


@pytest.fixture
def limits(monkeypatch):
    """캐시 시간·하루 상한을 테스트가 정한다. 기본은 운영 기본값이다."""
    settings = get_settings()

    def _set(*, cache_seconds: int | None = None, per_day: int | None = None) -> None:
        if cache_seconds is not None:
            monkeypatch.setattr(settings, "coach_feedback_cache_seconds", cache_seconds)
        if per_day is not None:
            monkeypatch.setattr(settings, "coach_feedback_per_day", per_day)

    monkeypatch.setattr(settings, "rate_limit_enabled", True)
    return _set


def _member(client) -> tuple[str, dict[str, str]]:
    email = f"coach-cache-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "수빈"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def _get(client, headers, **extra):
    r = client.get("/v1/ai-coach/feedback", headers={**headers, **extra})
    assert r.status_code == 200, r.text
    return r.json()


def _card(body: dict, tag: str) -> dict:
    return next(s for s in body["suggestions"] if s["tag"] == tag)


def _add_diet(db_session, user_id: str, *, sodium: int = 800) -> str:
    entry_id = f"cache-diet-{uuid4().hex[:8]}"
    db_session.add(
        DietEntry(
            id=entry_id, user_id=user_id, date=clock.today_iso(), meal_type="lunch",
            total_calories=600, sodium_mg=sodium, sugar_g=10,
        )
    )
    db_session.commit()
    return entry_id


def _add_exercise(db_session, user_id: str, *, minutes: int = 40) -> str:
    session_id = f"cache-ex-{uuid4().hex[:8]}"
    today = clock.today()
    db_session.add(
        ExerciseSession(
            id=session_id, user_id=user_id, week_start=monday_of(today).isoformat(),
            day_label="월", type="cardio", name="걷기", minutes=minutes, calories=150,
        )
    )
    db_session.commit()
    return session_id


def _state(db_session, user_id: str) -> CoachFeedbackState | None:
    db_session.expire_all()
    return db_session.get(CoachFeedbackState, user_id)


# ---- 캐시 ----


def test_reopening_the_sheet_does_not_call_the_model_again(client, llm, limits):
    _, h = _member(client)

    first = _get(client, h)
    calls = llm.calls
    again = _get(client, h)
    third = _get(client, h)

    # 기록이 없는 회원은 식단이 규칙 카드라 운동 코치만 모델을 부른다.
    assert calls == 1
    assert llm.calls == calls
    assert again["suggestions"] == first["suggestions"] == third["suggestions"]
    assert _card(again, "exercise")["body"] == _AI_BODY
    assert _card(again, "diet")["title"] == _NO_DIET_TITLE


def test_cached_reply_counts_one_generation(client, db_session, llm, limits):
    member_id, h = _member(client)

    for _ in range(3):
        _get(client, h)

    db_session.expire_all()
    assert coach_feedback_service.used_today(db_session, member_id) == 1


def test_greeting_is_not_cached(client, llm, limits, monkeypatch):
    limits(cache_seconds=24 * 60 * 60)
    _, h = _member(client)
    day = clock.now().replace(hour=9, minute=0, second=0, microsecond=0)
    monkeypatch.setattr(clock, "now", lambda: day)
    morning = _get(client, h)

    monkeypatch.setattr(clock, "now", lambda: day.replace(hour=20))
    evening = _get(client, h)

    assert "좋은 아침" in morning["greeting"]
    assert "마무리" in evening["greeting"]
    # 카드는 캐시 그대로다 — 인사말만 시각을 따라간다.
    assert evening["suggestions"] == morning["suggestions"]
    assert llm.calls == 1


def test_cache_expires_after_the_configured_seconds(client, llm, limits, monkeypatch):
    limits(cache_seconds=600)
    _, h = _member(client)
    start = clock.now().replace(hour=10, minute=0, second=0, microsecond=0)
    monkeypatch.setattr(clock, "now", lambda: start)
    _get(client, h)

    monkeypatch.setattr(clock, "now", lambda: start + timedelta(seconds=599))
    _get(client, h)
    assert llm.calls == 1

    monkeypatch.setattr(clock, "now", lambda: start + timedelta(seconds=600))
    _get(client, h)
    assert llm.calls == 2


def test_zero_cache_seconds_generates_every_time(client, db_session, llm, limits):
    limits(cache_seconds=0)
    member_id, h = _member(client)

    _get(client, h)
    _get(client, h)

    assert llm.calls == 2
    state = _state(db_session, member_id)
    assert state is not None and state.payload_json is None
    assert state.generations == 2


def test_an_english_header_reads_the_same_cached_cards(client, llm, limits):
    """서버 문장은 한국어 하나다 — 헤더가 달라도 같은 카드를 캐시에서 준다(#3404)."""
    _, h = _member(client)

    plain = _get(client, h)
    en = _get(client, h, **EN)

    assert llm.calls == 1
    assert _card(plain, "diet")["title"] == _NO_DIET_TITLE
    assert en == plain


def test_cache_is_per_member(client, llm, limits):
    _, a = _member(client)
    _, b = _member(client)

    _get(client, a)
    _get(client, b)
    _get(client, a)

    assert llm.calls == 2


def test_new_day_drops_yesterdays_cards(client, db_session, llm, limits, monkeypatch):
    member_id, h = _member(client)
    late = clock.now().replace(hour=23, minute=55, second=0, microsecond=0)
    monkeypatch.setattr(clock, "now", lambda: late)
    _get(client, h)
    assert llm.calls == 1

    # 캐시 시간(30분) 안이지만 날이 바뀌었다 — 어제 카드를 쓰지 않는다.
    monkeypatch.setattr(clock, "now", lambda: late + timedelta(minutes=10))
    _get(client, h)

    assert llm.calls == 2
    state = _state(db_session, member_id)
    assert state.kst_date == (late + timedelta(minutes=10)).date().isoformat()
    assert state.generations == 1


# ---- 기록 변경 시 무효화 ----


def test_diet_record_drops_the_cache_and_the_next_sheet_reflects_it(
    client, db_session, llm, limits
):
    member_id, h = _member(client)
    before = _get(client, h)
    assert _card(before, "diet")["title"] == _NO_DIET_TITLE

    _add_diet(db_session, member_id)
    after = _get(client, h)

    assert _card(after, "diet")["title"] != _NO_DIET_TITLE
    assert _card(after, "diet")["title"] == "오늘의 식단 코칭"
    # 식단·운동 코치를 다시 만들었다.
    assert llm.calls == 3
    # 그 뒤로는 다시 캐시다.
    _get(client, h)
    assert llm.calls == 3


def test_high_sodium_record_shows_up_right_away(client, db_session, llm, limits):
    member_id, h = _member(client)
    _get(client, h)

    _add_diet(db_session, member_id, sodium=5000)

    assert _card(_get(client, h), "diet")["title"] == "나트륨 섭취가 많아요"


def test_exercise_record_drops_the_cache(client, db_session, llm, limits):
    member_id, h = _member(client)
    _get(client, h)
    calls = llm.calls

    _add_exercise(db_session, member_id)
    _get(client, h)

    assert llm.calls == calls + 1
    assert _state(db_session, member_id).revision == 1


def test_editing_and_deleting_a_record_drop_the_cache(client, db_session, llm, limits):
    member_id, h = _member(client)
    session_id = _add_exercise(db_session, member_id)
    _get(client, h)
    assert _state(db_session, member_id).payload_json is not None

    row = db_session.get(ExerciseSession, session_id)
    row.minutes = 90
    db_session.commit()
    assert _state(db_session, member_id).payload_json is None

    _get(client, h)
    assert _state(db_session, member_id).payload_json is not None
    db_session.delete(db_session.get(ExerciseSession, session_id))
    db_session.commit()
    assert _state(db_session, member_id).payload_json is None


def test_another_members_record_keeps_my_cache(client, db_session, llm, limits):
    _, mine = _member(client)
    other_id, _ = _member(client)
    _get(client, mine)
    calls = llm.calls

    _add_diet(db_session, other_id)
    _add_exercise(db_session, other_id)
    _get(client, mine)

    assert llm.calls == calls


def test_rolled_back_record_keeps_the_cache(client, db_session, llm, limits):
    member_id, h = _member(client)
    _get(client, h)
    calls = llm.calls

    db_session.add(
        DietEntry(
            id=f"cache-diet-{uuid4().hex[:8]}", user_id=member_id, date=clock.today_iso(),
            meal_type="lunch", total_calories=500, sodium_mg=700, sugar_g=5,
        )
    )
    db_session.flush()
    db_session.rollback()
    _get(client, h)

    assert llm.calls == calls


def test_record_saved_while_generating_is_not_hidden_by_a_stale_cache(
    client, db_session, llm, limits
):
    """만드는 사이에 들어온 기록 — 옛 기록으로 만든 카드를 캐시에 남기지 않는다."""
    member_id, h = _member(client)
    llm.on_call = lambda: _add_exercise(db_session, member_id)

    _get(client, h)
    llm.on_call = None

    assert _state(db_session, member_id).payload_json is None
    calls = llm.calls
    _get(client, h)
    assert llm.calls == calls + 1


def _profile(db_session, user_id: str) -> HealthProfile:
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == user_id)
    )
    if profile is None:
        profile = HealthProfile(user_id=user_id)
        db_session.add(profile)
        db_session.commit()
    return profile


def test_changing_the_sodium_goal_drops_the_cache(client, db_session, llm, limits):
    """목표를 낮추면 같은 기록이 초과가 된다 — 옛 기준의 카드를 남기지 않는다(#3350)."""
    member_id, h = _member(client)
    _profile(db_session, member_id)
    _add_diet(db_session, member_id, sodium=1500)
    assert _card(_get(client, h), "diet")["title"] == "오늘의 식단 코칭"

    _profile(db_session, member_id).daily_sodium_mg = 1200
    db_session.commit()

    assert _state(db_session, member_id).payload_json is None
    assert _card(_get(client, h), "diet")["title"] == "나트륨 섭취가 많아요"


def test_changing_the_cardio_goal_drops_the_cache(client, db_session, llm, limits):
    limits(per_day=1)
    member_id, h = _member(client)
    _profile(db_session, member_id)
    _add_exercise(db_session, member_id, minutes=100)
    _get(client, h)

    _profile(db_session, member_id).weekly_cardio_minutes = 90
    db_session.commit()
    # 상한이 찼으니 규칙 카드다 — 새 목표로 판정한다.
    over = _get(client, h)

    assert llm.calls == 1
    assert _card(over, "exercise")["title"] == "운동량이 충분해요"


def test_unrelated_profile_change_keeps_the_cache(client, db_session, llm, limits):
    member_id, h = _member(client)
    _profile(db_session, member_id)
    _get(client, h)
    calls = llm.calls

    _profile(db_session, member_id).activity_points = 500
    db_session.commit()
    _get(client, h)

    assert _state(db_session, member_id).payload_json is not None
    assert llm.calls == calls


def test_invalidate_without_a_state_row_is_a_no_op(db_session):
    user_id = f"user-cache-{uuid4().hex[:8]}"
    db_session.add(
        User(
            id=user_id, email=f"{user_id}@oncare.com", name="새 회원",
            hashed_password=hash_password("test-pw-1234"),
        )
    )
    db_session.commit()

    coach_feedback_service.invalidate(db_session, user_id)
    db_session.commit()

    assert _state(db_session, user_id) is None
    assert coach_feedback_service.used_today(db_session, user_id) == 0


# ---- 회원별 하루 상한 ----


def test_over_the_daily_limit_returns_rule_cards_not_an_error(
    client, db_session, llm, limits
):
    limits(cache_seconds=0, per_day=2)
    member_id, h = _member(client)

    _get(client, h)
    _get(client, h)
    assert llm.calls == 2

    over = _get(client, h)

    assert llm.calls == 2
    assert [s["tag"] for s in over["suggestions"]] == ["diet", "exercise"]
    assert _card(over, "exercise")["title"] == "이번 주 운동을 시작해 보세요"
    assert over["greeting"]
    assert coach_feedback_service.used_today(db_session, member_id) == 2


def test_rule_cards_over_the_limit_follow_new_records(client, db_session, llm, limits):
    limits(per_day=1)
    member_id, h = _member(client)
    _get(client, h)

    # 기록이 캐시를 버렸고 상한은 이미 찼다 — 규칙 카드가 새 기록을 말한다.
    _add_exercise(db_session, member_id, minutes=40)
    over = _get(client, h)

    assert llm.calls == 1
    assert _card(over, "exercise")["title"] == "조금만 더 움직여봐요"
    assert "유산소 40분" in _card(over, "exercise")["body"]


def test_rule_cards_over_the_limit_are_korean_for_an_english_header(client, llm, limits):
    limits(cache_seconds=0, per_day=1)
    _, h = _member(client)
    _get(client, h)

    over = _get(client, h, **EN)

    assert llm.calls == 1
    assert any("가" <= ch <= "힣" for ch in _card(over, "exercise")["title"])


def test_daily_limit_is_per_member(client, llm, limits):
    limits(cache_seconds=0, per_day=1)
    _, a = _member(client)
    _, b = _member(client)

    _get(client, a)
    _get(client, a)
    body = _get(client, b)

    assert llm.calls == 2
    assert _card(body, "exercise")["body"] == _AI_BODY


def test_daily_limit_reopens_on_the_next_kst_day(client, llm, limits, monkeypatch):
    limits(cache_seconds=0, per_day=1)
    _, h = _member(client)
    noon = clock.now().replace(hour=12, minute=0, second=0, microsecond=0)
    monkeypatch.setattr(clock, "now", lambda: noon)
    _get(client, h)
    _get(client, h)
    assert llm.calls == 1

    monkeypatch.setattr(clock, "now", lambda: noon + timedelta(days=1))
    body = _get(client, h)

    assert llm.calls == 2
    assert _card(body, "exercise")["body"] == _AI_BODY


def test_zero_limit_turns_the_cap_off(client, llm, limits):
    limits(cache_seconds=0, per_day=0)
    _, h = _member(client)

    for _ in range(4):
        _get(client, h)

    assert llm.calls == 4


def test_rate_limit_switch_turns_the_cap_off_but_keeps_the_cache(limits, monkeypatch):
    limits(cache_seconds=1800, per_day=1)
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", False)
    assert coach_feedback_service.daily_limit() == 0
    assert coach_feedback_service.cache_seconds() == 1800


# ---- 회원 전용 ----


def test_trainer_account_is_refused(client, db_session, llm):
    trainer_id = f"user-cache-tr-{uuid4().hex[:8]}"
    db_session.add(
        User(
            id=trainer_id, email=f"{trainer_id}@oncare.com", name="트레이너",
            hashed_password=hash_password("test-pw-1234"), role="trainer",
        )
    )
    db_session.commit()
    headers = {"Authorization": f"Bearer {create_access_token(trainer_id)}"}

    r = client.get("/v1/ai-coach/feedback", headers=headers)

    assert r.status_code == 403
    assert llm.calls == 0


def test_request_without_a_token_is_refused(client, llm):
    r = client.get("/v1/ai-coach/feedback")

    assert r.status_code == 401
    assert llm.calls == 0
