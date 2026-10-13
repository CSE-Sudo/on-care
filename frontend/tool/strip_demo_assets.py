#!/usr/bin/env python3
"""운영 빌드에서 데모 전용 자산 선언을 뺀다(#3157).

두 앱의 pubspec.yaml 은 데모 전용 자산(데모 시드 끼니 사진·데모 대화 첨부 PDF)을
`# >>> demo-assets` 와 `# <<< demo-assets` 표시 사이에 선언한다. 데모(Pages)·개발·
테스트는 그대로 싣고, 운영 빌드만 `flutter build` 직전에 이 스크립트로 그 구간을
지운다. 선언이 빠지면 Flutter 가 자산을 번들에 넣지 않는다.

    python3 frontend/tool/strip_demo_assets.py frontend/flutter
    python3 frontend/tool/strip_demo_assets.py frontend/flutter_trainer

이미 지운 pubspec 에 다시 돌려도 그대로 둔다. 표시 밖에 `assets/demo` 선언이 남아
있으면 실패한다 — 그 자산은 운영 번들에 실리기 때문이다.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

BEGIN = "# >>> demo-assets"
END = "# <<< demo-assets"
DEMO_DIR = "assets/demo"


class StripError(Exception):
    pass


def strip(text: str) -> tuple[str, int]:
    """표시 구간을 지운 pubspec 본문과 지운 구간 수를 돌려준다."""
    out: list[str] = []
    removed = 0
    inside = False
    for number, line in enumerate(text.splitlines(keepends=True), start=1):
        marker = line.strip()
        if marker.startswith(BEGIN):
            if inside:
                raise StripError(f"{number}행: '{BEGIN}' 가 닫히기 전에 다시 열렸다")
            inside = True
            continue
        if marker.startswith(END):
            if not inside:
                raise StripError(f"{number}행: 열지 않은 '{END}'")
            inside = False
            removed += 1
            continue
        if not inside:
            out.append(line)
    if inside:
        raise StripError(f"'{BEGIN}' 가 닫히지 않았다")
    stripped = "".join(out)
    for number, line in enumerate(stripped.splitlines(), start=1):
        body = line.split("#", 1)[0]
        if DEMO_DIR in body:
            raise StripError(
                f"표시 밖에 데모 자산 선언이 남았다(지운 뒤 {number}행): {line.strip()}"
            )
    return stripped, removed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("app_dir", type=Path, help="pubspec.yaml 이 있는 앱 폴더")
    args = parser.parse_args(argv)
    pubspec = args.app_dir / "pubspec.yaml"
    try:
        text = pubspec.read_text(encoding="utf-8")
        stripped, removed = strip(text)
    except (OSError, StripError) as error:
        print(f"::error file={pubspec}::{error}")
        return 1
    if stripped != text:
        pubspec.write_text(stripped, encoding="utf-8")
    print(f"{pubspec}: 데모 자산 구간 {removed}곳을 뺐다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
