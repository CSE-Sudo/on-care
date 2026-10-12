"""두 앱 CI 의 테스트 묶음 배선 정적 검사(#3321).

`user-app-ci.yml`·`trainer-ci.yml` 은 `flutter test` 를 묶음으로 나눠 여러 잡에서 돌린다.
묶음 번호가 어긋나거나 전체 묶음 수를 숫자로 적어 두면, 잡은 모두 초록인데 어떤 테스트
파일은 어느 잡에서도 돌지 않는다. 결과를 모으는 잡이 실패를 놓쳐도 마찬가지다. 두
워크플로는 앱 경로를 건드리는 PR 에서만 돌므로, 배선은 경로와 무관하게 PR gate 에서 본다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import re
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

    def test_total_follows_the_matrix_and_index_starts_at_zero(self) -> None:
        for found, _, _ in self.each():
            job = found["test"]
            self.assertIn("          SHARD: ${{ matrix.shard }}\n", job)
            self.assertIn("          TOTAL_SHARDS: ${{ strategy.job-total }}\n", job)
            self.assertIn(
                '        run: flutter test --total-shards "$TOTAL_SHARDS" --shard-index "$((SHARD - 1))"\n',
                job,
            )

    def test_shards_run_the_plain_test_command_once(self) -> None:
        # 묶음 잡에 경로·이름 필터가 붙으면 그만큼의 테스트가 조용히 빠진다.
        for found, _, _ in self.each():
            commands = re.findall(r"(?m)^        run: (flutter test.*)$", found["test"])
            self.assertEqual(len(commands), 1)
            for flag in ("--name", "--plain-name", "--tags", "--exclude-tags", " test/"):
                self.assertNotIn(flag, commands[0])

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
            self.assertIn("    needs: [analyze, test]\n", job)
            self.assertIn("    if: always()\n", job)

    def test_result_job_fails_unless_both_succeeded(self) -> None:
        for found, _, _ in self.each():
            job = found["analyze-and-test"]
            self.assertIn("ANALYZE_RESULT: ${{ needs.analyze.result }}", job)
            self.assertIn("TEST_RESULT: ${{ needs.test.result }}", job)
            self.assertIn('[ "${ANALYZE_RESULT}" != success ] || [ "${TEST_RESULT}" != success ]', job)
            self.assertIn("exit 1", job)
            self.assertNotIn("|| true", job)

    def test_trainer_web_build_still_waits_for_analysis(self) -> None:
        self.assertIn("    needs: analyze\n", jobs("trainer-ci.yml")["web-build"])


if __name__ == "__main__":
    unittest.main()
