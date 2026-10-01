"""간단한 인메모리 rate limiter (브루트포스 방어).

인증 엔드포인트(로그인/회원가입/refresh/소셜)에 IP·엔드포인트별 슬라이딩 윈도우로
분당 시도 횟수를 제한한다. 단일 인스턴스/데모에 충분하며, 다중 인스턴스 운영에서는
Redis 백엔드로 교체(같은 check() 인터페이스 유지)하면 된다.

키는 `엔드포인트 + IP`(또는 트레이너·회원 id — [check_user]) 조합이라 바깥에서 늘릴 수 있다. 그래서
윈도우가 지난 키는 들고 있지 않는다 — check() 안에서 비워진 키를 바로 지우고,
주기적으로 만료 키를 훑어 정리하며, 그래도 남으면 키 총수 상한으로 자른다.

RATE_LIMIT_ENABLED=false 로 끌 수 있고, RATE_LIMIT_AUTH_PER_MINUTE 로 한도를 조정한다.
"""
from __future__ import annotations

import threading
import time
from collections import deque

from fastapi import HTTPException, Request, status

from app.core.config import get_settings

#: 만료 키 청소 주기(초). 요청마다 전체를 훑지 않기 위한 간격이다.
SWEEP_INTERVAL = 60.0
#: 키 총수 상한. 한 청소 주기 안에 서로 다른 키가 쏟아져도 메모리가 열리지 않게 한다.
MAX_KEYS = 10_000


class RateLimiter:
    def __init__(
        self,
        *,
        max_keys: int = MAX_KEYS,
        sweep_interval: float = SWEEP_INTERVAL,
    ) -> None:
        self._hits: dict[str, deque[float]] = {}
        # 키별 만료 시각(마지막 기록 + window). 청소할 때 window 를 다시 받지 않아도
        # 되도록 기록해 둔다 — 버킷마다 window 가 다를 수 있다.
        self._expires_at: dict[str, float] = {}
        self._max_keys = max_keys
        self._sweep_interval = sweep_interval
        self._next_sweep = time.monotonic() + sweep_interval
        self._lock = threading.Lock()

    def clear(self) -> None:
        """상태 초기화(테스트 격리용)."""
        with self._lock:
            self._hits.clear()
            self._expires_at.clear()
            self._next_sweep = time.monotonic() + self._sweep_interval

    def check(
        self, key: str, limit: int, window: float, *, detail: object | None = None
    ) -> None:
        """key 에 대해 window(초) 동안 limit 회 초과 시 429.

        [detail] 을 주면 429 응답의 `detail` 로 쓴다 — 앱이 다른 429(하루 상한 등)와
        구분해야 하는 경로는 `{code, message}` 를 넘긴다.
        """
        now = time.monotonic()
        with self._lock:
            if now >= self._next_sweep:
                self._sweep(now)
            dq = self._hits.get(key)
            if dq is not None:
                cutoff = now - window
                while dq and dq[0] <= cutoff:
                    dq.popleft()
                if not dq:
                    # 윈도우가 지난 키는 남기지 않는다.
                    self._drop(key)
                    dq = None
            # 한도 판정은 키가 없을 때(0회)도 예전과 똑같이 먼저 한다 — limit 이 0 이면
            # 첫 요청부터 막히고, 그때 키는 만들지 않는다.
            if (len(dq) if dq is not None else 0) >= limit:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=detail
                    if detail is not None
                    else "요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.",
                    headers={"Retry-After": str(int(window))},
                )
            if dq is None:
                self._make_room(now)
                dq = self._hits[key] = deque()
            dq.append(now)
            self._expires_at[key] = now + window

    # ---- 내부: 키 정리 ----

    def _drop(self, key: str) -> None:
        self._hits.pop(key, None)
        self._expires_at.pop(key, None)

    def _sweep(self, now: float) -> None:
        """만료된 키를 한 번에 걷어낸다. 호출자가 _lock 을 쥔 상태로 부른다."""
        for key in [k for k, exp in self._expires_at.items() if exp <= now]:
            self._drop(key)
        self._next_sweep = now + self._sweep_interval

    def _make_room(self, now: float) -> None:
        """새 키를 받기 전 상한을 지킨다. 호출자가 _lock 을 쥔 상태로 부른다."""
        if len(self._hits) < self._max_keys:
            return
        self._sweep(now)
        if len(self._hits) < self._max_keys:
            return
        # 청소로도 안 줄면 곧 만료될 키부터 버린다 — 어차피 가장 먼저 풀릴 한도라
        # 아직 살아 있는 다른 키의 방어를 덜 깎는다.
        victims = sorted(self._expires_at, key=self._expires_at.__getitem__)
        for key in victims[: len(self._hits) - self._max_keys + 1]:
            self._drop(key)


limiter = RateLimiter()


def rate_limit(bucket: str, per_minute: int | None = None):
    """엔드포인트에 붙일 의존성 팩토리. bucket 은 엔드포인트 구분자.

    `per_minute` 를 주면 그 한도를, 안 주면 인증용 기본 한도를 쓴다. LLM 호출처럼
    실패해도 비용이 나가는 엔드포인트는 브루트포스 방어와 목적이 달라 한도를 따로
    잡는다.
    """

    def _dep(request: Request) -> None:
        settings = get_settings()
        if not settings.rate_limit_enabled:
            return
        ip = request.client.host if request.client else "unknown"
        limit = per_minute or settings.rate_limit_auth_per_minute
        limiter.check(f"{bucket}:{ip}", limit, 60.0)

    return _dep


def check_user(
    bucket: str, user_id: str, per_minute: int, *, detail: object | None = None
) -> None:
    """사용자 id 버킷으로 분당 한도를 센다. (#2827)

    IP 버킷은 같은 헬스장 Wi-Fi 의 회원들이 한 버킷을 나눠 쓴다 — 한 사람의 폭주가
    옆 사람의 기록을 막는다. 로그인한 사용자의 비용 가드는 사람 단위로 센다(트레이너
    AI 코치의 트레이너 id 버킷 #1548 과 같은 방식). `per_minute` 가 0 이하면 끈다.
    """
    if not get_settings().rate_limit_enabled or per_minute <= 0:
        return
    limiter.check(f"{bucket}:user:{user_id}", per_minute, 60.0, detail=detail)
