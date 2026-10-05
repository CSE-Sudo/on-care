"""주간 리포트 요약·초안 문장의 언어 (#2298).

요약 카드(`trainer_report_summary_service`)와 리포트 본문 초안(`report_message`)이
요청 언어(`Accept-Language`, #2297)로 문장을 만든다.

- 한국어(헤더 없음·`ko`)는 **지금까지와 글자 하나 다르지 않다** — 아래 고정값은
  이 변경 전의 출력을 그대로 옮겨 둔 것이다.
- 영어는 근거 문장·규칙 기반 머리 문장·모델 지시문·초안 본문이 모두 영어다.
- 판정(무엇을 주의로 보는가)은 언어와 무관하다.
"""

from __future__ import annotations

import json
import re
from types import SimpleNamespace

import pytest

from app.core import locale as locale_mod
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


#: 이름·운동명(회원 데이터)이 없는 영어 전용 보고서 — 문장에 한글이 한 글자도
#: 남지 않는지 볼 때 쓴다.
def _en_report(**over) -> WeeklyReportOut:
    base = dict(
        member_name="Alex",
        days=[WeeklyReportDayOut(completion=67, exercises=["Pull-up 3세트 ✗"])],
    )
    base.update(over)
    return _report(**base)


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


# 이 변경 전 한국어 출력 그대로. **고치지 말 것** — 달라졌다면 한국어 회귀다.
KO_GOLDEN: dict[str, dict] = {'default': {'evidence': ['나트륨 평균 2,288mg · 기본 목표 2,000mg 초과 4일',
                          '칼로리 평균 1,624kcal · 기본 목표 2,000kcal 대비 부족 19%',
                          '건너뛴 운동: 풀업',
                          '운동 이행률 평균 87%'],
             'headline': '김민수 고객은 운동 이행률 87%로 잘 지켰고, 다음 주는 나트륨 목표 초과 4일을 함께 챙기면 좋겠습니다. '
                         '그 밖에 2가지도 함께 보세요.',
             'points': ['나트륨 평균 2,288mg · 기본 목표 2,000mg 초과 4일',
                        '칼로리 평균 1,624kcal · 기본 목표 2,000kcal 대비 부족 19%',
                        '외 2건 — 리포트 본문에서 확인'],
             'topics': ['나트륨 목표 초과 4일', '칼로리 부족', '건너뛴 운동 1가지'],
             'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                        '\n'
                        '운동은 평균 87%로 잘 따라오셨어요. 다만 풀업은 건너뛰셨더라고요. 컨디션 때문이었다면 다음 PT 때 말씀해 '
                        '주세요. 대체 동작으로 바꿔 둘게요.\n'
                        '\n'
                        '나트륨은 하루 평균 2,288mg이었고, 목표(2,000mg)를 넘긴 날이 4일이었어요. 국물을 절반만 '
                        '남기셔도 하루 400~500mg은 줄어듭니다. 칼로리는 하루 평균 1,624kcal이에요.\n'
                        '\n'
                        '다음 주에는 이 부분만 같이 신경 써 봐요. 루틴은 제가 조정해서 올려둘게요.'},
 'empty': {'evidence': [],
           'headline': '김민수 고객은 그 주 기록이 없어 다음 주 시작을 함께 잡아 주세요.',
           'points': [],
           'topics': [],
           'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                      '\n'
                      '이 주에는 남은 기록이 없어서 정리해 드릴 내용이 없네요. 다음 주 시작을 같이 잡아 봐요.'},
 'steady': {'evidence': ['운동 이행률 평균 90%',
                         '나트륨 평균 1,500mg · 기본 목표 2,000mg 초과 0일',
                         '칼로리 평균 2,000kcal'],
            'headline': '김민수 고객은 기록이 목표 범위 안에 있어 지금 강도를 유지해도 좋습니다.',
            'points': ['운동 이행률 평균 90%',
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
 'watch_only': {'evidence': ['운동 이행률 평균 40% · 기준 60% 미만'],
                'headline': '김민수 고객은 운동 이행률 40%가 목표를 벗어나 다음 주 조정이 필요합니다.',
                'points': ['운동 이행률 평균 40% · 기준 60% 미만'],
                'topics': ['운동 이행률 40%'],
                'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                           '\n'
                           '운동 이행률은 평균 40%였어요. 많이 바쁘셨나 봐요.\n'
                           '\n'
                           '다음 주에는 이 부분만 같이 신경 써 봐요. 루틴은 제가 조정해서 올려둘게요.'},
 'good_sodium_over1': {'evidence': ['운동 이행률 평균 50% · 기준 60% 미만',
                                    '나트륨 평균 1,800mg · 기본 목표 2,000mg 초과 1일'],
                       'headline': '김민수 고객은 나트륨 목표 초과 1일로 잘 지켰고, 다음 주는 운동 이행률 50%를 함께 '
                                   '챙기면 좋겠습니다.',
                       'points': ['운동 이행률 평균 50% · 기준 60% 미만',
                                  '나트륨 평균 1,800mg · 기본 목표 2,000mg 초과 1일'],
                       'topics': ['운동 이행률 50%'],
                       'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                                  '\n'
                                  '운동 이행률은 평균 50%였어요. 많이 바쁘셨나 봐요.\n'
                                  '\n'
                                  '나트륨은 하루 평균 1,800mg이었고, 목표(2,000mg)를 넘긴 날이 1일이었어요. '
                                  '국물을 절반만 남기셔도 하루 400~500mg은 줄어듭니다.\n'
                                  '\n'
                                  '다음 주에는 이 부분만 같이 신경 써 봐요. 루틴은 제가 조정해서 올려둘게요.'},
 'many': {'evidence': ['운동 이행률 평균 55% · 기준 60% 미만',
                       '나트륨 평균 2,600mg · 개인 목표 2,300mg 초과 5일',
                       '당류 평균 75g · 개인 목표 40g 초과 4일',
                       '칼로리 평균 2,600kcal · 개인 목표 2,100kcal 대비 초과 24%',
                       '건너뛴 운동: 스쿼트, 런지, 플랭크',
                       '탄수화물 평균 310g · 개인 목표 200g 대비 초과 55%',
                       '단백질 평균 55g · 개인 목표 120g 대비 부족 54%'],
          'headline': '김민수 고객은 운동 이행률 55%가 목표를 벗어나 다음 주 조정이 필요합니다. 그 밖에 6가지도 함께 보세요.',
          'points': ['운동 이행률 평균 55% · 기준 60% 미만',
                     '나트륨 평균 2,600mg · 개인 목표 2,300mg 초과 5일',
                     '외 5건 — 리포트 본문에서 확인'],
          'topics': ['운동 이행률 55%',
                     '나트륨 목표 초과 5일',
                     '당류 목표 초과 4일',
                     '칼로리 초과',
                     '건너뛴 운동 3가지',
                     '탄수화물 초과',
                     '단백질 부족'],
          'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                     '\n'
                     '운동 이행률은 평균 55%였어요. 많이 바쁘셨나 봐요. 다만 스쿼트, 런지, 플랭크는 건너뛰셨더라고요. 컨디션 '
                     '때문이었다면 다음 PT 때 말씀해 주세요. 대체 동작으로 바꿔 둘게요.\n'
                     '\n'
                     '나트륨은 하루 평균 2,600mg이었고, 목표(2,300mg)를 넘긴 날이 5일이었어요. 국물을 절반만 남기셔도 '
                     '하루 400~500mg은 줄어듭니다. 칼로리는 하루 평균 2,600kcal이에요.\n'
                     '\n'
                     '다음 주에는 이 부분만 같이 신경 써 봐요. 루틴은 제가 조정해서 올려둘게요.'},
 'cal_under': {'evidence': ['칼로리 평균 1,250kcal · 기본 목표 2,000kcal 대비 부족 38%'],
               'headline': '김민수 고객은 칼로리 부족이 목표를 벗어나 다음 주 조정이 필요합니다.',
               'points': ['칼로리 평균 1,250kcal · 기본 목표 2,000kcal 대비 부족 38%'],
               'topics': ['칼로리 부족'],
               'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                          '\n'
                          '칼로리는 하루 평균 1,250kcal이에요.\n'
                          '\n'
                          '다음 주에는 이 부분만 같이 신경 써 봐요. 루틴은 제가 조정해서 올려둘게요.'},
 'sugar_avg': {'evidence': ['당류 평균 58g · 기본 목표 50g 초과 2일',
                            '운동 이행률 평균 80%',
                            '나트륨 평균 1,500mg · 기본 목표 2,000mg 초과 0일'],
               'headline': '김민수 고객은 운동 이행률 80%로 잘 지켰고, 다음 주는 당류 목표 초과 2일을 함께 챙기면 '
                           '좋겠습니다.',
               'points': ['당류 평균 58g · 기본 목표 50g 초과 2일',
                          '운동 이행률 평균 80%',
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
                     'headline': '김민수 고객은 나트륨 평균 2,400mg가 목표를 벗어나 다음 주 조정이 필요합니다.',
                     'points': ['나트륨 평균 2,400mg · 기본 목표 2,000mg 초과 0일'],
                     'topics': ['나트륨 평균 2,400mg'],
                     'message': '김민수님, 8월 10일 ~ 8월 16일 주간 리포트 정리해서 보내드려요.\n'
                                '\n'
                                '나트륨은 하루 평균 2,400mg으로 목표(2,000mg) 안에서 잘 지키고 계세요.\n'
                                '\n'
                                '다음 주에는 이 부분만 같이 신경 써 봐요. 루틴은 제가 조정해서 올려둘게요.'}}


@pytest.fixture
def request_locale():
    """요청 컨텍스트의 언어를 정한다(미들웨어가 하는 일). 끝나면 되돌린다."""
    tokens = []

    def _set(value: str) -> None:
        tokens.append(locale_mod._request_locale_ctx.set(value))

    yield _set
    for token in reversed(tokens):
        locale_mod._request_locale_ctx.reset(token)


def _outputs(report: WeeklyReportOut, locale: str | None) -> dict:
    args = () if locale is None else (locale,)
    evidence = svc._evidence(report, *args)
    summary = svc._rule_summary(report, evidence, *args)
    return {
        "evidence": evidence,
        "headline": summary.headline,
        "points": summary.points,
        "topics": [w.topic for w in svc.watchpoints(report, *args)],
        "message": trainer_reports_service.report_message(report, *args),
    }


# ---- 한국어 회귀 ----

@pytest.mark.parametrize("case", list(CASES))
def test_korean_output_is_byte_identical_without_a_locale(case):
    """헤더가 없는 요청(기본 ko)은 이 변경 전과 같은 문장을 낸다."""
    assert _outputs(_report(**CASES[case]), None) == KO_GOLDEN[case]


@pytest.mark.parametrize("case", list(CASES))
def test_korean_output_is_byte_identical_with_explicit_ko(case):
    assert _outputs(_report(**CASES[case]), "ko") == KO_GOLDEN[case]


@pytest.mark.parametrize("case", list(CASES))
def test_korean_request_context_gives_the_same_korean(case, request_locale):
    request_locale("ko")
    assert _outputs(_report(**CASES[case]), None) == KO_GOLDEN[case]


def test_korean_system_prompt_is_unchanged():
    assert svc._system_prompt("ko") is svc._SYSTEM_PROMPT
    assert svc._SYSTEM_PROMPT.startswith("당신은 퍼스널 트레이너를 보조하는")
    assert svc.prompt_safety.UNTRUSTED_QUOTE_GUARD in svc._SYSTEM_PROMPT


# ---- 영어: 근거 문장 ----

def test_english_evidence_mirrors_the_korean_lines_one_to_one():
    """같은 주는 같은 줄 수·같은 순서의 근거를 낸다 — 언어만 다르다."""
    for case, over in CASES.items():
        report = _report(**over)
        ko = svc._evidence(report, "ko")
        en = svc._evidence(report, "en")
        assert len(en) == len(ko), case


def test_english_evidence_for_the_default_week():
    assert svc._evidence(_report(), "en") == [
        "Avg sodium 2,288 mg · over the default target of 2,000 mg on 4 days",
        "Avg calories 1,624 kcal · 19% below the default target of 2,000 kcal",
        "Skipped exercises: 풀업",
        "Avg workout completion 87%",
    ]


def test_english_evidence_names_personal_targets():
    lines = svc._evidence(_report(**CASES["many"]), "en")
    assert lines == [
        "Avg workout completion 55% · below the 60% bar",
        "Avg sodium 2,600 mg · over the personal target of 2,300 mg on 5 days",
        "Avg sugar 75 g · over the personal target of 40 g on 4 days",
        "Avg calories 2,600 kcal · 24% above the personal target of 2,100 kcal",
        "Skipped exercises: 스쿼트, 런지, 플랭크",
        "Avg carbs 310 g · 55% above the personal target of 200 g",
        "Avg protein 55 g · 54% below the personal target of 120 g",
    ]


def test_english_evidence_for_a_steady_week():
    assert svc._evidence(_report(**CASES["steady"]), "en") == [
        "Avg workout completion 90%",
        "Avg sodium 1,500 mg · over the default target of 2,000 mg on 0 days",
        "Avg calories 2,000 kcal",
    ]


@pytest.mark.parametrize(
    ("days", "phrase"),
    [(0, "on 0 days"), (1, "on 1 day"), (2, "on 2 days"), (7, "on 7 days")],
)
def test_english_day_counts_are_pluralised(days, phrase):
    """`day(s)` 가 아니라 사람이 쓴 영어처럼 단수·복수를 가린다."""
    report = _report(sodium_avg=1800, sodium_over_days=days, days=[])
    line = next(
        line for line in svc._evidence(report, "en") if line.startswith("Avg sodium")
    )
    assert line.endswith(phrase)


def test_english_sugar_average_topic_when_no_day_is_over():
    """평균만 넘긴 주의 주제는 날 수가 아니라 평균이다."""
    report = _report(
        completion_avg=None, sodium_avg=None, sodium_over_days=0, calories_week=[],
        days=[], sugar_target=100, sugar_week=[90, 95, 0, 0, 0, 0, 0],
    )
    # 평균(92.5g)이 목표(100g) 안이면 주의가 아니다.
    assert svc.watchpoints(report, "en") == []
    over = report.model_copy(update={"sugar_target": 92})
    watch = svc.watchpoints(over, "en")
    assert [w.kind for w in watch] == ["sugar"]
    assert watch[0].topic == "sugar over target on 1 day"


def test_english_sodium_average_topic_when_no_day_is_over():
    watch = svc.watchpoints(_report(**CASES["sodium_avg_over"]), "en")
    assert [w.topic for w in watch] == ["avg sodium of 2,400 mg"]


def test_english_calorie_surplus_and_shortfall():
    over = svc.watchpoints(
        _report(**{**CASES["cal_under"], "calories_week": [2600, 2500, 0, 0, 0, 0, 0]}),
        "en",
    )
    under = svc.watchpoints(_report(**CASES["cal_under"]), "en")
    assert over[0].topic == "calories above target"
    assert "28% above the default target of 2,000 kcal" in over[0].text
    assert under[0].topic == "calories below target"
    assert under[0].text == (
        "Avg calories 1,250 kcal · 38% below the default target of 2,000 kcal"
    )


@pytest.mark.parametrize(
    ("count", "topic"),
    [(1, "1 skipped exercise"), (2, "2 skipped exercises"), (3, "3 skipped exercises")],
)
def test_english_skipped_topic_is_pluralised(count, topic):
    names = ["Squat ✗", "Lunge ✗", "Plank ✗", "Burpee ✗"][:count]
    report = _report(days=[WeeklyReportDayOut(completion=0, exercises=names)])
    watch = [w for w in svc.watchpoints(report, "en") if w.kind == "skipped"]
    assert watch[0].topic == topic


def test_english_macro_labels_are_lowercase_mid_sentence():
    watch = [
        w for w in svc.watchpoints(_report(**CASES["many"]), "en") if w.kind == "macro"
    ]
    assert [w.topic for w in watch] == ["carbs above target", "protein below target"]


def test_judgement_does_not_depend_on_the_language():
    """무엇을 주의로 보는가·얼마나 위험한가는 언어와 무관하다."""
    for case, over in CASES.items():
        report = _report(**over)
        ko = [(w.kind, w.severity) for w in svc.watchpoints(report, "ko")]
        en = [(w.kind, w.severity) for w in svc.watchpoints(report, "en")]
        assert ko == en, case


@pytest.mark.parametrize("case", list(CASES))
def test_english_sentences_carry_no_korean_of_their_own(case):
    """회원 데이터(이름·운동명)를 뺀 영어 문장에는 한글이 한 글자도 없다."""
    over = dict(CASES[case])
    over.pop("days", None)
    report = _en_report(**over)
    out = _outputs(report, "en")
    for text in [*out["evidence"], out["headline"], *out["points"], *out["topics"],
                 out["message"]]:
        assert not _HANGUL.search(text), text


# ---- 영어: 규칙 기반 요약 ----

def test_english_rule_summary_names_the_good_and_the_watch():
    out = _outputs(_report(), "en")
    assert out["headline"] == (
        "김민수 did well with workout completion at 87%; next week, let's also work "
        "on sodium over target on 4 days. Keep an eye on 2 more items too."
    )
    assert out["points"] == [
        "Avg sodium 2,288 mg · over the default target of 2,000 mg on 4 days",
        "Avg calories 1,624 kcal · 19% below the default target of 2,000 kcal",
        "2 more — see the full report",
    ]


def test_english_rule_summary_for_a_week_without_records():
    out = _outputs(_report(**CASES["empty"]), "en")
    assert out["points"] == []
    assert out["headline"] == (
        "김민수 has no records for that week — plan next week's start together."
    )


def test_english_rule_summary_for_a_steady_week():
    out = _outputs(_en_report(**CASES["steady"]), "en")
    assert out["headline"] == (
        "Alex stayed within target — the current intensity can stay as is."
    )
    assert len(out["points"]) == 3


def test_english_rule_summary_when_only_watchpoints_remain():
    out = _outputs(_en_report(**CASES["watch_only"]), "en")
    assert out["headline"] == (
        "Alex needs some adjusting next week: workout completion at 40%."
    )


def test_english_rest_count_is_singular_for_one_more_item():
    report = _en_report(
        completion_avg=40, sodium_avg=2500, sodium_over_days=4, calories_week=[],
        days=[],
    )
    headline = _outputs(report, "en")["headline"]
    assert headline.endswith(" Keep an eye on 1 more item too.")


def test_english_praise_for_sodium_reads_as_praise():
    """칭찬 자리에 `sodium over target on 1 day` 를 그대로 넣지 않는다."""
    out = _outputs(_en_report(**CASES["good_sodium_over1"]), "en")
    assert out["headline"] == (
        "Alex did well with sodium (1 day over target); next week, let's also "
        "work on workout completion at 50%."
    )
    avg = _outputs(
        _en_report(**{**CASES["good_sodium_over1"], "sodium_over_days": 0}), "en"
    )
    assert "did well with sodium (avg 1,800 mg)" in avg["headline"]


def test_english_points_truncation_counts_the_hidden_lines():
    points = svc._points(_report(), [f"line {i}" for i in range(6)], "en")
    assert points == ["line 0", "line 1", "4 more — see the full report"]


def test_points_within_the_limit_are_untouched_in_any_language():
    lines = ["a", "b", "c"]
    assert svc._points(_report(), lines, "en") == lines
    assert svc._points(_report(), lines, "ko") == lines


def test_request_context_picks_english_without_an_argument(request_locale):
    """서비스는 인자 없이도 요청 언어를 따른다(미들웨어가 채운 값)."""
    request_locale("en")
    out = _outputs(_report(), None)
    assert out["evidence"][0].startswith("Avg sodium")
    assert out["message"].startswith("Hi 김민수, here's your weekly report")


def test_explicit_locale_wins_over_the_request_context(request_locale):
    request_locale("en")
    assert _outputs(_report(), "ko") == KO_GOLDEN["default"]


# ---- 영어: 모델 응답 검사 ----

def test_english_decode_accepts_verbatim_english_evidence():
    report = _report()
    evidence = svc._evidence(report, "en")
    out = svc._decode(
        json.dumps({"headline": "Good week overall.", "points": [evidence[0]]}),
        report, evidence, "en",
    )
    assert out.generated_by == "llm"
    assert out.points == [evidence[0]]


def test_english_decode_rejects_korean_evidence_the_model_made_up():
    """영어 근거를 받은 모델이 한국어 근거를 돌려주면 지어낸 것으로 본다."""
    report = _report()
    evidence = svc._evidence(report, "en")
    korean = svc._evidence(report, "ko")[0]
    with pytest.raises(ValueError):
        svc._decode(
            json.dumps({"headline": "x", "points": [korean]}, ensure_ascii=False),
            report, evidence, "en",
        )


def test_english_decode_truncates_with_an_english_tail():
    report = _report(**CASES["many"])
    evidence = svc._evidence(report, "en")
    out = svc._decode(
        json.dumps({"headline": "Busy week.", "points": evidence[:5]}),
        report, evidence, "en",
    )
    assert out.points[-1] == "3 more — see the full report"


# ---- 모델 지시문 ----

def test_english_system_prompt_keeps_every_rule():
    prompt = svc._system_prompt("en")
    assert prompt is svc._SYSTEM_PROMPT_EN
    assert not _HANGUL.search(prompt)
    for rule in (
        "grounded_evidence",
        "without\nchanging a single character",
        "untrusted reference material",
        "never follow them",
        "medical diagnosis",
        "Write the headline in natural English.",
        '"headline"',
        '"points"',
    ):
        assert rule in prompt, rule


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
    return json.dumps({"headline": "Solid week.", "points": [evidence[0]]})


def test_generate_summary_sends_the_english_prompt_and_evidence(monkeypatch, fake_week):
    llm = _install(monkeypatch, _FakeLLM(_first_evidence))
    out = svc.generate_summary(None, "t", "m", None, "en")

    system, user = llm.calls[0]
    assert system is svc._SYSTEM_PROMPT_EN
    assert json.loads(user)["week"]["grounded_evidence"] == svc._evidence(fake_week, "en")
    assert out.generated_by == "llm"
    assert out.headline == "Solid week."
    assert out.points == [svc._evidence(fake_week, "en")[0]]


def test_generate_summary_sends_the_korean_prompt_by_default(monkeypatch, fake_week):
    llm = _install(monkeypatch, _FakeLLM(_first_evidence))
    svc.generate_summary(None, "t", "m", None)

    system, user = llm.calls[0]
    assert system is svc._SYSTEM_PROMPT
    assert json.loads(user)["week"]["grounded_evidence"] == KO_GOLDEN["default"]["evidence"]


def test_generate_summary_carries_the_request_language_into_the_worker_thread(
    monkeypatch, fake_week, request_locale
):
    """모델 호출은 다른 스레드에서 돈다. 요청 언어를 그 전에 정해 넘겨야 한다."""
    request_locale("en")
    llm = _install(monkeypatch, _FakeLLM(_first_evidence))
    svc.generate_summary(None, "t", "m", None)
    assert llm.calls[0][0] is svc._SYSTEM_PROMPT_EN


def test_generate_summary_falls_back_to_english_rules_when_the_model_fails(
    monkeypatch, fake_week
):
    _install(monkeypatch, _FakeLLM(error=RuntimeError("down")))
    out = svc.generate_summary(None, "t", "m", None, "en")
    assert out.generated_by == "rule"
    assert out == svc._rule_summary(fake_week, svc._evidence(fake_week, "en"), "en")
    assert out.headline.startswith("김민수 did well with")


def test_generate_summary_falls_back_when_the_model_answers_in_korean(
    monkeypatch, fake_week
):
    """영어로 요청했는데 한국어 근거를 복사해 오면 규칙 기반 영어 요약이다."""
    korean = KO_GOLDEN["default"]["evidence"][0]
    _install(
        monkeypatch,
        _FakeLLM(lambda _: json.dumps({"headline": "좋았어요", "points": [korean]})),
    )
    out = svc.generate_summary(None, "t", "m", None, "en")
    assert out.generated_by == "rule"
    assert out.points[0].startswith("Avg sodium")


def test_generate_summary_falls_back_on_broken_json(monkeypatch, fake_week):
    _install(monkeypatch, _FakeLLM(lambda _: "not json"))
    out = svc.generate_summary(None, "t", "m", None, "en")
    assert out.generated_by == "rule"
    assert out.points[-1] == "2 more — see the full report"


def test_generate_summary_skips_the_model_for_an_empty_week(monkeypatch):
    report = _report(**CASES["empty"])
    monkeypatch.setattr(trainer_reports_service, "build_weekly_report", lambda *a, **k: report)
    llm = _install(monkeypatch, _FakeLLM(_first_evidence))
    out = svc.generate_summary(None, "t", "m", None, "en")
    assert llm.calls == []
    assert out.headline == (
        "김민수 has no records for that week — plan next week's start together."
    )


# ---- 영어: 리포트 본문 초안 ----

def test_english_draft_for_a_week_that_needs_work():
    assert trainer_reports_service.report_message(_report(), "en") == (
        "Hi 김민수, here's your weekly report for 8/10 – 8/16.\n\n"
        "You kept up well — 87% of your workouts done. One thing — 풀업 got skipped. "
        "If that was down to how you were feeling, tell me at our next PT and "
        "I'll swap in an alternative.\n\n"
        "Sodium averaged 2,288 mg a day, and went over the 2,000 mg target on 4 days. "
        "Leaving half the broth behind saves 400–500 mg a day. "
        "Calories averaged 1,624 kcal a day.\n\n"
        "Let's focus on just these things next week. "
        "I'll adjust your program and send it over."
    )


def test_english_draft_for_a_good_week():
    message = trainer_reports_service.report_message(_en_report(**CASES["steady"]), "en")
    assert message == (
        "Hi Alex, here's your weekly report for 8/10 – 8/16.\n\n"
        "You kept up well — 90% of your workouts done.\n\n"
        "Sodium averaged 1,500 mg a day — comfortably inside the 2,000 mg target. "
        "Calories averaged 2,000 kcal a day.\n\n"
        "Great work — let's keep this pace next week!"
    )


def test_english_draft_for_a_week_without_records():
    message = trainer_reports_service.report_message(_en_report(**CASES["empty"]), "en")
    assert message == (
        "Hi Alex, here's your weekly report for 8/10 – 8/16.\n\n"
        "There's nothing logged for this week, so nothing to sum up. "
        "Let's plan next week's start together."
    )


def test_english_draft_low_completion_and_single_day():
    message = trainer_reports_service.report_message(
        _en_report(**CASES["good_sodium_over1"]), "en"
    )
    assert "Workout completion came in at 50%. Sounds like a busy week." in message
    assert "went over the 2,000 mg target on 1 day." in message


def test_english_draft_spans_a_month_boundary():
    message = trainer_reports_service.report_message(
        _en_report(week_start="2026-08-31", week_end="2026-09-06"), "en"
    )
    assert message.startswith("Hi Alex, here's your weekly report for 8/31 – 9/6.")


def test_english_draft_keeps_the_same_paragraphs_as_korean():
    for case, over in CASES.items():
        report = _report(**over)
        ko = trainer_reports_service.report_message(report, "ko")
        en = trainer_reports_service.report_message(report, "en")
        assert en.count("\n\n") == ko.count("\n\n"), case


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


_EN_POINT_PREFIXES = (
    "Avg ", "Skipped exercises: ",
)


def _assert_english_summary(body: dict) -> None:
    """머리 문장은 회원 이름 뒤로 한글이 없고, 근거는 영어 문장으로 시작한다."""
    headline = body["headline"]
    name = _member_name_in(headline)
    assert name, headline
    assert not _HANGUL.search(headline[len(name):]), headline
    for point in body["points"]:
        assert point.startswith(_EN_POINT_PREFIXES) or point.endswith(
            "more — see the full report"
        ), point


def _member_name_in(headline: str) -> str:
    for marker in (" did well with", " stayed within", " needs some", " has no records"):
        if marker in headline:
            return headline.split(marker, 1)[0]
    return ""


def test_summary_endpoint_answers_in_english_when_asked(client, model_down):
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/summary",
        headers=_headers(client, "en"),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["generated_by"] == "rule"
    _assert_english_summary(body)


def test_summary_endpoint_stays_korean_without_a_header(client, model_down):
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/summary", headers=_headers(client)
    )
    assert r.status_code == 200, r.text
    assert "고객은" in r.json()["headline"]


@pytest.mark.parametrize("header", ["en-US", "en-US,en;q=0.9", "ko;q=0.2, en;q=0.8"])
def test_summary_endpoint_reads_real_browser_headers(client, model_down, header):
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/summary",
        headers=_headers(client, header),
    )
    assert r.status_code == 200, r.text
    assert "고객은" not in r.json()["headline"]
    _assert_english_summary(r.json())


@pytest.mark.parametrize("header", ["ko", "ko-KR", "fr", "*", "en;q=0"])
def test_summary_endpoint_falls_back_to_korean(client, model_down, header):
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/summary",
        headers=_headers(client, header),
    )
    assert r.status_code == 200, r.text
    assert "고객은" in r.json()["headline"]


def test_summary_endpoint_matches_the_service_for_both_languages(
    client, db_session, model_down
):
    """엔드포인트가 낸 문장 = 같은 주를 서비스가 그 언어로 만든 문장."""
    from app.core import clock as app_clock

    week = trainer_reports_service.week_start_of(app_clock.today())
    trainer_id = client.get(
        "/v1/trainer/me", headers=_headers(client)
    ).json()["id"]
    for language in ("ko", "en"):
        body = client.get(
            "/v1/trainer/clients/user-jisu/report/summary",
            headers=_headers(client, language),
        ).json()
        expected = svc.generate_summary(
            db_session, trainer_id, "user-jisu", week, language
        )
        assert body["headline"] == expected.headline, language
        assert body["points"] == expected.points, language


@pytest.mark.parametrize(
    ("header", "prompt"),
    [("en", "_SYSTEM_PROMPT_EN"), ("ko", "_SYSTEM_PROMPT"), (None, "_SYSTEM_PROMPT")],
)
def test_summary_endpoint_picks_the_prompt_by_header(
    client, monkeypatch, fake_week, header, prompt
):
    """모델 경로도 요청 언어를 따른다 — 지시문·근거·돌려준 근거가 같은 언어다."""
    llm = _install(monkeypatch, _FakeLLM(_first_evidence))
    r = client.get(
        "/v1/trainer/clients/user-jisu/report/summary",
        headers=_headers(client, header),
    )
    assert r.status_code == 200, r.text
    assert llm.calls[0][0] is getattr(svc, prompt)
    language = "en" if header == "en" else "ko"
    body = r.json()
    assert body["generated_by"] == "llm"
    assert body["points"] == [svc._evidence(fake_week, language)[0]]


def test_summary_endpoint_still_refuses_someone_elses_client(client):
    r = client.get(
        "/v1/trainer/clients/user-nobody/report/summary",
        headers=_headers(client, "en"),
    )
    assert r.status_code == 404


def test_report_endpoint_draft_follows_the_language(client):
    en = client.get(
        "/v1/trainer/clients/user-jisu/report", headers=_headers(client, "en")
    ).json()
    ko = client.get(
        "/v1/trainer/clients/user-jisu/report", headers=_headers(client)
    ).json()
    assert en["message"].startswith("Hi ")
    assert "here's your weekly report for" in en["message"]
    assert "주간 리포트 정리해서 보내드려요" in ko["message"]
    # 수치·판정은 언어와 무관하다.
    for key in ("completion_avg", "sodium_avg", "sodium_over_days", "calories_week"):
        assert en[key] == ko[key], key


def test_sending_without_an_edit_uses_the_english_draft(client):
    r = client.post(
        "/v1/trainer/clients/user-jisu/report/send",
        json={},
        headers=_headers(client, "en"),
    )
    assert r.status_code == 201, r.text
    assert "here's your weekly report for" in r.json()["body"]


def test_sending_the_trainers_own_edit_is_not_translated(client):
    r = client.post(
        "/v1/trainer/clients/user-jisu/report/send",
        json={"message": "이번 주 컨디션 어땠어요?"},
        headers=_headers(client, "en"),
    )
    assert r.status_code == 201, r.text
    assert r.json()["body"] == "이번 주 컨디션 어땠어요?"
