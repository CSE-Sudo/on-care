#!/usr/bin/env bash
# verify_backend_health.sh 의 통과·실패 경계 검사(#3029).
# 사용: bash .github/scripts/test_verify_backend_health.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/verify_backend_health.sh"
failures=0

record() {
  local want="$1" got="$2" label="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> $got (기대: $want)"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got"
  fi
}

expect() {
  local want="$1" label="$2" body="$3"; shift 3
  local got
  if printf '%s' "$body" | bash "$tool" "$@" > /dev/null 2>&1; then got=pass; else got=fail; fi
  record "$want" "$got" "$label"
}

sha="0123456789abcdef0123456789abcdef01234567"
prod_ok='{"status":"ok","env":"prod","demo_fallback":false,"demo_seed":false,"attachment_storage":"s3","commit_sha":"'"$sha"'"}'

# --- healthz: 운영 ---
expect pass 'healthz 운영 정상' "$prod_ok" healthz prod
expect fail 'healthz 운영 + 첨부 local' '{"env":"prod","demo_fallback":false,"demo_seed":false,"attachment_storage":"local"}' healthz prod
expect fail 'healthz 운영 + 첨부 misconfigured' '{"env":"prod","demo_fallback":false,"demo_seed":false,"attachment_storage":"misconfigured"}' healthz prod
expect fail 'healthz 운영 + 첨부 필드 없음' '{"env":"prod","demo_fallback":false,"demo_seed":false}' healthz prod
expect fail 'healthz 운영 + env 다름' '{"env":"dev","demo_fallback":false,"demo_seed":false,"attachment_storage":"s3"}' healthz prod
expect fail 'healthz 운영 + 데모 폴백 켜짐' '{"env":"prod","demo_fallback":true,"demo_seed":false,"attachment_storage":"s3"}' healthz prod
expect fail 'healthz 운영 + 데모 시드 켜짐' '{"env":"prod","demo_fallback":false,"demo_seed":true,"attachment_storage":"s3"}' healthz prod
expect fail 'healthz 운영 + 데모 폴백 필드 없음' '{"env":"prod","demo_seed":false,"attachment_storage":"s3"}' healthz prod

# --- healthz: 스테이징(시연) — 첨부·시드는 보지 않는다 ---
expect pass 'healthz 스테이징 + 첨부 local' '{"env":"staging","demo_fallback":false,"demo_seed":true,"attachment_storage":"local"}' healthz staging
expect fail 'healthz 스테이징 + 데모 폴백 켜짐' '{"env":"staging","demo_fallback":true,"demo_seed":true,"attachment_storage":"local"}' healthz staging

# --- version ---
expect pass 'version 같은 커밋' '{"api_version":"v1","app_version":"0.4.0","commit_sha":"'"$sha"'"}' version "$sha"
expect fail 'version 다른 커밋' '{"api_version":"v1","app_version":"0.4.0","commit_sha":"ffffffffffffffffffffffffffffffffffffffff"}' version "$sha"
expect fail 'version unknown' '{"api_version":"v1","app_version":"0.4.0","commit_sha":"unknown"}' version "$sha"
expect fail 'version 필드 없음' '{"api_version":"v1","app_version":"0.4.0"}' version "$sha"

# --- 입력 오류 ---
expect fail 'JSON 아님' 'not json' healthz prod
expect fail '기대 env 없음' "$prod_ok" healthz
expect fail '기대 SHA 없음' "$prod_ok" version
expect fail '알 수 없는 모드' "$prod_ok" readyz prod

if [ "$failures" -ne 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
