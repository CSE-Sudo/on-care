#!/usr/bin/env bash
# check_web_api_base_url.sh 의 통과·실패 경계 검사(#2810).
# 사용: bash .github/scripts/test_check_web_api_base_url.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/check_web_api_base_url.sh"
failures=0

expect() {
  local want="$1" value="$2" got
  if API_BASE_URL="$value" bash "$guard" > /dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: API_BASE_URL='$value' -> $got (기대: $want)"
    failures=$((failures + 1))
  else
    echo "ok:   API_BASE_URL='$value' -> $got"
  fi
}

# 빈 값 — 변수를 만들지 않았거나 이름을 틀린 경우
expect fail ''
# https 가 아님
expect fail 'http://api.oncare.test.internal/v1'
expect fail 'api.oncare.kr/v1'
# /v1 누락·끝 슬래시
expect fail 'https://api.oncare.kr'
expect fail 'https://api.oncare.kr/v1/'
expect fail 'https://api.oncare.kr/v2'
# 코드 기본값의 자리표시자
expect fail 'https://dev.api.oncare.example.com/v1'
expect fail 'https://api.example.test/v1'
# 올바른 형식
expect pass 'https://api.oncare.kr/v1'
expect pass 'https://abc123.ap-northeast-2.awsapprunner.com/v1'

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
