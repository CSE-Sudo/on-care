"""주간 리포트 요약·초안 문장 (#2298, #3404).

요약 카드(`trainer_report_summary_service`)와 리포트 본문 초안(`report_message`)은
한국어 문장만 만든다. 서버는 `Accept-Language` 를 읽지 않는다.

- 아래 고정값은 문장을 글자 그대로 옮겨 둔 것이다 — 달라졌다면 회귀다.
- `en` 을 보낸 요청도 헤더 없는 요청과 같은 문장·같은 지시문을 받는다.
"""

from __future__ import annotations

import json
import re
from types import SimpleNamespace

import pytest

from app.schemas.trainer_api import WeeklyReportDayOut, WeeklyReportOut
from app.services import trainer_report_summary_service as svc
from app.services.trainer import reports as trainer_reports_service

_HANGUL = re.compile(r"[가-힣]")


def _report(**over) -> WeeklyReportOut:
    base = dict(
        member_id="m", member_name="김민수",
        week_start="2026-08-10", week_end="2026-08-16",
        sessions_booked=1, sessions_done=1,
        completion_avg=87, sodium_over_days=4, sodium_avg=2288,
        calories_week=[1710, 1830, 1560, 1900, 1680, 1067, 0],
        days=[WeeklyReportDayOut(completion=67, exercises=["풀업 3세트 ✗"])],
        message="",
    )
    base.update(over)
    return WeeklyReportOut(**base)


CASES: dict[str, dict] = {
    "default": {},
    "empty": dict(
        completion_avg=None, sodium_avg=None, sodium_over_days=0,
        sessions_booked=0, sessions_done=0, calories_week=[], days=[],
    ),
    "steady": dict(
        completion_avg=90, sodium_avg=1500, sodium_over_days=0,
        calories_week=[2000, 1950, 2050, 0, 0, 0, 0], days=[],
    ),
    "watch_only": dict(
        completion_avg=40, sodium_avg=None, sodium_over_days=0,
        calories_week=[], days=[],
    ),
    "good_sodium_over1": dict(
        completion_avg=50, sodium_avg=1800, sodium_over_days=1,
        calories_week=[], days=[],
    ),
    "many": dict(
        completion_avg=55, sodium_avg=2600, sodium_over_days=5,
        sugar_week=[80, 90, 70, 60, 0, 0, 0],
        calories_week=[2600, 2700, 2500, 0, 0, 0, 0],
        carbs_target=200, carbs_week=[320, 300, 0, 0, 0, 0, 0],
        protein_target=120, protein_week=[50, 60, 0, 0, 0, 0, 0],
        fat_target=60, fat_week=[55, 60, 0, 0, 0, 0, 0],
        sugar_target=40, calorie_target=2100, sodium_target=2300,
        days=[
            WeeklyReportDayOut(
                completion=0,
                exercises=[
                    "스쿼트 4세트 · 10회 · 40kg ✗", "런지 10분 ✗", "플랭크 30초 ✗", "버피 ✗",
                ],
            )
        ],
    ),
    "cal_under": dict(
        completion_avg=None, sodium_avg=None, sodium_over_days=0,
        calories_week=[1200, 1300, 0, 0, 0, 0, 0], days=[],
    ),
    "sugar_avg": dict(
        completion_avg=80, sodium_avg=1500, sodium_over_days=0,
        sugar_week=[60, 55, 0, 0, 0, 0, 0], calories_week=[], days=[],
    ),
    "sodium_avg_over": dict(
        completion_avg=None, sodium_avg=2400, sodium_over_days=0,
        calories_week=[], days=[],
    ),
}


# 고정한 출력(#3116 에서 `완료율`·`회원`·`프로그램` 으로 용어만 맞춤). **고치지 말 것** — 달라졌다면 문장 회귀다.
KO_GOLDEN: dict[str, dict] = {'default': {'evidence': ['나트륨 평균 2,288mg · 기본 목표 2,000mg 초과 4일',
                          '칼로리 평균 1,624kcal · 기본 목표 2,000kcal 대비 부족 19%',
                          '건너뛴 운동: 풀업',
                          '운동 완료율 평균 87%'],
             'headline': '김민수 회원은 운동 완료율 87%로 잘 지켰고, 다음 주는 나트륨 목표 초과 4일을 함께 챙기면 좋겠습니다. '
                         '그 밖에 2가지도 함께 보세요.',
             'points': ['나트륨 평균 2,288mg · 기본 목표 2,000mg 초과 4일',
                        '칼로리 평균 1,624kcal · 기본 목표 2,000kcal 대비 부족 19%',
                        '외 2건 — 리포트 본문에서 확인'],
             'topics': ['나트륨 목표 초과 4일', '칼로리 부족', '건너뛴 운동 1가지'],
             'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                        '\n'
                        '운동은 평균 87%로 잘 따라오셨어요. 다만 풀업은 건너뛰셨더라고요. 컨디션 때문이었다면 다음 PT 때 말씀해 '
                        '주세요. 대체 운동으로 바꿔 둘게요.\n'
                        '\n'
                        '나트륨은 하루 평균 2,288mg이었고, 목표(2,000mg)를 넘긴 날이 4일이었어요. 국물을 절반만 '
                        '남기셔도 하루 400~500mg은 줄어듭니다. 칼로리는 하루 평균 1,624kcal이에요.\n'
                        '\n'
                        '다음 주에는 이 부분만 같이 신경 써 봐요. 프로그램은 제가 조정해서 올려둘게요.'},
 'empty': {'evidence': [],
           'headline': '김민수 회원은 그 주 기록이 없어 다음 주 시작을 함께 잡아 주세요.',
           'points': [],
           'topics': [],
           'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                      '\n'
                      '이 주에는 남은 기록이 없어서 정리해 드릴 내용이 없네요. 다음 주 시작을 같이 잡아 봐요.'},
 'steady': {'evidence': ['운동 완료율 평균 90%',
                         '나트륨 평균 1,500mg · 기본 목표 2,000mg 초과 0일',
                         '칼로리 평균 2,000kcal'],
            'headline': '김민수 회원은 기록이 목표 범위 안에 있어 지금 강도를 유지해도 좋습니다.',
            'points': ['운동 완료율 평균 90%',
                       '나트륨 평균 1,500mg · 기본 목표 2,000mg 초과 0일',
                       '칼로리 평균 2,000kcal'],
            'topics': [],
            'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                       '\n'
                       '운동은 평균 90%로 잘 따라오셨어요.\n'
                       '\n'
                       '나트륨은 하루 평균 1,500mg으로 목표(2,000mg) 안에서 잘 지키고 계세요. 칼로리는 하루 평균 '
                       '2,000kcal이에요.\n'
                       '\n'
                       '정말 잘하셨어요. 다음 주도 이 페이스 그대로 가요!'},
 'watch_only': {'evidence': ['운동 완료율 평균 40% · 기준 60% 미만'],
                'headline': '김민수 회원은 운동 완료율 40%가 목표를 벗어나 다음 주 조정이 필요합니다.',
                'points': ['운동 완료율 평균 40% · 기준 60% 미만'],
                'topics': ['운동 완료율 40%'],
                'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                           '\n'
                           '운동 완료율은 평균 40%였어요. 많이 바쁘셨나 봐요.\n'
                           '\n'
                           '다음 주에는 이 부분만 같이 신경 써 봐요. 프로그램은 제가 조정해서 올려둘게요.'},
 'good_sodium_over1': {'evidence': ['운동 완료율 평균 50% · 기준 60% 미만',
                                    '나트륨 평균 1,800mg · 기본 목표 2,000mg 초과 1일'],
                       'headline': '김민수 회원은 나트륨 목표 초과 1일로 잘 지켰고, 다음 주는 운동 완료율 50%를 함께 '
                                   '챙기면 좋겠습니다.',
                       'points': ['운동 완료율 평균 50% · 기준 60% 미만',
                                  '나트륨 평균 1,800mg · 기본 목표 2,000mg 초과 1일'],
                       'topics': ['운동 완료율 50%'],
                       'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                                  '\n'
                                  '운동 완료율은 평균 50%였어요. 많이 바쁘셨나 봐요.\n'
                                  '\n'
                                  '나트륨은 하루 평균 1,800mg이었고, 목표(2,000mg)를 넘긴 날이 1일이었어요. '
                                  '국물을 절반만 남기셔도 하루 400~500mg은 줄어듭니다.\n'
                                  '\n'
                                  '다음 주에는 이 부분만 같이 신경 써 봐요. 프로그램은 제가 조정해서 올려둘게요.'},
 'many': {'evidence': ['운동 완료율 평균 55% · 기준 60% 미만',
                       '나트륨 평균 2,600mg · 개인 목표 2,300mg 초과 5일',
                       '당류 평균 75g · 개인 목표 40g 초과 4일',
                       '칼로리 평균 2,600kcal · 개인 목표 2,100kcal 대비 초과 24%',
                       '건너뛴 운동: 스쿼트, 런지, 플랭크',
                       '탄수화물 평균 310g · 개인 목표 200g 대비 초과 55%',
                       '단백질 평균 55g · 개인 목표 120g 대비 부족 54%'],
          'headline': '김민수 회원은 운동 완료율 55%가 목표를 벗어나 다음 주 조정이 필요합니다. 그 밖에 6가지도 함께 보세요.',
          'points': ['운동 완료율 평균 55% · 기준 60% 미만',
                     '나트륨 평균 2,600mg · 개인 목표 2,300mg 초과 5일',
                     '외 5건 — 리포트 본문에서 확인'],
          'topics': ['운동 완료율 55%',
                     '나트륨 목표 초과 5일',
                     '당류 목표 초과 4일',
                     '칼로리 초과',
                     '건너뛴 운동 3가지',
                     '탄수화물 초과',
                     '단백질 부족'],
          'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                     '\n'
                     '운동 완료율은 평균 55%였어요. 많이 바쁘셨나 봐요. 다만 스쿼트, 런지, 플랭크는 건너뛰셨더라고요. 컨디션 '
                     '때문이었다면 다음 PT 때 말씀해 주세요. 대체 운동으로 바꿔 둘게요.\n'
                     '\n'
                     '나트륨은 하루 평균 2,600mg이었고, 목표(2,300mg)를 넘긴 날이 5일이었어요. 국물을 절반만 남기셔도 '
                     '하루 400~500mg은 줄어듭니다. 칼로리는 하루 평균 2,600kcal이에요.\n'
                     '\n'
                     '다음 주에는 이 부분만 같이 신경 써 봐요. 프로그램은 제가 조정해서 올려둘게요.'},
 'cal_under': {'evidence': ['칼로리 평균 1,250kcal · 기본 목표 2,000kcal 대비 부족 38%'],
               'headline': '김민수 회원은 칼로리 부족이 목표를 벗어나 다음 주 조정이 필요합니다.',
               'points': ['칼로리 평균 1,250kcal · 기본 목표 2,000kcal 대비 부족 38%'],
               'topics': ['칼로리 부족'],
               'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                          '\n'
                          '칼로리는 하루 평균 1,250kcal이에요.\n'
                          '\n'
                          '다음 주에는 이 부분만 같이 신경 써 봐요. 프로그램은 제가 조정해서 올려둘게요.'},
 'sugar_avg': {'evidence': ['당류 평균 58g · 기본 목표 50g 초과 2일',
                            '운동 완료율 평균 80%',
                            '나트륨 평균 1,500mg · 기본 목표 2,000mg 초과 0일'],
               'headline': '김민수 회원은 운동 완료율 80%로 잘 지켰고, 다음 주는 당류 목표 초과 2일을 함께 챙기면 '
                           '좋겠습니다.',
               'points': ['당류 평균 58g · 기본 목표 50g 초과 2일',
                          '운동 완료율 평균 80%',
                          '나트륨 평균 1,500mg · 기본 목표 2,000mg 초과 0일'],
               'topics': ['당류 목표 초과 2일'],
               'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                          '\n'
                          '운동은 평균 80%로 잘 따라오셨어요.\n'
                          '\n'
                          '나트륨은 하루 평균 1,500mg으로 목표(2,000mg) 안에서 잘 지키고 계세요.\n'
                          '\n'
                          '정말 잘하셨어요. 다음 주도 이 페이스 그대로 가요!'},
 'sodium_avg_over': {'evidence': ['나트륨 평균 2,400mg · 기본 목표 2,000mg 초과 0일'],
                     'headline': '김민수 회원은 나트륨 평균 2,400mg가 목표를 벗어나 다음 주 조정이 필요합니다.',
                     'points': ['나트륨 평균 2,400mg · 기본 목표 2,000mg 초과 0일'],
                     'topics': ['나트륨 평균 2,400mg'],
                     'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                                '\n'
                                '나트륨은 하루 평균 2,400mg으로 목표(2,000mg) 안에서 잘 지키고 계세요.\n'
                                '\n'
                                '다음 주에는 이 부분만 같이 신경 써 봐요. 프로그램은 제가 조정해서 올려둘게요.'}}


def _outputs(report: WeeklyReportOut) -> dict:
    evidence = svc._evidence(report)
    summary = svc._rule_summary(report, evidence)
    return {
        "evidence": evidence,
        "headline": summary.headline,
        "points": summary.points,
        "topics": [w.topic for w in svc.watchpoints(report)],
        "message": trainer_reports_service.report_message(report),
    }


# ---- 문장 회귀 ----

@pytest.mark.parametrize("case", list(CASES))
def test_output_is_byte_identical(case):
    assert _outputs(_report(**CASES[case])) == KO_GOLDEN[case]


def test_system_prompt_is_unchanged():
    assert svc._SYSTEM_PROMPT.startswith("당신은 퍼스널 트레이너를 보조하는")
    assert svc.prompt_safety.UNTRUSTED_QUOTE_GUARD in svc._SYSTEM_PROMPT


def test_points_within_the_limit_are_untouched():
    lines = ["a", "b"]
    assert svc._points(_report(), lines) == lines


# ---- 모델 경로 ----

class _FakeLLM:
    """받은 지시문을 기록하고 정해 둔 응답을 돌려준다."""

    def __init__(self, reply=None, error: Exception | None = None):
        self.reply = reply
        self.error = error
        self.calls: list[tuple[str, str]] = []

    def generate(self, system_prompt, user_prompt, **_):
        self.calls.append((system_prompt, user_prompt))
        if self.error:
            raise self.error
        return SimpleNamespace(text=self.reply(user_prompt))


@pytest.fixture
def fake_week(monkeypatch):
    """DB 없이 generate_summary 를 돌린다 — 리포트 조립만 바꿔 끼운다."""
    report = _report()
    monkeypatch.setattr(
        trainer_reports_service, "build_weekly_report", lambda *a, **k: report
    )
    return report


def _install(monkeypatch, llm: _FakeLLM) -> _FakeLLM:
    monkeypatch.setattr(svc, "get_coach_llm", lambda *a, **k: llm)
    return llm


def _first_evidence(user_prompt: str) -> str:
    evidence = json.loads(user_prompt)["week"]["grounded_evidence"]
    return json.dumps(
        {"headline": "꾸준한 한 주였어요.", "points": [evidence[0]]}, ensure_ascii=False
    )


def test_generate_summary_sends_the_korean_prompt_and_evidence(monkeypatch, fake_week):
    llm = _install(monkeypatch, _FakeLLM(_first_evidence))
    out = svc.generate_summary(None, "t", "m", None)

    system, user = llm.calls[0]
    assert system is svc._SYSTEM_PROMPT
    assert json.loads(user)["week"]["grounded_evidence"] == KO_GOLDEN["default"]["evidence"]
    assert out.generated_by == "llm"
    assert out.headline == "꾸준한 한 주였어요."
    assert out.points == [KO_GOLDEN["default"]["evidence"][0]]


def test_generate_summary_falls_back_to_rules_when_the_model_fails(monkeypatch, fake_week):
    _install(monkeypatch, _FakeLLM(error=RuntimeError("down")))
    out = svc.generate_summary(None, "t", "m", None)
    assert out.generated_by == "rule"
    assert out == svc._rule_summary(fake_week, svc._evidence(fake_week))
    assert out.headline == KO_GOLDEN["default"]["headline"]


def test_generate_summary_falls_back_on_broken_json(monkeypatch, fake_week):
    _install(monkeypatch, _FakeLLM(lambda _: "not json"))
    out = svc.generate_summary(None, "t", "m", None)
    assert out.generated_by == "rule"
    assert out.points == KO_GOLDEN["default"]["points"]


def test_generate_summary_skips_the_model_for_an_empty_week(monkeypatch):
    report = _report(**CASES["empty"])
    monkeypatch.setattr(trainer_reports_service, "build_weekly_report", lambda *a, **k: report)
    llm = _install(monkeypatch, _FakeLLM(_first_evidence))
    out = svc.generate_summary(None, "t", "m", None)
    assert llm.calls == []
    assert out.headline == KO_GOLDEN["empty"]["headline"]


# ---- 엔드포인트 ----

def _trainer_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _headers(client, language: str | None = None) -> dict:
    headers = {"Authorization": f"Bearer {_trainer_token(client)}"}
    if language is not None:
        headers["Accept-Language"] = language
    return headers


@pytest.fixture
def model_down(monkeypatch):
    """모델이 없는 환경 — 규칙 기반 요약이 돌아와 문장을 비교할 수 있다."""
    _install(monkeypatch, _FakeLLM(error=RuntimeError("no provider in tests")))


#: 어떤 헤더로 불러도 같은 한국어 응답이어야 한다.
LANGUAGES = [None, "ko", "en", "en-US,en;q=0.9", "ko;q=0.2, en;q=0.8", "fr"]


@pytest.mark.parametrize("language", LANGUAGES)
def test_summary_endpoint_is_korean_whatever_the_header(client, model_down, language):
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/summary",
        headers=_headers(client, language),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["generated_by"] == "rule"
    assert "회원" in body["headline"]
    assert _HANGUL.search(body["headline"])


def test_summary_endpoint_matches_the_service_whatever_the_header(
    client, db_session, model_down
):
    """엔드포인트가 낸 문장 = 같은 주를 서비스가 만든 문장. 헤더는 문장을 바꾸지 않는다."""
    from app.core import clock as app_clock

    week = trainer_reports_service.week_start_of(app_clock.today())
    trainer_id = client.get(
        "/v1/trainer/me", headers=_headers(client)
    ).json()["id"]
    expected = svc.generate_summary(db_session, trainer_id, "user-jisu", week)
    for language in (None, "ko", "en"):
        body = client.get(
            "/v1/trainer/clients/user-jisu/report/summary",
            headers=_headers(client, language),
        ).json()
        assert body["headline"] == expected.headline, language
        assert body["points"] == expected.points, language


@pytest.mark.parametrize("language", [None, "ko", "en"])
def test_summary_endpoint_always_sends_the_korean_prompt(
    client, monkeypatch, fake_week, language
):
    """모델 경로도 헤더와 무관하다 — 지시문·근거·돌려준 근거가 한국어다."""
    llm = _install(monkeypatch, _FakeLLM(_first_evidence))
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/summary",
        headers=_headers(client, language),
    )
    assert r.status_code == 200, r.text
    assert llm.calls[0][0] is svc._SYSTEM_PROMPT
    body = r.json()
    assert body["generated_by"] == "llm"
    assert body["points"] == [KO_GOLDEN["default"]["evidence"][0]]


def test_summary_endpoint_still_refuses_someone_elses_client(client):
    r = client.get(
        "/v1/trainer/clients/user-nobody/report/summary",
        headers=_headers(client, "en"),
    )
    assert r.status_code == 404


def test_report_endpoint_draft_is_korean_whatever_the_header(client):
    default = client.get(
        "/v1/trainer/clients/user-jisu/report", headers=_headers(client)
    ).json()
    assert "주간 리포트 정리해서 보내드려요" in default["message"]
    for language in ("ko", "en"):
        body = client.get(
            "/v1/trainer/clients/user-jisu/report", headers=_headers(client, language)
        ).json()
        assert body["message"] == default["message"], language
        for key in ("completion_avg", "sodium_avg", "sodium_over_days", "calories_week"):
            assert body[key] == default[key], key


def test_sending_without_an_edit_uses_the_korean_draft(client):
    r = client.post(
        "/v1/trainer/clients/user-jisu/report/send",
        json={},
        headers=_headers(client, "en"),
    )
    assert r.status_code == 201, r.text
    assert "주간 리포트 정리해서 보내드려요" in r.json()["body"]


def test_sending_the_trainers_own_edit_is_sent_as_written(client):
    r = client.post(
        "/v1/trainer/clients/user-jisu/report/send",
        json={"message": "이번 주 컨디션 어땠어요?"},
        headers=_headers(client, "en"),
    )
    assert r.status_code == 201, r.text
    assert r.json()["body"] == "이번 주 컨디션 어땠어요?"
