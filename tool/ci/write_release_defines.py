#!/usr/bin/env python3
"""서명 빌드 워크플로가 환경 변수로 회원 앱 define 파일(config/release.json)을 쓴다(#3148).

`.github/workflows/member-app-release.yml` 이 Environment `mobile-release` 의 변수·비밀을
환경 변수로 넘기면, 이 스크립트가 JSON 으로 옮긴다. 셸에서 문자열을 이어 붙이면 따옴표·
역슬래시가 섞인 값이 JSON 을 깨뜨리기 때문이다. 값의 검사는 하지 않는다 — 바로 뒤에
`tool/check_release_defines.sh` 가 같은 파일을 검사하고, 필수 값이 비면 거기서 멈춘다.

  필수 키(비어 있어도 쓴다): ENV ← APP_ENV, USE_MOCK_API(false 고정), API_BASE_URL, SENTRY_DSN
  선택 키(값이 있을 때만): KAKAO_JS_KEY, KAKAO_MAP_ORIGIN, IOS_APP_STORE_ID,
                          BUILD_NUMBER, RELEASE_DATE
  BUILD_NUMBER·RELEASE_DATE 는 설정 화면 `버전 정보`(#3226)가 읽는 빌드 번호·배포 일시다.
  워크플로 게이트가 `.github/scripts/release_build_stamp.sh` 로 만들어 넘긴다.

사용: write_release_defines.py <출력 경로>
"""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Mapping
from pathlib import Path

OPTIONAL_KEYS = (
    "KAKAO_JS_KEY",
    "KAKAO_MAP_ORIGIN",
    "IOS_APP_STORE_ID",
    "BUILD_NUMBER",
    "RELEASE_DATE",
)


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


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("사용: write_release_defines.py <출력 경로>", file=sys.stderr)
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
