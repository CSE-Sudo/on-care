"""DB 접속 주소 점검 — Neon 풀러 엔드포인트 거부(#3146).

Neon 은 같은 DB 에 직접 엔드포인트(`ep-xxx.<region>.aws.neon.tech`)와 풀러 엔드포인트
(`ep-xxx-pooler.<region>.aws.neon.tech`) 두 주소를 준다. 풀러는 PgBouncer **트랜잭션
모드**라 세션 단위 기능을 쓸 수 없다.

- 기동 마이그레이션은 세션 advisory lock 으로 태스크를 직렬화한다(`scripts/migrate.py`).
  트랜잭션 모드에서는 잠금이 다른 클라이언트와 섞인 연결에 걸려 아무것도 지키지 못한다.
- 공개 문서 재적재도 전용 연결의 세션 잠금을 쓴다(`app/db/init_db.py`).
- 모든 연결에 시작 옵션 `options=-c statement_timeout=…` 을 붙이는데(`app/db/session.py`),
  풀러는 이 옵션을 받지 않아 연결 자체가 거절된다.

설정 검증(`Settings._guard_prod_secrets`)·기동 점검(`startup_checks`)·마이그레이션 러너
(`scripts/migrate.py`)가 같은 판정을 쓴다. 마이그레이션 러너는 앱 설정을 읽기 전에
도는 별도 프로세스라, 이 모듈은 표준 라이브러리만 쓴다.
"""
from __future__ import annotations

from urllib.parse import urlsplit

#: 풀러 엔드포인트 호스트 표식. Neon 은 엔드포인트 id 뒤에 이 접미사를 붙인다.
POOLER_HOST_MARKER = "-pooler"


def database_host(url: str) -> str:
    """접속 주소의 호스트(소문자). 읽을 수 없으면 빈 문자열.

    `postgres://`·`postgresql://`·`postgresql+psycopg://` 를 모두 받는다. 비밀번호가 든
    주소 전체는 어디에도 남기지 않고 호스트만 돌려준다.
    """
    try:
        return (urlsplit((url or "").strip()).hostname or "").lower()
    except ValueError:
        return ""


def is_pooler_host(host: str) -> bool:
    """Neon 풀러 엔드포인트 호스트인가. 첫 DNS 이름 조각에 `-pooler` 가 붙은 경우다."""
    first_label = (host or "").lower().split(".", 1)[0]
    return first_label.endswith(POOLER_HOST_MARKER)


def direct_host(host: str) -> str:
    """풀러 호스트에 대응하는 직접 엔드포인트 호스트(첫 조각의 `-pooler` 를 뗀다)."""
    first, dot, rest = host.partition(".")
    if first.endswith(POOLER_HOST_MARKER):
        first = first[: -len(POOLER_HOST_MARKER)]
    return first + dot + rest


def pooler_problem(url: str) -> str | None:
    """접속 주소가 풀러 엔드포인트면 고칠 방법을 담은 문구, 아니면 None."""
    host = database_host(url)
    if not host or not is_pooler_host(host):
        return None
    return (
        f"DATABASE_URL 이 Neon 풀러 엔드포인트({host})를 가리킵니다 — 트랜잭션 풀링이라 "
        "마이그레이션 잠금이 동작하지 않고 연결 시작 옵션(statement_timeout)이 거절됩니다. "
        f"직접 엔드포인트({direct_host(host)})로 바꾸십시오."
    )
