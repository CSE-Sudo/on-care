#!/usr/bin/env bash
# 백엔드 이미지를 운영 설정(ENV=prod)으로 띄워 보는 스모크(#3163).
#
# 기존 기동 스모크는 ENV=dev 로만 돌아, 운영에서만 켜지는 설정 가드(_guard_prod_secrets)·
# 기동 점검(startup_checks)의 운영 분기·FORCE_HTTPS 미들웨어가 실제 엔트리포인트
# (scripts/start.sh → 마이그레이션 → uvicorn)와 함께 검증되지 않았다. 여기서는
#
#   1) 더미 운영 설정(backend/tests/fixtures/prod_smoke.env)으로 컨테이너를 띄우고,
#      로드 밸런서처럼 X-Forwarded-Proto: https 를 붙여 /v1/healthz·/v1/readyz 를 확인한다.
#      헤더 없는 평문 요청이 https 로 리다이렉트되는지(FORCE_HTTPS)와 API 문서가 닫혔는지도 본다.
#   2) 필수 운영 값을 하나씩 뺀 설정으로 띄워 컨테이너가 **기동하지 못하고** 그 값을 가리키는
#      오류를 남기는지 확인한다.
#
# 사용: backend_prod_boot_smoke.sh <이미지> <env 파일>
# 컨테이너는 --network host 로 CI 의 Postgres 서비스(localhost:5432)에 붙는다.
set -euo pipefail

IMAGE="${1:?이미지 이름이 필요합니다}"
ENV_FILE="${2:?env 파일이 필요합니다}"
PORT="${SMOKE_PORT:-8010}"
NAME="oncare-backend-prod-smoke"
BASE="http://localhost:${PORT}"
HTTPS=(-H "X-Forwarded-Proto: https")

# 빼면 기동이 멈춰야 하는 값과, 그때 로그에 나와야 하는 문구(설정 이름).
# tests/test_prod_smoke_env.py 가 같은 목록으로 가드를 직접 확인한다.
REQUIRED_CASES=(
  "JWT_SECRET|JWT_SECRET"
  "CORS_ALLOW_ORIGINS|CORS_ALLOW_ORIGINS"
  "GEMINI_API_KEY|GEMINI_API_KEY"
  "ATTACHMENT_S3_BUCKET|ATTACHMENT_S3_BUCKET"
)

work="$(mktemp -d)"
cleanup() {
  docker rm -f "$NAME" > /dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  echo "::error title=운영 설정 기동 스모크::$*"
  docker logs "$NAME" 2>&1 | tail -n 200 || true
  exit 1
}

# --- 1) 더미 운영 설정으로 기동
docker run -d --name "$NAME" --network host --env-file "$ENV_FILE" -e "PORT=${PORT}" "$IMAGE" > /dev/null
ready=0
for i in $(seq 1 60); do
  if curl --fail --silent --max-time 5 "${HTTPS[@]}" "${BASE}/v1/healthz" > /dev/null; then
    echo "healthz ok after ${i} tries (ENV=prod)"
    ready=1
    break
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != "true" ]; then
    fail "운영 설정 컨테이너가 기동 중에 종료됐습니다(아래 로그)."
  fi
  sleep 3
done
[ "$ready" -eq 1 ] || fail "운영 설정 컨테이너가 3분 안에 /v1/healthz 에 응답하지 않았습니다."

health=$(curl --fail --silent --show-error --max-time 5 "${HTTPS[@]}" "${BASE}/v1/healthz")
echo "healthz: ${health}"
printf '%s' "$health" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status") == "ok" else 1)' \
  || fail "/v1/healthz 응답의 status 가 ok 가 아닙니다."

ready_body=$(curl --fail --silent --show-error --max-time 10 "${HTTPS[@]}" "${BASE}/v1/readyz") \
  || fail "/v1/readyz 가 실패했습니다(DB 연결)."
echo "readyz: ${ready_body}"
printf '%s' "$ready_body" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status") == "ready" else 1)' \
  || fail "/v1/readyz 응답의 status 가 ready 가 아닙니다."

# FORCE_HTTPS: 프록시 헤더 없는 평문 요청은 https 로 보낸다.
code=$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code} %{redirect_url}' "${BASE}/v1/version")
echo "plain http /v1/version: ${code}"
case "$code" in
  "307 https://"*) ;;
  *) fail "FORCE_HTTPS 가 켜지지 않았습니다 — 평문 /v1/version 이 https 리다이렉트가 아닙니다(${code})." ;;
esac

# 운영은 API 문서를 열지 않는다(#2834).
docs=$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' "${HTTPS[@]}" "${BASE}/docs")
echo "/docs: ${docs}"
[ "$docs" = "404" ] || fail "운영 설정에서 /docs 가 열려 있습니다(${docs})."

docker logs "$NAME" > "$work/boot.log" 2>&1
grep -F "[start] ENV=prod" "$work/boot.log" > /dev/null || fail "엔트리포인트 로그에 ENV=prod 가 없습니다."
docker rm -f "$NAME" > /dev/null
echo "운영 설정 기동 통과."

# --- 2) 필수 값을 하나씩 빼면 기동하지 못한다
for case_line in "${REQUIRED_CASES[@]}"; do
  key="${case_line%%|*}"
  needle="${case_line#*|}"
  grep -q "^${key}=" "$ENV_FILE" || fail "$ENV_FILE 에 ${key} 가 없습니다 — 빼 볼 값이 없습니다."
  grep -v "^${key}=" "$ENV_FILE" > "$work/without-${key}.env"
  set +e
  timeout 120 docker run --name "$NAME" --network host --env-file "$work/without-${key}.env" \
    -e "PORT=${PORT}" "$IMAGE" > "$work/without-${key}.log" 2>&1
  status=$?
  set -e
  docker rm -f "$NAME" > /dev/null 2>&1 || true
  if [ "$status" -eq 124 ]; then
    tail -n 50 "$work/without-${key}.log"
    fail "${key} 없이도 컨테이너가 2분 넘게 떠 있었습니다 — 운영 가드가 동작하지 않습니다."
  fi
  if [ "$status" -eq 0 ]; then
    tail -n 50 "$work/without-${key}.log"
    fail "${key} 없이 컨테이너가 정상 종료(0)했습니다."
  fi
  if ! grep -F -- "$needle" "$work/without-${key}.log" > /dev/null; then
    tail -n 50 "$work/without-${key}.log"
    fail "${key} 없이 기동이 멈췄지만 로그에 '${needle}' 이 없습니다 — 다른 이유로 실패했을 수 있습니다."
  fi
  echo "${key} 없음 → 기동 거부(종료 코드 ${status})."
done
echo "필수 운영 값 확인 통과."
