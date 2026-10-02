"""앱의 API 라우트 표를 펼쳐 읽는 테스트 도우미. (#2831 · #2832)

FastAPI 0.14x 부터 `include_router` 가 라우트를 앱 목록에 펼쳐 넣지 않고 포함된
라우터 하나(`_IncludedRouter`)로 남긴다. 그래서 `app.routes` 에서 `APIRoute` 만 고르면
`/v1/...` 라우트가 하나도 나오지 않는다 — 라우트 표를 훑는 가드가 빈 표를 보고
조용히 통과하거나 "라우트가 없다" 로 실패한다.

`fastapi.routing.iter_route_contexts` 가 있으면 그것으로 접두사까지 붙은 실제 경로를
펼치고, 없는 예전 버전에서는 `app.routes` 를 그대로 쓴다. 돌려주는 값은 둘 다
`path`·`methods`·`dependant` 를 가진다.
"""
from __future__ import annotations

from typing import Any

from fastapi.routing import APIRoute


def api_routes(app: Any) -> list[Any]:
    """앱의 모든 API 라우트(포함된 라우터 안쪽까지, 접두사가 붙은 경로)."""
    try:
        from fastapi.routing import iter_route_contexts
    except ImportError:  # 라우터를 펼쳐 넣던 예전 FastAPI
        return [r for r in app.routes if isinstance(r, APIRoute)]
    return [
        rc for rc in iter_route_contexts(app.routes) if isinstance(rc.original_route, APIRoute)
    ]
