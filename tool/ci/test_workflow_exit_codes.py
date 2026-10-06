"""종료 코드를 받아 분기하는 워크플로 step 이 `bash -e` 에서도 분기에 닿는지 본다(#3235).

`shell:` 을 지정하지 않은 step 은 GitHub 이 `bash -e {0}` 로 돌린다. 스크립트 첫 줄의
`set -uo pipefail` 은 -e 를 끄지 않으므로, `cmd` 다음 줄에서 `code=$?` 로 받으면 cmd 가
0 이 아닌 값으로 끝나는 순간 step 이 그 자리에서 끝난다. 여기서는

  1) 모든 워크플로의 `run:` 에서 `x=$?` 를 따로 받는 줄을 찾아, `|| x=$?` 꼴이거나 `else`
     바로 다음이거나 앞에서 `set +e` 를 둔 경우만 허용하고,
  2) 그 분기를 쓰는 step(프런트 배포 대기 두 개·두 배포의 옛 커밋 가드(#3254)·pip-audit)을 실제로
     `bash -e` 로 돌려
     가짜 명령이 0 이 아닌 값을 내도 다음 분기까지 가는지 확인한다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
WORKFLOWS = REPO_ROOT / ".github" / "workflows"
AWS_DEPLOY = WORKFLOWS / "aws-frontend-deploy.yml"
BACKEND_CI = WORKFLOWS / "backend-ci.yml"
BACKEND_DEPLOY = WORKFLOWS / "backend-deploy.yml"

BASH = shutil.which("bash")

_CAPTURE = re.compile(r"^\s*[A-Za-z_][A-Za-z0-9_]*=\$\?\s*$")


def run_blocks(text: str) -> list[tuple[str, list[str]]]:
    """`run: |` 블록을 (step 이름, 본문 줄) 목록으로 돌려준다. 들여쓰기는 걷어 낸다."""
    lines = text.splitlines()
    blocks: list[tuple[str, list[str]]] = []
    name = "?"
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^\s*- name:\s*(.+)$", line)
        if m:
            name = m.group(1).strip()
        m = re.match(r"^(\s*)run:\s*\|", line)
        if not m:
            i += 1
            continue
        key_indent = len(m.group(1))
        body: list[str] = []
        i += 1
        while i < len(lines):
            nxt = lines[i]
            if nxt.strip() and len(nxt) - len(nxt.lstrip(" ")) <= key_indent:
                break
            body.append(nxt)
            i += 1
        while body and not body[-1].strip():
            body.pop()
        blocks.append((name, textwrap.dedent("\n".join(body)).splitlines()))
    return blocks


def step_script(path: Path, name: str) -> str:
    found = [body for step, body in run_blocks(path.read_text(encoding="utf-8")) if step == name]
    if len(found) != 1:
        raise AssertionError(f"{path.name} 에서 step '{name}' 의 run 블록을 정확히 하나 찾지 못했습니다({len(found)})")
    return "\n".join(found[0]) + "\n"


class CaptureAfterFailureTest(unittest.TestCase):
    """`cmd` 다음 줄의 `x=$?` 는 `bash -e` 에서 닿지 않는다."""

    def test_no_bare_exit_code_capture(self) -> None:
        offenders = []
        for workflow in sorted(WORKFLOWS.glob("*.yml")):
            for name, body in run_blocks(workflow.read_text(encoding="utf-8")):
                errexit_off = False
                prev = ""
                for line in body:
                    stripped = line.strip()
                    if stripped.startswith("set +e"):
                        errexit_off = True
                    elif re.match(r"set -[a-z]*e", stripped):
                        errexit_off = False
                    if _CAPTURE.match(line) and not errexit_off and prev != "else":
                        offenders.append(f"{workflow.name}: {name}: {stripped}")
                    if stripped:
                        prev = stripped
        self.assertEqual(offenders, [], "종료 코드는 `cmd || code=$?` 로 받습니다(#3235)")

    def test_detector_catches_the_old_form(self) -> None:
        sample = "      - name: X\n        run: |\n          set -uo pipefail\n          cmd\n          code=$?\n"
        (name, body), = run_blocks(sample)
        self.assertEqual(name, "X")
        self.assertTrue(any(_CAPTURE.match(line) for line in body))


@unittest.skipIf(BASH is None, "bash 가 없습니다")
class StepUnderErrexitTest(unittest.TestCase):
    """step 본문을 GitHub 기본 셸과 같은 `bash -e` 로 돌린다."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.work = Path(self._tmp.name)
        self.bin = self.work / "_bin"
        self.bin.mkdir()
        self.summary = self.work / "summary.md"
        self.summary.write_text("", encoding="utf-8")
        # 대기 루프의 sleep 은 건너뛴다.
        self.stub(self.bin / "sleep", "exit 0\n")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def stub(self, path: Path, body: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(("#!/usr/bin/env bash\n" + body).encode("utf-8"))
        path.chmod(0o755)

    def sequenced_stub(self, path: Path, outputs: list[tuple[int, str]]) -> None:
        """부를 때마다 outputs 를 차례로 내는 가짜 스크립트. 부른 횟수는 <path>.count 에 남는다."""
        cases = []
        for n, (code, out) in enumerate(outputs, start=1):
            cases.append(f"  {n}) printf '%s' '{out}'; exit {code} ;;")
        last_code, last_out = outputs[-1]
        cases.append(f"  *) printf '%s' '{last_out}'; exit {last_code} ;;")
        body = (
            'count_file="$0.count"\n'
            'n=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))\n'
            'echo "$n" > "$count_file"\n'
            'case "$n" in\n' + "\n".join(cases) + "\nesac\n"
        )
        self.stub(path, body)

    def calls(self, path: Path) -> int:
        count = Path(str(path) + ".count")
        return int(count.read_text(encoding="utf-8").strip()) if count.exists() else 0

    def run_step(self, script: str, env: dict[str, str], cwd: Path | None = None) -> subprocess.CompletedProcess:
        step = self.work / "step.sh"
        step.write_bytes(script.encode("utf-8"))
        full_env = dict(os.environ)
        full_env.update(env)
        full_env["GITHUB_STEP_SUMMARY"] = str(self.summary)
        full_env["PATH"] = str(self.bin) + os.pathsep + full_env.get("PATH", "")
        return subprocess.run(
            [BASH, "-e", str(step)],
            cwd=cwd or self.work,
            env=full_env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=60,
        )

    # --- aws-frontend-deploy.yml: Check CI results for the commit
    def ci_gate(self, outputs: list[tuple[int, str]], wait: str = "1800") -> tuple[subprocess.CompletedProcess, Path]:
        gate = self.work / ".github" / "scripts" / "frontend_ci_gate.sh"
        self.sequenced_stub(gate, outputs)
        script = step_script(AWS_DEPLOY, "Check CI results for the commit")
        return self.run_step(script, {"SHA": "a" * 40, "WAIT_SECONDS": wait}), gate

    def test_ci_gate_waits_then_passes(self) -> None:
        result, gate = self.ci_gate([(10, "- E2E CI: in_progress\n"), (0, "- E2E CI: success\n")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(gate), 2)
        self.assertIn("- E2E CI: success", self.summary.read_text(encoding="utf-8"))

    def test_ci_gate_failure_prints_reason(self) -> None:
        result, gate = self.ci_gate([(1, "- E2E CI: failure\n")])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls(gate), 1)
        self.assertIn("- E2E CI: failure", result.stdout)
        self.assertIn("- E2E CI: failure", self.summary.read_text(encoding="utf-8"))

    def test_ci_gate_times_out(self) -> None:
        result, _ = self.ci_gate([(10, "- E2E CI: in_progress\n")], wait="0")
        self.assertEqual(result.returncode, 1)
        self.assertIn("안에 끝나지 않았습니다", result.stdout)

    # --- aws-frontend-deploy.yml: Check backend deploy order
    def backend_order(self, outputs: list[tuple[int, str]], enabled: str = "true") -> tuple[subprocess.CompletedProcess, Path]:
        scripts = self.work / ".github" / "scripts"
        self.stub(scripts / "check_web_api_base_url.sh", "exit 0\n")
        order = scripts / "frontend_backend_order.sh"
        self.sequenced_stub(order, outputs)
        script = step_script(AWS_DEPLOY, "Check backend deploy order")
        env = {
            "API_BASE_URL": "https://api.example.test",
            "SHA": "b" * 40,
            "SKIP": "false",
            "BACKEND_DEPLOY_ENABLED": enabled,
            "WAIT_SECONDS": "2700",
        }
        return self.run_step(script, env), order

    def test_backend_order_waits_then_passes(self) -> None:
        result, order = self.backend_order(
            [(10, "state=waiting\nbackend_sha=old\n"), (0, "state=deployed\nbackend_sha=new\n")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(order), 2)
        self.assertIn("- Backend order: deployed", self.summary.read_text(encoding="utf-8"))

    def test_backend_order_stops_when_backend_deploy_is_off(self) -> None:
        result, order = self.backend_order([(10, "state=waiting\nbackend_sha=old\n")], enabled="false")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls(order), 1)
        self.assertIn("BACKEND_DEPLOY_ENABLED", result.stdout)
        self.assertIn("- Backend order: waiting", self.summary.read_text(encoding="utf-8"))

    def test_backend_order_unknown_backend_sha(self) -> None:
        result, _ = self.backend_order([(11, "state=unknown\nbackend_sha=\n")])
        self.assertEqual(result.returncode, 1)
        self.assertIn("commit_sha", result.stdout)

    # --- 옛 커밋 재배포 가드(#3254): 종료 코드 20 이 건너뜀이다.
    def outputs(self) -> dict[str, str]:
        text = self.output.read_text(encoding="utf-8") if self.output.exists() else ""
        return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)

    def guard_env(self, extra: dict[str, str]) -> dict[str, str]:
        self.output = self.work / "github_output"
        runner_temp = self.work / "_runner_temp"
        runner_temp.mkdir(exist_ok=True)
        env = {"GITHUB_OUTPUT": str(self.output), "RUNNER_TEMP": str(runner_temp)}
        env.update(extra)
        return env

    def frontend_guard(self, event: str, outputs: list[tuple[int, str]]) -> subprocess.CompletedProcess:
        # 판정 스크립트는 `git show $GITHUB_SHA:…` 로 꺼낸다. 가짜 git 이 가짜 스크립트를 내준다.
        tool = self.work / "_fake_tool.sh"
        self.sequenced_stub(tool, outputs)
        self.git_calls = self.work / "git.calls"
        self.stub(self.bin / "git", f'echo "$*" >> "{self.git_calls.as_posix()}"\n'
                  f'[ "$1" = show ] && cat "{tool.as_posix()}"\n')
        script = step_script(AWS_DEPLOY, "Skip a release that is already live or older")
        env = self.guard_env({
            "EVENT_NAME": event,
            "DISTRIBUTION_ID": "E2EXAMPLE",
            "RELEASE_SHA": "c" * 40,
            "GITHUB_SHA": "d" * 40,
        })
        return self.run_step(script, env)

    def test_frontend_guard_skips_an_older_release(self) -> None:
        result = self.frontend_guard("workflow_run", [(20, "live_sha=" + "e" * 40 + "\nstate=older\n")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.outputs().get("deploy"), "false")
        summary = self.summary.read_text(encoding="utf-8")
        self.assertIn("deployment skipped", summary)
        self.assertIn("e" * 40, summary)
        self.assertIn("(older)", summary)
        self.assertIn("show " + "d" * 40 + ":.github/scripts/deploy_freshness.sh",
                      self.git_calls.read_text(encoding="utf-8"))

    def test_frontend_guard_deploys_a_newer_release(self) -> None:
        result = self.frontend_guard("workflow_run", [(0, "live_sha=" + "e" * 40 + "\nstate=newer\n")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.outputs().get("deploy"), "true")
        self.assertEqual(self.summary.read_text(encoding="utf-8"), "")

    def test_frontend_guard_fails_on_usage_error(self) -> None:
        result = self.frontend_guard("workflow_run", [(1, "")])
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("deploy", self.outputs())

    def test_frontend_guard_ignores_manual_runs(self) -> None:
        result = self.frontend_guard("workflow_dispatch", [(20, "state=older\n")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.outputs().get("deploy"), "true")
        self.assertFalse(self.git_calls.exists())

    def backend_guard(self, event: str, outputs: list[tuple[int, str]]) -> tuple[subprocess.CompletedProcess, Path]:
        tool = self.work / ".github" / "scripts" / "deploy_freshness.sh"
        self.sequenced_stub(tool, outputs)
        script = step_script(BACKEND_DEPLOY, "Skip a commit that is already live or older")
        env = self.guard_env({
            "EVENT_NAME": event,
            "API_BASE_URL": "https://api.example.test/v1",
            "SHA": "c" * 40,
        })
        return self.run_step(script, env), tool

    def test_backend_guard_skips_the_same_commit(self) -> None:
        result, tool = self.backend_guard("workflow_run", [(20, "live_sha=" + "c" * 40 + "\nstate=same\n")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(tool), 1)
        self.assertEqual(self.outputs().get("deploy"), "false")
        self.assertIn("Backend deployment skipped", self.summary.read_text(encoding="utf-8"))
        self.assertIn("(same)", self.summary.read_text(encoding="utf-8"))

    def test_backend_guard_deploys_when_live_commit_is_unknown(self) -> None:
        result, _ = self.backend_guard("workflow_run", [(0, "live_sha=none\nstate=unknown\n")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.outputs().get("deploy"), "true")

    def test_backend_guard_ignores_manual_runs(self) -> None:
        result, tool = self.backend_guard("workflow_dispatch", [(20, "state=older\n")])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(tool), 0)
        self.assertEqual(self.outputs().get("deploy"), "true")

    # --- backend-ci.yml: Audit locked dependencies
    def audit(self, write_json: bool, code: int) -> subprocess.CompletedProcess:
        backend = self.work / "backend"
        backend.mkdir()
        body = ""
        if write_json:
            body += 'printf \'%s\' \'{"dependencies": []}\' > audit.json\n'
        body += f"exit {code}\n"
        self.stub(self.bin / "pip-audit", body)
        script = step_script(BACKEND_CI, "Audit locked dependencies")
        return self.run_step(script, {}, cwd=backend)

    def test_audit_findings_reach_the_allowlist_step(self) -> None:
        result = self.audit(write_json=True, code=1)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("pip-audit exit code: 1", result.stdout)

    def test_audit_without_json_fails(self) -> None:
        result = self.audit(write_json=False, code=1)
        self.assertEqual(result.returncode, 1)
        self.assertIn("audit.json", result.stdout)


if __name__ == "__main__":
    unittest.main()
