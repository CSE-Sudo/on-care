"""Rate limiter (브루트포스 방어·비용 가드).

인증 엔드포인트(로그인/회원가입/refresh/소셜)에 IP·엔드포인트별 슬라이딩 윈도우로
분당 시도 횟수를 제한한다.

키는 `엔드포인트 + IP`(또는 트레이너·회원 id — [check_user]) 조합이라 바깥에서 늘릴 수 있다. 그래서
윈도우가 지난 키는 들고 있지 않는다 — check() 안에서 비워진 키를 바로 지우고,
주기적으로 만료 키를 훑어 정리하며, 그래도 남으면 키 총수 상한으로 자른다.

RATE_LIMIT_ENABLED=false 로 끌 수 있고, RATE_LIMIT_AUTH_PER_MINUTE 로 한도를 조정한다.

**IP 는 `app.core.client_ip.client_ip` 로 읽는다**(#2815) — 감사 로그와 같은 함수다.
요청자가 `X-Forwarded-For` 를 바꿔 보내도 버킷이 갈라지지 않는다.

IP 버킷만으로는 부족한 곳(로그인·연결 코드·비밀번호 변경·가입)은 계정·이메일·
사용자 id 를 키로 하는 버킷을 같이 건다(`check_key`, 실패 잠금 `ensure_unlocked`·
`record_failure`). IP 를 바꿔도 같은 계정을 노리는 시도는 한 버킷에 모인다.

**저장소는 두 가지다(#3143).** 같은 메서드(`check`·`retry_after`·`hit`·`reset`·`clear`)를
갖고, 모듈의 `limiter` 가 설정(`RATE_LIMIT_STORE`)을 보고 매 호출 고른다 — 호출하는 쪽은
저장소를 모른다.

- `RateLimiter`(memory): 프로세스 메모리. 개발·테스트 기본값. 인스턴스가 N 개면 한도도
  N 배가 되고 재시작하면 잠금이 풀린다.
- `DatabaseRateLimiter`(database): Postgres 표 `rate_limit_hits`. 운영 기본값. 태스크·워커가
  여럿이어도 한 한도를 나눠 쓰고 재배포에도 잠금이 남는다. 한도 대상 요청마다 DB 왕복이
  한 번 늘어난다.
"""
from __future__ import annotations

import logging
import threading
import time
from collections import deque
from typing import Any

from fastapi import HTTPException, Request, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.core import metrics
from app.core.client_ip import client_ip
from app.core.config import get_settings

logger = logging.getLogger(__name__)

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
            dq = self._live(key, now, window)
            # 한도 판정은 키가 없을 때(0회)도 예전과 똑같이 먼저 한다 — limit 이 0 이면
            # 첫 요청부터 막히고, 그때 키는 만들지 않는다.
            if (len(dq) if dq is not None else 0) >= limit:
                raise too_many_requests(window, detail=detail)
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


#: 키 단위 트랜잭션 잠금의 이름공간. `pg_advisory_xact_lock(int4, int4)` 의 첫 값이다 —
#: 두 정수 형식은 마이그레이션·문서 적재가 쓰는 bigint 형식 잠금과 겹치지 않는다.
_ADVISORY_NAMESPACE = 0x524C  # "RL"

#: 창 길이(초) → interval. 모든 질의가 같은 식을 쓴다.
_WINDOW = "make_interval(secs => CAST(:window AS double precision))"

_WINDOW_HITS_SQL = text(
    f"""
    SELECT count(*) AS hits,
           EXTRACT(EPOCH FROM (min(hit_at) + {_WINDOW} - clock_timestamp())) AS oldest_left
    FROM rate_limit_hits
    WHERE key = :key AND hit_at > clock_timestamp() - {_WINDOW}
    """
)
_INSERT_HIT_SQL = text(
    f"""
    INSERT INTO rate_limit_hits (key, hit_at, expires_at)
    VALUES (:key, clock_timestamp(), clock_timestamp() + {_WINDOW})
    """
)
_LOCK_KEY_SQL = text(
    "SELECT pg_advisory_xact_lock(CAST(:ns AS integer), hashtext(CAST(:key AS text)))"
)
_DROP_EXPIRED_KEY_SQL = text(
    "DELETE FROM rate_limit_hits WHERE key = :key AND expires_at <= clock_timestamp()"
)
_PURGE_EXPIRED_SQL = text("DELETE FROM rate_limit_hits WHERE expires_at <= clock_timestamp()")


class DatabaseRateLimiter:
    """Postgres 공유 저장소(`rate_limit_hits`) 구현. `RateLimiter` 와 같은 메서드. (#3143)

    - 시도 한 번이 한 행이다. 창 안의 행 수로 판정하므로 메모리 구현과 같은 슬라이딩
      창이다 — 고정 창 카운터처럼 창 경계에서 한도의 두 배가 통과하는 일이 없다(로그인
      잠금이 경계에서 풀리지 않는다).
    - `check` 는 키 단위 트랜잭션 잠금(`pg_advisory_xact_lock`) 안에서 세고 기록한다.
      여러 태스크·워커가 같은 키를 동시에 세도 한도를 넘지 않는다.
    - 시각은 DB 의 `clock_timestamp()` 하나만 쓴다 — 태스크마다 시계가 조금씩 달라도
      판정이 같다.
    - 막힌 시도는 기록하지 않는다(메모리 구현과 같다). 한 키의 행 수는 한도를 넘지 않는다.
    - 만료 행은 판정할 때 그 키의 것을, `sweep_interval` 마다 전체를 지운다.
      정기 정리 작업은 [purge_expired] 를 부른다.
    - DB 오류는 한도를 열어 둔 채(fail-open) 오류 로그·메트릭(`rate_limit.store_errors`)만
      남긴다. 한도 저장소 장애로 로그인·가입 전체를 막지 않기 위해서다 — 같은 DB 가
      내려가면 로그인 자체가 어차피 실패한다.
    """

    def __init__(self, *, engine: Any | None = None, sweep_interval: float = SWEEP_INTERVAL) -> None:
        self._engine = engine
        self._sweep_interval = sweep_interval
        self._next_sweep = time.monotonic() + sweep_interval
        self._sweep_lock = threading.Lock()

    def _bind(self) -> Any:
        if self._engine is None:
            # 앱 엔진(연결 풀·statement_timeout 공유). 순수 테스트가 이 모듈을 import 할 때
            # DB 모듈을 끌어오지 않도록 처음 쓸 때 읽는다.
            from app.db.session import engine

            self._engine = engine
        return self._engine

    def check(
        self, key: str, limit: int, window: float, *, detail: object | None = None
    ) -> None:
        """key 에 대해 window(초) 동안 limit 회 초과 시 429. 막히지 않으면 한 번 기록한다."""
        if limit <= 0:
            # 메모리 구현과 같다 — 첫 요청부터 막고, 행은 남기지 않는다.
            raise too_many_requests(window, detail=detail)
        params = {"key": key, "window": float(window)}
        try:
            with self._bind().begin() as conn:
                conn.execute(_LOCK_KEY_SQL, {"ns": _ADVISORY_NAMESPACE, "key": key})
                conn.execute(_DROP_EXPIRED_KEY_SQL, {"key": key})
                hits = conn.execute(_WINDOW_HITS_SQL, params).one().hits
                if hits >= limit:
                    blocked = True
                else:
                    blocked = False
                    conn.execute(_INSERT_HIT_SQL, params)
        except SQLAlchemyError:
            self._store_error("check", key)
            return
        if blocked:
            raise too_many_requests(window, detail=detail)
        self._maybe_sweep()

    def retry_after(self, key: str, limit: int, window: float) -> int | None:
        """기록하지 않고 한도만 본다. 막혔으면 풀릴 때까지 남은 초, 아니면 None."""
        try:
            with self._bind().connect() as conn:
                row = conn.execute(
                    _WINDOW_HITS_SQL, {"key": key, "window": float(window)}
                ).one()
        except SQLAlchemyError:
            self._store_error("retry_after", key)
            return None
        if row.hits < limit:
            return None
        if row.oldest_left is None:
            return int(window)
        # 가장 오래된 기록이 창 밖으로 나가면 한 번 더 시도할 수 있다.
        return max(1, int(float(row.oldest_left) + 0.999))

    def hit(self, key: str, window: float) -> None:
        """한도 판정 없이 한 번 센다."""
        try:
            with self._bind().begin() as conn:
                conn.execute(_INSERT_HIT_SQL, {"key": key, "window": float(window)})
        except SQLAlchemyError:
            self._store_error("hit", key)
            return
        self._maybe_sweep()

    def reset(self, key: str) -> None:
        """key 의 기록을 지운다(로그인 성공 시 실패 기록 초기화)."""
        try:
            with self._bind().begin() as conn:
                conn.execute(text("DELETE FROM rate_limit_hits WHERE key = :key"), {"key": key})
        except SQLAlchemyError:
            self._store_error("reset", key)

    def clear(self) -> None:
        """모든 기록을 지운다(테스트 격리용)."""
        with self._bind().begin() as conn:
            conn.execute(text("DELETE FROM rate_limit_hits"))
        self._next_sweep = time.monotonic() + self._sweep_interval

    def purge_expired(self) -> int:
        """만료된 행을 지우고 지운 수를 돌려준다. 정기 정리 작업이 부른다."""
        with self._bind().begin() as conn:
            return int(conn.execute(_PURGE_EXPIRED_SQL).rowcount or 0)

    # ---- 내부 ----

    def _maybe_sweep(self) -> None:
        """`sweep_interval` 마다 한 번 만료 행 전체를 지운다. 다시 오지 않는 키도 남지 않는다."""
        now = time.monotonic()
        if now < self._next_sweep or not self._sweep_lock.acquire(blocking=False):
            return
        try:
            self._next_sweep = now + self._sweep_interval
            self.purge_expired()
        except SQLAlchemyError:
            self._store_error("sweep", "*")
        finally:
            self._sweep_lock.release()

    @staticmethod
    def _store_error(op: str, key: str) -> None:
        metrics.incr("rate_limit.store_errors", op=op)
        # 키에는 이메일이 들어갈 수 있어 버킷 이름(첫 ':' 앞)만 남긴다.
        logger.error(
            "시도 제한 저장소 오류 — 이번 요청은 한도 없이 통과합니다 (op=%s, bucket=%s)",
            op, key.split(":", 1)[0], exc_info=True,
        )


class ConfiguredLimiter:
    """설정(`RATE_LIMIT_STORE`)이 고른 저장소로 넘긴다. 모듈의 `limiter` 다. (#3143)

    호출부는 `limiter.check(...)` 처럼 이 객체만 안다. 매 호출 설정을 읽으므로 테스트가
    설정을 바꾸면 바로 그 저장소를 쓴다.
    """

    def __init__(self) -> None:
        self.memory = RateLimiter()
        self.database = DatabaseRateLimiter()

    def store(self) -> RateLimiter | DatabaseRateLimiter:
        if get_settings().rate_limit_backend == "database":
            return self.database
        return self.memory

    def check(
        self, key: str, limit: int, window: float, *, detail: object | None = None
    ) -> None:
        self.store().check(key, limit, window, detail=detail)

    def retry_after(self, key: str, limit: int, window: float) -> int | None:
        return self.store().retry_after(key, limit, window)

    def hit(self, key: str, window: float) -> None:
        self.store().hit(key, window)

    def reset(self, key: str) -> None:
        self.store().reset(key)

    def clear(self) -> None:
        """상태 초기화(테스트 격리용). DB 저장소는 그 저장소를 쓰는 중일 때만 비운다 —
        DB 없이 도는 순수 테스트가 DB 에 닿지 않게."""
        self.memory.clear()
        if get_settings().rate_limit_backend == "database":
            self.database.clear()


limiter = ConfiguredLimiter()


def purge_expired() -> int:
    """공유 저장소의 만료 행을 지운다(지운 수). 메모리 저장소면 0. 정기 정리 작업용."""
    if get_settings().rate_limit_backend != "database":
        return 0
    return limiter.database.purge_expired()


def too_many_requests(
    retry_after: float, *, detail: object | None = None
) -> HTTPException:
    """모든 버킷이 같은 429 문구·`Retry-After` 를 쓴다(화면은 기존 안내 그대로).

    [detail] 을 주면 그 값을 `detail` 로 쓴다 — 다른 429(하루 상한 등)와 구분해야
    하는 경로가 `{code, message}` 를 넘긴다.
    """
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail=detail
        if detail is not None
        else "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.",
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


class PasswordChangeGuard:
    """비밀번호 변경 계정 단위 실패 잠금(#2913, #3087). 회원·트레이너 라우트 공용.

    접근 토큰을 손에 넣은 쪽이 IP 를 바꿔 가며 현재 비밀번호를 맞혀 보지 못하게
    사용자 id 로 센다. 로그인 잠금과 같은 창(`login_lockout_seconds`) 안에
    `password_change_max_failures` 번 틀리면 남은 시간 동안 429 다.
    """

    def __init__(self, user_id: str) -> None:
        settings = get_settings()
        self._key = password_change_fail_key(user_id)
        self._limit = settings.password_change_max_failures
        self._window = float(settings.login_lockout_seconds)

    def ensure_unlocked(self) -> None:
        """잠겼으면 429. 비밀번호 확인보다 먼저 부른다."""
        ensure_unlocked(self._key, self._limit, self._window)

    def record_failure(self) -> None:
        """현재 비밀번호가 틀린 시도 한 번을 센다."""
        record_failure(self._key, self._window)

    def clear(self) -> None:
        """현재 비밀번호가 맞으면 실패 기록을 지운다."""
        clear_failures(self._key)


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
