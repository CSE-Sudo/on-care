"""
사용자 응답 스키마 — 프론트 계약(_usersMe, _usersMeHealth)에 정확히 맞춤.

모든 필드는 snake_case (프론트 case_mapper 가 camelCase 로 변환).
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, ClassVar, Literal, Optional
from pydantic import BaseModel, Field, field_validator, model_validator

from app.schemas.health_goal_ranges import (
    ConditionsText,
    check_conditions_notes,
    DailyBurnKcal,
    DailyCalories,
    DailyCarbsG,
    DailyFatG,
    DailyProteinG,
    DailySodiumMg,
    DailySugarG,
    WeeklyBurnGoal,
    WeeklyCardioMinutes,
    WeeklyExerciseMinutesGoal,
    WeeklyFlexibilityMinutes,
    WeeklyStrengthSets,
    WeeklyWorkoutGoal,
)
from app.schemas.partial_update import PartialUpdate
from app.services.contact_format import clean_email, normalize_email, normalize_phone
from app.services.password_policy import check_new_password
from app.services.profile_format import clean_birth_date, clean_name
from app.services.health_focus import normalize_conditions
from app.services.signup_consent import SubmittedKind as ConsentKind, missing_required


# ---- GET /users/me ----
class UserMe(BaseModel):
    id: str
    name: str
    email: str
    #: 계정 역할(`member`·`trainer`, #3054). 회원 앱과 트레이너 웹은 한 출처에
    #: 배포돼 브라우저 저장소를 같이 쓴다. 앱이 세션을 되살릴 때 이 값으로 자기
    #: 계정인지 한 번 더 확인한다. 트레이너 토큰은 이 API 에서 이미 403 이다.
    role: str = "member"
    #: 필수 가입 동의(약관·개인정보·건강정보·만 14세) 중 지금 버전에 동의하지
    #: 않은 항목이 있는가(#2819). 참이면 앱이 다른 화면보다 먼저 동의 화면을
    #: 띄운다 — 동의 절차가 생기기 전에 가입한 계정, 소셜 첫 가입, 문서 버전이
    #: 올라간 뒤의 첫 로그인이 여기에 걸린다.
    consent_required: bool = False
    #: 아직 동의하지 않은 필수 항목(`terms`·`privacy`·`health`·`age14`).
    consent_pending: list[str] = Field(default_factory=list)


class ConsentSubmit(BaseModel):
    """POST /users/me/consents — 가입 뒤 동의 화면에서 받은 항목. (#2819)"""

    consents: list[ConsentKind]


class ConsentStatus(BaseModel):
    """동의를 남긴 뒤의 상태. `GET /users/me` 의 같은 이름 칸과 같다."""

    consent_required: bool
    consent_pending: list[str] = Field(default_factory=list)


class OptionalConsentState(BaseModel):
    """선택 동의 한 항목의 상태 — `GET`·`PUT`·`DELETE /users/me/consents/{kind}`. (#3136)

    `agreed` 는 **지금 버전**에 철회하지 않은 동의가 있는가다. 약관이 바뀌어 옛
    버전에만 동의한 계정은 `false` 이고, 앱은 다음 이용 때 다시 묻는다.
    `version`·`agreed_at`·`revoked_at` 은 가장 최근 기록의 값이다(없으면 null).
    """

    kind: str
    agreed: bool
    current_version: str
    version: Optional[str] = None
    agreed_at: Optional[datetime] = None
    revoked_at: Optional[datetime] = None


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
    """MY 탭 계정 카드 — 회원 식별 정보와 포인트 잔액.

    위험 문구(`risk`)·활동 순위(`activity_rank`)·설정 메뉴(`settings`)는
    #2903 에서 뺐다. 앱이 읽지 않는 고정값이었다.
    """

    profile: HealthProfileBrief
    activity_points: int


# ---- 인증(로그인) ----
class Token(BaseModel):
    access_token: str
    refresh_token: str = ""
    token_type: str = "bearer"


class LoginToken(Token):
    """로그인·소셜 로그인 응답. (#2819)

    토큰과 함께 이 계정이 동의 화면을 거쳐야 하는지 알린다. 앱이 로그인 직후
    `GET /users/me` 를 한 번 더 부르지 않고도 바로 동의 화면으로 갈 수 있다.
    """

    consent_required: bool = False
    # 이 계정의 역할(`member`|`trainer`). 회원 앱은 저장 전에 이 값을 보고 트레이너
    # 계정의 토큰을 버린다(#3137) — 받아 두면 로그인 직후부터 회원 API 가 모두 403 이다.
    role: str = "member"


class RefreshRequest(BaseModel):
    refresh_token: str


class PasswordChanged(Token):
    """비밀번호 변경 응답(#2766).

    변경은 계정의 토큰 세대를 올려 그 전 토큰을 모두 무효로 만든다. 요청한 기기도
    예외가 아니므로, 그 기기가 로그아웃되지 않도록 새 세대 토큰 한 쌍을 함께 준다.
    클라이언트는 받은 토큰으로 저장소를 바꿔야 한다.
    """

    status: str = "changed"


class MemberPasswordChange(BaseModel):
    """회원 비밀번호 변경(`POST /users/me/password`, #2824).

    트레이너 `TrainerPasswordChange` 와 같은 규약이다. 현재 비밀번호를 요구해
    토큰만 빼앗긴 상태에서 계정까지 넘어가지 않게 한다.
    """

    #: 지금 비밀번호는 기준 이전에 만든 것일 수 있어 새 기준을 보지 않는다.
    current_password: str = Field(min_length=1, max_length=200)
    #: 가입과 같은 기준(`password_policy.check_new_password`, #1555).
    new_password: str

    @field_validator("new_password")
    @classmethod
    def _check_new_password(cls, value: str) -> str:
        return check_new_password(value)


class PasswordResetRequest(BaseModel):
    """비밀번호 재설정 요청(`POST /auth/password-reset/request`, #2824).

    형식 검사는 하지 않는다 — 형식이 틀린 주소는 어차피 계정이 없고, 422 와
    202 가 갈리면 응답이 하나 더 생길 뿐이다. 길이만 막는다.
    """

    email: str = Field(min_length=1, max_length=255)

    @field_validator("email")
    @classmethod
    def _normalize(cls, value: str) -> str:
        # 로그인과 같이 공백을 자르고 소문자로 맞춘다(#2816·#3094) — 이메일은 소문자로
        # 저장되므로 그대로 두면 `Hong@…` 로 친 요청이 계정을 찾지 못한다.
        return normalize_email(value)


class PasswordResetRequested(BaseModel):
    """재설정 요청 응답. 계정이 있든 없든 **같다** — 가입 여부를 드러내지 않는다."""

    status: str = "requested"
    #: 코드 유효 시간(분). 화면이 "N분 안에 입력하세요" 를 그린다.
    expires_in_minutes: int


class PasswordResetConfirm(BaseModel):
    """비밀번호 재설정 확인(`POST /auth/password-reset/confirm`, #2824)."""

    #: 메일의 코드. 하이픈·공백·대소문자는 서버가 정규화한다.
    token: str = Field(min_length=1, max_length=64)
    #: 가입과 같은 기준(#1555).
    new_password: str

    @field_validator("new_password")
    @classmethod
    def _check_new_password(cls, value: str) -> str:
        return check_new_password(value)


class PasswordResetDone(BaseModel):
    """재설정 완료. 토큰은 주지 않는다 — 새 비밀번호로 다시 로그인한다."""

    status: str = "reset"


class SignupEmailCodeRequest(BaseModel):
    """가입 이메일 인증 코드 요청(`POST /auth/register/email-code`, #3038).

    이메일은 가입과 같은 규칙으로 검사·정규화한다(`clean_email`, 소문자) — 코드는
    정규화한 주소에 묶이므로 가입 요청과 같은 값이어야 맞는다.
    """

    email: str
    purpose: Literal["member_signup", "trainer_signup"]

    @field_validator("email", mode="before")
    @classmethod
    def _check_email(cls, value: Any) -> Any:
        if isinstance(value, str):
            return clean_email(value)
        return value


class SignupEmailCodeSent(BaseModel):
    """코드 요청 응답. 이미 가입된 주소여도 **같다** — 가입 여부를 드러내지 않는다."""

    #: 코드 유효 시간(분).
    expires_in_minutes: int
    #: 다시 받기까지 기다리는 시간(초). 화면이 "다시 받기" 버튼을 이만큼 잠근다.
    resend_after_seconds: int


class SocialLoginRequest(BaseModel):
    # provider 가 준 토큰 (kakao=access_token, google=id_token)
    token: str


class KakaoCodeExchangeRequest(BaseModel):
    """카카오 웹 로그인 창이 돌려준 인가 코드 (#330).

    `redirect_uri` 는 로그인 창을 열 때 쓴 값과 **글자 그대로** 같아야 카카오가 교환해 준다.
    """

    code: str = Field(min_length=1, max_length=2048)
    redirect_uri: str = Field(min_length=1, max_length=2048)


class KakaoCodeExchangeResponse(BaseModel):
    """교환한 카카오 access_token. 앱은 이 값을 `POST /auth/social/kakao` 의 `token` 으로 쓴다."""

    access_token: str


class UserRegister(BaseModel):
    #: 형식은 `contact_format.clean_email` 이 본다(#1780). 앞뒤 공백을 잘라내고
    #: 소문자로 맞춰 저장한다(#2816) — 로그인·중복 확인도 같은 규칙으로 비교한다.
    email: str
    #: 새로 정하는 비밀번호라 `password_policy.check_new_password` 기준을 본다
    #: (#1555). 로그인은 이 스키마를 쓰지 않으므로 기준 이전에 만든 계정은
    #: 그대로 로그인된다.
    password: str
    #: 보내지 않으면 핸들러가 이메일 로컬 파트로 채운다
    #: (`profile_format.name_from_email`). 빈 문자열도 같이 본다 — 회원 앱은
    #: 이름을 필수로 받지만 스키마에서 빈 값을 422 로 되돌리면, 이름을 아예
    #: 넣을 자리가 없는 경로(트레이너 가입·옛 빌드)가 가입에서 막힌다.
    #:
    #: 값을 보냈으면 저장 가능한 길이인지는 본다(#1887). 전에는 101자가
    #: `value too long` 500 이 됐다.
    name: str = ""
    #: 가입 시점에 프로필을 채우기 위해 받는다 (#1634). 예전에는 MY 탭 프로필
    #: 편집에서만 넣을 수 있어 가입 직후에는 연락처가 비어 있었다.
    #:
    #: 두 앱 가입 화면은 필수로 받지만 스키마에서는 선택이다 — 번호 칸이 없던 옛
    #: 빌드의 가입도 받고, 비어 있어도 MY 에서 언제든 넣을 수 있다. 회원은
    #: `HealthProfile.phone`, 트레이너(`TrainerRegister`)는 `TrainerProfile.phone` 에
    #: 담긴다. 아이디(가입 이메일) 찾기가 이 값을 쓴다.
    #:
    #: 들어온 표기가 무엇이든 `010-0000-0000` 하나로 정리해 저장한다(#1780).
    phone: str = ""
    #: 가입 화면에서 체크한 동의 항목(#2819). 보냈다면 필수 항목
    #: ([REQUIRED_CONSENTS_ROLE] 의 필수 집합)이 모두 있어야 한다 — 빠지면 422.
    #:
    #: **보내지 않으면(null) 막지 않는다.** 동의 화면이 없는 옛 앱 빌드에서도
    #: 가입은 되고, 동의 행이 없으므로 로그인 직후 동의 화면을 거친다. 빈
    #: 목록(`[]`)은 '보냈는데 아무것도 체크하지 않았다'라 422 다.
    consents: Optional[list[ConsentKind]] = None
    #: 가입 전에 이 이메일로 받은 6자리 인증 코드(#3038,
    #: `POST /auth/register/email-code`). 빠지면 핸들러가 422 `email_code_required`
    #: 를 준다 — 스키마에서 막으면 FastAPI 목록 detail 이 되어 화면이 코드를 가를 수
    #: 없다. `SIGNUP_EMAIL_VERIFICATION=false` 인 서버(테스트·E2E)는 보지 않는다.
    email_code: Optional[str] = Field(default=None, max_length=16)

    #: 필수 항목을 고르는 역할. 트레이너 가입은 건강정보 동의가 없다.
    REQUIRED_CONSENTS_ROLE: ClassVar[str] = "member"

    @model_validator(mode="after")
    def _check_required_consents(self) -> "UserRegister":
        if self.consents is None:
            return self
        missing = missing_required(self.REQUIRED_CONSENTS_ROLE, self.consents)
        if missing:
            raise ValueError(f"필수 동의 항목이 빠졌습니다: {', '.join(missing)}")
        return self

    @field_validator("email", mode="before")
    @classmethod
    def _check_email(cls, value: Any) -> Any:
        if isinstance(value, str):
            return clean_email(value)
        return value

    @field_validator("password")
    @classmethod
    def _check_password(cls, value: str) -> str:
        return check_new_password(value)

    @field_validator("name", mode="before")
    @classmethod
    def _check_name(cls, value: Any) -> Any:
        # 빈 값은 '안 보냈다' 와 같이 둔다 — 위 주석대로 핸들러가 채운다.
        if isinstance(value, str) and value.strip():
            return clean_name(value)
        return value

    @field_validator("phone", mode="before")
    @classmethod
    def _normalize_phone(cls, value: Any) -> Any:
        if isinstance(value, str):
            return normalize_phone(value)
        return value


class TrainerRegister(UserRegister):
    """트레이너 가입 — 회원 가입과 같은 필드를 받는다. (#475, #1627)

    예전에는 헬스장 초대 코드를 더 받았지만 발급 경로가 없어 걷어 냈다(#1627).
    소속 헬스장은 가입 뒤 `PUT /trainer/me/gym` 으로 고른다. 스키마를 따로 두는
    이유는 엔드포인트가 달라서다 — 트레이너만의 필드가 다시 생기면 여기에 더한다.

    필수 동의 항목은 회원과 다르다(#2819) — 트레이너는 자기 건강정보를 기록하지
    않으므로 건강정보 처리 동의가 없다.

    전화번호(`phone`)는 회원과 같이 받아 트레이너 프로필에 담는다. 전에는 받지 않아
    가입 직후 번호가 비어 있었고, 번호로 가입 이메일을 찾을 수 없었다.
    """

    REQUIRED_CONSENTS_ROLE: ClassVar[str] = "trainer"


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
    daily_calories: Optional[int] = None
    daily_sodium_mg: Optional[int] = None
    daily_sugar_g: Optional[int] = None
    daily_carbs_g: Optional[int] = None
    daily_protein_g: Optional[int] = None
    #: 식단 분석·조언이 실제로 쓰는 하루 단백질 목표(#2898) — 개인 목표가 있으면
    #: 그 값, 없으면 체중 × 1.2g, 둘 다 없으면 60g. 영양 카드 분모가 이 값이다.
    effective_daily_protein_g: Optional[int] = None
    daily_fat_g: Optional[int] = None
    weekly_workout_goal: Optional[int] = None
    weekly_exercise_minutes_goal: Optional[int] = None
    weekly_burn_goal: Optional[int] = None
    daily_burn_kcal: Optional[int] = None
    weekly_cardio_minutes: Optional[int] = None
    weekly_strength_sets: Optional[int] = None
    weekly_flexibility_minutes: Optional[int] = None
    onboarded: bool = False
    #: 첫 설정을 건너뛰었는가(#2855). 앱은 `onboarded` 또는 이 값이 참이면 로그인·
    #: 세션 복구 뒤 첫 설정 화면으로 보내지 않는다.
    onboarding_skipped: bool = False
    #: 이메일 비밀번호가 있는 계정인가(#2824). 소셜 로그인 전용 계정은 false 라
    #: 앱이 MY 의 비밀번호 변경 대신 안내를 보여 준다.
    has_password: bool = True
    #: 건강 목표를 마지막으로 바꾼 사람(`member`|`trainer`)과 시각. 바꾼 적이 없으면
    #: 둘 다 null 이다(#1832).
    focus_changed_by: Optional[str] = None
    focus_changed_at: Optional[datetime] = None
    #: 건강상태·주의사항을 마지막으로 바꾼 사람과 시각(#2942). 목표 칩 기록과 따로다.
    notes_changed_by: Optional[str] = None
    notes_changed_at: Optional[datetime] = None
    #: 로그인 이메일을 바꾼 저장(`PUT /users/me`)에만 채운다(#3039). 바꾸면 토큰 세대가
    #: 올라 다른 기기가 모두 로그아웃되고, 이 기기는 이 새 한 쌍으로 이어 쓴다
    #: (`POST /users/me/password` 와 같은 규약). 그 밖의 응답에서는 null 이다.
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None


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
        """옛 질환 이름(고혈압·당뇨 등)을 새 건강 목표로 정리한다(#1814).

        건강상태·주의사항은 트레이너 경로와 같은 상한이다(#2619).
        """
        return check_conditions_notes(normalize_conditions(value))


class OnboardingRequest(BaseModel):
    """POST /users/me/onboarding — 최초 온보딩(모두 선택, 부분 저장 허용).

    name 은 User, 나머지는 HealthProfile 컬럼과 1:1 로 매핑된다.
    """

    #: 이름은 비울 수 없다(#1887). 가입에서 필수로 받은 값을 온보딩이 빈
    #: 문자열로 덮으면, 이름이 빈 회원이 트레이너 로스터와 채팅에 공백으로 뜬다.
    name: Optional[str] = None
    #: `YYYY-MM-DD` 만 받는다(#1887). 날짜가 아닌 값이 저장되면 트레이너의 담당
    #: 요청 확인 화면에서 나이가 조용히 비어 보인다.
    birth_date: Optional[str] = None
    gender: Optional[str] = Field(default=None, pattern="^(male|female|other|)$")
    height_cm: Optional[float] = Field(default=None, ge=50, le=300)
    weight_kg: Optional[float] = Field(default=None, ge=20, le=500)
    conditions: Optional[ConditionsText] = None  # "체중 감량, 혈압 관리" — 옛 질환 이름은 정리(#1814)
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
        """옛 질환 이름(고혈압·당뇨 등)을 새 건강 목표로 정리한다(#1814).

        건강상태·주의사항은 트레이너 경로와 같은 상한이다(#2619).
        """
        return check_conditions_notes(normalize_conditions(value))

    # 프로필 수정(`ProfileUpdate`)과 같은 함수를 부른다(#1887). 같은 두 칸을
    # 고치는 두 경로가 다른 기준을 쓰면, 한쪽으로 들어온 값이 다른 쪽에서
    # 고칠 수 없는 값이 된다.
    @field_validator("name", mode="before")
    @classmethod
    def _check_name(cls, value: Any) -> Any:
        if isinstance(value, str):
            return clean_name(value)
        return value

    @field_validator("birth_date", mode="before")
    @classmethod
    def _check_birth_date(cls, value: Any) -> Any:
        if isinstance(value, str):
            return clean_birth_date(value)
        return value


class ReauthFields(BaseModel):
    """민감한 계정 변경 전 본인 확인 값(#3039, `app/services/reauth.py`).

    접근 토큰만으로는 탈퇴·로그인 이메일 변경을 하지 않는다 — 토큰이 새거나 잠금 없는
    기기를 남이 들면 계정을 지우거나 가져갈 수 있다. 비밀번호가 있는 계정은
    `current_password`, 소셜 로그인 전용 계정은 방금 다시 로그인해 받은 provider 토큰
    (`social_provider`·`social_token`)을 보낸다.
    """

    current_password: Optional[str] = Field(default=None, max_length=256)
    social_provider: Optional[str] = Field(default=None, max_length=20)
    social_token: Optional[str] = Field(default=None, max_length=4096)


class AccountDeleteRequest(ReauthFields):
    """DELETE /users/me·/trainer/me 본문 — 탈퇴 사유와 본인 확인. (#2019, #3039)

    사유는 탈퇴를 막는 조건이 아니라 물어보는 자리다. 고른 것 중 서버가 아는 값만
    남는다. 본인 확인 값은 늘 필요하다(#3039) — 본문이 없으면 400 `reauth_required`.
    """

    reasons: list[str] = Field(default_factory=list, max_length=10)


class AccountDeletionPreview(BaseModel):
    """GET /users/me/deletion-preview — 탈퇴하면 사라지는 것의 수. (#3006)

    회원 탈퇴 확인창이 읽어 0 이 아닌 항목만 보여 준다. 읽기에 실패하면 앱은
    숫자 없이 고정 문구로 알린다.
    """

    #: 남은 포인트. 탈퇴하면 내역과 함께 사라진다.
    points: int = Field(ge=0)
    #: 아직 쓸 수 있는 쿠폰 수(사용·취소·만료 제외).
    active_coupons: int = Field(ge=0)
    #: 시작 전인 PT 예약 수. 탈퇴하면 취소되고 자리가 풀린다.
    upcoming_reservations: int = Field(ge=0)
    #: 아직 답을 받지 않은 상담 요청 수. 탈퇴하면 취소되고 트레이너에게 알린다.
    pending_consultations: int = Field(ge=0)


class ProfileUpdate(PartialUpdate):
    """PUT /users/me — 내 프로필 모달(이름/이메일/전화/생년월일).

    네 항목 모두 DB NOT NULL 이라 null 로 바꿀 수 있는 값이 아니다. 전에는
    핸들러가 `is not None` 으로 걸러 조용히 무시했다 — 저장된 줄 알게 된다(#495).
    """

    nullable_fields: ClassVar[frozenset[str]] = frozenset(
        {"height_cm", "weight_kg", "current_password", "social_provider", "social_token"}
    )

    #: 가입과 같은 기준으로 본다(#1887) — 비울 수 없고, 컬럼에 들어가는
    #: 길이여야 한다. 전에는 `{"name": ""}` 가 200 으로 저장돼, 가입에서 필수로
    #: 받은 이름을 이 화면에서 지울 수 있었다.
    name: Optional[str] = None
    #: 가입과 **같은 기준**으로 본다(#1883). 로그인이 이메일로 이뤄지므로, 여기서
    #: 형식을 보지 않으면 오타 한 번이 계정 잠김이 된다 — 전에는 `asdf` 가 200 으로
    #: 저장되고 그 회원은 원래 주소로 다시 로그인할 수 없었다. 비밀번호 찾기
    #: 경로가 없어 스스로 되돌릴 방법도 없다.
    #:
    #: 빈 문자열도 막힌다. 이메일은 비울 수 있는 값이 아니다.
    email: Optional[str] = None
    #: 가입과 같이 `010-0000-0000` 한 표기로 정리해 저장한다(#1883). 가입만
    #: 정리하면 이 화면이 그 정리를 그대로 되돌린다.
    #:
    #: 빈 문자열은 그대로 둔다 — 연락처를 지우는 것은 할 수 있는 일이다.
    phone: Optional[str] = None
    #: `YYYY-MM-DD` 만 받는다(#1887). 전에는 `asdfghjkl` 이 그대로 저장되고
    #: `1990-01-01T00:00:00Z` 는 컬럼 길이를 넘겨 500 이 됐다.
    #:
    #: 빈 문자열은 그대로 둔다 — 넣을 자리가 없던 시절에 가입한 회원과 소셜
    #: 로그인 가입자에게는 처음부터 없는 값이다.
    birth_date: Optional[str] = None
    gender: Optional[str] = Field(default=None, pattern="^(male|female|other|)$")
    height_cm: Optional[float] = Field(default=None, ge=50, le=300)
    weight_kg: Optional[float] = Field(default=None, ge=20, le=500)
    #: 로그인 이메일을 **실제로** 바꿀 때만 보는 본인 확인 값(#3039, `ReauthFields`
    #: 와 같은 뜻). 이름·연락처만 고치는 저장에는 필요 없다. 저장할 항목이 아니다.
    current_password: Optional[str] = Field(default=None, max_length=256)
    social_provider: Optional[str] = Field(default=None, max_length=20)
    social_token: Optional[str] = Field(default=None, max_length=4096)

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

    @field_validator("name", mode="before")
    @classmethod
    def _check_name(cls, value: Any) -> Any:
        if isinstance(value, str):
            return clean_name(value)
        return value

    @field_validator("birth_date", mode="before")
    @classmethod
    def _check_birth_date(cls, value: Any) -> Any:
        if isinstance(value, str):
            return clean_birth_date(value)
        return value
