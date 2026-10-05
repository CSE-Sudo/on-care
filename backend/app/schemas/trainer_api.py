"""
트레이너 API 스키마 — 트레이너 프론트 계약(seedTrainerProfile / TrainerProfile) 정렬.

GET /trainer/me 응답:
  { id, name, email, phone, specialty, career, intro, certifications[], gym{...} }
"""
from __future__ import annotations

import json
from datetime import date as _date, datetime as _datetime
from typing import Annotated, Any, ClassVar, Literal, TypeVar

from pydantic import (
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from app.core import clock
from app.schemas.exercise_limits import (
    MAX_EXERCISE_HOLD_SECONDS,
    MAX_EXERCISE_MINUTES,
    MAX_EXERCISE_REPS,
    MAX_EXERCISE_SECONDS,
    MAX_EXERCISE_SETS,
    MAX_EXERCISE_WEIGHT_KG,
)
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
from app.schemas.text_limits import TEXT_ENTRY_MAX, TEXT_LINE_MAX, TEXT_LONG_MAX
from app.schemas.points_api import PointsOut
from app.services.password_policy import check_new_password
from app.services import contact_format
from app.services import health_focus
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
    #: 소속 헬스장 좌표(`places.lat`·`lng`). 트레이너 웹이 헬스장 찾기 지도를 검색
    #: 전에도 현재 소속 위치로 띄우는 데 쓴다(#3206). 소속이 없거나 좌표가 없으면 None.
    lat: float | None = None
    lng: float | None = None


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
    #: 운영자 계정인가(#3008). 트레이너 웹이 `신고·계정 관리` 메뉴를 보일지 정한다 —
    #: 실제 차단은 `/admin/*` 의 `RequireAdmin` 이 한다.
    is_admin: bool = False
    #: 비밀번호로 로그인하는 계정인가(#3039). 탈퇴 본인 확인에서 현재 비밀번호
    #: 칸과 소셜 다시 로그인 중 무엇을 보일지 고른다. 회원 `ProfileView` 와 같은 뜻.
    has_password: bool = True


class ClientSignalOut(BaseModel):
    """회원 목록의 PT 관리 신호 하나. (#2203)

    기준은 `app/services/client_signals.py` 에 있다. 근거 값은 신호마다 쓰는 것만
    채운다 — 기록 끊김·배정 루틴 미수행은 `days`, 노쇼·취소 반복은 `count`, 운동
    목표 미달·칼로리 이탈·단백질 부족은 `percent`, 칼로리 이탈은 `direction` 도.
    """
    kind: Literal[
        "discomfort",
        "record_gap",
        "no_show",
        "routine_missed",
        "exercise_goal_low",
        "calorie_off",
        "protein_low",
    ]
    #: 기록 끊김: 마지막 기록(없으면 담당 시작일)에서 지난 날 수, 30 이면 30일 넘게.
    #: 배정 루틴 미수행: 루틴이 걸려 있었는데 하나도 완료하지 않은 날 수.
    days: int | None = None
    #: 노쇼·취소 반복: 최근 30일 노쇼와 회원 사정 취소 횟수.
    count: int | None = None
    #: 운동 목표 미달: 경과일 비례 달성률(%). 칼로리 이탈: 목표에서 벗어난 폭(%).
    #: 단백질 부족: 목표 대비 섭취율(%).
    percent: int | None = None
    #: 칼로리 이탈의 방향.
    direction: Literal["over", "under"] | None = None


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
    #: 생년월일로 계산한 만 나이. 회원이 넣지 않았으면 `None` — 앱이 표시값을
    #: 정한다(#2728).
    age: int | None = None
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
    #: 마지막 루틴을 보낸 날(KST, YYYY-MM-DD). 없으면 None (#2300).
    #: `last_routine` 은 서버가 문장으로 만든 라벨이라 화면 언어를 따라가지 못한다
    #: — 앱은 이 날짜로 `오늘`·`N일 전` 을 로케일에 맞춰 직접 그린다. 옛 앱을 위해
    #: `last_routine` 도 계속 보낸다.
    last_routine_date: str | None = None
    #: 이번 주 일별 이행률 7개(월→일). 그날 걸린 개인운동·잡힌 PT 중 한 비율이다
    #: (#2513). 아무것도 걸리지 않은 날과 아직 오지 않은 날은 null 이다 — 0 은
    #: "걸렸는데 하나도 안 했다" 라는 다른 뜻이다.
    week_completion: list[int | None]
    sodium_week: list[int]       # 최근 7일 일별 나트륨(오래된→오늘)
    #: 최근 7일 일별 칼로리·당류. 나트륨과 같은 창이라 세 지표를 한 그래프에서
    #: 바꿔 가며 볼 수 있다(#746). 당류만 소수를 유지한다.
    calories_week: list[int] = Field(default_factory=list)
    sugar_week: list[float] = Field(default_factory=list)
    #: PT 관리 신호, 급한 순(#2203). 담당 해제·휴면 회원은 빈 목록이다. 답장 대기는
    #: 앱이 안 읽은 메시지 수로 따로 센다.
    signals: list[ClientSignalOut] = Field(default_factory=list)


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


class MemberHealthProfileOut(BaseModel):
    member_id: str
    member_name: str
    height_cm: float | None = None
    weight_kg: float | None = None
    gender: str = ""
    conditions: str = ""
    daily_calories: int | None = None
    daily_sodium_mg: int | None = None
    daily_sugar_g: int | None = None
    daily_carbs_g: int | None = None
    daily_protein_g: int | None = None
    #: 식단 분석이 실제로 쓰는 하루 단백질 목표(#2898) — 개인 목표 → 체중 × 1.2g
    #: → 60g. 영양 요약 카드 분모가 이 값이다.
    effective_daily_protein_g: int | None = None
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
    #: 건강 목표를 마지막으로 바꾼 사람(`member`|`trainer`)과 시각(#1832).
    focus_changed_by: str | None = None
    focus_changed_at: _datetime | None = None
    #: 건강상태·주의사항을 마지막으로 바꾼 사람과 시각(#2942). 목표 칩 기록과 따로다.
    notes_changed_by: str | None = None
    notes_changed_at: _datetime | None = None


class MemberHealthProfileUpdate(PartialUpdate):
    height_cm: float | None = Field(default=None, ge=50, le=300)
    weight_kg: float | None = Field(default=None, ge=20, le=500)
    gender: str | None = Field(default=None, pattern="^(male|female|other|)$")
    #: 건강 목표(최대 2개)와 트레이너가 적은 건강상태·주의사항이 함께 담긴다.
    #: 옛 질환 이름은 저장 전에 정리한다 — 회원앱 저장과 같은 규칙이다(#1818).
    #:
    #: 아래 범위는 회원 경로(`HealthGoalsUpdate`·`OnboardingRequest`)와 **같은
    #: 것**이다(#1888). 같은 컬럼을 고치는 두 문이 다른 기준을 쓰면, 한쪽으로
    #: 들어온 값이 다른 쪽에서 고칠 수 없는 값이 된다.
    conditions: ConditionsText | None = None
    daily_calories: DailyCalories | None = None
    daily_sodium_mg: DailySodiumMg | None = None
    daily_sugar_g: DailySugarG | None = None
    daily_carbs_g: DailyCarbsG | None = None
    daily_protein_g: DailyProteinG | None = None
    daily_fat_g: DailyFatG | None = None
    daily_burn_kcal: DailyBurnKcal | None = None
    weekly_cardio_minutes: WeeklyCardioMinutes | None = None
    weekly_strength_sets: WeeklyStrengthSets | None = None
    weekly_flexibility_minutes: WeeklyFlexibilityMinutes | None = None
    weekly_workout_goal: WeeklyWorkoutGoal | None = None
    weekly_exercise_minutes_goal: WeeklyExerciseMinutesGoal | None = None
    weekly_burn_goal: WeeklyBurnGoal | None = None

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

    @field_validator("conditions")
    @classmethod
    def _normalize_conditions(cls, value: str | None) -> str | None:
        # 건강상태·주의사항은 기록 한 건 상한까지다 — 회원 경로와 같다(#2618).
        return check_conditions_notes(health_focus.normalize_conditions(value))

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


#: 이력 종류 코드(#2300). 서버가 붙이는 고정 이름만 코드가 있다 — 트레이너가
#: 지은 루틴 이름처럼 사람이 쓴 이름은 코드 없이 `label` 로만 온다.
#: - ``pt_session``: 완료한 PT 세션 (`PT 세션 · 트레이너 지도`)
#: - ``ai_personal``: AI 개인운동 (`AI 개인운동`, 옛 `AI 루틴 · 자율 운동`)
#: - ``assigned_routine``: 이름 없는 배정 루틴 수행 (`배정 루틴 수행`)
RoutineHistoryKind = Literal[
    "pt_session", "ai_personal", "assigned_routine", "personal_routine"
]


class RoutineHistoryExerciseOut(BaseModel):
    """이력의 운동 한 종목 — 문장이 아닌 값(#2300).

    `exercises` 의 `스쿼트 3세트 12회 40kg` 은 단위가 한국어로 박힌 문장이라 영어
    화면에서도 `세트`·`회` 가 그대로 나온다. 같은 내용을 값으로 나눠 보내고 단위는
    앱이 ARB 로 붙인다. 필드 이름은 앱 `ClientExerciseItem` 과 같다.
    """
    name: str
    #: `cardio` | `strength` | `stretching` | `other`. 모르면 빈 문자열.
    type: str = ""
    minutes: int = 0
    sets: int | None = None
    reps: int | None = None
    hold_seconds: int | None = None
    #: 유산소·스트레칭·기타에 쓴 시간(초). `minutes` 는 여기서 반올림한 값이다.
    #: 초를 적은 배정 수행만 채운다 — 비어 있으면 앱은 `minutes` 로 읽는다.
    #: (#2221)
    duration_seconds: int | None = None
    weight: float | None = None
    #: `light` | `moderate` | `high`. 강도를 적은 기록(배정 수행)만 채운다.
    intensity: str | None = None
    #: 하루치 `개인운동` 카드(#2510)의 **한** 줄에서 트레이너가 처방한 강도.
    #: [intensity] 는 회원이 실제로 고른 강도라, 둘이 다르면 트레이너 화면이
    #: 처방을 회색으로 두고 `수행 …` 을 붙인다(#2508). 안 한 줄은 [intensity]
    #: 가 곧 처방이라 비운다.
    prescribed_intensity: str | None = None
    #: 실제로 했는가(`✓`/`✗`). 표시가 없던 기록은 한 것으로 본다.
    done: bool = True
    #: 하루치 `개인운동` 카드(#2510)에서 한 줄이 가리키는 운동 기록 id. 트레이너
    #: 메모가 줄마다 이 값으로 그 완료를 가리킨다(#2332). 하지 않은 줄은 비어 있다.
    session_id: str | None = None


class RoutineHistoryOut(BaseModel):
    """고객 운동기록 서브탭 항목 — 프론트 RoutineHistoryEntry 계약 정렬."""
    id: str = ""
    date_label: str          # "7/12 (오늘)"
    label: str               # "PT 세션 · 트레이너 지도"
    completion_rate: int     # 0..100
    exercises: list[str]
    #: 이력이 붙는 날(KST, YYYY-MM-DD) — `date_label` 을 만든 바로 그 날이다.
    #: 앱은 이 값으로 `7/12 (오늘)` 을 로케일에 맞춰 그린다(#2300).
    date: str | None = None
    #: `label` 이 서버가 붙인 고정 이름이면 그 코드. 사람이 지은 이름이면 None.
    kind: RoutineHistoryKind | None = None
    #: `exercises` 와 같은 순서·같은 개수의 값 목록(#2300).
    exercise_items: list[RoutineHistoryExerciseOut] = Field(default_factory=list)
    #: 두 칸 모두 트레이너 웹 화면이 읽지 않는다(#2334). 개인운동 이력은 늘 빈
    #: 문자열이고(#1825, #2517), PT 세션 이력의 `trainer_note` 는 PT 완료 때
    #: 복사한 일정의 글이다 — 정리는 일정 글 결정(#2515)과 함께 본다.
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


class RoutineDeliveryCardOut(BaseModel):
    """채팅 가운데 루틴 전송 안내 — 무엇을 보냈나. (#2672)

    [kind] 는 `pt_with_routine`(PT 프로그램과 개인운동) · `routine_only`(개인운동만)
    · `cancelled_routine_only`(취소·노쇼 PT 뒤 개인운동) · `routine`(단건 배정·AI
    제안 승인). 운동 이름은 회원·트레이너가 적은 그대로라 번역하지 않는다.
    """

    kind: str
    program_names: list[str] = Field(default_factory=list)
    routine_names: list[str] = Field(default_factory=list)


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
    # 이모티콘 메시지면 그 id(#2020). 두 앱이 이 값으로 그림을 고르고, 모르는
    # id 면 본문 글로 대신한다 — 앱보다 새 이모티콘이 와도 대화가 깨지지 않는다.
    emote_id: str | None = None
    # 주간 리포트 전송 안내라면 그 주 월요일 `YYYY-MM-DD`, 아니면 None. 두 앱은
    # 이 값으로 대화 가운데 안내 상자를 그린다(#1600). 첨부 유무와는 별개다 —
    # 리포트는 PDF 없이 본문만으로도 나간다.
    report_week_start: str | None = None
    # 루틴 전송 안내라면 그 전송(#2672), 아니면 None. 두 앱이 리포트 안내처럼
    # 대화 가운데 카드로 그린다.
    routine_delivery: RoutineDeliveryCardOut | None = None


class ChatSendRequest(BaseModel):
    # 상한만 둔다(빈/공백은 라우터에서 trim 후 400). 과도한 길이는 여기서 422.
    #
    # 이모티콘만 보낼 때는 본문이 비어 있다 — 그때는 [emote_id] 가 대신 채운다.
    text: str = Field(default="", max_length=TEXT_LONG_MAX)
    #: 이모티콘 id(#2020). 회원은 이용권이 있어야 보낼 수 있고, 트레이너는 그냥
    #: 보낸다. 모르는 id 는 400 이다.
    emote_id: str | None = Field(default=None, min_length=1, max_length=40)
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

#: 개인운동이 어떤 전송에 속하나 — 이력에서 종류를 구분해 보여 준다(#2223, #2225).
#: 'pt_with_routine' 은 PT 프로그램과 함께 정해 그 PT 일정에 붙인 것,
#: 'routine_only' 는 프로그램 만들기의 `개인운동만`, 'cancelled_routine_only' 는
#: PT 취소·노쇼 뒤에 개인운동만 보낸 것이다(#2224). 이 칸이 생기기 전 배정과 AI
#: 제안 후보는 비어 있다.
RoutineDeliveryKind = Literal[
    "pt_with_routine", "routine_only", "cancelled_routine_only"
]

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
        model.duration_seconds = None
        # 한 세트는 회로든 초로든 한 번만 잰다(#1969). 버티는 운동이면 초가
        # 맞고 횟수를 비운다 — 둘이 함께 남으면 `플랭크 3세트 · 10회 · 60초`
        # 처럼 한 줄이 두 단위로 자기를 말한다.
        #
        # 0 이하의 초는 "버티지 않음" 이다 — 빈 칸을 0 으로 채워 보내는
        # 클라이언트가 있어, 0 을 버티기로 읽으면 일반 근력 운동의 횟수가
        # 지워진 채 저장됐다(`스쿼트 3세트 · 12회` → `스쿼트 3세트`).
        if model.hold_seconds is not None and model.hold_seconds > 0:
            model.reps = None
        else:
            model.hold_seconds = None
    else:
        model.sets = None
        model.reps = None
        model.hold_seconds = None
        model.weight = None
    return model


def _sync_duration_units(model: _ProgramLike) -> _ProgramLike:
    """운동 시간의 두 단위 — 분(`duration`)과 초(`duration_seconds`)를 맞춘다. (#2221)

    트레이너 웹은 시·분·초 세 칸으로 적어 초를 보낸다. 분만 있던 동안에는
    45초짜리 운동을 적을 수 없었고, 한 시간이 넘으면 90분처럼 환산해야 했다.

    초가 있으면 **초가 기준**이고 분은 거기서 반올림한 값이다(0 이 아니면
    최소 1분) — 회원 운동 기록(`ExerciseSessionCreate`)과 같은 규칙이다. 분을
    더하는 집계·알림·예전 클라이언트는 분을 그대로 읽는다.

    초가 없으면(이 칸이 생기기 전의 행·분만 보내는 클라이언트) 분 × 60 으로
    채운다. 그래서 읽는 쪽은 언제나 초를 믿으면 된다.
    """
    if model.duration_seconds is not None:
        seconds = model.duration_seconds
        model.duration = max(1, round(seconds / 60)) if seconds > 0 else 0
    elif model.duration is not None:
        model.duration_seconds = model.duration * 60
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
    #: `duration_seconds` 가 있으면 거기서 반올림한 값이다(#2221).
    duration: LooseInt = Field(default=None, ge=0, le=600)
    #: 같은 운동 시간을 초로(#2221). 트레이너가 시·분·초로 적은 그대로다 —
    #: 비어 오면 `duration` × 60 으로 채운다([_sync_duration_units]).
    duration_seconds: LooseInt = Field(default=None, ge=0, le=MAX_EXERCISE_SECONDS)
    #: 근력의 세트 수·한 세트당 횟수·중량(kg). 다른 유형에서는 비어 있다.
    sets: LooseInt = Field(default=None, ge=0, le=MAX_EXERCISE_SETS)
    reps: LooseInt = Field(default=None, ge=0, le=MAX_EXERCISE_REPS)
    #: 버티는 운동이면 한 세트를 버티는 시간(초). `reps` 와 한 자리를 나눠
    #: 쓴다 — 이 값이 있으면 횟수가 비고, 없으면 반대다(#1969). 이 칸이 없던
    #: 동안 트레이너는 "플랭크 3세트 · 60초" 를 **이름에** 적을 수밖에 없었고,
    #: 이름에 적힌 글자는 어떤 집계에도 잡히지 않았다.
    hold_seconds: LooseInt = Field(
        default=None, ge=0, le=MAX_EXERCISE_HOLD_SECONDS
    )
    weight: LooseFloat = Field(default=None, ge=0, le=MAX_EXERCISE_WEIGHT_KG)
    intensity: RoutineIntensity = "moderate"
    memo: str = Field(default="", max_length=300)
    source: ProgramExerciseSource = "trainer"
    #: 회원에게 보일 효과 한 줄(#2570). `개인운동만` 은 세션마다 운동이 하나라
    #: 이 값이 그 배정의 효과가 된다. 비면 서버가 문구표로 채운다.
    effect: str = Field(default="", max_length=40)

    _drop_mismatched_fields = model_validator(mode="after")(
        _drop_fields_not_in_type
    )
    # 유형에 맞지 않는 칸을 비운 **뒤에** 맞춘다 — 근력의 시간은 둘 다 빈다.
    _sync_duration = model_validator(mode="after")(_sync_duration_units)




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
    #: 버티는 루틴이면 한 세트를 버티는 시간(초). `reps` 와 한 자리를 나눠
    #: 쓴다 — 있으면 횟수가 비고, 없으면 반대다. (#1969)
    hold_seconds: int | None = None
    #: 유산소·스트레칭·기타의 운동 시간(초)(#2221). `minutes` 는 여기서 반올림한
    #: 값이다. 초를 적지 않은 예전 배정은 `minutes` × 60 으로 채워 오고, 근력은
    #: 세트로 재므로 비어 있다.
    duration_seconds: int | None = None
    weight: float | None = None
    reason: str
    #: 회원에게 보일 효과 한 줄(#2570). 트레이너가 적은 값, 없으면 운동 유형 ×
    #: 회원 건강 목표 문구표의 값이다. 운동 여럿으로 짠 PT 세션처럼 한 줄로
    #: 말할 수 없는 배정은 비어 있다.
    effect: str = ""
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
    #: 회원이 완료한 기록의 시간(초). 초로 남기지 않은 기록은 비어 있다(#2221).
    completed_duration_seconds: int | None = None
    completed_intensity: str | None = None
    #: 개인 운동 피드백은 회원(#1825)·트레이너(#2517) 모두 없앴다. 늘 빈
    #: 문자열이며, 이 칸을 읽는 옛 앱을 위해 모양만 남긴다.
    member_note: str = ""
    trainer_feedback: str = ""
    #: 이 개인운동이 붙어 있는 PT 일정(#2223). 개인운동만 보낸 배정은 비어 있다.
    schedule_id: str | None = None
    #: 그 PT 일정의 날짜(#2225). 미전송 알림이 스케줄 탭의 **그 주**를 열어야
    #: 해서 필요하다 — 날짜 없이 일정 id 만 보내면 이번 주에서 찾지 못한다.
    #: 미전송 조회에서만 채운다. 일정의 날짜 칸과 같은 `YYYY-MM-DD` 문자열이다
    #: (`ScheduleSessionOut.date` 와 같은 어휘).
    schedule_date: str = ""
    #: PT 일정에 붙여만 두고 **아직 회원에게 보내지 않았는가**(#2224). 일정
    #: 상세가 보낸 것과 보낼 것을 같은 목록에서 가르는 데 쓴다. 회원 앱이 보는
    #: 배정은 모두 이미 보낸 것이라 언제나 거짓이다.
    pending_send: bool = False
    #: 어떤 전송에 속한 개인운동인가(#2225). 이 칸이 생기기 전 배정은 비어 있다.
    delivery_kind: RoutineDeliveryKind | None = None
    #: 전송에 붙인 회원에게 한마디. 선택 입력이라 보통 빈 문자열이다(#2223).
    trainer_message: str = ""


class UpcomingRoutinesOut(BaseModel):
    """GET /me/coach/routines/upcoming — 아직 시작하지 않은 개인운동 한 묶음. (#3106)

    트레이너가 `개인운동만` 을 미래 시작일로 보내면(#2656) 알림은 바로 가지만, 그날
    목록(`/me/coach/routines`)은 시작일부터 그 운동을 싣는다. 회원 앱은 이 값으로
    오늘 목록 아래에 `8/22(토)부터 · 빠르게 걷기 · …` 한 줄을 둔다. 둘 이상이면
    가장 최근에 보낸 것 하나다.
    """

    #: 걸리기 시작하는 날 — 이날부터 그날 목록에 들어 체크할 수 있다.
    starts_on: _date
    #: 트레이너가 보낸 날.
    sent_on: _date
    #: 묶음의 운동 이름(배정 순서).
    names: list[str]


class RoutineCompleteOut(RoutineOut):
    """POST /me/coach/routines/{id}/complete 응답 — 이번 완료의 포인트 적립을 더한다. (#1786)

    AI 추천 루틴과 트레이너 배정 루틴 모두 `추천·배정 운동 완료` 규칙으로 적립하고
    하루 한도 1회를 함께 쓴다. 목록 응답(`RoutineOut`)에는 붙지 않는다.
    """

    points: PointsOut


class RoutineAssignRequest(BaseModel):
    """루틴 배정 입력. 잘못된 값은 DB 500 이 아니라 422 로 거른다.

    type/source 는 허용값(Literal)만, 길이·범위는 Field 로 제한한다.
    """
    name: str = Field(min_length=1, max_length=100)
    minutes: int = Field(default=0, ge=0, le=600)   # 0..600분(현실적 상한)
    #: 같은 운동 시간을 초로(#2547). 보내면 이 값이 기준이고 `minutes` 는
    #: 거기서 반올림한다 — 개인운동(`PersonalRoutineItem`)과 같은 규칙이다. 분만
    #: 보내는 예전 클라이언트는 그대로 받는다.
    duration_seconds: int | None = Field(
        default=None, ge=0, le=MAX_EXERCISE_SECONDS
    )
    type: RoutineType
    #: 언제 하라고 보내는 배정인가. 회원 앱 운동 추가와 같은 칸이다. (#1276)
    exercise_date: _date | None = None
    intensity: RoutineIntensity = "moderate"
    #: 근력이면 세트 수·한 세트당 횟수·중량(kg). 다른 유형에서 와도 저장하지
    #: 않는다.
    sets: int | None = Field(default=None, gt=0, le=MAX_EXERCISE_SETS)
    reps: int | None = Field(default=None, gt=0, le=MAX_EXERCISE_REPS)
    #: 버티는 운동이면 한 세트를 버티는 시간(초). `reps` 와 한 자리를 나눠
    #: 쓴다 — 이 값을 보내면 서버가 횟수를 비운다. (#1969)
    hold_seconds: int | None = Field(
        default=None, gt=0, le=MAX_EXERCISE_HOLD_SECONDS
    )
    weight: float | None = Field(default=None, ge=0, le=MAX_EXERCISE_WEIGHT_KG)
    reason: str = Field(default="", max_length=200)
    source: RoutineSource = "trainer"
    #: 전송 시도당 클라이언트가 만드는 멱등키. 재시도 시 **같은 키를 다시 보내야**
    #: 중복 배정이 막힌다. 없으면 기존처럼 매 요청이 새 배정이다(#581).
    client_request_id: str | None = Field(default=None, max_length=64)

    @model_validator(mode="after")
    def _minutes_from_seconds(self) -> "RoutineAssignRequest":
        """초가 오면 분을 거기서 반올림한다. 근력은 세트로 재므로 초를 비운다. (#2547)"""
        if self.type == "근력":
            self.duration_seconds = None
        elif self.duration_seconds is not None:
            seconds = self.duration_seconds
            self.minutes = max(1, round(seconds / 60)) if seconds > 0 else 0
        return self


class RoutineSuggestionCreateRequest(BaseModel):
    """AI 개인운동 후보 등록. 검토 대기 상태로만 만들어진다.

    승인 전에는 회원에게 닿지 않으므로 알림도 나가지 않는다.
    """

    name: str = Field(min_length=1, max_length=100)
    minutes: int = Field(default=0, ge=0, le=600)
    #: 같은 운동 시간을 초로(#2547). 보내면 이 값이 기준이고 `minutes` 는
    #: 거기서 반올림한다 — 개인운동(`PersonalRoutineItem`)과 같은 규칙이다. 분만
    #: 보내는 예전 클라이언트는 그대로 받는다.
    duration_seconds: int | None = Field(
        default=None, ge=0, le=MAX_EXERCISE_SECONDS
    )
    type: RoutineType
    #: 근력이면 세트 수·한 세트당 횟수·중량(kg). 배정(`RoutineAssignRequest`)과
    #: 같은 계약이다 — 승인하는 순간 이 행이 그대로 배정이 되므로, 여기서 받지
    #: 않으면 근력 제안은 세트가 빈 채로 회원에게 간다(#1321). 다른 유형에서
    #: 와도 저장하지 않는다.
    sets: int | None = Field(default=None, gt=0, le=MAX_EXERCISE_SETS)
    reps: int | None = Field(default=None, gt=0, le=MAX_EXERCISE_REPS)
    #: 버티는 운동이면 한 세트를 버티는 시간(초). `reps` 와 한 자리를 나눠
    #: 쓴다 — 이 값을 보내면 서버가 횟수를 비운다. (#1969)
    hold_seconds: int | None = Field(
        default=None, gt=0, le=MAX_EXERCISE_HOLD_SECONDS
    )
    weight: float | None = Field(default=None, ge=0, le=MAX_EXERCISE_WEIGHT_KG)
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

    @model_validator(mode="after")
    def _minutes_from_seconds(self) -> "RoutineSuggestionCreateRequest":
        """초가 오면 분을 거기서 반올림한다. 근력은 세트로 재므로 초를 비운다. (#2547)"""
        if self.type == "근력":
            self.duration_seconds = None
        elif self.duration_seconds is not None:
            seconds = self.duration_seconds
            self.minutes = max(1, round(seconds / 60)) if seconds > 0 else 0
        return self


class RoutineSuggestionApproveRequest(PartialUpdate):
    """제안 승인. 필드를 주면 그것으로 고쳐서 승인한다(수정 후 추천).

    아무 필드도 주지 않으면 그대로 승인이다. `RoutineUpdateRequest` 와 같은 이유로
    명시적 null 은 422 다 — 이름·시간을 '지우는 것'은 기능이 아니다.
    """

    name: str | None = Field(default=None, min_length=1, max_length=100)
    minutes: int | None = Field(default=None, ge=0, le=600)
    #: 같은 운동 시간을 초로(#2547). 보내면 이 값이 기준이고 분은 서버가 초에서
    #: 다시 접는다. 분만 보내면 예전 초를 지운다 — 남겨 두면 초를 먼저 읽는
    #: 화면들이 고치기 전 시간을 계속 보여 준다.
    duration_seconds: int | None = Field(
        default=None, ge=0, le=MAX_EXERCISE_SECONDS
    )
    type: RoutineType | None = None
    #: 근력이면 세트 수·한 세트당 횟수·중량(kg). 트레이너가 승인 직전에 고치는
    #: 자리라, 유형을 근력으로 바꾸며 이 셋을 함께 채우는 것이 이 화면의 흔한
    #: 흐름이다(#1321).
    sets: int | None = Field(default=None, gt=0, le=MAX_EXERCISE_SETS)
    reps: int | None = Field(default=None, gt=0, le=MAX_EXERCISE_REPS)
    #: 버티는 운동이면 한 세트를 버티는 시간(초). `reps` 와 한 자리를 나눠
    #: 쓴다 — 이 값을 보내면 서버가 횟수를 비운다. (#1969)
    hold_seconds: int | None = Field(
        default=None, gt=0, le=MAX_EXERCISE_HOLD_SECONDS
    )
    weight: float | None = Field(default=None, ge=0, le=MAX_EXERCISE_WEIGHT_KG)
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
    #: 같은 운동 시간을 초로(#2547). 보내면 이 값이 기준이고 분은 서버가 초에서
    #: 다시 접는다. 분만 보내면 예전 초를 지운다 — 남겨 두면 초를 먼저 읽는
    #: 화면들이 고치기 전 시간을 계속 보여 준다.
    duration_seconds: int | None = Field(
        default=None, ge=0, le=MAX_EXERCISE_SECONDS
    )
    type: RoutineType | None = None
    reason: str | None = Field(default=None, max_length=200)


# ---- 프로그램 초안 (#708) ----

#: 세션 하나가 담는 운동 수 상한. 화면이 한 세션에 넣을 수 있는 현실적인 개수를
#: 훨씬 넘는 값이며, 한 요청이 DB 에 무한정 밀어 넣는 것을 막는다.
_PROGRAM_DRAFT_MAX_EXERCISES = 50

#: 한 프로그램의 세션 수 상한. 주 단위 분할(A/B/C…)을 충분히 담는 값이다.
_PROGRAM_MAX_SESSIONS = 12

#: 한 프로그램 **전체**의 운동 수 상한. 일정 한 건이 담는 항목 상한과 같다 —
#: 초안·배정·일정 추가가 같은 크기를 받아야 배정은 되고 일정만 422 가 되는 경로가
#: 없다(#1583). 트레이너 웹 편집기(`kProgramMaxExercises`)도 같은 값을 쓴다.
_PROGRAM_MAX_TOTAL_EXERCISES = 30


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


def _check_program_total_exercises(
    sessions: list[ProgramDraftSession] | None,
) -> list[ProgramDraftSession] | None:
    """세션 전체의 운동 수가 [_PROGRAM_MAX_TOTAL_EXERCISES] 이하인지 본다(#1583)."""
    if sessions is not None and (
        sum(len(session.exercises) for session in sessions)
        > _PROGRAM_MAX_TOTAL_EXERCISES
    ):
        raise ValueError(
            f"운동은 프로그램 전체에서 최대 {_PROGRAM_MAX_TOTAL_EXERCISES}개까지 담을 수 있습니다."
        )
    return sessions


#: 자동 보관 작성 상태(`workspace`)를 JSON 으로 옮긴 길이 상한(#2873). 위저드의
#: A/B 후보·분석과 개인운동을 넉넉히 담고, 한 요청이 화면 상태라며 큰 덩어리를
#: 밀어 넣는 것은 막는다.
PROGRAM_WORKSPACE_MAX_CHARS = 64_000


def _check_program_workspace(
    workspace: dict[str, Any] | None,
) -> dict[str, Any] | None:
    """작성 상태가 [PROGRAM_WORKSPACE_MAX_CHARS] 를 넘지 않는지 본다(#2873)."""
    if workspace is not None and (
        len(json.dumps(workspace, ensure_ascii=False))
        > PROGRAM_WORKSPACE_MAX_CHARS
    ):
        raise ValueError("작성 상태가 너무 큽니다.")
    return workspace


class TrainerProgramDraftOut(BaseModel):
    """저장된 프로그램 초안. 세션은 저장한 순서 그대로 돌아온다."""
    id: str
    name: str
    goal: str
    period: str
    memo: str
    sessions: list[ProgramDraftSession]
    #: 자동 보관한 회원(#2873). 회원 없는 초안(#708)은 비어 있다.
    member_id: str | None = None
    #: 편집기 밖의 작성 상태 — 위저드 단계·후보·개인운동(#2873). 화면이 쓰고
    #: 화면이 읽는 값이라 서버는 해석하지 않는다.
    workspace: dict[str, Any] = Field(default_factory=dict)
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
    #: 자동 보관한 회원(#2873). 회원 없는 초안은 비어 있다.
    member_id: str | None = None
    updated_at: _datetime


class TrainerProgramDraftCreate(BaseModel):
    """초안 저장 입력."""
    name: str = Field(min_length=1, max_length=100)
    goal: str = Field(default="", max_length=200)
    period: str = Field(default="", max_length=100)
    memo: str = Field(default="", max_length=TEXT_ENTRY_MAX)
    #: 운동이 하나도 없는 초안도 저장할 수 있다 — 이름과 목표만 잡아 둔 상태가
    #: 초안으로서 의미가 있고, 그 상태를 저장하지 못하면 기능이 반쪽이 된다.
    sessions: list[ProgramDraftSession] = Field(
        default_factory=list, max_length=_PROGRAM_MAX_SESSIONS
    )
    #: 코칭 화면이 자동 보관하는 회원(#2873). 담당 회원이 아니면 404 다.
    #: 비우면 지금까지처럼 회원 없는 초안이다.
    member_id: str | None = Field(default=None, min_length=1, max_length=64)
    workspace: dict[str, Any] | None = None

    _v_total = field_validator("sessions")(_check_program_total_exercises)
    _v_workspace = field_validator("workspace")(_check_program_workspace)


class TrainerProgramDraftUpdate(PartialUpdate):
    """초안 부분 수정. 보낸 필드만 반영한다.

    `sessions` 는 통째로 교체한다 — 편집기가 항목 단위 diff 가 아니라 현재
    구성 전체를 들고 있고, 부분 병합은 순서가 어긋날 여지만 만든다.
    """

    name: str | None = Field(default=None, min_length=1, max_length=100)
    goal: str | None = Field(default=None, max_length=200)
    period: str | None = Field(default=None, max_length=100)
    memo: str | None = Field(default=None, max_length=TEXT_ENTRY_MAX)
    sessions: list[ProgramDraftSession] | None = Field(
        default=None, max_length=_PROGRAM_MAX_SESSIONS
    )
    #: 작성 상태는 통째로 교체한다(#2873). 회원은 바꾸지 않는다 — 다른 회원에게
    #: 짜던 내용이 되면 새 초안이다.
    workspace: dict[str, Any] | None = None

    _v_total = field_validator("sessions")(_check_program_total_exercises)
    _v_workspace = field_validator("workspace")(_check_program_workspace)


class PersonalRoutineItem(BaseModel):
    """PT 프로그램과 함께 정한 개인운동 한 건. (#2223)

    회원이 PT 사이에 혼자 할 운동이다. PT 프로그램과 같은 전송에 실려 오지만
    회원에게 바로 가지 않는다 — 그 PT 를 완료할 때 함께 보낸다(#2224). 그래서
    배정 입력([RoutineAssignRequest])과 칸은 같아도 `source` 와 멱등키가 없다:
    출처는 AI 제안인지 트레이너가 직접 넣은 것인지로 서버가 정하고, 멱등은
    전송 전체의 키 하나가 맡는다.
    """

    name: str = Field(min_length=1, max_length=100)
    minutes: int = Field(default=0, ge=0, le=600)
    #: 같은 운동 시간을 초로(#2221). 보내면 이 값이 기준이고 `minutes` 는
    #: 거기서 반올림한다 — 프로그램 운동(`ProgramDraftExercise`)과 같은 규칙이다.
    duration_seconds: int | None = Field(
        default=None, ge=0, le=MAX_EXERCISE_SECONDS
    )
    type: RoutineType
    intensity: RoutineIntensity = "moderate"
    sets: int | None = Field(default=None, gt=0, le=MAX_EXERCISE_SETS)
    reps: int | None = Field(default=None, gt=0, le=MAX_EXERCISE_REPS)
    hold_seconds: int | None = Field(
        default=None, gt=0, le=MAX_EXERCISE_HOLD_SECONDS
    )
    weight: float | None = Field(default=None, ge=0, le=MAX_EXERCISE_WEIGHT_KG)
    reason: str = Field(default="", max_length=200)
    #: 회원에게 보일 효과 한 줄(#2570). 트레이너가 적은 것만 오고, 비면 서버가
    #: 운동 유형 × 회원 건강 목표 문구표로 채운다.
    effect: str = Field(default="", max_length=40)
    source: RoutineSource = "trainer"

    @model_validator(mode="after")
    def _minutes_from_seconds(self) -> "PersonalRoutineItem":
        """초가 오면 분을 거기서 반올림한다. 근력은 세트로 재므로 초를 비운다."""
        if self.type == "근력":
            self.duration_seconds = None
        elif self.duration_seconds is not None:
            seconds = self.duration_seconds
            self.minutes = max(1, round(seconds / 60)) if seconds > 0 else 0
        return self


#: 한 PT 일정에 붙일 수 있는 개인운동 수의 상한. 프로그램 세션 상한과 같은
#: 값이다(#2223) — `개인운동만` 은 운동 하나가 세션 하나가 되므로, 두 경로에
#: 다른 상한을 두면 같은 목록이 한쪽에서만 거절된다.
_MAX_PERSONAL_ROUTINES = _PROGRAM_MAX_SESSIONS

#: 위저드가 개인운동 단계를 채운 AI 제안 id(#2747). 개인운동 한 줄이 제안 하나라
#: 개인운동 상한과 같다.
_SuggestionId = Annotated[str, Field(min_length=1, max_length=64)]


class ScheduleRoutineUpdateRequest(BaseModel):
    """PT 에 붙은 개인운동을 고친다 — 보내지 않는다. (#2224)

    비울 수 없다: 개인운동은 PT 마다 최소 한 개라는 규칙(#2223)이 여기서도
    같다.
    """

    personal_routines: list[PersonalRoutineItem] = Field(
        min_length=1, max_length=_MAX_PERSONAL_ROUTINES
    )
    # 이 개인운동을 채운 대기 중 AI 제안 — 고치기와 같은 트랜잭션에서 닫는다
    # (#2747). 이미 있는 PT 에 붙이는 길도 프로그램 만들기와 같은 규칙이다.
    suggestion_ids: list[_SuggestionId] = Field(
        default_factory=list, max_length=_MAX_PERSONAL_ROUTINES
    )


class ScheduleRoutineSendRequest(BaseModel):
    """마무리된 PT 의 개인운동을 보낸다 — 고쳐서 보낼 수도 있다. (#2224)

    [personal_routines] 를 비우면 붙어 있던 그대로 보낸다. 주면 그 내용으로
    갈아 끼운 뒤 보낸다 — 취소된 PT 에는 프로그램 만들기로 다시 붙일 수 없어
    (`예정` 세션만 찾는다) 고치는 자리가 이 요청뿐이다.
    """

    personal_routines: list[PersonalRoutineItem] | None = Field(
        default=None, max_length=_MAX_PERSONAL_ROUTINES
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
    #: 이 배정이 어떤 전송인가(#2223). 프로그램 만들기의 `개인운동만` 은
    #: 'routine_only' 를 실어 보내 이력에서 PT 와 함께 간 전송과 구분된다.
    #: 비우면 예전처럼 종류 없는 배정이다.
    delivery_kind: RoutineDeliveryKind | None = None
    #: 회원에게 함께 남기는 한마디(선택). 예: "이번 주는 PT 쉬어요, 이것만
    #: 챙겨 주세요".
    trainer_message: str = Field(default="", max_length=200)
    #: 회원이 이 운동을 시작할 날(#2223). 비우면 예전처럼 날짜 없는 배정이다.
    start_date: _date | None = None
    #: 이 배정이 회원 목록에 **며칠간 걸려 있는가**(#2223). 배정한 날을 1일로
    #: 센다.
    #:
    #: 추천 개인운동은 매일 새로 체크하는 목록이고 걸려 있는 기간은
    #: `active_from`~`ended_on` 이 정한다(#2161). 프로그램 만들기의 `개인운동만`
    #: 은 7 을 보내 보낸 날부터 한 주 동안 걸어 두고, 다음 주 분은 트레이너가
    #: 다시 보낸다. 비우면 트레이너가 철회할 때까지 걸려 있는 기존 배정이다.
    active_days: int | None = Field(default=None, ge=1, le=31)
    #: 이 전송에 실린 개인운동을 채운 **대기 중 AI 제안** id(#2747). 배정과 같은
    #: 트랜잭션에서 그 제안을 닫는다 — 대기로 남으면 다음 위저드가 보낸 제안을
    #: 다시 채우고, 쌓인 대기가 백로그 한도를 막아 새 제안이 끊긴다. 남의
    #: 제안·이미 검토한 제안 id 는 조용히 무시한다.
    suggestion_ids: list[_SuggestionId] = Field(
        default_factory=list, max_length=_MAX_PERSONAL_ROUTINES
    )

    _v_total = field_validator("sessions")(_check_program_total_exercises)


#: 메모 출처. 'trainer' 는 회원 상세에서 직접 쓴 메모, 'chat_insight' 는 채팅에서
#: 감지한 신호를 저장한 메모, 'exercise_memo' 는 운동 탭 기록 카드에서 남긴
#: 메모다(#2332). 회원 상세는 세 종류를 한 목록으로 보여 준다.
TrainerMemoSource = Literal["trainer", "chat_insight", "exercise_memo"]

#: 운동 기록 메모가 가리키는 기록의 갈래. 앱이 출처 태그(`PT 세션 · 9/23`,
#: `개인 운동 · 9/23 코어 강화`, `회원 기록 · 9/23`)를 그리는 데 쓴다.
#: `day` 는 그날 운동 기록 전체에 단 메모다(#2508). `member_log` 는 그 전에 회원 직접
#: 기록 카드에 남긴 메모로, 읽기만 한다.
TrainerMemoRefKind = Literal["pt_session", "personal", "member_log", "day"]

#: 메모 분류(#2622). 트레이너가 직접 쓴 메모에서 고른다 — 운동·식단·통증·부상·
#: 생활·일정. 빈 문자열은 고르지 않은 것이다(태그는 `직접 작성`). 운동 기록 메모는
#: 서버가 늘 'exercise' 로 채우고, 채팅 감지 메모는 비어 있다.
TrainerMemoCategory = Literal["", "exercise", "diet", "pain", "life"]


class TrainerMemoOut(BaseModel):
    """회원별 트레이너 메모. (#706)"""
    id: str
    body: str
    source: TrainerMemoSource
    #: 채팅 인사이트에서 만든 메모만 값을 갖는다(중복 저장 방지 키).
    insight_id: str | None = None
    #: 인사이트 종류(discomfort|negativeFeedback). 직접 쓴 메모는 빈 문자열.
    insight_kind: str = ""
    #: 운동 기록 메모만 값을 갖는다 — 어느 기록에서 남겼는가(#2332).
    ref_kind: TrainerMemoRefKind | None = None
    ref_id: str | None = None
    ref_date: str | None = None
    #: 트레이너가 지은 루틴 이름. 고정 이름(PT 세션 등)은 비어 있다.
    ref_name: str = ""
    #: 분류(#2622). 고르지 않았으면 빈 문자열.
    category: TrainerMemoCategory = ""
    created_at: _datetime
    updated_at: _datetime


class TrainerMemoCreateRequest(BaseModel):
    """메모 작성 입력.

    `insight_id` 를 보내면 그 인사이트에 대해 멱등하다 — 같은 채팅 신호를 다시
    저장해도 메모가 늘지 않고 먼저 저장된 메모가 그대로 돌아온다. 직접 쓴 메모는
    이 값을 보내지 않으므로 같은 내용을 여러 번 남길 수 있다(그것이 기능이다).
    """
    #: 메모는 기억해 둘 한두 줄이다 — 프로그램 AI 요청(`trainer_note`)과 같은 500자(#2516).
    body: str = Field(min_length=1, max_length=500)
    source: TrainerMemoSource = "trainer"
    insight_id: str | None = Field(default=None, max_length=64)
    insight_kind: str = Field(default="", max_length=32)
    #: 운동 기록 메모가 가리키는 이력 id(운동 탭 기록 카드의 id).
    ref_id: str | None = Field(default=None, max_length=64)
    #: 회원 직접 기록 카드는 하루치 묶음이라 id 대신 그 날(YYYY-MM-DD)을 보낸다.
    ref_date: _date | None = None
    #: 날짜로 가리킬 때 그날의 어느 상자인가(#2508) — 운동 탭 `오늘` 의
    #: `개인운동`(personal)·`회원 추가`(member_log) 상자, 또는 그날 전체(day,
    #: 기본). `ref_date` 와만 함께 보낸다.
    ref_kind: Literal["personal", "member_log", "day"] | None = None
    #: 분류(#2622). 직접 쓴 메모만 고른다. 운동 기록 메모는 보내지 않아도
    #: 'exercise' 가 되고, 다른 분류를 보내면 422 다.
    category: TrainerMemoCategory = ""

    @model_validator(mode="after")
    def _reject_mismatched_source(self) -> TrainerMemoCreateRequest:
        """출처와 중복 방지 키·기록 연결이 짝을 이루는지 본다.

        어긋난 두 조합이 조용히 통과하면 각각 다른 방식으로 망가진다 —
        키 없는 인사이트 메모는 반복 저장 때마다 늘어나고, 직접 쓴 메모가
        `insight_id` 를 가지면 그 인사이트의 유니크 키를 대신 차지한다.
        운동 기록 메모는 가리키는 기록이 꼭 하나여야 출처 태그를 그릴 수 있다.
        """
        if self.source == "chat_insight" and not self.insight_id:
            raise ValueError("chat_insight 메모에는 insight_id가 필요합니다.")
        if self.source != "chat_insight" and self.insight_id:
            raise ValueError(f"{self.source} 메모에는 insight_id를 보낼 수 없습니다.")
        has_ref = self.ref_id is not None or self.ref_date is not None
        if self.source == "exercise_memo":
            if (self.ref_id is None) == (self.ref_date is None):
                raise ValueError(
                    "exercise_memo 메모에는 ref_id 와 ref_date 중 하나만 보내야 합니다."
                )
        elif has_ref:
            raise ValueError(f"{self.source} 메모에는 기록 연결을 보낼 수 없습니다.")
        if self.ref_kind is not None and self.ref_date is None:
            raise ValueError("ref_kind 는 ref_date 와 함께 보내야 합니다.")
        # 분류는 트레이너가 고르는 값이다 — 채팅 감지 메모는 감지 이유가 태그이고,
        # 운동 기록 메모는 언제나 운동이다.
        if self.source == "chat_insight" and self.category:
            raise ValueError("chat_insight 메모에는 분류를 보낼 수 없습니다.")
        if self.source == "exercise_memo" and self.category not in ("", "exercise"):
            raise ValueError("exercise_memo 메모의 분류는 exercise 입니다.")
        return self


class TrainerMemoUpdateRequest(PartialUpdate):
    """메모 부분 수정. 본문과, 직접 쓴 메모의 분류(#2622)를 고칠 수 있다.

    `source`·`insight_id` 는 "이 메모가 어디서 왔나"라는 사실이라 고칠 값이 아니다 —
    채팅에서 생긴 메모를 손봤다고 직접 쓴 메모가 되지는 않고, `insight_id` 를
    바꿀 수 있으면 중복 방지 키가 무너진다. 운동 기록·채팅 감지 메모의 분류도
    출처에서 정해지므로 바꿀 수 없다(바꾸려 하면 400).
    """

    body: str | None = Field(default=None, min_length=1, max_length=500)
    #: 빈 문자열은 분류를 지운다(`직접 작성` 으로 돌아간다).
    category: TrainerMemoCategory | None = None


#: 회원 피드백 모아 보기의 출처(#2615). 'pt_session' 은 완료 PT 세션 피드백
#: (`TrainerSchedule.note`), 'report' 는 보낸 주간 리포트, 'weekly' 는 회원이
#: 쓴 주간 피드백이다.
ClientFeedbackKind = Literal["pt_session", "report", "weekly"]

#: 피드백의 방향. 앞의 둘은 트레이너가 회원에게, 'weekly' 는 회원이 트레이너에게.
ClientFeedbackDirection = Literal["to_member", "from_member"]


class ClientFeedbackOut(BaseModel):
    """회원 한 명과 주고받은 피드백 한 건 — 읽기 전용 모아 보기(#2615).

    고치는 곳은 원래 자리(스케줄 일정·리포트 주·회원 앱) 하나뿐이다. 그래서
    앱이 그 자리로 가는 데 쓰는 값(`schedule_id`·`week_start`)을 함께 준다.
    """

    #: 출처 안에서 유일한 값에 출처를 붙였다(`pt_session:<id>` 등).
    id: str
    kind: ClientFeedbackKind
    direction: ClientFeedbackDirection
    #: 그 피드백이 붙는 날(YYYY-MM-DD). PT 는 수업 날, 리포트·주간 피드백은 그 주 월요일.
    date: str
    #: 피드백 글. 주간 피드백은 한 줄 피드백(비어 있을 수 있다 — 칩만 고른 주).
    body: str = ""
    #: PT 세션 피드백의 일정 id — 앱이 스케줄의 그 일정으로 간다.
    schedule_id: str | None = None
    #: 리포트·주간 피드백의 주(월요일) — 앱이 리포트의 그 주로 간다.
    week_start: str | None = None
    #: 리포트를 보낸 시각·주간 피드백을 마지막으로 고친 시각. PT 는 없다.
    at: _datetime | None = None
    #: 주간 피드백 칩(회원 앱 값 그대로 — great|good|ok|tired|bad 등). 앱이 번역한다.
    condition: str = ""
    intensity: str = ""
    pain_area: str = ""
    pain_on: str = ""


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


#: AI 추천이 읽을 수 있는 트레이너 쪽 자료(#2587).
#:
#: * recent_chat — 회원과의 최근 대화 원문(최근 14일 · 최신 10건, #2794)
#: * pt_feedback — 완료한 PT 일정의 글(트레이너 피드백)
#: * consult_memo — 상담 일정의 글(상담 메모, 트레이너만 본다)
#: * trainer_memo — 회원 상세에서 트레이너가 직접 쓴 메모(`source='trainer'`)
#: * chat_insight — 채팅 감지에서 남긴 메모(`source='chat_insight'`)
#: * weekly_feedback — 회원이 남긴 주간 피드백
RoutineContextSource = Literal[
    "recent_chat",
    "pt_feedback",
    "consult_memo",
    "trainer_memo",
    "chat_insight",
    "weekly_feedback",
]

#: 트레이너가 고르지 않았을 때의 기본값. 상담 메모만 뺀다 — 등록 상담처럼
#: 운동 구성과 무관하거나 민감한 내용이 섞이는 자리라, 넣을지는 트레이너가 켠다.
ROUTINE_DEFAULT_SOURCES: tuple[RoutineContextSource, ...] = (
    "recent_chat", "pt_feedback", "trainer_memo", "chat_insight", "weekly_feedback",
)

#: 자료별 최대 건수. 서비스의 조회 limit 이 이 값을 그대로 쓴다 — 이유는
#: [ROUTINE_CHAT_MAX_MESSAGES] 와 같다(서비스만 올리면 폴백 밖에서 500).
ROUTINE_PT_FEEDBACK_MAX = 5
ROUTINE_CONSULT_MEMO_MAX = 3
ROUTINE_TRAINER_MEMO_MAX = 5
ROUTINE_WEEKLY_FEEDBACK_MAX = 2


class RoutineOptionsRequest(BaseModel):
    """회원 데이터 기반 맞춤 루틴 후보 생성 조건.

    두 필드 모두 비워 둘 수 있다(#776) — 운동 기록이 쌓인 회원은 서버가 최근
    패턴에서 값을 채우고, 기록이 없으면 기본값을 쓴다. 트레이너가 값을 보내면
    그 값이 항상 우선한다.
    """

    available_minutes: int | None = Field(default=None, ge=10, le=180)
    intensity_preference: RoutineIntensityPreference | None = None
    trainer_note: str = Field(default="", max_length=500)
    #: AI 가 참고할 자료(#2587). 트레이너가 위저드에서 고른 것만 프롬프트와 규칙
    #: 폴백에 들어간다. 보내지 않으면(`None`) [ROUTINE_DEFAULT_SOURCES] 를 쓴다 —
    #: 이 필드 이전의 클라이언트도 같은 기본값으로 동작한다. 빈 목록은 "아무 자료도
    #: 넣지 않음" 이라는 명시적 선택이라 기본값으로 바꾸지 않는다.
    sources: list[RoutineContextSource] | None = Field(default=None, max_length=6)


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
    #: (`source='trainer'`)는 [trainer_memos] 에 따로 싣는다.
    insight_memos: list[str] = Field(
        default_factory=list, max_length=ROUTINE_INSIGHT_MEMO_MAX
    )
    #: 이번 생성에 실제로 넣은 자료(#2587). 트레이너가 고른 값, 고르지 않았으면
    #: 기본값이다. 끈 자료의 목록은 늘 비어 있다.
    sources: list[RoutineContextSource] = Field(default_factory=list)
    #: 최근 14일 완료한 PT 일정의 글(트레이너 피드백), 최신 먼저. `"09.01 …"`.
    pt_feedbacks: list[str] = Field(
        default_factory=list, max_length=ROUTINE_PT_FEEDBACK_MAX
    )
    #: 최근 30일 상담 일정의 글(상담 메모), 최신 먼저. 기본으로는 꺼져 있다.
    consult_memos: list[str] = Field(
        default_factory=list, max_length=ROUTINE_CONSULT_MEMO_MAX
    )
    #: 최근 14일 트레이너가 회원 상세에서 직접 쓴 메모, 최신 먼저(#2519).
    trainer_memos: list[str] = Field(
        default_factory=list, max_length=ROUTINE_TRAINER_MEMO_MAX
    )
    #: 이번 주와 지난주의 회원 주간 피드백, 최신 주 먼저. 담당이 시작된 주부터다.
    weekly_feedback: list[str] = Field(
        default_factory=list, max_length=ROUTINE_WEEKLY_FEEDBACK_MAX
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
    #: 같은 운동 시간을 초로 — [ProgramDraftExercise.duration_seconds] 와 같다(#2221).
    duration_seconds: LooseInt = Field(default=None, ge=0, le=MAX_EXERCISE_SECONDS)
    sets: LooseInt = Field(default=None, ge=0, le=MAX_EXERCISE_SETS)
    #: 근력의 한 세트당 횟수. 세트·중량과 한 벌이다(#1310) — 셋이 다 있어야
    #: 트레이너가 짠 근력 한 줄이 회원 화면에서 그대로 재현된다.
    reps: LooseInt = Field(default=None, ge=0, le=MAX_EXERCISE_REPS)
    #: 버티는 운동이면 한 세트를 버티는 시간(초). `reps` 와 한 자리를 나눠
    #: 쓴다 — 이 값이 있으면 횟수가 비고, 없으면 반대다(#1969). 이 칸이 없던
    #: 동안 트레이너는 "플랭크 3세트 · 60초" 를 **이름에** 적을 수밖에 없었고,
    #: 이름에 적힌 글자는 어떤 집계에도 잡히지 않았다.
    hold_seconds: LooseInt = Field(
        default=None, ge=0, le=MAX_EXERCISE_HOLD_SECONDS
    )
    weight: LooseFloat = Field(default=None, ge=0, le=MAX_EXERCISE_WEIGHT_KG)
    intensity: RoutineIntensity = "moderate"
    session: str = Field(default="", max_length=100)

    _drop_mismatched_fields = model_validator(mode="after")(
        _drop_fields_not_in_type
    )
    # 유형에 맞지 않는 칸을 비운 **뒤에** 맞춘다 — 근력의 시간은 둘 다 빈다.
    _sync_duration = model_validator(mode="after")(_sync_duration_units)


#: 취소 주체. 트레이너 사정의 취소를 회원의 미이행으로 읽지 않으려면 남아 있어야
#: 한다. 빈 문자열은 "취소가 아님"(예정·완료·노쇼)이다. (#871)
CancellationSource = Literal["", "member", "trainer", "other"]


class ScheduleConsultationOut(BaseModel):
    """상담 일정을 만든 상담 요청의 내용 — 트레이너 웹 카드의 `상담 요청 내용`. (#2584)

    회원이 신청 때 적은 것이라 읽기 전용이다. 예전에는 수락이 문의 글을 일정
    `note` 에 넣어, 트레이너 메모 자리에 회원 글이 섞였다. 값은 상담 인박스
    (`TrainerConsultationOut`)와 같은 코드로 내려 화면이 같은 이름표를 쓴다.
    """

    id: str
    exercise_goal: str
    health_purpose_type: str
    health_purpose_detail: str | None = None
    message: str | None = None


class ScheduleSessionOut(BaseModel):
    """스케줄 슬롯 — 프론트 ScheduleSession 계약 정렬."""
    id: str
    date: str
    time: str
    client_name: str
    #: 담당 회원 id. 가망 고객(이름만 있는 상담)·공백 슬롯은 null 이다. 웹이
    #: 회원별로 일정을 묶으려면(이탈 위험·활동 피드백) 이 값이 있어야 한다(#2586).
    member_id: str | None = None
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
    #: 상담 요청으로 생긴 일정이면 그 요청의 내용(#2584). 트레이너 응답에만 싣고
    #: 회원 응답에서는 비운다 — 회원은 자기 요청을 `내 상담 요청` 에서 본다.
    consultation: ScheduleConsultationOut | None = None
    #: 담당이 끊긴(해제·동의 철회) 회원의 일정인가(#2589). 참이면 트레이너가 참여한
    #: 수업 기록으로만 남는다 — 이름은 `해제 회원`, `member_id`·글·프로그램·취소
    #: 사유는 비어 있고, 회원 상세·코칭으로 이어지지 않는다.
    member_detached: bool = False
    #: 회원이 예약 슬롯으로 잡은 일정인가(#2756). 예약이 시각·회원·좌석을 갖고
    #: 있어 일반 일정 수정(시각·회원·종류·길이)·삭제·되돌리기는 409 다. 메모·
    #: 프로그램은 고칠 수 있고, 일정을 거두려면 취소한다.
    is_reservation: bool = False
    #: 완료한 PT 가 담당 트레이너와의 몇 번째 수업인가(1부터, #2697). 회원 응답의
    #: 완료 PT 에만 싣는다 — 예정·취소·노쇼·상담과 트레이너 응답은 null 이다.
    #: 회원 목록이 최근 100건으로 잘리므로 앱이 세면 그보다 오래된 회원에게 틀린다.
    session_number: int | None = None


class DeliveryOut(BaseModel):
    """트레이너가 회원에게 **한 번에 보낸 것** 한 묶음. (#2225)

    전송 이력이 PT 프로그램과 개인운동을 따로 나열하던 동안에는, PT 완료 때 함께
    보낸 개인운동이 어느 PT 와 짝인지 알 수 없었다(#2224). 한 번의 전송이 만든
    줄은 멱등키의 `#` 앞부분(`{base}#0`·`{base}#routine0`)을 함께 쓰므로, 그
    값으로 묶는다. 옛 배정처럼 키가 없으면 보낸 날과 종류로 묶는다.
    """

    #: 이 전송이 어떤 것인가 — 화면이 종류를 글자로 보여 준다.
    kind: RoutineDeliveryKind
    #: 회원 목록에 걸린 날(=보낸 날).
    sent_on: _date | None = None
    #: PT 와 함께 간 전송이면 그 일정(그 안에 PT 프로그램이 들어 있다).
    #: `개인운동만` 은 비어 있다.
    session: ScheduleSessionOut | None = None
    #: 회원이 혼자 할 개인운동. `개인운동만` 전송은 이 목록이 전부다.
    routines: list[RoutineOut] = Field(default_factory=list)


#: 그날 걸린 개인운동 하나의 결과(#2508).
#:
#: * `done` — 그날 완료.
#: * `late` — 그날 완료를 다음 날 이후에 체크했다. 완료로 센다.
#: * `missed` — 하지 않았다. **오늘 이전**만 이 값이다.
#: * `pending` — 오늘, 아직 하지 않았다.
RoutineDayStatus = Literal["done", "late", "missed", "pending"]


class TrainerRoutineDayItemOut(BaseModel):
    """그날 칸 하나 — 어느 배정이 그날 어떻게 되었나. (#2508)"""

    routine_id: str
    status: RoutineDayStatus
    #: 완료(`done`·`late`)로 남은 운동 기록 id. 트레이너 메모가 이 값을 가리킨다.
    session_id: str | None = None


class TrainerRoutineDayOut(BaseModel):
    """하루치 — 그날 걸린 개인운동과 결과(배정 순서). 빈 날도 한 칸이다. (#2508)"""

    date: _date
    items: list[TrainerRoutineDayItemOut] = Field(default_factory=list)


class TrainerRoutineDayRoutineOut(BaseModel):
    """기간 안에 한 번이라도 걸렸던 배정 하나. (#2508)

    화면은 [sent_on]·[ended_on]·[personal] 이 같은 줄을 한 배정 묶음으로 묶어
    머리 줄("9/29(화) 보낸 개인운동 · 10/5(월)까지")을 그리고, `active_from`
    ~`ended_on` 전날을 회색 띠로 칠한다.
    """

    id: str
    name: str
    #: 유산소|근력|스트레칭|기타 — 배정의 한글 유형 그대로다.
    type: str
    #: ai|trainer
    source: str
    sort_order: int
    #: 회원 목록에 뜨는 첫날.
    active_from: _date
    #: 회원 목록에서 내려가는 날 — **그날은 뜨지 않는다**. 기한 없는 배정은 null.
    ended_on: _date | None = None
    #: 트레이너가 보낸 날. 시작일을 미래로 고른 `개인운동만` 은 [active_from]
    #: 보다 이르다(#2656).
    sent_on: _date
    #: 개인운동(한 주씩 보내는 것)인가. 거짓이면 기한 없는 따로 배정이다.
    personal: bool
    #: 배정에 적힌 양 — 줄을 `[유형] 이름 · 세부 · 효과` 로 그린다. 근력은
    #: 세트·횟수(또는 버틴 초)·중량, 나머지는 시간이다. 없는 칸은 null.
    minutes: int = 0
    duration_seconds: int | None = None
    sets: int | None = None
    reps: int | None = None
    hold_seconds: int | None = None
    weight: float | None = None
    #: 효과 한 줄 — 회원 앱과 같은 값(적힌 값, 없으면 문구표, #2570).
    effect: str = ""


class TrainerRoutineDaysOut(BaseModel):
    """`GET /trainer/clients/{id}/routine-days` — 날짜별 개인운동 이행. (#2508)"""

    #: 읽은 기간(양끝 포함). 걸린 적이 없으면 둘 다 null 이고 목록이 빈다.
    start: _date | None = None
    end: _date | None = None
    routines: list[TrainerRoutineDayRoutineOut] = Field(default_factory=list)
    days: list[TrainerRoutineDayOut] = Field(default_factory=list)


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
    note: str = Field(default="", max_length=TEXT_ENTRY_MAX)
    program: list[ProgramItem] = Field(
        default_factory=list, max_length=_PROGRAM_MAX_TOTAL_EXERCISES
    )
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
    note: str = Field(default="", max_length=TEXT_ENTRY_MAX)
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
    #: 같은 `client_request_id` 로 이미 만들어진 시리즈가 있다(응답만 잃은 재시도).
    #: 그 회차는 `conflicts` 에서 빠진다 — 같은 키로 만들기를 다시 부르면 그
    #: 회차들을 그대로 돌려받는다. (#3102)
    already_created: bool = False


class ProgramScheduleRequest(BaseModel):
    """프로그램 탭 `일정 추가` 한 번 — 회원 배정과 PT 일정 등록을 함께 한다. (#1580)

    예전에는 배정(`POST .../program`)과 일정 등록(`PUT .../schedule-program`)을
    화면이 차례로 불러, 배정만 되고 일정은 빠진 반쪽 상태가 남을 수 있었다. 두
    쓰기를 한 트랜잭션에 묶어 둘 다 되거나 둘 다 안 된다.

    일정에 실릴 항목은 서버가 `sessions` 에서 펼친다 — 클라이언트가 같은 운동을
    두 벌로 실어 보내면 배정과 일정이 서로 다른 구성을 가질 수 있다.
    """

    name: str = Field(min_length=1, max_length=100)
    sessions: list[ProgramDraftSession] = Field(
        min_length=1, max_length=_PROGRAM_MAX_SESSIONS
    )
    date: str = Field(max_length=10)
    time: str = Field(max_length=10)
    duration_minutes: int = Field(gt=0, le=600)
    client_name: str = Field(default="", max_length=100)
    #: 전송 시도 하나의 멱등키. 응답을 잃고 같은 키로 다시 보내면 배정도 일정도
    #: 새로 만들지 않고 먼저 처리한 결과를 돌려준다. 서버가 `{key}#{index}`·
    #: `{key}#schedule` 로 나눠 저장하므로 프로그램 배정과 같은 48자 상한이다.
    client_request_id: str | None = Field(default=None, min_length=1, max_length=48)
    #: 고른 시간대와 겹치는 예정 세션이 여럿일 때 트레이너가 확인창에서 고른
    #: 연결 대상(#1581). 후보가 하나 이하면 비워 둔다.
    session_id: str | None = Field(default=None, min_length=1, max_length=64)
    #: 이 PT 에 붙일 개인운동(#2223). 프로그램 만들기의 개인운동 단계에서 정한
    #: 것이고, 회원에게는 PT 를 완료할 때 간다(#2224) — 여기서는 일정에 붙여
    #: 두기만 한다. 비어 있어도 받는다: 개인운동 단계가 생기기 전에 만들어진
    #: 초안과 옛 앱이 그대로 보낼 수 있어야 한다.
    personal_routines: list[PersonalRoutineItem] = Field(
        default_factory=list, max_length=_MAX_PERSONAL_ROUTINES
    )
    #: [personal_routines] 를 채운 대기 중 AI 제안 id(#2747). 일정 등록과 같은
    #: 트랜잭션에서 닫는다 — [ProgramAssignRequest.suggestion_ids] 와 같은 규약.
    suggestion_ids: list[_SuggestionId] = Field(
        default_factory=list, max_length=_MAX_PERSONAL_ROUTINES
    )

    _v_date = field_validator("date")(_validate_ymd)
    _v_time = field_validator("time")(_validate_hhmm)
    _v_total = field_validator("sessions")(_check_program_total_exercises)

    @field_validator("date")
    @classmethod
    def _not_in_the_past(cls, value: str) -> str:
        """지난 날짜로는 새 일정을 잡지 않는다(#1582).

        화면을 자정 넘게 열어 둔 채 누르면 전날 날짜가 올 수 있다. 날짜만 본다 —
        오늘이면 고른 시각이 이미 지났어도 받는다. 스케줄 탭의 지난 수업 기록
        (`POST /trainer/schedule`)은 과거 날짜가 정상이라 이 검사를 두지 않는다.
        """
        if _date.fromisoformat(value) < clock.today():
            raise ValueError("지난 날짜에는 일정을 추가할 수 없습니다.")
        return value


class ProgramScheduleOut(BaseModel):
    routines: list[RoutineOut]
    session: ScheduleSessionOut
    attached_to_existing: bool
    #: 이 PT 일정에 붙인 개인운동(#2223). 아직 회원에게 가지 않은 상태라
    #: `routines` 와 나눠 싣는다 — 저 목록은 이미 배정된 것이다.
    personal_routines: list[RoutineOut] = Field(default_factory=list)


class ScheduleUpdateRequest(PartialUpdate):
    """부분 수정 — 제공된 필드만 반영."""
    date: str | None = Field(default=None)
    time: str | None = Field(default=None, max_length=10)
    client_name: str | None = Field(default=None, max_length=100)
    member_id: str | None = Field(default=None, max_length=64)
    type: str | None = Field(default=None, max_length=30)
    duration_minutes: int | None = Field(default=None, ge=0, le=600)
    note: str | None = Field(default=None, max_length=TEXT_ENTRY_MAX)
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
    note: str = Field(default="", max_length=TEXT_ENTRY_MAX)


class ScheduleReopenRequest(BaseModel):
    """완료 세션을 예정으로 되돌리며 옮길 날짜. (#1396)

    과거 날짜로는 되돌리지 않는다 — "완료를 취소"하는 자리가 아니라, 반복
    등록의 시작 회차처럼 이미 끝난 세션을 다가올 약속으로 다시 잡는
    자리이기 때문이다.
    """
    date: str
    #: 옮길 시각·길이(#2757). 주면 겹침 검사와 반영을 되돌리기 한 요청 안에서
    #: 끝낸다 — 따로 보내면 되돌린 뒤의 수정이 겹침으로 멈춰도 되돌리기는 이미
    #: 커밋돼 있다. 없으면 지금 값을 쓴다.
    time: str | None = Field(default=None, max_length=10)
    duration_minutes: int | None = Field(default=None, ge=0, le=600)

    @field_validator("date")
    @classmethod
    def _v_date(cls, v: str) -> str:
        return _validate_ymd(v)

    @field_validator("time")
    @classmethod
    def _v_time(cls, v: str | None) -> str | None:
        return _validate_hhmm(v) if v is not None else v


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

    **트레이너 이름 수정을 열 때** 담당 회원에게 이름이 바뀌었다고 알림 하나를 함께
    보낸다(#2065). 이미 받은 알림은 옛 이름으로 남으므로 그 알림이 둘을 잇는다 —
    회원 쪽은 `name_change.record_member_rename` 이 같은 일을 한다.

    모든 항목이 DB NOT NULL 이라 null 로 바꿀 수 있는 값이 아니다(#495).
    """
    #: 트레이너 본인의 휴대전화. 회원 경로(`UserRegister`·`ProfileUpdate`)와
    #: **같은 함수**로 정리한다(#1914) — 전에는 길이만 봐서 `없음`·`0101234` 가
    #: 200 으로 저장됐다. 두 앱이 같은 종류의 값을 다른 기준으로 받으면, 나중에
    #: 이 번호를 회원 화면에 보일 때 그 자리에서 정리부터 해야 한다.
    #:
    #: 빈 문자열은 그대로 둔다. 트레이너 가입은 전화번호를 받지 않으므로
    #: (트레이너 웹 가입 화면에 전화번호 칸이 없다) 처음부터 없는 값이고, 회원 쪽의
    #: "있던 번호는 못 지운다"(#1883)는 여기 해당하지 않는다.
    phone: str | None = Field(default=None, max_length=20)
    specialty: str | None = Field(default=None, max_length=50)
    career_years: int | None = Field(default=None, ge=0, le=80)
    intro: str | None = Field(default=None, max_length=TEXT_ENTRY_MAX)
    certifications: list[str] | None = Field(default=None, max_length=30)
    #: 헬스장 문자열 네 칸은 **더 이상 직접 저장하지 않는다**(#2543). 보내면 409.
    #: 소속(`gym_id`)에서만 파생된다 — 직접 적은 이름은 `gym_id` 가 비어 회원에게
    #: 노출되지 않는데도 화면에는 소속이 있어 보였다. 필드를 지우지 않고 남겨 두는
    #: 이유: 지우면 pydantic 이 모르는 키를 조용히 버려 옛 클라이언트가 200 을 받고
    #: 저장된 줄 안다.
    gym_name: str | None = Field(default=None, max_length=100)
    gym_address: str | None = Field(default=None, max_length=300)
    gym_hours: str | None = Field(default=None, max_length=50)
    #: 헬스장 대표번호. **여기에는 위 규칙을 걸지 않는다**(#1914).
    #:
    #: `normalize_phone` 은 휴대전화 3-4-4(숫자 11자리)만 받는데, 헬스장 번호는
    #: 그 모양이 아니다 — 시드에만도 `02-1234-5678`(10자리) · `02-332-1720`(9자리)
    #: · `0502-5552-4212`(12자리)가 섞여 있다. 그 규칙을 걸면 **정상 번호가 422**
    #: 로 막히고, 더 나쁘게는 소속을 설정할 때 `Place.phone` 이 이 칸에 그대로
    #: 들어오므로(`set_trainer_gym`) 그 뒤로 이 폼을 저장할 수 없게 된다.
    #:
    #: 대표번호 표기를 통일하려면 지역번호·안심번호까지 읽는 별도 규칙이
    #: 필요하다. 그건 이 이슈에서 다루지 않는다.
    gym_phone: str | None = Field(default=None, max_length=20)

    # `None` 을 그냥 통과시키는 것은 여기서 판단할 일이 아니기 때문이다 —
    # 누락인지 명시적 null 인지는 아래 `_reject_explicit_null` 이 가른다.
    @field_validator("phone", mode="before")
    @classmethod
    def _normalize_phone(cls, value: Any) -> Any:
        if isinstance(value, str):
            return contact_format.normalize_phone(value)
        return value

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


class TrainerGymCandidate(BaseModel):
    """GET /trainer/gyms/search 한 줄 — 소속으로 고를 수 있는 헬스장. (#2543)

    `registered` 면 이미 `places` 에 있는 헬스장이라 `PUT /trainer/me/gym` 으로 바로
    고른다. 아니면 카카오에서 찾은 곳이라 `PUT /trainer/me/gym/kakao` 로 고르고,
    서버가 그때 `places` 에 넣는다. 좌표는 지도 핀용이고, 거리는 검색에 좌표를
    줬을 때만 채운다.
    """
    id: str
    name: str
    address: str
    lat: float | None = None
    lng: float | None = None
    phone: str = ""
    distance_meters: int | None = None
    registered: bool


class TrainerKakaoGymSelect(BaseModel):
    """PUT /trainer/me/gym/kakao — 카카오 검색 결과로 소속 설정. (#2543)

    이름·주소를 받지 않는 이유: 클라이언트가 보낸 값을 그대로 `places` 에 넣으면
    아무 이름의 헬스장이나 만들 수 있다. 서버가 `name` 으로 카카오를 다시 검색해
    `kakao_place_id` 가 같은 결과를 찾고, 그 결과의 값만 쓴다. `name` 은 그 검색어다.
    """
    kakao_place_id: str = Field(min_length=1, max_length=30, pattern=r"^\d+$")
    name: str = Field(min_length=1, max_length=200)


#: 헬스장 태그 개수·길이 상한(#2700). 회원 앱 목록 카드에 칩으로 한 줄 남짓 그려지는
#: 값이라 길게 받을 이유가 없다.
GYM_TAGS_MAX = 10
GYM_TAG_MAX_LENGTH = 20


class TrainerGymProfileOut(BaseModel):
    """GET·PUT /trainer/me/gym/profile — 소속 헬스장의 부가 정보. (#2700)

    회원 앱 헬스장 목록·상세(`GymOut`)에 그대로 나가는 값이다. 평점은 트레이너가
    고치는 값이 아니라 싣지 않는다.
    """
    gym_id: str
    name: str
    weekday_hours: str
    weekend_hours: str
    phone: str
    tags: list[str]


class TrainerGymProfileUpdate(PartialUpdate):
    """PUT /trainer/me/gym/profile — 소속 헬스장 부가 정보 부분 수정. (#2700)

    보낸 칸만 바꾼다. 빈 문자열은 "비운다"이고, null 은 422 다(`PartialUpdate`).
    길이 상한은 `gym_profiles` 컬럼 길이와 같다 — 넘치면 DB 가 막는다.

    **평점은 받지 않는다.** 트레이너가 자기 헬스장 평점을 적게 두면 그 값은 평점이
    아니다. 보내도 모르는 키로 버려지지 않게 422 로 막는다(`extra="forbid"`).
    """
    model_config = ConfigDict(extra="forbid")

    weekday_hours: str | None = Field(default=None, max_length=50)
    weekend_hours: str | None = Field(default=None, max_length=50)
    #: 헬스장 대표번호 — 휴대전화 규칙(`normalize_phone`)을 걸지 않는다(#1914,
    #: `TrainerMeUpdate.gym_phone` 주석). `02-332-1720` 같은 정상 번호가 막힌다.
    phone: str | None = Field(default=None, max_length=20)
    tags: list[str] | None = Field(default=None, max_length=GYM_TAGS_MAX)

    @field_validator("weekday_hours", "weekend_hours", "phone")
    @classmethod
    def _strip(cls, value: str | None) -> str | None:
        return value.strip() if isinstance(value, str) else value

    @field_validator("tags")
    @classmethod
    def _clean_tags(cls, value: list[str] | None) -> list[str] | None:
        """앞뒤 공백을 걷고, 빈 태그는 422, 같은 태그는 처음 것만 남긴다."""
        if value is None:
            return value
        cleaned: list[str] = []
        for raw in value:
            tag = raw.strip()
            if not tag:
                raise ValueError("빈 태그는 저장할 수 없습니다.")
            if len(tag) > GYM_TAG_MAX_LENGTH:
                raise ValueError(f"태그는 {GYM_TAG_MAX_LENGTH}자 이하로 입력하세요.")
            if tag not in cleaned:
                cleaned.append(tag)
        return cleaned


# ---- 주간 리포트 (트레이너 → 회원) ----

class WeeklyReportDayOut(BaseModel):
    """리포트의 하루 — 그날의 이행률과 실제로 배정된 운동.

    이행률만으로는 67% 가 어디서 나온 값인지 화면에서 알 수 없다. 배정된
    운동과 건너뛴 운동을 함께 내려 주면 분모·분자가 드러난다(#754).
    """
    #: 0..100 — 그날 걸린 개인운동·잡힌 PT 중 한 비율(#2513). 아무것도 걸리지
    #: 않은 날과 아직 오지 않은 날은 null 이다(0 은 "하나도 안 했다").
    completion: int | None = None
    #: 운동 이름. 끝의 '✓'/'✗' 는 수행 여부를 나타내는 저장 규칙이며 화면은
    #: 그 표시를 읽어 아이콘으로 바꿔 그린다(운동 기록 탭과 같은 규칙).
    exercises: list[str] = Field(default_factory=list)
    #: 그날 회원 목록에 걸려 있던 추천 개인운동 수 — 개인운동 칸의 분모다(#2772).
    #: 추천 개인운동은 매일 리셋되는 목록이라 그날 걸려 있던 배정을 센다
    #: (#2161). 배정이 없던 날과 아직 오지 않은 날은 null 이다 — 0 은 쉬는
    #: 날과 구분되지 않아 쓰지 않고, null 이면 화면이 실제로 한 운동 수로
    #: 되돌아간다(#2232, 데모와 같은 규칙).
    assigned: int | None = None
    #: 그중 그날 완료한 수 — [assigned] 의 짝인 분자다(#3115). `exercises` 는
    #: 직접 기록·PT 기록까지 담아 개인운동 완료 수로 쓸 수 없다. [assigned] 가
    #: null 인 날은 이것도 null 이다.
    assigned_done: int | None = None


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
    week_completion: list[int | None] = Field(default_factory=list)
    sodium_week: list[int] = Field(default_factory=list)
    calories_week: list[int] = Field(default_factory=list)
    sugar_week: list[float] = Field(default_factory=list)
    #: 그 주의 일별 탄·단·지(g). 트레이너 화면의 `이번 달` 칼로리 막대를 탄단지로
    #: 쌓는 재료다(#944). 끼니 목록을 날마다 부르면 한 달에 서른 번 넘게 오가므로,
    #: 칼로리·나트륨·당류와 **같은 응답**에 실어 보낸다.
    carbs_week: list[float] = Field(default_factory=list)
    protein_week: list[float] = Field(default_factory=list)
    fat_week: list[float] = Field(default_factory=list)
    #: 그 주(월→일)의 요일별 끼니 기록 수 — 그날 `DietEntry` 수다(#2772).
    #: 칼로리가 답하지 못하는 값이다 — 0kcal 인 날은 안 먹은 날이 아니라 안
    #: 적은 날이다(#2232). 기록 없는 날과 아직 오지 않은 날은 0 이고, 아직
    #: 오지 않은 날을 `–` 로 그리는 것은 화면 규칙이다.
    meal_counts: list[int] = Field(default_factory=list)
    #: 그 회원의 하루 목표. 건강 프로필에 적혀 있으면 그 값, 없으면 null 이다
    #: (#1430). 주의사항 판정이 고정 상수보다 이 값을 먼저 쓴다 — 같은 1,900kcal
    #: 이 어떤 회원에게는 부족이고 어떤 회원에게는 초과다. 근거 문장도 어느
    #: 기준을 썼는지 이 값으로 적는다.
    calorie_target: int | None = None
    sodium_target: int | None = None
    sugar_target: float | None = None
    carbs_target: float | None = None
    protein_target: float | None = None
    #: 개인 단백질 목표가 없어도 채워지는 실효 목표(#2898) — 식단 분석과 같은
    #: 규칙(개인 목표 → 체중 × 1.2g → 60g). 리포트 막대 분모가 이 값이다.
    #: `protein_target` 은 '이 회원의 목표'와 기본값을 가르려고 그대로 둔다.
    effective_protein_target: float | None = None
    fat_target: float | None = None
    #: 월→일 7칸. 이행률과 함께 그날의 운동 내역을 담는다(#754).
    days: list[WeeklyReportDayOut] = Field(default_factory=list)
    #: 칼로리 `평소` — 직전 4주(28일)에 기록한 날의 하루 평균 kcal(#2863).
    #: 편집기가 이번 주 칼로리를 견주는 기준이다. 예전에는 앱이 직전 4주
    #: 리포트·회원 피드백을 통째로 다시 불러 계산했다. 기록이 없으면 null.
    calorie_baseline: float | None = None
    message: str                 # 회원에게 전송될 본문(미리보기와 동일)


#: 리포트 요약 headline 의 응답 상한(#3090). 회원 이름(최대 100자)이 들어간 규칙 기반
#: 영어 문장까지 넉넉히 담는다. AI 문장은 이보다 짧은 선에서 먼저 걸러진다.
REPORT_HEADLINE_MAX = 400


class ReportSummaryOut(BaseModel):
    """리포트 요약 — 트레이너가 피드백 초안으로 가져다 고칠 재료."""
    member_id: str
    week_start: str              # YYYY-MM-DD (월요일)
    #: 이번 주를 한 문장으로. AI 문장은 200자를 넘으면 규칙 기반으로 바뀐다
    #: (`trainer_report_summary_service.HEADLINE_MAX`, #3090). 이 상한은 회원 이름이
    #: 들어가는 규칙 기반 문장까지 담는 바깥 계약이다.
    headline: str = Field(max_length=REPORT_HEADLINE_MAX)
    #: 근거가 된 수치 문장. 리포트 화면이 이미 보여 주는 값만 담는다 — 요약과
    #: 그래프가 다른 값을 말하면 트레이너가 어느 쪽을 믿어야 할지 모른다.
    points: list[str] = Field(default_factory=list)
    #: `llm` | `rule`. 공급자 장애·미설정이면 규칙 기반으로 되돌아간다.
    generated_by: str


class ReportSendRequest(BaseModel):
    """리포트 전송 — 본문을 직접 주면 그것을, 없으면 서버 생성본을 보낸다."""
    week_start: str | None = Field(default=None, description="YYYY-MM-DD (기본: 이번 주)")
    message: str | None = Field(default=None, max_length=TEXT_LONG_MAX)


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

    `max_length` 는 전송 본문(`ReportSendRequest.message`)과 같은 긴 글 상한이다 —
    저장은 됐는데 보낼 수 없는 길이가 생기면 안 된다.
    """
    week_start: str | None = Field(default=None, description="YYYY-MM-DD (기본: 이번 주)")
    body: str = Field(default="", max_length=TEXT_LONG_MAX)


class MemberWeeklyFeedbackOut(BaseModel):
    """회원이 그 주에 남긴 세 문항. (#2232)

    `submitted` 가 false 면 나머지 칸은 기본값이고 회원이 아직 답하지 않은
    것이다. 404 로 답하지 않는 까닭은 `ReportFeedbackOut` 과 같다 — 답이 없는
    것은 오류가 아니라 정상 상태이고, 리포트 화면은 그때 "아직 받지 못함"을
    적어야 한다. 비어 있음을 오류로 만들면 그 칸이 통째로 사라진다.
    """
    week_start: str              # YYYY-MM-DD (월요일)
    submitted: bool = False
    condition: str = ""          # great|good|ok|tired|bad
    intensity: str = ""          # too_easy|right|hard|too_hard
    pain_area: str = ""
    pain_on: str = ""            # YYYY-MM-DD
    note: str = ""
    submitted_at: _datetime | None = None


class MemberWeeklyFeedbackSaveRequest(BaseModel):
    """회원이 한 주 피드백을 보낸다. 같은 주에 다시 보내면 덮어쓴다.

    한 주에 대한 회원의 말은 마지막 것 하나다 — 고쳐 보낸 답이 먼저 보낸 답
    옆에 나란히 서면 트레이너는 둘 중 무엇을 믿을지 알 수 없다.
    """
    week_start: str | None = Field(default=None, description="YYYY-MM-DD (기본: 지난 주)")
    condition: str = Field(description="great|good|ok|tired|bad")
    intensity: str = Field(description="too_easy|right|hard|too_hard")
    pain_area: str = Field(default="", max_length=40)
    pain_on: str = Field(default="", description="YYYY-MM-DD")
    #: 한 줄은 길게 받지 않는다 — 30초 안에 끝나야 매주 돌아온다.
    note: str = Field(default="", max_length=TEXT_LINE_MAX)


class ReportGoalsOut(BaseModel):
    """그 주에 적용돼 있는 목표. (#2232)

    비어 있는 것이 정상이다 — 지난 주에 아무것도 고르지 않았거나, 이 회원의
    첫 주다. 404 로 만들면 리포트의 ③ 칸이 통째로 사라진다.
    """
    week_start: str              # 목표가 적용되는 주의 월요일 YYYY-MM-DD
    goals: list[str] = Field(default_factory=list)


class ReportGoalsSaveRequest(BaseModel):
    """②에서 고른 목표를 **다음 주**에 적용한다. (#2232)

    `week_start` 는 지금 보고 있는 주다. 적용되는 주(다음 주)는 서버가 더한다 —
    주 경계 계산이 앱과 서버 두 곳에 있으면 한쪽만 틀리는 날이 온다.
    """
    week_start: str | None = Field(default=None, description="YYYY-MM-DD (기본: 이번 주)")
    #: 목표 문장들. 한 화면이 들고 있는 목록 전체로 통째로 바꾼다.
    goals: list[str] = Field(default_factory=list, max_length=20)


class ReportSendOut(BaseModel):
    """한 회원에게 그 주 리포트가 나간 기록. (#2288)

    따로 저장한 표가 아니라 리포트 전송이 남긴 채팅 메시지(`report_week_start`)
    에서 읽는다 — 전송 기록을 두 곳에 두면 한쪽만 남는 날이 온다.
    """
    member_id: str
    week_start: str              # 리포트 주의 월요일 YYYY-MM-DD
    #: 가장 최근에 보낸 시각(ISO, UTC).
    sent_at: str
    #: 가장 최근에 보낸 본문 — 회원이 받은 글 그대로다.
    message: str
    #: 회원이 가장 최근 전송을 열어 봤는가(`read_at`).
    read: bool
    #: 가장 최근 전송이 PDF 첨부였는가.
    has_pdf: bool
    #: 그 주 리포트를 몇 번 보냈는가. 다시 보낸 적이 있으면 2 이상이다.
    send_count: int = Field(ge=1)


class ReportQueueItemOut(BaseModel):
    """리포트 작업대 한 줄의 수치 — 담당 회원 한 명의 그 주. (#2863)

    작업대가 줄 순서와 신호를 세우는 데 쓰는 값만 싣는다. 같은 회원의
    `WeeklyReportOut` 과 **같은 규칙·같은 값**이다(`sessions_*`·`completion_avg`·
    `week_completion`). 식단·회원 피드백은 편집기를 열 때 리포트가 따로 준다.
    """
    member_id: str
    sessions_booked: int
    sessions_done: int
    completion_avg: int | None   # 기록이 없으면 null (0% 아님)
    week_completion: list[int | None] = Field(default_factory=list)


class ReportQueueOut(BaseModel):
    """그 주 리포트 작업대 — 열람할 수 있는 담당 회원 전원의 요약. (#2863)"""
    week_start: str              # YYYY-MM-DD (월요일)
    items: list[ReportQueueItemOut] = Field(default_factory=list)


class ReportSendsOut(BaseModel):
    """그 주에 리포트가 나간 담당 회원들. 보낸 적이 없으면 빈 목록이다. (#2288)"""
    week_start: str              # YYYY-MM-DD (월요일)
    sends: list[ReportSendOut] = Field(default_factory=list)


class MemberReportSendOut(BaseModel):
    """한 회원에게 한 주 리포트가 나간 기록 — 회원별 지난 리포트 한 줄. (#2393)

    `ReportSendOut` 과 근거·접는 규칙이 같다(그 주의 가장 최근 전송 하나 + 횟수).
    본문 전체 대신 첫 줄만 싣는다 — 목록은 여러 주를 한 번에 세우고, 전문은
    `message_id` 로 채팅에서 찾아 연다.
    """
    week_start: str              # 리포트 주의 월요일 YYYY-MM-DD
    #: 가장 최근에 보낸 시각(ISO, UTC).
    sent_at: str
    #: 회원이 가장 최근 전송을 열어 봤는가(`read_at`).
    read: bool
    #: 그 주 리포트를 몇 번 보냈는가. 다시 보낸 적이 있으면 2 이상이다.
    send_count: int = Field(ge=1)
    #: 가장 최근 전송의 채팅 메시지 id. PDF 로 보냈으면 그 첨부를 가진 메시지다.
    message_id: str
    #: 가장 최근 전송이 PDF 첨부였는가.
    has_pdf: bool
    #: 가장 최근 전송 본문의 첫 줄(비어 있지 않은 첫 줄, 길면 잘라 `…` 를 붙인다).
    feedback_preview: str


class MemberReportSendsOut(BaseModel):
    """한 회원에게 나간 리포트를 최신 주부터. 보낸 적이 없으면 빈 목록이다. (#2393)"""
    member_id: str
    sends: list[MemberReportSendOut] = Field(default_factory=list)
    #: 다음 쪽 커서 — 이 값을 `before` 로 다시 주면 더 오래된 주가 온다.
    #: 더 없으면 null 이다.
    next_before: str | None = None


class TrainerPasswordChange(BaseModel):
    """비밀번호 변경 — 현재 비밀번호 확인 후 교체.

    현재 비밀번호를 요구하는 이유: 토큰이 탈취된 상태에서 비밀번호까지
    바꿔 계정을 완전히 뺏기는 경로를 막는다.
    """
    #: 지금 쓰는 비밀번호는 기준 이전에 만든 것일 수 있어 새 기준을 보지 않는다
    #: — 여기서 막으면 약한 비밀번호를 가진 계정이 그 비밀번호를 바꿀 길이 없다.
    current_password: str = Field(min_length=1, max_length=200)
    #: 가입과 같은 기준(`password_policy.check_new_password`, #1555). 전에는
    #: 8~200자만 봐서 가입 화면이 막는 `12345678` 도, bcrypt 가 앞 72바이트만
    #: 보는 200자짜리도 새 비밀번호로 받았다.
    new_password: str

    @field_validator("new_password")
    @classmethod
    def _check_new_password(cls, value: str) -> str:
        return check_new_password(value)


# ---- 알림 수신 설정 (#379) ----

#: 세션 알림 시점 선택지(분). 앱의 SegmentedSwitch 와 같은 목록 — 서버가
#: 계약을 소유하고, 클라이언트는 이 중에서만 고른다.
REMINDER_LEAD_OPTIONS: tuple[int, ...] = (10, 30, 60)


class TrainerNotificationOut(BaseModel):
    """트레이너 알림함 항목. (#503)

    `category` 는 회원 알림의 집합(reminder|health_check|achievement|system)이 아니라
    트레이너 전용 값이다 — `message`|`consultation`|`reservation`|`health_goal`|
    `member_name`|`member_left`|`consult_withdrawn`|`invite_accepted`|
    `invite_rejected`|`weekly_feedback`(#3026, 회원 주간 피드백 → 그 회원 메모 창
    '피드백' 탭, `subject_id`·`target_date`=주 시작). 한 테이블을 공유하지만 읽는
    화면과 이동할 곳이 다르다.
    """

    id: str
    title: str
    body: str
    category: str
    read: bool
    created_at: _datetime
    time_ago: str
    #: 알림이 가리키는 회원 id — `health_goal` 알림이 그 회원 상세로 가는 데 쓴다(#1832).
    subject_id: str | None = None
    #: 문장 틀 코드와 인자(#2302). 트레이너 웹이 이 둘로 ARB 문장을 조립한다. 틀이
    #: 생기기 전의 알림은 둘 다 없고, 그때는 `title`·`body` 를 그대로 쓴다.
    template: str | None = None
    args: dict[str, Any] | None = None
    #: 알림이 가리키는 날짜(`YYYY-MM-DD`) — 예약·상담 알림이 스케줄을 그 날짜로
    #: 여는 데 쓴다(#2292). 옛 알림에는 없다.
    target_date: str | None = None


#: 미션 키 하나(`report-<id>` 등). 서버는 내용을 해석하지 않고 길이만 막는다.
_TaskKey = Annotated[str, Field(min_length=1, max_length=200)]


class TrainerTaskProgressDayOut(BaseModel):
    """대시보드 `오늘 할 일` 의 하루 진행 상태. (#1633)"""
    date: str
    total: int
    completed_today: int
    completed_carried_over: int
    pending_keys: list[str]
    dismissed_keys: list[str]
    #: 체크한 키(#1716). 이 값이 생기기 전에 저장된 날은 null.
    completed_keys: list[str] | None = None


class TrainerTaskProgressOut(BaseModel):
    """보관 기간 안의 날짜별 진행 상태(날짜 오름차순).

    `first_saved_date` 는 보관 중인 가장 이른 날이다. 앱의 데모 이력이 어디까지
    끼어들어도 되는지의 경계로 쓴다(#1203).
    """
    first_saved_date: str | None
    days: list[TrainerTaskProgressDayOut]


class TrainerTaskProgressSave(BaseModel):
    """하루 진행 상태를 통째로 저장한다 — 부분 수정이 아니다."""
    total: int = Field(ge=0, le=1000)
    completed_today: int = Field(ge=0, le=1000)
    completed_carried_over: int = Field(ge=0, le=1000)
    pending_keys: list[_TaskKey] = Field(default_factory=list, max_length=1000)
    dismissed_keys: list[_TaskKey] = Field(default_factory=list, max_length=1000)
    #: 체크한 키(#1716). 옛 앱은 보내지 않는다 — 그때는 저장하지 않고 null 로 둔다.
    completed_keys: list[_TaskKey] | None = Field(default=None, max_length=1000)

    @model_validator(mode="after")
    def _completed_within_total(self) -> TrainerTaskProgressSave:
        if self.completed_today + self.completed_carried_over > self.total:
            raise ValueError("완료 수는 전체 할 일 수보다 많을 수 없습니다.")
        return self


class TrainerTaskKeyChange(BaseModel):
    """할 일 키 하나의 변경 — 그날 행에 이 키만 더하거나 뺀다. (#2886)

    통째 저장(`TrainerTaskProgressSave`)은 나중에 도착한 쪽이 그날 전체를 덮어써,
    탭·기기 두 곳에서 서로 다른 할 일을 체크하면 한쪽 체크가 사라졌다. 이 요청은
    누른 키 하나만 바꾸고 합계는 서버가 저장된 집합에서 다시 낸다.

    - `keys`: 화면이 지금 보여 주는 미션 키(지운 것 제외). 처음 보는 미션을 그날
      목록에 올린다.
    - `seen`: 이 화면이 그날 한 번이라도 본 미션 키. 저장된 키 중 여기 있으면서
      `keys` 에 없는 것은 화면에서 사라진 미션(처리한 상담 등)이라 목록에서 뺀다.
      여기 없는 저장 키는 이 화면이 모르는 미션이라 그대로 둔다(#2763).
    """
    key: _TaskKey
    action: Literal["check", "uncheck", "dismiss"]
    keys: list[_TaskKey] = Field(default_factory=list, max_length=1000)
    seen: list[_TaskKey] = Field(default_factory=list, max_length=1000)


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
    message: str | None = Field(default=None, max_length=TEXT_LINE_MAX)


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
    #: 운동 시간(분). `duration_seconds` 가 있으면 거기서 반올림한 값이다 —
    #: 분만 보내는 예전 클라이언트를 위해 받기는 계속 받는다. (#2521)
    minutes: int = Field(default=0, ge=0, le=MAX_EXERCISE_MINUTES)
    #: 같은 운동 시간을 초로(#2521). 트레이너가 시·분·초로 적은 그대로다 —
    #: 프로그램 운동(`ProgramDraftExercise`)과 같은 규칙이다. 비어 오면(이 칸이
    #: 생기기 전에 저장된 템플릿) `minutes` × 60 으로 채운다.
    #:
    #: 상한은 편집기의 운동 시간과 같은 열 시간이다. 예전 상한(300분)은 편집기
    #: (600분)보다 짧아, 다섯 시간이 넘는 운동은 템플릿으로 저장할 때 422 였다.
    duration_seconds: int | None = Field(
        default=None, gt=0, le=MAX_EXERCISE_SECONDS
    )
    type: RoutineType = "근력"
    sets: LooseIntZero = Field(default=0, ge=0, le=MAX_EXERCISE_SETS)
    reps: LooseIntZero = Field(default=0, ge=0, le=MAX_EXERCISE_REPS)
    #: 버티는 운동이면 한 세트를 버티는 시간(초). 0 이 "적지 않음" 이고, 값이
    #: 있으면 `reps` 를 비운다 — 이 모델의 다른 칸과 같은 규칙이다. (#1969)
    hold_seconds: LooseIntZero = Field(
        default=0, ge=0, le=MAX_EXERCISE_HOLD_SECONDS
    )
    weight: LooseFloatZero = Field(default=0, ge=0, le=MAX_EXERCISE_WEIGHT_KG)

    @model_validator(mode="after")
    def _sync_duration_units(self) -> ProgramTemplateExercise:
        """분과 초를 맞춘다 — 초가 있으면 초가 기준이고 분은 반올림(최소
        1분)이다. `_sync_duration_units` 와 같은 규칙이다. (#2521)

        분만 있던 동안에는 편집기에서 `버피 45초` 를 템플릿으로 저장하면
        `1분` 으로, `1시간 30분 15초` 는 `90분` 으로 남아 다시 적용할 때 초가
        사라졌다.
        """
        if self.duration_seconds is not None:
            self.minutes = max(1, round(self.duration_seconds / 60))
        elif self.minutes >= 1:
            self.duration_seconds = self.minutes * 60
        else:
            raise ValueError("minutes 또는 duration_seconds 중 하나는 있어야 합니다.")
        return self

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
            self.hold_seconds = 0
            self.weight = 0.0
        elif self.hold_seconds:
            # 버티는 운동이면 초가 맞고 횟수는 비운다. (#1969)
            self.reps = 0
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
