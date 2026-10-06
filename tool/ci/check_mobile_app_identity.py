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

실행 화면 (#3153) — Flutter 첫 화면 전에 보이는 네이티브 화면이 템플릿의 빈 화면이 아닌지
  - Android `drawable`·`drawable-v21` 의 `launch_background.xml` 에 로고 비트맵 항목이
    살아 있고(템플릿은 주석 처리), 가리키는 그림이 밀도별 폴더에 실제로 있는지
  - Android 12 이상용 `values-v31`·`values-night-v31` 의 `LaunchTheme` 에
    `windowSplashScreenBackground`·`windowSplashScreenAnimatedIcon` 이 있는지
  - iOS `LaunchImage` 세트의 그림이 1×1 자리표시가 아니고(최소 48pt), 배율끼리
    같은 크기인지, `LaunchScreen.storyboard` 가 그 세트를 쓰는지

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
import struct
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

ANDROID_RES = Path("android/app/src/main/res")
LAUNCH_BACKGROUNDS = (
    ANDROID_RES / "drawable" / "launch_background.xml",
    ANDROID_RES / "drawable-v21" / "launch_background.xml",
)
SPLASH_STYLES_V31 = (
    ANDROID_RES / "values-v31" / "styles.xml",
    # 밤 모드 한정자가 API 한정자보다 앞서므로, 밤 모드 기기는 values-v31 이 아니라 이
    # 폴더를 읽는다. 여기에 빠지면 밤 모드 Android 12 기기만 기본 화면이 뜬다.
    ANDROID_RES / "values-night-v31" / "styles.xml",
)
SPLASH_ATTRIBUTES = (
    "android:windowSplashScreenBackground",
    "android:windowSplashScreenAnimatedIcon",
)
LAUNCH_IMAGESET = Path("ios/Runner/Assets.xcassets/LaunchImage.imageset")
LAUNCH_STORYBOARD = Path("ios/Runner/Base.lproj/LaunchScreen.storyboard")
# 실행 화면 로고의 최소 크기(pt). 템플릿 자리표시는 1×1 이다.
MIN_LAUNCH_IMAGE_POINTS = 48
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


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


def png_size(path: Path) -> tuple[int, int] | None:
    """PNG 의 IHDR 에서 (가로, 세로) 픽셀을 읽는다. PNG 가 아니면 None."""
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def _android_resource_files(app_dir: Path, reference: str) -> list[Path]:
    """`@drawable/이름`·`@mipmap/이름` 이 가리키는 파일들(밀도·버전 폴더 전부)."""
    match = re.fullmatch(r"@(drawable|mipmap)/(\w+)", reference)
    if not match:
        return []
    kind, name = match.groups()
    found: list[Path] = []
    for folder in sorted((app_dir / ANDROID_RES).glob(f"{kind}*")):
        found.extend(sorted(folder.glob(f"{name}.*")))
    return found


def check_launch_screen(app_dir: Path) -> list[Problem]:
    problems: list[Problem] = []

    for relative in LAUNCH_BACKGROUNDS:
        path = app_dir / relative
        if not path.exists():
            problems.append(Problem(relative, "실행 화면 배경 파일이 없습니다"))
            continue
        # 주석은 파서가 버린다 — 템플릿처럼 로고 항목을 주석으로 남겨 두면 비트맵이 없다.
        bitmaps = [
            element.get(f"{ANDROID_NS}src")
            for element in ET.parse(path).getroot().iter("bitmap")
        ]
        sources = [source for source in bitmaps if source]
        if not sources:
            problems.append(
                Problem(relative, "실행 화면에 로고 비트맵 항목이 없습니다(템플릿의 흰 화면 그대로입니다)")
            )
            continue
        for source in sources:
            files = _android_resource_files(app_dir, source)
            if not files:
                problems.append(Problem(relative, f"로고 비트맵 `{source}` 의 그림 파일이 없습니다"))
                continue
            for image in files:
                if image.suffix != ".png":
                    continue
                size = png_size(image)
                if size is None or min(size) < MIN_LAUNCH_IMAGE_POINTS:
                    problems.append(
                        Problem(
                            image.relative_to(app_dir),
                            f"실행 화면 로고가 {size} 픽셀입니다. 자리표시가 아닌 실제 로고여야 합니다",
                        )
                    )

    for relative in SPLASH_STYLES_V31:
        path = app_dir / relative
        if not path.exists():
            problems.append(Problem(relative, "Android 12 이상 실행 화면 스타일 파일이 없습니다"))
            continue
        launch = [
            style
            for style in ET.parse(path).getroot().iter("style")
            if style.get("name") == "LaunchTheme"
        ]
        if not launch:
            problems.append(Problem(relative, "LaunchTheme 스타일이 없습니다"))
            continue
        items = {item.get("name"): (item.text or "").strip() for item in launch[0].iter("item")}
        for attribute in SPLASH_ATTRIBUTES:
            if not items.get(attribute):
                problems.append(Problem(relative, f"LaunchTheme 에 `{attribute}` 가 없습니다"))
        icon = items.get("android:windowSplashScreenAnimatedIcon")
        if icon and icon.startswith("@") and not _android_resource_files(app_dir, icon):
            problems.append(Problem(relative, f"실행 화면 아이콘 `{icon}` 의 파일이 없습니다"))

    contents_path = app_dir / LAUNCH_IMAGESET / "Contents.json"
    if not contents_path.exists():
        problems.append(Problem(LAUNCH_IMAGESET / "Contents.json", "LaunchImage 세트가 없습니다"))
    else:
        contents = json.loads(contents_path.read_text(encoding="utf-8"))
        points: dict[str, tuple[float, float]] = {}
        for entry in contents.get("images", []):
            filename = entry.get("filename")
            if not filename:
                continue
            relative = LAUNCH_IMAGESET / filename
            scale = float(str(entry.get("scale", "1x")).rstrip("x") or 1)
            image = app_dir / relative
            size = png_size(image) if image.exists() else None
            if size is None:
                problems.append(Problem(relative, "LaunchImage 그림이 없거나 PNG 가 아닙니다"))
                continue
            point_size = (size[0] / scale, size[1] / scale)
            if min(point_size) < MIN_LAUNCH_IMAGE_POINTS:
                problems.append(
                    Problem(
                        relative,
                        f"LaunchImage 가 {size[0]}×{size[1]} 픽셀 자리표시입니다. "
                        f"실제 로고(최소 {MIN_LAUNCH_IMAGE_POINTS}pt)로 바꾸세요",
                    )
                )
            points[filename] = point_size
        if len(set(points.values())) > 1:
            problems.append(
                Problem(
                    LAUNCH_IMAGESET / "Contents.json",
                    f"LaunchImage 배율별 크기가 서로 다릅니다: {points}",
                )
            )

    storyboard_path = app_dir / LAUNCH_STORYBOARD
    if not storyboard_path.exists():
        problems.append(Problem(LAUNCH_STORYBOARD, "실행 화면 스토리보드가 없습니다"))
    else:
        image_views = [
            view
            for view in ET.parse(storyboard_path).getroot().iter("imageView")
            if view.get("image") == "LaunchImage"
        ]
        if not image_views:
            problems.append(Problem(LAUNCH_STORYBOARD, "실행 화면이 LaunchImage 를 보여 주지 않습니다"))
    return problems


def check(app_dir: Path) -> list[Problem]:
    return (
        check_android(app_dir)
        + check_ios(app_dir)
        + check_web(app_dir)
        + check_launch_screen(app_dir)
    )


def main(argv: list[str]) -> int:
    app_dir = Path(argv[0]) if argv else DEFAULT_APP_DIR
    problems = check(app_dir)
    for problem in problems:
        print(f"::error file={app_dir / problem.file}::{problem.message}")
    if problems:
        print(f"앱 ID·앱 이름·서명·실행 화면 설정이 어긋난 곳 {len(problems)}건 (docs/mobile_release.md).")
        return 1
    print(
        f"앱 ID `{EXPECTED_APP_ID}`, 앱 이름 `{EXPECTED_APP_NAME}` — Android·iOS·웹 일치, "
        "릴리스 서명·실행 화면 설정 확인."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
