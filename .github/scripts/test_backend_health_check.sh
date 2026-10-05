#!/usr/bin/env bash
# backend_health_check.sh 의 통과·실패 경계 검사(#3020).
# 사용: bash .github/scripts/test_backend_health_check.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
check="$here/backend_health_check.sh"
failures=0

expect() {
  local want="$1" env="$2" body="$3" label="$4" got
  if printf '%s' "$body" | bash "$check" "$env" > /dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> $got (기대: $want)"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got"
  fi
}

prod_ok='{"status":"ok","env":"prod","demo_fallback":false,"demo_seed":false,"attachment_storage":"s3"}'
staging_demo='{"status":"ok","env":"staging","demo_fallback":true,"demo_seed":true,"attachment_storage":"s3"}'

expect pass prod "$prod_ok" "운영 기대 설정"
expect fail prod '{"env":"dev","demo_fallback":false,"demo_seed":false,"attachment_storage":"s3"}' "운영인데 env=dev"
expect fail prod '{"env":"prod","demo_fallback":true,"demo_seed":false,"attachment_storage":"s3"}' "운영 데모 폴백 켜짐"
expect fail prod '{"env":"prod","demo_fallback":false,"demo_seed":true,"attachment_storage":"s3"}' "운영 데모 시드 켜짐"
expect fail prod '{"env":"prod","demo_fallback":false,"demo_seed":false,"attachment_storage":"local"}' "운영 로컬 첨부 저장소"
expect fail prod '{"env":"prod","demo_seed":false,"attachment_storage":"s3"}' "demo_fallback 필드 없음"
expect fail prod '{"env":"prod","demo_fallback":false,"demo_seed":false,"attachment_storage":"misconfigured"}' "첨부 설정 오류"
expect fail prod 'not json' "JSON 아님"
expect fail prod '[]' "객체 아님"
expect pass staging "$staging_demo" "staging 데모 시드·폴백 허용"
expect pass staging '{"env":"staging","demo_fallback":false,"demo_seed":false,"attachment_storage":"s3"}' "staging 데모 꺼짐"
expect fail staging "$prod_ok" "staging 자리에 운영 서비스"
expect fail staging '{"env":"staging","demo_fallback":false,"demo_seed":true,"attachment_storage":"local"}' "staging 로컬 첨부 저장소"
expect fail dev "$prod_ok" "알 수 없는 기대 환경"
expect fail '' "$prod_ok" "기대 환경 누락"

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
