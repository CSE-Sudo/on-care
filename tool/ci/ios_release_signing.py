#!/usr/bin/env python3
"""회원 앱 IPA 서명 빌드에서 Runner 를 수동 서명으로 바꾸고 내보내기 설정을 만든다(#3148).

저장소의 Xcode 프로젝트는 개발자 PC 의 자동 서명(팀 계정 로그인)을 쓴다. CI 러너에는 Apple
계정이 없으므로 서명 빌드 워크플로(`.github/workflows/member-app-release.yml`)가 비밀로 받은
배포 인증서·프로비저닝 프로필로 **수동 서명**해야 한다. 이 스크립트는 러너의 작업 사본에서만
쓰이고, 고친 프로젝트 파일은 커밋되지 않는다.

하는 일
  1. 프로비저닝 프로필(`security cms -D` 로 푼 plist)에서 UUID·이름·팀 ID·앱 ID 를 읽고,
     앱 ID 가 `<팀 ID>.<번들 ID>` 인지 확인한다(다른 앱의 프로필이면 멈춘다).
  2. project.pbxproj 에서 번들 ID 가 정확히 그 값인 **Release** 빌드 설정 하나(Runner 타깃)에
     수동 서명 설정을 넣는다. Pods·RunnerTests·Debug·Profile 은 건드리지 않는다 — 명령줄로
     PROVISIONING_PROFILE_SPECIFIER 를 넘기면 모든 타깃에 걸려 Pods 빌드가 깨지기 때문이다.
  3. `flutter build ipa --export-options-plist=` 가 읽을 ExportOptions.plist 를 쓴다.

사용
  ios_release_signing.py --pbxproj <project.pbxproj> --profile-plist <풀어 둔 프로필 plist> \\
      --bundle-id com.csesudo.oncare --export-options <출력 plist>
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path

SIGNING_IDENTITY = "Apple Distribution"
# app-store-connect 는 Xcode 15.3 부터의 이름이다(이전 이름 app-store).
EXPORT_METHOD = "app-store-connect"
# 서명에 쓰는 설정 키. 이미 있으면 바꾸고, 없으면 넣는다.
MANAGED_KEYS = (
    "CODE_SIGN_STYLE",
    "CODE_SIGN_IDENTITY",
    '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"',
    "DEVELOPMENT_TEAM",
    "PROVISIONING_PROFILE_SPECIFIER",
)

UUID_PATTERN = re.compile(r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
TEAM_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
# `<id> /* Release */ = { isa = XCBuildConfiguration; ... name = Release; };` 한 블록.
CONFIG_BLOCK = re.compile(
    r"(?P<head>\t\t[0-9A-F]{24} /\* (?P<name>[^*]+) \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n)"
    r"(?P<body>.*?)"
    r"(?P<tail>\n\t\t\};\n)",
    re.DOTALL,
)
SETTINGS = re.compile(r"(?P<open>\t\t\tbuildSettings = \{\n)(?P<settings>.*?)(?P<close>\t\t\t\};\n)", re.DOTALL)


class SigningError(Exception):
    """프로필·프로젝트가 기대와 달라 서명 설정을 만들 수 없다."""


@dataclass(frozen=True)
class Profile:
    uuid: str
    name: str
    team_id: str
    app_id: str


def read_profile(data: bytes, bundle_id: str) -> Profile:
    """풀어 둔 프로비저닝 프로필 plist 를 읽고 이 앱의 배포용 프로필인지 확인한다."""
    try:
        plist = plistlib.loads(data)
    except Exception as exc:  # plistlib 은 형식마다 다른 예외를 낸다.
        raise SigningError(f"프로비저닝 프로필을 plist 로 읽지 못했습니다: {exc}") from exc
    uuid = str(plist.get("UUID", ""))
    name = str(plist.get("Name", ""))
    teams = plist.get("TeamIdentifier") or []
    team_id = str(teams[0]) if teams else ""
    app_id = str((plist.get("Entitlements") or {}).get("application-identifier", ""))
    if not UUID_PATTERN.match(uuid):
        raise SigningError(f"프로필 UUID 가 형식에 맞지 않습니다: {uuid!r}")
    if not name or '"' in name or "\n" in name:
        raise SigningError(f"프로필 이름을 쓸 수 없습니다: {name!r}")
    if not TEAM_PATTERN.match(team_id):
        raise SigningError(f"프로필 팀 ID 가 형식에 맞지 않습니다: {team_id!r}")
    if app_id != f"{team_id}.{bundle_id}":
        raise SigningError(
            f"프로필의 앱 ID {app_id!r} 가 {team_id}.{bundle_id} 가 아닙니다. 회원 앱용 프로필인지 확인하세요."
        )
    if (plist.get("Entitlements") or {}).get("get-task-allow") is True:
        raise SigningError("개발용 프로필(get-task-allow)입니다. App Store 배포용 프로필을 넣으세요.")
    if plist.get("ProvisionedDevices"):
        raise SigningError("기기 목록이 있는 프로필(Ad Hoc·개발용)입니다. App Store 배포용 프로필을 넣으세요.")
    return Profile(uuid=uuid, name=name, team_id=team_id, app_id=app_id)


def _set(settings: str, key: str, value: str) -> str:
    line = f"\t\t\t\t{key} = {value};\n"
    pattern = re.compile(rf"^\t\t\t\t{re.escape(key)} = .*;\n", re.MULTILINE)
    if pattern.search(settings):
        return pattern.sub(lambda _m: line, settings, count=1)
    return settings + line


def apply_manual_signing(pbxproj: str, bundle_id: str, profile: Profile) -> str:
    """번들 ID 가 bundle_id 인 Release 빌드 설정 하나에만 수동 서명 설정을 넣는다."""
    bundle_line = re.compile(rf"^\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {re.escape(bundle_id)};$", re.MULTILINE)
    matches = [
        m for m in CONFIG_BLOCK.finditer(pbxproj)
        if m.group("name") == "Release" and bundle_line.search(m.group("body"))
    ]
    if len(matches) != 1:
        raise SigningError(
            f"번들 ID {bundle_id} 의 Release 빌드 설정을 정확히 하나 찾지 못했습니다(찾은 수: {len(matches)})."
        )
    block = matches[0]
    settings_match = SETTINGS.search(block.group("body"))
    if settings_match is None:
        raise SigningError("Runner Release 빌드 설정에 buildSettings 가 없습니다.")
    settings = settings_match.group("settings")
    values = {
        "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY": f'"{SIGNING_IDENTITY}"',
        '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"': f'"{SIGNING_IDENTITY}"',
        "DEVELOPMENT_TEAM": profile.team_id,
        "PROVISIONING_PROFILE_SPECIFIER": f'"{profile.uuid}"',
    }
    for key in MANAGED_KEYS:
        settings = _set(settings, key, values[key])
    # pbxproj 는 키 순서가 정렬돼 있다. Xcode 가 다시 써도 같은 모양이 되도록 맞춘다.
    lines = settings.splitlines(keepends=True)
    settings = "".join(_sorted_setting_lines(lines))
    body = block.group("body")
    body = body[: settings_match.start("settings")] + settings + body[settings_match.end("settings"):]
    return pbxproj[: block.start("body")] + body + pbxproj[block.end("body"):]


def _sorted_setting_lines(lines: list[str]) -> list[str]:
    """한 줄 설정과 여러 줄 설정(`KEY = (` … `);`)을 키 이름순으로 정렬한다."""
    entries: list[list[str]] = []
    for line in lines:
        if line.startswith("\t\t\t\t") and not line.startswith("\t\t\t\t\t") and not line.startswith("\t\t\t\t);"):
            entries.append([line])
        elif entries:
            entries[-1].append(line)
        else:
            entries.append([line])

    def key(entry: list[str]) -> str:
        return entry[0].strip().strip('"').split(" = ", 1)[0].strip('"')

    return [line for entry in sorted(entries, key=key) for line in entry]


def export_options(bundle_id: str, profile: Profile) -> bytes:
    return plistlib.dumps(
        {
            "method": EXPORT_METHOD,
            "destination": "export",
            "signingStyle": "manual",
            "signingCertificate": SIGNING_IDENTITY,
            "teamID": profile.team_id,
            "provisioningProfiles": {bundle_id: profile.uuid},
            "manageAppVersionAndBuildNumber": False,
            "uploadSymbols": True,
        }
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pbxproj", type=Path, required=True)
    parser.add_argument("--profile-plist", type=Path, required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--export-options", type=Path, required=True)
    args = parser.parse_args(argv)

    try:
        profile = read_profile(args.profile_plist.read_bytes(), args.bundle_id)
        patched = apply_manual_signing(args.pbxproj.read_text(encoding="utf-8"), args.bundle_id, profile)
    except (OSError, SigningError) as exc:
        print(f"::error title=iOS signing::{exc}", file=sys.stderr)
        return 1
    args.pbxproj.write_text(patched, encoding="utf-8")
    args.export_options.write_bytes(export_options(args.bundle_id, profile))
    # UUID·이름은 비밀이 아니다. 어떤 프로필로 서명했는지 빌드 정보에 남기려고 출력한다.
    print(f"profile_uuid={profile.uuid}")
    print(f"profile_name={profile.name}")
    print(f"team_id={profile.team_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
