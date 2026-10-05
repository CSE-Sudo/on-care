#!/usr/bin/env python3
"""새로 들어온 Alembic 마이그레이션에서 파괴적 변경을 찾는다(#1552).

운영 컨테이너는 기동할 때 `alembic upgrade head` 를 돌리고, 배포를 되돌려도 스키마는
되돌리지 않는다(backend/docs/DEPLOY.md "마이그레이션 운영 정책"). 그래서 칸·표를 지우거나
데이터를 고치는 마이그레이션은 직전 이미지와 함께 돌 수 있는지, 두 번에 나눠 배포하는지를
병합 전에 사람이 확인해야 한다. 이 검사는 그 확인이 필요한 파일을 골라 PR 을 멈춘다.

찾는 것(`downgrade()` 안은 보지 않는다 — 되돌리기는 원래 지우는 쪽이다):
  - Alembic 연산: drop_table · drop_column · alter_column · drop_constraint · drop_index ·
    rename_table (`op.` 뿐 아니라 `batch_op.` 처럼 같은 이름의 메서드면 모두)
  - NOT NULL 칸 추가: `add_column(…, sa.Column(…, nullable=False))` 에 `server_default` 가
    없거나 `server_default=None`
  - SQLAlchemy core 데이터 변경: `sa.update(t)`·`sa.delete(t)`·`t.update()`·`t.delete()`,
    `query(...).update({...})`
  - 문자열 SQL(op.execute·conn.execute·sa.text 어디든): DELETE FROM · UPDATE … SET(별칭·ONLY
    포함) · TRUNCATE · DROP … · ALTER COLUMN(`COLUMN` 을 뺀 `ALTER TABLE t ALTER c …` 포함) ·
    RENAME · 기본값 없는 `ADD COLUMN … NOT NULL`. `"DROP " + "TABLE t"` 처럼 이어 붙인 문자열,
    `" ".join([...])`·`"...".format()`·`%` 도 합친 값으로 본다(이름 자리는 `{}`).

검토를 마친 PR 은 둘 중 하나로 통과한다.
  - 파일 안 주석 한 줄(사유는 비울 수 없다). 사유가 마이그레이션과 함께 이력에 남는다.
        # destructive-migration: <왜 안전한지 — 예: 옛 칸을 읽지 않는 코드가 #1234 로 먼저 배포됨>
    진짜 주석만 본다 — docstring·문자열 안에 같은 문구가 있어도 승인이 아니다(#3236).
  - PR 라벨 `destructive-migration`. 라벨을 붙인 그 실행에서만 워크플로가 `--label-approved` 를
    넘긴다. PR 전체를 승인하므로 찾은 곳은 경고로만 남긴다. 라벨을 붙인 뒤 커밋이 더해지거나
    다른 라벨이 바뀌어 다시 돌면 `--stale-label` 로 넘겨 승인으로 치지 않는다(#3236).

사용법:
  check_destructive_migrations.py --base <rev>   # <rev>..HEAD 에서 추가·변경된 마이그레이션
  check_destructive_migrations.py <파일 ...>      # 주어진 파일만
  --label-approved                               # 이번 실행이 라벨을 붙인 이벤트 — 경고만 남기고 통과
  --stale-label                                  # 라벨은 있지만 붙인 뒤 다시 돈 실행 — 승인 아님
위반이 있으면 GitHub Actions 주석(`::error file=...,line=...::`)을 찍고 1 로 끝난다.
"""

from __future__ import annotations

import argparse
import ast
import io
import re
import subprocess
import sys
import tokenize
from dataclasses import dataclass
from pathlib import Path

MIGRATIONS_GLOB = "backend/migrations/versions/*.py"

DESTRUCTIVE_OPS = frozenset(
    {
        "drop_table",
        "drop_column",
        "alter_column",
        "drop_constraint",
        "drop_index",
        "rename_table",
    }
)

# PR 승인 라벨. 워크플로가 이 이름을 보고 --label-approved 를 넘긴다.
APPROVAL_LABEL = "destructive-migration"

# 파일 안 승인 주석. 사유가 있어야 한다. 주석 토큰 하나(`#` 부터 줄 끝까지)에 맞춘다.
APPROVAL = re.compile(r"^#[ \t]*destructive-migration[ \t]*:[ \t]*(?P<reason>\S.*)$")

# 문자열 SQL 에서 찾는 형태. f-string·이어 붙인 문자열의 값 자리는 `{}` 로 바꿔 읽는다.
_IDENT = r"[\"\w{}.]+"
# UPDATE 대상: `[ONLY] 표 [[AS] 별칭]`. 별칭 자리에 SET 이 오면 별칭이 아니다.
_UPDATE_TARGET = rf"(?:only\s+)?{_IDENT}(?:\s+(?:as\s+)?(?!set\b){_IDENT})?"
SQL_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("DELETE", re.compile(r"\bdelete\s+from\b", re.IGNORECASE)),
    ("UPDATE", re.compile(rf"\bupdate\s+{_UPDATE_TARGET}\s+set\b", re.IGNORECASE)),
    ("TRUNCATE", re.compile(r"\btruncate\b", re.IGNORECASE)),
    (
        "DROP",
        re.compile(
            r"\bdrop\s+(?:table|column|index|constraint|schema|type|view|materialized|"
            r"extension|sequence|trigger|function|not\s+null)\b",
            re.IGNORECASE,
        ),
    ),
    ("ALTER COLUMN", re.compile(r"\balter\s+column\b", re.IGNORECASE)),
    # Postgres 는 `ALTER TABLE t ALTER c TYPE …` 처럼 COLUMN 을 생략할 수 있다.
    (
        "ALTER COLUMN",
        re.compile(
            rf"\balter\s+table\b[^;]*?\balter\s+(?!column\b|constraint\b){_IDENT}\s+"
            r"(?:set|drop|type|reset|add)\b",
            re.IGNORECASE | re.DOTALL,
        ),
    ),
    ("RENAME", re.compile(r"\brename\s+(?:to|column|constraint)\b", re.IGNORECASE)),
)

# `ALTER TABLE … ADD [COLUMN] [IF NOT EXISTS] c 타입 …` 의 칸 추가. 제약 추가는 칸이 아니다.
_ALTER_TABLE = re.compile(r"\balter\s+table\b", re.IGNORECASE)
_ADD_COLUMN = re.compile(
    r"\badd\s+(?!constraint\b|primary\b|foreign\b|unique\b|check\b|exclude\b)", re.IGNORECASE
)
_NOT_NULL = re.compile(r"\bnot\s+null\b", re.IGNORECASE)
# 기존 행을 채우는 값이 있는 칸. `DEFAULT NULL` 은 채우지 않는다.
_FILLED = re.compile(
    r"\bdefault\s+(?!null\b)|\bgenerated\b|\b(?:small|big)?serial\b", re.IGNORECASE
)

# `sa.update(t)`·`sa.delete(t)` 처럼 sqlalchemy 모듈에서 부르는 데이터 변경.
_CORE_DML = frozenset({"update", "delete"})


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    reason: str


def _string_value(node: ast.AST) -> str | None:
    """문자열 식이면 합친 값을 돌려준다. 값을 알 수 없는 자리는 `{}` 로 둔다."""
    if isinstance(node, ast.Constant):
        return node.value if isinstance(node.value, str) else None
    if isinstance(node, ast.JoinedStr):
        parts = []
        for value in node.values:
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                parts.append(value.value)
            else:
                parts.append("{}")
        return "".join(parts)
    if isinstance(node, ast.BinOp):
        left = _string_value(node.left)
        if isinstance(node.op, ast.Add):
            right = _string_value(node.right)
            if left is None and right is None:
                return None
            return (left if left is not None else "{}") + (right if right is not None else "{}")
        if isinstance(node.op, ast.Mod):
            return left
        return None
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
        receiver = _string_value(node.func.value)
        if receiver is None:
            return None
        if node.func.attr == "format":
            return receiver
        if node.func.attr == "join" and len(node.args) == 1 and isinstance(
            node.args[0], (ast.List, ast.Tuple)
        ):
            items = [_string_value(item) for item in node.args[0].elts]
            return receiver.join(item if item is not None else "{}" for item in items)
    return None


def _docstring_nodes(tree: ast.AST) -> set[int]:
    ids: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            body = node.body
            if (
                body
                and isinstance(body[0], ast.Expr)
                and isinstance(body[0].value, ast.Constant)
                and isinstance(body[0].value.value, str)
            ):
                ids.add(id(body[0].value))
    return ids


def _sqlalchemy_names(tree: ast.AST) -> tuple[set[str], set[str]]:
    """(sqlalchemy 모듈을 가리키는 이름, sqlalchemy 에서 가져온 update·delete 이름)."""
    modules: set[str] = set()
    functions: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "sqlalchemy" or alias.name.startswith("sqlalchemy."):
                    modules.add(alias.asname or alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom) and (node.module or "").startswith("sqlalchemy"):
            for alias in node.names:
                if alias.name in _CORE_DML:
                    functions.add(alias.asname or alias.name)
    return modules, functions


def _missing_server_default(keywords: dict[str, ast.expr]) -> bool:
    value = keywords.get("server_default")
    return value is None or (isinstance(value, ast.Constant) and value.value is None)


def _not_null_without_default(call: ast.Call) -> bool:
    """`add_column(table, sa.Column(..., nullable=False))` 이고 server_default 가 없으면 참."""
    for arg in call.args:
        if not isinstance(arg, ast.Call):
            continue
        func = arg.func
        name = func.attr if isinstance(func, ast.Attribute) else getattr(func, "id", "")
        if name != "Column":
            continue
        keywords = {kw.arg: kw.value for kw in arg.keywords if kw.arg}
        nullable = keywords.get("nullable")
        if (
            isinstance(nullable, ast.Constant)
            and nullable.value is False
            and _missing_server_default(keywords)
        ):
            return True
    return False


def _clause_end(text: str, start: int) -> int:
    """`start` 부터 괄호 밖의 `,`·`;` 또는 닫는 괄호 앞까지."""
    depth = 0
    for i in range(start, len(text)):
        char = text[i]
        if char == "(":
            depth += 1
        elif char == ")":
            if depth == 0:
                return i
            depth -= 1
        elif char in ",;" and depth == 0:
            return i
    return len(text)


def _sql_adds_not_null_without_default(text: str) -> bool:
    table = _ALTER_TABLE.search(text)
    if not table:
        return False
    for match in _ADD_COLUMN.finditer(text, table.end()):
        clause = text[match.end() : _clause_end(text, match.end())]
        if _NOT_NULL.search(clause) and not _FILLED.search(clause):
            return True
    return False


class _Visitor(ast.NodeVisitor):
    def __init__(self, path: str, tree: ast.AST) -> None:
        self.path = path
        self.docstrings = _docstring_nodes(tree)
        self.sa_modules, self.sa_functions = _sqlalchemy_names(tree)
        self.findings: list[Finding] = []
        # 문자열 식 안쪽 조각은 합친 값으로 이미 봤으므로 다시 보지 않는다.
        self._in_string = 0

    def _add(self, node: ast.AST, reason: str) -> None:
        self.findings.append(Finding(self.path, getattr(node, "lineno", 1), reason))

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        if node.name == "downgrade":
            return
        self.generic_visit(node)

    def _core_dml(self, node: ast.Call) -> str | None:
        func = node.func
        if isinstance(func, ast.Name) and func.id in self.sa_functions:
            return func.id
        if not isinstance(func, ast.Attribute) or func.attr not in _CORE_DML:
            return None
        if isinstance(func.value, ast.Name) and func.value.id in self.sa_modules:
            return func.attr
        if func.attr == "delete":
            # 표·쿼리·세션의 delete. 사전·집합에는 delete 메서드가 없다.
            return func.attr
        # `t.update()` 는 인자가 없고, `query(...).update({...})` 는 호출 사슬 위에서 부른다.
        # 이름 하나에 인자를 넘기는 `values.update({...})` 는 사전 갱신이라 보지 않는다.
        if (not node.args and not node.keywords) or isinstance(func.value, ast.Call):
            return func.attr
        return None

    def visit_Call(self, node: ast.Call) -> None:
        func = node.func
        if isinstance(func, ast.Attribute):
            if func.attr in DESTRUCTIVE_OPS:
                self._add(node, f"`{func.attr}`")
            elif func.attr == "add_column" and _not_null_without_default(node):
                self._add(node, "기본값 없는 NOT NULL 칸 추가(`add_column` · `nullable=False`)")
        dml = self._core_dml(node)
        if dml:
            self._add(node, f"SQLAlchemy `{dml}()`")
        if self._string_expr(node):
            return
        saved, self._in_string = self._in_string, 0
        try:
            self.generic_visit(node)
        finally:
            self._in_string = saved

    def _check_sql(self, node: ast.AST, text: str) -> None:
        for label, pattern in SQL_PATTERNS:
            if pattern.search(text):
                self._add(node, f"SQL `{label}`")
                return
        if _sql_adds_not_null_without_default(text):
            self._add(node, "기본값 없는 NOT NULL 칸 추가(SQL `ADD COLUMN … NOT NULL`)")

    def _string_expr(self, node: ast.AST) -> bool:
        """문자열 식이면 합친 값으로 한 번만 보고 참을 돌려준다."""
        text = _string_value(node)
        if text is None:
            return False
        if not self._in_string and id(node) not in self.docstrings:
            self._check_sql(node, text)
        self._in_string += 1
        try:
            self.generic_visit(node)
        finally:
            self._in_string -= 1
        return True

    def visit_Constant(self, node: ast.Constant) -> None:
        self._string_expr(node)

    def visit_JoinedStr(self, node: ast.JoinedStr) -> None:
        # 조각 단위가 아니라 합친 문자열로 본다(`UPDATE "{t}" SET` 처럼 이름이 값 자리일 때).
        if not self._string_expr(node):
            self.generic_visit(node)

    def visit_BinOp(self, node: ast.BinOp) -> None:
        # `"DROP " + "TABLE t"`·`"... %s" % t` 도 합친 값으로 본다.
        if not self._string_expr(node):
            self.generic_visit(node)


def approval_reason(source: str) -> str | None:
    """파일의 진짜 주석에서 승인 사유를 찾는다. docstring·문자열 안 문구는 보지 않는다."""
    try:
        for token in tokenize.generate_tokens(io.StringIO(source).readline):
            if token.type != tokenize.COMMENT:
                continue
            match = APPROVAL.match(token.string)
            if match:
                return match.group("reason").strip()
    except (tokenize.TokenError, SyntaxError):
        return None
    return None


def scan_source(path: str, source: str) -> list[Finding]:
    tree = ast.parse(source, filename=path)
    visitor = _Visitor(path, tree)
    visitor.visit(tree)
    return visitor.findings


def changed_migrations(base: str) -> list[str]:
    """base..HEAD 에서 추가(A)·변경(M)·이름 바뀜(R)된 마이그레이션 파일."""
    out = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=AMR", f"{base}...HEAD", "--", MIGRATIONS_GLOB],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [line for line in out.splitlines() if line.strip()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", help="이 커밋 이후 추가·변경된 마이그레이션만 본다")
    labels = parser.add_mutually_exclusive_group()
    labels.add_argument(
        "--label-approved",
        action="store_true",
        help=f"이번 실행이 PR 에 `{APPROVAL_LABEL}` 라벨을 붙인 이벤트다 — 경고만 남기고 통과",
    )
    labels.add_argument(
        "--stale-label",
        action="store_true",
        help=f"`{APPROVAL_LABEL}` 라벨은 있지만 붙인 뒤 다시 돈 실행이다 — 승인으로 치지 않는다",
    )
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args(argv)

    paths = list(args.paths)
    if args.base:
        paths += changed_migrations(args.base)
    if not paths:
        print("새로 추가·변경된 마이그레이션이 없습니다.")
        return 0

    blocked = 0
    for path in paths:
        source = Path(path).read_text(encoding="utf-8")
        findings = scan_source(path, source)
        if not findings:
            print(f"OK   {path}")
            continue
        reason = approval_reason(source)
        if reason:
            print(f"승인 {path} — {len(findings)}곳, 사유: {reason}")
            continue
        if args.label_approved:
            print(f"승인 {path} — {len(findings)}곳, PR 라벨 `{APPROVAL_LABEL}`")
            for finding in findings:
                print(
                    f"::warning file={finding.path},line={finding.line}::파괴적 마이그레이션 "
                    f"{finding.reason} — PR 라벨 `{APPROVAL_LABEL}` 로 승인됨."
                )
            continue
        blocked += 1
        print(f"막음 {path} — 파괴적 변경 {len(findings)}곳")
        for finding in findings:
            print(
                f"::error file={finding.path},line={finding.line}::파괴적 마이그레이션 "
                f"{finding.reason}. 두 번에 나눠 배포하는지 확인하고 파일에 "
                f"`# destructive-migration: <사유>` 주석을 두거나 PR 에 `{APPROVAL_LABEL}` 라벨을 "
                f"붙이세요(backend/docs/DEPLOY.md)."
            )

    if blocked:
        if args.stale_label:
            print(
                f"::error::PR 에 `{APPROVAL_LABEL}` 라벨이 있지만 이번 실행은 라벨을 붙인 때가 아닙니다"
                "(그 뒤 커밋이 더해졌거나 다른 라벨이 바뀜). 라벨은 붙인 순간의 PR 내용만 승인합니다. "
                "지금 내용을 다시 검토했으면 라벨을 뗐다가 다시 붙이거나, 파일에 승인 주석을 두세요."
            )
        print(
            f"\n승인되지 않은 파괴적 마이그레이션 {blocked}개. "
            "backend/docs/DEPLOY.md \"마이그레이션 운영 정책\"을 보세요."
        )
        return 1
    return 0


if __name__ == "__main__":
    # Windows 콘솔(cp949)처럼 `—` 를 못 찍는 출력에서도 판정 결과까지 가게 한다.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="replace")
    sys.exit(main())
