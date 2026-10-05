"""두 웹 배포의 새 버전 안내 배선 검사(#3023).

열린 탭이 새 배포를 알아채려면 세 가지가 함께 맞아야 한다.

* 두 웹 빌드가 `--dart-define=RELEASE_SHA=...` 로 자기 릴리스 SHA 를 내장하고,
* 같은 SHA 를 담은 `version.txt` 가 각 앱 폴더(`/frontend/`·`/trainer/`)에 올라가며,
* 운영 업로드는 진입 파일을 no-cache 로 나눠 올리는 스크립트를 거치고 그 헤더를 검증한다.

안내의 `새로고침` 이 실제로 새 번들을 받으려면(#3204) 다음도 맞아야 한다.

* 두 앱이 서비스 워커를 등록하지 않는다 — `web/flutter_bootstrap.js` 템플릿에
  `serviceWorkerSettings` 가 없다.
* 예전 빌드가 설치한 워커를 `web/js/sw_cleanup.js` 가 해제한다(두 앱 같은 파일).
* 빌드는 `--pwa-strategy` 를 넘기지 않는다 — Flutter 의 자기 해제형
  `flutter_service_worker.js` 가 빈 파일로 바뀌지 않게. 그 파일은 no-cache 로 올린다.
* 새로고침 전에 진입 파일을 `cache: 'reload'` 로 받아 HTTP 캐시를 바꾼다.

하나만 빠져도 빌드·배포는 성공하고 안내만 조용히 사라지거나 되풀이되므로 병합 전에 확인한다.

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
WEB_BUILD_WORKFLOWS = ("deploy.yml", "aws-frontend-deploy.yml", "trainer-ci.yml", "user-app-ci.yml",
                       "e2e-ci.yml")


def strip_line_comments(text: str) -> str:
    """`//` 로 시작하는 줄(설명 주석)을 뺀 코드만 남긴다."""
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("//"))


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

    def test_apps_boot_without_service_worker(self) -> None:
        for app in APPS:
            path = REPO_ROOT / app / "web" / "flutter_bootstrap.js"
            with self.subTest(app=app):
                self.assertTrue(path.is_file(), path)
                code = strip_line_comments(path.read_text(encoding="utf-8"))
                self.assertIn("{{flutter_js}}", code)
                self.assertIn("{{flutter_build_config}}", code)
                self.assertIn("_flutter.loader.load();", code)
                self.assertNotIn("serviceWorkerSettings", code)
                self.assertNotIn("flutter_service_worker_version", code)
                self.assertNotIn("serviceWorker", code)

    def test_apps_unregister_old_service_workers(self) -> None:
        copies = {}
        for app in APPS:
            script = REPO_ROOT / app / "web" / "js" / "sw_cleanup.js"
            index = (REPO_ROOT / app / "web" / "index.html").read_text(encoding="utf-8")
            with self.subTest(app=app):
                self.assertTrue(script.is_file(), script)
                copies[app] = script.read_bytes()
                self.assertIn('<script src="js/sw_cleanup.js"></script>', index)
                head = index[: index.index("</head>")]
                self.assertIn("js/sw_cleanup.js", head)
                code = copies[app].decode("utf-8")
                self.assertIn("getRegistrations()", code)
                self.assertIn(".unregister()", code)
                self.assertIn("document.baseURI", code)
        self.assertEqual(len(set(copies.values())), 1, "두 앱의 sw_cleanup.js 사본이 다르다")

    def test_builds_keep_self_destroying_worker(self) -> None:
        for name in WEB_BUILD_WORKFLOWS:
            path = WORKFLOWS / name
            if not path.is_file():
                continue
            with self.subTest(workflow=name):
                self.assertNotIn("--pwa-strategy", path.read_text(encoding="utf-8"))

    def test_script_keeps_service_worker_uncached(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")
        entries = re.search(r"ENTRY_FILES=\((.*?)\)", script, re.DOTALL)
        self.assertIsNotNone(entries)
        self.assertIn("flutter_service_worker.js", set(entries.group(1).split()))

    def test_apps_refresh_entry_files_before_reload(self) -> None:
        for app in APPS:
            path = REPO_ROOT / app / "lib" / "core" / "release" / "release_probe_web.dart"
            with self.subTest(app=app):
                text = path.read_text(encoding="utf-8")
                self.assertIn("cache: 'reload'", text)
                for name in ("'flutter_bootstrap.js'", "'main.dart.js'"):
                    self.assertIn(name, text)
                self.assertIn("arrayBuffer()", text)
                self.assertIn("sessionStorage", text)
                refresh = text.index("kReleaseEntryFiles.map(_refresh)")
                self.assertLess(refresh, text.index("location.reload()"))


if __name__ == "__main__":
    unittest.main()
