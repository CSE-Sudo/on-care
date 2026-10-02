"""check_mobile_app_identity.py 테스트(#2823).

실제 회원 앱 설정이 통과하는지, 그리고 한 곳만 어긋나도 걸리는지를 확인한다. 어긋난
경우는 회원 앱 설정 파일을 임시 폴더로 복사한 뒤 한 군데만 바꿔 만든다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import io
import shutil
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


def run_main(*args: str) -> tuple[int, str]:
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        code = identity.main(list(args))
    return code, buffer.getvalue()


class RealAppTest(unittest.TestCase):
    def test_member_app_passes(self) -> None:
        self.assertEqual(identity.check(APP_DIR), [])

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

    def test_main_reports_annotation_and_fails(self) -> None:
        self.replace(identity.ANDROID_MANIFEST, f'android:label="{APP_NAME}"', 'android:label="oncare"')
        code, output = run_main(str(self.app))
        self.assertEqual(code, 1)
        self.assertIn("::error file=", output)
        self.assertIn("AndroidManifest.xml", output)


if __name__ == "__main__":
    unittest.main()
