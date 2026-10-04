"""두 웹 배포의 새 버전 안내 배선 검사(#3023).

열린 탭이 새 배포를 알아채려면 세 가지가 함께 맞아야 한다.

* 두 웹 빌드가 `--dart-define=RELEASE_SHA=...` 로 자기 릴리스 SHA 를 내장하고,
* 같은 SHA 를 담은 `version.txt` 가 각 앱 폴더(`/frontend/`·`/trainer/`)에 올라가며,
* 운영 업로드는 진입 파일을 no-cache 로 나눠 올리는 스크립트를 거치고 그 헤더를 검증한다.

하나만 빠져도 빌드·배포는 성공하고 안내만 조용히 사라지므로 병합 전에 확인한다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
WORKFLOWS = REPO_ROOT / ".github" / "workflows"
AWS_DEPLOY = WORKFLOWS / "aws-frontend-deploy.yml"
PAGES_DEPLOY = WORKFLOWS / "deploy.yml"
SCRIPT = REPO_ROOT / ".github" / "scripts" / "web_cache_headers.sh"
APPS = ("frontend/flutter", "frontend/flutter_trainer")


def step_blocks(text: str) -> dict[str, str]:
    """`- name: X` 부터 다음 `- name:` 직전까지를 이름별로 자른다."""
    parts = re.split(r"^\s*- name: (.+)$", text, flags=re.MULTILINE)
    return {parts[i].strip(): parts[i + 1] for i in range(1, len(parts) - 1, 2)}


class WebReleaseRefreshWiringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.aws = AWS_DEPLOY.read_text(encoding="utf-8")
        cls.pages = PAGES_DEPLOY.read_text(encoding="utf-8")
        cls.aws_steps = step_blocks(cls.aws)

    def test_aws_builds_embed_release_sha(self) -> None:
        builds = [b for n, b in self.aws_steps.items() if n.startswith("Build Flutter web")]
        self.assertEqual(len(builds), 2)
        for block in builds:
            # 빌드 인자는 배열에 모아 빌드 전 검사(#3147)와 빌드가 같은 값을 쓴다.
            self.assertIn('flutter build web "${args[@]}"', block)
            self.assertRegex(block, r"args=\(\s*--release\b")
            self.assertRegex(block, r"--dart-define=RELEASE_SHA=\"\$\{RELEASE_SHA:-\$GITHUB_SHA\}\"")

    def test_pages_builds_embed_release_sha(self) -> None:
        self.assertEqual(self.pages.count('args+=(--dart-define=RELEASE_SHA="$GITHUB_SHA")'), 2)
        self.assertEqual(self.pages.count('flutter build web "${args[@]}"'), 2)

    def test_both_deploys_copy_version_into_each_app(self) -> None:
        for text in (self.aws, self.pages):
            for app in ("frontend", "trainer"):
                self.assertIn(f"cp public/version.txt public/{app}/version.txt", text)

    def test_aws_upload_goes_through_cache_header_script(self) -> None:
        upload = self.aws_steps["Upload release to S3"]
        self.assertIn("bash .github/scripts/web_cache_headers.sh upload public", upload)
        self.assertNotIn("aws s3 sync", upload)
        verify = self.aws_steps["Verify cache headers of the uploaded release"]
        self.assertIn("bash .github/scripts/web_cache_headers.sh verify", verify)

    def test_cache_header_verify_runs_before_traffic_switch(self) -> None:
        names = list(self.aws_steps)
        self.assertLess(names.index("Copy release marker into each app"),
                        names.index("Upload release to S3"))
        self.assertLess(names.index("Upload release to S3"),
                        names.index("Verify cache headers of the uploaded release"))
        self.assertLess(names.index("Verify cache headers of the uploaded release"),
                        names.index("Switch CloudFront origin to the new release"))

    def test_script_keeps_entry_files_uncached(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('ENTRY_CACHE_CONTROL="no-cache"', script)
        entries = re.search(r"ENTRY_FILES=\((.*?)\)", script, re.DOTALL)
        self.assertIsNotNone(entries)
        names = set(entries.group(1).split())
        for name in ("index.html", "flutter_bootstrap.js", "main.dart.js",
                     "version.json", "version.txt", "manifest.json"):
            self.assertIn(name, names)

    def test_apps_read_release_sha_define(self) -> None:
        for app in APPS:
            path = REPO_ROOT / app / "lib" / "core" / "release" / "release_update.dart"
            with self.subTest(app=app):
                text = path.read_text(encoding="utf-8")
                self.assertIn("String.fromEnvironment('RELEASE_SHA')", text)

    def test_apps_fetch_version_relative_to_base_href(self) -> None:
        for app in APPS:
            path = REPO_ROOT / app / "lib" / "core" / "release" / "release_probe_web.dart"
            with self.subTest(app=app):
                text = path.read_text(encoding="utf-8")
                self.assertIn("baseURI", text)
                self.assertIn("'version.txt'", text)
                self.assertIn("no-store", text)


if __name__ == "__main__":
    unittest.main()
