"""AI 루틴 A/B 생성 — 순수 규칙형 로직.

회원의 실데이터 요약(나트륨/완료율/목표)과 트레이너가 조종하는 입력(가능 시간/강도/
메모)으로 두 계획을 만든다:
  * A안 — 짧고 지속하기 쉬운 회복 중심
  * B안 — 운동량/강도를 높인 루틴

LLM 생성과 이 규칙형 생성기로의 폴백은 `trainer_routine_options_service`가 담당한다.
이 모듈은 결정적인 규칙형 계획만 만들며, 의료 진단·치료 지시를 하지 않는다
(운동 구성과 근거만 제시).

**언어(#2301).** 판단(부위 주의·대체 운동 고르기)은 언제나 한국어 운동 이름으로
하고, 결과 문장·라이브러리 운동 이름만 마지막에 요청 언어로 옮긴다. 판단 규칙의
키워드가 한국어라, 영어 이름으로 판단하면 영어 화면에서만 주의 부위를 놓친다.
`intensity`·`type` 은 번역하지 않는 계약값이다.
"""
from __future__ import annotations

import re

from app.core.locale import Locale, localized
from app.services import goal_defaults, korean_josa

SODIUM_TARGET_MG = goal_defaults.DAILY_SODIUM_MG

#: 근거 문장 길이 상한 — 응답 스키마(`RoutineOptionPlanOut.rationale`)와 같은 값이다.
#: 트레이너 메모(최대 500자)를 그대로 인용하므로, 긴 메모에 주의 문장이 붙으면
#: 상한을 넘어 폴백 자체가 검증 오류로 죽는다. 영어 문장은 더 길어 더 쉽게
#: 넘는다(#2301). 넘칠 때만 끝을 줄임표로 자른다 — 짧은 문장은 그대로다.
RATIONALE_MAX_CHARS = 500

# 타입별 운동 라이브러리(부담 낮음 → 높음).
_CARDIO_EASY = ("저강도 걷기", "유산소")
_CARDIO_HARD = ("인터벌 러닝", "유산소")
_STRENGTH = ("스쿼트", "근력")
_STRENGTH2 = ("플랭크", "근력")
_STRETCH = ("코어 스트레칭", "스트레칭")
_STRETCH2 = ("목·어깨 스트레칭", "스트레칭")

_B_LABEL = {"low": "낮음", "moderate": "보통", "high": "높음"}

#: 라이브러리 운동 이름 → 영어(#2301). 회원이 직접 적은 반복 운동 이름은 여기
#: 없으므로 원문 그대로 나간다 — 회원 기록에 적힌 이름을 서버가 바꿔 부르지 않는다.
_EN_EXERCISE_NAMES = {
    "저강도 걷기": "Low-intensity walk",
    "인터벌 러닝": "Interval running",
    "스쿼트": "Squat",
    "플랭크": "Plank",
    "코어 스트레칭": "Core stretch",
    "목·어깨 스트레칭": "Neck & shoulder stretch",
}

#: 주의 부위 이름 → 영어(#2301). 근거 문장에만 쓴다.
_EN_CAUTION_PARTS = {
    "무릎": "knee",
    "허리": "lower back",
    "어깨": "shoulder",
    "발목": "ankle",
}

#: 반복 운동 이름으로 타입을 대략 짐작한다. 완료 기록엔 이름만 있고 타입이
#: 없어서, 화면에 보여줄 타입 하나는 정해야 한다(#776).
_STRETCH_KEYWORDS = ("스트레칭", "요가", "폼롤러")
_CARDIO_KEYWORDS = ("걷기", "러닝", "런닝", "자전거", "유산소", "인터벌", "달리기")


#: 주의사항·대화에서 찾는 부담 부위와, 그 부위에 부담이 큰 운동 이름의 조각.
#: (#1440) 진단을 하지 않는다 — **무엇을 빼야 안전한가**만 안다.
#:
#: 이 표와 아래 낱말 표·라이브러리 운동은 트레이너 웹 데모 A/B
#: (`demo_routine_rules.dart`)도 같은 값으로 든다. 바꾸면
#: `scripts/gen_routine_caution_cases.py` 로 공유 사례 파일
#: (`shared/oncare_rules/vectors/routine_caution_cases.json`)을 다시 만든다 —
#: 서버·트레이너 웹 테스트가 그 파일과 대조한다(#2906).
_CAUTION_RULES: tuple[tuple[str, tuple[str, ...], tuple[str, ...]], ...] = (
    (
        "무릎",
        ("무릎", "슬개", "반월"),
        ("러닝", "런닝", "달리기", "점프", "스쿼트", "런지", "계단"),
    ),
    (
        "허리",
        ("허리", "요추", "디스크"),
        ("데드리프트", "윗몸", "점프", "러닝", "런닝", "달리기"),
    ),
    (
        "어깨",
        ("어깨", "회전근", "견관절"),
        ("숄더", "오버헤드", "푸시업", "벤치", "풀업"),
    ),
    (
        "발목",
        ("발목", "족저"),
        ("러닝", "런닝", "달리기", "점프", "줄넘기", "계단"),
    ),
)

#: 이 말이 보이면 강도를 올리지 않고 전문가 확인을 권한다. 운동으로 판단할
#: 문제가 아니다.
_ESCALATION_KEYWORDS = (
    "가슴 통증",
    "흉통",
    "호흡 곤란",
    "숨이 차",
    "실신",
    "어지럼",
    "수술",
    "골절",
)


def _caution_text(conditions: str, recent_messages: list[str] | tuple[str, ...]) -> str:
    """주의사항으로 읽을 글 — 건강 프로필과 최근 대화를 한 덩어리로 본다."""
    return " ".join([conditions, *recent_messages]).strip()


def cautions_in(
    conditions: str,
    recent_messages: list[str] | tuple[str, ...] = (),
) -> list[str]:
    """조심할 부위 이름. 없으면 빈 목록이다. (#1440)"""
    text = _caution_text(conditions, recent_messages)
    if not text:
        return []
    return [
        part for part, keywords, _ in _CAUTION_RULES if any(k in text for k in keywords)
    ]


def needs_professional_check(
    conditions: str,
    recent_messages: list[str] | tuple[str, ...] = (),
) -> bool:
    """운동 구성으로 답할 수 없는 상태인가 — 그러면 강도를 올리지 않는다."""
    text = _caution_text(conditions, recent_messages)
    return any(keyword in text for keyword in _ESCALATION_KEYWORDS)


def _avoids(name: str, cautions: list[str]) -> bool:
    """이 운동이 조심할 부위에 부담을 주는가."""
    for part, _, risky in _CAUTION_RULES:
        if part in cautions and any(token in name for token in risky):
            return True
    return False


def _safe_parts(
    parts: list[tuple[str, str, int]],
    cautions: list[str],
) -> list[tuple[str, str, int]]:
    """부담이 큰 운동을 저충격 대안으로 바꾼다. 남는 것이 없으면 대안만 남는다."""
    if not cautions:
        return parts
    kept = [part for part in parts if not _avoids(part[0], cautions)]
    if len(kept) == len(parts):
        return parts
    alternatives = [
        (_STRETCH[0], _STRETCH[1], 2),
        (_CARDIO_EASY[0], _CARDIO_EASY[1], 2),
    ]
    for alternative in alternatives:
        if not any(part[0] == alternative[0] for part in kept):
            kept.append(alternative)
        if len(kept) >= len(parts):
            break
    return kept or alternatives


def _caution_suffix(
    cautions: list[str], escalate: bool, locale: Locale = "ko"
) -> str:
    """근거 문장에 붙일 안전 메모. 트레이너가 무엇이 반영됐는지 읽는 자리다."""
    parts: list[str] = []
    if cautions:
        if locale == "en":
            names = ", ".join(_EN_CAUTION_PARTS.get(c, c) for c in cautions)
            parts.append(
                f" Cautions ({names}) applied: removed movements that load "
                "those areas."
            )
        else:
            parts.append(f" 주의사항({', '.join(cautions)}) 반영: 해당 부위 부담 동작을 뺐어요.")
    if escalate:
        parts.append(
            localized(
                " 강도는 올리지 않았어요 — 전문가 확인 후 조정해 주세요.",
                " Intensity was not raised — adjust after a professional check.",
                locale,
            )
        )
    return "".join(parts)


def exercise_name(name: str, locale: Locale = "ko") -> str:
    """라이브러리 운동 이름을 [locale] 로. 라이브러리 밖 이름은 그대로다(#2301)."""
    if locale == "en":
        return _EN_EXERCISE_NAMES.get(name, name)
    return name


def _localize_exercises(items: list[dict], locale: Locale) -> list[dict]:
    """구성이 끝난 운동 목록의 이름만 [locale] 로 옮긴다. 시간·유형은 그대로다."""
    if locale != "en":
        return items
    return [{**item, "name": exercise_name(item["name"], locale)} for item in items]


def _guess_type(name: str) -> str:
    if any(keyword in name for keyword in _STRETCH_KEYWORDS):
        return "스트레칭"
    if any(keyword in name for keyword in _CARDIO_KEYWORDS):
        return "유산소"
    return "근력"


def _compose(total: int, parts: list[tuple[str, str, int]]) -> list[dict]:
    """[(name, type, weight)] 를 total 분으로 가중 분배(각 ≥1, 반올림 오차는 마지막에)."""
    total = max(len(parts), total)  # 각 운동 최소 1분 보장
    tw = sum(w for _, _, w in parts) or 1
    used = 0
    out: list[dict] = []
    for i, (name, type_, w) in enumerate(parts):
        if i == len(parts) - 1:
            m = max(1, total - used)
        else:
            m = max(1, round(total * w / tw))
            used += m
        out.append({"name": name, "minutes": m, "type": type_})
    return out


def _clip_rationale(text: str) -> str:
    """[RATIONALE_MAX_CHARS] 를 넘으면 끝을 줄임표로 자른다."""
    if len(text) <= RATIONALE_MAX_CHARS:
        return text
    return text[: RATIONALE_MAX_CHARS - 1] + "…"


def _note_suffix(trainer_note: str, locale: Locale = "ko") -> str:
    note = trainer_note.strip()
    if not note:
        return ""
    return localized(
        f" 트레이너 메모 반영: {note}.", f" Trainer note applied: {note}.", locale
    )


def rule_based_plans(
    *,
    goal: str,
    sodium_today_mg: int,
    avg_completion_rate: int,
    available_minutes: int,
    intensity_preference: str,
    trainer_note: str,
    frequent_exercises: list[str] | tuple[str, ...] = (),
    conditions: str = "",
    recent_messages: list[str] | tuple[str, ...] = (),
    insight_memos: list[str] | tuple[str, ...] = (),
    locale: Locale = "ko",
) -> tuple[dict, dict]:
    """결정적 규칙형 A/B. 회원 수치를 근거 문구에 인용한다.

    [locale] 은 이름·사유·근거 문장의 언어다(#2301). 구성(운동·시간·강도)은
    언어와 무관하게 같다.

    `frequent_exercises` 가 있으면(#776, 개인화 가능한 회원) 고정 라이브러리
    대신 그 운동들로 A/B 를 구성한다 — 데이터가 없는 회원과 같은 함수를 쓰되
    인자 하나로 갈리므로, 개인화 여부에 따라 별도 함수를 유지·동기화할 필요가
    없다.
    """
    # 안전 주의사항은 LLM 이 죽은 주에도 지켜야 한다(#1440). 건강 프로필의
    # 주의사항과 최근 대화를 같은 기준으로 읽어, 부담이 큰 동작을 빼고 저충격
    # 대안으로 바꾼다. 진단은 하지 않는다 — 무엇을 빼야 안전한가만 본다.
    # 채팅 감지 메모(`"09.01 무릎 불편 감지"`)도 대화와 같은 글로 읽는다(#1655).
    # 트레이너가 남겨 둔 신호라 LLM 이 죽은 주에도 그 부위는 피해야 한다.
    signals = [*recent_messages, *insight_memos]
    cautions = cautions_in(conditions, signals)
    escalate = needs_professional_check(conditions, signals)
    if frequent_exercises:
        return _pattern_based_plans(
            frequent_exercises=list(frequent_exercises),
            available_minutes=available_minutes,
            intensity_preference=intensity_preference,
            trainer_note=trainer_note,
            cautions=cautions,
            escalate=escalate,
            locale=locale,
        )

    over = sodium_today_mg > SODIUM_TARGET_MG
    low_adherence = avg_completion_rate < 50
    goal_label = goal.strip() or localized("설정된 목표", "the set goal", locale)

    # A안 — 회복·지속: 가능 시간의 ~70%, 낮은 강도, 유산소+스트레칭 중심.
    total_a = min(available_minutes, max(5, round(available_minutes * 0.7)))
    parts_a = [(_CARDIO_EASY[0], _CARDIO_EASY[1], 3), (_STRETCH[0], _STRETCH[1], 2)]
    if over or low_adherence:
        # 부담을 더 낮추고 스트레칭 비중을 키운다.
        parts_a = [
            (_CARDIO_EASY[0], _CARDIO_EASY[1], 2),
            (_STRETCH[0], _STRETCH[1], 2),
            (_STRETCH2[0], _STRETCH2[1], 1),
        ]
    plan_a = {
        "key": "A",
        "label": localized("회복·지속 중심", "Recovery & consistency", locale),
        "total_minutes": total_a,
        "intensity": "낮음",
        "exercises": _localize_exercises(
            _compose(total_a, _safe_parts(parts_a, cautions)), locale
        ),
        "reason": localized(
            "짧고 지속하기 쉬운 회복 중심 루틴",
            "A short, easy-to-sustain recovery routine",
            locale,
        ),
        "rationale": _clip_rationale(
            localized(
                f"오늘 나트륨 {sodium_today_mg}mg"
                f"{' (목표 초과)' if over else ''}, 최근 운동 완료율 "
                f"{avg_completion_rate}% → 부담이 적은 유산소·스트레칭으로 지속 가능성에 집중.",
                f"Sodium today {sodium_today_mg} mg"
                f"{' (over goal)' if over else ''}, recent workout completion "
                f"{avg_completion_rate}% → focusing on consistency with "
                "low-strain cardio and stretching.",
                locale,
            )
            + _note_suffix(trainer_note, locale)
            + _caution_suffix(cautions, escalate, locale)
        ),
    }

    # B안 — 입력한 가능 시간 전부, 근력+유산소 중심. 강도 선호는 운동
    # 강도를 조절하는 값이지 트레이너가 입력한 시간 계약을 바꾸지 않는다.
    total_b = available_minutes
    parts_b = [
        (_CARDIO_HARD[0], _CARDIO_HARD[1], 3),
        (_STRENGTH[0], _STRENGTH[1], 2),
        (_STRENGTH2[0], _STRENGTH2[1], 1),
    ]
    plan_b = {
        "key": "B",
        "label": localized("강도·운동량 중심", "Intensity & volume", locale),
        "total_minutes": total_b,
        # 판단이 어려운 상태에서는 강도를 올리지 않는다.
        "intensity": "보통" if escalate else _B_LABEL.get(intensity_preference, "높음"),
        "exercises": _localize_exercises(
            _compose(total_b, _safe_parts(parts_b, cautions)), locale
        ),
        "reason": localized(
            "운동량과 강도를 높인 루틴",
            "A routine with more volume and intensity",
            locale,
        ),
        "rationale": _clip_rationale(
            localized(
                f"목표 '{goal_label}' 기준, 완료율 {avg_completion_rate}%로 "
                f"{'상향 여력이 있어' if avg_completion_rate >= 60 else '점진적으로'} "
                f"근력·유산소를 더해 운동량을 높임.",
                f"Based on the goal '{goal_label}' and a {avg_completion_rate}% "
                "completion rate, "
                f"{'there is room to step up — adding' if avg_completion_rate >= 60 else 'gradually adding'} "
                "strength and cardio to raise the workload.",
                locale,
            )
            + _note_suffix(trainer_note, locale)
            + _caution_suffix(cautions, escalate, locale)
        ),
    }
    return plan_a, plan_b


def _pattern_based_plans(
    *,
    frequent_exercises: list[str],
    available_minutes: int,
    intensity_preference: str,
    trainer_note: str,
    cautions: list[str] | None = None,
    escalate: bool = False,
    locale: Locale = "ko",
) -> tuple[dict, dict]:
    """반복 패턴이 확인된 회원용 A/B(#776).

    A안 — 기존 패턴 유지형: 반복 확인된 운동을 그대로 구성한다.
    B안 — 점진적 강화형: 같은 핵심 운동에 하나만 더해 운동량을 소폭 늘린다.
    두 안 모두 완전히 새로운 루틴을 만들지 않는다는 이슈의 요구를 반영한다.
    """
    safe = list(cautions or [])
    # 반복해 온 운동이라도 지금 아픈 부위에 부담이 되면 그대로 다시 내밀지
    # 않는다(#1440).
    core = [name for name in frequent_exercises if not _avoids(name, safe)][:3]
    if not core:
        core = frequent_exercises[:1]
    core_parts = _safe_parts([(name, _guess_type(name), 2) for name in core], safe)
    core_label = ", ".join(core)
    intensity_label = _B_LABEL.get(intensity_preference, "보통")

    # A안은 요청 시간의 ~75%만 쓴다 — 기존 패턴 그대로이되, "유지"와 "확대"가
    # 시간상으로도 구분돼야 한다(전체 A/B 계약이 기대하는 a < b, #776).
    # B안은 요청 시간 전부를 쓴다.
    total_a = min(available_minutes, max(len(core_parts), round(available_minutes * 0.75)))
    plan_a = {
        "key": "A",
        "label": localized("기존 패턴 유지형", "Keep current pattern", locale),
        "total_minutes": total_a,
        "intensity": intensity_label,
        "exercises": _localize_exercises(_compose(total_a, core_parts), locale),
        "reason": localized(
            "최근 자주 수행한 운동을 그대로 유지",
            "Keeps the exercises done most often recently",
            locale,
        ),
        "rationale": _clip_rationale(
            localized(
                f"최근 기록에서 반복 확인된 운동({core_label})을 유지하고 "
                "부족한 부분만 보완.",
                f"Keeps the exercises repeated in recent records ({core_label}) "
                "and fills in only what is missing.",
                locale,
            )
            + _note_suffix(trainer_note, locale)
            + _caution_suffix(safe, escalate, locale)
        ),
    }

    # 이미 핵심으로 쓴 운동은 제외하고 라이브러리에서 하나만 더한다 — 셋 다
    # 겹치는 것은 사실상 없지만(반복 기록은 자유 텍스트, 라이브러리는 고정
    # 한국어 이름), 겹쳐도 첫 후보로 안전하게 넘어가게 기본값을 둔다.
    extra_pool = (_STRENGTH, _CARDIO_HARD, _STRENGTH2, _STRETCH, _CARDIO_EASY)
    extra_name, extra_type = next(
        (
            (name, type_)
            for name, type_ in extra_pool
            if name not in core and not _avoids(name, safe)
        ),
        (_STRETCH[0], _STRETCH[1]),
    )
    total_b = available_minutes
    plan_b = {
        "key": "B",
        "label": localized("점진적 강화형", "Gradual progression", locale),
        "total_minutes": total_b,
        "intensity": "보통" if escalate else _B_LABEL.get(intensity_preference, "높음"),
        "exercises": _localize_exercises(
            _compose(total_b, [*core_parts, (extra_name, extra_type, 1)]), locale
        ),
        "reason": localized(
            "기존 핵심 운동을 유지하며 운동량을 소폭 확대",
            "Keeps the core exercises and slightly raises the workload",
            locale,
        ),
        "rationale": _clip_rationale(
            localized(
                f"기존 핵심 운동({core_label})은 유지하고 '{extra_name}'"
                f"{korean_josa.particle(extra_name, '을', '를')} 더해 "
                "운동량을 점진적으로 늘림.",
                f"Keeps the core exercises ({core_label}) and adds "
                f"'{exercise_name(extra_name, locale)}' to gradually raise the "
                "workload.",
                locale,
            )
            + _note_suffix(trainer_note, locale)
            + _caution_suffix(safe, escalate, locale)
        ),
    }
    return plan_a, plan_b


#: 판단 결과에 보여 줄 부위별 대표 동작(#3280). [_CAUTION_RULES] 의 낱말 조각은
#: 판단용이라 `러닝·런닝·달리기` 처럼 같은 동작이 겹친다 — 화면에는 서로 다른
#: 동작 셋을 운동 이름으로 보인다. 데모(`demo_routine_rules.dart`)도 같은 표다.
_CAUTION_EXAMPLES = {
    "무릎": "러닝·점프·스쿼트",
    "허리": "데드리프트·윗몸일으키기·점프",
    "어깨": "오버헤드 프레스·푸시업·풀업",
    "발목": "러닝·점프·줄넘기",
}

#: 판단 결과 한 줄의 근거 글 묶음 — (화면 이름 ko, en, 글 목록). 글 목록은
#: 가장 최근 것이 먼저 오게 넘긴다(#3280).
FindingSource = tuple[str, str, list[str] | tuple[str, ...]]

#: 메모·피드백 줄 앞의 `"MM.dd"` — 근거 날짜로 쓴다. 대화 줄에는 날짜가 없다.
_LINE_DATE = re.compile(r"^(\d{2}\.\d{2})")


def _first_hit(
    sources: list[FindingSource], keywords: tuple[str, ...]
) -> tuple[FindingSource, str, str] | None:
    """[keywords] 가 처음 보이는 (자료, 줄, 걸린 낱말). 앞 자료가 먼저다."""
    for source in sources:
        for line in source[2]:
            for keyword in keywords:
                if keyword in line:
                    return source, line, keyword
    return None


def _source_label(source: FindingSource, line: str, locale: Locale) -> str:
    name = localized(source[0], source[1], locale)
    matched = _LINE_DATE.match(line.strip())
    return f"{name} · {matched.group(1)}" if matched else name


def rule_findings(
    *,
    sources: list[FindingSource],
    frequent_exercises: list[str] | tuple[str, ...],
    history_session_count: int,
    analysis_period_days: int,
    sodium_today_mg: int,
    avg_completion_rate: int,
    locale: Locale = "ko",
) -> list[dict]:
    """서버가 이번 생성에서 **찾은 것**과 그에 따른 **반영 방향**(#3280).

    [rule_based_plans] 와 같은 규칙·같은 갈림으로 센다 — 화면이 "무엇을 보고
    어떻게 판단했는지" 를 근거 문장(`rationale`)을 잘라 읽지 않고 항목으로
    보여 주기 위해서다. 같은 분석을 받는 AI 경로에도 같은 목록을 싣는다. AI 는
    이 신호를 같은 지시(통증 부위 회피·판단이 어려우면 강도 유지)로 받는다.

    [sources] 는 주의사항으로 읽는 자료를 화면 이름과 함께, 먼저 볼 순서로
    넘긴다. 진단은 하지 않는다 — 어느 글에 무엇이 보였는지만 말한다.
    """
    out: list[dict] = []
    for part, keywords, risky in _CAUTION_RULES:
        hit = _first_hit(sources, keywords)
        if hit is None:
            continue
        source, line, _ = hit
        part_en = _EN_CAUTION_PARTS.get(part, part)
        moves = _CAUTION_EXAMPLES.get(part, "·".join(risky[:3]))
        out.append({
            "kind": "caution",
            "finding": localized(
                f"{part} 불편·통증 언급", f"Mentions {part_en} discomfort", locale
            ),
            "source": _source_label(source, line, locale),
            "action": localized(
                f"{part}에 부담이 큰 동작({moves} 등)을 빼고 저충격 대안으로",
                f"Removes movements that load the {part_en} and uses "
                "low-impact alternatives",
                locale,
            ),
        })
    escalation = _first_hit(sources, _ESCALATION_KEYWORDS)
    if escalation is not None:
        source, line, keyword = escalation
        out.append({
            "kind": "escalation",
            "finding": localized(
                f"전문가 확인이 필요한 언급({keyword})",
                "Mentions a symptom that needs a professional check",
                locale,
            ),
            "source": _source_label(source, line, locale),
            "action": localized(
                "강도를 올리지 않음 — 전문가 확인 후 조정",
                "Does not raise intensity — adjust after a professional check",
                locale,
            ),
        })

    records = localized("운동 기록", "Workout records", locale)
    if frequent_exercises:
        names = ", ".join(frequent_exercises)
        out.append({
            "kind": "pattern",
            "finding": localized(
                f"반복한 운동: {names}", f"Repeated exercises: {names}", locale
            ),
            "source": localized(
                f"{records} · 최근 {analysis_period_days}일 {history_session_count}회",
                f"{records} · last {analysis_period_days} days, "
                f"{history_session_count} sessions",
                locale,
            ),
            "action": localized(
                "A안은 이 운동을 그대로 유지, B안은 하나를 더해 운동량 확대",
                "Plan A keeps these; plan B adds one to raise the workload",
                locale,
            ),
        })
        return out

    # 반복 패턴이 없는 회원만 완료율·나트륨으로 A안 부담을 가른다
    # ([rule_based_plans] 의 목표 기반 갈림과 같다).
    over = sodium_today_mg > SODIUM_TARGET_MG
    if over:
        out.append({
            "kind": "sodium",
            "finding": localized(
                f"오늘 나트륨 {sodium_today_mg}mg (목표 초과)",
                f"Sodium today {sodium_today_mg} mg (over goal)",
                locale,
            ),
            "source": localized("식단 기록 · 오늘", "Diet records · today", locale),
            "action": localized(
                "A안 부담을 낮추고 스트레칭 비중 확대",
                "Plan A lowers the load and adds more stretching",
                locale,
            ),
        })
    if avg_completion_rate < 50:
        action = localized(
            "A안 부담을 낮추고 스트레칭 비중 확대",
            "Plan A lowers the load and adds more stretching",
            locale,
        )
    elif avg_completion_rate >= 60:
        action = localized(
            "상향 여력이 있어 B안에서 운동량을 높임",
            "Room to step up — plan B raises the workload",
            locale,
        )
    else:
        action = localized(
            "B안은 운동량을 점진적으로 높임",
            "Plan B raises the workload gradually",
            locale,
        )
    out.append({
        "kind": "adherence",
        "finding": localized(
            f"평균 완료율 {avg_completion_rate}%",
            f"Average completion {avg_completion_rate}%",
            locale,
        ),
        "source": records,
        "action": action,
    })
    return out
