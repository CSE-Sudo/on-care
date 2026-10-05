#!/usr/bin/env bash
# 실서버 웹 빌드에 넘길 API 주소를 빌드 전에 검사한다(#2810, #3020).
#
# 두 웹 앱은 `API_BASE_URL` 을 받지 못하면 코드 기본값(자리표시자 주소)으로 빌드되고,
# `USE_MOCK_API=false` 와 함께라면 존재하지 않는 서버를 부르는 앱이 그대로 배포된다.
# 빌드는 성공하므로 배포 뒤에야 드러난다 — 그래서 값이 없거나 형식이 틀리면 여기서
# 워크플로를 멈춘다.
#
# 사용: API_BASE_URL=<값> [FORBIDDEN_API_BASE_URL=<값>] [API_BASE_URL_NAME=<변수 이름>] \
#         bash .github/scripts/check_web_api_base_url.sh
#
# FORBIDDEN_API_BASE_URL 은 이 빌드가 절대 부르면 안 되는 주소다. 운영 빌드에는 staging
# 주소를, 데모·staging 빌드에는 운영 주소를 넘긴다 — 저장소 변수를 바꿔 적어도 두 환경이
# 섞이지 않게 한다(#3020). 비어 있으면 그 검사는 건너뛴다. API_BASE_URL_NAME 은 오류
# 문구에 보일 저장소 변수 이름이다(기본 API_BASE_URL).
#
# 규칙
#  - 비어 있으면 실패
#  - https:// 로 시작해야 함(배포 웹은 https 로 서빙되므로 http 주소는 브라우저가 막는다)
#  - /v1 로 끝나야 함(두 앱은 요청 경로를 `/auth/login` 처럼 /v1 없이 쓴다). 끝 `/` 금지
#  - 코드 기본값의 자리표시자 도메인(example.com 계열)이면 실패
#  - FORBIDDEN_API_BASE_URL 과 같으면 실패(대소문자·끝 / 무시)
set -euo pipefail

value="${API_BASE_URL:-}"
forbidden="${FORBIDDEN_API_BASE_URL:-}"
name="${API_BASE_URL_NAME:-API_BASE_URL}"

fail() {
  echo "::error title=$name::$1"
  echo "저장소 Settings > Secrets and variables > Actions > Variables 의 $name 을 확인하세요." >&2
  echo "형식: https://<API 도메인>/v1" >&2
  exit 1
}

normalize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's#/*$##'
}

if [ -z "$value" ]; then
  fail "$name 저장소 변수가 비어 있습니다. 실서버 웹 빌드를 중단합니다."
fi

case "$value" in
  https://*) ;;
  *) fail "$name 은 https:// 로 시작해야 합니다." ;;
esac

case "$value" in
  */v1) ;;
  *) fail "$name 은 /v1 로 끝나야 합니다(끝에 / 없이)." ;;
esac

case "$value" in
  *example.com*|*example.test*) fail "$name 이 자리표시자 도메인입니다." ;;
esac

if [ -n "$forbidden" ] && [ "$(normalize "$value")" = "$(normalize "$forbidden")" ]; then
  fail "$name 이 이 빌드에서 쓰면 안 되는 다른 환경의 주소와 같습니다(운영·staging 혼용 방지)."
fi

echo "$name 확인 완료."
