"""
트레이너 API 스키마 — 트레이너 프론트 계약(seedTrainerProfile / TrainerProfile) 정렬.

GET /trainer/me 응답:
  { id, name, email, phone, specialty, career, intro, certifications[], gym{...} }
"""
from __future__ import annotations

from datetime import date as _date, datetime as _datetime
from typing import Annotated, Any, ClassVar, Literal, TypeVar

from pydantic import (
    BaseModel,
    BeforeValidator,
    Field,
    field_validator,
    model_validator,
)

from app.schemas.partial_update import PartialUpdate
from app.services import exercise_types


def _validate_ymd(v: str) -> str:
    try:
        _date.fromisoformat(v)  # 2026-99-99 / 2026-02-31 등 달력상 불가능한 값 거부
    except ValueError as e:
        raise ValueError("유효한 날짜(YYYY-MM-DD)가 아닙니다.") from e
    return v


def _validate_hhmm(v: str) -> str:
    try:
        _datetime.strptime(v, "%H:%M")  # 25:99 / 빈 문자열 등 거부
    except ValueError as e:
        raise ValueError("유효한 시간(HH:MM)이 아닙니다.") from e
    return v


class TrainerGymOut(BaseModel):
    #: 소속 헬스장 id(`places.id`). 회원앱이 "내 헬스장" 카드에서 헬스장 상세로
    #: 이동하고 상담 대상을 지정하는 데 필요하다 — 이름만으로는 목록의 헬스장과
    #: 이어붙일 수 없다(#324). 아직 gym_id 가 없는 프로필은 None.
    id: str | None = None
    name: str
    address: str
    hours: str
    phone: str


class TrainerMe(BaseModel):
    id: str
    name: str
    email: str
    phone: str
    specialty: str
    career: str          # "7년" (career_years 파생)
    intro: str
    certifications: list[str]
    gym: TrainerGymOut


class TrainerClientOut(BaseModel):
    """고객 로스터 카드 — 프론트 TrainerClient 계약 정렬.

    id 는 회원 User id(하위 엔드포인트 키). 영양소 필드는 회원의
    실제 오늘 식단(DietEntry)에서 집계한 값이다(진짜 데이터 공유).
    """
    id: str                      # member_id — /trainer/clients/{id}/... 키
    name: str
    avatar: str
    #: 카드가 이름 옆에 적는 성별(male|female|other). 저장된 적이 없으면 빈 값이고,
    #: 그때는 앱이 스스로 표시값을 정한다(#960).
    gender: str = ""
    goal: str
    last_message: str
    last_time: str
    #: ISO timestamp used by the roster's recent-message sort. The relative
    #: label above is presentation-only and cannot be ordered reliably.
    last_message_at: _datetime | None = None
    #: 트레이너 화면의 활성/휴면 배지. 담당 관계가 살아 있고(`TrainerClient.active`)
    #: 트레이너가 휴면으로 내리지 않은(`dormant=False`) 회원만 True 다. (#707)
    active: bool
    #: 현재 담당 관계가 등록 상태인지. `active`(활성/휴면 관리 표시)와 별개다.
    registered: bool = True
    calories: int                # 오늘 총 칼로리(회원 실데이터)
    sodium_mg: int               # 오늘 총 나트륨
    sugar_g: float               # 오늘 총 당류(소수)
    carbs_g: float               # 오늘 총 탄수화물(g)
    protein_g: float             # 오늘 총 단백질(g)
    fat_g: float                 # 오늘 총 지방(g)
    last_routine: str            # 마지막 루틴 전송 라벨(오늘/어제/N일 전)
    week_completion: list[int]   # 이번 주 일별 완료율 7개(월→일)
    sodium_week: list[int]       # 최근 7일 일별 나트륨(오래된→오늘)
    #: 최근 7일 일별 칼로리·당류. 나트륨과 같은 창이라 세 지표를 한 그래프에서
    #: 바꿔 가며 볼 수 있다(#746). 당류만 소수를 유지한다.
    calories_week: list[int] = Field(default_factory=list)
    sugar_week: list[float] = Field(default_factory=list)


class TrainerClientStatusUpdate(BaseModel):
    """회원 활성/휴면 전환 입력. (#707)

    `active=False` 는 **담당 관계 해제가 아니다** — 트레이너가 이 회원을 당분간
    관리하지 않는다는 표시이고, 기록·식단·운동·채팅과 담당 링크는 그대로 남는다.
    """
    active: bool


class TrainerClientStatusOut(BaseModel):
    """전환 후의 상태. 로스터 카드의 `active` 와 같은 값이다."""
    member_id: str
    active: bool


class DashboardCoachingClientOut(BaseModel):
    """대시보드 AI 요약에 노출할 고객별 실행 가능한 코칭 인사이트."""

    member_id: str
    member_name: str
    priority: Literal["high", "medium", "low"]
    status_summary: str = Field(min_length=1, max_length=300)
    evidence: list[str] = Field(default_factory=list, max_length=3)
    exercise_focus: str = Field(min_length=1, max_length=300)
    caution: str = Field(default="", max_length=200)


class DashboardCoachingSummaryOut(BaseModel):
    """트레이너 대시보드의 오늘 AI 코칭 요약."""

    headline: str = Field(min_length=1, max_length=300)
    clients: list[DashboardCoachingClientOut] = Field(
        default_factory=list,
        max_length=3,
    )
    generated_by: Literal["ai", "rule"]
    data_as_of: _date


class MemberHealthProfileOut(BaseModel):
    member_id: str
    member_name: str
    height_cm: float | None = None
    weight_kg: float | None = None
    gender: str = ""
    conditions: str = ""
    goals: str = ""
    daily_calories: int | None = None
    daily_sodium_mg: int | None = None
    daily_sugar_g: int | None = None
    daily_carbs_g: int | None = None
    daily_protein_g: int | None = None
    daily_fat_g: int | None = None
    #: 운동 탭이 실제로 견주는 목표 (#1139) — 회원 앱 마이페이지가 쓰는 값이다.
    #: 트레이너 화면도 같은 필드를 읽고 저장해야 한 쪽에서 고친 목표가 다른
    #: 쪽에서 옛 값으로 남지 않는다(#1449).
    daily_burn_kcal: int | None = None
    weekly_cardio_minutes: int | None = None
    weekly_strength_sets: int | None = None
    weekly_flexibility_minutes: int | None = None
    #: 옛 주간 목표(횟수·시간·소모). 다른 화면이 아직 읽고 있어 응답에는
    #: 남기지만, 트레이너 편집 폼은 위의 현행 목표만 다룬다(#1449).
    weekly_workout_goal: int | None = None
    weekly_exercise_minutes_goal: int | None = None
    weekly_burn_goal: int | None = None


class MemberHealthProfileUpdate(PartialUpdate):
    height_cm: float | None = Field(default=None, ge=50, le=300)
    weight_kg: float | None = Field(default=None, ge=20, le=500)
    gender: str | None = Field(default=None, pattern="^(male|female|other|)$")
    conditions: str | None = Field(default=None, max_length=1000)
    goals: str | None = Field(default=None, max_length=500)
    daily_calories: int | None = Field(default=None, ge=500, le=10000)
    daily_sodium_mg: int | None = Field(default=None, ge=0, le=50000)
    daily_sugar_g: int | None = Field(default=None, ge=0, le=1000)
    daily_carbs_g: int | None = Field(default=None, ge=0, le=2000)
    daily_protein_g: int | None = Field(default=None, ge=0, le=1000)
    daily_fat_g: int | None = Field(default=None, ge=0, le=1000)
    daily_burn_kcal: int | None = Field(default=None, ge=0, le=20000)
    weekly_cardio_minutes: int | None = Field(default=None, ge=0, le=10080)
    weekly_strength_sets: int | None = Field(default=None, ge=0, le=1000)
    weekly_flexibility_minutes: int | None = Field(default=None, ge=0, le=10080)
    weekly_workout_goal: int | None = Field(default=None, ge=0, le=21)
    weekly_exercise_minutes_goal: int | None = Field(default=None, ge=0, le=10080)
    weekly_burn_goal: int | None = Field(default=None, ge=0, le=100000)

    nullable_fields: ClassVar[frozenset[str]] = frozenset(
        {
            "height_cm",
            "weight_kg",
            "daily_calories",
            "daily_sodium_mg",
            "daily_sugar_g",
            "daily_carbs_g",
            "daily_protein_g",
            "daily_fat_g",
            "daily_burn_kcal",
            "weekly_cardio_minutes",
            "weekly_strength_sets",
            "weekly_flexibility_minutes",
            "weekly_workout_goal",
            "weekly_exercise_minutes_goal",
            "weekly_burn_goal",
        }
    )


class ClientDietEntryOut(BaseModel):
    """고객 식단 서브탭 한 끼 — 프론트 ClientDietEntry 계약 정렬."""
    #: `DietEntry.id`. 같은 날 같은 끼니(예: 간식 두 번)가 meal_type 중복을
    #: 막는 제약 없이 저장될 수 있어, 화면 목록의 키로 meal 라벨을 쓸 수 없다.
    id: str = ""
    meal: str        # 아침|점심|저녁|간식
    items: str       # 음식명 나열
    # 회원이 자기 앱에서 보는 것과 같은 끼니 카드를 트레이너도 본다(#1166).
    # 시각과 음식별 영양이 없으면 트레이너 화면은 이름 한 줄로 떨어져, 같은
    # 끼니를 두 화면이 다른 수준으로 말한다. 회원 API(`DietEntryOut`)가 이미
    # 같은 `foods_json` 을 그대로 흘려 보낸다 — 키도 그쪽과 같다.
    time_label: str = ""
    foods: list[dict[str, Any]] = []  # [{name, calories, sodium_mg, sugar_g}]
    calories: int
    sodium_mg: int
    # 나트륨과 나란히 읽히는 값인데 이 응답에만 빠져 있어, 트레이너 끼니
    # 카드가 당류를 하루 합계로만 볼 수 있었다(#1025).
    sugar_g: float
    carbs_g: float
    protein_g: float
    fat_g: float
    # 회원이 올린 끼니 사진 경로(API base 기준 상대 경로). 담당 트레이너 전용
    # 경로라 회원 앱이 받는 값과 다르다. 사진이 없으면 null. (#699)
    photo_url: str | None = None


class RoutineHistoryOut(BaseModel):
    """고객 운동기록 서브탭 항목 — 프론트 RoutineHistoryEntry 계약 정렬."""
    id: str = ""
    date_label: str          # "7/12 (오늘)"
    label: str               # "PT 세션 · 트레이너 지도"
    completion_rate: int     # 0..100
    exercises: list[str]
    client_feedback: str
    trainer_note: str
    assigned_routine_id: str | None = None
    completed_at: _datetime | None = None


# 채팅 sender 출력 허용값 — 뷰어 관점(_sender_out): 트레이너 앱은 trainer|client,
# 회원 앱은 me|trainer.
ChatSender = Literal["trainer", "client", "me"]


class ChatAttachmentOut(BaseModel):
    """채팅 메시지에 딸린 파일.

    #778 의 주간 리포트 PDF 로 시작해 #921 에서 이미지가 더해졌다. **두 종류
    뿐이다** — 임의 파일 공유는 이 대화의 목적이 아니고, 받는 쪽이 그릴 수 없는
    형식이 오면 화면은 아이콘 하나만 남긴다.

    `type` 으로 화면이 그릴 방법을 정한다: `pdf` 는 내려받기, `image` 는 대화
    안에서 그린다.
    """
    type: Literal["pdf", "image"]
    file_name: str
    file_id: str
    file_size: int
    download_path: str


class ChatMessageOut(BaseModel):
    """채팅 메시지 — 프론트 ClientChatMessage 계약 정렬.

    sender 는 프론트 계약에 맞춰 'trainer'|'client' 로 노출(백엔드 저장값 member→client).
    created_at(ISO)은 프론트 createdAt 이자 페이지네이션 커서다. 이전 페이지는 이 스레드
    가장 오래된 메시지의 (created_at, id)를 before/before_id 로 넘겨 요청한다.
    """
    id: str
    sender: ChatSender  # trainer|client(트레이너 뷰) | me|trainer(회원 뷰)
    body: str
    time_label: str    # "18:10"
    created_at: str    # ISO datetime — 커서/정렬용
    attachment: ChatAttachmentOut | None = None
    # 주간 리포트 전송 안내라면 그 주 월요일 `YYYY-MM-DD`, 아니면 None. 두 앱은
    # 이 값으로 대화 가운데 안내 상자를 그린다(#1600). 첨부 유무와는 별개다 —
    # 리포트는 PDF 없이 본문만으로도 나간다.
    report_week_start: str | None = None


class ChatSendRequest(BaseModel):
    # 상한만 둔다(빈/공백은 라우터에서 trim 후 400). 과도한 길이는 여기서 422.
    text: str = Field(max_length=2000)
    # 발신 시도당 한 번 만들고 재시도에서 재사용한다. 선택값이라 구버전 앱도
    # 기존처럼 전송할 수 있다.
    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)


#: 운동 유형 — 유산소 / 근력 / 스트레칭 / 기타 네 가지. (#996, #1276)
#:
#: 예전 어휘(걷기·요가·유연성)로 들어오면 422 로 막지 않고 접어 준다. 이미
#: 저장된 루틴과 아직 옛 값을 보내는 화면이 있고, 유형 하나 때문에 배정이 통째로
#: 실패하는 편이 더 나쁘다. 세분화가 필요한 자리는 유형이 아니라 운동 이름으로
#: 적는다.
RoutineType = Annotated[
    Literal["유산소", "근력", "스트레칭", "기타"],
    BeforeValidator(exercise_types.fold_legacy_ko),
]
RoutineSource = Literal["ai", "trainer"]  # ai 추천 | 트레이너 직접 배정

#: 운동 항목의 출처. 'ai' 는 AI 제안을 편집기에 반영한 것, 'trainer' 는 트레이너가
#: 직접 추가한 것. 저장·복원에서도 이 구분이 남아야 화면이 같은 배지를 그린다.
ProgramExerciseSource = Literal["ai", "trainer"]

#: 운동 강도 — 회원 앱의 가벼움/보통/높음과 같은 값이다. 배정 루틴과 프로그램에도
#: 강도를 실어야 트레이너가 짠 운동과 회원이 적은 운동이 같은 칼로리 식을 탄다.
#: (#1276)
RoutineIntensity = Literal["light", "moderate", "high"]


def _loose_int(value: object) -> object:
    """예전 자유 입력("10회"·"3세트"·"")을 정수로 되돌린다. (#1276)

    프로그램 항목은 오래 문자열로 저장돼 왔다. 이제 숫자로 받지만, 이미 저장된
    초안까지 422 로 거절하면 트레이너가 써 둔 프로그램이 열리지 않는다 — 읽는
    자리에서 숫자만 뽑아 준다. 숫자가 없으면 None 이라 "적지 않음"이 된다.
    """
    if not isinstance(value, str):
        return value
    digits = "".join(ch for ch in value if ch.isdigit())
    return int(digits) if digits else None


def _loose_float(value: object) -> object:
    """`_loose_int` 의 소수 판 — 중량("20kg"·"12.5")용."""
    if not isinstance(value, str):
        return value
    kept = "".join(ch for ch in value if ch.isdigit() or ch == ".")
    try:
        return float(kept)
    except ValueError:
        return None


LooseInt = Annotated[int | None, BeforeValidator(_loose_int)]
LooseFloat = Annotated[float | None, BeforeValidator(_loose_float)]


def _loose_int_zero(value: object) -> object:
    """`_loose_int` 의 "적지 않음 = 0" 판 — 템플릿 운동용. (#1310)

    템플릿은 없는 값을 None 이 아니라 0 으로 둔다. 이미 저장된 템플릿에는
    `"10회"` 같은 문자열이 남아 있어, 그대로 읽으면 트레이너가 만들어 둔
    템플릿이 통째로 열리지 않는다.
    """
    coerced = _loose_int(value)
    return 0 if coerced is None else coerced


def _loose_float_zero(value: object) -> object:
    """`_loose_float` 의 "적지 않음 = 0" 판 — 템플릿 중량용. (#1310)"""
    coerced = _loose_float(value)
    return 0.0 if coerced is None else coerced


LooseIntZero = Annotated[int, BeforeValidator(_loose_int_zero)]
LooseFloatZero = Annotated[float, BeforeValidator(_loose_float_zero)]


#: 유형과 맞지 않는 칸을 비운 뒤 자신을 돌려주는 모델.
_ProgramLike = TypeVar("_ProgramLike", bound=BaseModel)


def _drop_fields_not_in_type(model: _ProgramLike) -> _ProgramLike:
    """유형과 맞지 않는 칸을 비운다 — 근력은 시간을, 나머지는 세트·횟수·중량을.

    통일 스펙(#1276)은 유형마다 재는 단위를 하나로 정해 두었다: 유산소·
    스트레칭·기타는 시간, 근력은 세트·횟수·중량. 그런데 값을 **받는** 자리에는
    그 규칙이 없어, 두 칸을 함께 실은 항목이 그대로 저장됐다 — 화면은 그것을
    `저강도 유산소(걷기) 3세트 · 30회` 라고 읽었다. 한 번 그렇게 저장되면 그
    행을 다시 쓰는 화면마다 같은 값이 따라다닌다.

    저장된 행을 되읽는 자리(`_program_items`)도 이 모델을 지나므로, 규칙이 서기
    전에 들어온 행은 고치지 않아도 유형에 맞게 읽힌다.
    """
    if model.type == "근력":
        model.duration = None
    else:
        model.sets = None
        model.reps = None
        model.weight = None
    return model


class ProgramDraftExercise(BaseModel):
    """초안의 운동 한 항목 — 편집기 `ProgramExerciseDraft` 계약 정렬.

    값마다 제 타입으로 받는다(#1276). 예전에는 세트·횟수·중량·시간이 전부
    자유 문자열이라 "10회"·"20kg" 같은 표현이 그대로 저장됐는데, 그러면 같은
    프로그램을 회원 기록과 나란히 집계할 수가 없었다 — 지금은 회원 앱의 운동
    추가와 같은 스펙(날짜·종류·이름·시간 또는 세트·중량·강도)을 쓴다.

    거리·휴식·RPE 는 뺐다. 통일 스펙에 없는 칸이고, 강도가 RPE 자리를
    대신한다. 횟수는 한때 같이 뺐다가 되살렸다(#1310) — 세트·중량만으로는
    근력 한 줄이 재현되지 않는다.
    """
    id: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=100)
    type: RoutineType = "근력"
    #: 이 운동을 하는 날. 아직 일정에 걸지 않은 초안은 비어 있다.
    date: _date | None = None
    #: 유산소·스트레칭·기타의 운동 시간(분). 근력은 세트로 재므로 비어 있다.
    duration: LooseInt = Field(default=None, ge=0, le=600)
    #: 근력의 세트 수·한 세트당 횟수·중량(kg). 다른 유형에서는 비어 있다.
    sets: LooseInt = Field(default=None, ge=0, le=99)
    reps: LooseInt = Field(default=None, ge=0, le=999)
    weight: LooseFloat = Field(default=None, ge=0, le=1000)
    intensity: RoutineIntensity = "moderate"
    memo: str = Field(default="", max_length=300)
    source: ProgramExerciseSource = "trainer"

    _drop_mismatched_fields = model_validator(mode="after")(
        _drop_fields_not_in_type
    )




class RoutineOut(BaseModel):
    """배정 루틴 — 프론트 ClientAiRoutine 계약 정렬.

    다중 세션 프로그램은 세션당 한 건이다(#709). `program_name` 이 같은 건들이
    한 프로그램이고 `session_order` 가 순서다. 단일 배정은 세 값이 비어 있어
    예전 계약과 같다.
    """
    id: str
    name: str
    minutes: int
    #: 이 루틴을 수행하면 예상되는 소모 칼로리. 루틴 이름·유형·시간·강도와 **그
    #: 회원의 체중**에서 계산한 값이라 따로 저장하지 않는다 — 운동을 시간과 칼로리
    #: 두 축으로 보여 주기로 한 뒤(#996) 배정 카드에도 이 값이 필요해졌다.
    calories: int = 0
    #: 위 값의 근거 — db=종목 참조표+체중, mixed=이름 해석만 AI, estimate=유형
    #: 평균 어림값. 회원 앱(`ExerciseSessionOut.calorie_source`)과 같은 어휘라
    #: 두 앱이 같은 기록을 같은 굵기로 보여 준다(#1312).
    calorie_source: str = "estimate"
    type: RoutineType
    #: 트레이너가 언제 하라고 보낸 배정인가. 날짜를 정하지 않았으면 비어 있다.
    exercise_date: _date | None = None
    intensity: RoutineIntensity = "moderate"
    #: 근력 루틴의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 비어 있다.
    #: (#1276, #1310)
    sets: int | None = None
    reps: int | None = None
    weight: float | None = None
    reason: str
    source: RoutineSource
    #: 여러 세션을 묶는 프로그램 이름. 단일 배정은 빈 문자열.
    program_name: str = ""
    #: 이 루틴이 어느 세션인가. 세션이 하나뿐인 프로그램은 빈 문자열.
    session_name: str = ""
    #: 프로그램 안에서의 세션 순서(0부터).
    session_order: int = 0
    #: 그 세션의 운동 구성. 예전에는 이름만 `reason` 에 이어 붙였다.
    exercises: list[ProgramDraftExercise] = Field(default_factory=list)
    #: 이 추천이 무엇을 보고 만들어졌나 — 트레이너 검토용 근거 문구(#790).
    #: 트레이너가 직접 배정한 루틴은 비어 있다.
    evidence: list[str] = Field(default_factory=list)
    completed: bool = False
    completed_at: _datetime | None = None
    completed_minutes: int | None = None
    completed_intensity: str | None = None
    member_note: str = ""
    trainer_feedback: str = ""


class RoutineAssignRequest(BaseModel):
    """루틴 배정 입력. 잘못된 값은 DB 500 이 아니라 422 로 거른다.

    type/source 는 허용값(Literal)만, 길이·범위는 Field 로 제한한다.
    """
    name: str = Field(min_length=1, max_length=100)
    minutes: int = Field(default=0, ge=0, le=600)   # 0..600분(현실적 상한)
    type: RoutineType
    #: 언제 하라고 보내는 배정인가. 회원 앱 운동 추가와 같은 칸이다. (#1276)
    exercise_date: _date | None = None
    intensity: RoutineIntensity = "moderate"
    #: 근력이면 세트 수·한 세트당 횟수·중량(kg). 다른 유형에서 와도 저장하지
    #: 않는다.
    sets: int | None = Field(default=None, gt=0, le=99)
    reps: int | None = Field(default=None, gt=0, le=999)
    weight: float | None = Field(default=None, ge=0, le=1000)
    reason: str = Field(default="", max_length=200)
    source: RoutineSource = "trainer"
    #: 전송 시도당 클라이언트가 만드는 멱등키. 재시도 시 **같은 키를 다시 보내야**
    #: 중복 배정이 막힌다. 없으면 기존처럼 매 요청이 새 배정이다(#581).
    client_request_id: str | None = Field(default=None, max_length=64)


class RoutineSuggestionCreateRequest(BaseModel):
    """AI 개인운동 후보 등록. 검토 대기 상태로만 만들어진다.

    승인 전에는 회원에게 닿지 않으므로 알림도 나가지 않는다.
    """

    name: str = Field(min_length=1, max_length=100)
    minutes: int = Field(ge=0, le=600)
    type: RoutineType
    #: 근력이면 세트 수·한 세트당 횟수·중량(kg). 배정(`RoutineAssignRequest`)과
    #: 같은 계약이다 — 승인하는 순간 이 행이 그대로 배정이 되므로, 여기서 받지
    #: 않으면 근력 제안은 세트가 빈 채로 회원에게 간다(#1321). 다른 유형에서
    #: 와도 저장하지 않는다.
    sets: int | None = Field(default=None, gt=0, le=99)
    reps: int | None = Field(default=None, gt=0, le=999)
    weight: float | None = Field(default=None, ge=0, le=1000)
    reason: str = Field(default="", max_length=200)
    #: 이 후보의 근거 문구. 트레이너가 승인 판단에 쓰는 재료이고 회원에게는
    #: 전달되지 않는다. 개수·길이를 묶는 이유는 카드 한 장이 읽히는 분량을
    #: 넘기면 근거가 오히려 판단을 방해하기 때문이다 — AI 내부 분석을 길게
    #: 노출하지 않는 것이 이 기능의 요구다(#790).
    evidence: list[Annotated[str, Field(min_length=1, max_length=40)]] = Field(
        default_factory=list, max_length=4
    )
    #: 재전송 중복 생성 방지용 멱등키. 배정(`AssignRoutineRequest`)과 같은 규약이다.
    client_request_id: str | None = Field(default=None, max_length=64)


class RoutineSuggestionApproveRequest(PartialUpdate):
    """제안 승인. 필드를 주면 그것으로 고쳐서 승인한다(수정 후 추천).

    아무 필드도 주지 않으면 그대로 승인이다. `RoutineUpdateRequest` 와 같은 이유로
    명시적 null 은 422 다 — 이름·시간을 '지우는 것'은 기능이 아니다.
    """

    name: str | None = Field(default=None, min_length=1, max_length=100)
    minutes: int | None = Field(default=None, ge=0, le=600)
    type: RoutineType | None = None
    #: 근력이면 세트 수·한 세트당 횟수·중량(kg). 트레이너가 승인 직전에 고치는
    #: 자리라, 유형을 근력으로 바꾸며 이 셋을 함께 채우는 것이 이 화면의 흔한
    #: 흐름이다(#1321).
    sets: int | None = Field(default=None, gt=0, le=99)
    reps: int | None = Field(default=None, gt=0, le=999)
    weight: float | None = Field(default=None, ge=0, le=1000)
    reason: str | None = Field(default=None, max_length=200)


class RoutineUpdateRequest(PartialUpdate):
    """루틴 부분 수정. 보낸 필드만 반영한다. (#504)

    `source` 는 없다 — 그 값은 "누가 만들었나"(trainer|ai)라는 사실이지 트레이너가
    고칠 값이 아니다. AI 가 만든 루틴을 손봤다고 해서 트레이너가 만든 것이 되지는
    않는다.

    null 을 허용하는 필드가 없다. 이름·시간·종류·사유 어느 것도 '지우는 것'이
    기능이 아니라, 명시적 null 은 422 다(#495 규약).
    """

    name: str | None = Field(default=None, min_length=1, max_length=100)
    minutes: int | None = Field(default=None, ge=0, le=600)
    type: RoutineType | None = None
    reason: str | None = Field(default=None, max_length=200)


class RoutineFeedbackRequest(BaseModel):
    feedback: str = Field(min_length=1, max_length=2000)


# ---- 프로그램 초안 (#708) ----

#: 세션 하나가 담는 운동 수 상한. 화면이 한 세션에 넣을 수 있는 현실적인 개수를
#: 훨씬 넘는 값이며, 한 요청이 DB 에 무한정 밀어 넣는 것을 막는다.
_PROGRAM_DRAFT_MAX_EXERCISES = 50

#: 한 프로그램의 세션 수 상한. 주 단위 분할(A/B/C…)을 충분히 담는 값이다.
_PROGRAM_MAX_SESSIONS = 12


class ProgramDraftSession(BaseModel):
    """프로그램의 세션 하나 — 편집기 `ProgramSessionDraft` 계약 정렬. (#709)

    순서는 배열 순서다. 별도 정렬 값을 두면 배열과 어긋날 수 있고, 편집기는
    이미 순서를 가진 목록을 들고 있다.
    """
    id: str = Field(min_length=1, max_length=64)
    name: str = Field(default="", max_length=100)
    exercises: list[ProgramDraftExercise] = Field(
        default_factory=list, max_length=_PROGRAM_DRAFT_MAX_EXERCISES
    )


class TrainerProgramDraftOut(BaseModel):
    """저장된 프로그램 초안. 세션은 저장한 순서 그대로 돌아온다."""
    id: str
    name: str
    goal: str
    period: str
    memo: str
    sessions: list[ProgramDraftSession]
    created_at: _datetime
    updated_at: _datetime


class TrainerProgramDraftSummary(BaseModel):
    """목록용 요약 — 운동 구성 전체를 싣지 않는다.

    목록은 "무엇을 저장해 뒀나"만 보여 주고, 편집기로 불러올 때 상세를 읽는다.
    초안 수가 늘어도 목록 응답이 함께 커지지 않는다.
    """
    id: str
    name: str
    goal: str
    period: str
    session_count: int
    exercise_count: int
    updated_at: _datetime


class TrainerProgramDraftCreate(BaseModel):
    """초안 저장 입력."""
    name: str = Field(min_length=1, max_length=100)
    goal: str = Field(default="", max_length=200)
    period: str = Field(default="", max_length=100)
    memo: str = Field(default="", max_length=2000)
    #: 운동이 하나도 없는 초안도 저장할 수 있다 — 이름과 목표만 잡아 둔 상태가
    #: 초안으로서 의미가 있고, 그 상태를 저장하지 못하면 기능이 반쪽이 된다.
    sessions: list[ProgramDraftSession] = Field(
        default_factory=list, max_length=_PROGRAM_MAX_SESSIONS
    )


class TrainerProgramDraftUpdate(PartialUpdate):
    """초안 부분 수정. 보낸 필드만 반영한다.

    `sessions` 는 통째로 교체한다 — 편집기가 항목 단위 diff 가 아니라 현재
    구성 전체를 들고 있고, 부분 병합은 순서가 어긋날 여지만 만든다.
    """

    name: str | None = Field(default=None, min_length=1, max_length=100)
    goal: str | None = Field(default=None, max_length=200)
    period: str | None = Field(default=None, max_length=100)
    memo: str | None = Field(default=None, max_length=2000)
    sessions: list[ProgramDraftSession] | None = Field(
        default=None, max_length=_PROGRAM_MAX_SESSIONS
    )


class ProgramAssignRequest(BaseModel):
    """다중 세션 프로그램을 담당 회원에게 배정하는 입력. (#709)

    세션 하나당 루틴 하나가 만들어진다. 세션이 하나뿐이면 예전 단일 배정과
    같은 모양의 루틴 하나가 되고 세션 라벨이 붙지 않는다 — 회원 화면에 없던
    구분이 갑자기 생기지 않게 하려는 것이다.
    """
    name: str = Field(min_length=1, max_length=100)
    sessions: list[ProgramDraftSession] = Field(
        min_length=1, max_length=_PROGRAM_MAX_SESSIONS
    )
    #: 전송 시도당 클라이언트가 만드는 멱등키. 재시도에 같은 키를 다시 보내면
    #: 프로그램 전체가 두 번 배정되지 않는다(단일 배정과 같은 규약, #581).
    #:
    #: 단건 배정(64)보다 짧다. 서버가 세션마다 `{key}#{index}` 로 나눠 저장하는데
    #: 그 값이 들어갈 컬럼이 `String(64)` 라, 접미사 자리를 남겨 두지 않으면 긴
    #: 키가 저장 단계에서 길이 초과로 터진다.
    client_request_id: str | None = Field(default=None, max_length=48)


#: 메모 출처. 'trainer' 는 회원 상세에서 직접 쓴 메모, 'chat_insight' 는 채팅에서
#: 감지한 신호를 저장한 메모다. 회원 상세는 두 종류를 한 목록으로 보여 준다.
TrainerMemoSource = Literal["trainer", "chat_insight"]


class TrainerMemoOut(BaseModel):
    """회원별 트레이너 메모. (#706)"""
    id: str
    body: str
    source: TrainerMemoSource
    #: 채팅 인사이트에서 만든 메모만 값을 갖는다(중복 저장 방지 키).
    insight_id: str | None = None
    #: 인사이트 종류(discomfort|negativeFeedback). 직접 쓴 메모는 빈 문자열.
    insight_kind: str = ""
    created_at: _datetime
    updated_at: _datetime


class TrainerMemoCreateRequest(BaseModel):
    """메모 작성 입력.

    `insight_id` 를 보내면 그 인사이트에 대해 멱등하다 — 같은 채팅 신호를 다시
    저장해도 메모가 늘지 않고 먼저 저장된 메모가 그대로 돌아온다. 직접 쓴 메모는
    이 값을 보내지 않으므로 같은 내용을 여러 번 남길 수 있다(그것이 기능이다).
    """
    body: str = Field(min_length=1, max_length=2000)
    source: TrainerMemoSource = "trainer"
    insight_id: str | None = Field(default=None, max_length=64)
    insight_kind: str = Field(default="", max_length=32)

    @model_validator(mode="after")
    def _reject_mismatched_source(self) -> TrainerMemoCreateRequest:
        """출처와 중복 방지 키가 짝을 이루는지 본다.

        어긋난 두 조합이 조용히 통과하면 각각 다른 방식으로 망가진다 —
        키 없는 인사이트 메모는 반복 저장 때마다 늘어나고, 직접 쓴 메모가
        `insight_id` 를 가지면 그 인사이트의 유니크 키를 대신 차지한다.
        """
        if self.source == "chat_insight" and not self.insight_id:
            raise ValueError("chat_insight 메모에는 insight_id가 필요합니다.")
        if self.source == "trainer" and self.insight_id:
            raise ValueError("trainer 메모에는 insight_id를 보낼 수 없습니다.")
        return self


class TrainerMemoUpdateRequest(PartialUpdate):
    """메모 부분 수정. 본문만 고칠 수 있다.

    `source`·`insight_id` 는 "이 메모가 어디서 왔나"라는 사실이라 고칠 값이 아니다 —
    채팅에서 생긴 메모를 손봤다고 직접 쓴 메모가 되지는 않고, `insight_id` 를
    바꿀 수 있으면 중복 방지 키가 무너진다.
    """

    body: str | None = Field(default=None, min_length=1, max_length=2000)


#: 후속 관리 할 일이 가리키는 업무 갈래. 할 일에서 어느 화면으로 갈지를 고르는
#: 값이라 열어 두지 않는다 — 앱이 모르는 값이 오면 이동할 곳이 없다. 새 갈래는
#: 앱의 route 매핑과 **함께** 늘린다.
FollowUpTaskContext = Literal[
    "general", "diet", "exercise", "message", "program", "schedule"
]

#: 할 일 상태. 완료는 되돌리지 않으므로 두 값이면 충분하다.
FollowUpTaskStatus = Literal["pending", "completed"]


#: 대시보드/목록이 고르는 조회 범위. `due` 는 오늘까지 처리해야 할 미완료(지난
#: 항목 포함), `open` 은 예정일과 무관한 미완료 전체.
FollowUpScope = Literal["due", "open"]


class TrainerFollowUpTaskOut(BaseModel):
    """고객별 후속 관리 할 일. (#869)"""
    id: str
    member_id: str
    #: 대시보드가 "누구의 할 일인가"를 함께 보여 준다. 트레이너 웹이 할 일마다
    #: 회원을 다시 조회하지 않도록 서버가 채워 준다.
    member_name: str = ""
    title: str
    #: 확인 예정일 `YYYY-MM-DD`(KST).
    due_date: str
    status: FollowUpTaskStatus
    context_type: FollowUpTaskContext
    created_at: _datetime
    updated_at: _datetime
    #: 완료 처리 시각. 미완료는 None.
    completed_at: _datetime | None = None


class TrainerFollowUpTaskCreateRequest(BaseModel):
    """후속 관리 할 일 등록 입력.

    고객은 경로(`/trainer/clients/{member_id}/follow-ups`)가 정하므로 본문에
    두지 않는다 — 두 곳에서 오면 어긋난 조합을 검증할 자리가 생긴다.

    `client_request_id` 를 보내면 그 시도에 대해 멱등하다. 저장 응답을 못 받고
    재시도한 등록이 같은 할 일을 두 번 만들면 대시보드에 같은 줄이 겹쳐 뜬다.
    """
    title: str = Field(min_length=1, max_length=200)
    due_date: str = Field(max_length=10)
    context_type: FollowUpTaskContext = "general"
    client_request_id: str | None = Field(default=None, max_length=64)

    _check_due_date = field_validator("due_date")(_validate_ymd)


class TrainerFollowUpTaskUpdateRequest(PartialUpdate):
    """할 일 부분 수정. 내용과 예정일만 고칠 수 있다.

    상태는 여기서 받지 않는다 — 완료는 완료 시각까지 함께 남기는 상태 전이라
    전용 경로(`POST .../complete`)를 지난다. 고객(`member_id`)도 고치지 않는다:
    다른 고객의 할 일로 옮기는 것은 수정이 아니라 새 할 일이다.
    """

    title: str | None = Field(default=None, min_length=1, max_length=200)
    due_date: str | None = Field(default=None, max_length=10)

    _check_due_date = field_validator("due_date")(
        lambda v: v if v is None else _validate_ymd(v)
    )


RoutineIntensityPreference = Literal["low", "moderate", "high"]
RoutineOptionGenerator = Literal["ai", "rule"]

#: 계획의 강도 라벨. 트레이너 앱이 이 세 값을 그대로 화면에 뿌리므로 열어 두면
#: LLM 이 "아주높음" 같은 값을 반환해도 통과해 UI 가 깨진다(#585). 규칙형 생성기
#: (`routine_ai._B_LABEL`)가 내는 값과 같아야 한다 — 어긋나면 폴백이 422 가 된다.
RoutineIntensityLabel = Literal["낮음", "보통", "높음"]


class RoutineOptionsRequest(BaseModel):
    """회원 데이터 기반 맞춤 루틴 후보 생성 조건.

    두 필드 모두 비워 둘 수 있다(#776) — 운동 기록이 쌓인 회원은 서버가 최근
    패턴에서 값을 채우고, 기록이 없으면 기본값을 쓴다. 트레이너가 값을 보내면
    그 값이 항상 우선한다.
    """

    available_minutes: int | None = Field(default=None, ge=10, le=180)
    intensity_preference: RoutineIntensityPreference | None = None
    trainer_note: str = Field(default="", max_length=500)


#: 분석에 싣는 최근 대화 최대 건수. 서비스의 조회 limit 이 이 값을 그대로 쓴다 —
#: 따로 두면 서비스 쪽만 올렸을 때 여기서 ValidationError 가 나는데, 그 생성은
#: LLM 폴백 try 블록 밖이라 500 이 된다.
ROUTINE_CHAT_MAX_MESSAGES = 10

#: 분석에 싣는 채팅 감지 메모 최대 건수(#1655). 최근 7일치라 실제로는 이보다
#: 적지만, 상한을 스키마에 두는 이유는 [ROUTINE_CHAT_MAX_MESSAGES] 와 같다 —
#: 서비스의 limit 만 올리면 여기서 검증이 터지고, 그 생성은 폴백 밖이라 500 이다.
ROUTINE_INSIGHT_MEMO_MAX = 10

#: 감지 메모를 읽는 기간(일, KST 달력일). 오늘과 이전 6일이다. 프로그램 탭
#: 분석 박스가 보여 주는 창과 같아야 한다 — 화면에 없는 메모가 생성에만
#: 반영되면 트레이너는 왜 그렇게 나왔는지 알 길이 없다.
ROUTINE_INSIGHT_MEMO_DAYS = 7


#: 고객의 운동 데이터 축적도에 따른 추천 방식(#776).
#:
#: * template — 개인 패턴을 판단하기엔 기록이 부족해 목표 기반 기본값을 씀.
#: * learning — 최근 운동은 있지만 반복 패턴이라 부르기엔 아직 이르다.
#: * personalized — 여러 주에 걸쳐 반복된 운동·세션 패턴이 확인된다.
RecommendationStatus = Literal["template", "learning", "personalized"]


class RoutineOptionAnalysisOut(BaseModel):
    goal: str
    member_goal: str = ""
    conditions: str = ""
    gender: str = ""
    height_cm: float | None = None
    weight_kg: float | None = None
    weekly_workout_goal: int | None = None
    weekly_exercise_minutes_goal: int | None = None
    weekly_burn_goal: int | None = None
    sodium_today_mg: int = Field(ge=0)
    sodium_over_target: bool
    avg_completion_rate: int = Field(ge=0, le=100)
    latest_routine: str
    note: str
    #: 최근 트레이너↔회원 대화(오래된→최신). "회원: …" / "트레이너: …" 라벨이
    #: 붙은 한 줄씩이며, 통증·컨디션 언급을 루틴 생성 근거로 쓴다(#580).
    #: 트레이너가 어떤 발화가 반영됐는지 확인할 수 있도록 응답에도 함께 내보낸다.
    recent_messages: list[str] = Field(
        default_factory=list, max_length=ROUTINE_CHAT_MAX_MESSAGES
    )
    #: 최근 7일(KST)의 채팅 감지 메모, 최신 먼저. `"09.01 무릎 불편 감지"` 처럼
    #: 날짜와 요약이 한 줄이다(#1655).
    #:
    #: 회원 발화 원문이 아니라 트레이너가 **메모로 남기기로 한** 감지 요약이다 —
    #: 대화(`recent_messages`)가 14일 창의 원문을 그대로 싣는 것과 달리, 이쪽은
    #: 트레이너가 한 번 걸러 둔 자료라 더 무겁게 볼 수 있다. 손으로 쓴 메모
    #: (`source='trainer'`)는 넣지 않는다.
    insight_memos: list[str] = Field(
        default_factory=list, max_length=ROUTINE_INSIGHT_MEMO_MAX
    )
    #: 이 분석이 어느 추천 단계에 해당하는지(#776). 프론트가 화면 문구를
    #: 정하는 유일한 기준이다 — 프론트가 자체 기준으로 다시 판단하지 않는다.
    recommendation_status: RecommendationStatus = "template"
    #: 분석에 사용한 기간 안의 완료 기록 수.
    history_session_count: int = Field(default=0, ge=0)
    #: 분석에 사용한 최근 기간(일).
    analysis_period_days: int = Field(default=0, ge=0)
    #: 최근 기록에서 반복 확인된 운동 이름(최대 3개, 빈도 높은 순).
    frequent_exercises: list[str] = Field(default_factory=list, max_length=3)
    #: 최근 기록 기반으로 제안하는 운동 가능 시간. 기록이 부족하면 비운다.
    suggested_available_minutes: int | None = Field(default=None, ge=10, le=180)
    #: 최근 기록 기반으로 제안하는 강도. 기록이 부족하면 비운다.
    suggested_intensity: RoutineIntensityPreference | None = None


class RoutineOptionExerciseOut(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    minutes: int = Field(ge=1, le=180)
    type: RoutineType


class RoutineOptionPlanOut(BaseModel):
    key: Literal["A", "B"]
    label: str = Field(min_length=1, max_length=50)
    total_minutes: int = Field(ge=1, le=180)
    intensity: RoutineIntensityLabel
    exercises: list[RoutineOptionExerciseOut] = Field(min_length=1, max_length=12)
    reason: str = Field(min_length=1, max_length=200)
    rationale: str = Field(min_length=1, max_length=500)

    @model_validator(mode="after")
    def _total_matches_exercises(self) -> RoutineOptionPlanOut:
        total = sum(exercise.minutes for exercise in self.exercises)
        if total != self.total_minutes:
            raise ValueError("total_minutes 는 exercises 시간 합계와 같아야 합니다.")
        return self


class RoutineOptionsOut(BaseModel):
    analysis: RoutineOptionAnalysisOut
    plan_a: RoutineOptionPlanOut
    plan_b: RoutineOptionPlanOut
    generated_by: RoutineOptionGenerator

    @model_validator(mode="after")
    def _requires_distinct_a_and_b(self) -> RoutineOptionsOut:
        if self.plan_a.key != "A" or self.plan_b.key != "B":
            raise ValueError("plan_a/plan_b key 는 각각 A/B여야 합니다.")
        return self


# ---- 스케줄 (트레이너 타임라인 + 예약→수업→기록 루프) ----

ScheduleStatus = Literal["예정", "완료", "공백"]


class ProgramItem(BaseModel):
    """세션 프로그램 한 항목 — 코칭 탭 `ProgramDraftExercise` 와 같은 스펙이다.

    두 편집기(스케줄 탭 세션 프로그램·코칭 탭 초안)가 같은 칸을 받는다(#1276).
    예전에는 여기만 `sets: int`, 나머지는 문자열이라 같은 운동이 화면마다 다른
    모양으로 저장됐다.

    `session` 은 다중 세션 프로그램을 일정에 등록할 때 그 항목이 속한 세션
    이름이다(#709). 기존 행에는 이 키가 없고, 없으면 빈 문자열이라 예전처럼
    세션 구분 없는 목록으로 읽힌다.

    PT 완료 자동 기록과 프로그램 전송이 이 값으로 실제 소모 칼로리를 계산한다.
    """
    name: str = Field(min_length=1, max_length=100)
    type: RoutineType = "근력"
    date: _date | None = None
    duration: LooseInt = Field(default=None, ge=0, le=600)
    sets: LooseInt = Field(default=None, ge=0, le=99)
    #: 근력의 한 세트당 횟수. 세트·중량과 한 벌이다(#1310) — 셋이 다 있어야
    #: 트레이너가 짠 근력 한 줄이 회원 화면에서 그대로 재현된다.
    reps: LooseInt = Field(default=None, ge=0, le=999)
    weight: LooseFloat = Field(default=None, ge=0, le=1000)
    intensity: RoutineIntensity = "moderate"
    session: str = Field(default="", max_length=100)

    _drop_mismatched_fields = model_validator(mode="after")(
        _drop_fields_not_in_type
    )


#: 취소 주체. 트레이너 사정의 취소를 회원의 미이행으로 읽지 않으려면 남아 있어야
#: 한다. 빈 문자열은 "취소가 아님"(예정·완료·노쇼)이다. (#871)
CancellationSource = Literal["", "member", "trainer", "other"]


class ScheduleSessionOut(BaseModel):
    """스케줄 슬롯 — 프론트 ScheduleSession 계약 정렬."""
    id: str
    date: str
    time: str
    client_name: str
    type: str
    duration_minutes: int
    status: str          # 예정|완료|취소|노쇼|공백
    note: str
    program: list[ProgramItem]
    #: 완료한 세션의 프로그램을 회원에게 보냈는가. 보낸 적 없는 세션과 이미
    #: 보낸 세션은 화면에서 다른 것을 말해야 한다(#822).
    program_sent: bool = False
    #: 취소·노쇼로 마무리된 세션의 기록. 예정·완료는 전부 비어 있다(#871).
    cancelled_at: _datetime | None = None
    cancellation_source: CancellationSource = ""
    cancellation_reason: str = ""
    no_show_at: _datetime | None = None


class ScheduleProgramSendRequest(BaseModel):
    """완료한 세션의 프로그램을 회원에게 보내는 입력. (#822)

    본문은 멱등키뿐이다 — 무엇을 보낼지는 세션 행이 이미 알고 있고, 클라이언트가
    다시 실어 보내면 화면과 저장된 프로그램이 갈릴 수 있다. 재시도에 같은 키를
    다시 보내면 배정이 두 번 만들어지지 않는다(단일·프로그램 배정과 같은 규약).
    """
    client_request_id: str | None = Field(default=None, max_length=48)


class ScheduleCreateRequest(BaseModel):
    date: str = Field(max_length=10)
    time: str = Field(max_length=10)
    client_name: str = Field(default="", max_length=100)
    member_id: str | None = Field(default=None, max_length=64)
    type: str = Field(default="", max_length=30)
    duration_minutes: int = Field(default=0, ge=0, le=600)
    note: str = Field(default="", max_length=500)
    program: list[ProgramItem] = Field(default_factory=list, max_length=30)
    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)

    _v_date = field_validator("date")(_validate_ymd)
    _v_time = field_validator("time")(_validate_hhmm)


class ScheduleRecurringRequest(BaseModel):
    """주간 반복으로 PT 회차를 한 번에 잡는 입력. (#870)

    이번 범위는 **주간 반복**뿐이다 — PT 운영에서 실제로 쓰이는 형태이고, 월 N번째
    요일 같은 규칙까지 받으면 화면과 검증이 함께 커진다.

    종료 기준은 `count` 또는 `until` **중 하나**다. 둘 다 없으면 끝이 없고, 둘 다
    있으면 어느 쪽이 이겼는지 화면과 서버의 해석이 갈린다.
    """

    date: str = Field(max_length=10)
    time: str = Field(max_length=10)
    client_name: str = Field(default="", max_length=100)
    member_id: str | None = Field(default=None, max_length=64)
    type: str = Field(default="", max_length=30)
    duration_minutes: int = Field(default=0, ge=0, le=600)
    note: str = Field(default="", max_length=500)
    #: 반복할 요일(ISO: 월=1 … 일=7).
    weekdays: list[int] = Field(min_length=1, max_length=7)
    #: 반복 횟수로 끝내기.
    count: int | None = Field(default=None, ge=1, le=52)
    #: 종료일로 끝내기(포함).
    until: str | None = Field(default=None, max_length=10)
    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)

    _v_date = field_validator("date")(_validate_ymd)
    _v_time = field_validator("time")(_validate_hhmm)

    @field_validator("weekdays")
    @classmethod
    def _check_weekdays(cls, value: list[int]) -> list[int]:
        if any(day < 1 or day > 7 for day in value):
            raise ValueError("요일은 1(월)~7(일) 사이여야 합니다.")
        # 같은 요일을 두 번 보내도 회차가 두 배가 되지 않게 여기서 눕힌다.
        return sorted(set(value))

    @model_validator(mode="after")
    def _check_end(self) -> ScheduleRecurringRequest:
        if (self.count is None) == (self.until is None):
            raise ValueError("반복 횟수 또는 종료일 중 하나만 지정해 주세요.")
        if self.until is not None:
            _validate_ymd(self.until)
            if self.until < self.date:
                raise ValueError("종료일은 시작일 이후여야 합니다.")
        return self


class ScheduleRecurringPreviewOut(BaseModel):
    """저장 전에 보여 줄 회차와 충돌. (#870)"""

    #: 생성될 날짜들(`YYYY-MM-DD`, 오름차순).
    dates: list[str]
    #: 그 자리에 이미 있는 세션. 비어 있지 않으면 생성은 409 로 막힌다.
    conflicts: list[ScheduleSessionOut]


class ScheduleProgramRegisterRequest(BaseModel):
    """AI coaching command to attach a program or create its PT session."""

    date: str = Field(max_length=10)
    time: str = Field(max_length=10)
    duration_minutes: int = Field(gt=0, le=600)
    client_name: str = Field(default="", max_length=100)
    program: list[ProgramItem] = Field(min_length=1, max_length=30)

    _v_date = field_validator("date")(_validate_ymd)
    _v_time = field_validator("time")(_validate_hhmm)


class ScheduleProgramRegisterOut(BaseModel):
    session: ScheduleSessionOut
    attached_to_existing: bool


class ScheduleUpdateRequest(PartialUpdate):
    """부분 수정 — 제공된 필드만 반영."""
    date: str | None = Field(default=None)
    time: str | None = Field(default=None, max_length=10)
    client_name: str | None = Field(default=None, max_length=100)
    member_id: str | None = Field(default=None, max_length=64)
    type: str | None = Field(default=None, max_length=30)
    duration_minutes: int | None = Field(default=None, ge=0, le=600)
    note: str | None = Field(default=None, max_length=500)
    program: list[ProgramItem] | None = Field(default=None, max_length=30)

    @field_validator("date")
    @classmethod
    def _v_date(cls, v: str | None) -> str | None:
        return _validate_ymd(v) if v is not None else v

    @field_validator("time")
    @classmethod
    def _v_time(cls, v: str | None) -> str | None:
        return _validate_hhmm(v) if v is not None else v

    #: null 은 '배정 해제'를 뜻하는 member_id 에만 허용한다. 규약 본문은
    #: `PartialUpdate` 에 있다(#495).
    nullable_fields: ClassVar[frozenset[str]] = frozenset({"member_id"})


class ScheduleCompleteRequest(BaseModel):
    note: str = Field(default="", max_length=500)


class ScheduleReopenRequest(BaseModel):
    """완료 세션을 예정으로 되돌리며 옮길 날짜. (#1396)

    과거 날짜로는 되돌리지 않는다 — "완료를 취소"하는 자리가 아니라, 반복
    등록의 시작 회차처럼 이미 끝난 세션을 다가올 약속으로 다시 잡는
    자리이기 때문이다.
    """
    date: str

    @field_validator("date")
    @classmethod
    def _v_date(cls, v: str) -> str:
        return _validate_ymd(v)


class ScheduleCancelRequest(BaseModel):
    """일정 취소 입력. (#871)

    `source` 를 받는 까닭은 지표 때문이다 — 트레이너 사정의 취소와 고객 취소를
    구분하지 않으면 나중에 회원의 낮은 완료율을 잘못 읽는다. 기본값을 두지 않고
    화면이 고르게 한다: 무엇이든 기본으로 저장되면 그 값이 사실인지 알 수 없다.

    `reason` 은 트레이너가 보는 내부 기록이라 선택이다. 회원에게 나가는 알림에는
    싣지 않는다.
    """
    source: Literal["member", "trainer", "other"]
    reason: str = Field(default="", max_length=200)


# ---- 회원측 미러 (내 담당 코치 / 받은 루틴 / 채팅) ----

class MemberCoachOut(BaseModel):
    """회원 앱의 '내 담당 트레이너' 요약."""
    trainer_id: str
    name: str
    specialty: str
    career: str          # "7년"
    intro: str
    gym: TrainerGymOut
    goal: str            # 트레이너가 설정한 내 코칭 목표(TrainerClient.goal)


# ---- 트레이너 프로필 수정 ----

class TrainerMeUpdate(PartialUpdate):
    """PUT /trainer/me — 보낸 필드만 반영(부분 수정).

    이름/이메일은 계정(User)에 속하므로 여기서 바꾸지 않는다. 프로필 화면에서
    바꿀 수 있는 값만 노출한다.

    모든 항목이 DB NOT NULL 이라 null 로 바꿀 수 있는 값이 아니다(#495).
    """
    phone: str | None = Field(default=None, max_length=20)
    specialty: str | None = Field(default=None, max_length=50)
    career_years: int | None = Field(default=None, ge=0, le=80)
    intro: str | None = Field(default=None, max_length=1000)
    certifications: list[str] | None = Field(default=None, max_length=30)
    gym_name: str | None = Field(default=None, max_length=100)
    gym_address: str | None = Field(default=None, max_length=300)
    gym_hours: str | None = Field(default=None, max_length=50)
    gym_phone: str | None = Field(default=None, max_length=20)

    @model_validator(mode="after")
    def _reject_explicit_null(self) -> TrainerMeUpdate:
        """명시적 null 을 422 로 거른다.

        여기 필드는 전부 DB NOT NULL 컬럼이라 null 을 그대로 반영하면
        IntegrityError 500 이 난다. 누락은 '변경 없음', null 은 '잘못된 값'
        으로 구분한다(ScheduleUpdateRequest 와 같은 규약).
        """
        for field in self.model_fields_set:
            if getattr(self, field) is None:
                raise ValueError(f"{field}에는 null을 사용할 수 없습니다.")
        return self


class TrainerGymAffiliation(BaseModel):
    """PUT /trainer/me/gym — 소속 헬스장 설정·변경. (#452)

    위 `gym_*` 문자열과 달리 실재하는 `places` 행을 가리킨다. 해제는 값 대신
    DELETE 로 표현한다 — 이 필드에 null 을 허용하면 "안 보냈다"와 "지워라"가
    같은 요청으로 섞인다.
    """
    gym_id: str = Field(min_length=1, max_length=64)


# ---- 트레이너용 AI 코칭 (회원 데이터 기반) ----

class ClientCoachRequest(BaseModel):
    """트레이너가 담당 고객에 대해 AI에게 묻는 질문."""
    message: str = Field(min_length=1, max_length=1000)


class ClientCoachMessageOut(BaseModel):
    """복원된 문답 한 줄 (#588).

    `role` 은 저장값을 그대로 쓴다(user|coach). 회원 앱의 채팅 계약과 같은 값이라
    프론트가 두 화면에서 같은 분기를 쓸 수 있다.
    """
    role: str
    content: str
    sources: list[str] = Field(default_factory=list)


class ClientCoachOut(BaseModel):
    """AI 답변 + 근거.

    회원 앱의 `/ai-coach/chat` 과 같은 RAG 파이프라인이지만, 검색 스코프가
    **호출한 트레이너가 아니라 담당 회원**이라는 점이 다르다 — 트레이너가
    자기 자신의(비어 있는) 기록으로 코칭받는 일이 없도록.
    """
    member_id: str
    reply: str
    sources: list[str] = []


# ---- 주간 리포트 (트레이너 → 회원) ----

class WeeklyReportDayOut(BaseModel):
    """리포트의 하루 — 그날의 이행률과 실제로 배정된 운동.

    이행률만으로는 67% 가 어디서 나온 값인지 화면에서 알 수 없다. 배정된
    운동과 건너뛴 운동을 함께 내려 주면 분모·분자가 드러난다(#754).
    """
    completion: int              # 0..100 (0 = 그날 기록 없음)
    #: 운동 이름. 끝의 '✓'/'✗' 는 수행 여부를 나타내는 저장 규칙이며 화면은
    #: 그 표시를 읽어 아이콘으로 바꿔 그린다(운동 기록 탭과 같은 규칙).
    exercises: list[str] = Field(default_factory=list)


class WeeklyReportOut(BaseModel):
    """담당 고객 한 명의 한 주 — 트레이너가 회원에게 보낼 수 있는 요약."""
    member_id: str
    member_name: str
    week_start: str              # YYYY-MM-DD (월요일)
    week_end: str                # YYYY-MM-DD (일요일)
    sessions_booked: int
    sessions_done: int
    completion_avg: int | None   # 기록이 없으면 null (0% 아님)
    sodium_over_days: int
    sodium_avg: int | None
    #: 그 주(월→일)의 요일별 값. 로스터의 같은 이름 필드는 **이번 주** 것이라
    #: 과거 주 화면에 쓸 수 없다 — 리포트는 자기 주의 계열을 직접 들고 온다(#752).
    week_completion: list[int] = Field(default_factory=list)
    sodium_week: list[int] = Field(default_factory=list)
    calories_week: list[int] = Field(default_factory=list)
    sugar_week: list[float] = Field(default_factory=list)
    #: 그 주의 일별 탄·단·지(g). 트레이너 화면의 `이번 달` 칼로리 막대를 탄단지로
    #: 쌓는 재료다(#944). 끼니 목록을 날마다 부르면 한 달에 서른 번 넘게 오가므로,
    #: 칼로리·나트륨·당류와 **같은 응답**에 실어 보낸다.
    carbs_week: list[float] = Field(default_factory=list)
    protein_week: list[float] = Field(default_factory=list)
    fat_week: list[float] = Field(default_factory=list)
    #: 그 회원의 하루 목표. 건강 프로필에 적혀 있으면 그 값, 없으면 null 이다
    #: (#1430). 주의사항 판정이 고정 상수보다 이 값을 먼저 쓴다 — 같은 1,900kcal
    #: 이 어떤 회원에게는 부족이고 어떤 회원에게는 초과다. 근거 문장도 어느
    #: 기준을 썼는지 이 값으로 적는다.
    calorie_target: int | None = None
    sodium_target: int | None = None
    sugar_target: float | None = None
    carbs_target: float | None = None
    protein_target: float | None = None
    fat_target: float | None = None
    #: 월→일 7칸. 이행률과 함께 그날의 운동 내역을 담는다(#754).
    days: list[WeeklyReportDayOut] = Field(default_factory=list)
    message: str                 # 회원에게 전송될 본문(미리보기와 동일)


class ReportSummaryOut(BaseModel):
    """리포트 요약 — 트레이너가 피드백 초안으로 가져다 고칠 재료."""
    member_id: str
    week_start: str              # YYYY-MM-DD (월요일)
    headline: str                # 이번 주를 한 문장으로
    #: 근거가 된 수치 문장. 리포트 화면이 이미 보여 주는 값만 담는다 — 요약과
    #: 그래프가 다른 값을 말하면 트레이너가 어느 쪽을 믿어야 할지 모른다.
    points: list[str] = Field(default_factory=list)
    #: `llm` | `rule`. 공급자 장애·미설정이면 규칙 기반으로 되돌아간다.
    generated_by: str


class ReportSendRequest(BaseModel):
    """리포트 전송 — 본문을 직접 주면 그것을, 없으면 서버 생성본을 보낸다."""
    week_start: str | None = Field(default=None, description="YYYY-MM-DD (기본: 이번 주)")
    message: str | None = Field(default=None, max_length=2000)


class ReportFeedbackOut(BaseModel):
    """그 주 리포트에 저장돼 있는 트레이너 피드백 초안. (#821)

    저장한 적이 없으면 `body` 가 빈 문자열이고 `updated_at` 이 null 이다 —
    404 로 답하지 않는 이유는, 초안이 없는 것이 오류가 아니라 정상 상태이고
    화면은 그때 자동 생성 문구를 쓰기 때문이다.
    """
    member_id: str
    week_start: str              # YYYY-MM-DD (월요일)
    body: str
    updated_at: _datetime | None = None


class ReportFeedbackSaveRequest(BaseModel):
    """피드백 초안 저장. 보낸 본문으로 그 주의 초안을 통째로 바꾼다.

    `max_length` 는 전송 본문(`ReportSendRequest.message`)과 같은 2000 자다 —
    저장은 됐는데 보낼 수 없는 길이가 생기면 안 된다.
    """
    week_start: str | None = Field(default=None, description="YYYY-MM-DD (기본: 이번 주)")
    body: str = Field(default="", max_length=2000)


class TrainerPasswordChange(BaseModel):
    """비밀번호 변경 — 현재 비밀번호 확인 후 교체.

    현재 비밀번호를 요구하는 이유: 토큰이 탈취된 상태에서 비밀번호까지
    바꿔 계정을 완전히 뺏기는 경로를 막는다.
    """
    current_password: str = Field(min_length=1, max_length=200)
    new_password: str = Field(min_length=8, max_length=200)


# ---- 알림 수신 설정 (#379) ----

#: 세션 알림 시점 선택지(분). 앱의 SegmentedSwitch 와 같은 목록 — 서버가
#: 계약을 소유하고, 클라이언트는 이 중에서만 고른다.
REMINDER_LEAD_OPTIONS: tuple[int, ...] = (10, 30, 60)


class TrainerNotificationOut(BaseModel):
    """트레이너 알림함 항목. (#503)

    `category` 는 회원 알림의 집합(reminder|health_check|achievement|system)이 아니라
    트레이너 전용 값이다 — `message`|`consultation`|`reservation`. 한 테이블을
    공유하지만 읽는 화면과 이동할 곳이 다르다.
    """

    id: str
    title: str
    body: str
    category: str
    read: bool
    created_at: _datetime
    time_ago: str


class TrainerNotificationSettings(BaseModel):
    """트레이너 알림 수신 설정."""
    notify_new_message: bool
    notify_session_reminder: bool
    reminder_lead_minutes: int


class TrainerNotificationSettingsUpdate(PartialUpdate):
    """부분 수정 — 보낸 필드만 반영.

    세 항목 모두 DB NOT NULL 이라 null 로 바꿀 수 있는 값이 아니다(#495).
    """
    notify_new_message: bool | None = None
    notify_session_reminder: bool | None = None
    reminder_lead_minutes: int | None = None

    @field_validator("reminder_lead_minutes")
    @classmethod
    def _v_lead(cls, v: int | None) -> int | None:
        if v is not None and v not in REMINDER_LEAD_OPTIONS:
            raise ValueError(
                f"reminder_lead_minutes 는 {list(REMINDER_LEAD_OPTIONS)} 중 하나여야 합니다."
            )
        return v

    @model_validator(mode="after")
    def _reject_explicit_null(self) -> TrainerNotificationSettingsUpdate:
        """명시적 null 을 422 로 거른다.

        세 컬럼 모두 DB NOT NULL 이라 null 을 그대로 반영하면 IntegrityError
        500 이 난다. 누락은 '변경 없음', null 은 '잘못된 값' 으로 구분한다
        (TrainerMeUpdate · ScheduleUpdateRequest 와 같은 규약).
        """
        for field in self.model_fields_set:
            if getattr(self, field) is None:
                raise ValueError(f"{field}에는 null을 사용할 수 없습니다.")
        return self


# ---------------------------------------------------------------------------
# 트레이너 → 회원 담당 요청 (#919)
# ---------------------------------------------------------------------------


class PairingCodeRedeem(BaseModel):
    """트레이너가 입력한 6자리 동기화 코드. (#1634)

    자릿수만 서버가 못 박고, 공백·하이픈 같은 표기는 서비스가 걷어낸다 —
    사람이 받아 적는 값이라 표기 차이를 오류로 돌려주면 무엇이 틀렸는지 알 수
    없다.
    """

    code: str = Field(min_length=1, max_length=16)


class PairedMemberOut(BaseModel):
    """동기화가 끝난 회원. 화면이 "이 사람이 맞나요" 를 보여 줄 만큼만 담는다.

    코드를 준 것이 회원 본인이라 신원 확인은 이미 끝났다. 그래도 이름만
    돌려주지 않는 것은, 트레이너가 여섯 자리를 잘못 눌렀을 때 **연결된 뒤에라도**
    그 사실을 알아볼 수 있어야 하기 때문이다.

    키·몸무게·질환 같은 값은 여기 없다. 그것들은 담당 화면의 건강 프로필에서
    조회한다.
    """

    #: 내부 식별자(`User.id`) — 고객 상세로 넘어갈 때 쓴다.
    member_id: str
    name: str
    #: `male`/`female`/`other`. 회원이 자기 앱에 등록해 둔 값이고, 비어 있을 수 있다.
    gender: str = ""
    #: 생년월일로 계산한 만 나이. 회원이 넣지 않았으면 `None`.
    age: int | None = None
    #: 회원이 적어 둔 운동 목표. 비어 있을 수 있다.
    goal: str = ""


class TrainerClientInviteCreate(BaseModel):
    member_id: str = Field(min_length=1, max_length=64)
    #: 회원에게 함께 보이는 한마디. 비워도 된다.
    message: str | None = Field(default=None, max_length=500)


class TrainerClientInviteOut(BaseModel):
    """트레이너가 보고 있는 '보낸 요청' 카드."""

    id: str
    member_id: str
    member_name: str
    member_email: str
    message: str | None = None
    status: Literal["pending", "accepted", "rejected", "cancelled"]
    created_at: _datetime
    decided_at: _datetime | None = None


class MemberInviteAcceptRequest(BaseModel):
    """담당 요청 수락 — 데이터 공유 동의를 함께 받는다. (#1022)

    기본값을 두지 않는다. 빠뜨리면 422 다 — 동의는 "안 보냈으니 승낙" 이 될 수
    없다.
    """

    data_sharing_consent: bool


class MemberClientInviteOut(BaseModel):
    """회원이 보고 있는 '받은 요청' 카드.

    트레이너 응답과 스키마를 나누는 이유는 상담 요청과 같다 — 회원에게는 자기
    이메일이 필요 없고, 트레이너 이름·소속은 반드시 필요하다.
    """

    id: str
    trainer_id: str
    trainer_name: str
    gym_name: str | None = None
    message: str | None = None
    status: Literal["pending", "accepted", "rejected", "cancelled"]
    created_at: _datetime


# ---------------------------------------------------------------------------
# 프로그램 템플릿 — 어느 회원에게든 끼워 넣는 블록 (#920)
# ---------------------------------------------------------------------------

#: 한 템플릿에 담을 수 있는 운동 수. 블록이지 프로그램이 아니라 짧다.
_TEMPLATE_MAX_EXERCISES = 20


class ProgramTemplateExercise(BaseModel):
    """템플릿 안의 운동 한 줄.

    `sets`/`reps`/`weight` 는 근력 운동에서만 쓴다 — `ProgramItem` 과 같은
    계약이라, 템플릿을 적용해 만든 운동이 프로그램 편집기·배정 payload 로
    넘어갈 때 값이 그대로 옮겨진다. 비근력 운동은 `minutes` 만 쓰고 셋은
    기본값(0)으로 둔다.

    횟수는 `"10회"` 같은 문자열이 아니라 수다(#1310). 문자열이던 동안에는
    편집기·배정 payload 가 쓰는 정수와 어긋나 값을 옮길 때마다 숫자만
    되짚어야 했다. 중량은 앱이 보내던 값을 서버가 받을 자리가 없어 조용히
    버려지고 있었다 — 같은 스펙으로 함께 받는다.
    """

    name: str = Field(min_length=1, max_length=100)
    minutes: int = Field(ge=1, le=300)
    type: RoutineType = "근력"
    sets: LooseIntZero = Field(default=0, ge=0, le=99)
    reps: LooseIntZero = Field(default=0, ge=0, le=999)
    weight: LooseFloatZero = Field(default=0, ge=0, le=1000)

    @model_validator(mode="after")
    def _drop_fields_not_in_type(self) -> ProgramTemplateExercise:
        """근력이 아니면 세트·횟수·중량을 비운다 — `_drop_fields_not_in_type`
        와 같은 규칙이고, 빈 값만 이 모델이 쓰는 0 이다.

        `minutes` 는 근력에서도 남긴다: 템플릿은 블록의 길이로 자리를 잡고,
        운동 한 줄이 아니라 끼워 넣을 시간을 먼저 말한다.
        """
        if self.type != "근력":
            self.sets = 0
            self.reps = 0
            self.weight = 0.0
        return self


class TrainerProgramTemplateOut(BaseModel):
    id: str
    name: str
    goal: str
    exercises: list[ProgramTemplateExercise]
    updated_at: _datetime


class TrainerProgramTemplateCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    goal: str = Field(default="", max_length=200)
    #: 운동이 하나도 없는 템플릿은 끼워 넣어도 아무 일이 없다 — 초안과 달리
    #: 빈 상태에 의미가 없으므로 최소 하나를 요구한다.
    exercises: list[ProgramTemplateExercise] = Field(
        min_length=1, max_length=_TEMPLATE_MAX_EXERCISES
    )


class TrainerProgramTemplateUpdate(PartialUpdate):
    """부분 수정. 보낸 필드만 반영한다.

    `exercises` 는 통째로 교체한다 — 편집 화면이 항목 단위 diff 가 아니라 현재
    구성 전체를 들고 있다(초안과 같은 규약).
    """

    name: str | None = Field(default=None, min_length=1, max_length=100)
    goal: str | None = Field(default=None, max_length=200)
    exercises: list[ProgramTemplateExercise] | None = Field(
        default=None, min_length=1, max_length=_TEMPLATE_MAX_EXERCISES
    )
