"""API_CONTRACT.md 가 실제 라우터와 어긋나지 않는지 — DB 불필요.

새 엔드포인트를 만들고 계약 문서에 적지 않으면 앱 쪽(목업·실서버 클라이언트)은 그 경로가
있다는 사실을 코드를 읽어야만 안다(#2901). 반대로 지운 경로가 문서 표에 남으면 앱이 없는
주소를 부른다. 여기서 둘을 경로 단위로 맞춘다.

문서의 표 한 줄을 "엔드포인트 명세" 로 본다: 첫 칸에 메서드(GET/POST/PUT/DELETE/PATCH,
백틱 유무 무관), 둘째 칸에 백틱으로 감싼 경로(`/v1` 접두사 없이). 경로의 `?` 뒤 질의는
비교하지 않고, `{member_id}`·`{id}` 같은 경로 변수는 이름과 무관하게 같은 자리로 본다.
"""
from __future__ import annotations

import re
from pathlib import Path

from app.core.config import get_settings
from app.main import app

CONTRACT = Path(__file__).resolve().parents[1] / "API_CONTRACT.md"

_METHODS = ("GET", "POST", "PUT", "DELETE", "PATCH")
_METHOD_RE = re.compile(r"\b(GET|POST|PUT|DELETE|PATCH)\b")
_PATH_RE = re.compile(r"`(/[^`?\s]*)")
_PARAM_RE = re.compile(r"\{[^}]+\}")

# 라우터에 있지만 계약 문서 표에 일부러 두지 않는 경로 — 사유와 함께 적는다.
_UNDOCUMENTED_OK: dict[tuple[str, str], str] = {}


def _normalize(path: str) -> str:
    return _PARAM_RE.sub("{}", path)


def _router_routes() -> set[tuple[str, str]]:
    prefix = get_settings().api_v1_prefix
    routes: set[tuple[str, str]] = set()
    for path, ops in app.openapi()["paths"].items():
        if prefix and path.startswith(prefix):
            path = path[len(prefix):] or "/"
        for method in ops:
            if method.upper() in _METHODS:
                routes.add((method.upper(), _normalize(path)))
    return routes


def _documented_routes() -> set[tuple[str, str]]:
    rows: set[tuple[str, str]] = set()
    for raw in CONTRACT.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 2:
            continue
        methods = _METHOD_RE.findall(cells[0])
        if not methods:
            continue
        for path in _PATH_RE.findall(cells[1]):
            for method in methods:
                rows.add((method, _normalize(path)))
    return rows


def test_router_has_routes():
    """비교 대상이 비어 통과하는 일이 없게 — 라우터 수집이 실제로 경로를 찾는다."""
    routes = _router_routes()
    assert ("GET", "/healthz") in routes
    assert len(routes) > 100


def test_every_route_is_in_contract():
    """라우터의 모든 엔드포인트가 API_CONTRACT.md 표에 한 줄씩 있다."""
    missing = _router_routes() - _documented_routes() - set(_UNDOCUMENTED_OK)
    assert not missing, (
        "API_CONTRACT.md 표에 없는 엔드포인트: "
        + ", ".join(f"{m} {p}" for m, p in sorted(missing, key=lambda r: (r[1], r[0])))
        + " — 해당 절의 표에 `| METHOD | `경로` | 응답 |` 줄을 추가하세요."
    )


def test_contract_has_no_removed_routes():
    """계약 문서 표에 라우터에 없는(지워졌거나 오타 난) 경로가 남지 않는다."""
    extra = _documented_routes() - _router_routes()
    assert not extra, (
        "라우터에 없는 경로가 계약 문서 표에 있다: "
        + ", ".join(f"{m} {p}" for m, p in sorted(extra, key=lambda r: (r[1], r[0])))
    )


def test_undocumented_allowlist_is_not_stale():
    """예외 목록이 낡지 않았다 — 지운 경로나 이미 문서화된 경로가 남지 않는다."""
    routes = _router_routes()
    documented = _documented_routes()
    for key in _UNDOCUMENTED_OK:
        assert key in routes, f"라우터에 없는 예외 항목: {key}"
        assert key not in documented, f"이미 문서화된 예외 항목: {key}"
