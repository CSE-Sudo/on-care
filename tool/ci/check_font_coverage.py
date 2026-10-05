#!/usr/bin/env python3
"""서브셋한 Pretendard 가 앱 문구의 글자를 모두 담고 있는지 확인한다(#3142).

두 앱은 Pretendard 를 KS X 1001 한글·라틴·기호 위주로 줄여 싣는다
(`tool/fonts/subset_pretendard.py`). 줄인 글꼴에 없는 글자는 엔진의 대체 글꼴로
그려지므로 화면이 깨지지는 않지만, 같은 문장 안에서 한 글자만 모양이 달라진다.
그래서 앱이 직접 내보내는 글자 — ARB 문구, 백엔드 시드·데모 데이터, 화면 코드의
문자열 — 가 두 앱의 네 굵기 글꼴 cmap 에 모두 있는지 본다.

원본 Pretendard 에도 없는 글자(그림 이모지 등)는 원래부터 대체 글꼴이 그리므로
`tool/fonts/pretendard_fallback_chars.txt` 에 적어 검사에서 뺀다.

빠진 글자가 나오면:
  1. 원본 Pretendard 에 있는 글자면 `tool/fonts/pretendard_extra_chars.txt` 에 넣고
     `tool/fonts/subset_pretendard.py` 로 글꼴을 다시 만든다.
  2. 원본에도 없는 글자면 `tool/fonts/pretendard_fallback_chars.txt` 에 넣는다.

글꼴 파일은 fontTools 없이 sfnt `cmap` 표(형식 4·12)를 직접 읽는다 — CI 에
추가 패키지를 깔지 않기 위해서다.

실행: python3 tool/ci/check_font_coverage.py
"""

from __future__ import annotations

import struct
import sys
import unicodedata
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
FONT_TOOL_DIR = REPO_ROOT / "tool" / "fonts"
FALLBACK_FILE = FONT_TOOL_DIR / "pretendard_fallback_chars.txt"

APP_DIRS = ("frontend/flutter", "frontend/flutter_trainer")
WEIGHTS = ("Regular", "Medium", "SemiBold", "Bold")

# 앱이 화면에 내보내는 글자의 출처. 경로는 저장소 루트 기준 glob 이다.
SOURCE_GLOBS = (
    "frontend/flutter/lib/l10n/*.arb",
    "frontend/flutter_trainer/lib/l10n/*.arb",
    "frontend/flutter/lib/**/*.dart",
    "frontend/flutter_trainer/lib/**/*.dart",
    "shared/*/lib/**/*.dart",
    "shared/demo_fixture/assets/*.json",
    "backend/app/db/seed_*.py",
    "backend/app/db/demo_fixture_data.json",
    "backend/app/data/*_seed.py",
)

# 자동 생성 l10n 코드는 ARB 와 같은 글자라 다시 읽지 않는다.
SKIP_PARTS = ("/gen/",)


def font_paths(repo_root: Path = REPO_ROOT) -> list[Path]:
    return [
        repo_root / app / "assets" / "fonts" / f"Pretendard-{weight}.otf"
        for app in APP_DIRS
        for weight in WEIGHTS
    ]


def read_cmap(path: Path) -> set[int]:
    """sfnt 글꼴의 유니코드 cmap(형식 4·12)에서 코드포인트 집합을 읽는다."""
    data = path.read_bytes()
    num_tables = struct.unpack_from(">H", data, 4)[0]
    cmap_offset = None
    for i in range(num_tables):
        tag, _checksum, offset, _length = struct.unpack_from(">4sIII", data, 12 + 16 * i)
        if tag == b"cmap":
            cmap_offset = offset
            break
    if cmap_offset is None:
        raise ValueError(f"{path}: cmap 표가 없다")

    num_subtables = struct.unpack_from(">H", data, cmap_offset + 2)[0]
    codepoints: set[int] = set()
    for i in range(num_subtables):
        platform_id, encoding_id, sub_offset = struct.unpack_from(
            ">HHI", data, cmap_offset + 4 + 8 * i
        )
        # 유니코드 서브테이블만 본다: (0, *) 또는 (3, 1)/(3, 10).
        if not (platform_id == 0 or (platform_id == 3 and encoding_id in (1, 10))):
            continue
        start = cmap_offset + sub_offset
        fmt = struct.unpack_from(">H", data, start)[0]
        if fmt == 4:
            codepoints |= _read_format4(data, start)
        elif fmt == 12:
            codepoints |= _read_format12(data, start)
    return codepoints


def _read_format4(data: bytes, start: int) -> set[int]:
    seg_count = struct.unpack_from(">H", data, start + 6)[0] // 2
    ends_at = start + 14
    starts_at = ends_at + 2 * seg_count + 2
    deltas_at = starts_at + 2 * seg_count
    range_offsets_at = deltas_at + 2 * seg_count
    result: set[int] = set()
    for seg in range(seg_count):
        end = struct.unpack_from(">H", data, ends_at + 2 * seg)[0]
        first = struct.unpack_from(">H", data, starts_at + 2 * seg)[0]
        delta = struct.unpack_from(">h", data, deltas_at + 2 * seg)[0]
        range_offset_pos = range_offsets_at + 2 * seg
        range_offset = struct.unpack_from(">H", data, range_offset_pos)[0]
        for code in range(first, end + 1):
            if code == 0xFFFF:
                continue
            if range_offset == 0:
                glyph = (code + delta) & 0xFFFF
            else:
                glyph_pos = range_offset_pos + range_offset + 2 * (code - first)
                glyph = struct.unpack_from(">H", data, glyph_pos)[0]
                if glyph != 0:
                    glyph = (glyph + delta) & 0xFFFF
            if glyph != 0:
                result.add(code)
    return result


def _read_format12(data: bytes, start: int) -> set[int]:
    num_groups = struct.unpack_from(">I", data, start + 12)[0]
    result: set[int] = set()
    for group in range(num_groups):
        first, last, start_glyph = struct.unpack_from(">III", data, start + 16 + 12 * group)
        for offset, code in enumerate(range(first, last + 1)):
            if start_glyph + offset != 0:
                result.add(code)
    return result


def read_char_list(path: Path) -> set[str]:
    """글자 목록 파일을 읽는다. `#` 로 시작하는 줄은 설명이고, 공백은 무시한다."""
    chars: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        chars |= {c for c in line if not c.isspace()}
    return chars


def source_files(repo_root: Path = REPO_ROOT) -> list[Path]:
    files: set[Path] = set()
    for pattern in SOURCE_GLOBS:
        for path in repo_root.glob(pattern):
            posix = path.as_posix()
            if path.is_file() and not any(part in posix for part in SKIP_PARTS):
                files.add(path)
    return sorted(files)


def needs_glyph(char: str) -> bool:
    """글꼴에 모양이 있어야 하는 글자인가. 공백·제어·서식 문자는 뺀다."""
    if char.isspace():
        return False
    return unicodedata.category(char) not in ("Cc", "Cf", "Cs", "Co", "Cn", "Mn", "Zl", "Zp")


def used_chars(files: list[Path]) -> dict[str, Path]:
    """앱이 쓰는 글자와, 그 글자가 처음 나온 파일."""
    found: dict[str, Path] = {}
    for path in files:
        for char in path.read_text(encoding="utf-8"):
            if ord(char) < 0x80 or char in found or not needs_glyph(char):
                continue
            found[char] = path
    # ASCII 는 글자 수가 적어 전부 확인한다.
    for code in range(0x21, 0x7F):
        found.setdefault(chr(code), files[0] if files else Path("."))
    return found


def missing_chars(
    fonts: list[Path], chars: dict[str, Path], fallback: set[str]
) -> dict[Path, list[str]]:
    report: dict[Path, list[str]] = {}
    for font in fonts:
        cmap = read_cmap(font)
        missing = sorted(c for c in chars if c not in fallback and ord(c) not in cmap)
        if missing:
            report[font] = missing
    return report


def main(argv: list[str] | None = None) -> int:
    del argv
    fonts = font_paths()
    absent = [f for f in fonts if not f.is_file()]
    if absent:
        for font in absent:
            print(f"::error::글꼴 파일이 없다: {font.relative_to(REPO_ROOT)}")
        return 1

    chars = used_chars(source_files())
    fallback = read_char_list(FALLBACK_FILE)
    report = missing_chars(fonts, chars, fallback)
    if not report:
        print(f"Pretendard 서브셋이 앱 글자 {len(chars)}종을 모두 담고 있다 ({len(fonts)}개 글꼴).")
        return 0

    for font, missing in report.items():
        rel = font.relative_to(REPO_ROOT)
        print(f"::error file={rel}::서브셋 글꼴에 없는 글자 {len(missing)}종")
        for char in missing:
            origin = chars[char].relative_to(REPO_ROOT)
            print(f"  U+{ord(char):04X} {char!r} ({origin})")
    print(
        "원본 Pretendard 에 있는 글자면 tool/fonts/pretendard_extra_chars.txt 에 넣고 "
        "tool/fonts/subset_pretendard.py 로 다시 만든다. 원본에도 없는 글자(이모지 등)면 "
        "tool/fonts/pretendard_fallback_chars.txt 에 넣는다."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
