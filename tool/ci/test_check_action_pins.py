"""check_action_pins.py 테스트(#2340).

pr-gate 는 모든 PR 의 필수 검사라, 이 스크립트가 오탐하면 모든 병합이 막힌다.
그래서 통과해야 하는 형태와 걸려야 하는 형태를 픽스처로 함께 고정해 둔다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
FIXTURES = HERE / "fixtures"
SCRIPT = HERE / "check_action_pins.py"

sys.path.insert(0, str(HERE))
import check_action_pins as pins  # noqa: E402

SHA = "11d5960a326750d5838078e36cf38b85af677262"


def run_main(*args: str) -> tuple[int, str]:
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        code = pins.main(list(args))
    return code, buffer.getvalue()


class ParseValueTest(unittest.TestCase):
    def test_strips_trailing_comment(self) -> None:
        self.assertEqual(
            pins.parse_value(f" actions/checkout@{SHA} # v4.4.0"),
            f"actions/checkout@{SHA}",
        )

    def test_strips_quotes(self) -> None:
        self.assertEqual(pins.parse_value(' "actions/checkout@v4" # v4'), "actions/checkout@v4")
        self.assertEqual(pins.parse_value(" 'actions/checkout@v4'"), "actions/checkout@v4")

    def test_hash_without_space_is_part_of_value(self) -> None:
        self.assertEqual(pins.parse_value(" owner/repo@ref#frag"), "owner/repo@ref#frag")

    def test_empty(self) -> None:
        self.assertEqual(pins.parse_value("   "), "")


class CheckReferenceTest(unittest.TestCase):
    def test_accepts_sha_pinned_action(self) -> None:
        self.assertIsNone(pins.check_reference(f"actions/checkout@{SHA}"))

    def test_accepts_sha_pinned_subdirectory_action(self) -> None:
        self.assertIsNone(pins.check_reference(f"github/codeql-action/init@{SHA}"))

    def test_accepts_sha_pinned_reusable_workflow(self) -> None:
        self.assertIsNone(
            pins.check_reference(f"octo-org/shared/.github/workflows/build.yml@{SHA}")
        )

    def test_accepts_local_action(self) -> None:
        self.assertIsNone(pins.check_reference("./.github/actions/setup"))

    def test_accepts_docker_reference(self) -> None:
        self.assertIsNone(pins.check_reference("docker://alpine:3.20"))

    def test_rejects_tag(self) -> None:
        reason = pins.check_reference("actions/checkout@v4")
        self.assertIsNotNone(reason)
        self.assertIn("@v4", reason)

    def test_rejects_branch(self) -> None:
        self.assertIsNotNone(pins.check_reference("subosito/flutter-action@main"))

    def test_rejects_short_sha(self) -> None:
        self.assertIsNotNone(pins.check_reference(f"actions/checkout@{SHA[:7]}"))

    def test_rejects_too_long_sha(self) -> None:
        self.assertIsNotNone(pins.check_reference(f"actions/checkout@{SHA}0"))

    def test_rejects_uppercase_hex(self) -> None:
        self.assertIsNotNone(pins.check_reference(f"actions/checkout@{SHA.upper()}"))

    def test_rejects_missing_ref(self) -> None:
        self.assertIsNotNone(pins.check_reference("actions/cache"))

    def test_rejects_tag_on_reusable_workflow(self) -> None:
        self.assertIsNotNone(
            pins.check_reference("octo-org/shared/.github/workflows/build.yml@v1")
        )

    def test_rejects_expression(self) -> None:
        self.assertIsNotNone(pins.check_reference("${{ matrix.action }}"))

    def test_rejects_empty(self) -> None:
        self.assertIsNotNone(pins.check_reference(""))


class CheckFileTest(unittest.TestCase):
    def test_pinned_fixture_has_no_problems(self) -> None:
        self.assertEqual(pins.check_file(FIXTURES / "pinned.yml"), [])

    def test_unpinned_fixture_reports_each_offending_line(self) -> None:
        problems = pins.check_file(FIXTURES / "unpinned.yml")
        self.assertEqual([line for line, _ in problems], [9, 14, 16, 18, 20, 22, 24])

    def test_commented_uses_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "commented.yml"
            path.write_text(
                "jobs:\n  a:\n    steps:\n      # - uses: actions/checkout@v4\n",
                encoding="utf-8",
            )
            self.assertEqual(pins.check_file(path), [])


class MainTest(unittest.TestCase):
    def test_repository_workflows_pass(self) -> None:
        # 현재 저장소의 워크플로는 모두 SHA 고정이어야 한다. 여기서 실패하면
        # 이 검사가 pr-gate 에서 모든 PR 을 막는다.
        code, output = run_main(str(REPO_ROOT / ".github" / "workflows"))
        self.assertEqual(code, 0, output)
        self.assertNotIn("::error", output)

    def test_pinned_fixture_passes(self) -> None:
        code, output = run_main(str(FIXTURES / "pinned.yml"))
        self.assertEqual(code, 0, output)

    def test_unpinned_fixture_fails_with_annotations(self) -> None:
        path = FIXTURES / "unpinned.yml"
        code, output = run_main(str(path))
        self.assertEqual(code, 1)
        errors = [line for line in output.splitlines() if line.startswith("::error ")]
        self.assertEqual(len(errors), 7)
        self.assertTrue(errors[0].startswith(f"::error file={path},line=9::"))
        self.assertIn(f"::error file={path},line=14::", output)

    def test_directory_argument_checks_all_yaml_files(self) -> None:
        code, output = run_main(str(FIXTURES))
        self.assertEqual(code, 1)
        errors = [line for line in output.splitlines() if line.startswith("::error ")]
        self.assertEqual(len(errors), 7)
        # 경로 구분자는 OS 마다 다르다(Windows 는 `\`). 주석의 file= 값을 파일 이름으로 비교한다.
        files = {Path(line.split("file=", 1)[1].split(",line=", 1)[0]).name for line in errors}
        self.assertEqual(files, {"unpinned.yml"}, errors)

    def test_yaml_extension_is_checked(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "ci.yaml").write_text(
                "jobs:\n  a:\n    steps:\n      - uses: actions/checkout@v4\n",
                encoding="utf-8",
            )
            code, output = run_main(tmp)
        self.assertEqual(code, 1)
        self.assertIn("ci.yaml,line=4", output)

    def test_empty_directory_is_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            code, output = run_main(tmp)
        self.assertEqual(code, 2)
        self.assertIn("::error::", output)

    def test_missing_path_is_an_error(self) -> None:
        code, output = run_main(str(FIXTURES / "does-not-exist.yml"))
        self.assertEqual(code, 2)
        self.assertIn("::error::", output)

    def test_default_target_from_repository_root(self) -> None:
        # pr-gate 는 저장소 루트에서 인자 없이 실행한다.
        result = subprocess.run(
            [sys.executable, str(SCRIPT)],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
