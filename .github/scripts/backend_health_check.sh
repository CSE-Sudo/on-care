#!/usr/bin/env bash
# 배포 직후 /v1/healthz 응답이 그 환경의 기대 설정인지 판정한다(#2821, #3020).
#
# 사용: printf '%s' "$BODY" | bash .github/scripts/backend_health_check.sh <prod|staging>
#
# 백엔드의 안전장치(데모 폴백 차단·JWT/CORS 검사)는 ENV=prod 일 때만 켜지는데, 서비스
# 환경변수에 ENV 를 빠뜨려도 기동은 되므로 healthz 가 200 이라는 것만으로는 알 수 없다.
#
# 규칙
#  - env 가 기대값과 같아야 한다
#  - attachment_storage 는 s3 여야 한다(컨테이너 디스크는 재배포 때 사진·PDF 를 잃는다, #2817)
#  - prod: demo_fallback=false, demo_seed=false
#  - staging: 데모 시드·폴백은 시연용으로 켤 수 있다(별도 DB, DEPLOY.md 5-2). 값만 기록한다
set -euo pipefail

expected="${1:-}"
case "$expected" in
  prod|staging) ;;
  *) echo "::error::기대 환경은 prod 또는 staging 이어야 합니다: '$expected'"; exit 2 ;;
esac

body="$(cat)"
if ! printf '%s' "$body" | jq -e 'type == "object"' > /dev/null 2>&1; then
  echo "::error::healthz 응답이 JSON 객체가 아닙니다: $body"
  exit 1
fi

# jq 의 `//` 는 false 도 빈 값으로 보므로 has() 로 있는지부터 가린다.
field() {
  printf '%s' "$body" |
    jq -r --arg k "$1" 'if has($k) then (.[$k] | tostring) else "missing" end'
}

actual_env="$(field env)"
demo_fallback="$(field demo_fallback)"
demo_seed="$(field demo_seed)"
storage="$(field attachment_storage)"
failed=0

if [ "$actual_env" != "$expected" ]; then
  echo "::error::서비스 env=$actual_env (기대값 $expected). 서비스 스택의 ENV 를 확인하세요."
  failed=1
fi
if [ "$storage" != "s3" ]; then
  echo "::error::첨부 저장소가 s3 가 아닙니다(attachment_storage=$storage). ATTACHMENT_S3_BUCKET·태스크 역할을 확인하세요."
  failed=1
fi
if [ "$expected" = "prod" ]; then
  if [ "$demo_fallback" != "false" ]; then
    echo "::error::데모 폴백이 꺼져 있지 않습니다(demo_fallback=$demo_fallback) — 토큰 없는 요청이 데모 회원으로 처리됩니다."
    failed=1
  fi
  if [ "$demo_seed" != "false" ]; then
    echo "::error::운영 서비스에 데모 시드가 켜져 있습니다(demo_seed=$demo_seed). 데모는 staging 서비스·DB 로 띄우세요."
    failed=1
  fi
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "healthz OK: env=$actual_env demo_fallback=$demo_fallback demo_seed=$demo_seed attachment_storage=$storage"
