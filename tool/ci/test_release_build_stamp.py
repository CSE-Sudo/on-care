"""릴리스 빌드 번호·배포 일시 배선 검사(#3226).

두 앱 고객 지원의 버전 줄 는 `On-Care · 버전 0.4.0 (7032) · <KST 배포 일시>` 처럼 보인다. 빌드 번호와
배포 일시는 빌드 때 dart-define 으로만 들어가므로, 하나만 빠져도 빌드는 성공하고 화면은 조용히
`개발 빌드` 로 보인다. 그래서 병합 전에 다음을 본다.

* `.github/scripts/release_build_stamp.sh` — 커밋 수를 빌드 번호로, UTC 시각을 배포 일시로 낸다.
  얕은 체크아웃·하한 이하 번호는 거부한다.
* 데모 Pages(`deploy.yml`)·운영(`aws-frontend-deploy.yml`) 두 웹 빌드가 같은 스탬프를
  `--build-number`·`BUILD_NUMBER`·`RELEASE_DATE` 로 받고, 체크아웃이 전체 이력을 받는다.
* 두 앱이 같은 이름의 define 을 읽는다.

서명 빌드(`member-app-release.yml`)의 배선은 test_member_app_release.py 가 본다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPT = REPO_ROOT / ".github" / "scripts" / "release_build_stamp.sh"
WORKFLOWS = REPO_ROOT / ".github" / "workflows"
WEB_DEPLOYS = (WORKFLOWS / "deploy.yml", WORKFLOWS / "aws-frontend-deploy.yml")
STAMP_STEP = "Stamp release build number and date"
APPS = ("frontend/flutter", "frontend/flutter_trainer")
DATE_RE = re.compile(r"^RELEASE_DATE=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", re.MULTILINE)

GIT_ENV = {
    "GIT_AUTHOR_NAME": "stamp-test",
    "GIT_AUTHOR_EMAIL": "stamp-test@example.com",
    "GIT_COMMITTER_NAME": "stamp-test",
    "GIT_COMMITTER_EMAIL": "stamp-test@example.com",
    "GIT_CONFIG_NOSYSTEM": "1",
}


def git(cwd: Path, *args: str) -> None:
    subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        env={**os.environ, **GIT_ENV},
    )


def make_repo(root: Path, commits: int) -> Path:
    repo = root / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    for index in range(commits):
        git(repo, "commit", "-q", "--allow-empty", "-m", f"commit {index}")
    return repo


def run_stamp(cwd: Path, *args: str, min_build: str | None = None) -> subprocess.CompletedProcess[str]:
    env = {**os.environ}
    env.pop("MIN_BUILD_NUMBER", None)
    if min_build is not None:
        env["MIN_BUILD_NUMBER"] = min_build
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        # 스크립트는 한국어 안내를 UTF-8 로 낸다. Windows 기본 인코딩(cp949)으로 읽으면 출력이 None 이 된다.
        encoding="utf-8",
        env=env,
    )


def step_blocks(text: str) -> list[tuple[str, str]]:
    """`- name: X` 부터 다음 step 직전까지를 순서대로 자른다."""
    parts = re.split(r"(?m)^      - name: (.+)$", text)
    return [(parts[i].strip(), parts[i + 1]) for i in range(1, len(parts) - 1, 2)]


class StampScriptTest(unittest.TestCase):
    def test_build_number_is_the_commit_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(Path(tmp), 3)
            result = run_stamp(repo)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("BUILD_NUMBER=3\n", result.stdout)
            self.assertRegex(result.stdout, DATE_RE)

    def test_number_grows_with_each_merge(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(Path(tmp), 2)
            first = run_stamp(repo).stdout
            git(repo, "commit", "-q", "--allow-empty", "-m", "next")
            second = run_stamp(repo).stdout
            self.assertIn("BUILD_NUMBER=2\n", first)
            self.assertIn("BUILD_NUMBER=3\n", second)

    def test_appends_to_the_output_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(Path(tmp), 4)
            out = Path(tmp) / "github_env"
            out.write_text("EXISTING=1\n", encoding="utf-8")
            result = run_stamp(repo, str(out))
            self.assertEqual(result.returncode, 0, result.stdout)
            lines = out.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines[0], "EXISTING=1")
            self.assertEqual(lines[1], "BUILD_NUMBER=4")
            self.assertRegex(lines[2], DATE_RE)
            self.assertEqual(len(lines), 3)

    def test_refuses_a_shallow_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(Path(tmp), 3)
            shallow = Path(tmp) / "shallow"
            git(Path(tmp), "clone", "-q", "--depth", "1", f"file://{repo}", str(shallow))
            result = run_stamp(shallow)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("fetch-depth: 0", result.stdout)
            self.assertNotIn("BUILD_NUMBER=", result.stdout)

    def test_refuses_outside_a_repository(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_stamp(Path(tmp))
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("BUILD_NUMBER=", result.stdout)

    def test_minimum_must_be_exceeded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(Path(tmp), 5)
            self.assertEqual(run_stamp(repo, min_build="4").returncode, 0)
            self.assertNotEqual(run_stamp(repo, min_build="5").returncode, 0)
            self.assertNotEqual(run_stamp(repo, min_build="12").returncode, 0)
            self.assertNotEqual(run_stamp(repo, min_build="abc").returncode, 0)
            # 비어 있으면 하한 검사를 건너뛴다.
            self.assertEqual(run_stamp(repo, min_build="").returncode, 0)

    def test_failure_does_not_touch_the_output_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(Path(tmp), 2)
            out = Path(tmp) / "github_env"
            out.write_text("", encoding="utf-8")
            result = run_stamp(repo, str(out), min_build="9")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(out.read_text(encoding="utf-8"), "")


class WebDeployWiringTest(unittest.TestCase):
    def test_both_web_builds_receive_the_stamp(self) -> None:
        for workflow in WEB_DEPLOYS:
            blocks = step_blocks(workflow.read_text(encoding="utf-8"))
            builds = [body for name, body in blocks if "flutter build web" in body]
            with self.subTest(workflow=workflow.name):
                self.assertEqual(len(builds), 2)
                for body in builds:
                    self.assertIn('--build-number="$BUILD_NUMBER"', body)
                    self.assertIn('--dart-define=BUILD_NUMBER="$BUILD_NUMBER"', body)
                    self.assertIn('--dart-define=RELEASE_DATE="$RELEASE_DATE"', body)
                    self.assertNotIn("--build-name", body)

    def test_stamp_runs_once_before_the_builds(self) -> None:
        for workflow in WEB_DEPLOYS:
            blocks = step_blocks(workflow.read_text(encoding="utf-8"))
            names = [name for name, _ in blocks]
            with self.subTest(workflow=workflow.name):
                self.assertEqual(names.count(STAMP_STEP), 1)
                stamp = names.index(STAMP_STEP)
                body = dict(blocks)[STAMP_STEP]
                self.assertIn('bash .github/scripts/release_build_stamp.sh "$GITHUB_ENV"', body)
                build_indexes = [i for i, (_, b) in enumerate(blocks) if "flutter build web" in b]
                self.assertTrue(all(stamp < i for i in build_indexes))

    def test_build_job_checkout_keeps_full_history(self) -> None:
        for workflow in WEB_DEPLOYS:
            blocks = step_blocks(workflow.read_text(encoding="utf-8"))
            names = [name for name, _ in blocks]
            stamp = names.index(STAMP_STEP)
            # 스탬프 단계와 같은 잡에서 가장 가까운 앞쪽 체크아웃.
            checkout = next(
                body for name, body in reversed(blocks[:stamp]) if name == "Checkout repository"
            )
            with self.subTest(workflow=workflow.name):
                self.assertIn("fetch-depth: 0", checkout)


class AppDefinesTest(unittest.TestCase):
    def test_apps_read_the_same_define_names(self) -> None:
        for app in APPS:
            path = REPO_ROOT / app / "lib" / "core" / "release" / "build_info.dart"
            with self.subTest(app=app):
                text = path.read_text(encoding="utf-8")
                self.assertIn("String.fromEnvironment('BUILD_NUMBER')", text)
                self.assertIn("String.fromEnvironment('RELEASE_DATE')", text)


if __name__ == "__main__":
    unittest.main()
