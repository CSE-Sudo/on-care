"""담당 회원의 개인운동·하루 운동 기록 시드 규칙 — 트레이너 웹 데모와 같은 표·같은 셈. (#3003)

트레이너 웹 데모(`frontend/flutter_trainer/lib/core/storage/seed_clients.dart` 의
`aiRoutine`, `seed_workouts.dart`)와 실서버 시드가 같은 회원에게 같은 운동을 말하게
하는 단일 표다. 예전에는 실서버가 확장 회원 모두에게 같은 세 운동(빠르게 걷기·스쿼트·
전신 스트레칭)을 걸고, 같은 날 요일 루틴을 `member` 로 또 심어, 데모와 다른 운동을
보였다 — 하루 합계는 30분인데 줄은 전부 안 한 것으로 그려지기도 했다.

규칙(데모와 같다):

- 그날 이행률만큼 **배정 순서 앞에서부터** 완료다([done_count]). 이행률은 회원의
  요일 표(`seed_roster._METRICS` · [COMPLETION])에 주 계수를 곱한 값이다.
- 완료한 개인운동은 그 운동의 양·소모 kcal(분 × [KCAL_PER_MINUTE])·강도를 싣는다.
- 정해진 날([is_late_day])에는 마지막 완료를 다음 날 체크한 것으로 둔다 — 데모의
  `다음 날 이후 체크` 칸과 같은 날이다.
- 회원이 직접 적은 운동([MEMBER_LOGS])과 PT 수업의 운동([PT_PROGRAMS])도 같은 값이다.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date

#: 회원 → 트레이너 웹 데모의 회원 번호(`seed-client-N`). 다음 날 체크 날짜를 데모와
#: 같은 셈으로 고르는 씨앗이다.
MEMBER_NO: dict[str, int] = {
    "user-jisu": 2,
    "user-sungho": 3,
    "user-hayun": 4,
    "user-woojin": 5,
    "user-kangseoyeon": 6,
    "user-dohyun": 7,
    "user-sera": 8,
    "user-junhyuk": 9,
    "user-yuna": 10,
    "user-jiho": 11,
    "user-gayoung": 12,
    "user-taekyung": 13,
    "user-seojin": 14,
    "user-eunchae": 15,
}

#: 유형별 분당 소모 kcal — 트레이너 웹 데모(`client_repository` 의 `_DemoKind`)와
#: 같은 대략값이다. 줄을 더하면 하루 합계가 된다.
KCAL_PER_MINUTE = {"cardio": 7, "strength": 6, "stretching": 3}

#: 배정 유형(한국어) → 운동 기록 유형 코드.
TYPE_CODE = {"유산소": "cardio", "근력": "strength", "스트레칭": "stretching"}


def kcal(type_code: str, minutes: int) -> int:
    """운동 한 줄의 소모 kcal."""
    return minutes * KCAL_PER_MINUTE.get(type_code, 7)


@dataclass(frozen=True)
class SeedRoutine:
    """회원에게 걸린 개인운동 한 줄 — 데모 `_Routine` 과 같은 값."""

    name: str
    minutes: int
    #: 유산소|근력|스트레칭 — 배정의 한국어 어휘.
    type: str
    reason: str
    sets: int | None = None
    reps: int | None = None
    hold_seconds: int | None = None
    weight: float | None = None
    #: 처방 강도 — `light` | `moderate` | `high`. 회원별로 섞는다.
    intensity: str = "moderate"

    @property
    def code(self) -> str:
        return TYPE_CODE.get(self.type, "other")

    @property
    def strength(self) -> bool:
        return self.code == "strength"


def _r(name, minutes, type_, reason, *, sets=None, reps=None, hold=None,
       weight=None, intensity="moderate") -> SeedRoutine:
    return SeedRoutine(name, minutes, type_, reason, sets, reps, hold, weight, intensity)


#: 회원별 개인운동 세 줄(배정 순서). 데모 `seed_clients.dart` 의 `aiRoutine` 과 같다.
ROUTINES: dict[str, tuple[SeedRoutine, ...]] = {
    "user-jisu": (
        _r("인터벌 런닝", 25, "유산소", "체지방 연소 효율↑", intensity="high"),
        _r("스쿼트", 15, "근력", "하체 근력 강화", sets=3, reps=12, weight=40),
        _r("플랭크", 10, "근력", "코어 안정화", sets=3, hold=30),
    ),
    "user-sungho": (
        _r("벤치프레스", 20, "근력", "상체 근력 목표", sets=4, reps=8, weight=65,
           intensity="high"),
        _r("데드리프트", 15, "근력", "전신 근력 향상", sets=3, reps=8, weight=70,
           intensity="high"),
        _r("유산소 쿨다운", 10, "유산소", "나트륨 배출 지원", intensity="light"),
    ),
    "user-hayun": (
        _r("저강도 걷기", 25, "유산소", "회복기 심박 관리", intensity="light"),
        _r("골반 안정화", 15, "스트레칭", "산후 코어 재활", intensity="light"),
        _r("밴드 로우", 12, "근력", "상체 자세 교정", sets=3, reps=15),
    ),
    "user-woojin": (
        _r("LSD 러닝", 45, "유산소", "유산소 기반 다지기"),
        _r("힙 힌지 드릴", 12, "근력", "러닝 이코노미 개선", sets=3, reps=12),
        _r("종아리 스트레칭", 10, "스트레칭", "부상 예방", intensity="light"),
    ),
    "user-kangseoyeon": (
        _r("주말 회복 걷기", 30, "유산소", "주말 나트륨 배출", intensity="light"),
        _r("전신 서킷", 20, "근력", "평일 프로그램 유지", sets=4, reps=12,
           intensity="high"),
        _r("상체 스트레칭", 10, "스트레칭", "피로 해소", intensity="light"),
    ),
    "user-dohyun": (
        _r("체력 측정 걷기", 20, "유산소", "기초 체력 파악"),
        _r("맨몸 스쿼트", 10, "근력", "하체 기준선 측정", sets=3, reps=15),
        _r("전신 스트레칭", 10, "스트레칭", "가동범위 확인", intensity="light"),
    ),
    "user-sera": (
        _r("저강도 걷기", 20, "유산소", "혈압 우선 안정", intensity="light"),
        _r("호흡 이완", 10, "스트레칭", "교감신경 완화", intensity="light"),
        _r("의자 스쿼트", 8, "근력", "최소 부하로 재시작", sets=2, reps=10,
           intensity="light"),
    ),
    "user-junhyuk": (
        _r("퇴근 후 걷기", 15, "유산소", "짧게라도 유지"),
        _r("목·어깨 스트레칭", 10, "스트레칭", "장시간 착석 보완", intensity="light"),
        _r("플랭크", 5, "근력", "최소 코어 유지", sets=3, hold=20),
    ),
    "user-yuna": (
        _r("실내 자전거", 20, "유산소", "무릎 부담 없는 유산소"),
        _r("레그 익스텐션", 12, "근력", "대퇴사두 재건", sets=3, reps=12, weight=20),
        _r("무릎 가동범위", 10, "스트레칭", "재활 프로토콜", intensity="light"),
    ),
    "user-jiho": (
        _r("트레드밀 경사 걷기", 25, "유산소", "정체 구간 자극 변화", intensity="high"),
        _r("풀업 어시스트", 12, "근력", "상체 자극 전환", sets=3, reps=8,
           intensity="high"),
        _r("전신 스트레칭", 10, "스트레칭", "회복", intensity="light"),
    ),
    "user-gayoung": (
        _r("가벼운 걷기", 20, "유산소", "복귀 준비", intensity="light"),
        _r("전신 스트레칭", 15, "스트레칭", "휴식기 스트레칭 유지", intensity="light"),
        _r("맨몸 스쿼트", 8, "근력", "최소 근력 유지", sets=3, reps=12),
    ),
    "user-taekyung": (
        _r("스쿼트", 25, "근력", "하체 볼륨 확보", sets=5, reps=8, weight=80,
           intensity="high"),
        _r("벤치프레스", 25, "근력", "상체 볼륨 확보", sets=5, reps=8, weight=60,
           intensity="high"),
        _r("유산소 쿨다운", 10, "유산소", "나트륨 배출", intensity="light"),
    ),
    "user-seojin": (
        _r("러닝머신", 30, "유산소", "나트륨 배출 지원"),
        _r("전신 근력 서킷", 25, "근력", "현 프로그램 유지", sets=3, reps=12,
           intensity="high"),
        _r("스트레칭", 10, "스트레칭", "회복", intensity="light"),
    ),
    "user-eunchae": (
        _r("걷기", 20, "유산소", "습관 형성 우선", intensity="light"),
        _r("맨몸 스쿼트", 8, "근력", "부담 없는 시작", sets=3, reps=15, intensity="light"),
        _r("전신 스트레칭", 10, "스트레칭", "운동 후 회복", intensity="light"),
    ),
}

#: 요일별 이행률(월→일) — 확장 회원은 `seed_roster._METRICS` 에 있고, 따로 시드되는
#: 이지수·박성호만 여기 둔다. 데모 `weekCompletion` 과 같다.
COMPLETION: dict[str, list[int]] = {
    "user-jisu": [67, 100, 100, 100, 100, 0, 0],
    "user-sungho": [0, 33, 100, 0, 0, 0, 0],
}


@dataclass(frozen=True)
class SeedExercise:
    """회원이 직접 적은 운동·PT 수업 운동 한 줄."""

    name: str
    #: 운동 기록 유형 코드 — cardio|strength|stretching.
    type: str
    minutes: int
    sets: int | None = None
    reps: int | None = None
    weight: float | None = None
    intensity: str = "moderate"

    @property
    def calories(self) -> int:
        return kcal(self.type, self.minutes)

    def as_history(self) -> dict:
        """이력(`RoutineHistory.exercises_json`)에 싣는 값 객체."""
        row: dict = {"name": self.name, "type": self.type, "minutes": self.minutes}
        if self.sets is not None:
            row["sets"] = self.sets
        if self.reps is not None:
            row["reps"] = self.reps
        if self.weight is not None:
            row["weight"] = self.weight
        row["intensity"] = self.intensity
        parts = [f"{self.sets}세트", f"{self.reps}회"] if self.sets else [f"{self.minutes}분"]
        if self.weight is not None:
            parts.append(f"{self.weight:g}kg")
        row["label"] = " ".join([self.name, *parts, "✓"])
        return row


#: 회원이 직접 적은 운동 — (요일 0=월, 운동). 지난 날 그 요일마다 한 줄. 데모
#: `seed_workouts.dart` 의 `_memberLogs` 와 같다.
MEMBER_LOGS: dict[str, tuple[tuple[int, SeedExercise], ...]] = {
    "user-woojin": ((5, SeedExercise("주말 러닝", "cardio", 40)),),
    "user-kangseoyeon": (
        (6, SeedExercise("가벼운 등산", "cardio", 60, intensity="light")),
    ),
}

#: PT 수업에서 한 운동 — 지난 완료 수업마다 PT 이력과 `trainer_pt` 행이 된다. 데모
#: `seed_workouts.dart` 의 `_ptPrograms` 와 같다.
PT_PROGRAMS: dict[str, tuple[SeedExercise, ...]] = {
    "user-woojin": (
        SeedExercise("데드리프트", "strength", 9, sets=3, reps=8, weight=70),
        SeedExercise("스텝업", "strength", 9, sets=3, reps=12, weight=10),
        SeedExercise("코어 서킷", "strength", 6, sets=2, reps=12),
    ),
    "user-jiho": (
        SeedExercise("레그프레스", "strength", 12, sets=4, reps=10, weight=120,
                     intensity="high"),
        SeedExercise("랫풀다운", "strength", 9, sets=3, reps=12, weight=45,
                     intensity="high"),
        SeedExercise("케이블 크런치", "strength", 9, sets=3, reps=15, weight=20),
    ),
    "user-taekyung": (
        SeedExercise("스쿼트", "strength", 15, sets=5, reps=5, weight=90,
                     intensity="high"),
        SeedExercise("벤치프레스", "strength", 15, sets=5, reps=5, weight=70,
                     intensity="high"),
        SeedExercise("바벨 로우", "strength", 12, sets=4, reps=8, weight=60),
    ),
}

#: PT 이력의 이름 — 실서버 PT 완료가 남기는 것과 같다.
PT_LABEL = "PT 세션 · 트레이너 지도"


def half_up(value: float) -> int:
    """반올림(.5 는 위로) — 데모(Dart `round`)와 같은 셈이다. 파이썬 `round` 는
    짝수 쪽으로 붙어(22.5 → 22) 같은 주의 이행률이 데모와 1씩 갈린다."""
    return math.floor(value + 0.5)


def day_rate(pattern: list[int], weekday: int, factor: float) -> int:
    """그 요일 이행률 — 요일 표 값에 주 계수를 곱해 0..100 으로 자른다."""
    if weekday >= len(pattern):
        return 0
    return max(0, min(100, half_up(pattern[weekday] * factor)))


def done_count(rate: int, routines: int) -> int:
    """그날 완료한 개인운동 수 — 데모 `_RateDone` 과 같은 반올림."""
    return half_up(routines * rate / 100)


def is_late_day(member_id: str, day: date, done: int, today: date) -> bool:
    """마지막 완료를 다음 날 체크한 날인가 — 데모 `_RateDone.lateDay` 와 같은 날."""
    number = MEMBER_NO.get(member_id)
    if number is None or done <= 0 or day >= today:
        return False
    return (day.day + len(f"seed-client-{number}")) % 4 == 0
