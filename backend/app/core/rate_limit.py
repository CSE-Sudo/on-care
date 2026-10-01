"""간단한 인메모리 rate limiter (브루트포스 방어).

인증 엔드포인트(로그인/회원가입/refresh/소셜)에 IP·엔드포인트별 슬라이딩 윈도우로
분당 시도 횟수를 제한한다. 단일 인스턴스/데모에 충분하며, 다중 인스턴스 운영에서는
Redis 백엔드로 교체(같은 check() 인터페이스 유지)하면 된다.

키는 `엔드포인트 + IP`(또는 트레이너 id) 조합이라 바깥에서 늘릴 수 있다. 그래서
윈도우가 지난 키는 들고 있지 않는다 — check() 안에서 비워진 키를 바로 지우고,
주기적으로 만료 키를 훑어 정리하며, 그래도 남으면 키 총수 상한으로 자른다.

RATE_LIMIT_ENABLED=false 로 끌 수 있고, RATE_LIMIT_AUTH_PER_MINUTE 로 한도를 조정한다.

**IP 는 `app.core.client_ip.client_ip` 로 읽는다**(#2815) — 감사 로그와 같은 함수다.
요청자가 `X-Forwarded-For` 를 바꿔 보내도 버킷이 갈라지지 않는다.

IP 버킷만으로는 부족한 곳(로그인·연결 코드·비밀번호 변경·가입)은 계정·이메일·
사용자 id 를 키로 하는 버킷을 같이 건다(`check_key`, 실패 잠금 `ensure_unlocked`·
`record_failure`). IP 를 바꿔도 같은 계정을 노리는 시도는 한 버킷에 모인다.

**저장소는 프로세스 메모리다.** 인스턴스가 N 개면 한도도 N 배가 된다. 운영 인스턴스가
하나를 넘게 되면 같은 메서드(`check`·`retry_after`·`hit`·`reset`)를 가진 공유
저장소(Redis 등) 구현으로 `limiter` 를 바꾼다 — 호출하는 쪽은 그대로다.
"""
from __future__ import annotations

import threading
import time
from collections import deque

from fastapi import HTTPException, Request, status

from app.core.client_ip import client_ip
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

    def check(self, key: str, limit: int, window: float) -> None:
        """key 에 대해 window(초) 동안 limit 회 초과 시 429."""
        now = time.monotonic()
        with self._lock:
            if now >= self._next_sweep:
                self._sweep(now)
            dq = self._live(key, now, window)
            # 한도 판정은 키가 없을 때(0회)도 예전과 똑같이 먼저 한다 — limit 이 0 이면
            # 첫 요청부터 막히고, 그때 키는 만들지 않는다.
            if (len(dq) if dq is not None else 0) >= limit:
                raise too_many_requests(window)
            self._append(key, now, window, dq)

    def retry_after(self, key: str, limit: int, window: float) -> int | None:
        """기록하지 않고 한도만 본다. 막혔으면 풀릴 때까지 남은 초, 아니면 None.

        실패만 세는 버킷(로그인 잠금)이 쓴다 — 시도할 때가 아니라 틀렸을 때 `hit`
        으로 센다.
        """
        now = time.monotonic()
        with self._lock:
            dq = self._live(key, now, window)
            count = len(dq) if dq is not None else 0
            if count < limit:
                return None
            if dq is None:
                return int(window)
            # 가장 오래된 기록이 창 밖으로 나가면 한 번 더 시도할 수 있다.
            return max(1, int(dq[0] + window - now + 0.999))

    def hit(self, key: str, window: float) -> None:
        """한도 판정 없이 한 번 센다."""
        now = time.monotonic()
        with self._lock:
            if now >= self._next_sweep:
                self._sweep(now)
            self._append(key, now, window, self._live(key, now, window))

    def reset(self, key: str) -> None:
        """key 의 기록을 지운다(로그인 성공 시 실패 기록 초기화)."""
        with self._lock:
            self._drop(key)

    # ---- 내부: 기록 ----

    def _live(self, key: str, now: float, window: float) -> deque[float] | None:
        """창 안에 남은 기록. 비었으면 키를 지우고 None. 호출자가 _lock 을 쥔다."""
        dq = self._hits.get(key)
        if dq is None:
            return None
        cutoff = now - window
        while dq and dq[0] <= cutoff:
            dq.popleft()
        if not dq:
            # 윈도우가 지난 키는 남기지 않는다.
            self._drop(key)
            return None
        return dq

    def _append(
        self, key: str, now: float, window: float, dq: deque[float] | None
    ) -> None:
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


def too_many_requests(retry_after: float) -> HTTPException:
    """모든 버킷이 같은 429 문구·`Retry-After` 를 쓴다(화면은 기존 안내 그대로)."""
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.",
        headers={"Retry-After": str(max(1, int(retry_after)))},
    )


def check_key(key: str, limit: int, window: float = 60.0) -> None:
    """IP 가 아닌 키(사용자 id·이메일 등)로 한도를 건다. 끄면 아무것도 하지 않는다."""
    if not get_settings().rate_limit_enabled:
        return
    limiter.check(key, limit, window)


def ensure_unlocked(key: str, limit: int, window: float) -> None:
    """실패 기록이 한도에 닿은 키면 429. 시도 자체는 세지 않는다."""
    if not get_settings().rate_limit_enabled:
        return
    retry = limiter.retry_after(key, limit, window)
    if retry is not None:
        raise too_many_requests(retry)


def record_failure(key: str, window: float) -> None:
    """실패 한 번을 센다(`ensure_unlocked` 와 짝)."""
    if not get_settings().rate_limit_enabled:
        return
    limiter.hit(key, window)


def clear_failures(key: str) -> None:
    """성공하면 실패 기록을 지운다."""
    limiter.reset(key)


def register_email_key(email: str) -> str:
    """가입 시도 이메일 버킷 키(#2913). 회원·트레이너 가입이 같은 키를 쓴다."""
    return f"register-email:{email.strip().lower()}"


def password_change_fail_key(user_id: str) -> str:
    """비밀번호 변경 실패 잠금 키(#2913). 회원 쪽 변경도 같은 키 규칙을 쓴다."""
    return f"password-change-fail:{user_id}"


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
        # 감사 로그와 같은 함수로 읽는다(#2815) — 위조한 X-Forwarded-For 로 버킷이
        # 갈라지지 않는다.
        ip = client_ip(request) or "unknown"
        limit = per_minute or settings.rate_limit_auth_per_minute
        limiter.check(f"{bucket}:{ip}", limit, 60.0)

    return _dep
