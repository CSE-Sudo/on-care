"""check_font_coverage.py 와 서브셋 Pretendard 의 테스트(#3142).

서브셋 글꼴에서 앱 문구의 글자가 빠지면 그 글자만 대체 글꼴로 그려져 모양이 달라진다.
검사 스크립트가 실제 저장소에서 통과하는지와 함께, 검사 자체가 빠진 글자를 제대로
잡는지, 글꼴이 서브셋 범위를 지키는지를 고정해 둔다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import io
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_font_coverage as coverage  # noqa: E402

REPO_ROOT = coverage.REPO_ROOT
EXTRA_FILE = REPO_ROOT / "tool" / "fonts" / "pretendard_extra_chars.txt"

# 서브셋 전 원본은 굵기당 약 1.57MB 였다. 원본이 다시 들어오면 여기서 걸린다.
MAX_FONT_BYTES = 600_000


def ks_x_1001_hangul() -> list[str]:
    syllables = []
    for lead in range(0xB0, 0xC9):
        for trail in range(0xA1, 0xFF):
            syllables.append(bytes((lead, trail)).decode("euc_kr"))
    return syllables


class RepositoryCoverageTest(unittest.TestCase):
    def test_repository_passes(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            code = coverage.main([])
        self.assertEqual(code, 0, out.getvalue())

    def test_sources_include_both_apps_arb_and_seed(self) -> None:
        files = {p.relative_to(REPO_ROOT).as_posix() for p in coverage.source_files()}
        for expected in (
            "frontend/flutter/lib/l10n/app_ko.arb",
            "frontend/flutter/lib/l10n/app_en.arb",
            "frontend/flutter_trainer/lib/l10n/app_ko.arb",
            "frontend/flutter_trainer/lib/l10n/app_en.arb",
            "backend/app/db/demo_fixture_data.json",
        ):
            self.assertIn(expected, files)
        self.assertTrue(any(f.startswith("backend/app/db/seed_") for f in files))
        self.assertFalse(any("/gen/" in f for f in files))


class SubsetFontTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fonts = coverage.font_paths()
        cls.cmaps = {font: coverage.read_cmap(font) for font in cls.fonts}

    def test_all_weights_exist_in_both_apps(self) -> None:
        self.assertEqual(len(self.fonts), 8)
        for font in self.fonts:
            self.assertTrue(font.is_file(), font)

    def test_both_apps_ship_identical_files(self) -> None:
        member, trainer = self.fonts[:4], self.fonts[4:]
        for a, b in zip(member, trainer):
            self.assertEqual(a.name, b.name)
            self.assertEqual(a.read_bytes(), b.read_bytes(), a.name)

    def test_fonts_are_subset_sized(self) -> None:
        for font in self.fonts:
            self.assertLess(font.stat().st_size, MAX_FONT_BYTES, font.name)

    def test_ks_x_1001_hangul_fully_covered(self) -> None:
        syllables = ks_x_1001_hangul()
        self.assertEqual(len(syllables), 2350)
        for font, cmap in self.cmaps.items():
            missing = [s for s in syllables if ord(s) not in cmap]
            self.assertEqual(missing, [], font.name)

    def test_ascii_and_common_symbols_covered(self) -> None:
        for font, cmap in self.cmaps.items():
            for code in range(0x20, 0x7F):
                self.assertIn(code, cmap, f"{font.name} U+{code:04X}")
            for char in "·×–—“”…→↑①₩°±「」":
                self.assertIn(ord(char), cmap, f"{font.name} {char}")

    def test_outside_range_is_dropped(self) -> None:
        # '똠'·'햏' 은 KS X 1001 완성형 밖, '漢' 은 한자라 서브셋에서 빠진다.
        for font, cmap in self.cmaps.items():
            for char in "똠햏漢":
                self.assertNotIn(ord(char), cmap, f"{font.name} {char}")

    def test_extra_chars_are_in_font(self) -> None:
        extras = coverage.read_char_list(EXTRA_FILE)
        self.assertIn("₩", extras)
        for font, cmap in self.cmaps.items():
            missing = sorted(c for c in extras if ord(c) not in cmap)
            self.assertEqual(missing, [], f"{font.name}: subset_pretendard.py 를 다시 돌린다")

    def test_fallback_chars_are_not_in_font(self) -> None:
        # 대체 글꼴 목록은 '원본에도 없는 글자' 다. 글꼴에 있는 글자가 들어 있으면
        # 검사가 그 글자를 놓치게 되므로 막는다.
        fallback = coverage.read_char_list(coverage.FALLBACK_FILE)
        self.assertIn("🙂", fallback)
        for font, cmap in self.cmaps.items():
            present = sorted(c for c in fallback if ord(c) in cmap)
            self.assertEqual(present, [], font.name)

    def test_ofl_notice_kept_in_both_apps(self) -> None:
        notices = [
            REPO_ROOT / app / "assets" / "fonts" / "Pretendard-OFL.txt" for app in coverage.APP_DIRS
        ]
        for notice in notices:
            self.assertIn("SIL OPEN FONT LICENSE", notice.read_text(encoding="utf-8").upper())
        self.assertEqual(notices[0].read_bytes(), notices[1].read_bytes())


class CheckerBehaviourTest(unittest.TestCase):
    def test_reports_missing_char_with_origin(self) -> None:
        font = coverage.font_paths()[0]
        origin = REPO_ROOT / "frontend/flutter/lib/l10n/app_ko.arb"
        chars = {"가": origin, "똠": origin, "🙂": origin}
        report = coverage.missing_chars([font], chars, fallback={"🙂"})
        self.assertEqual(report, {font: ["똠"]})

    def test_no_report_when_all_present(self) -> None:
        font = coverage.font_paths()[0]
        report = coverage.missing_chars([font], {"가": font, "A": font}, fallback=set())
        self.assertEqual(report, {})

    def test_used_chars_skips_invisible_and_collects_text(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "app_ko.arb"
            path.write_text('{"a": "근력 · 3세트\\u200d", "b": "👍‍️ "}', encoding="utf-8")
            found = coverage.used_chars([path])
        for char in "근력·세트👍":
            self.assertIn(char, found)
        for char in ("‍", "️", " ", " "):
            self.assertNotIn(char, found)
        self.assertIn("A", found)  # ASCII 는 항상 확인한다.

    def test_read_char_list_ignores_comments_and_spaces(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "chars.txt"
            path.write_text("# 설명 줄의 글자는 무시\n₩ −\n\n  ✓\n", encoding="utf-8")
            self.assertEqual(coverage.read_char_list(path), {"₩", "−", "✓"})

    def test_read_cmap_rejects_font_without_cmap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "empty.otf"
            path.write_bytes(b"OTTO" + struct.pack(">HHHH", 0, 0, 0, 0))
            with self.assertRaises(ValueError):
                coverage.read_cmap(path)

    def test_main_fails_with_guidance_on_missing_char(self) -> None:
        original = coverage.read_char_list
        out = io.StringIO()
        try:
            # 대체 글꼴 목록을 비우면 이모지가 '빠진 글자' 로 잡혀야 한다.
            coverage.read_char_list = lambda path: set()
            with redirect_stdout(out):
                code = coverage.main([])
        finally:
            coverage.read_char_list = original
        self.assertEqual(code, 1)
        self.assertIn("::error", out.getvalue())
        self.assertIn("pretendard_fallback_chars.txt", out.getvalue())


if __name__ == "__main__":
    unittest.main()
