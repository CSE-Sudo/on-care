#!/usr/bin/env bash
# 실서버 웹 빌드에 넘길 API 주소를 빌드 전에 검사한다(#2810).
#
# 두 웹 앱은 `API_BASE_URL` 을 받지 못하면 코드 기본값(자리표시자 주소)으로 빌드되고,
# `USE_MOCK_API=false` 와 함께라면 존재하지 않는 서버를 부르는 앱이 그대로 배포된다.
# 빌드는 성공하므로 배포 뒤에야 드러난다 — 그래서 값이 없거나 형식이 틀리면 여기서
# 워크플로를 멈춘다.
#
# 사용: API_BASE_URL=<값> bash .github/scripts/check_web_api_base_url.sh
#
# 규칙
#  - 비어 있으면 실패
#  - https:// 로 시작해야 함(배포 웹은 https 로 서빙되므로 http 주소는 브라우저가 막는다)
#  - /v1 로 끝나야 함(두 앱은 요청 경로를 `/auth/login` 처럼 /v1 없이 쓴다). 끝 `/` 금지
#  - 코드 기본값의 자리표시자 도메인(example.com 계열)이면 실패
set -euo pipefail

value="${API_BASE_URL:-}"

fail() {
  echo "::error title=API_BASE_URL::$1"
  echo "저장소 Settings > Secrets and variables > Actions > Variables 의 API_BASE_URL 을 확인하세요." >&2
  echo "형식: https://<운영 API 도메인>/v1" >&2
  exit 1
}

if [ -z "$value" ]; then
  fail "API_BASE_URL 저장소 변수가 비어 있습니다. 실서버 웹 빌드를 중단합니다."
fi

case "$value" in
  https://*) ;;
  *) fail "API_BASE_URL 은 https:// 로 시작해야 합니다." ;;
esac

case "$value" in
  */v1) ;;
  *) fail "API_BASE_URL 은 /v1 로 끝나야 합니다(끝에 / 없이)." ;;
esac

case "$value" in
  *example.com*|*example.test*) fail "API_BASE_URL 이 자리표시자 도메인입니다." ;;
esac

echo "API_BASE_URL 확인 완료."
