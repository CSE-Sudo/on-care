#!/usr/bin/env bash
# 배포(또는 롤백) 직후 서비스가 기대 설정으로 떴고 DB 까지 닿는지 확인한다(#2821, #2912, #3019).
#
# 사용: bash .github/scripts/backend_verify_service.sh <host> <prod|staging> [commit-sha]
#
# 1) /v1/healthz — 프로세스가 떴는지, 그 환경의 기대 설정인지(backend_health_check.sh)
# 2) /v1/readyz  — DB 까지 닿는지. 헬스체크 경로는 healthz 라 DB 일시 장애로 태스크를
#                  갈아 치우지 않으므로, DB 연결은 배포 직후 여기서 따로 본다.
# 3) /v1/version — 응답에 commit_sha 가 있으면 배포한 커밋과 같은지 본다. 필드가 아직
#                  없는 이미지(백엔드 쪽 노출 전)면 확인을 건너뛰고 알림만 남긴다.
#
# 재시도 횟수·간격은 VERIFY_ATTEMPTS(기본 10)·VERIFY_SLEEP(기본 10초)로 바꾼다.
set -euo pipefail

host="${1:-}"
expected_env="${2:-}"
expected_sha="${3:-}"
attempts="${VERIFY_ATTEMPTS:-10}"
pause="${VERIFY_SLEEP:-10}"
here="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$host" ] || [ -z "$expected_env" ]; then
  echo "사용: $0 <host> <prod|staging> [commit-sha]" >&2
  exit 2
fi
case "$host" in
  */*|*:*) echo "::error::호스트 이름만 넘깁니다(scheme·경로 없이): $host"; exit 2 ;;
esac

base="https://$host/v1"

body=""
for i in $(seq 1 "$attempts"); do
  if body="$(curl -fsS --max-time 10 "$base/healthz")"; then
    break
  fi
  body=""
  echo "healthz not ready, retry $i"
  sleep "$pause"
done
if [ -z "$body" ]; then
  echo "::error::배포 후 /v1/healthz 가 응답하지 않습니다."
  exit 1
fi
echo "healthz: $body"
printf '%s' "$body" | bash "$here/backend_health_check.sh" "$expected_env"

ready=0
for i in $(seq 1 "$attempts"); do
  if ready_body="$(curl -fsS --max-time 10 "$base/readyz")" &&
     [ "$(printf '%s' "$ready_body" | jq -r '.status // "missing"' 2> /dev/null)" = "ready" ]; then
    ready=1
    break
  fi
  echo "readyz not ready, retry $i"
  sleep "$pause"
done
if [ "$ready" -ne 1 ]; then
  echo "::error::배포 후 /v1/readyz 가 ready 를 돌려주지 않습니다 — DATABASE_URL·DB 상태를 확인하세요."
  exit 1
fi
echo "readyz OK"

if [ -n "$expected_sha" ]; then
  version_body="$(curl -fsS --max-time 10 "$base/version" || true)"
  served="$(printf '%s' "$version_body" |
    jq -r 'if type == "object" and has("commit_sha") then (.commit_sha | tostring) else "" end' 2> /dev/null || true)"
  if [ -z "$served" ]; then
    echo "::notice::/v1/version 에 commit_sha 가 없어 커밋 대조를 건너뜁니다."
  elif [ "$served" != "$expected_sha" ]; then
    echo "::error::서비스가 다른 커밋을 돌리고 있습니다: commit_sha=$served (기대 $expected_sha)"
    exit 1
  else
    echo "version OK: commit_sha=$served"
  fi
fi
