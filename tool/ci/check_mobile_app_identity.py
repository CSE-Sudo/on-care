#!/usr/bin/env python3
"""회원 앱의 앱 ID·홈 화면 이름·릴리스 서명 설정이 플랫폼마다 같은지 검사한다(#2823).

앱 ID 는 스토어 등록 뒤 바꿀 수 없고, 홈 화면 이름은 Android·iOS·웹이 따로 적혀 있어
한 곳만 고치면 금방 어긋난다. 그래서 확정한 값을 여기 한 곳에 두고 아래를 확인한다.

앱 ID (`EXPECTED_APP_ID`)
  - Android `android/app/build.gradle.kts` 의 `applicationId`·`namespace`
  - Kotlin `MainActivity.kt` 의 `package` 선언과 디렉터리 경로
  - iOS `ios/Runner.xcodeproj/project.pbxproj` 의 `PRODUCT_BUNDLE_IDENTIFIER`
    (Runner 는 앱 ID 그대로, RunnerTests 는 `<앱 ID>.RunnerTests`)

홈 화면 이름 (`EXPECTED_APP_NAME`)
  - Android `AndroidManifest.xml` 의 `<application android:label>`
  - iOS `Info.plist` 의 `CFBundleDisplayName`·`CFBundleName`
  - 웹 `web/manifest.json` 의 `name`·`short_name`, `web/index.html` 의
    `apple-mobile-web-app-title`

릴리스 서명
  - `release` 빌드 유형이 디버그 키(`signingConfigs.getByName("debug")`)를 쓰지 않고
    `key.properties` 를 읽는 `release` 서명 설정을 쓰는지

값을 바꿀 때는 위 파일들과 이 파일의 상수를 함께 고친다(docs/mobile_release.md).
외부 파서 없이 표준 라이브러리만 쓴다 — 러너에 추가 설치 없이 돌게 하기 위해서다.

사용법:
  check_mobile_app_identity.py [회원 앱 경로]
경로를 주지 않으면 `frontend/flutter` 를 본다. 어긋난 곳이 있으면 GitHub Actions
주석(`::error file=...::`)을 찍고 1 로 끝난다.
"""

from __future__ import annotations

import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path

EXPECTED_APP_ID = "com.csesudo.oncare"
EXPECTED_APP_NAME = "On-Care"
RUNNER_TESTS_SUFFIX = ".RunnerTests"

DEFAULT_APP_DIR = Path("frontend/flutter")

GRADLE = Path("android/app/build.gradle.kts")
KOTLIN_ROOT = Path("android/app/src/main/kotlin")
ANDROID_MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
PBXPROJ = Path("ios/Runner.xcodeproj/project.pbxproj")
INFO_PLIST = Path("ios/Runner/Info.plist")
WEB_MANIFEST = Path("web/manifest.json")
WEB_INDEX = Path("web/index.html")

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


class Problem:
    def __init__(self, file: Path, message: str) -> None:
        self.file = file
        self.message = message

    def __repr__(self) -> str:  # 테스트 실패 메시지용
        return f"Problem({self.file}, {self.message!r})"


def _gradle_value(text: str, key: str) -> str | None:
    match = re.search(rf'^\s*{key}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    return match.group(1) if match else None


def _release_block(text: str) -> str | None:
    """`buildTypes { release { ... } }` 의 본문을 중괄호 짝을 맞춰 꺼낸다."""
    build_types = re.search(r"\bbuildTypes\s*\{", text)
    if not build_types:
        return None
    release = re.search(r"\brelease\s*\{", text[build_types.end():])
    if not release:
        return None
    start = build_types.end() + release.end()
    depth = 1
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start:index]
    return None


def check_android(app_dir: Path) -> list[Problem]:
    problems: list[Problem] = []
    gradle_text = (app_dir / GRADLE).read_text(encoding="utf-8")
    for key in ("applicationId", "namespace"):
        value = _gradle_value(gradle_text, key)
        if value != EXPECTED_APP_ID:
            problems.append(
                Problem(GRADLE, f"{key} 가 `{value}` 입니다. `{EXPECTED_APP_ID}` 여야 합니다")
            )

    release = _release_block(gradle_text)
    if release is None:
        problems.append(Problem(GRADLE, "buildTypes 의 release 블록을 찾지 못했습니다"))
    else:
        if 'getByName("debug")' in release:
            problems.append(
                Problem(GRADLE, "release 빌드가 디버그 키로 서명됩니다. release 서명 설정을 쓰세요")
            )
        if 'signingConfigs.getByName("release")' not in release:
            problems.append(
                Problem(GRADLE, "release 빌드가 `signingConfigs.getByName(\"release\")` 를 쓰지 않습니다")
            )
    if 'rootProject.file("key.properties")' not in gradle_text:
        problems.append(Problem(GRADLE, "release 서명이 android/key.properties 를 읽지 않습니다"))
    if "GradleException" not in gradle_text:
        problems.append(
            Problem(GRADLE, "서명 설정이 없을 때 릴리스 빌드를 멈추는 가드(GradleException)가 없습니다")
        )

    activities = sorted((app_dir / KOTLIN_ROOT).rglob("MainActivity.kt"))
    if len(activities) != 1:
        problems.append(
            Problem(KOTLIN_ROOT, f"MainActivity.kt 가 {len(activities)}개입니다. 앱 ID 경로 아래 하나여야 합니다")
        )
    for activity in activities:
        relative = activity.relative_to(app_dir)
        package_path = ".".join(activity.parent.relative_to(app_dir / KOTLIN_ROOT).parts)
        if package_path != EXPECTED_APP_ID:
            problems.append(
                Problem(relative, f"Kotlin 패키지 경로가 `{package_path}` 입니다. `{EXPECTED_APP_ID}` 여야 합니다")
            )
        declared = re.search(r"^\s*package\s+([\w.]+)", activity.read_text(encoding="utf-8"), re.MULTILINE)
        declared_value = declared.group(1) if declared else None
        if declared_value != EXPECTED_APP_ID:
            problems.append(
                Problem(relative, f"package 선언이 `{declared_value}` 입니다. `{EXPECTED_APP_ID}` 여야 합니다")
            )

    manifest = ET.parse(app_dir / ANDROID_MANIFEST).getroot()
    application = manifest.find("application")
    label = application.get(f"{ANDROID_NS}label") if application is not None else None
    if label != EXPECTED_APP_NAME:
        problems.append(
            Problem(ANDROID_MANIFEST, f"android:label 이 `{label}` 입니다. `{EXPECTED_APP_NAME}` 여야 합니다")
        )
    return problems


def check_ios(app_dir: Path) -> list[Problem]:
    problems: list[Problem] = []
    pbxproj = (app_dir / PBXPROJ).read_text(encoding="utf-8")
    bundle_ids = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*\"?([^\";]+)\"?;", pbxproj)
    allowed = {EXPECTED_APP_ID, EXPECTED_APP_ID + RUNNER_TESTS_SUFFIX}
    for bundle_id in sorted(set(bundle_ids) - allowed):
        problems.append(
            Problem(PBXPROJ, f"번들 ID `{bundle_id}` 가 앱 ID `{EXPECTED_APP_ID}` 와 다릅니다")
        )
    if EXPECTED_APP_ID not in bundle_ids:
        problems.append(Problem(PBXPROJ, f"Runner 번들 ID `{EXPECTED_APP_ID}` 가 없습니다"))

    with (app_dir / INFO_PLIST).open("rb") as handle:
        info = plistlib.load(handle)
    for key in ("CFBundleDisplayName", "CFBundleName"):
        if info.get(key) != EXPECTED_APP_NAME:
            problems.append(
                Problem(INFO_PLIST, f"{key} 가 `{info.get(key)}` 입니다. `{EXPECTED_APP_NAME}` 여야 합니다")
            )
    return problems


class _MetaCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.meta: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "meta":
            return
        values = dict(attrs)
        name = values.get("name")
        if name:
            self.meta[name] = values.get("content") or ""


def check_web(app_dir: Path) -> list[Problem]:
    problems: list[Problem] = []
    manifest = json.loads((app_dir / WEB_MANIFEST).read_text(encoding="utf-8"))
    for key in ("name", "short_name"):
        if manifest.get(key) != EXPECTED_APP_NAME:
            problems.append(
                Problem(WEB_MANIFEST, f"{key} 가 `{manifest.get(key)}` 입니다. `{EXPECTED_APP_NAME}` 여야 합니다")
            )

    collector = _MetaCollector()
    collector.feed((app_dir / WEB_INDEX).read_text(encoding="utf-8"))
    title = collector.meta.get("apple-mobile-web-app-title")
    if title != EXPECTED_APP_NAME:
        problems.append(
            Problem(WEB_INDEX, f"apple-mobile-web-app-title 이 `{title}` 입니다. `{EXPECTED_APP_NAME}` 여야 합니다")
        )
    return problems


def check(app_dir: Path) -> list[Problem]:
    return check_android(app_dir) + check_ios(app_dir) + check_web(app_dir)


def main(argv: list[str]) -> int:
    app_dir = Path(argv[0]) if argv else DEFAULT_APP_DIR
    problems = check(app_dir)
    for problem in problems:
        print(f"::error file={app_dir / problem.file}::{problem.message}")
    if problems:
        print(f"앱 ID·앱 이름·서명 설정이 어긋난 곳 {len(problems)}건 (docs/mobile_release.md).")
        return 1
    print(f"앱 ID `{EXPECTED_APP_ID}`, 앱 이름 `{EXPECTED_APP_NAME}` — Android·iOS·웹 일치, 릴리스 서명 설정 확인.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
