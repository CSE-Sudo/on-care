"""프런트 배포 역할의 OIDC subject(#3019)와 기본 오리진의 릴리스 경로 파라미터(#3129)를 본다."""
from __future__ import annotations

import re
from pathlib import Path

from cfn_yaml import load_template

TEMPLATE = load_template("frontend-hosting.yml")


def _trust() -> list:
    role = TEMPLATE["Resources"]["GitHubFrontendDeployRole"]
    return role["Properties"]["AssumeRolePolicyDocument"]["Statement"]


def test_environment_subject_is_trusted() -> None:
    environment = _trust()[0]
    assert environment["Sid"] == "TrustGitHubEnvironment"
    sub = environment["Condition"]["StringEqualsIgnoreCase"]["token.actions.githubusercontent.com:sub"]
    # ID 기반 subject 하나만 믿는다(#3089) — 이름 기반 선택지는 없다.
    assert sub["Fn::Sub"].startswith("repo:${GitHubOwner}@${GitHubOwnerId}/")
    assert sub["Fn::Sub"].endswith(":environment:${GitHubEnvironment}")
    assert TEMPLATE["Parameters"]["GitHubEnvironment"]["Default"] == "production"


def test_branch_subject_is_only_a_transition_option() -> None:
    branch = _trust()[1]["Fn::If"]
    assert branch[0] == "AllowBranchOidcSubjectCondition"
    assert branch[1]["Sid"] == "TrustMainBranchDuringMove"
    assert branch[2] == {"Ref": "AWS::NoValue"}
    assert TEMPLATE["Parameters"]["AllowBranchOidcSubject"]["AllowedValues"] == ["true", "false"]
    sub = branch[1]["Condition"]["StringEquals"]["token.actions.githubusercontent.com:sub"]
    assert sub["Fn::Sub"].startswith("repo:${GitHubOwner}@${GitHubOwnerId}/")


def test_name_based_subject_option_is_gone() -> None:
    assert "UseImmutableGitHubOidcSubject" not in TEMPLATE["Parameters"]
    assert "UseImmutableGitHubOidcSubjectCondition" not in TEMPLATE["Conditions"]


def test_audience_is_pinned_in_every_statement() -> None:
    statements = [_trust()[0], _trust()[1]["Fn::If"][1]]
    for statement in statements:
        assert statement["Condition"]["StringEquals"]["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"


def _origin() -> dict:
    distribution = TEMPLATE["Resources"]["FrontendDistribution"]["Properties"]["DistributionConfig"]
    origins = distribution["Origins"]
    assert len(origins) == 1
    assert distribution["DefaultCacheBehavior"]["TargetOriginId"] == origins[0]["Id"]
    return origins[0]


def test_default_origin_path_comes_from_release_parameter() -> None:
    # 스택 갱신이 배포 워크플로가 바꿔 둔 OriginPath 를 빈 값으로 덮어쓰지 않게(#3129).
    assert _origin()["OriginPath"] == {"Ref": "ReleaseOriginPath"}


def test_release_origin_path_only_allows_release_prefixes() -> None:
    parameter = TEMPLATE["Parameters"]["ReleaseOriginPath"]
    assert parameter["Type"] == "String"
    assert parameter["Default"] == ""
    pattern = re.compile(parameter["AllowedPattern"])
    sha = "0123456789abcdef0123456789abcdef01234567"
    for allowed in ["", f"/releases/{sha}"]:
        assert pattern.fullmatch(allowed), allowed
    for rejected in [
        "/",
        "/releases",
        "/releases/",
        f"/releases/{sha}/",
        f"releases/{sha}",
        f"/releases/{sha[:-1]}",
        f"/releases/{sha.upper()}",
        f"/releases/{sha}/trainer",
        "/frontend",
    ]:
        assert not pattern.fullmatch(rejected), rejected


def test_stack_update_script_passes_live_origin_path() -> None:
    root = Path(__file__).resolve().parents[2]
    script = (root / ".github" / "scripts" / "frontend_hosting_stack.sh").read_text(encoding="utf-8")
    # 살아 있는 distribution 에서 읽은 값을 언제나 넘기고, 사람이 직접 넘기는 값은 거부한다.
    assert "cloudfront get-distribution-config" in script
    assert '--parameter-overrides "ReleaseOriginPath=$path"' in script
    assert "ReleaseOriginPath=*)" in script
    # 스크립트의 형식 검사가 템플릿 패턴과 같다.
    assert f"ORIGIN_PATH_PATTERN='{TEMPLATE['Parameters']['ReleaseOriginPath']['AllowedPattern']}'" in script
    infra_ci = (root / ".github" / "workflows" / "infra-ci.yml").read_text(encoding="utf-8")
    assert ".github/scripts/test_frontend_hosting_stack.sh" in infra_ci
    # 배포 문서의 스택 갱신 절차가 이 스크립트를 쓴다.
    docs = (root / "docs" / "aws-frontend-deployment.md").read_text(encoding="utf-8")
    assert "bash .github/scripts/frontend_hosting_stack.sh deploy oncare-frontend" in docs
