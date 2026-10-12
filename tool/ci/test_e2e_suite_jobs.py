"""E2E CI 의 스위트별 잡 배선 정적 검사(#3321).

`e2e-ci.yml` 은 `tool/run_*_e2e.sh` 를 찾아 스위트마다 잡을 하나씩 띄운다. 찾기가 빈
목록을 넘기거나, 결과를 모으는 잡이 건너뛴 스위트를 통과로 읽으면, 체크는 초록인데
E2E 는 하나도 돌지 않는다. 운영 프런트 배포가 이 워크플로의 성공을 신호로 삼으므로
배선은 PR gate 에서 본다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "e2e-ci.yml"


def jobs() -> dict[str, str]:
    text = WORKFLOW.read_text(encoding="utf-8").split("\njobs:\n", 1)[1]
    parts = re.split(r"(?m)^  ([A-Za-z0-9_-]+):\n", text)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}


class E2eSuiteJobsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.jobs = jobs()

    def test_workflow_name_stays_the_deploy_trigger(self) -> None:
        # aws-frontend-deploy.yml 이 이 이름의 완료(workflow_run)로 시작한다.
        self.assertTrue(WORKFLOW.read_text(encoding="utf-8").startswith("name: E2E CI\n"))

    def test_runner_convention_matches_real_files(self) -> None:
        self.assertIn("runners=(tool/run_*_e2e.sh)", self.jobs["suites"])
        self.assertTrue(sorted((REPO_ROOT / "tool").glob("run_*_e2e.sh")))

    def test_finding_no_suite_is_an_error(self) -> None:
        job = self.jobs["suites"]
        self.assertIn("shopt -s nullglob", job)
        self.assertRegex(job, r"if \[ \$\{#runners\[@\]\} -eq 0 \]; then\n.*\n\s+exit 1")

    def test_matrix_comes_from_the_found_suites(self) -> None:
        self.assertIn("      runners: ${{ steps.find.outputs.runners }}\n", self.jobs["suites"])
        self.assertIn('>> "$GITHUB_OUTPUT"', self.jobs["suites"])
        job = self.jobs["suite"]
        self.assertIn("    needs: suites\n", job)
        self.assertIn("        runner: ${{ fromJSON(needs.suites.outputs.runners) }}\n", job)
        self.assertIn("      fail-fast: false\n", job)

    def test_each_suite_job_has_its_own_database_and_backend(self) -> None:
        job = self.jobs["suite"]
        self.assertIn("        image: pgvector/pgvector:pg16\n", job)
        self.assertIn("        run: alembic upgrade head\n", job)
        self.assertIn("nohup uvicorn app.main:app", job)
        self.assertIn('      AUTO_CREATE_TABLES: "false"\n', job)

    def test_suite_name_reaches_the_shell_through_env_only(self) -> None:
        job = self.jobs["suite"]
        self.assertIn("      E2E_RUNNER: ${{ matrix.runner }}\n", job)
        scripts = re.findall(r"(?ms)^        run: \|\n(.*?)(?=^      - |\Z)", job)
        self.assertTrue(scripts)
        for script in scripts:
            self.assertNotIn("${{", script)

    def test_suite_runs_under_the_timeout_and_fails_the_job(self) -> None:
        job = self.jobs["suite"]
        self.assertIn(
            'if timeout --signal=TERM --kill-after=30s "$E2E_SUITE_TIMEOUT" bash "$r"; then', job
        )
        self.assertIn('echo "::error::$r 실패 (exit $rc)"\n              exit 1\n', job)
        self.assertNotIn("continue-on-error", job)

    def test_only_quarantined_suites_may_fail_quietly(self) -> None:
        job = self.jobs["suite"]
        self.assertIn('      E2E_QUARANTINE: ""\n', job)
        self.assertIn('*" $E2E_RUNNER "*) quarantined=true ;;', job)
        # 실패 분기의 `exit 1` 은 격리가 아닌 쪽에만 있다.
        failure = job.split("rc=$?", 1)[1].split("- name:", 1)[0]
        quarantined, normal = failure.split("else", 1)
        self.assertNotIn("exit 1", quarantined)
        self.assertIn("exit 1", normal)

    def test_result_job_keeps_the_old_check_name(self) -> None:
        self.assertIn(
            "    name: Real-API E2E (member app + trainer web)\n", self.jobs["e2e"]
        )

    def test_result_job_always_runs_and_fails_unless_all_succeeded(self) -> None:
        job = self.jobs["e2e"]
        self.assertIn("    needs: [suites, suite]\n", job)
        self.assertIn("    if: always()\n", job)
        self.assertIn("SUITES_RESULT: ${{ needs.suites.result }}", job)
        self.assertIn("SUITE_RESULT: ${{ needs.suite.result }}", job)
        self.assertIn('[ "${SUITES_RESULT}" != success ] || [ "${SUITE_RESULT}" != success ]', job)
        self.assertIn("exit 1", job)


if __name__ == "__main__":
    unittest.main()
