"""운동 기록 한 건을 저장하는 테스트 도우미. (#2544)

`POST /exercise/sessions` 는 목록(`{"sessions": [...]}`)을 받고 목록을 돌려준다.
대부분의 테스트는 한 건을 넣고 그 한 건을 읽으므로, 여기서 감싸고 풀어 준다 —
테스트마다 `["sessions"][0]` 을 적으면 확인하려는 것이 묻힌다.

실패 응답(4xx)은 그대로 돌려준다. 422 의 `detail` 을 보는 테스트가 있다.
"""
from __future__ import annotations

from typing import Any

EXERCISE_SESSIONS_PATH = "/v1/exercise/sessions"


class _OneSessionResponse:
    """성공 응답을 옛 단건 응답처럼 읽게 한다 — 기록 한 건에 `points` 를 더한 모양."""

    def __init__(self, response: Any) -> None:
        self._response = response
        self.status_code = response.status_code
        self.text = response.text
        self.headers = response.headers

    def json(self) -> Any:
        body = self._response.json()
        if self.status_code >= 300 or not isinstance(body, dict):
            return body
        return {**body["sessions"][0], "points": body["points"]}


def post_exercise(client: Any, json: dict[str, Any], **kwargs: Any) -> Any:
    """운동 기록 [json] 한 건을 목록으로 감싸 저장한다."""
    return _OneSessionResponse(
        client.post(EXERCISE_SESSIONS_PATH, json={"sessions": [json]}, **kwargs)
    )
