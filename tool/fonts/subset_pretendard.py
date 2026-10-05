#!/usr/bin/env python3
"""두 앱의 Pretendard 글꼴을 서브셋해 다시 만든다(#3142).

원본 Pretendard(v1.3.9, 굵기당 약 1.57MB)는 한글 11,172자 전체와 다국어 글리프를
담고 있다. 웹은 첫 화면 전에 네 굵기를 모두 받으므로, 앱이 실제로 쓰는 범위만 남긴다.

남기는 글자:
  - 기본 라틴(U+0020~U+007E)과 라틴-1 보충(U+00A0~U+00FF)
  - KS X 1001 의 한자를 뺀 글자 — 기호, 한글 자모, 완성형 한글 2,350자,
    그리스·키릴 문자, 원 숫자 등
  - 일반 문장부호(U+2010~U+205F)
  - `pretendard_extra_chars.txt` 에 적은 글자

글리프 모양·자간(GPOS)·대체(GSUB)·세로 지표는 그대로 두므로 남긴 글자의 모양은
원본과 같다. 범위 밖 글자는 엔진의 대체 글꼴이 그린다. 앱 문구가 범위 안에 있는지는
`tool/ci/check_font_coverage.py` 가 CI 에서 확인한다.

원본은 기본값으로 Pretendard 를 처음 들인 커밋(#995)의 파일을 git 이력에서 꺼내 쓴다.
`--source-dir` 로 Pretendard 배포본의 `public/static` 폴더를 줄 수도 있다. 어느 쪽이든
SHA-256 이 아래 값과 같아야 한다 — 같은 원본에서는 항상 같은 결과가 나온다.

필요: fontTools (`python3 -m pip install fonttools`)

실행: python3 tool/fonts/subset_pretendard.py [--source-dir DIR]
"""

from __future__ import annotations

import argparse
import hashlib
import io
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
EXTRA_CHARS_FILE = HERE / "pretendard_extra_chars.txt"

APP_DIRS = ("frontend/flutter", "frontend/flutter_trainer")
WEIGHTS = ("Regular", "Medium", "SemiBold", "Bold")

# Pretendard 를 처음 들인 커밋(#995). 그때 실은 파일이 서브셋의 원본이다.
SOURCE_COMMIT = "0662c8d61d1f5d18e85822519e317120fafd28b7"
SOURCE_PATH = "frontend/flutter/assets/fonts/Pretendard-{weight}.otf"
SOURCE_SHA256 = {
    "Regular": "3ffbacde6ab8411f1d2db54bb9b1f0b3ee2a738932033722cf0388c06aed1c93",
    "Medium": "d39e50e4bb52b4993b6a4eeb821a171254745bd824446af01e1f616b89fface0",
    "SemiBold": "c89bc43027dc7cde5726e96223376f8eec09302b2fc1f8147fd5b57cfc376118",
    "Bold": "2e91915fab54df71cc9598ebf608b2bdb54c6fe3c066ac61dff0bc44fca71cc7",
}

# KS X 1001 에서 한자(0xCA~0xFD 행)를 뺀 행: 기호·자모·그리스·키릴 등(0xA1~0xAC),
# 완성형 한글(0xB0~0xC8).
KS_X_1001_ROWS = (*range(0xA1, 0xAD), *range(0xB0, 0xC9))


def ks_x_1001_codepoints() -> set[int]:
    codepoints: set[int] = set()
    for lead in KS_X_1001_ROWS:
        for trail in range(0xA1, 0xFF):
            try:
                char = bytes((lead, trail)).decode("euc_kr")
            except UnicodeDecodeError:
                continue
            codepoints.add(ord(char))
    return codepoints


def extra_codepoints(path: Path = EXTRA_CHARS_FILE) -> set[int]:
    codepoints: set[int] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        codepoints |= {ord(c) for c in line if not c.isspace()}
    return codepoints


def subset_codepoints() -> set[int]:
    return (
        set(range(0x20, 0x7F))
        | set(range(0xA0, 0x100))
        | ks_x_1001_codepoints()
        | set(range(0x2010, 0x2060))
        | extra_codepoints()
    )


def load_source(weight: str, source_dir: Path | None) -> bytes:
    if source_dir is not None:
        data = (source_dir / f"Pretendard-{weight}.otf").read_bytes()
    else:
        data = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "show", f"{SOURCE_COMMIT}:{SOURCE_PATH.format(weight=weight)}"],
            check=True,
            capture_output=True,
        ).stdout
    digest = hashlib.sha256(data).hexdigest()
    if digest != SOURCE_SHA256[weight]:
        raise SystemExit(f"Pretendard-{weight}.otf 원본이 다르다: sha256 {digest}")
    return data


def subset_font(data: bytes, codepoints: set[int]) -> bytes:
    from fontTools import subset
    from fontTools.ttLib import TTFont

    options = subset.Options()
    options.layout_features = ["*"]  # 자간·합자·숫자 폭 등 원본 기능을 그대로 둔다.
    options.name_IDs = ["*"]  # 저작권·라이선스 이름표를 남긴다(OFL).
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.glyph_names = False

    # 생성 시각·전체 글리프 경계(head)는 원본 값을 둔다. 같은 원본에서 같은 파일이
    # 나오게 하고, 글꼴 경계로 줄 높이를 잡는 렌더러에서도 원본과 같게 그리기 위해서다.
    font = TTFont(io.BytesIO(data), recalcTimestamp=False, recalcBBoxes=False)
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)
    out = io.BytesIO()
    font.save(out)
    return out.getvalue()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--source-dir",
        type=Path,
        help="원본 Pretendard-*.otf 가 있는 폴더(없으면 git 이력의 원본을 쓴다)",
    )
    args = parser.parse_args(argv)

    codepoints = subset_codepoints()
    for weight in WEIGHTS:
        result = subset_font(load_source(weight, args.source_dir), codepoints)
        for app in APP_DIRS:
            target = REPO_ROOT / app / "assets" / "fonts" / f"Pretendard-{weight}.otf"
            target.write_bytes(result)
        print(f"Pretendard-{weight}.otf: {len(result):,} B (sha256 {hashlib.sha256(result).hexdigest()[:12]})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
