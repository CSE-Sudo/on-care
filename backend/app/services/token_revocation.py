"""refresh 토큰 폐기 — 로그아웃과 회전이 세션을 실제로 끊는 자리.

JWT 는 서명만 맞으면 만료까지 유효하다. 서버가 "이 토큰은 끝났다"고 말할 곳이
없으면 로그아웃은 **그 기기의 저장소를 지우는 일**에 그치고, 이미 빠져나간
토큰에는 아무 영향도 없다. 여기서 폐기된 `jti` 를 들고, `/auth/refresh` 가
그것을 확인한다(#966).

토큰 문자열이 아니라 `jti` 만 담는다 — 표가 새어도 그것으로 인증할 수는 없다.

재사용으로 탈취가 의심되면 토큰 한 장이 아니라 그 로그인 세션(`sid`)을 끊는다
(`revoke_session`, #3086). 그래야 탈취한 쪽이 먼저 회전해 받은 토큰도 함께 죽는다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.models import RevokedRefreshToken, RevokedSession

#: 폐기 사유(#3086). 재사용이 왔을 때 판단이 갈린다 — 회전된 토큰은 동시 갱신이거나
#: 탈취이고, 로그아웃·옛 세대 토큰은 이미 끊긴 세션이다.
REASON_ROTATED = "rotated"
REASON_LOGOUT = "logout"
REASON_STALE = "stale"


def is_revoked(db: Session, jti: str) -> bool:
    return (
        db.scalar(
            select(RevokedRefreshToken.jti).where(RevokedRefreshToken.jti == jti)
        )
        is not None
    )


def revoked_entry(db: Session, jti: str) -> RevokedRefreshToken | None:
    """폐기 기록. 사유와 폐기 시각으로 재사용을 판단할 때 쓴다(#3086)."""
    return db.get(RevokedRefreshToken, jti)


def revoke(
    db: Session,
    *,
    jti: str,
    user_id: str,
    expires_at: datetime,
    reason: str | None = None,
) -> bool:
    """`jti` 를 폐기한다. 처음 폐기하면 True, 이미 폐기돼 있었으면 False.

    두 번째 폐기가 실패가 아니라 **False** 인 것은 호출부의 판단이 갈리기 때문이다.
    로그아웃은 이미 끊긴 세션을 다시 끊는 것이라 그냥 성공이지만, 회전에서는 같은
    사건이 **이미 쓴 refresh 토큰이 다시 왔다**는 뜻이라 거부해야 한다.

    같은 토큰으로 동시에 두 요청이 들어오면 둘 다 빈 표를 보고 넣으려 할 수 있다.
    이때 지는 쪽을 유일 키(PK)가 잡아 주므로, 조회 결과가 아니라 **삽입 성공 여부**로
    판정한다.
    """
    if is_revoked(db, jti):
        return False
    db.add(
        RevokedRefreshToken(
            jti=jti, user_id=user_id, expires_at=expires_at, reason=reason
        )
    )
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        return False
    purge_expired(db)
    db.commit()
    return True


def is_session_revoked(db: Session, sid: str) -> bool:
    return (
        db.scalar(select(RevokedSession.sid).where(RevokedSession.sid == sid))
        is not None
    )


def revoke_session(
    db: Session, *, sid: str, user_id: str, expires_at: datetime
) -> bool:
    """로그인 세션 `sid` 를 끊는다. 처음 끊으면 True, 이미 끊겨 있었으면 False.

    `expires_at` 은 세션 절대 수명이 끝나는 시각이다 — 그 뒤로는 세션의 어떤 토큰도
    만료돼 있어 기록을 남길 이유가 없다.
    """
    if is_session_revoked(db, sid):
        return False
    db.add(RevokedSession(sid=sid, user_id=user_id, expires_at=expires_at))
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        return False
    db.commit()
    return True


def handle_reuse(
    db: Session,
    *,
    jti: str,
    user_id: str,
    session_id: str | None,
    session_expires_at: datetime,
    now: datetime | None = None,
) -> str:
    """이미 폐기된 refresh 토큰이 다시 왔을 때 세션을 끊을지 정하고, 감사 로그
    `detail` 로 남길 판단을 돌려준다(#3086).

    - 회전으로 폐기된 지 유예(`refresh_reuse_grace_seconds`) 안: 웹 탭 두 개나 응답을
      받기 전에 앱이 꺼진 경우처럼 정상 사용자도 같은 토큰을 두 번 보낼 수 있다.
      그 요청만 거부하고 세션은 둔다.
    - 유예 밖: 정상 사용자와 탈취자 둘 중 하나가 먼저 회전했다는 뜻이다. 어느 쪽이
      먼저였는지 알 수 없으니 그 세션(`sid`)을 끊어 이어 회전돼 나간 토큰까지 죽인다.
      같은 계정의 다른 로그인은 `sid` 가 달라 그대로다.
    - 로그아웃·옛 세대로 폐기된 토큰: 이미 끊긴 세션이라 더 할 일이 없다.
    """
    entry = revoked_entry(db, jti)
    if entry is None:
        # 같은 토큰의 동시 요청에서 진 쪽 — 이긴 쪽이 아직 커밋 전이다. 동시 갱신이다.
        return "concurrent"
    if entry.reason != REASON_ROTATED:
        return f"already revoked: {entry.reason or 'unknown'}"
    revoked_at = entry.revoked_at
    if revoked_at.tzinfo is None:
        revoked_at = revoked_at.replace(tzinfo=timezone.utc)
    current = now or datetime.now(timezone.utc)
    grace = timedelta(seconds=get_settings().refresh_reuse_grace_seconds)
    if current - revoked_at <= grace:
        return "within grace"
    if session_id is None:
        # 세션 이름이 생기기 전에 발급된 토큰. 끊을 고리가 없다.
        return "no session"
    revoke_session(
        db, sid=session_id, user_id=user_id, expires_at=session_expires_at
    )
    return f"session revoked: {session_id}"


def purge_expired(db: Session, *, now: datetime | None = None) -> int:
    """만료된 폐기 기록을 지우고 지운 수를 돌려준다.

    만료된 토큰은 JWT 검증에서 이미 거부되므로 폐기 여부를 물을 이유가 없다.
    남겨 두면 표가 발급량만큼 무한히 자란다. 폐기가 생길 때마다 함께 도는 정리라
    별도 배치나 스케줄러가 필요 없다.

    커밋하지 않는다 — 폐기와 같은 트랜잭션에서 끝나야 정리만 남고 폐기가 사라지는
    조합이 생기지 않는다.
    """
    cutoff = now or datetime.now(timezone.utc)
    result = db.execute(
        delete(RevokedRefreshToken).where(RevokedRefreshToken.expires_at < cutoff)
    )
    sessions = db.execute(
        delete(RevokedSession).where(RevokedSession.expires_at < cutoff)
    )
    return int(result.rowcount or 0) + int(sessions.rowcount or 0)
