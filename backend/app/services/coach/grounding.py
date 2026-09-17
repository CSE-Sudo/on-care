"""코치가 개인 기록으로 뒷받침할 수 있는 주제 (#602).

프롬프트가 "제공된 '내 건강 기록'에 근거해 X 를 조언하라" 고 지시하면, X 를 실제로
적재하고 있어야 한다. 안 그러면 모델은 근거 없이 그럴듯하게 답하거나 공공
가이드라인 일반론만 되풀이한다.

혈압·혈당이 정확히 그 상태였다. 프롬프트는 조언을 지시했지만 수집·저장 경로가
없다 — 입력이 번거로워 **제품에서 빼기로 한 항목**이고, 만들었다가 걷어낸 이력이
`migrations/versions/0016_drop_vitals.py` 에 남아 있다.

여기 상수를 두는 이유: 적재 도메인이 늘 때(#586 운동처럼) 프롬프트를 같이 고치는
걸 잊으면 아무도 모른다. 프롬프트가 이 목록에서 문구를 만들고, 테스트가 둘의
어긋남을 잡는다.
"""
from __future__ import annotations

#: 개인 문서로 적재돼 근거가 되는 주제. `personal_ingest` 가 적재하는 것과 맞춘다
#: — 식단(나트륨·당류), 운동, 그리고 트레이너 대화(#580).
GROUNDED_TOPICS: tuple[str, ...] = ("나트륨", "당류", "운동")

#: 수집하지 않기로 한 지표. 프롬프트에서 "근거해 조언하라" 대상이 되면 안 된다.
UNTRACKED_METRICS: tuple[str, ...] = ("혈압", "혈당")

#: 프롬프트에 넣는 주제 목록 문구.
GROUNDED_TOPIC_PHRASE = "·".join(GROUNDED_TOPICS)

#: 안 재는 지표를 물었을 때의 지침.
#:
#: 아예 말하지 말라고 하지 않는 이유: 회원이 건강 이야기를 하다 보면 그 질문은
#: 자연스럽게 나온다. 막으면 쓸모가 없고, 그냥 두면 모델이 사용자의 수치를 아는
#: 것처럼 답한다. 답하되 출처를 분명히 하게 한다.
UNTRACKED_METRIC_NOTICE = (
    f"{'·'.join(UNTRACKED_METRICS)}은 이 앱이 기록하지 않습니다. 물어보면 일반적인 "
    "가이드라인임을 밝히고 답하고, 사용자의 수치를 알고 있는 것처럼 말하지 마세요."
)

#: 질환명. 회원이나 자료가 질환을 말하는 것은 그 사람의 수치를 안다는 주장이
#: 아니다. 지표명이 문자열로 포함돼 있을 뿐이라 따로 걸러 낸다.
_CONDITION_TERMS: tuple[str, ...] = ("고혈압", "저혈압", "고혈당", "저혈당")


def mentions_untracked_metric(text: str) -> bool:
    """안 재는 지표를 **지표로서** 언급하는가.

    질환명은 세지 않는다 — 대상 집단을 밝히는 것은 근거 없는 주장이 아니다.
    """
    cleaned = text
    for term in _CONDITION_TERMS:
        cleaned = cleaned.replace(term, "")
    return any(metric in cleaned for metric in UNTRACKED_METRICS)
