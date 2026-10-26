"""백엔드 인프라 템플릿이 배포 규칙을 지키는지 본다(#3016, #3019, #3020).

cfn-lint 는 문법·리소스 스키마만 본다. 여기서는 이 서비스가 정한 규칙 —
태스크 수 범위와 공유 시도 제한 저장소, 첨부 버킷 접두사 권한, 배포 역할의 OIDC subject·PassRole 범위,
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
def test_task_count_defaults_to_one_and_can_scale_out(name: str) -> None:
    # 시도 제한이 DB 공유 저장소로 옮겨져(#3143) 태스크를 늘려도 한도가 느슨해지지 않는다.
    param = SERVICE["Parameters"][name]
    assert param["Default"] == 1
    assert "AllowedValues" not in param
    assert param["MinValue"] == 1
    # 상한은 DB 연결 수 계산(DEPLOY.md)이 감당하는 범위로 둔다.
    assert 1 < param["MaxValue"] <= 4
    assert _service_props()["ScalingTarget"][name] == {"Ref": name}


def test_rate_limit_uses_the_shared_database_store() -> None:
    # 태스크가 1 을 넘을 수 있으므로 시도 제한은 반드시 공유 저장소에 센다(#3143).
    env = _container_env()
    assert env["RATE_LIMIT_STORE"] == "database"
    assert env["RATE_LIMIT_ENABLED"] == "true"


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


def test_kakao_web_login_settings_are_optional() -> None:
    # 웹 카카오 로그인(#330): client_id 는 비밀이 아닌 파라미터, 시크릿은 켤 때만 비밀에서 읽는다.
    assert _conditional("Environment")["KAKAO_LOGIN_REST_API_KEY"] == "HasKakaoLoginRestApiKey"
    assert _conditional("Secrets")["KAKAO_CLIENT_SECRET"] == "HasKakaoClientSecret"
    assert "KAKAO_CLIENT_SECRET" not in _container_env()
    params = SERVICE["Parameters"]
    assert params["KakaoClientSecretEnabled"]["Default"] == "false"
    assert params["KakaoLoginRestApiKey"]["Default"] == ""


def test_apple_sign_in_settings_are_optional() -> None:
    # 애플 로그인(#3499): 허용 aud·팀 ID·키 ID 는 파라미터, .p8 키는 켤 때만 비밀에서 읽는다.
    env = _conditional("Environment")
    assert env["APPLE_CLIENT_IDS"] == "HasAppleClientIds"
    assert env["APPLE_TEAM_ID"] == "HasAppleTeamId"
    assert env["APPLE_KEY_ID"] == "HasAppleKeyId"
    assert _conditional("Secrets")["APPLE_PRIVATE_KEY"] == "HasAppleSignInKey"
    assert "APPLE_PRIVATE_KEY" not in _container_env()
    params = SERVICE["Parameters"]
    assert params["AppleSignInKeyEnabled"]["Default"] == "false"
    for name in ("AppleClientIds", "AppleTeamId", "AppleKeyId"):
        assert params[name]["Default"] == "", name


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


def _deploy_role_statements() -> tuple[list[dict], dict[str, dict]]:
    """배포 역할 문장을 (늘 있는 것, 운영에만 있는 것 Sid→문장) 으로 나눈다."""
    always: list[dict] = []
    production: dict[str, dict] = {}
    for stmt in statements(_role("GitHubBackendDeployRole")):
        if "Fn::If" in stmt:
            condition, then, otherwise = stmt["Fn::If"]
            assert condition == "IsProduction"
            assert otherwise == {"Ref": "AWS::NoValue"}
            production[then["Sid"]] = then
        else:
            always.append(stmt)
    return always, production


def test_github_deploy_role_has_no_direct_service_permissions() -> None:
    # 서비스 변경은 CloudFormation 이 한다. 운영 배포 직전 백업(#1552)만 예외로 아래에서 본다.
    always, _ = _deploy_role_statements()
    for stmt in always:
        for action in as_list(stmt["Action"]):
            assert action.startswith(("cloudformation:", "iam:PassRole")), action


def test_github_deploy_role_backup_permissions_are_production_only_and_narrow() -> None:
    # 운영 배포 직전 DB 백업(#1552): 백업 작업 하나를 띄우고 지켜보고 덤프 목록만 본다.
    _, production = _deploy_role_statements()
    assert set(production) == {
        "RunBackupTask", "WatchBackupTask", "StopBackupTask", "PassBackupTaskRoles", "CheckBackupObject",
        "ReadBackupLogs",
    }
    cluster = {"ArnEquals": {"ecs:cluster": {
        "Fn::Sub": "arn:${AWS::Partition}:ecs:${AWS::Region}:${AWS::AccountId}:cluster/${ServiceClusterName}"
    }}}
    run = production["RunBackupTask"]
    assert run["Action"] == "ecs:RunTask"
    assert run["Resource"]["Fn::Sub"].endswith(":task-definition/oncare-backend-${EnvironmentName}-db-backup:*")
    # 서비스 클러스터에서만 띄우고 멈출 수 있다.
    assert run["Condition"] == cluster
    stop = production["StopBackupTask"]
    assert stop["Action"] == "ecs:StopTask"
    assert stop["Condition"] == cluster
    watch = production["WatchBackupTask"]
    assert sorted(as_list(watch["Action"])) == ["ecs:DescribeServices", "ecs:DescribeTasks"]
    for resource in as_list(watch["Resource"]) + [stop["Resource"]]:
        assert ":${ServiceClusterName}/" in resource["Fn::Sub"].replace("service/", ":").replace("task/", ":")
    assert ENVIRONMENT["Parameters"]["ServiceClusterName"]["Default"] == "default"
    passes = production["PassBackupTaskRoles"]
    assert passes["Resource"] == [
        {"Fn::GetAtt": ["TaskExecutionRole", "Arn"]},
        {"Fn::GetAtt": ["BackupTaskRole", "Arn"]},
    ]
    assert passes["Condition"] == {"StringEquals": {"iam:PassedToService": "ecs-tasks.amazonaws.com"}}
    # 덤프 내용은 읽지 못한다 — 목록(크기)만.
    check = production["CheckBackupObject"]
    assert check["Action"] == "s3:ListBucket"
    assert check["Condition"]["StringLike"]["s3:prefix"] == "db/*"
    assert production["ReadBackupLogs"]["Action"] == "logs:GetLogEvents"
    for stmt in production.values():
        for action in as_list(stmt["Action"]):
            assert action != "s3:GetObject" and not action.endswith("*"), action


def test_github_deploy_role_passes_only_the_cloudformation_role() -> None:
    always, _ = _deploy_role_statements()
    passes = [s for s in always if s["Action"] == "iam:PassRole"]
    (stmt,) = passes
    assert stmt["Resource"] == {"Fn::GetAtt": ["CloudFormationDeployRole", "Arn"]}
    assert stmt["Condition"] == {"StringEquals": {"iam:PassedToService": "cloudformation.amazonaws.com"}}


def test_github_deploy_role_changes_only_its_service_stack() -> None:
    always, _ = _deploy_role_statements()
    by_sid = {s["Sid"]: s for s in always}
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
        {"Fn::If": ["IsProduction", {"Fn::GetAtt": ["BackupTaskRole", "Arn"]}, {"Ref": "AWS::NoValue"}]},
    ]


# ── 운영 DB 백업(#1552) ───────────────────────────────────────────────────


def test_backup_resources_exist_only_in_production() -> None:
    production = {"Fn::Equals": [{"Ref": "EnvironmentName"}, "production"]}
    assert ENVIRONMENT["Conditions"]["IsProduction"] == production
    assert SERVICE["Conditions"]["IsProduction"] == production
    for name in ("BackupBucket", "BackupBucketPolicy", "BackupLogGroup", "BackupTaskRole"):
        assert ENVIRONMENT["Resources"][name]["Condition"] == "IsProduction", name
    assert SERVICE["Resources"]["BackupTaskDefinition"]["Condition"] == "IsProduction"


def test_backup_bucket_is_private_encrypted_and_expires() -> None:
    bucket = ENVIRONMENT["Resources"]["BackupBucket"]
    assert bucket["DeletionPolicy"] == "Retain"
    props = bucket["Properties"]
    assert all(props["PublicAccessBlockConfiguration"].values())
    (encryption,) = props["BucketEncryption"]["ServerSideEncryptionConfiguration"]
    assert encryption["ServerSideEncryptionByDefault"]["SSEAlgorithm"] == "AES256"
    (rule,) = props["LifecycleConfiguration"]["Rules"]
    assert rule["Status"] == "Enabled"
    assert rule["ExpirationInDays"] == {"Ref": "BackupRetentionDays"}
    retention = ENVIRONMENT["Parameters"]["BackupRetentionDays"]
    assert retention["Default"] == 30
    assert retention["MaxValue"] <= 90
    # 버전 관리를 켜면 만료된 덤프가 이전 버전으로 남는다.
    assert "VersioningConfiguration" not in props
    (deny,) = ENVIRONMENT["Resources"]["BackupBucketPolicy"]["Properties"]["PolicyDocument"]["Statement"]
    assert deny["Effect"] == "Deny"
    assert deny["Condition"] == {"Bool": {"aws:SecureTransport": "false"}}


def test_backup_task_role_only_uploads_under_db_prefix() -> None:
    (stmt,) = statements(_role("BackupTaskRole"))
    assert sorted(as_list(stmt["Action"])) == ["s3:AbortMultipartUpload", "s3:PutObject"]
    assert stmt["Resource"] == {"Fn::Sub": "${BackupBucket.Arn}/db/*"}


def _backup_container() -> dict:
    (container,) = SERVICE["Resources"]["BackupTaskDefinition"]["Properties"]["ContainerDefinitions"]
    return container


def test_backup_task_uses_service_image_and_database_secret_only() -> None:
    props = SERVICE["Resources"]["BackupTaskDefinition"]["Properties"]
    # 워크플로(backend_db_backup.sh)·배포 역할 RunTask 범위와 같은 이름이어야 한다.
    assert props["Family"] == {"Fn::Sub": "oncare-backend-${EnvironmentName}-db-backup"}
    assert props["TaskRoleArn"] == {
        "Fn::ImportValue": {"Fn::Sub": "oncare-backend-${EnvironmentName}-BackupTaskRoleArn"}
    }
    container = _backup_container()
    assert container["Name"] == "db-backup"
    assert container["Image"] == {"Ref": "ImageIdentifier"}
    assert container["Command"] == ["python", "-m", "scripts.backup_db"]
    # 백업 작업에는 DB 주소만 넘긴다(JWT·AI 키 등은 쓰지 않는다).
    assert container["Secrets"] == [
        {"Name": "DATABASE_URL", "ValueFrom": {"Fn::Sub": "${SecretArn}:DATABASE_URL::"}}
    ]
    env = {item["Name"]: item["Value"] for item in container["Environment"]}
    assert env["BACKUP_S3_PREFIX"] == "db"
    assert container["LogConfiguration"]["Options"]["awslogs-stream-prefix"] == "db-backup"


def test_backup_outputs_feed_the_workflow() -> None:
    outputs = SERVICE["Outputs"]
    for name in ("BackupTaskDefinitionArn", "BackupBucketName", "BackupLogGroupName"):
        assert outputs[name]["Condition"] == "IsProduction", name
    assert outputs["ServiceArn"]["Value"] == {"Fn::GetAtt": ["BackendService", "ServiceArn"]}
    # 서비스 스택 출력의 이름은 환경 스택이 만든 리소스 이름과 같아야 한다.
    env = ENVIRONMENT["Resources"]
    assert outputs["BackupBucketName"]["Value"] == env["BackupBucket"]["Properties"]["BucketName"]
    assert outputs["BackupLogGroupName"]["Value"] == env["BackupLogGroup"]["Properties"]["LogGroupName"]
    script = (INFRA_DIR.parent / ".github" / "scripts" / "backend_db_backup.sh").read_text(encoding="utf-8")
    for name in ("BackupTaskDefinitionArn", "ServiceArn", "BackupBucketName", "BackupLogGroupName"):
        assert f" {name})" in script, name
    assert "CONTAINER=db-backup" in script


def test_backup_imports_exist_in_environment_stack() -> None:
    exported = {
        output["Export"]["Name"]["Fn::Sub"]
        for output in ENVIRONMENT["Outputs"].values()
        if "Export" in output
    }
    props = SERVICE["Resources"]["BackupTaskDefinition"]["Properties"]
    container = _backup_container()
    env = {item["Name"]: item["Value"] for item in container["Environment"]}
    imported = {
        props["ExecutionRoleArn"]["Fn::ImportValue"]["Fn::Sub"],
        props["TaskRoleArn"]["Fn::ImportValue"]["Fn::Sub"],
        env["BACKUP_S3_BUCKET"]["Fn::ImportValue"]["Fn::Sub"],
        container["LogConfiguration"]["Options"]["awslogs-group"]["Fn::ImportValue"]["Fn::Sub"],
    }
    assert imported <= exported


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
