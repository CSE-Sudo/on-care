"""에러 추적(Sentry) — 처리하지 못한 예외를 팀이 알 수 있게 모은다(#2839).

운영에서 500 이 나도 서버 로그에 한 줄 남을 뿐이라, 사용자가 신고하기 전까지 아무도
몰랐다. 여기서 Sentry 로 예외를 보내되 **식단·건강정보가 밖으로 나가지 않게** 다음을
지킨다.

- `SENTRY_DSN` 이 없거나 `ENV=dev` 면 초기화하지 않는다(개발·데모 오류는 보내지 않음).
- `send_default_pii=False`, 요청 본문 수집 끔(`max_request_body_size="never"`), 예외
  프레임의 지역 변수 수집 끔(`include_local_variables=False`).
- 그래도 SDK 가 채우는 요청 정보는 `scrub_event` 가 한 번 더 걷어 낸다 — 메서드와
  쿼리를 뺀 경로만 남기고 헤더(Authorization 포함)·쿠키·쿼리·본문·사용자·extra 를 지운다.
- 로그를 이벤트·브레드크럼으로 옮기지 않는다. 처리하지 못한 예외만 보낸다.
- 모든 이벤트에 요청 id(`X-Request-ID`) 태그를 달아 서버 로그와 잇는다.
"""

from __future__ import annotations

import logging
from typing import Any

import sentry_sdk
from sentry_sdk.integrations.logging import LoggingIntegration

from app.core.config import Settings

logger = logging.getLogger(__name__)

#: 오류를 보내지 않는 환경. 개발·데모 데이터의 오류는 팀 알림만 어지럽힌다.
DISABLED_ENVS = frozenset({"dev"})

#: 요청 정보 중 남기는 키. 나머지(headers·cookies·query_string·data·env)는 지운다.
_KEPT_REQUEST_KEYS = ("method", "url")

#: 바깥 호출 브레드크럼에서 남기는 키. URL 은 쿼리를 떼고 남긴다(키·토큰이 실릴 수 있다).
_KEPT_BREADCRUMB_DATA_KEYS = ("method", "status_code", "url")


def is_enabled(settings: Settings) -> bool:
    """이 설정에서 에러 추적을 켤지 — DSN 이 있고 개발 환경이 아닐 때만."""
    return bool(settings.sentry_dsn.strip()) and settings.env not in DISABLED_ENVS


def _strip_query(url: Any) -> Any:
    if not isinstance(url, str):
        return url
    return url.split("?", 1)[0].split("#", 1)[0]


def _drop_frame_vars(container: Any) -> None:
    if not isinstance(container, dict):
        return
    for value in container.get("values") or []:
        if not isinstance(value, dict):
            continue
        for frame in (value.get("stacktrace") or {}).get("frames") or []:
            if isinstance(frame, dict):
                frame.pop("vars", None)


def scrub_event(
    event: dict[str, Any], hint: dict[str, Any] | None = None
) -> dict[str, Any]:
    """보내기 직전 이벤트에서 개인정보가 될 수 있는 칸을 걷어 낸다."""
    request = event.get("request")
    if isinstance(request, dict):
        kept = {k: request[k] for k in _KEPT_REQUEST_KEYS if k in request}
        if "url" in kept:
            kept["url"] = _strip_query(kept["url"])
        event["request"] = kept
    # 사용자 식별·IP 는 보내지 않는다. 같은 오류의 영향 범위는 요청 id 로 서버 로그에서 본다.
    event.pop("user", None)
    # extra 에는 SDK·라이브러리가 임의 값을 싣는다. 쓰지 않으므로 통째로 뺀다.
    event.pop("extra", None)
    _drop_frame_vars(event.get("exception"))
    _drop_frame_vars(event.get("threads"))
    breadcrumbs = event.get("breadcrumbs")
    if isinstance(breadcrumbs, dict):
        breadcrumbs["values"] = [
            scrubbed
            for crumb in breadcrumbs.get("values") or []
            if (scrubbed := scrub_breadcrumb(crumb)) is not None
        ]
    return event


def scrub_breadcrumb(
    crumb: dict[str, Any] | None, hint: dict[str, Any] | None = None
) -> dict[str, Any] | None:
    """브레드크럼은 종류·메서드·상태·쿼리 뗀 URL 만 남긴다. 메시지는 지운다."""
    if not isinstance(crumb, dict):
        return None
    data = crumb.get("data")
    kept: dict[str, Any] = {}
    if isinstance(data, dict):
        kept = {k: data[k] for k in _KEPT_BREADCRUMB_DATA_KEYS if k in data}
        if "url" in kept:
            kept["url"] = _strip_query(kept["url"])
    crumb["data"] = kept
    crumb.pop("message", None)
    return crumb


def init_error_tracking(settings: Settings, *, transport: Any = None) -> bool:
    """설정이 허락하면 Sentry 를 초기화하고 True 를 돌려준다.

    `transport` 는 테스트가 실제 전송 대신 이벤트를 받아 보려고 넘긴다.
    """
    if not is_enabled(settings):
        logger.info("error tracking disabled (no SENTRY_DSN or env=%s)", settings.env)
        return False
    sentry_sdk.init(
        dsn=settings.sentry_dsn.strip(),
        environment=settings.sentry_environment.strip() or settings.env,
        release=f"oncare-backend@{settings.app_version}",
        sample_rate=settings.sentry_sample_rate,
        # 성능 추적(APM)은 범위 밖 — 트랜잭션을 만들지 않는다.
        traces_sample_rate=None,
        send_default_pii=False,
        max_request_body_size="never",
        include_local_variables=False,
        before_send=scrub_event,
        before_breadcrumb=scrub_breadcrumb,
        # 로그를 이벤트·브레드크럼으로 옮기지 않는다 — 로그 문장에 사용자 입력이 섞일 수 있다.
        integrations=[
            LoggingIntegration(level=None, event_level=None, sentry_logs_level=None)
        ],
        transport=transport,
    )
    logger.info(
        "error tracking enabled (env=%s)", settings.sentry_environment or settings.env
    )
    return True


def tag_request(request_id: str) -> None:
    """현재 요청 범위에 요청 id 태그를 단다. 초기화 전이면 아무 일도 하지 않는다."""
    if not sentry_sdk.get_client().is_active():
        return
    sentry_sdk.set_tag("request_id", request_id)


def capture_unhandled(exc: BaseException, *, request_id: str) -> None:
    """처리하지 못한 예외를 요청 id 와 함께 보낸다. 초기화 전이면 아무 일도 하지 않는다.

    SDK 의 ASGI 통합도 같은 예외를 잡을 수 있지만, 같은 예외 객체는 한 번만 보낸다
    (Dedupe 통합).
    """
    if not sentry_sdk.get_client().is_active():
        return
    with sentry_sdk.new_scope() as scope:
        scope.set_tag("request_id", request_id)
        sentry_sdk.capture_exception(exc)
