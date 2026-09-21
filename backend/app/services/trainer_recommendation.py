"""회원 신호 기반 트레이너 추천 점수. (#500)

`/trainers/recommended` 는 `TrainerProfile.recommend_reason` 이 비어 있지 않은
행을 그대로 돌려줬다. 그 사유는 시드에 사람이 써 넣은 문자열이라 **어떤 회원이
보든 같은 트레이너가 같은 순서로** 나왔다. README 가 말하는 "회원의 목표와 조건에
맞춘 추천" 이 실제로는 고정 목록이었다.

여기서 쓰는 신호는 전부 이미 DB 에 있다 — 새로 수집하는 것이 없다.

  회원   `HealthProfile.conditions`(온보딩 건강 목표) · `goals` ·
         가장 최근 `ConsultationRequest.exercise_goal` · `MemberGym`(내 헬스장)
  트레이너 `TrainerProfile.specialty` · `intro` · `career_years` ·
         `gym_id` → `places.lat/lng`

**왜 점수를 설명 가능하게 두는가.** 추천은 회원이 사람을 고르는 자리다. 순위가
왜 이렇게 나왔는지 코드에서 답할 수 없으면 화면의 "추천" 이라는 말이 근거를 잃는다.
그래서 가중치를 상수로 두고, 화면에 붙는 사유 문자열도 **점수를 만든 그 항목에서**
생성한다.

**한계(의도적).** 트레이너의 전문 분야는 `specialty`·`intro`·`recommend_reason`
자유 텍스트뿐이라 키워드 매칭에 기댄다. 트레이너 앱이 구조화된 전문 분야를
입력받게 되면 이 매칭은 그 값을 보도록 바뀌어야 한다 — 그때까지의 근사다.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.services import health_focus
from app.models.models import (
    ConsultationRequest,
    HealthProfile,
    MemberGym,
    Place,
    TrainerProfile,
    User,
)

#: 가중치. 합이 100 이라 각 항목이 순위에 얼마나 기여하는지 눈으로 읽힌다.
#:
#: 같은 헬스장을 가장 크게 둔 이유: 회원이 이미 그곳에 다니고 있다는 뜻이라
#: 실제로 만나서 지도받을 수 있다. 목표 일치가 그다음이고, 거리는 같은 헬스장이
#: 아닐 때의 대체 신호다. 경력은 동점을 가르는 정도로만 둔다 — 경력이 길다고 이
#: 회원에게 맞는 것은 아니다.
#:
#: **단일 항목이 아니라 합산이다.** 같은 헬스장이 최대 가중치지만 목표 일치와
#: 거리의 합이 그것을 넘을 수 있다 — 1km 떨어진 목표 적합 트레이너가 같은
#: 헬스장의 무관한 트레이너를 앞서는 것은 의도한 동작이다. "같은 헬스장이면 무조건
#: 1등" 을 원한다면 이 값이 아니라 정렬 자체를 계층으로 바꿔야 한다.
W_SAME_GYM = 40
W_GOAL = 30
W_DISTANCE = 25
W_CAREER = 5

#: 거리 점수가 0 이 되는 지점(km). 이보다 멀면 거리로는 가점이 없다.
_DISTANCE_ZERO_KM = 10.0

#: 경력 점수가 만점이 되는 연차. 이보다 길어도 더 오르지 않는다.
_CAREER_FULL_YEARS = 10


@dataclass(frozen=True)
class _Need:
    """회원의 관리 needs 하나 — 사유 문구용 라벨과 매칭용 동의어."""

    label: str
    keywords: tuple[str, ...]


#: 건강 목표(`health_focus.FOCUS_OPTIONS`) → needs. (#1814)
#:
#: 옛 질환 이름(고혈압·비만)으로 저장된 값은 [normalize_conditions] 가 새 목표로
#: 바꾼 뒤 찾는다. 상담 신청의 운동 목표와 라벨이 같아 [_dedup] 가 하나로 합친다.
#:
#: 동의어는 **트레이너가 실제로 쓰는 말**에서 가져온다. 사전에 없는 표현을 쓴
#: 트레이너는 목표 일치 30점을 통째로 못 받아 거리·경력만으로 줄 세워진다 —
#: `체력 강화`·`혈압 관리` 는 한때 데모 트레이너 14명 중 누구와도 매칭되지
#: 않았다(#2121). 선택지를 늘리거나 시드 문구를 고칠 때는
#: `test_every_focus_matches_someone` 가 이 대조를 대신 해 준다.
_CONDITION_NEEDS: dict[str, _Need] = {
    health_focus.FOCUS_WEIGHT_LOSS: _Need(
        "체중 감량", ("체중", "감량", "다이어트", "체지방", "체성분")
    ),
    health_focus.FOCUS_STRENGTH: _Need(
        "근력 향상", ("근력", "근육", "웨이트", "스트렝스", "파워리프팅")
    ),
    health_focus.FOCUS_FITNESS: _Need(
        "체력 강화", ("체력", "컨디셔닝", "지구력", "유산소", "러닝", "달리기")
    ),
    health_focus.FOCUS_POSTURE: _Need(
        "자세 교정", ("자세", "체형", "교정", "스트레칭")
    ),
    health_focus.FOCUS_REHAB: _Need(
        "재활", ("재활", "통증", "부상", "수술", "회복", "물리치료")
    ),
    health_focus.FOCUS_EATING: _Need(
        "식습관 개선", ("식단", "식습관", "영양", "식사")
    ),
    health_focus.FOCUS_EXERCISE_HABIT: _Need(
        "운동 습관", ("입문", "초보", "습관", "처음", "기구", "출석")
    ),
    health_focus.FOCUS_BLOOD_PRESSURE: _Need(
        "혈압 관리", ("혈압", "고혈압", "심혈관", "유산소")
    ),
}

#: 상담 요청의 `exercise_goal`(Literal) → needs.
#:
#: 상담 운동 목표가 건강 목표 여덟 종과 1:1 이 되면서(#1992) 표를 따로 들 이유가
#: 없어졌다 — [_CONDITION_NEEDS] 를 그대로 잇는다. 예전처럼 두 표를 나란히 두면
#: 한쪽만 고쳐져 같은 목표가 다른 needs 로 갈린다.
_EXERCISE_GOAL_NEEDS: dict[str, _Need] = {
    code: _CONDITION_NEEDS[focus]
    for code, focus in health_focus.EXERCISE_GOAL_FOCUS.items()
}
#: 없앤 선택지지만 이미 저장된 요청에 남아 있다. 건강 목표로는 잇지 않으므로
#: (`EXERCISE_GOAL_FOCUS`) 여기서만 needs 를 만든다.
#:
#: 'other' 는 무엇을 원하는지 알려주는 바가 없어 needs 로 만들지 않는다 — 그 회원은
#: 거리·경력만으로 점수가 나거나, 신호가 하나도 없으면 기존 순서로 되돌아간다.
_EXERCISE_GOAL_NEEDS["health"] = _Need("건강 관리", ("건강", "재활"))


@dataclass
class MemberSignals:
    """추천에 쓸 회원 쪽 신호. 하나도 없으면 점수를 낼 수 없다."""

    gym_id: str | None = None
    lat: float | None = None
    lng: float | None = None
    needs: list[_Need] = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        """점수를 낼 근거가 하나도 없는가.

        온보딩 전이거나 건강 목표·상담 이력·내 헬스장이 모두 없는 회원이다. 이때는
        무엇을 기준으로 줄 세워도 근거가 없으므로 기존 동작으로 되돌린다.
        """
        return self.gym_id is None and self.lat is None and not self.needs


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """두 좌표 사이 거리(km). `gym_service._haversine_m` 과 같은 계산."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.asin(math.sqrt(a))


def _dedup(needs: list[_Need]) -> list[_Need]:
    """같은 라벨의 needs 를 하나로. 체중 감량(온보딩)과 weight_loss(상담)는 같은 것이다."""
    seen: set[str] = set()
    out: list[_Need] = []
    for need in needs:
        if need.label in seen:
            continue
        seen.add(need.label)
        out.append(need)
    return out


def collect_member_signals(db: Session, member_id: str) -> MemberSignals:
    """회원의 추천 신호를 모은다. 쿼리는 회원당 상수개."""
    signals = MemberSignals()

    profile = db.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    needs: list[_Need] = []
    if profile is not None:
        # conditions 는 앱이 ', ' 로 이어 보낸 건강 목표다. 옛 질환 이름은 새
        # 목표로 읽는다(#1814).
        for focus in health_focus.focus_in(profile.conditions):
            need = _CONDITION_NEEDS.get(focus)
            if need is not None:
                needs.append(need)
        # goals 는 자유 서술이라 키워드가 그대로 들어 있으면 그 needs 로 본다.
        goals_text = (profile.goals or "").strip()
        if goals_text:
            for need in (*_CONDITION_NEEDS.values(), *_EXERCISE_GOAL_NEEDS.values()):
                if any(k in goals_text for k in need.keywords):
                    needs.append(need)

    # 가장 최근 상담 요청의 운동 목표 — 회원이 직접 고른 값이라 신뢰도가 높다.
    goal = db.scalar(
        select(ConsultationRequest.exercise_goal)
        .where(ConsultationRequest.member_id == member_id)
        .order_by(ConsultationRequest.id.desc())
        .limit(1)
    )
    if goal is not None:
        need = _EXERCISE_GOAL_NEEDS.get(goal)
        if need is not None:
            needs.append(need)

    signals.needs = _dedup(needs)

    gym_id = db.scalar(select(MemberGym.gym_id).where(MemberGym.member_id == member_id))
    if gym_id is not None:
        signals.gym_id = gym_id
        place = db.get(Place, gym_id)
        if place is not None:
            signals.lat, signals.lng = place.lat, place.lng
    return signals


@dataclass(frozen=True)
class Scored:
    """한 트레이너의 점수와 그 근거."""

    score: float
    #: 점수를 만든 항목에서 뽑은 사유 문구. 근거가 없으면 빈 문자열.
    reason: str


def score_trainer(
    signals: MemberSignals,
    profile: TrainerProfile,
    gym: Place | None,
) -> Scored:
    """회원 신호에 대한 트레이너 적합도. 0~100."""
    score = 0.0
    reasons: list[str] = []

    if signals.gym_id is not None and profile.gym_id == signals.gym_id:
        score += W_SAME_GYM
        reasons.append("회원님이 다니는 헬스장 소속")
    elif (
        signals.lat is not None
        and signals.lng is not None
        and gym is not None
        and gym.lat is not None
        and gym.lng is not None
    ):
        km = _haversine_km(signals.lat, signals.lng, gym.lat, gym.lng)
        if km < _DISTANCE_ZERO_KM:
            score += W_DISTANCE * (1 - km / _DISTANCE_ZERO_KM)
            reasons.append(f"{km:.1f}km 거리")

    if signals.needs:
        # 전문 분야·소개글·추천 사유를 함께 본다 — 시드처럼 specialty 가 '퍼스널
        # 트레이너' 로 일반적이고 실제 강점은 intro 나 recommend_reason 에 적혀
        # 있는 경우가 많다. recommend_reason 은 운영자가 그 트레이너의 강점을 한
        # 줄로 적어 둔 값이라 셋 중 가장 정확한데, 예전에는 점수에서만 빠져 있어
        # `혈압 관리와 운동 병행 지도` 라고 적힌 트레이너가 `혈압 관리` 회원에게
        # 0점을 받았다(#2121).
        haystack = " ".join(
            (profile.specialty or "", profile.intro or "", profile.recommend_reason or "")
        )
        matched = [
            need for need in signals.needs
            if any(k in haystack for k in need.keywords)
        ]
        if matched:
            score += W_GOAL * len(matched) / len(signals.needs)
            reasons.append(f"{matched[0].label} 지도 경험")

    years = max(profile.career_years or 0, 0)
    score += W_CAREER * min(years, _CAREER_FULL_YEARS) / _CAREER_FULL_YEARS

    # 경력만으로는 사유가 되지 않는다 — 모든 트레이너에 붙어 회원에게 아무것도
    # 알려주지 못한다. 회원과 이어지는 근거가 하나라도 있을 때만 문구를 만든다.
    return Scored(score=score, reason=" · ".join(reasons[:2]))


def rank(
    db: Session,
    member_id: str,
    candidates: list[tuple[User, TrainerProfile]],
) -> list[tuple[User, TrainerProfile, Scored]]:
    """후보를 회원 적합도 순으로. 신호가 없으면 빈 리스트(호출부가 폴백).

    정렬은 점수 내림차순이고, 동점은 **경력 → id** 로 갈라 같은 입력에 늘 같은
    순서가 나오게 한다. 동점 순서가 흔들리면 새로고침마다 추천 레일이 바뀐다.
    """
    signals = collect_member_signals(db, member_id)
    if signals.is_empty:
        return []

    gym_ids = {p.gym_id for _, p in candidates if p.gym_id is not None}
    gyms: dict[str, Place] = {}
    if gym_ids:
        gyms = {
            place.id: place
            for place in db.scalars(select(Place).where(Place.id.in_(gym_ids))).all()
        }

    scored = [
        (user, profile, score_trainer(signals, profile, gyms.get(profile.gym_id or "")))
        for user, profile in candidates
    ]
    scored.sort(
        key=lambda row: (-row[2].score, -(row[1].career_years or 0), row[0].id)
    )
    return scored
