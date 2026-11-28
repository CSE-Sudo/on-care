"""백엔드 CI 의 감사 차단·린트·운영 설정 기동 스모크 배선 정적 검사(#3163).

`.github/workflows/backend-ci.yml` 은 백엔드 경로를 건드리는 PR 에서만 돈다. 감사 잡을 다시
경고 모드로 되돌리거나, 린트·운영 스모크 단계가 빠지거나, 허용 목록 검사를 `|| true` 로
삼키는 변경을 경로와 무관하게 PR gate 에서 잡는다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import io
import re
import sys
import tomllib
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_action_pins  # noqa: E402

REPO_ROOT = HERE.parent.parent
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "backend-ci.yml"
SMOKE_SCRIPT = REPO_ROOT / ".github" / "scripts" / "backend_prod_boot_smoke.sh"
SMOKE_ENV = REPO_ROOT / "backend" / "tests" / "fixtures" / "prod_smoke.env"
RUFF_CONFIG = REPO_ROOT / "backend" / "ruff.toml"
ALLOWLIST = REPO_ROOT / "backend" / "audit-allowlist.toml"


def workflow_text() -> str:
    return WORKFLOW.read_text(encoding="utf-8")


def jobs() -> dict[str, str]:
    text = workflow_text().split("\njobs:\n", 1)[1]
    parts = re.split(r"(?m)^  ([A-Za-z0-9_-]+):\n", text)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}


def steps(job: str) -> list[str]:
    parts = re.split(r"(?m)^(?=      - (?:name|uses):)", job)
    return [part for part in parts if part.startswith("      - ")]


def step_named(job: str, name: str) -> str:
    found = [s for s in steps(job) if s.startswith(f"      - name: {name}\n")]
    if len(found) != 1:
        raise AssertionError(f"step '{name}' 를 정확히 하나 찾지 못했습니다({len(found)})")
    return found[0]


class AuditJobTest(unittest.TestCase):
    def setUp(self) -> None:
        self.job = jobs()["audit"]

    def test_no_warning_mode_left(self) -> None:
        self.assertNotIn("AUDIT_MODE", workflow_text())
        self.assertNotIn("경고 모드입니다", workflow_text())

    def test_pip_audit_writes_json_from_the_locked_file(self) -> None:
        step = step_named(self.job, "Audit locked dependencies")
        self.assertIn("pip-audit --requirement requirements-dev.txt --require-hashes --disable-pip", step)
        self.assertIn("--format json --output audit.json", step)
        # 결과가 없으면(조회 실패) 통과시키지 않는다.
        self.assertIn('if [ ! -s audit.json ]; then', step)
        self.assertIn("exit 1", step)
        self.assertRegex(step_named(self.job, "Install pip-audit"), r"pip-audit==\d+\.\d+\.\d+")

    def test_gate_decides_the_result(self) -> None:
        step = step_named(self.job, "Check findings against the allowlist")
        self.assertIn("python ../tool/ci/pip_audit_gate.py", step)
        self.assertIn("--audit audit.json", step)
        self.assertIn("--allowlist audit-allowlist.toml", step)
        self.assertIn('--summary "$GITHUB_STEP_SUMMARY"', step)
        self.assertNotIn("|| true", step)
        self.assertNotIn("continue-on-error", self.job)
        # 감사 단계 뒤에 온다.
        names = [s.splitlines()[0] for s in steps(self.job)]
        self.assertLess(names.index("      - name: Audit locked dependencies"),
                        names.index("      - name: Check findings against the allowlist"))

    def test_allowlist_parses(self) -> None:
        data = tomllib.loads(ALLOWLIST.read_text(encoding="utf-8"))
        self.assertLessEqual(set(data), {"ignore"})


class LintJobTest(unittest.TestCase):
    def test_ruff_runs_on_the_backend(self) -> None:
        job = jobs()["lint"]
        self.assertIn("name: Lint (ruff)", job)
        self.assertIn("working-directory: backend", job)
        self.assertRegex(step_named(job, "Install ruff"), r"ruff==\d+\.\d+\.\d+")
        self.assertIn("ruff check", step_named(job, "ruff check"))
        self.assertNotIn("--exit-zero", job)
        self.assertNotIn("continue-on-error", job)

    def test_ruff_config_selects_error_rules(self) -> None:
        config = tomllib.loads(RUFF_CONFIG.read_text(encoding="utf-8"))
        select = set(config["lint"]["select"])
        self.assertTrue({"F", "E9"} <= select, select)
        self.assertEqual(config["target-version"], "py312")
        self.assertNotIn("ignore", config.get("lint", {}))


class ProdBootSmokeTest(unittest.TestCase):
    def test_image_job_runs_the_prod_smoke_after_the_dev_boot(self) -> None:
        job = jobs()["image"]
        names = [s.splitlines()[0] for s in steps(job)]
        dev = names.index("      - name: Boot the container and probe health")
        prod = names.index("      - name: Boot with production settings")
        self.assertLess(dev, prod)
        step = step_named(job, "Boot with production settings")
        self.assertIn(
            "bash ../.github/scripts/backend_prod_boot_smoke.sh oncare-backend:ci tests/fixtures/prod_smoke.env",
            step,
        )

    def test_smoke_probes_health_through_https_proxy_header(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('HTTPS=(-H "X-Forwarded-Proto: https")', script)
        for path in ("/v1/healthz", "/v1/readyz"):
            self.assertRegex(script, rf'"\$\{{HTTPS\[@\]\}}" "\$\{{BASE\}}{re.escape(path)}"')
        self.assertIn('"307 https://"*', script)
        self.assertIn("--env-file", script)
        # dev 컨테이너(8000)와 겹치지 않는 포트.
        self.assertNotIn('PORT="${SMOKE_PORT:-8000}"', script)

    def test_smoke_checks_boot_fails_without_required_values(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")
        cases = re.search(r"^REQUIRED_CASES=\(\n(?P<body>.*?)^\)", script, re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(cases)
        keys = re.findall(r'^\s*"([A-Z0-9_]+)\|', cases.group("body"), re.MULTILINE)
        self.assertIn("JWT_SECRET", keys)
        env_keys = {line.split("=", 1)[0] for line in SMOKE_ENV.read_text(encoding="utf-8").splitlines()
                    if line and not line.startswith("#")}
        self.assertTrue(set(keys) <= env_keys, set(keys) - env_keys)
        # 2분 넘게 떠 있으면(가드가 안 걸림) 실패로 본다.
        self.assertIn("timeout 120 docker run", script)
        self.assertIn('if [ "$status" -eq 124 ]; then', script)

    def test_smoke_env_is_production(self) -> None:
        lines = SMOKE_ENV.read_text(encoding="utf-8").splitlines()
        self.assertIn("ENV=prod", lines)
        self.assertIn("FORCE_HTTPS=true", lines)
        self.assertIn("SEED_DEMO_DATA=false", lines)
        self.assertIn("AUTO_CREATE_TABLES=false", lines)


class TestShardTest(unittest.TestCase):
    """테스트 묶음 배선(#3321). 묶음이 빠지거나 결과 잡이 실패를 놓치면 초록인데 안 돈 것이 된다."""

    def setUp(self) -> None:
        self.jobs = jobs()

    def shards(self) -> list[int]:
        found = re.search(r"(?m)^        shard: \[([0-9, ]+)\]$", self.jobs["test"])
        self.assertIsNotNone(found, "test 잡에 shard 매트릭스가 없습니다")
        return [int(n) for n in found.group(1).split(",")]

    def test_shards_are_numbered_from_one_without_gaps(self) -> None:
        shards = self.shards()
        self.assertGreaterEqual(len(shards), 2)
        self.assertEqual(shards, list(range(1, len(shards) + 1)))

    def test_shard_total_follows_the_matrix(self) -> None:
        # 분모를 숫자로 적어 두면 목록만 고친 PR 에서 일부 파일이 어느 묶음에도 들지 않는다.
        self.assertIn(
            "      PYTEST_SHARD: ${{ matrix.shard }}/${{ strategy.job-total }}\n", self.jobs["test"]
        )

    def test_one_failing_shard_does_not_cancel_the_rest(self) -> None:
        self.assertIn("      fail-fast: false\n", self.jobs["test"])

    def test_every_shard_runs_the_whole_selection_on_an_alembic_schema(self) -> None:
        job = self.jobs["test"]
        self.assertIn('      AUTO_CREATE_TABLES: "false"\n', job)
        self.assertEqual(step_named(job, "Run migrations").strip().splitlines()[-1].strip(), "run: alembic upgrade head")
        self.assertEqual(step_named(job, "Run tests").strip().splitlines()[-1].strip(), "run: pytest")

    def test_shards_install_from_the_locked_file(self) -> None:
        self.assertIn(
            "pip install --require-hashes -r requirements-dev.txt",
            step_named(self.jobs["test"], "Install dependencies"),
        )

    def test_migration_checks_run_once_in_their_own_job(self) -> None:
        job = self.jobs["migrations"]
        for name in (
            "Python version matches the Dockerfile",
            "Assert single Alembic head (no branched migrations)",
            "Run migrations (validates baseline)",
            "Models match migrations (alembic check)",
        ):
            with self.subTest(step=name):
                step_named(job, name)
        self.assertNotIn("matrix:", job)

    def test_result_job_keeps_the_old_check_name(self) -> None:
        self.assertIn("    name: Alembic + Pytest (Postgres/pgvector)\n", self.jobs["test-result"])

    def test_result_job_always_runs_and_needs_both(self) -> None:
        job = self.jobs["test-result"]
        self.assertIn("    needs: [migrations, test]\n", job)
        self.assertIn("    if: always()\n", job)

    def test_result_job_fails_unless_both_succeeded(self) -> None:
        body = step_named(self.jobs["test-result"], "Require every shard and the migration checks to pass")
        self.assertIn("MIGRATIONS_RESULT: ${{ needs.migrations.result }}", body)
        self.assertIn("TEST_RESULT: ${{ needs.test.result }}", body)
        self.assertIn('[ "${MIGRATIONS_RESULT}" != success ] || [ "${TEST_RESULT}" != success ]', body)
        self.assertIn("exit 1", body)
        self.assertNotIn("|| true", body)

    def test_shard_rule_lives_in_the_test_package(self) -> None:
        rule = (REPO_ROOT / "backend" / "tests" / "sharding.py").read_text(encoding="utf-8")
        self.assertIn('ENV_VAR = "PYTEST_SHARD"', rule)
        conftest = (REPO_ROOT / "backend" / "tests" / "conftest.py").read_text(encoding="utf-8")
        self.assertIn("def pytest_collection_modifyitems(config, items):", conftest)
        self.assertIn("raise pytest.UsageError", conftest)


class TriggerAndPinTest(unittest.TestCase):
    def test_paths_cover_the_new_scripts(self) -> None:
        text = workflow_text()
        for path in (".github/scripts/backend_prod_boot_smoke.sh", "tool/ci/pip_audit_gate.py"):
            with self.subTest(path=path):
                self.assertEqual(text.count(f'- "{path}"'), 2)

    def test_main_runs_just_before_and_after_kst_midnight(self) -> None:
        # 실제 KST 23:55·00:05 에 main 을 돈다(#3453). cron 은 UTC 로 적는다.
        text = workflow_text()
        self.assertIn("  schedule:\n", text)
        self.assertIn('    - cron: "55 14 * * *" # KST 23:55\n', text)
        self.assertIn('    - cron: "5 15 * * *" # KST 00:05\n', text)

    def test_scheduled_runs_do_not_share_the_main_push_group(self) -> None:
        # 같은 그룹이면 예약 실행이 대기 중인 병합 커밋 실행을 밀어내 취소할 수 있다.
        group = re.search(r"(?m)^  group: (.+)$", workflow_text())
        self.assertIsNotNone(group)
        self.assertIn("github.event_name == 'schedule'", group.group(1))
        self.assertIn("github.event.schedule", group.group(1))
        self.assertIn("github.ref", group.group(1))

    def test_deploy_ignores_scheduled_runs(self) -> None:
        # 백엔드 배포는 push 로 끝난 CI 만 받는다 — 예약 실행이 배포를 일으키지 않는다.
        deploy = (REPO_ROOT / ".github" / "workflows" / "backend-deploy.yml").read_text(encoding="utf-8")
        self.assertIn("github.event.workflow_run.event == 'push'", deploy)

    def test_actions_are_pinned(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            code = check_action_pins.main([str(WORKFLOW)])
        self.assertEqual(code, 0, out.getvalue())


if __name__ == "__main__":
    unittest.main()
