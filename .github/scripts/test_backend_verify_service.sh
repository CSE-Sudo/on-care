#!/usr/bin/env bash
# backend_verify_service.sh 검사(#3019). curl 을 가짜 실행 파일로 바꿔 응답을 정한다.
# 사용: bash .github/scripts/test_backend_verify_service.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/backend_verify_service.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
SHA='0123456789abcdef0123456789abcdef01234567'

# 가짜 curl: 마지막 인자(URL) 끝 경로에 맞는 FAKE_<PATH> 값을 돌려준다. 값이 FAIL 이면 실패.
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
url="${*: -1}"
case "$url" in
  */healthz) value="${FAKE_HEALTHZ-}" ;;
  */readyz) value="${FAKE_READYZ-}" ;;
  */version) value="${FAKE_VERSION-}" ;;
  *) exit 22 ;;
esac
[ "$value" = "FAIL" ] && exit 22
printf '%s' "$value"
FAKE
chmod +x "$work/bin/curl"

PROD='{"status":"ok","env":"prod","demo_fallback":false,"demo_seed":false,"attachment_storage":"s3"}'
READY='{"status":"ready"}'

check() {
  local label="$1" want="$2" got
  shift 2
  if PATH="$work/bin:$PATH" VERIFY_ATTEMPTS=2 VERIFY_SLEEP=0 bash "$script" "$@" > "$work/out" 2>&1; then
    got=pass
  else
    got=fail
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> $got (기대: $want)"
    sed 's/^/      /' "$work/out"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got"
  fi
}

export FAKE_HEALTHZ="$PROD" FAKE_READYZ="$READY" FAKE_VERSION="{\"api_version\":\"v1\",\"commit_sha\":\"$SHA\"}"
check "정상 배포" pass api.example.on.aws prod "$SHA"
check "커밋 대조 없이" pass api.example.on.aws prod
FAKE_VERSION='{"api_version":"v1","app_version":"0.1.0"}' check "commit_sha 없음은 건너뜀" pass api.example.on.aws prod "$SHA"
FAKE_VERSION=FAIL check "version 응답 없음은 건너뜀" pass api.example.on.aws prod "$SHA"
FAKE_VERSION='{"commit_sha":"ffffffffffffffffffffffffffffffffffffffff"}' check "다른 커밋" fail api.example.on.aws prod "$SHA"
FAKE_HEALTHZ=FAIL check "healthz 무응답" fail api.example.on.aws prod
FAKE_HEALTHZ='{"env":"prod","demo_fallback":true,"demo_seed":false,"attachment_storage":"s3"}' check "운영 데모 폴백" fail api.example.on.aws prod
FAKE_READYZ='{"status":"not_ready"}' check "DB 미연결" fail api.example.on.aws prod
FAKE_READYZ=FAIL check "readyz 무응답" fail api.example.on.aws prod
check "scheme 붙은 호스트 거부" fail https://api.example.on.aws prod
check "인자 부족" fail api.example.on.aws

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
