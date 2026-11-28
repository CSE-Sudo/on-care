"""운동 `이번 주` AI 조언 — 탭 카드의 짧은 문장과 홈 코칭 시트의 긴 문장. (#3549) DB 필요.

보는 것:
1. 이번 주 운동 기록이 없으면 AI 를 부르지 않는다.
2. 한 번의 호출로 두 문장을 받아 보관하고, 기록이 그대로면 그날 다시 부르지 않는다.
3. 운동 기록이 바뀌면 다시 만들되 하루 5번까지다. AI 가 실패하면 1시간 뒤 다시 만든다.
4. 트레이너 경로(`generate=False`)는 보관한 문장만 읽는다.
5. `GET /exercise/advice` 는 `이번 주` 에만 `ai_sentence` 를 싣고, 홈 코칭 시트는 같은
   긴 문장을 새 호출 없이 잇는다.
"""
from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import delete

from app.core import clock
from app.services import exercise_week_ai as svc
from app.services import week_advice_refresh

MON = date(2026, 9, 21)  # 월요일
SENTENCE = "주말에 스트레칭을 더해요."
DETAIL = "이번 주는 걷기를 꾸준히 이어 갔어요. 남은 날에는 가벼운 근력 운동을 한 번 더해 보세요."


def _pair(sentence: str = SENTENCE, detail: str = DETAIL) -> str:
    return json.dumps({"sentence": sentence, "detail": detail}, ensure_ascii=False)


class _FakeAI:
    def __init__(self, answer: str | None = None, fail: bool = False) -> None:
        self.answer = answer or _pair()
        self.fail = fail
        self.calls = 0
        self.systems: list[str] = []
        self.users: list[str] = []

    def __call__(self, system: str, user: str) -> str:
        self.calls += 1
        self.systems.append(system)
        self.users.append(user)
        if self.fail:
            raise RuntimeError("키 없음")
        return self.answer


@pytest.fixture
def ai(monkeypatch) -> _FakeAI:
    fake = _FakeAI()
    monkeypatch.setattr(svc, "_call_llm", fake)
    return fake


class _Clock:
    """`clock.now` 를 테스트가 정한다. 기본은 목요일 저녁이다."""

    def __init__(self, monkeypatch) -> None:
        self.at = datetime(2026, 9, 24, 19, 0, tzinfo=clock.SEOUL)
        monkeypatch.setattr(clock, "now", lambda: self.at)


@pytest.fixture
def now(monkeypatch) -> _Clock:
    return _Clock(monkeypatch)


@pytest.fixture
def member(db_session):
    from app.core.security import hash_password
    from app.models.models import DietAdviceState, ExerciseSession, HealthProfile, User

    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=f"exweek-{uuid.uuid4().hex[:8]}@example.com",
        name="운동 이번 주", hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user)
    db_session.add(HealthProfile(user_id=user.id, weekly_cardio_minutes=150))
    db_session.commit()
    yield user
    db_session.rollback()
    for model in (DietAdviceState, ExerciseSession, HealthProfile):
        db_session.execute(delete(model).where(model.user_id == user.id))
    db_session.execute(delete(User).where(User.id == user.id))
    db_session.commit()


def _move(db_session, user_id: str, day_label: str = "월", *, kind: str = "cardio",
          name: str = "걷기", minutes: int = 30) -> str:
    from app.models.models import ExerciseSession

    session_id = f"exweek-{uuid.uuid4().hex[:10]}"
    db_session.add(ExerciseSession(
        id=session_id, user_id=user_id, week_start=MON.isoformat(), day_label=day_label,
        type=kind, name=name, minutes=minutes, calories=150,
    ))
    db_session.commit()
    return session_id


# ── 생성·보관 ────────────────────────────────────────────────────────────


def test_no_exercise_this_week_does_not_call_the_ai(db_session, member, ai, now):
    assert svc.week_ai(db_session, member.id) is None
    assert ai.calls == 0


def test_one_call_gives_both_sentences_and_is_kept_while_records_stay(
    db_session, member, ai, now
):
    _move(db_session, member.id, "월")
    _move(db_session, member.id, "수", kind="strength", name="스쿼트")

    first = svc.week_ai(db_session, member.id)
    assert (first.sentence, first.detail) == (SENTENCE, DETAIL)
    assert ai.calls == 1
    # 회원이 적은 운동 이름이 요일 순으로 실린다.
    assert "- 월 유산소: 걷기 30분" in ai.users[0]
    assert "스쿼트" in ai.users[0]

    now.at += timedelta(hours=3)
    again = svc.week_ai(db_session, member.id)
    assert (again.sentence, again.detail) == (SENTENCE, DETAIL)
    assert ai.calls == 1

    # 다음 날에는 새로 만든다.
    now.at += timedelta(days=1)
    svc.week_ai(db_session, member.id)
    assert ai.calls == 2


def test_trainer_path_only_reads_what_the_member_made(db_session, member, ai, now):
    _move(db_session, member.id)
    assert svc.week_ai(db_session, member.id, generate=False) is None
    assert ai.calls == 0

    svc.week_ai(db_session, member.id)
    _move(db_session, member.id, "화")  # 다시 만들 것 표시가 붙어도 읽기만 한다
    read = svc.week_ai(db_session, member.id, generate=False)
    assert (read.sentence, read.detail) == (SENTENCE, DETAIL)
    assert ai.calls == 1


# ── 다시 만들기 ──────────────────────────────────────────────────────────


def test_a_new_record_remakes_the_advice(db_session, member, ai, now):
    _move(db_session, member.id)
    svc.week_ai(db_session, member.id)

    _move(db_session, member.id, "화", kind="strength", name="런지")
    now.at += timedelta(minutes=5)
    svc.week_ai(db_session, member.id)

    assert ai.calls == 2
    assert "런지" in ai.users[1]


def test_editing_and_deleting_a_record_remake_the_advice(db_session, member, ai, now):
    from app.models.models import ExerciseSession

    session_id = _move(db_session, member.id)
    _move(db_session, member.id, "화")
    svc.week_ai(db_session, member.id)

    db_session.get(ExerciseSession, session_id).minutes = 60
    db_session.commit()
    svc.week_ai(db_session, member.id)
    assert ai.calls == 2

    db_session.delete(db_session.get(ExerciseSession, session_id))
    db_session.commit()
    svc.week_ai(db_session, member.id)
    assert ai.calls == 3


def test_changing_the_cardio_goal_remakes_but_other_profile_fields_do_not(
    db_session, member, ai, now
):
    from sqlalchemy import select

    from app.models.models import HealthProfile

    _move(db_session, member.id)
    svc.week_ai(db_session, member.id)

    profile = db_session.scalar(select(HealthProfile).where(HealthProfile.user_id == member.id))
    profile.activity_points = 500
    db_session.commit()
    svc.week_ai(db_session, member.id)
    assert ai.calls == 1

    profile.weekly_cardio_minutes = 90
    db_session.commit()
    svc.week_ai(db_session, member.id)
    assert ai.calls == 2


def test_another_members_record_keeps_my_advice(db_session, member, ai, now):
    from app.core.security import hash_password
    from app.models.models import ExerciseSession, User

    _move(db_session, member.id)
    svc.week_ai(db_session, member.id)

    other = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=f"exweek-{uuid.uuid4().hex[:8]}@example.com",
        name="다른 회원", hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(other)
    db_session.commit()
    try:
        _move(db_session, other.id)
        svc.week_ai(db_session, member.id)
        assert ai.calls == 1
    finally:
        db_session.execute(delete(ExerciseSession).where(ExerciseSession.user_id == other.id))
        db_session.execute(delete(User).where(User.id == other.id))
        db_session.commit()


def test_advice_is_remade_at_most_five_times_a_day(db_session, member, ai, now):
    _move(db_session, member.id)
    cap = week_advice_refresh.MAX_GENERATIONS_PER_DAY

    for _ in range(cap + 2):
        svc.week_ai(db_session, member.id)
        _move(db_session, member.id, "화", minutes=10)
        now.at += timedelta(minutes=1)
    assert ai.calls == cap

    # 상한이 차면 마지막 문장을 그대로 둔다.
    kept = svc.week_ai(db_session, member.id)
    assert (kept.sentence, kept.detail) == (SENTENCE, DETAIL)
    assert ai.calls == cap

    # 다음 날에는 다시 열린다.
    now.at += timedelta(days=1)
    svc.week_ai(db_session, member.id)
    assert ai.calls == cap + 1


def test_ai_failure_returns_nothing_and_retries_after_an_hour(db_session, member, now, monkeypatch):
    fake = _FakeAI(fail=True)
    monkeypatch.setattr(svc, "_call_llm", fake)
    _move(db_session, member.id)

    assert svc.week_ai(db_session, member.id) is None
    now.at += timedelta(minutes=59)
    assert svc.week_ai(db_session, member.id) is None
    assert fake.calls == 1

    fake.fail = False
    now.at += timedelta(minutes=2)
    retried = svc.week_ai(db_session, member.id)
    assert (retried.sentence, retried.detail) == (SENTENCE, DETAIL)
    assert fake.calls == 2


def test_a_bad_detail_keeps_the_sentence_and_retries_after_an_hour(
    db_session, member, now, monkeypatch
):
    fake = _FakeAI(answer=_pair(detail="짧아요."))
    monkeypatch.setattr(svc, "_call_llm", fake)
    _move(db_session, member.id)

    first = svc.week_ai(db_session, member.id)
    assert (first.sentence, first.detail) == (SENTENCE, None)
    calls = fake.calls

    fake.answer = _pair()
    now.at += timedelta(minutes=61)
    assert svc.week_ai(db_session, member.id).detail == DETAIL
    assert fake.calls == calls + 1


def test_a_detail_with_measures_is_not_kept(db_session, member, now, monkeypatch):
    """수치는 규칙이 말한다 — 긴 문장에 분·kcal 이 있으면 받지 않는다."""
    fake = _FakeAI(answer=_pair(detail="이번 주는 걷기를 120분 했어요. 남은 날에는 가벼운 근력 운동을 한 번 더해 보세요."))
    monkeypatch.setattr(svc, "_call_llm", fake)
    _move(db_session, member.id)

    assert svc.week_ai(db_session, member.id).detail is None


def test_the_ai_is_not_awaited_while_holding_the_connection(db_session, member, now, monkeypatch):
    """AI 문장을 기다리는 동안 트랜잭션(연결)을 쥐지 않는다(#3242)."""
    seen: list[bool] = []

    def fake(system: str, user: str) -> str:
        seen.append(db_session.in_transaction())
        return _pair()

    monkeypatch.setattr(svc, "_call_llm", fake)
    _move(db_session, member.id)
    svc.week_ai(db_session, member.id)
    assert seen == [False]


# ── 프롬프트 ─────────────────────────────────────────────────────────────


def test_prompt_asks_for_both_lengths_without_measures():
    system, user = svc.build_prompt(
        limit=30, finding="이번 주 2일 운동했고 모두 60분이다.",
        records=["월 유산소: 걷기 30분"], goal="체중 감량",
    )
    assert "30자 이내" in system
    assert "50~95자" in system
    assert "수치를 쓰지 않는다" in system
    assert svc.EXERCISE_NAME_GUARD in system
    assert '{"sentence":"...","detail":"..."}' in system
    assert "[목표] 체중 감량" in user
    assert "- 월 유산소: 걷기 30분" in user


# ── API ──────────────────────────────────────────────────────────────────


def _member_headers(client) -> tuple[str, dict[str, str]]:
    email = f"exweek-api-{uuid.uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "수빈"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def test_exercise_advice_carries_the_ai_sentence_only_for_the_week(
    client, db_session, ai, now
):
    member_id, headers = _member_headers(client)
    _move(db_session, member_id)

    today = client.get("/v1/exercise/advice?period=today", headers=headers).json()
    assert today["ai_sentence"] is None
    assert ai.calls == 0

    week = client.get("/v1/exercise/advice?period=week", headers=headers).json()
    assert week["ai_sentence"] == SENTENCE
    assert week["message"]  # 규칙 문장은 그대로 온다
    assert ai.calls == 1


def test_exercise_advice_without_ai_keeps_the_rule_card(client, db_session, now, monkeypatch):
    monkeypatch.setattr(svc, "_call_llm", _FakeAI(fail=True))
    member_id, headers = _member_headers(client)
    _move(db_session, member_id)

    r = client.get("/v1/exercise/advice?period=week", headers=headers)
    assert r.status_code == 200
    assert r.json()["ai_sentence"] is None
    assert r.json()["message"]


def test_home_sheet_reuses_the_week_detail_without_a_new_call(client, db_session, ai, now):
    """운동 탭이 만든 긴 문장을 홈 코칭 시트가 그대로 잇는다 — AI 호출은 한 번이다."""
    member_id, headers = _member_headers(client)
    _move(db_session, member_id)
    client.get("/v1/exercise/advice?period=week", headers=headers)
    assert ai.calls == 1

    sheet = client.get("/v1/ai-coach/feedback", headers=headers).json()
    card = next(s for s in sheet["suggestions"] if s["tag"] == "exercise")
    assert card["title"] == "조금만 더 움직여봐요"
    assert card["body"] == f"이번 주 유산소 30분 운동했어요. {DETAIL}"
    assert ai.calls == 1
