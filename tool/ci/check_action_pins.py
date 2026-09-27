#!/usr/bin/env python3
"""워크플로의 외부 action 이 40자 커밋 SHA 로 고정됐는지 검사한다(#2340).

태그(`@v4`)나 브랜치(`@main`)는 가리키는 커밋이 나중에 바뀔 수 있어, 검토하지 않은
코드가 CI 에서 돌 수 있다(#1554). 그래서 `uses:` 는 `owner/repo@<40자 SHA> # vX.Y.Z`
형식만 허용한다.

예외:
  - 로컬 action(`./...`) — 이 저장소 안의 코드라 PR 에서 함께 검토된다.
  - `docker://` 참조 — 커밋 SHA 가 아니라 이미지 참조라 이 검사의 대상이 아니다.
재사용 워크플로(`owner/repo/.github/workflows/x.yml@ref`)도 외부 코드이므로 SHA 를 요구한다.

YAML 파서 의존성 없이 줄 단위로 읽는다. 러너에 PyYAML 이 없어도 돌게 하고, 위반
위치를 원래 줄 번호로 정확히 짚기 위해서다.

사용법:
  check_action_pins.py [경로 ...]
경로를 주지 않으면 `.github/workflows` 아래 *.yml / *.yaml 을 모두 본다. 디렉터리를
주면 그 안의 *.yml / *.yaml 을, 파일을 주면 그 파일만 본다.
위반이 있으면 GitHub Actions 주석(`::error file=...,line=...::`)을 찍고 1 로 끝난다.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

DEFAULT_DIR = Path(".github/workflows")

# `uses:` 키가 있는 줄. 스텝 첫 키(`- uses:`)와 이어지는 키(`uses:`) 둘 다 잡는다.
USES_LINE = re.compile(r"^\s*(?:-\s+)?uses\s*:(?P<value>.*)$")
# 외부 참조: owner/repo[/경로]@ref. ref 가 정확히 40자 16진수여야 통과.
PINNED = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[^@\s]+)?@[0-9a-f]{40}$")


def parse_value(raw: str) -> str:
    """`uses:` 뒤의 값에서 따옴표와 줄 끝 주석을 걷어 낸다."""
    value = raw.strip()
    if value[:1] in ("'", '"'):
        quote = value[0]
        end = value.find(quote, 1)
        return value[1:end] if end != -1 else value[1:]
    # YAML 에서 주석은 공백 뒤의 `#` 부터다(`a#b` 는 값의 일부).
    return re.split(r"\s+#", value, maxsplit=1)[0].strip()


def check_reference(ref: str) -> str | None:
    """위반이면 이유를, 통과면 None 을 돌려준다."""
    if not ref:
        return "`uses:` 값이 비어 있습니다"
    if ref.startswith("./"):
        return None
    if ref.startswith("docker://"):
        return None
    if "${{" in ref:
        return f"`{ref}` — 식(expression)으로 만든 참조는 고정 여부를 확인할 수 없습니다"
    if "@" not in ref:
        return f"`{ref}` — ref 가 없습니다. `@<40자 커밋 SHA>` 로 고정하세요"
    if PINNED.match(ref):
        return None
    pinned_to = ref.rsplit("@", 1)[1]
    return (
        f"`{ref}` — `@{pinned_to}` 는 40자 커밋 SHA 가 아닙니다. "
        "`@<40자 커밋 SHA> # <버전>` 형식으로 고정하세요"
    )


def check_file(path: Path) -> list[tuple[int, str]]:
    """(줄 번호, 이유) 목록을 돌려준다."""
    problems: list[tuple[int, str]] = []
    text = path.read_text(encoding="utf-8")
    for number, line in enumerate(text.splitlines(), start=1):
        if line.lstrip().startswith("#"):
            continue
        match = USES_LINE.match(line)
        if not match:
            continue
        reason = check_reference(parse_value(match.group("value")))
        if reason:
            problems.append((number, reason))
    return problems


def collect(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(sorted([*path.glob("*.yml"), *path.glob("*.yaml")]))
        elif path.is_file():
            files.append(path)
        else:
            raise FileNotFoundError(path)
    return files


def main(argv: list[str]) -> int:
    targets = [Path(arg) for arg in argv] or [DEFAULT_DIR]
    try:
        files = collect(targets)
    except FileNotFoundError as missing:
        print(f"::error::검사할 경로가 없습니다: {missing}")
        return 2
    if not files:
        # 검사 대상이 하나도 없으면 통과로 치지 않는다 — 경로가 바뀌어 검사가
        # 조용히 아무것도 안 보게 되는 상황을 막는다.
        print(f"::error::검사할 워크플로 파일이 없습니다: {' '.join(map(str, targets))}")
        return 2

    violations = 0
    checked = 0
    for path in files:
        for number, reason in check_file(path):
            print(f"::error file={path},line={number}::{reason}")
            violations += 1
        checked += 1

    if violations:
        print(f"SHA 로 고정되지 않은 action 참조 {violations}건 (워크플로 {checked}개 검사).")
        return 1
    print(f"모든 외부 action 이 커밋 SHA 로 고정되어 있습니다 (워크플로 {checked}개 검사).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
