"""백엔드 인프라 템플릿이 배포 규칙을 지키는지 본다(#3016, #3019, #3020).

cfn-lint 는 문법·리소스 스키마만 본다. 여기서는 이 서비스가 정한 규칙 —
태스크 1 고정, 첨부 버킷 접두사 권한, 배포 역할의 OIDC subject·PassRole 범위,
운영에서 데모 설정이 꺼지는지 — 를 검사한다.
"""
from __future__ import annotations

import re

import pytest

from cfn_yaml import INFRA_DIR, as_list, load_template, statements

SERVICE = load_template("backend-service.yml")
ENVIRONMENT = load_template("backend-environment.yml")
BOOTSTRAP = load_template("backend-bootstrap.yml")


def _service_props() -> dict:
    return SERVICE["Resources"]["BackendService"]["Properties"]


def _container_env() -> dict[str, object]:
    env: dict[str, object] = {}
    for item in _service_props()["PrimaryContainer"]["Environment"]:
        if "Fn::If" in item:
            item = item["Fn::If"][1]
        env[item["Name"]] = item["Value"]
    return env


def _container_secrets() -> dict[str, object]:
    secrets: dict[str, object] = {}
    for item in _service_props()["PrimaryContainer"]["Secrets"]:
        if "Fn::If" in item:
            item = item["Fn::If"][1]
        secrets[item["Name"]] = item["ValueFrom"]
    return secrets


# ── 서비스 ────────────────────────────────────────────────────────────────


def test_service_is_express_gateway_service() -> None:
    assert SERVICE["Resources"]["BackendService"]["Type"] == "AWS::ECS::ExpressGatewayService"


@pytest.mark.parametrize("name", ["MinTaskCount", "MaxTaskCount"])
def test_task_count_is_pinned_to_one(name: str) -> None:
    # 시도 제한이 프로세스 메모리에 있어 태스크가 늘면 한도가 느슨해진다.
    param = SERVICE["Parameters"][name]
    assert param["Default"] == 1
    assert param["AllowedValues"] == [1]
    assert _service_props()["ScalingTarget"][name] == {"Ref": name}


def test_single_worker_and_one_proxy_hop() -> None:
    env = _container_env()
    assert env["WEB_CONCURRENCY"] == "1"
    assert env["TRUSTED_PROXY_HOPS"] == "1"


def test_health_check_uses_process_only_endpoint() -> None:
    assert _service_props()["HealthCheckPath"] == "/v1/healthz"
    assert _service_props()["PrimaryContainer"]["ContainerPort"] == 8000


def test_image_must_be_a_digest() -> None:
    pattern = re.compile(SERVICE["Parameters"]["ImageIdentifier"]["AllowedPattern"])
    digest = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/oncare-backend@sha256:" + "a" * 64
    assert pattern.match(digest)
    assert not pattern.match("123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/oncare-backend:latest")
    assert not pattern.match("123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/other@sha256:" + "a" * 64)


def test_production_turns_demo_settings_off() -> None:
    settings = SERVICE["Mappings"]["EnvironmentSettings"]
    assert settings["production"] == {"AppEnv": "prod", "SeedDemoData": "false"}
    assert settings["staging"]["AppEnv"] == "staging"
    env = _container_env()
    assert env["AUTO_CREATE_TABLES"] == "false"
    # 데모 폴백은 staging 일 때만 파라미터를 따르고, 운영은 늘 false.
    fallback = next(
        item for item in _service_props()["PrimaryContainer"]["Environment"]
        if item.get("Name") == "ALLOW_DEMO_FALLBACK"
    )
    assert fallback["Value"] == {"Fn::If": ["IsStaging", {"Ref": "AllowDemoFallback"}, "false"]}


def _conditional(kind: str) -> dict[str, str]:
    """조건부 항목 이름 → 조건 이름."""
    return {
        item["Fn::If"][1]["Name"]: item["Fn::If"][0]
        for item in _service_props()["PrimaryContainer"][kind]
        if "Fn::If" in item
    }


def test_demo_password_secret_is_staging_only() -> None:
    assert _conditional("Secrets")["DEMO_LOGIN_PASSWORD"] == "IsStaging"


def test_mail_settings_are_all_or_nothing() -> None:
    # 비밀에 없는 키를 참조하면 태스크가 뜨지 않으므로 SMTP 키는 메일을 켤 때만 읽는다.
    secrets = _conditional("Secrets")
    assert secrets["SMTP_USERNAME"] == "HasMail"
    assert secrets["SMTP_PASSWORD"] == "HasMail"
    env = _conditional("Environment")
    for name in ("MAIL_PROVIDER", "MAIL_FROM", "SMTP_HOST", "SMTP_PORT"):
        assert env[name] == "HasMail", name


def test_attachments_go_to_the_environment_bucket() -> None:
    env = _container_env()
    assert env["ATTACHMENT_STORAGE"] == "s3"
    assert env["ATTACHMENT_S3_BUCKET"] == {
        "Fn::ImportValue": {"Fn::Sub": "oncare-backend-${EnvironmentName}-AttachmentBucket"}
    }
    assert env["ATTACHMENT_S3_PREFIX"] == ENVIRONMENT["Parameters"]["AttachmentPrefix"]["Default"]


def test_secrets_reference_json_keys_of_one_secret() -> None:
    for name, value_from in _container_secrets().items():
        assert value_from == {"Fn::Sub": f"${{SecretArn}}:{name}::"}, name


def test_secret_arn_is_scoped_to_environment_name() -> None:
    pattern = re.compile(SERVICE["Parameters"]["SecretArn"]["AllowedPattern"])
    assert pattern.match("arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:oncare/backend/production-AbC123")
    assert not pattern.match("arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:oncare/backend/production")
    assert not pattern.match("arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:other-AbC123")


def test_cors_rejects_wildcards_and_plain_http() -> None:
    pattern = re.compile(SERVICE["Parameters"]["CorsAllowOrigins"]["AllowedPattern"])
    assert pattern.match("https://trainer.example.com,https://app.example.com")
    assert not pattern.match("*")
    assert not pattern.match("http://trainer.example.com")
    assert not pattern.match("https://*.example.com")


def test_service_outputs_feed_the_deploy_workflow() -> None:
    outputs = SERVICE["Outputs"]
    assert outputs["ServiceEndpoint"]["Value"] == {"Fn::GetAtt": ["BackendService", "Endpoint"]}
    assert outputs["ImageIdentifier"]["Value"] == {"Ref": "ImageIdentifier"}


def test_service_imports_exist_in_environment_stack() -> None:
    exported = {
        output["Export"]["Name"]["Fn::Sub"]
        for output in ENVIRONMENT["Outputs"].values()
        if "Export" in output
    }
    props = _service_props()
    imported = {
        props[key]["Fn::ImportValue"]["Fn::Sub"]
        for key in ("ExecutionRoleArn", "TaskRoleArn", "InfrastructureRoleArn")
    }
    imported.add(_container_env()["ATTACHMENT_S3_BUCKET"]["Fn::ImportValue"]["Fn::Sub"])
    assert imported <= exported


# ── 환경 스택 ─────────────────────────────────────────────────────────────


def _role(name: str) -> dict:
    return ENVIRONMENT["Resources"][name]


def test_task_role_is_limited_to_attachment_prefix() -> None:
    by_sid = {s["Sid"]: s for s in statements(_role("TaskRole"))}
    objects = by_sid["AttachmentObjects"]
    assert sorted(as_list(objects["Action"])) == ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    assert objects["Resource"] == {"Fn::Sub": "${AttachmentBucket.Arn}/${AttachmentPrefix}/*"}
    listing = by_sid["AttachmentListing"]
    assert listing["Action"] == "s3:ListBucket"
    assert listing["Condition"]["StringLike"]["s3:prefix"] == {"Fn::Sub": "${AttachmentPrefix}/*"}
    assert set(by_sid) == {"AttachmentObjects", "AttachmentListing"}


def test_attachment_bucket_is_private() -> None:
    bucket = ENVIRONMENT["Resources"]["AttachmentBucket"]
    assert bucket["DeletionPolicy"] == "Retain"
    block = bucket["Properties"]["PublicAccessBlockConfiguration"]
    assert all(block.values())
    policy = ENVIRONMENT["Resources"]["AttachmentBucketPolicy"]["Properties"]["PolicyDocument"]
    deny = policy["Statement"][0]
    assert deny["Effect"] == "Deny"
    assert deny["Condition"] == {"Bool": {"aws:SecureTransport": "false"}}


def test_execution_role_reads_only_its_environment_secret() -> None:
    (stmt,) = statements(_role("TaskExecutionRole"))
    assert stmt["Action"] == "secretsmanager:GetSecretValue"
    assert stmt["Resource"]["Fn::Sub"].endswith(":secret:oncare/backend/${EnvironmentName}-*")


def test_github_deploy_role_trusts_only_its_environment() -> None:
    trust = _role("GitHubBackendDeployRole")["Properties"]["AssumeRolePolicyDocument"]["Statement"]
    (stmt,) = trust
    condition = stmt["Condition"]
    assert condition["StringEquals"] == {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"}
    sub = condition["StringEqualsIgnoreCase"]["token.actions.githubusercontent.com:sub"]["Fn::Sub"]
    assert sub.endswith(":environment:${EnvironmentName}")
    assert "*" not in sub
    assert ":ref:" not in sub


def test_github_deploy_role_has_no_direct_service_permissions() -> None:
    for stmt in statements(_role("GitHubBackendDeployRole")):
        for action in as_list(stmt["Action"]):
            assert action.startswith(("cloudformation:", "iam:PassRole")), action


def test_github_deploy_role_passes_only_the_cloudformation_role() -> None:
    passes = [s for s in statements(_role("GitHubBackendDeployRole")) if s["Action"] == "iam:PassRole"]
    (stmt,) = passes
    assert stmt["Resource"] == {"Fn::GetAtt": ["CloudFormationDeployRole", "Arn"]}
    assert stmt["Condition"] == {"StringEquals": {"iam:PassedToService": "cloudformation.amazonaws.com"}}


def test_github_deploy_role_changes_only_its_service_stack() -> None:
    by_sid = {s["Sid"]: s for s in statements(_role("GitHubBackendDeployRole"))}
    resources = as_list(by_sid["ApplyServiceStack"]["Resource"])
    assert [r["Fn::Sub"] for r in resources] == [
        "arn:${AWS::Partition}:cloudformation:${AWS::Region}:${AWS::AccountId}:stack/oncare-backend-${EnvironmentName}/*"
    ]
    assert "cloudformation:DeleteStack" not in as_list(by_sid["ApplyServiceStack"]["Action"])


def test_cloudformation_role_passes_only_service_roles() -> None:
    passes = [s for s in statements(_role("CloudFormationDeployRole")) if s["Action"] == "iam:PassRole"]
    (stmt,) = passes
    assert stmt["Resource"] == [
        {"Fn::GetAtt": ["TaskExecutionRole", "Arn"]},
        {"Fn::GetAtt": ["TaskRole", "Arn"]},
        {"Fn::GetAtt": ["InfrastructureRole", "Arn"]},
    ]


def test_stack_name_output_matches_deploy_role_scope() -> None:
    assert ENVIRONMENT["Outputs"]["ServiceStackName"]["Value"] == {"Fn::Sub": "oncare-backend-${EnvironmentName}"}


# ── 공용 스택 ─────────────────────────────────────────────────────────────


def test_image_push_role_trusts_main_branch_and_only_pushes() -> None:
    role = BOOTSTRAP["Resources"]["GitHubBackendImagePushRole"]
    (trust,) = role["Properties"]["AssumeRolePolicyDocument"]["Statement"]
    sub = trust["Condition"]["StringEquals"]["token.actions.githubusercontent.com:sub"]["Fn::Sub"]
    assert sub.endswith(":ref:refs/heads/${GitHubBranch}")
    for stmt in statements(role):
        for action in as_list(stmt["Action"]):
            assert action.startswith("ecr:"), action


def test_no_app_runner_left_in_backend_templates() -> None:
    for name in ("backend-bootstrap.yml", "backend-environment.yml", "backend-service.yml"):
        text = (INFRA_DIR / name).read_text(encoding="utf-8")
        assert "apprunner" not in text.lower(), name


def test_ecr_tags_are_immutable_and_rollback_images_kept() -> None:
    repo = BOOTSTRAP["Resources"]["BackendRepository"]["Properties"]
    assert repo["ImageTagMutability"] == "IMMUTABLE"
    assert '"countNumber": 20' in repo["LifecyclePolicy"]["LifecyclePolicyText"]
