"""운영 웹 번들 검사와 데모 자산 선언 제거 스크립트의 테스트(#3157).

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import base64
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_prod_web_bundle as bundle  # noqa: E402

REPO_ROOT = bundle.REPO_ROOT


def _load_strip():
    path = REPO_ROOT / "frontend" / "tool" / "strip_demo_assets.py"
    spec = importlib.util.spec_from_file_location("strip_demo_assets", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


strip_demo = _load_strip()


def _write(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, str):
        data = data.encode("utf-8")
    path.write_bytes(data)


class _BuildFixture:
    """build/web 과 원본 앱 폴더를 흉내 낸 임시 폴더."""

    def __init__(self, root: Path) -> None:
        self.build = root / "build" / "web"
        self.app = root / "app"
        _write(self.build / "main.dart.js", "var a='real-api';")
        _write(self.build / "assets" / "assets" / "images" / "oncare-logo.png", b"png")
        _write(self.build / "assets" / "AssetManifest.json", '{"assets/images/oncare-logo.png":[]}')
        _write(self.app / "assets" / "demo" / "images" / "diet-chicken-salad.jpg", b"jpg")
        _write(self.app / "assets" / "demo" / "program.pdf", b"pdf")


class CheckProdWebBundleTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.fx = _BuildFixture(Path(self._tmp.name))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_check(self, app: str = "member") -> list[str]:
        return bundle.check(app, self.fx.build, self.fx.app)

    def test_clean_build_passes(self) -> None:
        self.assertEqual(self.run_check("member"), [])
        self.assertEqual(self.run_check("trainer"), [])

    def test_marker_in_main_bundle_fails(self) -> None:
        _write(self.fx.build / "main.dart.js", "var e='drift-local';")
        problems = self.run_check("member")
        self.assertEqual(len(problems), 1)
        self.assertIn("drift-local", problems[0])

    def test_marker_in_deferred_part_fails(self) -> None:
        _write(self.fx.build / "main.dart.js_3.part.js", "x('breakfast-onigiri')")
        problems = self.run_check("trainer")
        self.assertTrue(any("main.dart.js_3.part.js" in p for p in problems), problems)

    def test_markers_are_per_app(self) -> None:
        # 트레이너 표지가 회원 번들에 있다고 회원 검사가 실패하지는 않는다.
        _write(self.fx.build / "main.dart.js", "x('breakfast-onigiri')")
        self.assertEqual(self.run_check("member"), [])

    def test_demo_asset_tree_fails(self) -> None:
        _write(self.fx.build / "assets" / "assets" / "demo" / "images" / "other.jpg", b"jpg")
        problems = self.run_check()
        self.assertTrue(any("assets/assets/demo" in p for p in problems), problems)

    def test_demo_asset_in_manifest_fails(self) -> None:
        _write(
            self.fx.build / "assets" / "AssetManifest.json",
            '{"assets/demo/images/x.jpg":[]}',
        )
        problems = self.run_check()
        self.assertTrue(any("AssetManifest.json" in p for p in problems), problems)

    def test_demo_asset_in_base64_manifest_fails(self) -> None:
        raw = b"\x0d\x01\x07\x18assets/demo/images/x.jpg"
        _write(
            self.fx.build / "assets" / "AssetManifest.bin.json",
            json.dumps(base64.b64encode(raw).decode("ascii")),
        )
        problems = self.run_check()
        self.assertTrue(any("AssetManifest.bin.json" in p for p in problems), problems)

    def test_demo_file_name_anywhere_fails(self) -> None:
        _write(self.fx.build / "assets" / "packages" / "x" / "program.pdf", b"pdf")
        problems = self.run_check()
        self.assertTrue(any("program.pdf" in p for p in problems), problems)

    def test_missing_bundle_fails(self) -> None:
        (self.fx.build / "main.dart.js").unlink()
        problems = self.run_check()
        self.assertEqual(len(problems), 1)
        self.assertIn("main.dart.js", problems[0])

    def test_main_reports_errors_and_sizes(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            code = bundle.main(["--app", "member", str(self.fx.build)])
        # 실제 앱 폴더의 데모 자산 이름도 함께 보지만, 임시 산출물에는 없다.
        self.assertEqual(code, 0, out.getvalue())
        self.assertIn("JS 번들 합계", out.getvalue())

        _write(self.fx.build / "main.dart.js", "'demo_member_login'")
        out = io.StringIO()
        with redirect_stdout(out):
            code = bundle.main(["--app", "member", str(self.fx.build)])
        self.assertEqual(code, 1)
        self.assertIn("::error", out.getvalue())

    def test_markers_exist_in_demo_sources(self) -> None:
        # 표지가 소스에서 사라지면 검사가 아무것도 잡지 못한다 — 아직 있는지 본다.
        sources = {
            "member": [REPO_ROOT / "frontend/flutter/lib", REPO_ROOT / "shared/demo_fixture/lib"],
            "trainer": [
                REPO_ROOT / "frontend/flutter_trainer/lib",
                REPO_ROOT / "shared/demo_fixture/lib",
            ],
        }
        for app, roots in sources.items():
            text = "".join(
                p.read_text(encoding="utf-8")
                for root in roots
                for p in root.rglob("*.dart")
            )
            for marker in bundle.MARKERS[app]:
                self.assertIn(marker, text, f"{app}: {marker}")
                self.assertTrue(marker.isascii(), marker)


class StripDemoAssetsTest(unittest.TestCase):
    PUBSPEC = (
        "flutter:\n"
        "  assets:\n"
        "    - assets/images/\n"
        "    # >>> demo-assets — 설명\n"
        "    # 이어지는 설명\n"
        "    - assets/demo/\n"
        "    - assets/demo/images/\n"
        "    # <<< demo-assets\n"
        "\n"
        "  fonts:\n"
    )

    def test_removes_marked_block(self) -> None:
        stripped, removed = strip_demo.strip(self.PUBSPEC)
        self.assertEqual(removed, 1)
        self.assertNotIn("assets/demo", stripped)
        self.assertIn("    - assets/images/\n\n  fonts:\n", stripped)

    def test_is_idempotent(self) -> None:
        once, _ = strip_demo.strip(self.PUBSPEC)
        twice, removed = strip_demo.strip(once)
        self.assertEqual(once, twice)
        self.assertEqual(removed, 0)

    def test_rejects_demo_declaration_outside_block(self) -> None:
        text = self.PUBSPEC.replace("- assets/images/", "- assets/demo/extra/")
        with self.assertRaises(strip_demo.StripError):
            strip_demo.strip(text)

    def test_rejects_unbalanced_markers(self) -> None:
        with self.assertRaises(strip_demo.StripError):
            strip_demo.strip(self.PUBSPEC.replace("    # <<< demo-assets\n", ""))
        with self.assertRaises(strip_demo.StripError):
            strip_demo.strip(self.PUBSPEC.replace("    # >>> demo-assets — 설명\n", ""))

    def test_main_rewrites_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pubspec = Path(tmp) / "pubspec.yaml"
            pubspec.write_text(self.PUBSPEC, encoding="utf-8")
            with redirect_stdout(io.StringIO()):
                self.assertEqual(strip_demo.main([tmp]), 0)
            self.assertNotIn("assets/demo", pubspec.read_text(encoding="utf-8"))

    def test_both_app_pubspecs_strip_cleanly(self) -> None:
        for app_dir in bundle.APPS.values():
            text = (app_dir / "pubspec.yaml").read_text(encoding="utf-8")
            stripped, removed = strip_demo.strip(text)
            self.assertEqual(removed, 1, app_dir.name)
            self.assertNotIn("assets/demo", stripped)
            # 데모 자산 구간 밖의 운영 자산은 남는다.
            self.assertIn("- assets/images/", stripped)
            # 데모 시드 사진은 운영 자산 폴더가 아니라 데모 폴더에 있다.
            images = app_dir / "assets" / "images"
            leaked = sorted(
                p.name
                for p in images.iterdir()
                if p.name.split("-")[0] in {"breakfast", "lunch", "dinner", "snack", "diet"}
            )
            self.assertEqual(leaked, [], app_dir.name)


if __name__ == "__main__":
    unittest.main()
