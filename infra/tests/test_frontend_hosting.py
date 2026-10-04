"""프런트 배포 역할이 GitHub Environment 형식 OIDC subject 를 믿는지 본다(#3019)."""
from __future__ import annotations

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
