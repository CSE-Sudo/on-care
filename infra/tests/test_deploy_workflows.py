"""운영 배포 잡이 GitHub Environment 에서 돌고, 데모 빌드가 운영 백엔드를 보지 않는지 본다(#3019, #3020).

배포 역할은 Environment 형식 OIDC subject 만 믿는다. 잡에서 `environment:` 가 빠지면 토큰의
subject 가 브랜치 형식이 되어 배포가 인증 단계에서 멈추고, 승인 규칙도 걸리지 않는다.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"


def _workflow(name: str) -> dict[str, Any]:
    with (WORKFLOWS / name).open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def _environment_name(job: dict[str, Any]) -> str:
    env = job.get("environment")
    return env["name"] if isinstance(env, dict) else env


def test_frontend_deploy_runs_in_production_environment() -> None:
    job = _workflow("aws-frontend-deploy.yml")["jobs"]["build-and-deploy"]
    assert _environment_name(job) == "production"


def test_backend_service_deploy_runs_in_its_environment() -> None:
    job = _workflow("backend-deploy-service.yml")["jobs"]["deploy"]
    assert _environment_name(job) == "${{ inputs.environment }}"


def test_backend_deploy_targets_production_and_staging_environments() -> None:
    jobs = _workflow("backend-deploy.yml")["jobs"]
    production = jobs["deploy-production"]
    staging = jobs["deploy-staging"]
    assert production["uses"] == staging["uses"] == "./.github/workflows/backend-deploy-service.yml"
    assert production["with"]["environment"] == "production"
    assert production["with"]["expected_env"] == "prod"
    assert staging["with"]["environment"] == "staging"
    assert staging["with"]["expected_env"] == "staging"
    # staging 이 실패하면 운영으로 가지 않는다.
    assert "deploy-staging" in production["needs"]
    assert "needs.deploy-staging.result == 'success'" in production["if"]


def test_backend_deploy_keeps_master_switch() -> None:
    resolve = _workflow("backend-deploy.yml")["jobs"]["resolve"]
    assert "vars.BACKEND_DEPLOY_ENABLED == 'true'" in resolve["if"]


def test_image_build_job_has_no_environment() -> None:
    # 이미지 푸시는 승인 전에 돈다. 브랜치 형식 subject 를 믿는 푸시 역할만 쓴다.
    build = _workflow("backend-deploy.yml")["jobs"]["build"]
    assert "environment" not in build
    steps = {step.get("name"): step for step in build["steps"]}
    creds = steps["Configure AWS credentials (image push)"]
    assert creds["with"]["role-to-assume"] == "${{ vars.AWS_BACKEND_IMAGE_PUSH_ROLE_ARN }}"


def _steps_text(workflow: str) -> str:
    return (WORKFLOWS / workflow).read_text(encoding="utf-8")


def test_demo_real_build_uses_staging_backend() -> None:
    text = _steps_text("deploy.yml")
    assert "vars.STAGING_API_BASE_URL" in text
    assert "FORBIDDEN_API_BASE_URL: ${{ vars.API_BASE_URL }}" in text
    # 빌드 단계는 운영 주소를 넘기지 않는다.
    assert not re.search(r"^\s+API_BASE_URL: \$\{\{ vars\.API_BASE_URL \}\}", text, re.MULTILINE)
    assert 'echo "WEB_ENV=staging"' in text


def test_production_frontend_rejects_staging_backend() -> None:
    text = _steps_text("aws-frontend-deploy.yml")
    assert "FORBIDDEN_API_BASE_URL: ${{ vars.STAGING_API_BASE_URL }}" in text


def _step(workflow: str, job: str, name: str) -> dict[str, Any]:
    steps = _workflow(workflow)["jobs"][job]["steps"]
    matches = [step for step in steps if step.get("name") == name]
    assert len(matches) == 1, f"{workflow}:{job} 에 '{name}' 단계가 하나여야 한다"
    return matches[0]


def test_frontend_prune_counts_release_roots_via_script() -> None:
    # 릴리스 정리는 릴리스 루트 단위로 세는 스크립트를 쓴다(#3128). 인라인으로
    # `*/version.txt` 키를 세면 앱 폴더의 version.txt(#3023)까지 릴리스로 세어
    # 직전 릴리스의 하위 폴더가 지워진다.
    step = _step("aws-frontend-deploy.yml", "build-and-deploy", "Prune old releases")
    run = step["run"]
    assert "bash .github/scripts/frontend_release_prune.sh prune" in run
    assert '"$RELEASE_SHA" "$PREVIOUS_ORIGIN_PATH"' in run
    assert "aws s3 rm" not in run
    assert "ends_with" not in run
    assert step["env"]["KEEP"] == "5"
    assert step["env"]["PREVIOUS_ORIGIN_PATH"] == "${{ steps.switch.outputs.previous_origin_path }}"
    # 실패한 배포에서는 정리하지 않는다(롤백 대상 보존).
    assert "if" not in step


def test_frontend_prune_script_normalizes_to_release_root() -> None:
    script = (WORKFLOWS.parent / "scripts" / "frontend_release_prune.sh").read_text(encoding="utf-8")
    # 키를 `releases/<40자 SHA>/` 루트로 줄여 세고, 지우기 직전에도 루트 형식만 허용한다.
    assert "releases/[0-9a-f]{40}/([^\\t]*/)?version\\\\.txt$" in script
    assert "^releases/[0-9a-f]{40}/$" in script
    assert "ROOT_PREFIX_LEN=50" in script


def test_frontend_prune_script_is_tested_in_ci() -> None:
    gate = (WORKFLOWS / "pr-gate.yml").read_text(encoding="utf-8")
    assert "bash .github/scripts/test_frontend_release_prune.sh" in gate
