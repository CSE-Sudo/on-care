"""CloudFormation 단축 태그(!Ref, !Sub …)를 읽는 YAML 로더.

PyYAML 기본 로더는 `!Ref` 같은 태그를 모른다. 검사에서는 태그 이름과 값만 알면 되므로
`{"Ref": ...}`·`{"Fn::Sub": ...}` 처럼 긴 형식으로 바꿔 읽는다.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

INFRA_DIR = Path(__file__).resolve().parents[1]

_TAGS = {
    "Ref": "Ref",
    "Condition": "Condition",
    "GetAtt": "Fn::GetAtt",
    "ImportValue": "Fn::ImportValue",
}
_FN_TAGS = [
    "And", "Base64", "Cidr", "Equals", "FindInMap", "GetAZs", "If", "Join",
    "Not", "Or", "Select", "Split", "Sub",
]


class CfnLoader(yaml.SafeLoader):
    pass


def _construct(key: str):
    def construct(loader: yaml.SafeLoader, node: yaml.Node) -> dict[str, Any]:
        if isinstance(node, yaml.ScalarNode):
            value: Any = loader.construct_scalar(node)
            if key == "Fn::GetAtt" and isinstance(value, str):
                value = value.split(".", 1)
        elif isinstance(node, yaml.SequenceNode):
            value = loader.construct_sequence(node, deep=True)
        else:
            value = loader.construct_mapping(node, deep=True)
        return {key: value}

    return construct


for _tag, _key in _TAGS.items():
    CfnLoader.add_constructor(f"!{_tag}", _construct(_key))
for _tag in _FN_TAGS:
    CfnLoader.add_constructor(f"!{_tag}", _construct(f"Fn::{_tag}"))


def load_template(name: str) -> dict[str, Any]:
    with (INFRA_DIR / name).open(encoding="utf-8") as handle:
        return yaml.load(handle, Loader=CfnLoader)  # noqa: S506 — SafeLoader 파생


def statements(role: dict[str, Any]) -> list[dict[str, Any]]:
    """IAM 역할 리소스의 인라인 정책 문장을 모두 꺼낸다."""
    found: list[dict[str, Any]] = []
    for policy in role["Properties"].get("Policies", []):
        found.extend(policy["PolicyDocument"]["Statement"])
    return found


def as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else [value]
