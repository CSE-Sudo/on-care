"""업로드 요청 본문 크기 제한 (413).

`/diet/analyze` 는 업로드된 사진을 `await image.read()` 로 메모리에 올린다.
앞단에 리버스 프록시가 없고(App Runner + 앱 컨테이너), App Runner 의 서비스
쿼터에도 요청 본문 크기 제한이 없어서, 이 미들웨어가 없으면 큰 업로드가 그대로
인스턴스 메모리를 차지한다.

라우터가 아니라 ASGI 미들웨어인 이유: FastAPI 엔드포인트가 실행되는 시점에는
Starlette 이 이미 multipart 본문을 파싱해 스풀한 뒤다. 막으려던 적재가 이미
끝난 뒤에 크기를 재는 셈이라, 본문이 앱에 닿기 전에 잘라야 한다.
"""
from __future__ import annotations

import json
import re
from collections.abc import Sequence
from dataclasses import dataclass, field

from starlette.datastructures import Headers
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class _BodyTooLarge(Exception):
    """본문이 상한을 넘겼음을 receive 래퍼가 바깥으로 알리는 신호."""


@dataclass(frozen=True)
class BodyLimitRule:
    """경로 하나(또는 경로 모양 하나)에 거는 본문 상한. (#2832)

    `path` 는 기본이 **접두사**다. `regex=True` 면 정규식 전체 일치로 본다 —
    `/v1/trainer/clients/{member_id}/chat/image` 처럼 가운데에 id 가 들어가는
    경로는 접두사로 지정할 수 없어서다.

    `detail` 은 413 문구다. 비우면 업로드 기본 문구(최대 N MB)를 쓴다.
    """

    path: str
    max_bytes: int
    detail: str | None = None
    regex: bool = False
    _compiled: re.Pattern[str] | None = field(
        default=None, init=False, repr=False, compare=False
    )

    def __post_init__(self) -> None:
        if self.regex:
            object.__setattr__(self, "_compiled", re.compile(self.path))

    def matches(self, path: str) -> bool:
        if self._compiled is not None:
            return self._compiled.fullmatch(path) is not None
        return path.startswith(self.path)


class RequestBodySizeLimitMiddleware:
    """[rules] 의 경로로 가는 본문이 그 규칙의 상한을 넘으면 413 으로 끊는다.

    두 경로를 모두 막는다.

    * `Content-Length` 가 있으면 본문을 한 바이트도 읽기 전에 거절한다.
      정상 클라이언트(앱의 Dio multipart 포함)는 전부 이쪽이다.
    * 헤더가 없거나(chunked) 실제 본문이 헤더보다 큰 경우를 대비해, 읽는 도중
      누적 크기도 센다. 헤더만 믿으면 `Transfer-Encoding: chunked` 로 우회된다.

    누적 카운터는 **앱이 실제로 읽은 바이트**만 센다. 본문을 읽지 않는 엔드포인트로
    Content-Length 없이 큰 본문을 보내면 413 이 나지 않는데, 그 경우엔 애초에
    앱 메모리에 적재되지도 않으므로 막으려던 문제가 아니다.

    전역이 아니라 경로 목록을 받는 이유: 이 상한은 **업로드**를 겨냥한 값이다.
    모든 요청에 걸면 대량 텍스트를 본문으로 받는 JSON 엔드포인트(`/coach-docs`
    의 문서 적재 등)까지 같은 상한에 묶여, 의도치 않게 기능을 자른다. 업로드
    엔드포인트가 늘어나면 `rules` 에 경로를 추가한다 — 파일을 받는 라우트가 이
    표에 없으면 `tests/test_upload_body_limit_guard.py` 가 실패한다.

    경로마다 상한이 다르다(식단 사진·채팅 사진·리포트 PDF·AI 코치 채팅 JSON). 한
    인스턴스가 경로→상한 표(`rules`)를 받아 **처음 맞는 규칙 하나**를 적용한다.
    인스턴스를 여럿 등록하면 CORS 바깥 감싸기 순서를 경로마다 따로 지켜야 해서,
    표 하나로 모았다(#2832). 예전 인자(`max_bytes`·`protected_paths`·`detail`)도
    그대로 받는다 — 접두사 규칙 여러 개로 바꿔 넣는다.
    """

    def __init__(
        self,
        app: ASGIApp,
        *,
        rules: Sequence[BodyLimitRule] = (),
        max_bytes: int | None = None,
        protected_paths: Sequence[str] = (),
        detail: str | None = None,
    ) -> None:
        self.app = app
        legacy: list[BodyLimitRule] = []
        if protected_paths:
            if max_bytes is None:
                raise ValueError("protected_paths 를 주면 max_bytes 도 줘야 한다")
            # 413 문구. 주지 않으면 업로드용 기본 문구(최대 N MB)다. 업로드가 아닌 JSON
            # 경로(AI 코치 채팅, #1549)는 "업로드 용량" 이라고 하면 틀린 말이라 따로 준다.
            legacy = [BodyLimitRule(p, max_bytes, detail) for p in protected_paths]
        self.rules: tuple[BodyLimitRule, ...] = (*rules, *legacy)

    def rule_for(self, path: str) -> BodyLimitRule | None:
        """이 경로에 걸리는 규칙. 없으면 None(상한 없음)."""
        for rule in self.rules:
            if rule.matches(path):
                return rule
        return None

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        rule = self.rule_for(scope.get("path", "")) if scope["type"] == "http" else None
        if rule is None:
            await self.app(scope, receive, send)
            return

        if self._declared_too_large(scope, rule.max_bytes):
            await self._reject(send, rule)
            return

        received = 0
        response_started = False

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > rule.max_bytes:
                    raise _BodyTooLarge
            return message

        async def counting_send(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, counting_send)
        except _BodyTooLarge:
            # 응답이 이미 시작됐다면 상태줄을 다시 쓸 수 없다. 본문을 읽는 중에
            # 터지는 신호라 정상적으로는 여기 오지 않지만, 조용히 삼키면 커넥션이
            # 어중간하게 남으므로 그대로 올려보낸다.
            if response_started:
                raise
            await self._reject(send, rule)

    @staticmethod
    def _declared_too_large(scope: Scope, max_bytes: int) -> bool:
        """`Content-Length` 헤더만으로 상한 초과가 확정되는가."""
        raw = Headers(scope=scope).get("content-length")
        if raw is None:
            return False
        try:
            return int(raw) > max_bytes
        except ValueError:
            # 파싱 불가한 헤더는 신뢰하지 않는다 — 누적 카운터가 잡는다.
            return False

    @staticmethod
    async def _reject(send: Send, rule: BodyLimitRule) -> None:
        """413 을 직접 써 보낸다(앱을 거치지 않으므로 FastAPI 예외 경로가 없다)."""
        # 기존 415 처리와 같은 형태({"detail": ...})로 맞춘다.
        limit_mb = rule.max_bytes / (1024 * 1024)
        detail = rule.detail or f"업로드 용량이 너무 큽니다(최대 {limit_mb:.0f}MB)."
        body = json.dumps(
            {"detail": detail},
            ensure_ascii=False,
        ).encode("utf-8")
        await send(
            {
                "type": "http.response.start",
                "status": 413,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})
