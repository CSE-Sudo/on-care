#!/usr/bin/env bash
# 배포된 백엔드가 기대한 설정·커밋으로 떴는지 판정한다(#2821·#3029).
#
# 사용:
#   printf '%s' "$BODY" | bash .github/scripts/verify_backend_health.sh healthz <기대 env>
#   printf '%s' "$BODY" | bash .github/scripts/verify_backend_health.sh version <기대 커밋 SHA>
#
# 본문(JSON)은 표준 입력으로 받는다. 문제마다 `::error::` 한 줄을 남기고, 하나라도 있으면
# 종료 코드 1. 배포 워크플로(backend-deploy.yml)가 부르고, 경계는
# test_verify_backend_health.sh 가 확인한다.
set -euo pipefail

mode="${1:-}"
expected="${2:-}"
body="$(cat)"

if ! printf '%s' "$body" | jq -e 'type == "object"' > /dev/null 2>&1; then
  echo "::error::응답이 JSON 객체가 아닙니다: $body"
  exit 1
fi

# jq 의 `//` 는 false 도 빈 값으로 보므로 has() 로 있는지부터 가린다.
field() {
  printf '%s' "$body" |
    jq -r --arg k "$1" 'if has($k) then (.[$k] | tostring) else "missing" end'
}

failed=0
case "$mode" in
  healthz)
    if [ -z "$expected" ]; then
      echo "::error::기대 env 가 비어 있습니다." >&2
      exit 2
    fi
    actual_env=$(field env)
    demo_fallback=$(field demo_fallback)
    demo_seed=$(field demo_seed)
    storage=$(field attachment_storage)
    if [ "$actual_env" != "$expected" ]; then
      echo "::error::서비스 env=$actual_env (기대값 $expected). 서비스 환경변수 ENV 를 확인하세요."
      failed=1
    fi
    if [ "$demo_fallback" != "false" ]; then
      echo "::error::데모 폴백이 꺼져 있지 않습니다(demo_fallback=$demo_fallback) — 토큰 없는 요청이 데모 회원으로 처리됩니다."
      failed=1
    fi
    if [ "$expected" = "prod" ] && [ "$demo_seed" != "false" ]; then
      echo "::error::운영 서비스에 데모 시드가 켜져 있습니다(demo_seed=$demo_seed). SEED_DEMO_DATA=false 로 두고 데모는 별도 서비스·DB 로 띄우세요."
      failed=1
    fi
    # 운영은 첨부를 S3 에 둔다(#3029). local 이면 재배포 때 사진·리포트 PDF 가 사라지고,
    # misconfigured 는 ATTACHMENT_STORAGE=s3 인데 버킷이 빈 상태다.
    if [ "$expected" = "prod" ] && [ "$storage" != "s3" ]; then
      echo "::error::운영 서비스의 채팅 첨부 저장소가 s3 가 아닙니다(attachment_storage=$storage). ATTACHMENT_STORAGE=s3·ATTACHMENT_S3_BUCKET 을 확인하세요."
      failed=1
    fi
    if [ "$failed" -eq 0 ]; then
      echo "healthz OK: env=$actual_env demo_fallback=$demo_fallback demo_seed=$demo_seed attachment_storage=$storage"
    fi
    ;;
  version)
    if [ -z "$expected" ]; then
      echo "::error::기대 커밋 SHA 가 비어 있습니다." >&2
      exit 2
    fi
    actual_sha=$(field commit_sha)
    if [ "$actual_sha" != "$expected" ]; then
      echo "::error::요청을 받는 서버의 커밋이 배포한 커밋과 다릅니다(commit_sha=$actual_sha, 기대값 $expected). 이미지 빌드 인자 GIT_SHA 와 서비스 배포 상태를 확인하세요."
      failed=1
    else
      echo "version OK: commit_sha=$actual_sha"
    fi
    ;;
  *)
    echo "사용: verify_backend_health.sh healthz <기대 env> | version <기대 커밋 SHA>" >&2
    exit 2
    ;;
esac

exit "$failed"
