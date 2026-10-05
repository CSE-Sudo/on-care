"""check_mobile_app_identity.py 테스트(#2823, 실행 화면 #3153).

실제 회원 앱 설정이 통과하는지, 그리고 한 곳만 어긋나도 걸리는지를 확인한다. 어긋난
경우는 회원 앱 설정 파일을 임시 폴더로 복사한 뒤 한 군데만 바꿔 만든다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import io
import shutil
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
APP_DIR = REPO_ROOT / "frontend" / "flutter"

sys.path.insert(0, str(HERE))
import check_mobile_app_identity as identity  # noqa: E402

APP_ID = identity.EXPECTED_APP_ID
APP_NAME = identity.EXPECTED_APP_NAME
KOTLIN_DIR = identity.KOTLIN_ROOT / Path(*APP_ID.split("."))

COPIED = [
    identity.GRADLE,
    identity.ANDROID_MANIFEST,
    identity.PBXPROJ,
    identity.INFO_PLIST,
    identity.WEB_MANIFEST,
    identity.WEB_INDEX,
    KOTLIN_DIR / "MainActivity.kt",
]

# 실행 화면(#3153) 검사에 쓰는 파일. 그림은 바이너리라 그대로 복사한다.
LAUNCH_DENSITIES = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
LAUNCH_IMAGES = [
    identity.ANDROID_RES / f"drawable-{density}" / "launch_image.png"
    for density in LAUNCH_DENSITIES
]
IOS_LAUNCH_IMAGES = [
    identity.LAUNCH_IMAGESET / name
    for name in ("LaunchImage.png", "LaunchImage@2x.png", "LaunchImage@3x.png")
]
ANDROID12_ICON = identity.ANDROID_RES / "drawable-v31" / "launch_icon_android12.xml"
LAUNCH_FILES = [
    *identity.LAUNCH_BACKGROUNDS,
    *identity.SPLASH_STYLES_V31,
    ANDROID12_ICON,
    *LAUNCH_IMAGES,
    identity.LAUNCH_IMAGESET / "Contents.json",
    *IOS_LAUNCH_IMAGES,
    identity.LAUNCH_STORYBOARD,
]

COPIED += LAUNCH_FILES


def tiny_png(width: int, height: int) -> bytes:
    """IHDR 까지만 있는 PNG — 검사는 크기만 읽는다."""
    ihdr = struct.pack(">II", width, height) + bytes([8, 6, 0, 0, 0])
    return (
        identity.PNG_SIGNATURE
        + struct.pack(">I", len(ihdr))
        + b"IHDR"
        + ihdr
        + b"\x00\x00\x00\x00"
    )


def run_main(*args: str) -> tuple[int, str]:
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        code = identity.main(list(args))
    return code, buffer.getvalue()


class RealAppTest(unittest.TestCase):
    def test_member_app_passes(self) -> None:
        self.assertEqual(identity.check(APP_DIR), [])

    def test_member_app_launch_screen_passes(self) -> None:
        self.assertEqual(identity.check_launch_screen(APP_DIR), [])

    def test_ios_launch_images_are_real_logo_sizes(self) -> None:
        sizes = [identity.png_size(APP_DIR / image) for image in IOS_LAUNCH_IMAGES]
        self.assertNotIn((1, 1), sizes)
        base = sizes[0]
        self.assertIsNotNone(base)
        self.assertGreaterEqual(min(base), identity.MIN_LAUNCH_IMAGE_POINTS)
        self.assertEqual(sizes[1], (base[0] * 2, base[1] * 2))
        self.assertEqual(sizes[2], (base[0] * 3, base[1] * 3))

    def test_android_launch_images_follow_density_ratio(self) -> None:
        # mdpi 1 : hdpi 1.5 : xhdpi 2 : xxhdpi 3 : xxxhdpi 4
        ratios = (1, 1.5, 2, 3, 4)
        base = identity.png_size(APP_DIR / LAUNCH_IMAGES[0])
        self.assertIsNotNone(base)
        for image, ratio in zip(LAUNCH_IMAGES, ratios):
            self.assertEqual(
                identity.png_size(APP_DIR / image),
                (int(base[0] * ratio), int(base[1] * ratio)),
                str(image),
            )

    def test_png_size_rejects_non_png(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.png"
            path.write_bytes(b"not a png at all, just bytes......")
            self.assertIsNone(identity.png_size(path))
            path.write_bytes(tiny_png(120, 80))
            self.assertEqual(identity.png_size(path), (120, 80))

    def test_main_returns_zero_for_member_app(self) -> None:
        code, output = run_main(str(APP_DIR))
        self.assertEqual(code, 0, output)
        self.assertIn(APP_ID, output)


class MismatchTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.app = Path(self._tmp.name)
        for relative in COPIED:
            target = self.app / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(APP_DIR / relative, target)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def replace(self, relative: Path, old: str, new: str) -> None:
        path = self.app / relative
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text, f"{relative} 에 `{old}` 가 없어 테스트를 만들 수 없습니다")
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def assert_problem(self, file: Path, fragment: str) -> None:
        problems = identity.check(self.app)
        matched = [p for p in problems if p.file == file and fragment in p.message]
        self.assertTrue(matched, f"{file} 에서 `{fragment}` 문제를 기대했지만: {problems}")

    def test_copy_passes_before_changes(self) -> None:
        self.assertEqual(identity.check(self.app), [])

    def test_application_id_mismatch(self) -> None:
        self.replace(identity.GRADLE, f'applicationId = "{APP_ID}"', 'applicationId = "com.example.other"')
        self.assert_problem(identity.GRADLE, "applicationId")

    def test_namespace_mismatch(self) -> None:
        self.replace(identity.GRADLE, f'namespace = "{APP_ID}"', 'namespace = "com.example.other"')
        self.assert_problem(identity.GRADLE, "namespace")

    def test_release_signed_with_debug_key(self) -> None:
        self.replace(
            identity.GRADLE,
            'signingConfig = signingConfigs.getByName("release")',
            'signingConfig = signingConfigs.getByName("debug")',
        )
        self.assert_problem(identity.GRADLE, "디버그 키")

    def test_missing_signing_guard(self) -> None:
        self.replace(identity.GRADLE, "throw GradleException(", "println(")
        self.assert_problem(identity.GRADLE, "가드")

    def test_kotlin_package_declaration_mismatch(self) -> None:
        self.replace(KOTLIN_DIR / "MainActivity.kt", f"package {APP_ID}", "package com.example.other")
        self.assert_problem(KOTLIN_DIR / "MainActivity.kt", "package 선언")

    def test_kotlin_directory_mismatch(self) -> None:
        moved = self.app / identity.KOTLIN_ROOT / "com" / "example" / "other"
        moved.mkdir(parents=True)
        shutil.move(str(self.app / KOTLIN_DIR / "MainActivity.kt"), moved / "MainActivity.kt")
        self.assert_problem(
            identity.KOTLIN_ROOT / "com" / "example" / "other" / "MainActivity.kt", "패키지 경로"
        )

    def test_ios_runner_bundle_id_mismatch(self) -> None:
        self.replace(
            identity.PBXPROJ,
            f"PRODUCT_BUNDLE_IDENTIFIER = {APP_ID};",
            "PRODUCT_BUNDLE_IDENTIFIER = com.example.other;",
        )
        self.assert_problem(identity.PBXPROJ, "com.example.other")

    def test_ios_tests_bundle_id_mismatch(self) -> None:
        self.replace(
            identity.PBXPROJ,
            f"PRODUCT_BUNDLE_IDENTIFIER = {APP_ID}.RunnerTests;",
            "PRODUCT_BUNDLE_IDENTIFIER = com.example.other.RunnerTests;",
        )
        self.assert_problem(identity.PBXPROJ, "com.example.other.RunnerTests")

    def test_android_label_mismatch(self) -> None:
        self.replace(identity.ANDROID_MANIFEST, f'android:label="{APP_NAME}"', 'android:label="oncare"')
        self.assert_problem(identity.ANDROID_MANIFEST, "android:label")

    def test_ios_display_name_mismatch(self) -> None:
        self.replace(
            identity.INFO_PLIST,
            f"<key>CFBundleDisplayName</key>\n\t<string>{APP_NAME}</string>",
            "<key>CFBundleDisplayName</key>\n\t<string>Oncare</string>",
        )
        self.assert_problem(identity.INFO_PLIST, "CFBundleDisplayName")

    def test_web_manifest_name_mismatch(self) -> None:
        self.replace(identity.WEB_MANIFEST, f'"short_name": "{APP_NAME}"', '"short_name": "Oncare"')
        self.assert_problem(identity.WEB_MANIFEST, "short_name")

    def test_web_home_screen_title_mismatch(self) -> None:
        self.replace(
            identity.WEB_INDEX,
            f'name="apple-mobile-web-app-title" content="{APP_NAME}"',
            'name="apple-mobile-web-app-title" content="oncare"',
        )
        self.assert_problem(identity.WEB_INDEX, "apple-mobile-web-app-title")

    # ── 실행 화면 (#3153) ──

    def test_launch_background_template_comment(self) -> None:
        # 템플릿처럼 로고 항목을 주석으로 돌리면 흰 화면만 남는다.
        relative = identity.LAUNCH_BACKGROUNDS[0]
        path = self.app / relative
        text = path.read_text(encoding="utf-8")
        start = text.index("<item>\n        <bitmap")
        end = text.index("</item>", start) + len("</item>")
        path.write_text(
            text[:start] + "<!-- " + text[start:end] + " -->" + text[end:],
            encoding="utf-8",
        )
        self.assert_problem(relative, "로고 비트맵 항목이 없습니다")

    def test_launch_background_v21_checked_too(self) -> None:
        relative = identity.LAUNCH_BACKGROUNDS[1]
        self.replace(relative, "@drawable/launch_image", "@drawable/missing_logo")
        self.assert_problem(relative, "그림 파일이 없습니다")

    def test_android_placeholder_logo(self) -> None:
        (self.app / LAUNCH_IMAGES[2]).write_bytes(tiny_png(1, 1))
        self.assert_problem(LAUNCH_IMAGES[2], "자리표시가 아닌 실제 로고")

    def test_android12_background_missing(self) -> None:
        relative = identity.SPLASH_STYLES_V31[0]
        self.replace(relative, 'name="android:windowSplashScreenBackground"', 'name="android:unused"')
        self.assert_problem(relative, "windowSplashScreenBackground")

    def test_android12_night_icon_missing(self) -> None:
        relative = identity.SPLASH_STYLES_V31[1]
        self.replace(relative, 'name="android:windowSplashScreenAnimatedIcon"', 'name="android:unused"')
        self.assert_problem(relative, "windowSplashScreenAnimatedIcon")

    def test_android12_night_styles_missing(self) -> None:
        (self.app / identity.SPLASH_STYLES_V31[1]).unlink()
        self.assert_problem(identity.SPLASH_STYLES_V31[1], "스타일 파일이 없습니다")

    def test_android12_icon_drawable_missing(self) -> None:
        (self.app / ANDROID12_ICON).unlink()
        self.assert_problem(identity.SPLASH_STYLES_V31[0], "launch_icon_android12")

    def test_ios_one_pixel_placeholder(self) -> None:
        (self.app / IOS_LAUNCH_IMAGES[0]).write_bytes(tiny_png(1, 1))
        self.assert_problem(IOS_LAUNCH_IMAGES[0], "1×1 픽셀 자리표시")

    def test_ios_scale_mismatch(self) -> None:
        base = identity.png_size(self.app / IOS_LAUNCH_IMAGES[0])
        assert base is not None
        (self.app / IOS_LAUNCH_IMAGES[1]).write_bytes(tiny_png(base[0] * 3, base[1] * 3))
        self.assert_problem(identity.LAUNCH_IMAGESET / "Contents.json", "배율별 크기가 서로 다릅니다")

    def test_ios_launch_image_not_png(self) -> None:
        (self.app / IOS_LAUNCH_IMAGES[2]).write_bytes(b"placeholder")
        self.assert_problem(IOS_LAUNCH_IMAGES[2], "PNG 가 아닙니다")

    def test_storyboard_without_launch_image(self) -> None:
        self.replace(identity.LAUNCH_STORYBOARD, 'image="LaunchImage"', 'image="Other"')
        self.assert_problem(identity.LAUNCH_STORYBOARD, "LaunchImage 를 보여 주지 않습니다")

    def test_main_reports_annotation_and_fails(self) -> None:
        self.replace(identity.ANDROID_MANIFEST, f'android:label="{APP_NAME}"', 'android:label="oncare"')
        code, output = run_main(str(self.app))
        self.assertEqual(code, 1)
        self.assertIn("::error file=", output)
        self.assertIn("AndroidManifest.xml", output)


if __name__ == "__main__":
    unittest.main()
