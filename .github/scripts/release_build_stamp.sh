#!/usr/bin/env bash
# 릴리스 빌드에 넣을 빌드 번호와 배포 일시를 만든다(#3226).
#
# 두 앱 고객 지원의 버전 줄은 `On-Care · 버전 0.4.0 (7032) · <KST 배포 일시>` 처럼 보인다. 버전 이름은
# pubspec 에서 손으로 올리지만, 빌드 번호는 릴리스 빌드마다 저절로 커져야 한다. 사람이 올리면
# 웹 배포에서는 늘 같은 값이고, 스토어 빌드에서는 잊는 순간 업로드가 거부된다.
#
# 빌드 번호 = 빌드하는 커밋까지의 커밋 수(`git rev-list --count HEAD`).
#  - main 에 병합할 때마다 커지므로 릴리스 빌드마다 단조 증가한다.
#  - 워크플로마다 따로 세는 `github.run_number` 와 달리 공유 카운터다. 같은 커밋이면 데모 Pages·
#    운영 AWS·스토어 서명 빌드, 회원 앱·트레이너 웹 어디서 만들어도 같은 번호다.
#  - Android versionCode·iOS CFBundleVersion 으로도 쓰인다(`flutter build --build-number`).
#
# 배포 일시 = 이 스크립트를 실행한 UTC 시각(ISO 8601, 초 단위). 앱이 KST 로 바꿔 보인다.
#
# 사용: [MIN_BUILD_NUMBER=<정수>] bash .github/scripts/release_build_stamp.sh [출력 파일]
#   표준 출력과, 주어지면 출력 파일(보통 "$GITHUB_ENV" 나 "$GITHUB_OUTPUT")에 두 줄을 덧붙인다.
#     BUILD_NUMBER=<커밋 수>
#     RELEASE_DATE=<YYYY-MM-DDTHH:MM:SSZ>
#   MIN_BUILD_NUMBER 는 이미 쓴 빌드 번호(예: pubspec 의 `+` 뒤)다. 새 번호가 이보다 크지 않으면
#   스토어가 거부할 빌드이므로 멈춘다.
#
# 규칙
#  - 얕은 체크아웃(`fetch-depth` 기본값 1)이면 실패 — 커밋 수가 1 로 나와 번호가 뒤로 간다.
#    호출하는 잡의 체크아웃은 `fetch-depth: 0` 이어야 한다.
#  - 커밋 수가 양의 정수가 아니면 실패
#  - MIN_BUILD_NUMBER 가 있으면 숫자여야 하고, 새 번호가 그보다 커야 한다
set -euo pipefail

out="${1:-}"
min="${MIN_BUILD_NUMBER:-}"

fail() {
  echo "::error title=release build stamp::$1"
  exit 1
}

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  fail "git 저장소 안에서 실행해야 합니다."
fi
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  fail "얕은 체크아웃이라 커밋 수를 셀 수 없습니다. actions/checkout 에 fetch-depth: 0 을 주세요."
fi

build_number="$(git rev-list --count HEAD)"
if ! [[ "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  fail "커밋 수가 양의 정수가 아닙니다: '$build_number'"
fi

if [ -n "$min" ]; then
  if ! [[ "$min" =~ ^[0-9]+$ ]]; then
    fail "MIN_BUILD_NUMBER 는 0 이상의 정수여야 합니다: '$min'"
  fi
  if [ "$build_number" -le "$min" ]; then
    fail "빌드 번호 $build_number 가 이미 쓴 번호 $min 보다 크지 않습니다. 스토어가 거부합니다."
  fi
fi

release_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

lines="BUILD_NUMBER=$build_number
RELEASE_DATE=$release_date"
printf '%s\n' "$lines"
if [ -n "$out" ]; then
  printf '%s\n' "$lines" >> "$out"
fi
