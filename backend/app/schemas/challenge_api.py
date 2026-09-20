"""주간 운동 챌린지 응답 스키마. (#1789)"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class ChallengeOut(BaseModel):
    """참가한 주간 챌린지 한 건.

    `status`: active(진행 중)|succeeded(성공)|failed(실패). 주가 끝난 뒤 판정한다.
    `progress` 는 그 주에 운동 기록이 있는 날 수다(같은 날 여러 번은 1). 진행 중이면
    지금까지, 판정했으면 판정 때 센 값이다. `rewarded` 는 받은 보상으로, 성공이 아니면 0.
    """

    id: str
    #: 그 주의 월요일·일요일(KST, YYYY-MM-DD).
    week_start: str
    week_end: str
    goal: int
    progress: int
    stake: int
    reward: int
    status: str
    #: 목표를 채웠는가. 진행 중에도 참일 수 있다 — 보상은 주가 끝나야 받는다.
    achieved: bool
    rewarded: int
    joined_at: datetime
    settled_at: datetime | None = None


class WeeklyChallengeOut(BaseModel):
    """GET /me/challenges/weekly — 이번 주 챌린지와 지금 참가할 수 있는지.

    `goal` 은 참가했으면 고정된 목표, 아니면 지금 참가하면 걸릴 목표다.
    `blocked_reason`: `already_joined`(이번 주 참가함)·`join_closed`(월·화요일이 아님)·
    `insufficient_points`(잔액 부족). 참가할 수 있으면 null. `shortfall` 은 건 포인트에
    모자란 포인트(모자라지 않으면 0).
    """

    week_start: str
    week_end: str
    #: 참가할 수 있는 마지막 날(이번 주 화요일).
    join_until: str
    stake: int
    reward: int
    goal: int
    #: 이번 주에 운동 기록이 있는 날 수(오늘까지). 참가 여부와 상관없다.
    progress: int
    balance: int
    joinable: bool
    blocked_reason: str | None = None
    shortfall: int = 0
    challenge: ChallengeOut | None = None


class ChallengeJoinRequest(BaseModel):
    """POST /me/challenges/weekly/join 입력.

    `client_request_id` 는 참가 시도 단위 멱등키다. 같은 값으로 다시 보내면 새로
    걸지 않고 처음 참가 기록을 돌려준다.
    """

    client_request_id: str | None = Field(default=None, min_length=1, max_length=64)


class ChallengeJoinOut(BaseModel):
    """참가 응답 — 참가 기록, 건 포인트, 그 뒤의 잔액."""

    challenge: ChallengeOut
    spent: int
    balance: int
