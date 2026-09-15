from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

#: `TrainerSchedule.type` 과 같은 계약값이다(#1083) — 번역하지 않는다.
#: `체험` 은 `포인트 체험 허용` 으로 연 20분 자세 점검 자리다(#1790).
SessionType = Literal["1:1 PT", "상담", "체험"]


class TrainerSlotOut(BaseModel):
    id: str
    trainer_id: str
    starts_at: datetime
    duration_minutes: int = 60
    capacity: int
    remaining: int
    is_closed: bool = False
    session_type: SessionType = "1:1 PT"
    #: 이 자리를 잡은 회원 이름. 트레이너용 목록(`GET /trainer/reservation-slots`)
    #: 에서만 채운다 — 회원용 목록(`GET /trainers/{id}/slots`)은 다른 회원의
    #: 이름을 알 이유가 없어 항상 null이다.
    booked_by_name: str | None = None
    #: 이 자리를 예약하는 데 드는 포인트. 체험 자리만 500, 나머지는 0이다(#1790).
    points_cost: int = 0
    #: 회원용 목록의 체험 자리에서만 채운다 — 이 회원이 지금 예약할 수 없는 이유
    #: (`trial_used`|`insufficient_points`), 가능하면 null. 담당 트레이너가 있는
    #: 회원에게는 체험 자리 자체를 내주지 않는다.
    trial_blocked_reason: str | None = None


class TrainerSlotCreate(BaseModel):
    starts_at: datetime
    #: 체험 자리(`session_type == "체험"`)는 이 값과 상관없이 20분이다.
    duration_minutes: int | None = Field(default=None, ge=5, le=600)
    session_type: SessionType = "1:1 PT"

    @model_validator(mode="after")
    def require_timezone(self) -> TrainerSlotCreate:
        if self.starts_at.tzinfo is None or self.starts_at.utcoffset() is None:
            raise ValueError("starts_at에는 시간대가 포함되어야 합니다.")
        return self


class TrainerSlotUpdate(BaseModel):
    starts_at: datetime | None = None
    duration_minutes: int | None = Field(default=None, ge=5, le=600)
    session_type: SessionType | None = None
    is_closed: bool | None = None

    @model_validator(mode="after")
    def validate_update(self) -> TrainerSlotUpdate:
        if not self.model_fields_set:
            raise ValueError("수정할 항목이 없습니다.")
        if "starts_at" in self.model_fields_set:
            if self.starts_at is None:
                raise ValueError("starts_at은 null일 수 없습니다.")
            if self.starts_at.tzinfo is None or self.starts_at.utcoffset() is None:
                raise ValueError("starts_at에는 시간대가 포함되어야 합니다.")
        for field in self.model_fields_set:
            if getattr(self, field) is None:
                raise ValueError(f"{field}은 null일 수 없습니다.")
        return self


class ReservationCreate(BaseModel):
    slot_id: str = Field(min_length=1, max_length=64)


class ReservationOut(BaseModel):
    id: str
    slot_id: str
    schedule_id: str
    status: str
    created_at: datetime
    session_type: SessionType = "1:1 PT"
    #: 이 예약에 쓴 포인트. 체험 예약만 500이다(#1790).
    points_spent: int = 0
    #: 포인트를 쓴 뒤의 잔액. 포인트를 쓰지 않은 예약은 null이다.
    points_balance: int | None = None


class MyReservationOut(BaseModel):
    """회원의 예약 한 건 — '내 예약' 목록과 취소 버튼이 읽는 형태. (#502)

    슬롯 시각을 함께 실어 준다. 앱이 이걸 알아야 어느 자리가 내 예약인지 표시하고
    지난 예약에 취소 버튼을 띄우지 않을 수 있다.
    """

    id: str
    slot_id: str
    trainer_id: str
    starts_at: datetime
    #: 이 시각을 지나면 취소할 수 없다. 서버 판단을 그대로 내려, 앱이 자기
    #: 시계로 다시 계산하다 서버와 어긋나는 일이 없게 한다.
    cancellable: bool
    session_type: SessionType = "1:1 PT"
    #: 이 예약에 쓴 포인트(체험 예약만 500).
    points_cost: int = 0
    #: 지금 취소하면 포인트를 돌려받는가. 체험 예약이 시작 24시간 전일 때만 true —
    #: 취소 확인창이 이 값으로 반환·소멸 문구를 고른다(#1790).
    points_refundable: bool = False


class ReservationCancelOut(BaseModel):
    status: Literal["cancelled"] = "cancelled"
    #: 이번 취소로 돌려받은 포인트. 체험 예약을 24시간 전까지 취소했을 때만 0보다 크다.
    points_refunded: int = 0
