"""`async def` 안에서 동기 DB 세션을 직접 쓰지 않는다 — 정적 가드. (#2835)

FastAPI 는 `def` 라우트를 스레드풀로 보내지만 `async def` 안의 동기 호출은 이벤트
루프에서 그대로 돈다. 동기 SQLAlchemy 세션 조회·커밋이 루프에서 돌면 그동안 같은
프로세스의 다른 모든 요청(헬스체크 포함)이 멈춘다.

규칙: `app/` 의 `async def` 본문에서 세션(`db`)을 쓰는 호출은 다음 중 하나여야 한다.

- `await run_in_threadpool(fn, db, ...)` / `await asyncio.to_thread(fn, db, ...)`
- `await other_async(db, ...)` — 넘겨받은 쪽도 이 가드가 검사한다.

`db.scalar(...)` 처럼 세션 메서드를 직접 부르거나 동기 함수에 `db` 를 넘기면 실패한다.
DB 없이 도는 순수 테스트다.
"""
from __future__ import annotations

import ast
from pathlib import Path

import pytest

_APP = Path(__file__).resolve().parents[1] / "app"
_SESSION_NAMES = frozenset({"db", "session"})
_OFFLOADERS = frozenset({"run_in_threadpool", "to_thread"})


def _name_of(func: ast.expr) -> str:
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return ""


def _uses_session(call: ast.Call) -> bool:
    func = call.func
    if isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name):
        if func.value.id in _SESSION_NAMES:
            return True
    args = [*call.args, *(k.value for k in call.keywords)]
    return any(isinstance(a, ast.Name) and a.id in _SESSION_NAMES for a in args)


class _Finder(ast.NodeVisitor):
    def __init__(self) -> None:
        self.violations: list[ast.Call] = []

    def visit_FunctionDef(self, node):  # 중첩 동기 함수는 따로 불린다 — 건너뛴다.
        return

    def visit_AsyncFunctionDef(self, node):
        return

    def visit_Lambda(self, node):
        return

    def visit_Await(self, node: ast.Await):
        value = node.value
        if isinstance(value, ast.Call):
            # 기다리는 호출 자체는 허용. 스레드로 넘기는 호출이면 인자 전체가 허용이다.
            if _name_of(value.func) in _OFFLOADERS:
                return
            self.visit(value.func)
            for a in [*value.args, *(k.value for k in value.keywords)]:
                self.visit(a)
            return
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call):
        if _name_of(node.func) in _OFFLOADERS:
            return
        if _uses_session(node):
            self.violations.append(node)
        self.generic_visit(node)


def violations_in(source: str, filename: str = "<src>") -> list[str]:
    tree = ast.parse(source, filename)
    out: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.AsyncFunctionDef):
            continue
        finder = _Finder()
        for stmt in node.body:
            finder.visit(stmt)
        out.extend(
            f"{filename}:{call.lineno} {node.name}: {ast.unparse(call)[:80]}"
            for call in finder.violations
        )
    return out


def _app_sources() -> list[Path]:
    return sorted(p for p in _APP.rglob("*.py") if "__pycache__" not in p.parts)


def test_no_async_function_in_app_touches_the_sync_session_on_the_loop():
    found: list[str] = []
    for path in _app_sources():
        found.extend(violations_in(path.read_text(encoding="utf-8"), str(path.relative_to(_APP))))
    assert found == [], "async def 안의 동기 DB 호출:\n" + "\n".join(found)


# ---------- 가드 자체 ----------


@pytest.mark.parametrize(
    "body",
    [
        "x = db.scalar(q)",
        "db.commit()",
        "audit(db, event='x')",
        "helper(session=db)",
        "return service.save(db, 1)",
        "if flag:\n        db.rollback()",
    ],
)
def test_guard_flags_sync_session_use(body):
    src = f"async def route(db):\n    {body}\n"
    assert len(violations_in(src)) == 1


@pytest.mark.parametrize(
    "body",
    [
        "x = await run_in_threadpool(helper, db, 1)",
        "await run_in_threadpool(audit, db, event='x')",
        "x = await asyncio.to_thread(helper, db)",
        "x = await other_async(db, 1)",
        "data = await image.read()",
        "x = helper(1, 2)",
    ],
)
def test_guard_allows_offloaded_or_awaited_session_use(body):
    src = f"async def route(db):\n    {body}\n"
    assert violations_in(src) == []


def test_guard_ignores_sync_functions_and_nested_helpers():
    src = (
        "def route(db):\n    db.commit()\n\n"
        "async def outer(db):\n"
        "    def inner():\n        db.commit()\n"
        "    return await run_in_threadpool(inner)\n"
    )
    assert violations_in(src) == []
