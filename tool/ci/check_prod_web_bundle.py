#!/usr/bin/env python3
"""운영 웹 빌드에 데모 코드·데모 자산이 실리지 않았는지 본다(#3157).

운영 릴리스 빌드(`DEMO_BUILD` 없이 `flutter build web --release`)는 목업 분기가
컴파일 타임 상수 false 로 접혀 트리 셰이킹되고(`kDemoCodeIncluded`), 데모 전용 자산은
`frontend/tool/strip_demo_assets.py` 가 pubspec 선언에서 뺀다. 둘 중 하나라도 새면
데모 계정·시드 인물·데모 사진이 운영 배포물에 그대로 나간다. 이 스크립트가 빌드
산출물(build/web)을 직접 열어 확인한다.

* JS 번들(main.dart.js 와 지연 로드 조각)에 앱별 데모 표지 문자열이 없어야 한다.
  표지는 목업 분기(로컬 API·데모 로그인·데모 시드) 안에만 있는 ASCII 문자열이다.
* 자산 트리에 assets/demo/ 가 없고, 자산 목록(AssetManifest)에도 없어야 한다.
* 원본 앱의 assets/demo 아래 파일 이름이 산출물 어디에도 없어야 한다.

    python3 tool/ci/check_prod_web_bundle.py --app member frontend/flutter/build/web
    python3 tool/ci/check_prod_web_bundle.py --app trainer frontend/flutter_trainer/build/web
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

APPS: dict[str, Path] = {
    "member": REPO_ROOT / "frontend" / "flutter",
    "trainer": REPO_ROOT / "frontend" / "flutter_trainer",
}

# 데모·목업 코드에만 있는 문자열. 운영 코드가 같은 값을 쓰게 되면 표지를 바꾼다.
MARKERS: dict[str, tuple[str, ...]] = {
    "member": (
        # 데모 로그인 저장 키(core/demo/demo_accounts.dart).
        "demo_member_login",
        # 로컬 API 인터셉터(core/network/interceptors/local_api/**)의 응답·저장 키.
        "drift-local",
        "demo-refresh",
        "ai_coach_user_messages_v3",
        # 데모 시드(core/storage/seed_data.dart)와 로컬 API 가 함께 쓰는 키.
        "dashboard_ai_advice",
        # 앱 가이드(features/app_guide)는 운영에서도 데모 시드의 목업 저장소로 예시
        # 화면을 그린다 — 그래서 데모 계정 이메일·데모 코치 첨부·공유 픽스처 문자열은
        # 운영 번들에도 남고, 여기 표지로 쓰지 않는다.
    ),
    "trainer": (
        # 데모 회원 시드(core/storage/seed_clients.dart).
        "breakfast-onigiri",
        "tue-thu-15min-program.pdf",
        # 목업 로그인(features/auth/data/repositories/mock_trainer_auth_repository.dart).
        "demo-trainer-",
        # 공유 데모 픽스처(shared/demo_fixture)의 시드 사진.
        "diet-oatmeal-banana",
    ),
}

DEMO_ASSET_PREFIX = "assets/demo/"


def bundle_files(build_dir: Path) -> list[Path]:
    """dart2js 산출물 — main.dart.js 와 지연 로드 조각(main.dart.js_N.part.js)."""
    return sorted(p for p in build_dir.glob("main.dart*.js") if p.is_file())


def manifest_texts(build_dir: Path) -> dict[str, bytes]:
    """자산 목록 파일들의 내용. bin.json 은 base64 를 풀어 원래 바이트로 본다."""
    out: dict[str, bytes] = {}
    assets = build_dir / "assets"
    for name in ("AssetManifest.json", "AssetManifest.bin", "AssetManifest.bin.json"):
        path = assets / name
        if not path.is_file():
            continue
        data = path.read_bytes()
        if name.endswith(".bin.json"):
            data = base64.b64decode(json.loads(data.decode("utf-8")))
        out[name] = data
    return out


def demo_asset_names(app_dir: Path) -> list[str]:
    root = app_dir / "assets" / "demo"
    if not root.is_dir():
        return []
    return sorted({p.name for p in root.rglob("*") if p.is_file()})


def check(app: str, build_dir: Path, app_dir: Path | None = None) -> list[str]:
    """찾은 문제를 사람이 읽을 문장으로 돌려준다. 비어 있으면 통과."""
    app_dir = app_dir or APPS[app]
    problems: list[str] = []

    bundles = bundle_files(build_dir)
    if not bundles:
        return [f"{build_dir} 에 main.dart.js 가 없다 — 웹 빌드 산출물 폴더를 넘긴다"]
    for bundle in bundles:
        text = bundle.read_bytes()
        for marker in MARKERS[app]:
            if marker.encode("utf-8") in text:
                problems.append(f"{bundle.name} 에 데모 표지 '{marker}' 가 남았다")

    demo_tree = build_dir / "assets" / "assets" / "demo"
    if demo_tree.exists():
        problems.append(f"{demo_tree.relative_to(build_dir).as_posix()} 가 산출물에 있다")

    for name, data in manifest_texts(build_dir).items():
        if DEMO_ASSET_PREFIX.encode("utf-8") in data:
            problems.append(f"assets/{name} 에 {DEMO_ASSET_PREFIX} 자산이 올라 있다")

    shipped = {p.name for p in build_dir.rglob("*") if p.is_file()}
    for name in demo_asset_names(app_dir):
        if name in shipped:
            problems.append(f"데모 자산 파일 {name} 이 산출물에 있다")
    return problems


def describe_sizes(build_dir: Path) -> str:
    parts = [f"{p.name} {p.stat().st_size:,}B" for p in bundle_files(build_dir)]
    total = sum(p.stat().st_size for p in bundle_files(build_dir))
    return f"JS 번들 합계 {total:,}B ({', '.join(parts)})"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--app", choices=sorted(APPS), required=True)
    parser.add_argument("build_dir", type=Path, help="flutter build web 산출물(build/web)")
    args = parser.parse_args(argv)

    problems = check(args.app, args.build_dir)
    if problems:
        for problem in problems:
            print(f"::error title=운영 번들에 데모가 섞임 ({args.app})::{problem}")
        print(
            "목업 분기는 kDemoCodeIncluded(app_config.dart) 뒤에, 데모 자산은 "
            "pubspec 의 demo-assets 구간에 둔다(#3157)."
        )
        return 1
    print(f"{args.app}: 운영 번들에 데모 코드·자산 없음. {describe_sizes(args.build_dir)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
