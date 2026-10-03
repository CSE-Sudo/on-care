"""pytest 공통 설정.

- 순수 유닛 테스트(test_config, test_security)는 DB 없이 실행됩니다.
- DB/엔드포인트 테스트는 `client` 픽스처를 쓰며, DB 연결이 안 되면 자동 skip 됩니다
  (로컬은 skip, CI 의 Postgres(pgvector) 서비스에서 실행).
- 테스트는 **개발·데모 DB 가 아니라 전용 DB** 에 씁니다(아래 참고).
"""
from __future__ import annotations

import os

import pytest
from sqlalchemy import create_engine, text

#: 테스트 전용 DB. 예전에는 기본값이 개발 DB 라, 한 번 돌릴 때마다 테스트가 만든
#: 계정이 데모 DB 에 그대로 쌓였다(회원 수천 명·감사 로그 수만 행). 중단된 실행이
#: 남긴 행 때문에 다음 실행이 중복 키로 깨지기도 했다.
#:
#: 최초 1회만 만들어 두면 된다 — 스키마와 데모 시드는 앱 기동(lifespan)이 채운다.
#:
#:     createdb -h 127.0.0.1 -U oncare oncare_test
#:     psql -h 127.0.0.1 -d oncare_test -c 'CREATE EXTENSION IF NOT EXISTS vector'
#:
#: (확장 생성은 superuser 권한이 필요해 `oncare` 로는 안 된다. 한 번 만들어 두면
#: 앱의 `CREATE EXTENSION IF NOT EXISTS` 는 그냥 통과한다.)
DEFAULT_TEST_DATABASE_URL = (
    "postgresql+psycopg://oncare:oncare@localhost:5432/oncare_test"
)

#: 앱 엔진(`app.db.session`)은 설정에서 URL 을 읽고, 설정은 환경변수를 `.env` 보다
#: 먼저 본다. 그래서 **여기서 환경변수를 심어야** 테스트 클라이언트가 만드는 데이터도
#: 전용 DB 로 간다 — 이 파일 안의 상수만 바꾸면 픽스처만 옮겨 가고 앱은 개발 DB 에
#: 계속 쓴다. `setdefault` 라 CI 처럼 이미 지정된 값은 그대로 둔다.
os.environ.setdefault("DATABASE_URL", DEFAULT_TEST_DATABASE_URL)

DATABASE_URL = os.environ["DATABASE_URL"]

#: 테스트는 오프라인 해시 임베더를 쓴다.
#:
#: DB 를 비우고 시작하면서 공공 RAG 문서(8건)가 매 실행 다시 적재된다. 로컬
#: `.env` 에 실제 GEMINI_API_KEY 가 있으면 그 적재가 **네트워크 임베딩 호출**이
#: 되어, 스위트가 느려질 뿐 아니라 외부 서비스에 의존하게 된다. 키가 없는 CI 는
#: 이미 해시로 폴백하므로, 여기서 못 박아 로컬을 CI 와 같은 경로로 만든다
#: (`recognizer` 를 stub 으로 고정하는 것과 같은 이유다).
#:
#: 두 임베더가 `embed_dim` 을 공유해 벡터 차원은 달라지지 않는다.
os.environ.setdefault("EMBEDDER", "hash")

#: 식단 사진 분석 한도(#2827). 데모 회원 한 사람이 스위트 전체에서 수십 번
#: 분석하므로 기본값(분당 10·하루 20)이면 뒤쪽 테스트가 429 로 깨진다. 한도 자체는
#: 그 테스트가 설정을 낮춰 확인한다.
os.environ.setdefault("DIET_ANALYZE_PER_DAY", "100000")
os.environ.setdefault("DIET_ANALYZE_PER_MINUTE", "100000")

#: 테스트는 로컬 개발 환경(`.env.example`)과 같이 데모 폴백을 켠 채 돈다.
#:
#: 설정 기본값은 꺼짐이다(#2821) — 환경변수를 빠뜨린 배포 서버가 로그인 없는 요청을
#: 데모 회원으로 처리하지 않게 하려는 것이다. 토큰 없이 데모 회원 화면을 읽는 기존
#: 테스트는 개발 환경을 전제로 하므로 여기서 켠다. 기본값(꺼짐)의 동작은
#: `test_prod_readiness` 가 설정을 직접 바꿔 확인한다.
os.environ.setdefault("ALLOW_DEMO_FALLBACK", "true")


#: 이 DB 를 비워도 되는가.
#:
#: 로컬은 같은 DB 를 계속 재사용한다. 그래서 고정 id 를 넣는 테스트가 두 번째
#: 실행부터 중복 키로 깨지고, "첫 질문에는 이력이 없다" 처럼 빈 상태를 전제로 한
#: 테스트도 지난 실행이 남긴 행에 걸린다. 매 실행을 CI 와 같은 빈 상태에서
#: 시작하게 만드는 것이 이 판정의 목적이다(#762).
#:
#: **원격 DB 는 어떤 경우에도 건드리지 않는다.** 공유 DB(Neon)를 가리킨 채
#: 스위트를 돌리는 실수가 팀 데이터를 지우는 일로 이어지면 안 된다. 로컬이라도
#: 앱 기본 DB(개발·데모용)면 비우지 않는다 — 그쪽은 사람이 직접 쓰는 DB 다.
def _is_disposable(url: str) -> bool:
    from urllib.parse import urlparse

    parsed = urlparse(url.replace("postgresql+psycopg://", "postgresql://"))
    if parsed.hostname not in {"localhost", "127.0.0.1"}:
        return False
    name = (parsed.path or "").lstrip("/")
    return bool(name) and name != "oncare"


def _reset_database(url: str) -> None:
    """스키마는 두고 행만 비운다.

    `DROP SCHEMA` 가 아니라 `TRUNCATE` 인 이유는 pgvector 확장과 alembic 이력을
    살려 두기 위해서다 — 확장 생성은 superuser 권한이 필요해 지우면 되살릴 수
    없다. 테이블이 아직 없으면(새 DB) 지울 것도 없다.
    """
    engine = create_engine(url)
    try:
        with engine.begin() as conn:
            names = [
                row[0]
                for row in conn.execute(
                    text(
                        "SELECT tablename FROM pg_tables "
                        "WHERE schemaname = 'public' AND tablename <> 'alembic_version'"
                    )
                )
            ]
            if names:
                joined = ", ".join(f'public."{n}"' for n in names)
                conn.execute(text(f"TRUNCATE {joined} RESTART IDENTITY CASCADE"))
    finally:
        engine.dispose()


def _db_available() -> bool:
    try:
        engine = create_engine(DATABASE_URL, pool_pre_ping=True)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        engine.dispose()
        return True
    except Exception:
        return False


@pytest.fixture(scope="session", autouse=True)
def session_clock_pin():
    """테스트 세션 동안 서비스 기준 날짜를 세션 시작일로 고정한다. (#2940)

    `client` 의 시드는 세션 시작 때 한 번 '오늘'을 읽고, 요청은 그때그때 다시
    읽는다. 실행이 KST 자정을 걸치면 둘이 하루 어긋나므로 `clock.now()` 를
    [SessionClockPin.now] 로 바꿔 끼운다 — 시각은 흐르고 날짜만 묶인다.
    `clock.today()`·`today_iso()` 는 모듈의 `now()` 를 거치므로 함께 고정된다.

    autouse 세션 픽스처라 `client` 의 앱 기동(시드)보다 먼저 걸린다. 개별 테스트가
    `monkeypatch.setattr(clock, "now", ...)` 로 넣는 값은 이 위에 덮이고, 그
    테스트가 끝나면 다시 이 고정으로 돌아온다.
    """
    try:
        from app.core import clock
    except Exception:  # noqa: BLE001
        yield None
        return
    from tests.session_clock import SessionClockPin

    pin = SessionClockPin(clock.now)
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(clock, "now", pin.now)
        yield pin


@pytest.fixture(scope="session")
def client():
    """FastAPI TestClient. DB 가 없으면 skip."""
    if not _db_available():
        pytest.skip("DB 연결 불가 — CI(Postgres 서비스)에서 실행됩니다.")
    # 앱 기동(lifespan)이 스키마와 데모 시드를 채우기 **전에** 비운다. 뒤에
    # 비우면 시드까지 날아가 시드를 읽는 테스트가 전부 깨진다.
    if _is_disposable(DATABASE_URL):
        _reset_database(DATABASE_URL)
    from fastapi.testclient import TestClient

    from app.main import app

    with TestClient(app) as c:  # lifespan → init_db (vector extension / create_all / seed)
        yield c


@pytest.fixture(autouse=True)
def _reset_rate_limiter():
    """각 테스트 전 rate limiter 상태 초기화(테스트 간 누적 방지).
    fastapi 미설치 로컬 환경에서는 조용히 건너뛴다(순수 테스트에 무영향)."""
    try:
        from app.core.rate_limit import limiter
        limiter.clear()
    except Exception:  # noqa: BLE001
        pass
    yield


#: 테스트용 인식기 이름. 결과는 개발용 스텁과 같지만 이름이 `stub` 이 아니다.
TEST_RECOGNIZER = "test-vision"


@pytest.fixture(autouse=True)
def _force_stub_recognizer(monkeypatch):
    """테스트는 결정론적 오프라인 인식기를 사용한다.

    로컬 .env 에 실제 GEMINI_API_KEY 가 있으면 팩토리가 gemini 인식기를 골라,
    가짜 테스트 이미지가 실제 Vision API 로 나가 400(Unable to process image)을
    유발한다. CI(키 없음)와 동일 경로로 고정해 테스트를 .env 독립적으로 만든다.

    스텁과 같은 식단을 돌려주되 이름은 `test-vision` 이다. 개발용 스텁(`stub`)
    결과는 포인트·식판 조건에 세지 않으므로(#2812), 이름까지 스텁이면 "실제 인식기로
    저장한 끼니" 를 전제로 한 적립·식판 테스트가 모두 0 이 된다. 스텁 자체의 규칙은
    그 테스트가 `recognizer` 를 `stub` 으로 다시 고정해 확인한다."""
    try:
        from app.core.config import get_settings
        from app.services.recognizer import factory
        from app.services.recognizer.stub import StubFoodRecognizer

        class _TestVisionRecognizer(StubFoodRecognizer):
            name = TEST_RECOGNIZER

        factory._registry()
        monkeypatch.setitem(factory._REGISTRY, TEST_RECOGNIZER, _TestVisionRecognizer)
        factory._build.cache_clear()
        monkeypatch.setattr(get_settings(), "recognizer", TEST_RECOGNIZER)
    except Exception:  # noqa: BLE001, S110
        import warnings
        warnings.warn(
            "recognizer 를 테스트 인식기로 강제하지 못했습니다 — 테스트가 실제 Gemini Vision API 를 호출할 수 있습니다.",
            stacklevel=2,
        )
    yield


@pytest.fixture(autouse=True)
def _pin_session_start_clock(monkeypatch):
    """완료·노쇼의 시작 판정 시각을 오늘 KST 23:59 로 고정한다. (#2760)

    완료·노쇼는 시작 시각이 지나야 열린다. 많은 테스트가 오늘 저녁 시각의 PT 를
    만들어 완료하므로, 실제 시각을 쓰면 CI 가 도는 시간대에 따라 결과가 바뀐다.
    오늘 일정은 모두 시작한 것으로 두고, 시작 전 판정을 보는 테스트는 스스로
    `trainer.schedule._now_kst` 를 다시 고정한다.
    """
    try:
        from app.core import clock
        from app.services.trainer import schedule as trainer_schedule_service
    except Exception:  # noqa: BLE001
        yield
        return
    monkeypatch.setattr(
        trainer_schedule_service,
        "_now_kst",
        lambda: clock.now().replace(hour=23, minute=59, second=0, microsecond=0),
    )
    yield


@pytest.fixture
def db_session(client):
    """시드까지 끝난 DB 세션. client 픽스처가 먼저 init_db(시드)를 돌린다."""
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


#: 테스트가 만드는 회원 계정에 필수 동의를 함께 남길까. (#3088)
#:
#: 회원 데이터·AI API 는 필수 동의가 끝난 계정만 받는다. 기존 테스트 다수가
#: `consents` 없이 가입하거나 `User` 를 DB 에 직접 넣고 토큰을 만드는데, 그 계정은
#: 모두 동의 화면을 거친 회원을 뜻한다. 가입 헬퍼가 100여 파일에 흩어져 있어
#: 하나씩 고치는 대신, 회원 행이 생길 때 지금 버전의 필수 동의를 같은 트랜잭션에
#: 남긴다. 동의하지 않은 계정이 필요한 테스트는 `without_default_consent` 를 쓴다.
_DEFAULT_CONSENT = {"on": True}


def _record_default_consent(mapper, connection, target) -> None:
    if not _DEFAULT_CONSENT["on"]:
        return
    from sqlalchemy.dialects.postgresql import insert

    from app.core import clock
    from app.models.models import UserConsent
    from app.services import signup_consent

    # 아직 읽지 않은 서버 기본값(role)은 회원이다.
    role = target.__dict__.get("role") or "member"
    if role != "member":
        return
    now = clock.now()
    rows = [
        {
            "user_id": target.id,
            "kind": kind,
            "version": signup_consent.CURRENT_VERSIONS[kind],
            "agreed_at": now,
        }
        for kind in sorted(signup_consent.required_for(role))
    ]
    # 가입이 같은 항목을 이어서 남기면 그쪽은 이미 있는 행을 보고 건너뛴다.
    connection.execute(insert(UserConsent.__table__).values(rows).on_conflict_do_nothing())


try:
    from sqlalchemy import event

    from app.models.models import User as _User

    event.listen(_User, "after_insert", _record_default_consent)
except Exception:  # noqa: BLE001, S110 — 앱 의존성 없이 도는 순수 테스트
    pass


@pytest.fixture
def without_default_consent():
    """이 테스트가 만드는 회원 계정에는 동의를 남기지 않는다. (#3088)"""
    _DEFAULT_CONSENT["on"] = False
    try:
        yield
    finally:
        _DEFAULT_CONSENT["on"] = True
