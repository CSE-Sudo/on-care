"""AI 코치 생성 실패 폴백의 구조화 로그 (#1559).

생성 단계가 모든 예외를 `except Exception: pass` 로 삼켜, provider 장애·인증
오류·timeout·응답 계약 문제가 전부 정상 폴백으로만 보였다.

여기서 보는 것:

* 폴백마다 사유(`fallback_reason`)·provider·model·오류 유형·HTTP 상태·user_id 가
  레코드 필드와 메시지 양쪽에 남는다.
* 예상한 바깥 실패(설정·provider·빈 응답)는 WARNING, 우리 코드의 오류는 ERROR +
  스택으로 나뉜다.
* 예외 메시지·프롬프트·건강정보·질문·키는 로그에 남지 않는다.
* 요청 상관관계 — 실제 요청의 `X-Request-ID` 가 레코드에 붙는다.
* 로그를 남겨도 응답은 예전처럼 규칙 기반 폴백이다. 성공하면 폴백 로그가 없다.
"""
from __future__ import annotations

import logging
import uuid
from collections.abc import Iterator

import pytest
from sqlalchemy import text

from app.core.config import get_settings
from app.core.observability import RequestIdLogFilter
from app.models.models import HealthProfile, User
from app.services.coach import chat as coach_chat

LOGGER = "app.services.coach.chat"

#: 로그에 절대 나오면 안 되는 값들 — 프롬프트·건강정보·질문·키.
SECRET_MESSAGE = "무릎 수술 뒤 재활 중인데 스쿼트 해도 되나요 1559"
SECRET_CONDITION = "당뇨전단계-1559-민감"
SECRET_KEY = "sk-live-1559-DO-NOT-LOG"


class _ProviderFailure(Exception):
    """SDK 예외처럼 상태 코드와 요청 내용을 실은 오류."""

    def __init__(self, message: str, *, status_code: int | None = None, code=None):
        super().__init__(message)
        if status_code is not None:
            self.status_code = status_code
        if code is not None:
            self.code = code


class _StubLLM:
    name = "stub-provider"
    model_name = "stub-model-7"

    def __init__(self, *, reply: str | None = "좋아요.", error: Exception | None = None):
        self.reply = reply
        self.error = error
        self.prompts: list[str] = []

    def generate(self, system_prompt: str, user_prompt: str):
        self.prompts.append(user_prompt)
        if self.error is not None:
            raise self.error
        reply = self.reply

        class _R:
            text = reply

        return _R()


@pytest.fixture(autouse=True)
def _no_retrieve(monkeypatch):
    """검색은 비워 둔다 — 여기서 보는 것은 생성 단계다."""
    monkeypatch.setattr(
        coach_chat, "retrieve", lambda *a, **k: {"personal": [], "public": []}
    )


@pytest.fixture
def member(db_session) -> Iterator[User]:
    """민감한 프로필을 가진 회원 — 프롬프트에 실리는 값이 로그로 새는지 본다."""
    user = User(
        id=f"fallback-log-{uuid.uuid4().hex[:10]}",
        email=f"fallback-log-{uuid.uuid4().hex[:8]}@example.com",
        name="폴백 로그",
        hashed_password="unused",
        role="member",
    )
    db_session.add(user)
    db_session.flush()
    db_session.add(
        HealthProfile(user_id=user.id, conditions=SECRET_CONDITION)
    )
    db_session.commit()
    yield user
    db_session.rollback()
    db_session.execute(text("DELETE FROM users WHERE id = :id"), {"id": user.id})
    db_session.commit()


def _use(monkeypatch, llm) -> None:
    monkeypatch.setattr(coach_chat, "get_coach_llm", lambda *a, **k: llm)


def _fallback_records(caplog) -> list[logging.LogRecord]:
    return [
        r for r in caplog.records
        if r.name == LOGGER and getattr(r, "event", None) == coach_chat.FALLBACK_EVENT
    ]


def _assert_no_sensitive(caplog, *extra: str) -> None:
    rendered = caplog.text + "".join(
        str(getattr(r, "__dict__", {})) for r in caplog.records
    )
    for secret in (SECRET_MESSAGE, SECRET_CONDITION, SECRET_KEY, *extra):
        assert secret not in rendered, secret


def _ask(db_session, user: User, message: str = SECRET_MESSAGE):
    return coach_chat.answer(db_session, user.id, message, [])


# ---- 사유별 필드·레벨 ----


def test_provider_failure_logs_structured_fields(caplog, db_session, member, monkeypatch):
    llm = _StubLLM(error=_ProviderFailure("upstream timeout", status_code=504))
    _use(monkeypatch, llm)

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        reply, _, generated = _ask(db_session, member)

    assert generated is False
    assert reply.strip()  # 폴백 답은 그대로 나간다
    [record] = _fallback_records(caplog)
    assert record.levelno == logging.WARNING
    assert record.fallback_reason == coach_chat.FALLBACK_PROVIDER_ERROR
    assert record.llm_provider == "stub-provider"
    assert record.llm_model == "stub-model-7"
    assert record.error_type.endswith("._ProviderFailure")
    assert record.http_status == 504
    assert record.user_id == member.id
    # 사람이 읽는 메시지에도 같은 값이 있다(필드를 모르는 수집기에서도 보인다).
    message = record.getMessage()
    assert "reason=provider_error" in message
    assert "provider=stub-provider" in message
    assert "model=stub-model-7" in message
    assert "http_status=504" in message
    assert f"user_id={member.id}" in message
    # 예상한 바깥 실패라 스택은 붙이지 않는다.
    assert record.exc_info is None


def test_provider_failure_does_not_log_the_exception_message_or_prompt(
    caplog, db_session, member, monkeypatch
):
    """SDK 가 오류 메시지에 요청 본문·키를 되풀이해도 로그로 새지 않는다."""
    leaky = _ProviderFailure(
        f"400 bad request: prompt={SECRET_MESSAGE} profile={SECRET_CONDITION} "
        f"key={SECRET_KEY}",
        status_code=400,
    )
    llm = _StubLLM(error=leaky)
    _use(monkeypatch, llm)

    with caplog.at_level(logging.DEBUG, logger=LOGGER):
        _ask(db_session, member)

    # 프롬프트에는 실제로 건강정보가 실렸다 — 그래서 로그에 없다는 확인이 의미가 있다.
    assert SECRET_CONDITION in llm.prompts[0]
    assert _fallback_records(caplog)
    _assert_no_sensitive(caplog, "400 bad request", llm.prompts[0])


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (_ProviderFailure("auth", status_code=401), 401),
        (_ProviderFailure("quota", status_code=429), 429),
        (_ProviderFailure("grpc style", code=403), 403),
        (_ProviderFailure("no status"), None),
        (_ProviderFailure("string code", code="RESOURCE_EXHAUSTED"), None),
        (TimeoutError("read timed out"), None),
    ],
)
def test_http_status_is_taken_only_from_integer_codes(
    caplog, db_session, member, monkeypatch, error, expected
):
    _use(monkeypatch, _StubLLM(error=error))

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        _ask(db_session, member)

    [record] = _fallback_records(caplog)
    assert record.http_status == expected
    assert record.fallback_reason == coach_chat.FALLBACK_PROVIDER_ERROR


def test_timeout_error_type_is_fully_qualified(caplog, db_session, member, monkeypatch):
    _use(monkeypatch, _StubLLM(error=TimeoutError("slow")))

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        _ask(db_session, member)

    [record] = _fallback_records(caplog)
    assert record.error_type == "builtins.TimeoutError"


def test_unconfigured_llm_logs_the_configured_provider_and_model(
    caplog, db_session, member, monkeypatch
):
    """키가 없어 LLM 을 못 만들면 설정 문제로 따로 센다."""
    def _no_key(*a, **k):
        raise RuntimeError(f"GEMINI_API_KEY 가 설정되지 않았습니다. {SECRET_KEY}")

    monkeypatch.setattr(coach_chat, "get_coach_llm", _no_key)
    settings = get_settings()
    monkeypatch.setattr(settings, "coach_llm", "gemini")

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        _, _, generated = _ask(db_session, member)

    assert generated is False
    [record] = _fallback_records(caplog)
    assert record.levelno == logging.WARNING
    assert record.fallback_reason == coach_chat.FALLBACK_LLM_UNAVAILABLE
    assert record.llm_provider == "gemini"
    assert record.llm_model == settings.gemini_model
    assert record.error_type == "builtins.RuntimeError"
    assert record.exc_info is None
    _assert_no_sensitive(caplog, "GEMINI_API_KEY")


def test_unknown_provider_setting_is_logged_with_placeholder_model(
    caplog, db_session, member, monkeypatch
):
    def _unknown(*a, **k):
        raise ValueError("알 수 없는 코치 LLM")

    monkeypatch.setattr(coach_chat, "get_coach_llm", _unknown)
    monkeypatch.setattr(get_settings(), "coach_llm", "Mystery")

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        _ask(db_session, member)

    [record] = _fallback_records(caplog)
    assert record.fallback_reason == coach_chat.FALLBACK_LLM_UNAVAILABLE
    assert record.llm_provider == "mystery"
    assert record.llm_model == "-"
    assert record.error_type == "builtins.ValueError"


@pytest.mark.parametrize("reply", ["", "   \n", None])
def test_empty_reply_is_its_own_reason(caplog, db_session, member, monkeypatch, reply):
    _use(monkeypatch, _StubLLM(reply=reply))

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        _, _, generated = _ask(db_session, member)

    assert generated is False
    [record] = _fallback_records(caplog)
    assert record.fallback_reason == coach_chat.FALLBACK_EMPTY_REPLY
    assert record.error_type == "-"
    assert record.http_status is None
    assert record.levelno == logging.WARNING


def test_malformed_response_counts_as_provider_error(
    caplog, db_session, member, monkeypatch
):
    """`.text` 가 문자열이 아닌 응답은 provider 응답 계약 위반이다."""
    class _Weird:
        name = "stub-provider"
        model_name = "stub-model-7"

        def generate(self, system_prompt, user_prompt):
            class _R:
                text = 12345

            return _R()

    _use(monkeypatch, _Weird())

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        _, _, generated = _ask(db_session, member)

    assert generated is False
    [record] = _fallback_records(caplog)
    assert record.fallback_reason == coach_chat.FALLBACK_PROVIDER_ERROR
    assert record.error_type == "builtins.AttributeError"


def test_internal_error_is_logged_as_error_with_stack(
    caplog, db_session, member, monkeypatch
):
    """우리 코드의 오류는 고쳐야 할 버그다 — ERROR 와 스택으로 가른다."""
    llm = _StubLLM()
    _use(monkeypatch, llm)

    def _broken(db, user_id):
        raise KeyError("profile_field")

    monkeypatch.setattr(coach_chat, "_profile_context", _broken)

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        reply, _, generated = _ask(db_session, member)

    assert generated is False
    assert reply.strip()
    assert llm.prompts == []  # provider 는 부르지 않았다
    [record] = _fallback_records(caplog)
    assert record.levelno == logging.ERROR
    assert record.fallback_reason == coach_chat.FALLBACK_INTERNAL_ERROR
    assert record.error_type == "builtins.KeyError"
    assert record.exc_info is not None
    assert record.llm_provider == "stub-provider"
    _assert_no_sensitive(caplog)


def test_provider_and_internal_failures_use_different_levels(
    caplog, db_session, member, monkeypatch
):
    _use(monkeypatch, _StubLLM(error=_ProviderFailure("x", status_code=500)))
    with caplog.at_level(logging.WARNING, logger=LOGGER):
        _ask(db_session, member)
    provider_level = _fallback_records(caplog)[-1].levelno

    caplog.clear()
    monkeypatch.setattr(
        coach_chat, "_insight_context",
        lambda *a, **k: (_ for _ in ()).throw(RuntimeError("bug")),
    )
    with caplog.at_level(logging.WARNING, logger=LOGGER):
        _ask(db_session, member)
    internal_level = _fallback_records(caplog)[-1].levelno

    assert provider_level == logging.WARNING
    assert internal_level == logging.ERROR


def test_success_leaves_no_fallback_log(caplog, db_session, member, monkeypatch):
    _use(monkeypatch, _StubLLM(reply="오늘은 가볍게 걸어요."))

    with caplog.at_level(logging.DEBUG, logger=LOGGER):
        reply, _, generated = _ask(db_session, member)

    assert generated is True
    assert reply == "오늘은 가볍게 걸어요."
    assert _fallback_records(caplog) == []


def test_real_llm_classes_expose_their_model_name():
    """구현이 들고 있는 모델 id 가 로그의 model 로 나간다."""
    from app.services.coach.llm import GeminiCoachLLM

    llm = GeminiCoachLLM.__new__(GeminiCoachLLM)
    llm._model = "gemini-flash-latest"
    assert llm.model_name == "gemini-flash-latest"

    bare = GeminiCoachLLM.__new__(GeminiCoachLLM)
    assert bare.model_name == ""


# ---- 요청 상관관계 ----


class _Capture(logging.Handler):
    """운영 핸들러처럼 request_id 필터를 단 핸들러."""

    def __init__(self) -> None:
        super().__init__(level=logging.WARNING)
        self.addFilter(RequestIdLogFilter())
        self.records: list[logging.LogRecord] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.records.append(record)


def test_request_id_is_attached_on_the_member_chat_path(client, db_session, monkeypatch):
    from app.core.security import create_access_token

    user = User(
        id=f"fallback-rid-{uuid.uuid4().hex[:10]}",
        email=f"fallback-rid-{uuid.uuid4().hex[:8]}@example.com",
        name="상관관계", hashed_password="unused", role="member",
    )
    db_session.add(user)
    db_session.commit()
    user_id = user.id
    _use(monkeypatch, _StubLLM(error=_ProviderFailure("down", status_code=503)))
    handler = _Capture()
    logging.getLogger(LOGGER).addHandler(handler)
    request_id = "rid1559abcdef"
    try:
        r = client.post(
            "/v1/ai-coach/chat",
            json={"message": SECRET_MESSAGE},
            headers={
                "Authorization": f"Bearer {create_access_token(user_id)}",
                "X-Request-ID": request_id,
            },
        )
    finally:
        logging.getLogger(LOGGER).removeHandler(handler)
        db_session.rollback()
        db_session.execute(text("DELETE FROM users WHERE id = :id"), {"id": user_id})
        db_session.commit()

    assert r.status_code == 200, r.text
    assert r.headers["X-Request-ID"] == request_id
    records = [r for r in handler.records if getattr(r, "event", None) == coach_chat.FALLBACK_EVENT]
    assert len(records) == 1
    assert records[0].request_id == request_id
    assert records[0].user_id == user_id
    assert SECRET_MESSAGE not in records[0].getMessage()


def test_trainer_path_logs_the_member_scope(client, monkeypatch, caplog):
    """트레이너 고객 AI 코치도 같은 폴백 로그를 남긴다(검색 스코프 = 회원)."""
    _use(monkeypatch, _StubLLM(error=_ProviderFailure("down", status_code=502)))
    token = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/trainer/clients", headers=headers).json()[0]["id"]

    with caplog.at_level(logging.WARNING, logger=LOGGER):
        r = client.post(
            f"/v1/trainer/clients/{member_id}/ai-coach",
            headers=headers,
            json={"message": SECRET_MESSAGE},
        )

    assert r.status_code == 200, r.text
    [record] = _fallback_records(caplog)
    assert record.user_id == member_id
    assert record.http_status == 502
    _assert_no_sensitive(caplog)
