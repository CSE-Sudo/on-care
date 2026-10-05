#!/usr/bin/env bash
# 운영 웹 빌드에 넘길 dart-define 을 빌드 전에 검사한다(#3147).
#
# 두 앱의 기동 가드(`AppConfig.releaseProblems()`, #3022)가 같은 규칙으로 잘못된 운영
# 빌드를 막지만, 그 화면은 배포가 끝나 사용자가 열어 본 뒤에야 보인다. 모바일 스토어
# 빌드는 `frontend/flutter/tool/check_release_defines.sh` 가 빌드 전에 멈추는데, 운영 웹
# 빌드에는 같은 검사가 없었다. 여기서 같은 규칙으로 배포 전에 멈춘다.
#
# 사용: bash .github/scripts/check_web_release_defines.sh <flutter build web 인자...>
#   예: bash .github/scripts/check_web_release_defines.sh "${args[@]}"
#   `--dart-define=KEY=VALUE` 와 `--dart-define KEY=VALUE` 두 모양을 모두 읽는다.
#   dart-define 이 아닌 인자(--release, --base-href 등)는 건너뛴다.
#
# 규칙(운영 웹 빌드)
#  - ENV 는 prod 또는 staging 이어야 함(빠뜨리면 코드 기본값 dev)
#  - USE_MOCK_API 는 false 여야 함(빠뜨리면 코드 기본값 true — 목업)
#  - DEMO_BUILD=true 금지 — 데모 Pages 빌드(deploy.yml) 전용 표시
#  - SHOW_DEMO_ENTRY=true 금지 — 운영 로그인 화면에 데모 진입 버튼이 생긴다
#  - REAL_API 는 비어 있어야 함 — 목업 빌드에서 일부 기능만 실서버로 여는 데모 스위치
#  - --dart-define-from-file 금지 — 파일 안의 값은 여기서 보지 못한다
set -euo pipefail

# 받은 KEY=VALUE 를 순서대로 둔다. 같은 키가 여러 번 오면 flutter 처럼 마지막 값을 쓴다.
# (macOS 기본 bash 3 에서도 돌도록 연관 배열을 쓰지 않는다.)
pairs=()
errors=()

record() {
  local pair="$1"
  case "$pair" in
    *=*) pairs+=("$pair") ;;
    *) errors+=("dart-define 형식이 아닙니다: '$pair' (KEY=VALUE)") ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dart-define=*)
      record "${1#--dart-define=}"
      ;;
    --dart-define)
      if [ "$#" -lt 2 ]; then
        errors+=("--dart-define 뒤에 값이 없습니다.")
      else
        shift
        record "$1"
      fi
      ;;
    --dart-define-from-file|--dart-define-from-file=*)
      errors+=("--dart-define-from-file 은 운영 웹 빌드에서 쓰지 않습니다. 값을 --dart-define 으로 넘기세요.")
      ;;
  esac
  shift
done

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

value_of() {
  local key="$1" pair found=""
  if [ "${#pairs[@]}" -gt 0 ]; then
    for pair in "${pairs[@]}"; do
      if [ "${pair%%=*}" = "$key" ]; then
        found="${pair#*=}"
      fi
    done
  fi
  printf '%s' "$found"
}

env_value="$(value_of ENV)"
case "$env_value" in
  prod|staging) ;;
  *) errors+=("ENV 는 prod 또는 staging 이어야 합니다(지금: '${env_value}').") ;;
esac

if [ "$(lower "$(value_of USE_MOCK_API)")" != "false" ]; then
  errors+=("USE_MOCK_API=false 가 없습니다. 빠뜨리면 기기 안 데모 데이터로 도는 앱이 배포됩니다.")
fi

for flag in DEMO_BUILD SHOW_DEMO_ENTRY; do
  if [ "$(lower "$(value_of "$flag")")" = "true" ]; then
    errors+=("$flag=true 는 데모 빌드 전용입니다. 운영 웹 빌드 인자에서 지우세요.")
  fi
done

real_api="$(value_of REAL_API)"
if [ -n "${real_api//[[:space:],]/}" ]; then
  errors+=("REAL_API 는 목업 빌드에서 일부 기능만 실서버로 여는 데모 스위치입니다. 운영 웹 빌드 인자에서 지우세요(지금: '${real_api}').")
fi

if [ "${#errors[@]}" -gt 0 ]; then
  for message in "${errors[@]}"; do
    echo "::error title=web release defines::$message"
  done
  echo "운영 웹 빌드 인자가 운영 규칙에 맞지 않아 빌드를 중단합니다." >&2
  exit 1
fi

echo "운영 웹 빌드 인자 확인 완료."
