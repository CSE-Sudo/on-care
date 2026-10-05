#!/usr/bin/env python3
"""서명 빌드 워크플로가 환경 변수로 회원 앱 define 파일(config/release.json)을 쓴다(#3148).

`.github/workflows/member-app-release.yml` 이 Environment `mobile-release` 의 변수·비밀을
환경 변수로 넘기면, 이 스크립트가 JSON 으로 옮긴다. 셸에서 문자열을 이어 붙이면 따옴표·
역슬래시가 섞인 값이 JSON 을 깨뜨리기 때문이다. 값의 검사는 하지 않는다 — 바로 뒤에
`tool/check_release_defines.sh` 가 같은 파일을 검사하고, 필수 값이 비면 거기서 멈춘다.

  필수 키(비어 있어도 쓴다): ENV ← APP_ENV, USE_MOCK_API(false 고정), API_BASE_URL, SENTRY_DSN
  선택 키(값이 있을 때만): KAKAO_JS_KEY, KAKAO_MAP_ORIGIN, IOS_APP_STORE_ID,
    KAKAO_NATIVE_APP_KEY, GOOGLE_WEB_CLIENT_ID, GOOGLE_IOS_CLIENT_ID(카카오·구글 로그인, #330),
                          BUILD_NUMBER, RELEASE_DATE
  BUILD_NUMBER·RELEASE_DATE 는 고객 지원 버전 줄(#3226)이 읽는 빌드 번호·배포 일시다.
  워크플로 게이트가 `.github/scripts/release_build_stamp.sh` 로 만들어 넘긴다.

iOS 잡은 같은 값으로 로그인 URL 스킴 파일(ios/Flutter/Social.xcconfig)도 쓴다(#330).
카카오 SDK 는 `kakao<네이티브 앱 키>`, 구글 로그인은 iOS client_id 를 뒤집은 스킴으로 앱에
돌아온다. 값이 없는 쪽은 적지 않아 Debug/Release.xcconfig 의 자리표시 스킴이 남는다.

사용: write_release_defines.py <출력 경로>
      write_release_defines.py --ios-url-schemes <xcconfig 경로>
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections.abc import Mapping
from pathlib import Path

OPTIONAL_KEYS = (
    "KAKAO_JS_KEY",
    "KAKAO_MAP_ORIGIN",
    "IOS_APP_STORE_ID",
    "KAKAO_NATIVE_APP_KEY",
    "GOOGLE_WEB_CLIENT_ID",
    "GOOGLE_IOS_CLIENT_ID",
    "BUILD_NUMBER",
    "RELEASE_DATE",
)
GOOGLE_CLIENT_ID_SUFFIX = ".apps.googleusercontent.com"
KAKAO_APP_KEY = re.compile(r"[A-Za-z0-9]{16,64}")
GOOGLE_CLIENT_PREFIX = re.compile(r"[A-Za-z0-9-]+")


def release_defines(environ: Mapping[str, str]) -> dict[str, str]:
    defines = {
        "ENV": environ.get("APP_ENV", "").strip(),
        "USE_MOCK_API": "false",
        "API_BASE_URL": environ.get("API_BASE_URL", "").strip(),
        "SENTRY_DSN": environ.get("SENTRY_DSN", "").strip(),
    }
    for key in OPTIONAL_KEYS:
        value = environ.get(key, "").strip()
        if value:
            defines[key] = value
    return defines


def ios_url_schemes(environ: Mapping[str, str]) -> str:
    """iOS 로그인 URL 스킴 xcconfig 본문. 형식이 맞는 값만 적는다(나머지는 앞 단계 검사가 막는다)."""
    lines = ["// member-app-release.yml 이 빌드 변수로 쓴 파일(#330). 커밋하지 않는다."]
    kakao = environ.get("KAKAO_NATIVE_APP_KEY", "").strip()
    if KAKAO_APP_KEY.fullmatch(kakao):
        lines.append(f"KAKAO_URL_SCHEME = kakao{kakao}")
    google = environ.get("GOOGLE_IOS_CLIENT_ID", "").strip()
    prefix = google[: -len(GOOGLE_CLIENT_ID_SUFFIX)] if google.endswith(GOOGLE_CLIENT_ID_SUFFIX) else ""
    if GOOGLE_CLIENT_PREFIX.fullmatch(prefix):
        lines.append(f"GOOGLE_URL_SCHEME = com.googleusercontent.apps.{prefix}")
    return "\n".join(lines) + "\n"


def _write_url_schemes(path: Path) -> int:
    text = ios_url_schemes(os.environ)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    written = [line.split(" = ", 1)[0] for line in text.splitlines() if " = " in line]
    print(f"{path}: {', '.join(written) or '(로그인 스킴 없음)'}")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) == 2 and args[0] == "--ios-url-schemes":
        return _write_url_schemes(Path(args[1]))
    if len(args) != 1 or args[0].startswith("--"):
        print(
            "사용: write_release_defines.py <출력 경로> | --ios-url-schemes <xcconfig 경로>",
            file=sys.stderr,
        )
        return 2
    out = Path(args[0])
    defines = release_defines(os.environ)
    out.parent.mkdir(parents=True, exist_ok=True)
    # 비밀(SENTRY_DSN)이 들어가므로 소유자만 읽게 만든다.
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(defines, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    # 값은 찍지 않고 어떤 키를 썼는지만 남긴다.
    print(f"{out}: {', '.join(sorted(defines))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
