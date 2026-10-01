from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

#: `TrainerSchedule.type` 과 같은 계약값이다(#1083) — 번역하지 않는다.
SessionType = Literal["1:1 PT", "상담"]


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
    #: 트레이너의 다른 일정이 이 시간을 이미 차지했다(#2761). 자리를 연 뒤에
    #: 트레이너가 같은 시간에 일정을 잡거나 옮겨 온 경우다. 회원용 목록에서는
    #: `remaining` 도 0 으로 접혀 마감으로 보이고, 트레이너용 목록은 좌석 수를
    #: 그대로 둔 채 이 표시로 "일정과 겹침" 을 그린다. 일정이 취소·이동되면
    #: 다음 조회에서 저절로 false 로 돌아온다.
    overlapped: bool = False


class TrainerSlotCreate(BaseModel):
    starts_at: datetime
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
