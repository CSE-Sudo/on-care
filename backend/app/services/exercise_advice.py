"""운동 AI 맞춤 조언 한 마디 — 문장 키·값과 한국어 문장. (#2210)

조언은 예전에 한국어 문장 하나로만 나갔다. 영어로 앱을 쓰는 회원도 이 카드만은
한국어로 읽었다. 이제 조언을 **로케일과 무관한 키와 값**으로도 내보내고, 앱이 자기
번역(ARB)으로 문장을 그린다 — 홈 통합 조언(`ai_advice_key`, #1943)과 같은 방식이다.

한국어 문장(`message`)은 계속 함께 나간다. 키를 모르는 옛 앱과 트레이너웹이 그것을
읽는다. 그 문장은 아래 틀(`_KO`) 하나에서만 만든다 — 앱의 한국어 ARB 가 같은 틀을
옮겨 적고, 두 쪽이 글자까지 같은지는 공유 사례
(`frontend/flutter/test/core/demo/routine_advice_cases.json`)로 확인한다.

**값은 로케일과 무관하다.** 운동 유형은 코드(`cardio`), 부위는 코드(`lower`),
운동 이름은 트레이너가 적은 그대로다. 한국어 조사(을/를, 이/가)는 언어의 몫이라
값에 싣지 않고, 한국어 문장을 그릴 때 이름을 보고 붙인다(앱도 같다).
"""
from __future__ import annotations

from dataclasses import dataclass, field

from app.services import exercise_types

#: 운동 이름이 드는 값. 한국어 틀은 `{done_obj}`(을/를)·`{done_subj}`(이/가)처럼
#: 이름 뒤 조사를 따로 받는다.
_NAME_PARAMS = ("done", "next", "then", "name")
#: 운동 유형 코드가 드는 값. 한국어 틀은 `{top_label}`·`{top_subj}` 를 받는다.
_TYPE_PARAMS = ("type", "top", "missing")

#: 부위 코드 → 한국어. 코드는 `routine_advice` 의 부위 판정과 같다.
PART_LABELS_KO = {"lower": "하체", "upper": "상체", "core": "코어", "full": "전신"}

_REST_KO = {"remaining": "남은 날엔", "next_week": "다음 주엔"}
_KEEP_KO = {"remaining": "남은 날도 이어 가요.", "next_week": "다음 주도 이어 가요."}
_HOW_KO = {"even": "고르게", "steady": "꾸준히"}

#: 키 → 한국어 틀. 앱의 `app_ko.arb`(`exerciseAdvice…`)가 같은 문장을 적는다 —
#: 한쪽을 고치면 다른 쪽도 함께 고친다.
_KO: dict[str, str] = {
    # 직접 기록 기준 (#1025, #1574)
    "record_empty_today": "오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?",
    "record_empty_week": "이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?",
    "record_empty_all": "기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요.",
    "record_today": "오늘 {type_label} 위주로 {minutes}분, {calories}kcal 썼어요. 스트레칭으로 마무리해요.",
    "record_week_one_day": "이번 주는 {minutes}분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요.",
    "record_week_skew": "이번 주 {days}일 {minutes}분이 {top_label}에 몰렸어요. {missing_label}도 섞어 볼까요?",
    "record_week_balanced": "이번 주 {days}일 {minutes}분, 유형도 고르게 섞였어요.",
    "record_all_up": "최근 4주 운동량이 그 전보다 늘었어요. 지금 방식이 잘 맞아요.",
    "record_all_down": "최근 4주 운동량이 줄고 있어요. 짧게라도 주 3일을 지켜 봐요.",
    "record_all_steady": "{weeks}주 동안 {days}일 {minutes}분, 기복 없이 이어가고 있어요.",
    # 추천 개인운동 기준 — 오늘 (#2162)
    "routine_today_all_done": "오늘 추천 운동 {count}개를 모두 마쳤어요. 잘했어요!",
    "routine_today_done_next_order": "{done}{done_obj} 마쳤어요. 다음은 {next} → {then} 순서로 해 보세요.",
    "routine_today_done_next": "{done}{done_obj} 마쳤어요. 다음은 {next} 차례예요.",
    "routine_today_next_order": "다음은 {next} → {then} 순서로 해 보세요.",
    "routine_today_next": "다음은 {next} 차례예요.",
    "routine_today_left": "남은 추천 운동이 {count}개예요. 목록 순서대로 해 보세요.",
    "routine_today_start_order": "오늘 추천 운동은 {next} → {then} 순서로 시작해 보세요.",
    "routine_today_start": "오늘은 {next}부터 시작해 보세요.",
    # 이번 주
    "routine_week_none_today": "이번 주엔 추천 운동을 아직 안 했어요. 오늘 {next}부터 해 볼까요?",
    "routine_week_none_next": "이번 주엔 추천 운동을 아직 안 했어요. {next}부터 해 봐요.",
    "routine_week_none": "이번 주엔 추천 운동을 아직 안 했어요. 오늘 하나부터 해 봐요.",
    "routine_week_only": "이번 주엔 {top_label} 추천 운동만 했어요. {rest_ko} {missing_label}부터 해 보세요.",
    "routine_week_only_short": "이번 주엔 {top_label} 추천 운동만 했어요.",
    "routine_week_skew": "이번 주 추천 운동 중 {top_label}{top_subj} {share}%예요. {rest_ko} {missing_label}부터 해 보세요.",
    "routine_week_skew_short": "이번 주 추천 운동은 {top_label}{top_subj} {share}%예요.",
    "routine_week_praise": "이번 주 추천 운동을 {how_ko} 해냈어요. 이대로 이어 가요!",
    "routine_week_counts_today": "이번 주 추천 운동 {assigned}개 중 {completed}개를 했어요. 오늘 {next}부터 이어 가요.",
    "routine_week_counts_keep": "이번 주 추천 운동 {assigned}개 중 {completed}개를 했어요. {keep_ko}",
    "routine_week_counts": "이번 주 추천 운동 {assigned}개 중 {completed}개를 했어요.",
    # 지난주 회고 (월·화)
    "routine_last_week_none_next": "지난주엔 추천 운동을 못 했어요. 이번 주는 {next}부터 해 봐요.",
    "routine_last_week_none": "지난주엔 추천 운동을 못 했어요. 이번 주는 하나씩 해 봐요.",
    "routine_last_week_only": "지난주엔 {top_label} 추천 운동만 했어요. 이번 주는 {missing_label}부터 해 보세요.",
    "routine_last_week_only_short": "지난주엔 {top_label} 추천 운동만 했어요.",
    "routine_last_week_skew": "지난주 추천 운동 중 {top_label}{top_subj} {share}%였어요. 이번 주는 {missing_label}부터 해 보세요.",
    "routine_last_week_skew_short": "지난주 추천 운동은 {top_label}{top_subj} {share}%였어요.",
    "routine_last_week_praise": "지난주 추천 운동을 {how_ko} 해냈어요. 이번 주도 이어 가요!",
    "routine_last_week_counts_more": "지난주 추천 운동 {assigned}개 중 {completed}개를 했어요. 이번 주는 더 채워 봐요.",
    "routine_last_week_counts": "지난주 추천 운동 {assigned}개 중 {completed}개를 했어요.",
    # 전체
    "routine_all_new": "추천 목록을 받은 지 {days}일째예요. 일주일 뒤 빠진 운동을 짚어 드릴게요.",
    "routine_all_none_next": "추천 목록을 받은 지 {days}일째예요. 오늘 {next}부터 시작해 볼까요?",
    "routine_all_none": "추천 목록을 받은 지 {days}일째예요. 오늘 하나부터 시작해 봐요.",
    "routine_all_done_today_part": "자주 빠지던 {part_ko} 운동을 오늘 해냈어요. 이대로 이어 가요!",
    "routine_all_done_today_name": "자주 빠지던 {name}{name_obj} 오늘 해냈어요. 이대로 이어 가요!",
    "routine_all_done_today_name_plain": "자주 빠지던 {name}, 오늘 해냈어요. 이대로 이어 가요!",
    "routine_all_done_today": "자주 빠지던 운동을 오늘 해냈어요. 이대로 이어 가요!",
    "routine_all_missed_part": "추천 운동 중 {part_ko} 운동이 자주 빠졌어요. {part_ko} 운동을 먼저 해 볼까요?",
    "routine_all_missed_part_short": "{part_ko} 추천 운동이 자주 빠졌어요. 먼저 하는 순서로 바꿔 볼까요?",
    "routine_all_missed_name": "추천 운동 중 {name}{name_subj} 자주 빠졌어요. 다음엔 먼저 해 볼까요?",
    "routine_all_missed_name_short": "{name}{name_subj} 자주 빠졌어요. 먼저 해 볼까요?",
    "routine_all_missed_name_plain": "추천 운동 {name}, 자주 빠졌어요. 다음엔 먼저 해 볼까요?",
    "routine_all_missed_name_plain_short": "{name}, 자주 빠졌어요. 먼저 해 볼까요?",
    "routine_all_missed": "자주 빠진 추천 운동이 있어요. 목록 순서를 바꿔 볼까요?",
    "routine_all_praise": "추천 운동을 {weeks}주째 꾸준히 하고 있어요. 앞으로도 화이팅!",
    "routine_all_rate": "지금 추천 운동의 {pct}%를 했어요. 빠지는 날 없이 이어 가 봐요.",
}

#: 모든 키. 앱의 번역 테스트가 이 목록을 빠짐없이 그리는지 본다.
KEYS: tuple[str, ...] = tuple(_KO)


def has_final_consonant(word: str) -> bool | None:
    """마지막 글자에 받침이 있나. 한글로 끝나지 않으면 None — 조사를 정할 수 없다."""
    stripped = word.rstrip(" )]}")
    if not stripped:
        return None
    last = ord(stripped[-1])
    if not 0xAC00 <= last <= 0xD7A3:
        return None
    return (last - 0xAC00) % 28 != 0


def _particle(word: str, with_final: str, without_final: str) -> str:
    """받침에 맞는 조사. 정할 수 없는 이름은 `_plain` 키로 가므로 여기 오지 않지만,
    오면 두 꼴을 함께 적는다."""
    final = has_final_consonant(word)
    if final is None:
        return f"{with_final}({without_final})"
    return with_final if final else without_final


def _ko_fields(params: dict[str, str | int]) -> dict[str, str | int]:
    """한국어 틀이 받는 값 — 원래 값에 라벨과 조사를 더한다."""
    fields: dict[str, str | int] = dict(params)
    for key in _NAME_PARAMS:
        if isinstance(params.get(key), str):
            name = str(params[key])
            fields[f"{key}_obj"] = _particle(name, "을", "를")
            fields[f"{key}_subj"] = _particle(name, "이", "가")
    for key in _TYPE_PARAMS:
        if key in params:
            label = exercise_types.label_for(str(params[key]))
            fields[f"{key}_label"] = label
            fields[f"{key}_subj"] = _particle(label, "이", "가")
    if "part" in params:
        fields["part_ko"] = PART_LABELS_KO[str(params["part"])]
    if "rest" in params:
        fields["rest_ko"] = _REST_KO[str(params["rest"])]
        fields["keep_ko"] = _KEEP_KO[str(params["rest"])]
    if "how" in params:
        fields["how_ko"] = _HOW_KO[str(params["how"])]
    return fields


@dataclass(frozen=True)
class Advice:
    """조언 한 마디 — 문장 키, 로케일과 무관한 값, 한국어 문장."""

    key: str
    params: dict[str, str | int] = field(default_factory=dict)

    @property
    def text(self) -> str:
        return _KO[self.key].format(**_ko_fields(self.params))


def advice(key: str, **params: str | int) -> Advice:
    if key not in _KO:
        raise KeyError(f"모르는 조언 키: {key}")
    return Advice(key=key, params=params)
