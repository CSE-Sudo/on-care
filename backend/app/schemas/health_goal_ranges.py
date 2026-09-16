"""건강 목표 숫자의 허용 범위 — 회원 경로와 트레이너 경로가 함께 쓴다. (#1888)

목표는 **한 벌의 컬럼**(`health_profiles`)이고, 그 컬럼을 회원 앱과 트레이너
웹이 각자의 문으로 고친다. 그런데 범위 제한이 트레이너 경로에만 있었다. 회원
경로는 전부 제약 없는 `Optional[int]` 이라

* 정수 범위를 넘기면 **500**(`integer out of range`) — 목표 저장이 실패하고,
* 음수·비현실적인 값은 **200 으로 저장**됐다. 홈·운동 탭의 달성률이 음수나
  0% 로 깨지고, 같은 값을 트레이너 리포트도 읽는다.

**되돌릴 수도 없었다.** 회원이 넣은 `-3000` 을 트레이너가 화면에서 고치려 하면
트레이너 스키마의 하한에 걸려 422 가 난다 — 잘못된 값을 넣은 문과 고치는 문이
다른 기준을 쓰면, 한쪽으로 들어온 값이 다른 쪽에서 고칠 수 없는 값이 된다.

그래서 범위를 여기 한 곳에 두고 세 스키마(`HealthGoalsUpdate` ·
`OnboardingRequest` · `MemberHealthProfileUpdate`)가 나눠 쓴다. 두 벌로 적어
두면 또 갈라진다.

숫자의 출처는 트레이너 경로가 쓰던 값 그대로다 — 이미 운영되던 기준이라
회원이 지금까지 앱으로 저장해 온 값이 새로 막히지 않는다. 몇 가지는 단위에서
바로 나온다: 한 주는 `7 * 24 * 60 = 10080` 분이고, 주간 운동 횟수의 상한 21은
하루 세 번이다.
"""

from __future__ import annotations

from typing import Annotated

from pydantic import Field

#: 한 주의 분. 주간 시간 목표의 상한이다.
MINUTES_PER_WEEK = 7 * 24 * 60

# ---- 식단 일일 목표 ----

#: 하루 섭취 칼로리. 하한이 0 이 아닌 이유는 **굶는 목표를 세울 수 없기**
#: 때문이다 — 0kcal 목표는 달성률을 셀 수 없고, 그 값을 트레이너 리포트도 읽는다.
DailyCalories = Annotated[int, Field(ge=500, le=10000)]
DailySodiumMg = Annotated[int, Field(ge=0, le=50000)]
DailySugarG = Annotated[int, Field(ge=0, le=1000)]
DailyCarbsG = Annotated[int, Field(ge=0, le=2000)]
DailyProteinG = Annotated[int, Field(ge=0, le=1000)]
DailyFatG = Annotated[int, Field(ge=0, le=1000)]

# ---- 운동 목표 ----
#
# 운동 탭이 견주는 축과 같다 (#1139) — 소모는 하루, 유형별은 한 주다.

DailyBurnKcal = Annotated[int, Field(ge=0, le=20000)]
WeeklyCardioMinutes = Annotated[int, Field(ge=0, le=MINUTES_PER_WEEK)]
WeeklyStrengthSets = Annotated[int, Field(ge=0, le=1000)]
WeeklyFlexibilityMinutes = Annotated[int, Field(ge=0, le=MINUTES_PER_WEEK)]

# ---- 옛 주간 목표 ----
#
# 다른 화면이 아직 읽고 있어 남아 있는 열이다(#1449). 회원 앱 `건강 목표`
# 화면은 다루지 않지만 `HealthGoalsUpdate` 는 아직 받으므로, 여기서도 같은
# 범위를 준다 — 받는 칸에 기준이 없으면 그 칸이 다음 구멍이 된다.

#: 주간 운동 횟수. 상한 21은 하루 세 번이다.
WeeklyWorkoutGoal = Annotated[int, Field(ge=0, le=21)]
WeeklyExerciseMinutesGoal = Annotated[int, Field(ge=0, le=MINUTES_PER_WEEK)]
WeeklyBurnGoal = Annotated[int, Field(ge=0, le=100000)]

# ---- 글로 적는 목표 ----
#
# 컬럼이 `Text` 라 길이를 넘겨도 500 은 아니지만, 같은 모양으로 갈라져
# 있었다 — 트레이너는 1000/500자인데 회원 경로에는 상한이 없어
# `{"goals": 20만자}` 가 200 이었다.

#: 건강 목표(최대 2개)와 트레이너가 적은 건강상태·주의사항이 함께 담긴다.
ConditionsText = Annotated[str, Field(max_length=1000)]
GoalsText = Annotated[str, Field(max_length=500)]
