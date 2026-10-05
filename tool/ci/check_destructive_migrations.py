#!/usr/bin/env python3
"""새로 들어온 Alembic 마이그레이션에서 파괴적 변경을 찾는다(#1552).

운영 컨테이너는 기동할 때 `alembic upgrade head` 를 돌리고, 배포를 되돌려도 스키마는
되돌리지 않는다(backend/docs/DEPLOY.md "마이그레이션 운영 정책"). 그래서 칸·표를 지우거나
데이터를 고치는 마이그레이션은 직전 이미지와 함께 돌 수 있는지, 두 번에 나눠 배포하는지를
병합 전에 사람이 확인해야 한다. 이 검사는 그 확인이 필요한 파일을 골라 PR 을 멈춘다.

찾는 것(`downgrade()` 안은 보지 않는다 — 되돌리기는 원래 지우는 쪽이다):
  - Alembic 연산: drop_table · drop_column · alter_column · drop_constraint · drop_index ·
    rename_table (`op.` 뿐 아니라 `batch_op.` 처럼 같은 이름의 메서드면 모두)
  - NOT NULL 칸 추가: `add_column(…, sa.Column(…, nullable=False))` 에 `server_default` 가 없음
  - 문자열 SQL(op.execute·conn.execute·sa.text 어디든): DELETE FROM · UPDATE … SET ·
    TRUNCATE · DROP … · ALTER COLUMN · RENAME

검토를 마친 PR 은 둘 중 하나로 통과한다.
  - 파일 안 주석 한 줄(사유는 비울 수 없다). 사유가 마이그레이션과 함께 이력에 남는다.
        # destructive-migration: <왜 안전한지 — 예: 옛 칸을 읽지 않는 코드가 #1234 로 먼저 배포됨>
  - PR 라벨 `destructive-migration`. 워크플로가 라벨을 보고 `--label-approved` 를 넘긴다.
    PR 전체를 승인하므로 찾은 곳은 경고로만 남긴다.

사용법:
  check_destructive_migrations.py --base <rev>   # <rev>..HEAD 에서 추가·변경된 마이그레이션
  check_destructive_migrations.py <파일 ...>      # 주어진 파일만
  --label-approved                               # PR 라벨로 승인됨 — 경고만 남기고 통과
위반이 있으면 GitHub Actions 주석(`::error file=...,line=...::`)을 찍고 1 로 끝난다.
"""

from __future__ import annotations

import argparse
import ast
import re
import subprocess
import sys
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

# 파일 안 승인 주석. 사유가 있어야 한다.
# `\s` 는 줄바꿈까지 넘어가 다음 줄을 사유로 읽으므로 줄 안의 공백만 허용한다.
APPROVAL = re.compile(
    r"^[ \t]*#[ \t]*destructive-migration[ \t]*:[ \t]*(?P<reason>\S.*)$", re.MULTILINE
)

# 문자열 SQL 에서 찾는 형태. f-string 의 값 자리는 `{}` 로 바꿔 읽는다.
_IDENT = r"[\"\w{}.]+"
SQL_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("DELETE", re.compile(r"\bdelete\s+from\b", re.IGNORECASE)),
    ("UPDATE", re.compile(rf"\bupdate\s+{_IDENT}\s+set\b", re.IGNORECASE)),
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
    ("RENAME", re.compile(r"\brename\s+(?:to|column|constraint)\b", re.IGNORECASE)),
)


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    reason: str


def _string_value(node: ast.AST) -> str | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        parts = []
        for value in node.values:
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                parts.append(value.value)
            else:
                parts.append("{}")
        return "".join(parts)
    return None


def _docstring_nodes(tree: ast.AST) -> set[int]:
    ids: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            body = node.body
            if body and isinstance(body[0], ast.Expr) and _string_value(body[0].value) is not None:
                ids.add(id(body[0].value))
    return ids


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
            and "server_default" not in keywords
        ):
            return True
    return False


class _Visitor(ast.NodeVisitor):
    def __init__(self, path: str, docstrings: set[int]) -> None:
        self.path = path
        self.docstrings = docstrings
        self.findings: list[Finding] = []

    def _add(self, node: ast.AST, reason: str) -> None:
        self.findings.append(Finding(self.path, getattr(node, "lineno", 1), reason))

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        if node.name == "downgrade":
            return
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        func = node.func
        if isinstance(func, ast.Attribute):
            if func.attr in DESTRUCTIVE_OPS:
                self._add(node, f"`{func.attr}`")
            elif func.attr == "add_column" and _not_null_without_default(node):
                self._add(node, "기본값 없는 NOT NULL 칸 추가(`add_column` · `nullable=False`)")
        self.generic_visit(node)

    def _check_sql(self, node: ast.AST) -> None:
        if id(node) in self.docstrings:
            return
        text = _string_value(node)
        if text is None:
            return
        for label, pattern in SQL_PATTERNS:
            if pattern.search(text):
                self._add(node, f"SQL `{label}`")
                return

    def visit_Constant(self, node: ast.Constant) -> None:
        self._check_sql(node)

    def visit_JoinedStr(self, node: ast.JoinedStr) -> None:
        # 조각 단위가 아니라 합친 문자열로 본다(`UPDATE "{t}" SET` 처럼 이름이 값 자리일 때).
        self._check_sql(node)


def approval_reason(source: str) -> str | None:
    match = APPROVAL.search(source)
    return match.group("reason").strip() if match else None


def scan_source(path: str, source: str) -> list[Finding]:
    tree = ast.parse(source, filename=path)
    visitor = _Visitor(path, _docstring_nodes(tree))
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
    parser.add_argument(
        "--label-approved",
        action="store_true",
        help=f"PR 에 `{APPROVAL_LABEL}` 라벨이 있다 — 경고만 남기고 통과",
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
        print(
            f"\n승인되지 않은 파괴적 마이그레이션 {blocked}개. "
            "backend/docs/DEPLOY.md \"마이그레이션 운영 정책\"을 보세요."
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
