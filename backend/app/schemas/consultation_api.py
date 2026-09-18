from __future__ import annotations

from datetime import date as Date
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

#: 요청이 지정할 수 있는 대상. 트레이너 한 사람뿐이다 — 헬스장 전체로 보내는
#: 갈래는 폐지됐고, 그때 만들어진 이력도 남아 있지 않다.
ConsultationCreateTargetType = Literal["trainer"]
#: 새 상담 요청이 보낼 수 있는 운동 목표. 회원앱 온보딩·MY 의 건강 목표 여덟 종
#: (`health_focus.FOCUS_OPTIONS`)과 1:1 이고, 그 여덟 중 어디에도 넣기 어려운
#: 회원을 위한 `other` 가 하나 더 있다. (#1992)
#:
#: 없앤 `health`(건강 관리)는 **입력에서 받지 않는다** — 여덟 목표 중 하나로 옮길
#: 수 없어 그 회원만 건강 목표가 비어 있었고, 그게 이 통일의 이유다. 이미 저장된
#: `health` 행은 그대로 두고 응답으로 내려준다(아래 [ConsultationOut]).
ExerciseGoal = Literal[
    "weight_loss",
    "strength",
    "fitness",
    "posture",
    "rehab",
    "eating",
    "exercise_habit",
    "blood_pressure",
    "other",
]
HealthPurposeType = Literal[
    "weight", "chronic", "rehab", "general", "none", "other"
]
#: "HH:MM" 정확한 시각이거나 "HH:MM-HH:MM" 시작–종료 범위. 시각 없는
#: "flexible" 은 더 이상 받지 않는다(#1587) — 승인해도 잡을 시간이 없어,
#: 상담이 승인만 되고 일정은 만들어지지 않는 반쪽 상태가 남았다.
#:
#: 예전 flexible/morning/afternoon/evening 값이 이미 저장된 행에 남아 있어
#: **응답**은 `str` 로 느슨하게 받고 **입력**만 이 패턴으로 좁힌다(#1256).
#: 컬럼이 `String(20)` 그대로라 마이그레이션은 필요 없다.
PREFERRED_TIME_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d(?:-([01]\d|2[0-3]):[0-5]\d)?$"


class ConsultationCreate(BaseModel):
    """새 상담 요청. 대상은 트레이너 한 사람이다.

    헬스장 전체로 보내는 갈래를 없앤 이유: 소속 트레이너 누구나 받을 수 있는 요청은
    회원이 누구에게 상담을 거는지 모른 채 보내게 되고, 인박스에서도 "내 요청"과
    "우리 헬스장 요청"이 섞여 화면에서 구분이 안 됐다. 헬스장에서 시작하더라도
    회원이 소속 트레이너 중 한 명을 고른 뒤에 요청이 만들어진다.
    """

    #: 생략 가능하다 — 값은 `trainer` 하나뿐이라 클라이언트가 보낼 이유가 없다.
    target_type: ConsultationCreateTargetType = "trainer"
    trainer_id: str = Field(max_length=64)
    exercise_goal: ExerciseGoal
    health_purpose_type: HealthPurposeType
    health_purpose_detail: str | None = Field(default=None, max_length=500)
    #: 회원이 고른 트레이너의 빈 자리. 희망 시각을 적어 보내던
    #: `preferred_date`+`preferred_time_slot` 을 대신한다. (#1873)
    #:
    #: 자리가 길이까지 들고 있어 상담 시간을 아무도 다시 정하지 않는다 — 예전에는
    #: 회원이 적은 종료 시각이 쓰이지 않고 승인이 늘 시작+30분으로 일정을 만들었다.
    slot_id: str = Field(min_length=1, max_length=64)
    message: str | None = Field(default=None, max_length=2000)
    #: 식단·운동·신체 정보를 트레이너에게 보여 주는 데 동의했는가. (#1022)
    #:
    #: 기본값을 두지 않는다 — 빠뜨리면 422 다. 동의는 "안 보냈으니 승낙"이 될 수
    #: 없고, 화면이 체크를 지우고 보내도 서버가 통과시키면 안 된다.
    data_sharing_consent: bool

    @model_validator(mode="before")
    @classmethod
    def _reject_status(cls, data: Any) -> Any:
        if isinstance(data, dict) and "status" in data:
            raise ValueError("status는 서버에서 설정합니다.")
        return data

    @field_validator("health_purpose_detail", "message", mode="before")
    @classmethod
    def _normalize_optional_text(cls, value: Any) -> Any:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

    @field_validator("trainer_id", mode="before")
    @classmethod
    def _normalize_trainer_id(cls, value: Any) -> Any:
        """공백만 보낸 trainer_id 는 누락으로 본다 — 대상 없는 요청은 만들 수 없다."""
        if isinstance(value, str):
            value = value.strip()
            if not value:
                raise ValueError("상담을 요청할 트레이너를 지정해야 합니다.")
        return value

    @model_validator(mode="after")
    def _validate_target(self) -> ConsultationCreate:
        if self.health_purpose_type == "other" and self.health_purpose_detail is None:
            raise ValueError("기타 건강관리 목적에는 상세 내용이 필요합니다.")
        return self


#: 트레이너 인박스가 걸 수 있는 상태 필터. `all` 은 처리 이력까지 함께 본다.
#:
#: `expired` 는 트레이너가 시간 안에 확인하지 않아 자리가 풀린 요청이다 —
#: `rejected`(트레이너의 판단)와 구분한다. 대기 건수에서는 빠진다. (#1873)
ConsultationStatusFilter = Literal[
    "pending", "accepted", "rejected", "cancelled", "expired", "all"
]


class ConsultationDecision(BaseModel):
    """승인·거절 본문. 거절 사유는 회원 알림 본문에 그대로 실린다."""

    note: str | None = Field(default=None, max_length=500)

    @field_validator("note", mode="before")
    @classmethod
    def _normalize_note(cls, value: Any) -> Any:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value


class ConsultationAccept(ConsultationDecision):
    """승인 본문. 남는 것은 `note` 뿐이다. (#1873)

    예전에는 트레이너가 승인하면서 날짜·시각·종류·소요 시간을 함께 보냈다. 지금은
    **회원이 고른 자리**가 그 넷을 모두 들고 있어 승인이 시각을 정하지 않는다 —
    시각을 정하는 사람이 둘이면 회원은 자기가 모르는 일정에 묶인다.
    """


class ConsultationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    member_id: str
    trainer_id: str | None
    #: 목록 카드가 이름을 렌더한다. id 만 주면 앱이 트레이너마다 상세를 다시 조회해야
    #: 하고, 대상이 지워지면 이름을 영영 못 만든다(#327).
    trainer_name: str | None = None
    trainer_gym_name: str | None = None
    #: 응답은 없앤 `health`(건강 관리)를 포함해 저장된 그대로 내려준다 — 입력
    #: 쪽(`ConsultationCreate`)만 새 목록으로 좁혔다. `preferred_time_slot` 과
    #: 같은 규칙이고, 이미 접수된 요청을 백필하지 않기 때문이다(#1992).
    exercise_goal: str
    health_purpose_type: HealthPurposeType
    health_purpose_detail: str | None
    #: 회원이 고른 자리의 시각 사본. 자리 선택 이전 요청에는 회원이 적어 보낸
    #: 희망 시각이 그대로 남아 있다 — 그 요청들도 계속 조회돼야 해 두 칸을 지우지
    #: 않았다(#1873).
    preferred_date: Date
    #: 응답은 과거 morning/afternoon/evening 값을 포함해 저장된 그대로 내려준다 —
    #: 입력 쪽(`ConsultationCreate`)만 새 형식으로 좁혔다.
    preferred_time_slot: str
    #: 회원이 고른 자리. 화면이 **확정된 일시**를 그리는 자리다 — 승인 뒤에도
    #: 회원이 "언제로 잡혔는지"를 상담 내역에서 확인할 수 있어야 한다. (#1873)
    #:
    #: 자리 선택 이전 요청과, 트레이너가 자리를 지운 요청에서는 비어 있다. 그때는
    #: 화면이 위 `preferred_date`·`preferred_time_slot` 으로 되돌아간다.
    slot_id: str | None = None
    slot_starts_at: datetime | None = None
    slot_duration_minutes: int | None = None
    message: str | None
    status: str
    #: 거절 사유. 트레이너가 남긴 문장이 그대로 온다. (#473)
    #:
    #: 처리자 id(`decided_by`)는 **회원 응답에 싣지 않는다** — 회원에게 필요한 것은
    #: 결과와 이유이지 누가 눌렀는지가 아니다.
    decision_note: str | None = None
    #: 처리 시각. 화면이 "언제 답을 받았는지"를 보여 준다.
    decided_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class TrainerConsultationOut(ConsultationOut):
    """트레이너 인박스 카드. 회원용 [ConsultationOut] 에 처리 정보를 더한다.

    회원 응답과 스키마를 나누는 이유: 회원에게는 **누가 처리했는지**가 필요 없고,
    트레이너에게는 요청자 이름이 반드시 필요하다(회원 id 만으로는 카드를 못 그린다).
    한 스키마에 다 담으면 회원 응답에도 처리자 id 가 실린다.
    """

    #: 요청한 회원 이름. 대상 이름과 같은 이유로 id 대신 함께 내려준다.
    member_name: str | None = None
    #: 처리한 트레이너. 지금은 요청 대상(`trainer_id`)과 항상 같지만, 인박스 이력이
    #: "누가 언제 처리했는지"를 그대로 보여 줘야 해 응답에 남긴다. 회원 응답에는
    #: 없는 필드다.
    decided_by: str | None = None


class ConsultationAcceptOut(TrainerConsultationOut):
    """승인으로 실제 만들어진 결과를 화면이 판별할 수 있게 한다."""

    client_connected: bool = True
    schedule_created: bool
    schedule_id: str | None = None
