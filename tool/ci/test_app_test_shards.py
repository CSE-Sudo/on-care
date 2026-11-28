"""두 앱 CI 의 테스트 묶음 배선 정적 검사(#3321).

`user-app-ci.yml`·`trainer-ci.yml` 은 `flutter test` 를 묶음으로 나눠 여러 잡에서 돌린다.
묶음 번호가 어긋나거나 전체 묶음 수를 숫자로 적어 두면, 잡은 모두 초록인데 어떤 테스트
파일은 어느 잡에서도 돌지 않는다. 결과를 모으는 잡이 실패를 놓쳐도 마찬가지다. 두
워크플로는 앱 경로를 건드리는 PR 에서만 돌므로, 배선은 경로와 무관하게 PR gate 에서 본다.

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
WORKFLOWS = REPO_ROOT / ".github" / "workflows"

#: 워크플로 파일 → (앱 폴더, 결과를 모으는 잡이 지켜야 하는 체크 이름)
APPS = {
    "user-app-ci.yml": ("frontend/flutter", "Analyze and test (user app)"),
    "trainer-ci.yml": ("frontend/flutter_trainer", "Analyze and test"),
}


def jobs(name: str) -> dict[str, str]:
    text = (WORKFLOWS / name).read_text(encoding="utf-8").split("\njobs:\n", 1)[1]
    parts = re.split(r"(?m)^  ([A-Za-z0-9_-]+):\n", text)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}


class AppTestShardTest(unittest.TestCase):
    def each(self):
        for workflow, (app_dir, check_name) in APPS.items():
            with self.subTest(workflow=workflow):
                yield jobs(workflow), app_dir, check_name

    def test_shards_are_numbered_from_one_without_gaps(self) -> None:
        for found, _, _ in self.each():
            matrix = re.search(r"(?m)^        shard: \[([0-9, ]+)\]$", found["test"])
            self.assertIsNotNone(matrix, "test 잡에 shard 매트릭스가 없습니다")
            shards = [int(n) for n in matrix.group(1).split(",")]
            self.assertGreaterEqual(len(shards), 2)
            self.assertEqual(shards, list(range(1, len(shards) + 1)))

    def test_total_follows_the_matrix(self) -> None:
        for found, _, _ in self.each():
            job = found["test"]
            self.assertIn("          SHARD: ${{ matrix.shard }}\n", job)
            self.assertIn("          TOTAL_SHARDS: ${{ strategy.job-total }}\n", job)

    def test_shards_run_through_the_shard_script_once_without_filters(self) -> None:
        # 묶음 잡에 경로·이름·태그 필터가 붙으면 그만큼의 테스트가 조용히 빠진다.
        for found, _, _ in self.each():
            job = found["test"]
            commands = re.findall(r"(?m)^        run: (.*flutter.*test.*)$", job)
            self.assertEqual(
                commands,
                ['bash ../../.github/scripts/flutter_test_shard.sh "$SHARD" "$TOTAL_SHARDS"'],
            )
            # 테스트 단위로 나누는 옵션은 쓰지 않는다 — 모든 묶음이 모든 파일을 컴파일한다.
            self.assertNotIn("--total-shards", job)

    def test_one_failing_shard_does_not_cancel_the_rest(self) -> None:
        for found, _, _ in self.each():
            self.assertIn("      fail-fast: false\n", found["test"])

    def test_shards_run_in_the_app_folder_on_the_pinned_sdk(self) -> None:
        for found, app_dir, _ in self.each():
            job = found["test"]
            self.assertIn(f"        working-directory: {app_dir}\n", job)
            analyze_sdk = set(re.findall(r"flutter-version: '([0-9.]+)'", found["analyze"]))
            self.assertEqual(set(re.findall(r"flutter-version: '([0-9.]+)'", job)), analyze_sdk)
            self.assertEqual(len(analyze_sdk), 1)

    def test_analysis_job_no_longer_runs_the_app_tests(self) -> None:
        # 두 곳에서 돌면 시간만 다시 늘고, 한쪽만 고친 필터가 다른 쪽에 가려진다.
        for found, _, _ in self.each():
            self.assertNotIn("        run: flutter test\n", found["analyze"])
            self.assertIn("        run: flutter analyze\n", found["analyze"])
            self.assertIn("        run: dart run custom_lint\n", found["analyze"])

    def test_result_job_keeps_the_old_check_name(self) -> None:
        for found, _, check_name in self.each():
            self.assertIn(f"    name: {check_name}\n", found["analyze-and-test"])

    def test_result_job_always_runs_and_needs_both(self) -> None:
        for found, _, _ in self.each():
            job = found["analyze-and-test"]
            self.assertIn("    needs: [analyze, test, test-midnight]\n", job)
            self.assertIn("    if: always()\n", job)

    def test_result_job_fails_unless_both_succeeded(self) -> None:
        for found, _, _ in self.each():
            job = found["analyze-and-test"]
            self.assertIn("ANALYZE_RESULT: ${{ needs.analyze.result }}", job)
            self.assertIn("TEST_RESULT: ${{ needs.test.result }}", job)
            self.assertIn("MIDNIGHT_RESULT: ${{ needs.test-midnight.result }}", job)
            self.assertIn(
                '[ "${ANALYZE_RESULT}" != success ] || [ "${TEST_RESULT}" != success ]'
                ' || [ "${MIDNIGHT_RESULT}" != success ]',
                job,
            )
            self.assertIn("exit 1", job)
            self.assertNotIn("|| true", job)

    def test_midnight_runs_start_just_before_and_after_midnight(self) -> None:
        # 자정 직전·직후에 시작한 실행에서만 깨지는 테스트를 PR 에서 잡는다(#3448).
        for found, _, _ in self.each():
            job = found["test-midnight"]
            self.assertIn("        kst_time: ['23:59', '00:01']\n", job)
            self.assertIn("          KST_TIME: ${{ matrix.kst_time }}\n", job)
            self.assertIn('"--dart-define=ONCARE_TEST_KST_TIME=$KST_TIME"', job)

    def test_midnight_shards_cover_every_file(self) -> None:
        # 자정 실행은 `strategy.job-total` 에 시각 수까지 곱해지므로 묶음 수를 직접 적는다.
        # 목록 길이와 어긋나면 어떤 파일은 자정 실행에서 빠진다.
        for found, _, _ in self.each():
            job = found["test-midnight"]
            matrix = re.search(r"(?m)^        shard: \[([0-9, ]+)\]$", job)
            self.assertIsNotNone(matrix, "test-midnight 잡에 shard 매트릭스가 없습니다")
            shards = [int(n) for n in matrix.group(1).split(",")]
            self.assertGreaterEqual(len(shards), 2)
            self.assertEqual(shards, list(range(1, len(shards) + 1)))
            self.assertIn(f"          TOTAL_SHARDS: {len(shards)}\n", job)
            self.assertIn(f"${{{{ matrix.shard }}}}/{len(shards)})", job)
            commands = re.findall(r"(?m)^          (bash .*flutter_test_shard\.sh.*)$", job)
            self.assertEqual(
                commands,
                ['bash ../../.github/scripts/flutter_test_shard.sh "$SHARD" "$TOTAL_SHARDS"'],
            )
            self.assertNotIn("--total-shards", job)

    def test_midnight_shards_run_like_the_daytime_shards(self) -> None:
        for found, app_dir, _ in self.each():
            job = found["test-midnight"]
            self.assertIn("      fail-fast: false\n", job)
            self.assertIn(f"        working-directory: {app_dir}\n", job)
            analyze_sdk = set(re.findall(r"flutter-version: '([0-9.]+)'", found["analyze"]))
            self.assertEqual(set(re.findall(r"flutter-version: '([0-9.]+)'", job)), analyze_sdk)

    def test_trainer_web_build_still_waits_for_analysis(self) -> None:
        self.assertIn("    needs: analyze\n", jobs("trainer-ci.yml")["web-build"])


SCRIPT = REPO_ROOT / ".github" / "scripts" / "flutter_test_shard.sh"

#: `flutter` 자리에 세우는 대역. 받은 인자를 한 줄에 하나씩 파일에 적는다.
FAKE_FLUTTER = """#!/usr/bin/env bash
printf '%s\\n' "$@" > "$FAKE_FLUTTER_OUT"
"""


class FlutterTestShardScriptTest(unittest.TestCase):
    """묶음 스크립트가 파일을 빠짐·겹침 없이 나누는지 실제로 돌려 본다."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.fake = self.tmp / "flutter"
        self.fake.write_text(FAKE_FLUTTER, encoding="utf-8")
        self.fake.chmod(0o755)
        self.out = self.tmp / "args.txt"

    def run_shard(self, app_dir: Path, *args: str) -> subprocess.CompletedProcess[str]:
        if self.out.exists():
            self.out.unlink()
        env = {**os.environ, "FLUTTER": str(self.fake), "FAKE_FLUTTER_OUT": str(self.out)}
        return subprocess.run(
            ["bash", str(SCRIPT), *args], cwd=app_dir, env=env, capture_output=True, text=True
        )

    def passed_args(self) -> list[str]:
        return self.out.read_text(encoding="utf-8").splitlines()

    def make_app(self, names: list[str]) -> Path:
        app = self.tmp / "app"
        for name in names:
            path = app / "test" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("void main() {}\n", encoding="utf-8")
        return app

    def partition(self, app_dir: Path, total: int) -> list[list[str]]:
        shards = []
        for shard in range(1, total + 1):
            result = self.run_shard(app_dir, str(shard), str(total))
            self.assertEqual(result.returncode, 0, result.stderr)
            args = self.passed_args()
            self.assertEqual(args[0], "test")
            shards.append(args[1:])
        return shards

    def assert_exact_partition(self, app_dir: Path, total: int) -> None:
        expected = sorted(
            p.relative_to(app_dir).as_posix() for p in (app_dir / "test").rglob("*_test.dart")
        )
        shards = self.partition(app_dir, total)
        merged = [f for shard in shards for f in shard]
        self.assertEqual(len(merged), len(set(merged)), "두 묶음에 든 파일이 있습니다")
        self.assertEqual(sorted(merged), expected, "어느 묶음에도 없는 파일이 있습니다")
        sizes = [len(shard) for shard in shards]
        self.assertLessEqual(max(sizes) - min(sizes), 1)

    def test_every_file_lands_in_exactly_one_shard(self) -> None:
        app = self.make_app(
            [f"features/f{i % 5}/case_{i:02d}_test.dart" for i in range(23)] + ["widget_test.dart"]
        )
        for total in (1, 2, 4, 7):
            with self.subTest(total=total):
                self.assert_exact_partition(app, total)

    def test_real_apps_are_fully_covered_by_the_workflow_shards(self) -> None:
        for workflow, (app_dir, _) in APPS.items():
            with self.subTest(workflow=workflow):
                matrix = re.search(r"(?m)^        shard: \[([0-9, ]+)\]$", jobs(workflow)["test"])
                self.assert_exact_partition(REPO_ROOT / app_dir, len(matrix.group(1).split(",")))

    def test_helpers_and_non_test_files_are_left_to_flutter(self) -> None:
        app = self.make_app(["a_test.dart", "helpers/pump.dart", "flutter_test_config.dart"])
        self.assertEqual(self.partition(app, 1), [["test/a_test.dart"]])

    def test_same_split_on_every_run(self) -> None:
        app = self.make_app([f"t{i}_test.dart" for i in range(9)])
        self.assertEqual(self.partition(app, 3), self.partition(app, 3))

    def test_extra_arguments_reach_flutter_before_the_files(self) -> None:
        app = self.make_app(["a_test.dart"])
        result = self.run_shard(app, "1", "1", "--reporter", "expanded")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.passed_args(), ["test", "--reporter", "expanded", "test/a_test.dart"])

    def test_reports_how_many_files_the_shard_took(self) -> None:
        app = self.make_app([f"t{i}_test.dart" for i in range(5)])
        result = self.run_shard(app, "2", "2")
        self.assertIn("묶음 2/2: 테스트 파일 전체 5개 중 2개를 맡음", result.stdout)

    def test_empty_shard_is_an_error_not_a_pass(self) -> None:
        app = self.make_app(["a_test.dart"])
        result = self.run_shard(app, "2", "2")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.out.exists())

    def test_bad_shard_numbers_are_rejected(self) -> None:
        app = self.make_app(["a_test.dart"])
        for args in (("0", "4"), ("5", "4"), ("x", "4"), ("1", ""), ("1",), ()):
            with self.subTest(args=args):
                result = self.run_shard(app, *args)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.out.exists())

    def test_missing_test_folder_is_rejected(self) -> None:
        empty = self.tmp / "nowhere"
        empty.mkdir()
        self.assertEqual(self.run_shard(empty, "1", "1").returncode, 2)


if __name__ == "__main__":
    unittest.main()
