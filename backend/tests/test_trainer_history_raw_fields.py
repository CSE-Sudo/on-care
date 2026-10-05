"""운동 이력·로스터 라벨의 원시 값(#2300).

서버가 한국어로 조립하던 `(오늘)`·`N일 전`·`3세트`·`PT 세션 · 트레이너 지도` 대신
날짜·수량·종류 코드를 따로 보낸다. 옛 문자열 필드는 옛 앱을 위해 그대로 남고,
헤더가 없으면 **바이트 단위로 예전과 같은 한국어**여야 한다.

앞부분(순수 함수)은 DB 가 필요 없고, 뒷부분(`client` 픽스처)은 실제 API 경로로
같은 계약을 확인한다.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.core import clock
from app.core import locale as locale_module
from app.models.models import ExerciseSession
from app.schemas.trainer_api import ProgramItem, RoutineHistoryExerciseOut, RoutineHistoryOut
from app.services.trainer import _common as trainer_common_service
from app.services.trainer._common import (
    ASSIGNED_HISTORY_FALLBACK_LABEL,
    PT_HISTORY_KIND_LABEL,
    _assigned_exercise_item,
    _assigned_history_out,
    _iso_day_or_none,
    history_date_label,
    history_exercise_line,
    history_kind_code,
    parse_history_exercise,
    relative_day_label,
)
from app.services.trainer.schedule import _program_history_entry

_FIXED_TODAY = date(2026, 9, 27)


@pytest.fixture()
def fixed_today(monkeypatch):
    """'오늘'을 고정한다 — 라벨이 날짜 차이로 갈리므로 실행일에 기대지 않는다."""
    monkeypatch.setattr(trainer_common_service, "_today", lambda: _FIXED_TODAY)
    return _FIXED_TODAY


@pytest.fixture()
def english():
    """이 테스트 동안 요청 언어를 영어로 둔다(미들웨어가 하는 일과 같다)."""
    token = locale_module._request_locale_ctx.set("en")
    yield
    locale_module._request_locale_ctx.reset(token)


def _ago(days: int) -> str:
    return (_FIXED_TODAY - timedelta(days=days)).isoformat()


# ---------------------------------------------------------------------------
# 옛 문자열 필드 — 한국어는 그대로, 영어 요청이면 영어
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("days", "expected"),
    [
        (0, "오늘"),
        (1, "어제"),
        (2, "2일 전"),
        (7, "7일 전"),
        (30, "30일 전"),
        # 미래 날짜(시계 오차)는 오늘로 접는다 — 예전과 같다.
        (-1, "오늘"),
        (-10, "오늘"),
    ],
)
def test_relative_day_label_korean_is_unchanged(fixed_today, days, expected):
    assert relative_day_label(_ago(days)) == expected


@pytest.mark.parametrize(
    ("days", "expected"),
    [
        (0, "Today"),
        (1, "Yesterday"),
        (2, "2 days ago"),
        (15, "15 days ago"),
        (-3, "Today"),
    ],
)
def test_relative_day_label_follows_english_request(
    fixed_today, english, days, expected
):
    assert relative_day_label(_ago(days)) == expected


@pytest.mark.parametrize("raw", ["", "어제", "2026-13-01", "not-a-date"])
def test_relative_day_label_passes_unparseable_values_through(fixed_today, raw):
    assert relative_day_label(raw) == raw


@pytest.mark.parametrize(
    ("day", "expected"),
    [
        ("2026-09-27", "9/27 (오늘)"),
        ("2026-09-26", "9/26 (어제)"),
        ("2026-09-25", "9/25"),
        ("2026-01-05", "1/5"),
        # 미래는 꼬리표 없이 날짜만 — 예전과 같다.
        ("2026-09-28", "9/28"),
    ],
)
def test_history_date_label_korean_is_unchanged(fixed_today, day, expected):
    assert history_date_label(day) == expected


@pytest.mark.parametrize(
    ("day", "expected"),
    [
        ("2026-09-27", "9/27 (Today)"),
        ("2026-09-26", "9/26 (Yesterday)"),
        ("2026-09-20", "9/20"),
    ],
)
def test_history_date_label_follows_english_request(
    fixed_today, english, day, expected
):
    assert history_date_label(day) == expected


def test_history_date_label_passes_unparseable_values_through(fixed_today):
    assert history_date_label("7/12") == "7/12"


# ---------------------------------------------------------------------------
# 새 필드의 재료 — 날짜·종류 코드
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("2026-09-27", "2026-09-27"),
        ("2026-02-29", None),  # 없는 날
        ("7/12", None),
        ("", None),
        (None, None),
    ],
)
def test_iso_day_or_none(raw, expected):
    assert _iso_day_or_none(raw) == expected


@pytest.mark.parametrize(
    ("label", "expected"),
    [
        ("PT 세션 · 트레이너 지도", "pt_session"),
        ("  PT 세션 · 트레이너 지도  ", "pt_session"),
        ("AI 개인운동", "ai_personal"),
        ("AI 루틴 · 자율 운동", "ai_personal"),
        ("배정 루틴 수행", "assigned_routine"),
        # 사람이 지은 이름은 코드가 없다.
        ("하체 루틴 A", None),
        ("PT 세션 · 타트레이너", None),
        ("", None),
        (None, None),
    ],
)
def test_history_kind_code(label, expected):
    assert history_kind_code(label) == expected


def test_stored_kind_labels_are_the_contract_values():
    """DB 에 저장되는 이름이라 바뀌면 옛 행이 코드를 잃는다."""
    assert PT_HISTORY_KIND_LABEL == "PT 세션 · 트레이너 지도"
    assert ASSIGNED_HISTORY_FALLBACK_LABEL == "배정 루틴 수행"


# ---------------------------------------------------------------------------
# 저장된 운동 문장 → 값
# ---------------------------------------------------------------------------


def _item(**kw) -> dict:
    return RoutineHistoryExerciseOut(**kw).model_dump()


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # 완료한 PT 세션이 저장하는 모양(`_program_item_label`)
        (
            "스쿼트 3세트 12회 40kg",
            _item(name="스쿼트", type="strength", sets=3, reps=12, weight=40.0),
        ),
        (
            "플랭크 3세트 60초 0kg",
            _item(name="플랭크", type="strength", sets=3, hold_seconds=60, weight=0.0),
        ),
        ("레그프레스 3세트 80kg", _item(name="레그프레스", type="strength", sets=3, weight=80.0)),
        ("카프레이즈 1세트", _item(name="카프레이즈", type="strength", sets=1)),
        ("사이클 20분", _item(name="사이클", minutes=20)),
        # 시드의 모양 — `·` 로 이어지고 수행 표시가 붙는다
        (
            "스쿼트 3세트 · 12회 · 40kg ✓",
            _item(name="스쿼트", type="strength", sets=3, reps=12, weight=40.0),
        ),
        (
            "벤치프레스 4세트 · 8회 · 62.5kg",
            _item(name="벤치프레스", type="strength", sets=4, reps=8, weight=62.5),
        ),
        ("인터벌 런닝 25분 ✓", _item(name="인터벌 런닝", minutes=25)),
        # 이름에 공백이 있어도 이름으로 남는다
        (
            "인클라인 덤벨 3세트 · 10회 · 26kg",
            _item(name="인클라인 덤벨", type="strength", sets=3, reps=10, weight=26.0),
        ),
        # 옛 순서(중량이 앞)도 받는다
        (
            "레그프레스 70kg · 4세트",
            _item(name="레그프레스", type="strength", sets=4, weight=70.0),
        ),
        # 값이 없는 줄은 적힌 그대로 이름
        ("스쿼트 ✓", _item(name="스쿼트")),
        ("데드리프트 ✗", _item(name="데드리프트", done=False)),
        ("플랭크 ✗ (피로)", _item(name="플랭크 (피로)", done=False)),
        ("레그프레스", _item(name="레그프레스")),
        # 이름 없이 값만 있는 줄은 값으로 읽지 않는다 — 이름이 사라지면 안 된다
        ("3세트", _item(name="3세트")),
        # 숫자가 이름 중간에 있어도 끝에 단위가 없으면 이름이다
        ("5x5 스쿼트", _item(name="5x5 스쿼트")),
        ("", _item(name="")),
    ],
)
def test_parse_history_exercise_lines(raw, expected):
    assert parse_history_exercise(raw).model_dump() == expected


def test_parse_history_exercise_accepts_structured_items():
    parsed = parse_history_exercise(
        {
            "name": "스쿼트",
            "type": "근력",
            "sets": 3,
            "reps": 10,
            "weight": 20,
            "intensity": "high",
            "done": False,
        }
    )
    assert parsed.model_dump() == _item(
        name="스쿼트",
        type="strength",
        sets=3,
        reps=10,
        weight=20.0,
        intensity="high",
        done=False,
    )


@pytest.mark.parametrize(
    ("item", "line", "expected"),
    [
        (
            ProgramItem(name="버피", type="유산소", duration_seconds=45),
            "버피 45초",
            _item(name="버피", type="cardio", minutes=1, duration_seconds=45),
        ),
        (
            ProgramItem(name="사이클", type="유산소", duration_seconds=5415),
            "사이클 1시간 30분 15초",
            _item(name="사이클", type="cardio", minutes=90, duration_seconds=5415),
        ),
        (
            ProgramItem(name="플랭크", type="근력", sets=3, hold_seconds=60, weight=0),
            "플랭크 3세트 60초 0kg",
            _item(name="플랭크", type="strength", sets=3, hold_seconds=60, weight=0.0),
        ),
    ],
)
def test_pt_history_entry_keeps_seconds(item, line, expected):
    """완료한 PT 는 값을 객체로 남긴다 — 운동 시간 `45초` 가 버틴 초로 읽히지 않는다. (#2546)"""
    entry = _program_history_entry(item)
    assert history_exercise_line(entry) == line
    assert parse_history_exercise(entry).model_dump() == expected


def test_history_line_keeps_old_sentences():
    """문장으로 저장된 옛 행은 문장 그대로 싣는다(회귀). (#2546)"""
    assert history_exercise_line("사이클 20분") == "사이클 20분"
    assert history_exercise_line("플랭크 ✗ (피로)") == "플랭크 ✗ (피로)"
    assert history_exercise_line({"name": "스쿼트"}) == "스쿼트"


def test_parse_history_exercise_drops_broken_structured_values():
    parsed = parse_history_exercise(
        {"name": None, "sets": "3", "reps": True, "minutes": "20", "type": ""}
    )
    assert parsed.model_dump() == _item(name="")


def test_parse_history_exercise_tolerates_non_strings():
    assert parse_history_exercise(None).name == ""
    assert parse_history_exercise(42).name == "42"


# ---------------------------------------------------------------------------
# 배정 수행 이력 — 문장은 그대로, 값은 따로
# ---------------------------------------------------------------------------


def _assigned_row(**over) -> ExerciseSession:
    base = dict(
        id=f"ex-{uuid4().hex[:8]}",
        user_id="user-x",
        week_start="2026-09-21",
        day_label="금",
        type="근력",
        minutes=30,
        sets=3,
        reps=12,
        hold_seconds=None,
        weight=40.0,
        intensity="moderate",
        source="assigned_routine",
        assigned_routine_id="rt-1",
        assigned_routine_name="하체 루틴",
        completed_at=datetime(2026, 9, 25, 10, tzinfo=timezone.utc),
        created_at=datetime(2026, 9, 25, 10, tzinfo=timezone.utc),
    )
    base.update(over)
    return ExerciseSession(**base)


def test_assigned_history_korean_strings_are_byte_identical(fixed_today):
    out = _assigned_history_out(_assigned_row())
    assert out.date_label == "9/25"
    assert out.label == "하체 루틴"
    assert out.exercises == ["하체 루틴 · 3세트 · 12회 · 40kg · moderate"]
    # 새 필드
    assert out.date == "2026-09-25"
    assert out.kind is None  # 트레이너가 지은 이름
    assert [e.model_dump() for e in out.exercise_items] == [
        _item(
            name="하체 루틴",
            type="strength",
            sets=3,
            reps=12,
            weight=40.0,
            intensity="moderate",
        )
    ]


def test_assigned_history_without_name_gets_kind_code(fixed_today):
    out = _assigned_history_out(
        _assigned_row(assigned_routine_name=None, type="유산소", sets=None,
                      reps=None, weight=None, minutes=25, intensity="light")
    )
    assert out.label == "배정 루틴 수행"
    assert out.kind == "assigned_routine"
    assert out.exercises == ["유산소 · 25분 · light"]
    assert out.exercise_items[0].model_dump() == _item(
        name="유산소", type="cardio", minutes=25, intensity="light"
    )


@pytest.mark.parametrize(
    ("minutes", "seconds", "amount"),
    [(1, 45, "45초"), (90, 5415, "1시간 30분 15초"), (25, None, "25분")],
)
def test_assigned_history_sentence_keeps_seconds(fixed_today, minutes, seconds, amount):
    """문장도 초까지 적는다 — `45초` 가 `1분` 으로 읽히지 않는다(#2546)."""
    out = _assigned_history_out(
        _assigned_row(assigned_routine_name="줄넘기", type="유산소", sets=None,
                      reps=None, weight=None, minutes=minutes,
                      duration_seconds=seconds)
    )
    assert out.exercises == [f"줄넘기 · {amount} · moderate"]
    assert out.exercise_items[0].duration_seconds == seconds
    assert out.exercise_items[0].minutes == minutes


def test_assigned_history_date_matches_label_day(fixed_today):
    """`date` 와 `date_label` 은 같은 날을 말한다 — 논리 운동일(#1264)."""
    out = _assigned_history_out(
        _assigned_row(
            week_start="2026-09-21",
            day_label="토",
            completed_at=datetime(2026, 9, 27, 1, tzinfo=timezone.utc),
        )
    )
    assert out.date == "2026-09-26"
    assert out.date_label == "9/26 (어제)"


@pytest.mark.parametrize(
    ("over", "expected"),
    [
        # 버티는 근력 — 회 대신 초
        (
            dict(hold_seconds=45, reps=None, weight=0.0),
            _item(name="하체 루틴", type="strength", sets=3, hold_seconds=45,
                  weight=0.0, intensity="moderate"),
        ),
        # 초와 회가 함께 있으면 초 — 문장과 같은 규칙
        (
            dict(hold_seconds=30, reps=10, weight=None),
            _item(name="하체 루틴", type="strength", sets=3, hold_seconds=30,
                  intensity="moderate"),
        ),
        # 세트가 없던 옛 근력 배정은 분으로
        (
            dict(sets=None, reps=None, weight=None, minutes=20),
            _item(name="하체 루틴", type="strength", minutes=20, intensity="moderate"),
        ),
        # 영문 코드로 적힌 유형도 같게
        (
            dict(type="strength"),
            _item(name="하체 루틴", type="strength", sets=3, reps=12, weight=40.0,
                  intensity="moderate"),
        ),
        # 스트레칭은 시간
        (
            dict(type="스트레칭", sets=None, reps=None, weight=None, minutes=15),
            _item(name="하체 루틴", type="stretching", minutes=15, intensity="moderate"),
        ),
        # 초를 남긴 유산소 수행은 초도 싣는다 — 분은 반올림한 값(#2221)
        (
            dict(type="유산소", sets=None, reps=None, weight=None, minutes=1,
                 duration_seconds=45),
            _item(name="하체 루틴", type="cardio", minutes=1, duration_seconds=45,
                  intensity="moderate"),
        ),
        # 근력은 세트로 재므로 초를 싣지 않는다
        (
            dict(duration_seconds=1800),
            _item(name="하체 루틴", type="strength", sets=3, reps=12, weight=40.0,
                  intensity="moderate"),
        ),
        # 강도가 비어 있으면 없음
        (
            dict(intensity=""),
            _item(name="하체 루틴", type="strength", sets=3, reps=12, weight=40.0),
        ),
    ],
)
def test_assigned_exercise_item_shapes(over, expected):
    assert _assigned_exercise_item(_assigned_row(**over)).model_dump() == expected


def test_history_out_new_fields_default_for_old_constructors():
    """새 필드는 선택이다 — 옛 방식으로 만든 응답도 검증을 통과한다."""
    out = RoutineHistoryOut(
        date_label="7/12",
        label="x",
        completion_rate=0,
        exercises=[],
        client_feedback="",
        trainer_note="",
    )
    assert out.date is None
    assert out.kind is None
    assert out.exercise_items == []


# ---------------------------------------------------------------------------
# API 경로 (DB 필요)
# ---------------------------------------------------------------------------


def _trainer_headers(client, **extra) -> dict:
    token = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}", **extra}


def _label_day(entry: dict) -> str:
    """`date_label` 의 `M/D` 부분."""
    return entry["date_label"].split(" ", 1)[0]


def test_history_api_carries_raw_fields_alongside_korean_labels(client):
    headers = _trainer_headers(client)
    r = client.get("/v1/trainer/clients/user-jisu/history", headers=headers)
    assert r.status_code == 200, r.text
    hist = r.json()
    assert hist
    today = clock.today()
    for entry in hist:
        # 원시 날짜가 옛 라벨과 같은 날이다
        assert entry["date"] is not None
        day = date.fromisoformat(entry["date"])
        assert _label_day(entry) == f"{day.month}/{day.day}"
        if day == today:
            assert entry["date_label"].endswith(" (오늘)")
        elif day == today - timedelta(days=1):
            assert entry["date_label"].endswith(" (어제)")
        # 운동 값은 문장과 같은 개수·같은 순서
        assert len(entry["exercise_items"]) == len(entry["exercises"])
        for sentence, item in zip(entry["exercises"], entry["exercise_items"]):
            assert item["name"]
            assert item["name"].split(" ")[0] in sentence
        # 한국어 옛 필드에는 영어가 섞이지 않는다
        assert "Today" not in entry["date_label"]
        assert "Yesterday" not in entry["date_label"]
    # 시드의 하루치 개인운동 카드는 코드를 받는다(#3003)
    assert any(
        e["label"] == "개인운동" and e["kind"] == "personal_routine" for e in hist
    )


def test_history_api_english_request_localizes_only_date_label(client):
    ko = client.get(
        "/v1/trainer/clients/user-jisu/history", headers=_trainer_headers(client)
    ).json()
    en = client.get(
        "/v1/trainer/clients/user-jisu/history",
        headers=_trainer_headers(client, **{"Accept-Language": "en-US,en;q=0.9"}),
    ).json()
    assert [e["id"] for e in en] == [e["id"] for e in ko]
    for k, e in zip(ko, en):
        # 원시 값은 언어와 무관하다
        assert e["date"] == k["date"]
        assert e["kind"] == k["kind"]
        assert e["exercise_items"] == k["exercise_items"]
        # 저장된 이름·문장은 번역하지 않는다(앱이 코드로 그린다)
        assert e["label"] == k["label"]
        assert e["exercises"] == k["exercises"]
        # 날짜 꼬리표만 요청 언어를 따른다
        assert e["date_label"] == (
            k["date_label"]
            .replace(" (오늘)", " (Today)")
            .replace(" (어제)", " (Yesterday)")
        )
        assert "오늘" not in e["date_label"] and "어제" not in e["date_label"]


def test_history_api_is_trainer_only(client):
    email = f"member-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    r = client.get(
        "/v1/trainer/clients/user-jisu/history",
        headers={"Authorization": f"Bearer {token}", "Accept-Language": "en"},
    )
    assert r.status_code == 403


def test_history_api_unassigned_client_is_not_found(client):
    r = client.get(
        "/v1/trainer/clients/user-nobody/history",
        headers=_trainer_headers(client, **{"Accept-Language": "en"}),
    )
    assert r.status_code in (403, 404)


def test_roster_carries_last_routine_date(client):
    ko = client.get("/v1/trainer/clients", headers=_trainer_headers(client))
    assert ko.status_code == 200, ko.text
    en = client.get(
        "/v1/trainer/clients",
        headers=_trainer_headers(client, **{"Accept-Language": "en"}),
    ).json()
    en_by_id = {c["id"]: c for c in en}
    today = clock.today()
    saw_date = False
    for c in ko.json():
        raw = c["last_routine_date"]
        other = en_by_id[c["id"]]
        assert other["last_routine_date"] == raw
        if raw is None:
            # 보낸 루틴이 없으면 예전처럼 `-`
            assert c["last_routine"] == "-"
            assert other["last_routine"] == "-"
            continue
        saw_date = True
        delta = (today - date.fromisoformat(raw)).days
        if delta <= 0:
            assert (c["last_routine"], other["last_routine"]) == ("오늘", "Today")
        elif delta == 1:
            assert (c["last_routine"], other["last_routine"]) == ("어제", "Yesterday")
        else:
            assert c["last_routine"] == f"{delta}일 전"
            assert other["last_routine"] == f"{delta} days ago"
    assert saw_date, "시드 로스터에 루틴을 받은 회원이 하나도 없다"


@pytest.fixture()
def pt_session(client):
    """오늘 PT 세션 하나를 만들고 끝에 지운다(파생 이력도 함께 사라진다)."""
    created: list[tuple[str, dict]] = []

    def _make(headers: dict, program: list[dict]) -> str:
        body = {
            "date": clock.today().isoformat(), "time": "21:10",
            "client_name": "이지수", "member_id": "user-jisu",
            "type": "1:1 PT", "duration_minutes": 50, "program": program,
        }
        r = client.post("/v1/trainer/schedule", json=body, headers=headers)
        assert r.status_code == 201, r.text
        sid = r.json()["id"]
        created.append((sid, headers))
        return sid

    yield _make

    for sid, headers in created:
        client.delete(f"/v1/trainer/schedule/{sid}", headers=headers)


def test_completed_pt_session_history_has_code_and_values(client, pt_session):
    headers = _trainer_headers(client)
    sid = pt_session(
        headers,
        [
            {"name": "스쿼트", "type": "근력", "sets": 3, "reps": 12, "weight": 40.0},
            {"name": "플랭크", "type": "근력", "sets": 3, "hold_seconds": 60, "weight": 0},
            {"name": "사이클", "type": "유산소", "duration": 20},
            {"name": "버피", "type": "유산소", "duration_seconds": 45},
        ],
    )
    done = client.post(
        f"/v1/trainer/schedule/{sid}/complete", json={"note": ""}, headers=headers
    )
    assert done.status_code == 200, done.text

    hist = client.get(
        "/v1/trainer/clients/user-jisu/history",
        headers={**headers, "Accept-Language": "en"},
    ).json()
    entry = next(e for e in hist if e["id"] == f"sched-hist-{sid}")
    # 저장된 이름·문장은 그대로(한국어), 코드와 값이 따로 온다
    assert entry["label"] == "PT 세션 · 트레이너 지도"
    assert entry["kind"] == "pt_session"
    assert entry["exercises"] == [
        "스쿼트 3세트 12회 40kg",
        "플랭크 3세트 60초 0kg",
        "사이클 20분",
        "버피 45초",
    ]
    assert entry["date"] == clock.today().isoformat()
    assert entry["date_label"].endswith(" (Today)")
    items = [
        {k: v for k, v in item.items() if v not in (None, 0, "", True)}
        for item in entry["exercise_items"]
    ]
    assert items == [
        {"name": "스쿼트", "type": "strength", "sets": 3, "reps": 12, "weight": 40.0},
        {"name": "플랭크", "type": "strength", "sets": 3, "hold_seconds": 60},
        # 운동 시간은 초까지 값으로 남는다(#2546)
        {"name": "사이클", "type": "cardio", "minutes": 20, "duration_seconds": 1200},
        # `minutes: 1` 은 위 거르기에서 `True` 와 같다고 빠진다 — 아래에서 따로 본다
        {"name": "버피", "type": "cardio", "duration_seconds": 45},
    ]
    assert entry["exercise_items"][3]["minutes"] == 1
    # 맨몸 운동의 0kg 도 값으로 남는다(0 과 '적지 않음'은 다르다) — 화면은
    # 0 을 적지 않지만 저장 문장에는 남아야 값이 되짚힌다(#2533)
    assert entry["exercise_items"][1]["weight"] == 0.0
