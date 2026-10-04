"""릴리스 빌드 dart-define 주입 검사(#3022).

두 앱의 컴파일 타임 기본값은 로컬 개발용(ENV=dev·USE_MOCK_API=true·예시 주소)이라
define 하나를 빠뜨려도 빌드는 성공한다. 그래서 빌드를 만드는 곳마다 필요한 define 이
빠지지 않았는지 병합 전에 본다.

* 운영 웹(aws-frontend-deploy.yml) 두 빌드: USE_MOCK_API=false·ENV=prod·API_BASE_URL·
  SENTRY_DSN 이 모두 있고, DSN 은 앱마다 다른 비밀이며, DEMO_BUILD 는 없다.
* 데모 Pages(deploy.yml) 두 빌드: DEMO_BUILD=true 가 있다 — 빠지면 앱의 릴리스 가드가
  데모를 구성 오류 화면으로 띄운다.
* 스토어 릴리스 문서 두 곳의 빌드 명령은 같은 define 파일(--dart-define-from-file)을 쓰고,
  예시 파일이 필수 키를 모두 갖는다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
WORKFLOWS = REPO_ROOT / ".github" / "workflows"
AWS_DEPLOY = WORKFLOWS / "aws-frontend-deploy.yml"
DEMO_DEPLOY = WORKFLOWS / "deploy.yml"
RELEASE_EXAMPLE = REPO_ROOT / "frontend" / "flutter" / "config" / "release.example.json"
RELEASE_DOCS = (
    REPO_ROOT / "docs" / "mobile_release.md",
    REPO_ROOT / "frontend" / "flutter" / "docs" / "RELEASE.md",
)
APP_CONFIGS = (
    REPO_ROOT / "frontend" / "flutter" / "lib" / "core" / "config" / "app_config.dart",
    REPO_ROOT / "frontend" / "flutter_trainer" / "lib" / "core" / "config" / "app_config.dart",
)
REQUIRED_RELEASE_KEYS = {"ENV", "USE_MOCK_API", "API_BASE_URL", "SENTRY_DSN"}
FROM_FILE = "--dart-define-from-file=config/release.json"


def steps(workflow: Path) -> list[str]:
    """워크플로의 step 블록들(`      - name:` 부터 다음 step 직전까지)."""
    text = workflow.read_text(encoding="utf-8")
    parts = re.split(r"(?m)^(?=      - (?:name|uses):)", text)
    return [part for part in parts if part.startswith("      - ")]


def web_build_steps(workflow: Path) -> list[str]:
    return [step for step in steps(workflow) if "flutter build web" in step]


def code_blocks(text: str) -> list[str]:
    """마크다운 펜스 코드 블록 본문들. 들여 쓴 펜스(목록 안)도 센다."""
    blocks: list[str] = []
    current: list[str] | None = None
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            if current is None:
                current = []
            else:
                blocks.append("\n".join(current))
                current = None
            continue
        if current is not None:
            current.append(line)
    return blocks


def store_build_commands(text: str) -> list[str]:
    """문서 코드 블록 안의 스토어용 `flutter build …` 명령(줄 이음 `\\` 를 합친 것)."""
    commands = []
    for block in code_blocks(text):
        joined = re.sub(r"\s*\\\n\s*", " ", block)
        for line in joined.splitlines():
            if re.search(r"\bflutter build (appbundle|apk|ipa|ios)\b", line):
                commands.append(line.strip())
    return commands


class ProductionWebBuildTest(unittest.TestCase):
    def setUp(self) -> None:
        self.builds = web_build_steps(AWS_DEPLOY)

    def test_both_apps_are_built(self) -> None:
        self.assertEqual(len(self.builds), 2)
        self.assertTrue(any('"/frontend/"' in step for step in self.builds))
        self.assertTrue(any('"/trainer/"' in step for step in self.builds))

    def test_builds_pin_real_server_prod_and_sentry(self) -> None:
        for step in self.builds:
            with self.subTest(step=step.splitlines()[0]):
                self.assertIn("--dart-define=USE_MOCK_API=false", step)
                self.assertIn("--dart-define=ENV=prod", step)
                self.assertIn('--dart-define=API_BASE_URL="$API_BASE_URL"', step)
                self.assertIn('--dart-define=SENTRY_DSN="$SENTRY_DSN"', step)
                self.assertNotIn("DEMO_BUILD", step.split("run:", 1)[1])
                self.assertNotIn("SHOW_DEMO_ENTRY", step)
                self.assertNotIn("REAL_API", step)

    def test_builds_check_defines_before_building(self) -> None:
        # 데모·목업 값이 섞인 운영 빌드를 빌드 전에 막는다(#3147). 검사한 인자
        # 배열 그대로 빌드해야 검사와 빌드가 어긋나지 않는다.
        check = 'check_web_release_defines.sh" "${args[@]}"'
        build = 'flutter build web "${args[@]}"'
        for step in self.builds:
            with self.subTest(step=step.splitlines()[0]):
                self.assertIn(check, step)
                self.assertIn(build, step)
                self.assertLess(step.index(check), step.index(build))

    def test_each_app_reads_its_own_dsn_secret(self) -> None:
        secrets = {}
        for step in self.builds:
            match = re.search(r"SENTRY_DSN: \$\{\{ secrets\.(SENTRY_DSN_[A-Z]+) \}\}", step)
            self.assertIsNotNone(match, step.splitlines()[0])
            app = "member" if '"/frontend/"' in step else "trainer"
            secrets[app] = match.group(1)
        self.assertEqual(secrets, {"member": "SENTRY_DSN_MEMBER", "trainer": "SENTRY_DSN_TRAINER"})

    def test_missing_dsn_only_warns(self) -> None:
        check = [step for step in steps(AWS_DEPLOY) if "Check Sentry DSN secrets" in step]
        self.assertEqual(len(check), 1)
        self.assertIn("::warning", check[0])
        self.assertIn("https://", check[0])


class DemoWebBuildTest(unittest.TestCase):
    def test_demo_builds_mark_demo(self) -> None:
        builds = web_build_steps(DEMO_DEPLOY)
        self.assertEqual(len(builds), 2)
        for step in builds:
            with self.subTest(step=step.splitlines()[0]):
                self.assertIn("--dart-define=DEMO_BUILD=true", step)


class StoreReleaseDefinesTest(unittest.TestCase):
    def test_example_file_has_required_keys(self) -> None:
        data = json.loads(RELEASE_EXAMPLE.read_text(encoding="utf-8"))
        self.assertTrue(REQUIRED_RELEASE_KEYS <= set(data), sorted(data))
        self.assertEqual(data["ENV"], "prod")
        self.assertEqual(str(data["USE_MOCK_API"]).lower(), "false")
        self.assertNotIn("DEMO_BUILD", data)

    def test_release_file_is_ignored_but_example_is_not(self) -> None:
        ignore = (REPO_ROOT / "frontend" / "flutter" / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("/config/release*.json", ignore)
        self.assertIn("!/config/release.example.json", ignore)

    def test_docs_build_from_the_define_file(self) -> None:
        for doc in RELEASE_DOCS:
            commands = store_build_commands(doc.read_text(encoding="utf-8"))
            with self.subTest(doc=doc.name):
                self.assertTrue(commands, "스토어 빌드 명령을 찾지 못했습니다")
                for command in commands:
                    self.assertIn(FROM_FILE, command)
                    # 파일 밖에서 하나씩 넘기면 두 문서가 다시 어긋난다.
                    for key in REQUIRED_RELEASE_KEYS:
                        self.assertNotIn(f"--dart-define={key}=", command)

    def test_docs_run_the_checker_before_building(self) -> None:
        for doc in RELEASE_DOCS:
            with self.subTest(doc=doc.name):
                self.assertIn("tool/check_release_defines.sh config/release.json",
                              doc.read_text(encoding="utf-8"))

    def test_detector_reads_joined_commands(self) -> None:
        sample = (
            "```bash\n"
            "flutter build ipa --release \\\n"
            "  --dart-define=ENV=prod\n"
            "flutter pub get\n"
            "```\n"
        )
        self.assertEqual(store_build_commands(sample),
                         ["flutter build ipa --release --dart-define=ENV=prod"])


class AppGuardTest(unittest.TestCase):
    def test_both_apps_read_demo_build_and_guard_release(self) -> None:
        for path in APP_CONFIGS:
            text = path.read_text(encoding="utf-8")
            with self.subTest(app=path.parts[-5]):
                self.assertIn("bool.fromEnvironment('DEMO_BUILD')", text)
                self.assertIn("bool releaseMode = kReleaseMode", text)
                self.assertIn("List<ReleaseProblem> releaseProblems()", text)


if __name__ == "__main__":
    unittest.main()
