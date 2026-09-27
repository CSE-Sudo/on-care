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
from collections.abc import Sequence

from starlette.datastructures import Headers
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class _BodyTooLarge(Exception):
    """본문이 상한을 넘겼음을 receive 래퍼가 바깥으로 알리는 신호."""


class RequestBodySizeLimitMiddleware:
    """[protected_paths] 로 가는 본문이 [max_bytes] 를 넘으면 413 으로 끊는다.

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
    엔드포인트가 늘어나면 여기에 경로를 추가한다. 상한이 다른 경로(AI 코치 채팅처럼
    작은 JSON 본문, #1549)는 인스턴스를 따로 등록한다.
    """

    def __init__(
        self,
        app: ASGIApp,
        *,
        max_bytes: int,
        protected_paths: Sequence[str],
        detail: str | None = None,
    ) -> None:
        self.app = app
        self.max_bytes = max_bytes
        self.protected_paths = tuple(protected_paths)
        # 413 문구. 주지 않으면 업로드용 기본 문구(최대 N MB)다. 업로드가 아닌 JSON
        # 경로(AI 코치 채팅, #1549)는 "업로드 용량" 이라고 하면 틀린 말이라 따로 준다.
        self.detail = detail

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or not self._is_protected(scope):
            await self.app(scope, receive, send)
            return

        if self._declared_too_large(scope):
            await self._reject(send)
            return

        received = 0
        response_started = False

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
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
            await self._reject(send)

    def _is_protected(self, scope: Scope) -> bool:
        """이 요청이 상한을 적용할 업로드 경로로 가는가."""
        path = scope.get("path", "")
        return any(path.startswith(p) for p in self.protected_paths)

    def _declared_too_large(self, scope: Scope) -> bool:
        """`Content-Length` 헤더만으로 상한 초과가 확정되는가."""
        raw = Headers(scope=scope).get("content-length")
        if raw is None:
            return False
        try:
            return int(raw) > self.max_bytes
        except ValueError:
            # 파싱 불가한 헤더는 신뢰하지 않는다 — 누적 카운터가 잡는다.
            return False

    async def _reject(self, send: Send) -> None:
        """413 을 직접 써 보낸다(앱을 거치지 않으므로 FastAPI 예외 경로가 없다)."""
        # 기존 415 처리와 같은 형태({"detail": ...})로 맞춘다.
        limit_mb = self.max_bytes / (1024 * 1024)
        detail = self.detail or f"업로드 용량이 너무 큽니다(최대 {limit_mb:.0f}MB)."
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
