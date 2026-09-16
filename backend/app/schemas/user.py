"""
사용자 응답 스키마 — 프론트 계약(_usersMe, _usersMeHealth)에 정확히 맞춤.

모든 필드는 snake_case (프론트 case_mapper 가 camelCase 로 변환).
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, ClassVar, Optional
from pydantic import BaseModel, Field, field_validator, model_validator

from app.schemas.health_goal_ranges import (
    ConditionsText,
    DailyBurnKcal,
    DailyCalories,
    DailyCarbsG,
    DailyFatG,
    DailyProteinG,
    DailySodiumMg,
    DailySugarG,
    GoalsText,
    WeeklyBurnGoal,
    WeeklyCardioMinutes,
    WeeklyExerciseMinutesGoal,
    WeeklyFlexibilityMinutes,
    WeeklyStrengthSets,
    WeeklyWorkoutGoal,
)
from app.schemas.partial_update import PartialUpdate
from app.services.contact_format import clean_email, normalize_phone
from app.services.health_focus import normalize_conditions


# ---- GET /users/me ----
class UserMe(BaseModel):
    id: str
    name: str
    email: str


# ---- GET /users/me/health ----
class HealthProfileBrief(BaseModel):
    name: str
    email: str
    #: 회원 ID(`User.id`).
    #:
    #: MY 탭은 이 값을 더 이상 보여주지 않는다 (#1634) — 트레이너와의 연결은
    #: 그 자리에서 발급하는 6자리 동기화 코드로 한다. 화면이 쓰지 않게 됐지만
    #: 응답에서 빼지는 않는다. 옛 버전 앱이 아직 읽는 자리다.
    id: str = ""


class PairingCodeOut(BaseModel):
    """회원이 트레이너에게 불러 주는 6자리 동기화 코드. (#1634)

    남은 시간을 초로 함께 주는 이유는 만료 시각만으로는 화면이 기기 시계에
    기대게 되기 때문이다 — 시계가 어긋난 기기에서 카운트다운이 엉뚱해진다.
    """

    code: str
    expires_at: datetime
    #: 지금부터 만료까지 남은 초. 0 이하로는 내려가지 않는다.
    expires_in_seconds: int


class RiskInfo(BaseModel):
    title: str
    body: str
    level: str  # low | medium | high


class SettingItem(BaseModel):
    label: str
    icon: str
    kind: str


class MemberNotificationSettings(BaseModel):
    """회원 알림 수신 설정. (#489)

    필드 이름은 사용자 앱이 로컬에 쓰던 키(`notif_*`)에서 접두사만 뗀 것이다 —
    앱이 저장 위치만 서버로 옮기는 것이므로 새 이름을 만들면 화면과 대응이
    흐려진다.
    """

    diet_log: bool
    exercise_reminder: bool
    trainer_message: bool
    ai_coaching: bool
    weekly_report: bool


class MemberNotificationSettingsUpdate(PartialUpdate):
    """부분 수정 — 보낸 항목만 반영한다.

    다섯 항목 모두 DB NOT NULL 이라 null 로 바꿀 수 있는 값이 아니다(#489·#495).
    """

    diet_log: bool | None = None
    exercise_reminder: bool | None = None
    trainer_message: bool | None = None
    ai_coaching: bool | None = None
    weekly_report: bool | None = None


class UserHealth(BaseModel):
    profile: HealthProfileBrief
    risk: RiskInfo
    activity_points: int
    activity_rank: Optional[int]
    settings: list[SettingItem]


# ---- 인증(로그인) ----
class Token(BaseModel):
    access_token: str
    refresh_token: str = ""
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


class SocialLoginRequest(BaseModel):
    # provider 가 준 토큰 (kakao/naver=access_token, google=id_token)
    token: str


class UserRegister(BaseModel):
    #: 형식은 `contact_format.clean_email` 이 본다(#1780). 앞뒤 공백만 잘라내고
    #: 값 자체는 바꾸지 않는다 — 소문자로 고치면 로그인 조회가 어긋난다.
    email: str
    password: str
    name: str = ""
    #: 가입 시점에 프로필을 채우기 위해 받는다 (#1634). 예전에는 MY 탭 프로필
    #: 편집에서만 넣을 수 있어 가입 직후에는 연락처가 비어 있었다.
    #:
    #: 회원 앱 가입 화면은 필수로 받지만 스키마에서는 선택이다 — 트레이너 가입
    #: (`TrainerRegister`)은 이 값을 쓰지 않고, 없어도 회원은 MY 탭에서 언제든
    #: 넣을 수 있다.
    #:
    #: 들어온 표기가 무엇이든 `000-0000-0000` 하나로 정리해 저장한다(#1780).
    phone: str = ""

    @field_validator("email", mode="before")
    @classmethod
    def _check_email(cls, value: Any) -> Any:
        if isinstance(value, str):
            return clean_email(value)
        return value

    @field_validator("phone", mode="before")
    @classmethod
    def _normalize_phone(cls, value: Any) -> Any:
        if isinstance(value, str):
            return normalize_phone(value)
        return value


class TrainerRegister(UserRegister):
    """트레이너 가입 — 회원 가입에 헬스장 초대 코드를 더한다. (#475)

    코드가 소속 헬스장을 결정한다. 소속 없는 트레이너는 상담 대상이 될 수 없어
    (#443·#451) 가입 직후 아무것도 못 하는 상태가 되므로, 소속을 가입 시점에
    확정한다.
    """

    invite_code: str = Field(min_length=1, max_length=32)

    @field_validator("invite_code", mode="before")
    @classmethod
    def _normalize_code(cls, value: Any) -> Any:
        # 사람이 옮겨 적는 값이다. 공백과 대소문자 차이를 코드 오류로 만들지 않는다.
        if isinstance(value, str):
            return value.strip().upper()
        return value


# ---- 프로필 / 온보딩 / 건강 목표 ----
class ProfileView(BaseModel):
    """GET /users/me/profile — 내 프로필 화면용 통합 뷰."""

    id: str
    name: str
    email: str
    phone: str = ""
    birth_date: str = ""
    gender: str = ""
    height_cm: Optional[float] = None
    weight_kg: Optional[float] = None
    conditions: str = ""
    goals: str = ""
    daily_calories: Optional[int] = None
    daily_sodium_mg: Optional[int] = None
    daily_sugar_g: Optional[int] = None
    daily_carbs_g: Optional[int] = None
    daily_protein_g: Optional[int] = None
    daily_fat_g: Optional[int] = None
    weekly_workout_goal: Optional[int] = None
    weekly_exercise_minutes_goal: Optional[int] = None
    weekly_burn_goal: Optional[int] = None
    daily_burn_kcal: Optional[int] = None
    weekly_cardio_minutes: Optional[int] = None
    weekly_strength_sets: Optional[int] = None
    weekly_flexibility_minutes: Optional[int] = None
    onboarded: bool = False
    #: 건강 목표를 마지막으로 바꾼 사람(`member`|`trainer`)과 시각. 바꾼 적이 없으면
    #: 둘 다 null 이다(#1832).
    focus_changed_by: Optional[str] = None
    focus_changed_at: Optional[datetime] = None


class HealthGoalsUpdate(BaseModel):
    """PUT /users/me/health-goals — 식단 일일 목표(6종) + 운동 목표(7종).

    체중/혈압/혈당(vitals) 목표는 다루지 않는다. 모두 선택(부분 저장 허용).

    **여기만 `PartialUpdate` 를 쓰지 않는다**(#495). 목표 컬럼은 전부
    `nullable=True` 이고, 명시적 null 은 '목표 해제'로 실제 동작한다 — 핸들러가
    그대로 컬럼에 반영한다. 규약은 *NOT NULL 컬럼* 을 지키려는 것이므로 여기에는
    해당하지 않고, 적용하면 목표를 지울 방법이 사라진다.
    """

    #: 건강 목표(`체중 감량, 혈압 관리`)와 자유 입력 운동 목표. 온보딩이
    #: 저장하던 두 값을 MY `건강 목표` 화면도 같은 열로 읽고 고친다(#1471) —
    #: 두 화면이 다른 열을 쓰면 온보딩에서 고른 값이 MY 에서 보이지 않는다.
    #: 옛 질환 이름은 저장할 때 새 목표로 정리한다(#1814).
    #:
    #: 목표 숫자의 범위는 트레이너 경로(`MemberHealthProfileUpdate`)와 **같은
    #: 것**을 쓴다(#1888) — `health_goal_ranges` 한 곳에 있다. 전에는 이쪽만
    #: 제약이 없어 `daily_calories: 99999999999` 가 500 이고 `-3000` 은 그대로
    #: 저장됐는데, 그 값을 트레이너가 화면에서 고치려 하면 트레이너 스키마의
    #: 하한에 걸려 422 가 났다 — 넣은 문과 고치는 문이 달랐다.
    conditions: Optional[ConditionsText] = None
    goals: Optional[GoalsText] = None
    daily_calories: Optional[DailyCalories] = None
    daily_sodium_mg: Optional[DailySodiumMg] = None
    daily_sugar_g: Optional[DailySugarG] = None
    daily_carbs_g: Optional[DailyCarbsG] = None
    daily_protein_g: Optional[DailyProteinG] = None
    daily_fat_g: Optional[DailyFatG] = None
    weekly_workout_goal: Optional[WeeklyWorkoutGoal] = None
    weekly_exercise_minutes_goal: Optional[WeeklyExerciseMinutesGoal] = None
    weekly_burn_goal: Optional[WeeklyBurnGoal] = None
    # 운동 탭이 견주는 목표 (#1139). 소모는 하루, 유형별은 한 주다.
    daily_burn_kcal: Optional[DailyBurnKcal] = None
    weekly_cardio_minutes: Optional[WeeklyCardioMinutes] = None
    weekly_strength_sets: Optional[WeeklyStrengthSets] = None
    weekly_flexibility_minutes: Optional[WeeklyFlexibilityMinutes] = None

    @field_validator("conditions")
    @classmethod
    def _normalize_conditions(cls, value: Optional[str]) -> Optional[str]:
        """옛 질환 이름(고혈압·당뇨 등)을 새 건강 목표로 정리한다(#1814)."""
        return normalize_conditions(value)


class OnboardingRequest(BaseModel):
    """POST /users/me/onboarding — 최초 온보딩(모두 선택, 부분 저장 허용).

    name 은 User, 나머지는 HealthProfile 컬럼과 1:1 로 매핑된다.
    """

    name: Optional[str] = None
    birth_date: Optional[str] = None  # YYYY-MM-DD
    gender: Optional[str] = Field(default=None, pattern="^(male|female|other|)$")
    height_cm: Optional[float] = Field(default=None, ge=50, le=300)
    weight_kg: Optional[float] = Field(default=None, ge=20, le=500)
    conditions: Optional[ConditionsText] = None  # "체중 감량, 혈압 관리" — 옛 질환 이름은 정리(#1814)
    goals: Optional[GoalsText] = None
    # 목표 칸은 `HealthGoalsUpdate` 와 **같은 열**이다 — 온보딩이 권장값으로
    # 채워 둔 목표를 MY 건강 목표가 그대로 이어 고친다. 두 스키마가 서로 다른
    # 열을 다루면 온보딩에서 정한 목표가 MY 에서 보이지 않는다.
    #
    # 같은 열이므로 **범위도 같다**(#1888). 여기만 열어 두면 온보딩으로 들어온
    # 값을 MY 화면과 트레이너 화면이 고칠 수 없는 자리가 생긴다.
    daily_calories: Optional[DailyCalories] = None
    daily_sodium_mg: Optional[DailySodiumMg] = None
    daily_sugar_g: Optional[DailySugarG] = None
    daily_carbs_g: Optional[DailyCarbsG] = None
    daily_protein_g: Optional[DailyProteinG] = None
    daily_fat_g: Optional[DailyFatG] = None
    daily_burn_kcal: Optional[DailyBurnKcal] = None
    weekly_cardio_minutes: Optional[WeeklyCardioMinutes] = None
    weekly_strength_sets: Optional[WeeklyStrengthSets] = None
    weekly_flexibility_minutes: Optional[WeeklyFlexibilityMinutes] = None

    @field_validator("conditions")
    @classmethod
    def _normalize_conditions(cls, value: Optional[str]) -> Optional[str]:
        """옛 질환 이름(고혈압·당뇨 등)을 새 건강 목표로 정리한다(#1814)."""
        return normalize_conditions(value)


class ProfileUpdate(PartialUpdate):
    """PUT /users/me — 내 프로필 모달(이름/이메일/전화/생년월일).

    네 항목 모두 DB NOT NULL 이라 null 로 바꿀 수 있는 값이 아니다. 전에는
    핸들러가 `is not None` 으로 걸러 조용히 무시했다 — 저장된 줄 알게 된다(#495).
    """

    nullable_fields: ClassVar[frozenset[str]] = frozenset({"height_cm", "weight_kg"})

    name: Optional[str] = None
    #: 가입과 **같은 기준**으로 본다(#1883). 로그인이 이메일로 이뤄지므로, 여기서
    #: 형식을 보지 않으면 오타 한 번이 계정 잠김이 된다 — 전에는 `asdf` 가 200 으로
    #: 저장되고 그 회원은 원래 주소로 다시 로그인할 수 없었다. 비밀번호 찾기
    #: 경로가 없어 스스로 되돌릴 방법도 없다.
    #:
    #: 빈 문자열도 막힌다. 이메일은 비울 수 있는 값이 아니다.
    email: Optional[str] = None
    #: 가입과 같이 `000-0000-0000` 한 표기로 정리해 저장한다(#1883). 가입만
    #: 정리하면 이 화면이 그 정리를 그대로 되돌린다.
    #:
    #: 빈 문자열은 그대로 둔다 — 연락처를 지우는 것은 할 수 있는 일이다.
    phone: Optional[str] = None
    birth_date: Optional[str] = None
    gender: Optional[str] = Field(default=None, pattern="^(male|female|other|)$")
    height_cm: Optional[float] = Field(default=None, ge=50, le=300)
    weight_kg: Optional[float] = Field(default=None, ge=20, le=500)
    goals: Optional[GoalsText] = None

    # 가입(`UserRegister`)과 같은 함수를 부른다. 두 경로가 다른 기준을 쓰면
    # 한쪽이 정리한 값을 다른 쪽이 되돌린다.
    #
    # `None` 을 그냥 통과시키는 것은 여기서 판단할 일이 아니기 때문이다 —
    # 누락인지 명시적 null 인지는 `PartialUpdate` 가 뒤에서 가른다.
    @field_validator("email", mode="before")
    @classmethod
    def _check_email(cls, value: Any) -> Any:
        if isinstance(value, str):
            return clean_email(value)
        return value

    @field_validator("phone", mode="before")
    @classmethod
    def _normalize_phone(cls, value: Any) -> Any:
        if isinstance(value, str):
            return normalize_phone(value)
        return value
