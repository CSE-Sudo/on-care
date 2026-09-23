"""회원 목록 PT 관리 신호의 기준. (#2203) DB 필요.

기준 시각을 목요일 정오로 고정한다 — 운동 목표 미달은 월·화에 판단하지 않고, 칼로리·
배정 루틴은 어제까지 최근 3일을 보므로 요일이 흔들리면 같은 데이터가 다른 답을 낸다.
회원마다 새 트레이너·새 회원을 만들어 시드 데이터와 섞이지 않게 한다.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta
from uuid import uuid4

import pytest

from app.core import clock

TODAY = date(2026, 9, 24)  # 목요일
NOW = datetime(2026, 9, 24, 12, 0, tzinfo=clock.SEOUL)
MONDAY = TODAY - timedelta(days=TODAY.weekday())
WEEKDAYS = ["월", "화", "수", "목", "금", "토", "일"]


@pytest.fixture(autouse=True)
def _frozen_clock(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: NOW)
    monkeypatch.setattr(clock, "today", lambda: TODAY)


def _day(offset: int) -> date:
    return TODAY - timedelta(days=offset)


def _dt(day: date, hour: int = 12) -> datetime:
    return datetime(day.year, day.month, day.day, hour, tzinfo=clock.SEOUL)


class World:
    """트레이너 한 명과 그 회원들. 커밋하지 않고 테스트가 끝나면 롤백한다."""

    def __init__(self, db):
        from app.models.models import User

        self.db = db
        self.rows: list = []
        self.trainer_id = f"sig-trainer-{uuid4().hex[:8]}"
        self._add(User(
            id=self.trainer_id,
            email=f"{self.trainer_id}@test.local",
            name="신호 트레이너",
            role="trainer",
        ))
        self.links: list = []
        self._conversations: dict = {}

    def _add(self, row):
        self.db.add(row)
        self.db.flush()
        self.rows.append(row)
        return row

    def member(
        self,
        *,
        linked_days_ago: int = 20,
        dormant: bool = False,
        conditions: str = "",
        daily_calories: int | None = 2000,
        daily_protein_g: int | None = None,
        cardio: int | None = None,
        strength: int | None = None,
        stretching: int | None = None,
    ) -> str:
        from app.models.models import HealthProfile, TrainerClient, User

        member_id = f"sig-member-{uuid4().hex[:8]}"
        self._add(User(id=member_id, email=f"{member_id}@test.local", name="회원"))
        self._add(HealthProfile(
            user_id=member_id,
            conditions=conditions,
            daily_calories=daily_calories,
            daily_protein_g=daily_protein_g,
            weekly_cardio_minutes=cardio,
            weekly_strength_sets=strength,
            weekly_flexibility_minutes=stretching,
        ))
        link = self._add(TrainerClient(
            id=f"sig-link-{uuid4().hex[:8]}",
            trainer_id=self.trainer_id,
            member_id=member_id,
            active=True,
            dormant=dormant,
            created_at=_dt(_day(linked_days_ago)),
        ))
        self.links.append(link)
        return member_id

    def meal(self, member_id: str, day: date, kcal: int, protein: float = 0.0):
        from app.models.models import DietEntry

        self._add(DietEntry(
            id=f"sig-diet-{uuid4().hex[:8]}",
            user_id=member_id,
            date=day.isoformat(),
            meal_type="lunch",
            total_calories=kcal,
            protein_g=protein,
        ))

    def workout(
        self,
        member_id: str,
        day: date,
        type_: str = "cardio",
        minutes: int = 30,
        sets: int | None = None,
        routine_id: str | None = None,
    ):
        from app.models.models import ExerciseSession

        monday = day - timedelta(days=day.weekday())
        self._add(ExerciseSession(
            id=f"sig-ex-{uuid4().hex[:8]}",
            user_id=member_id,
            week_start=monday.isoformat(),
            day_label=WEEKDAYS[day.weekday()],
            type=type_,
            minutes=minutes,
            sets=sets,
            assigned_routine_id=routine_id,
        ))

    def routine(self, member_id: str, active_from: date) -> str:
        from app.models.models import TrainerRoutine

        routine_id = f"sig-rt-{uuid4().hex[:8]}"
        self._add(TrainerRoutine(
            id=routine_id,
            trainer_id=self.trainer_id,
            member_id=member_id,
            name="스쿼트",
            type="strength",
            status="approved",
            active_from=active_from.isoformat(),
        ))
        return routine_id

    def chat(self, member_id: str, body: str, *, days_ago: int = 1, sender: str = "member"):
        from app.models.models import ChatMessage

        self._add(ChatMessage(
            id=f"sig-chat-{uuid4().hex[:8]}",
            trainer_id=self.trainer_id,
            member_id=member_id,
            sender=sender,
            body=body,
            created_at=_dt(_day(days_ago)),
        ))

    def ai_chat(self, member_id: str, body: str, *, dismissed: bool = False):
        from app.models.models import AiConversation, AiMessage

        # 회원당 진행 중인 대화는 하나다(`uq_ai_conversations_active_member`).
        conv = self._conversations.get(member_id)
        if conv is None:
            conv = self._add(AiConversation(id=f"sig-conv-{uuid4().hex[:8]}", user_id=member_id))
            self._conversations[member_id] = conv
        self._add(AiMessage(
            id=f"sig-ai-{uuid4().hex[:8]}",
            conversation_id=conv.id,
            seq=sum(1 for r in self.rows if isinstance(r, AiMessage) and r.conversation_id == conv.id),
            role="user",
            content=body,
            insight_dismissed=dismissed,
            created_at=_dt(_day(1)),
        ))

    def session(self, member_id: str, day: date, status: str, source: str = ""):
        from app.models.models import TrainerSchedule

        self._add(TrainerSchedule(
            id=f"sig-sch-{uuid4().hex[:8]}",
            trainer_id=self.trainer_id,
            member_id=member_id,
            date=day.isoformat(),
            time="10:00",
            client_name="회원",
            type="1:1 PT",
            status=status,
            cancellation_source=source,
        ))

    def keep_active(self, member_id: str):
        """기록 끊김이 끼어들지 않게 어제 기록을 하나 남긴다(칼로리는 목표 안)."""
        self.meal(member_id, _day(1), 2000, 120)

    def signals(self) -> dict[str, list]:
        from app.services import client_signals

        return client_signals.build_signals(self.db, self.trainer_id, self.links)

    def kinds(self, member_id: str) -> list[str]:
        return [s.kind for s in self.signals()[member_id]]

    def cleanup(self):
        self.db.rollback()


@pytest.fixture()
def world(db_session):
    w = World(db_session)
    yield w
    w.cleanup()


def _enough_exercise(world: World, member_id: str):
    """이번 주 경과일 비례 목표를 채우는 운동 — 운동 목표 미달이 끼어들지 않게."""
    for offset in range(1, 4):
        day = _day(offset)
        world.workout(member_id, day, "cardio", 30)
        world.workout(member_id, day, "strength", 20, sets=4)
        world.workout(member_id, day, "stretching", 15)


# ---- 공용 기준 ----


def test_report_summary_uses_the_same_calorie_tolerance():
    from app.services import client_signals, trainer_report_summary_service

    assert trainer_report_summary_service.CALORIE_TOLERANCE == client_signals.CALORIE_TOLERANCE
    assert client_signals.CALORIE_TOLERANCE == 0.15


def test_schedule_status_literals_match_the_schedule_contract():
    from app.services import client_signals, trainer_service

    assert client_signals._SCHEDULE_NO_SHOW == trainer_service.SCHEDULE_NO_SHOW
    assert client_signals._SCHEDULE_CANCELLED == trainer_service.SCHEDULE_CANCELLED


def test_calorie_off_target_is_symmetric():
    from app.services.client_signals import calorie_off_target

    assert calorie_off_target(2310, 2000)
    assert calorie_off_target(1690, 2000)
    assert not calorie_off_target(2300, 2000)
    assert not calorie_off_target(1700, 2000)


# ---- 신호별 ----


def test_healthy_member_has_no_signals(world):
    m = world.member()
    _enough_exercise(world, m)
    for offset in range(1, 4):
        world.meal(m, _day(offset), 2000, 120)
    assert world.kinds(m) == []


def test_record_gap_counts_days_since_last_record(world):
    m = world.member()
    world.meal(m, _day(4), 1800)
    signals = world.signals()[m]
    assert [s.kind for s in signals] == ["record_gap"]
    assert signals[0].days == 4


def test_record_gap_not_raised_two_days_after_last_record(world):
    m = world.member()
    _enough_exercise(world, m)
    world.meal(m, _day(2), 2000)
    world.meal(m, _day(3), 2000)
    assert "record_gap" not in world.kinds(m)


def test_record_gap_counts_from_link_start_when_never_recorded(world):
    m = world.member(linked_days_ago=5)
    signals = world.signals()[m]
    assert signals[0].kind == "record_gap"
    assert signals[0].days == 5


def test_record_gap_stops_at_lookback(world):
    m = world.member(linked_days_ago=90)
    assert world.signals()[m][0].days == 30


def test_record_gap_hides_record_derived_signals(world):
    """기록이 없으면 운동 미달·배정 루틴 미수행도 뜨는 셈이지만, 원인은 하나다."""
    m = world.member()
    world.routine(m, _day(10))
    assert world.kinds(m) == ["record_gap"]


def test_new_link_only_reports_discomfort(world):
    m = world.member(linked_days_ago=1)
    world.chat(m, "어제 운동하고 무릎이 아파요")
    assert world.kinds(m) == ["discomfort"]


def test_discomfort_from_trainer_chat(world):
    m = world.member()
    world.keep_active(m)
    _enough_exercise(world, m)
    world.chat(m, "허리가 좀 아파요")
    assert world.kinds(m)[0] == "discomfort"


def test_discomfort_ignores_old_and_trainer_messages(world):
    m = world.member()
    world.keep_active(m)
    _enough_exercise(world, m)
    world.chat(m, "무릎이 아파요", days_ago=8)
    world.chat(m, "무릎 아프면 말해 주세요", sender="trainer")
    assert "discomfort" not in world.kinds(m)


def test_discomfort_from_ai_chatbot_skips_dismissed(world):
    m = world.member()
    world.keep_active(m)
    _enough_exercise(world, m)
    world.ai_chat(m, "목요일에 목이 아파요", dismissed=True)
    assert "discomfort" not in world.kinds(m)
    world.ai_chat(m, "발목이 아파요")
    assert "discomfort" in world.kinds(m)


def test_emote_message_is_not_read(world):
    """이모티콘은 본문이 비어 있다 — 글만 본다."""
    m = world.member()
    world.keep_active(m)
    _enough_exercise(world, m)
    world.chat(m, "")
    assert "discomfort" not in world.kinds(m)


def test_no_show_counts_member_cancellations_only(world):
    m = world.member()
    world.keep_active(m)
    _enough_exercise(world, m)
    world.session(m, _day(5), "노쇼")
    world.session(m, _day(9), "취소", source="trainer")
    assert "no_show" not in world.kinds(m)

    world.session(m, _day(12), "취소", source="member")
    signals = {s.kind: s for s in world.signals()[m]}
    assert signals["no_show"].count == 2


def test_no_show_ignores_sessions_older_than_window(world):
    m = world.member(linked_days_ago=60)
    world.keep_active(m)
    _enough_exercise(world, m)
    world.session(m, _day(31), "노쇼")
    world.session(m, _day(40), "노쇼")
    assert "no_show" not in world.kinds(m)


def test_routine_missed_when_assigned_routine_not_done(world):
    m = world.member()
    world.keep_active(m)
    _enough_exercise(world, m)
    world.routine(m, _day(10))
    signals = {s.kind: s for s in world.signals()[m]}
    assert signals["routine_missed"].days == 3


def test_routine_done_once_clears_missed(world):
    m = world.member()
    world.keep_active(m)
    _enough_exercise(world, m)
    rid = world.routine(m, _day(10))
    world.workout(m, _day(2), "strength", 20, sets=3, routine_id=rid)
    assert "routine_missed" not in world.kinds(m)


def test_routine_assigned_yesterday_is_not_missed_yet(world):
    m = world.member()
    world.keep_active(m)
    _enough_exercise(world, m)
    world.routine(m, _day(1))
    assert "routine_missed" not in world.kinds(m)


def test_exercise_goal_low_uses_elapsed_days(world):
    """목요일이면 목표의 4/7 만 기대한다. 유형마다 100% 에서 자른다."""
    m = world.member(cardio=140, strength=28, stretching=70)
    world.keep_active(m)
    # 유산소 80분(기대 80분 → 100%), 근력·스트레칭 0 → 평균 33%.
    world.workout(m, _day(1), "cardio", 80)
    signals = {s.kind: s for s in world.signals()[m]}
    assert signals["exercise_goal_low"].percent == 33


def test_exercise_goal_met_on_pace(world):
    m = world.member(cardio=140, strength=28, stretching=70)
    world.keep_active(m)
    world.workout(m, _day(1), "cardio", 40)  # 50%
    world.workout(m, _day(1), "strength", 30, sets=8)  # 50%
    world.workout(m, _day(1), "stretching", 20)  # 50%
    assert "exercise_goal_low" not in world.kinds(m)


def test_exercise_goal_not_judged_on_tuesday(world, monkeypatch):
    tuesday = MONDAY + timedelta(days=1)
    monkeypatch.setattr(clock, "today", lambda: tuesday)
    monkeypatch.setattr(clock, "now", lambda: _dt(tuesday))
    m = world.member()
    world.meal(m, tuesday - timedelta(days=1), 2000)
    assert "exercise_goal_low" not in world.kinds(m)


def test_calorie_off_over_and_under(world):
    over = world.member(daily_calories=2000)
    under = world.member(daily_calories=2000)
    for member_id in (over, under):
        _enough_exercise(world, member_id)
    world.meal(over, _day(1), 2400)
    world.meal(over, _day(2), 2400)
    world.meal(under, _day(1), 1500)
    world.meal(under, _day(3), 1500)
    signals = world.signals()
    got_over = {s.kind: s for s in signals[over]}["calorie_off"]
    got_under = {s.kind: s for s in signals[under]}["calorie_off"]
    assert (got_over.direction, got_over.percent) == ("over", 20)
    assert (got_under.direction, got_under.percent) == ("under", 25)


def test_calorie_off_ignores_today_and_single_day(world):
    m = world.member(daily_calories=2000)
    _enough_exercise(world, m)
    world.meal(m, TODAY, 500)
    world.meal(m, _day(1), 3000)
    assert "calorie_off" not in world.kinds(m)


def test_calorie_off_uses_default_target_without_profile_goal(world):
    m = world.member(daily_calories=None)
    _enough_exercise(world, m)
    world.meal(m, _day(1), 2400)
    world.meal(m, _day(2), 2400)
    assert "calorie_off" in world.kinds(m)


def test_protein_low_only_for_strength_or_weight_loss(world):
    strength = world.member(conditions="근력 향상", daily_protein_g=120)
    posture = world.member(conditions="자세 교정", daily_protein_g=120)
    for member_id in (strength, posture):
        _enough_exercise(world, member_id)
        world.meal(member_id, _day(1), 2000, 60)
        world.meal(member_id, _day(2), 2000, 70)
    signals = world.signals()
    got = {s.kind: s for s in signals[strength]}["protein_low"]
    assert got.percent == 54
    assert "protein_low" not in [s.kind for s in signals[posture]]


def test_protein_low_needs_personal_target(world):
    m = world.member(conditions="체중 감량", daily_protein_g=None)
    _enough_exercise(world, m)
    world.meal(m, _day(1), 2000, 10)
    world.meal(m, _day(2), 2000, 10)
    assert "protein_low" not in world.kinds(m)


def test_dormant_member_has_no_signals(world):
    m = world.member(dormant=True)
    assert world.signals()[m] == []


def test_signals_are_ordered_by_urgency(world):
    m = world.member(conditions="근력 향상", daily_protein_g=120)
    world.chat(m, "어깨가 아파요")
    world.session(m, _day(3), "노쇼")
    world.session(m, _day(6), "노쇼")
    world.meal(m, _day(1), 2600, 20)
    world.meal(m, _day(2), 2600, 20)
    assert world.kinds(m) == [
        "discomfort",
        "no_show",
        "exercise_goal_low",
        "calorie_off",
        "protein_low",
    ]


def test_roster_response_carries_signals(client):
    token = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    rows = client.get(
        "/v1/trainer/clients", headers={"Authorization": f"Bearer {token}"}
    ).json()
    assert rows and all(isinstance(r["signals"], list) for r in rows)
    for r in rows:
        if r["active"] is False:
            assert r["signals"] == []
