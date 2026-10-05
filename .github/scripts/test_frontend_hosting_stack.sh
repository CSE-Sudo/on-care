#!/usr/bin/env bash
# frontend_hosting_stack.sh 의 현재 OriginPath 조회·스택 갱신 인자 검사(#3129).
# 사용: bash .github/scripts/test_frontend_hosting_stack.sh
# 실제 aws 를 부르지 않는다 — AWS_CLI 에 인자를 적어 두고 표의 값을 돌려주는 가짜 명령을 넣는다.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/frontend_hosting_stack.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

check() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> '$got' (기대: '$want')"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> '$got'"
  fi
}

SHA=0123456789abcdef0123456789abcdef01234567

# 가짜 aws: 인자를 한 줄로 적고, 조회는 환경 변수의 값을 돌려준다.
#   FAKE_STACK_FAIL=1     describe-stacks 실패(스택 없음)
#   FAKE_DISTRIBUTION_ID  DistributionId 출력
#   FAKE_TARGET_ORIGIN    기본 동작의 TargetOriginId
#   FAKE_ORIGIN_PATH      그 오리진의 OriginPath(None 이면 오리진 없음)
fake="$work/aws"
cat > "$fake" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "CALL $*" >> "$FAKE_LOG"
case "$1 $2" in
  "cloudformation describe-stacks")
    [ "${FAKE_STACK_FAIL:-0}" = "1" ] && { echo "Stack does not exist" >&2; exit 254; }
    printf '%s\n' "$FAKE_DISTRIBUTION_ID"
    ;;
  "cloudfront get-distribution-config")
    case "$*" in
      *TargetOriginId*) printf '%s\n' "$FAKE_TARGET_ORIGIN" ;;
      *"Items[?Id=='frontend-s3-origin'].OriginPath"*) printf '%s\n' "$FAKE_ORIGIN_PATH" ;;
      *) echo None ;;
    esac
    ;;
esac
FAKE
chmod +x "$fake"
export AWS_CLI="$fake" FAKE_LOG="$work/log"

reset() {
  : > "$FAKE_LOG"
  export FAKE_STACK_FAIL=0 FAKE_DISTRIBUTION_ID=E2ABCDEF123456 \
    FAKE_TARGET_ORIGIN=frontend-s3-origin FAKE_ORIGIN_PATH="/releases/$SHA"
}

deploy_line() { grep '^CALL cloudformation deploy ' "$FAKE_LOG"; }
runs() { if "$@" > /dev/null 2>&1; then echo pass; else echo fail; fi; }

# --- origin-path: 기본 동작 오리진의 경로를 그대로 출력한다
reset
check "origin-path 릴리스" "/releases/$SHA" "$(bash "$script" origin-path oncare-frontend 2> /dev/null)"
check "origin-path 조회 대상" "1" \
  "$(grep -c "CALL cloudfront get-distribution-config --id E2ABCDEF123456 --query DistributionConfig.Origins.Items\[?Id=='frontend-s3-origin'\]" "$FAKE_LOG")"
reset
FAKE_ORIGIN_PATH=""
check "origin-path 버킷 루트" "" "$(bash "$script" origin-path oncare-frontend 2> /dev/null)"
check "origin-path 버킷 루트 성공" "pass" "$(runs bash "$script" origin-path oncare-frontend)"

# --- origin-path: 읽지 못하거나 형식이 틀리면 실패한다
reset; FAKE_STACK_FAIL=1
check "스택 없음" "fail" "$(runs bash "$script" origin-path oncare-frontend)"
check "스택 없음 종료 코드" "3" "$(bash "$script" origin-path oncare-frontend > /dev/null 2>&1; echo $?)"
reset; FAKE_DISTRIBUTION_ID=None
check "DistributionId 없음" "fail" "$(runs bash "$script" origin-path oncare-frontend)"
reset; FAKE_TARGET_ORIGIN=None
check "기본 오리진 없음" "fail" "$(runs bash "$script" origin-path oncare-frontend)"
reset; FAKE_ORIGIN_PATH=None
check "오리진 없음" "fail" "$(runs bash "$script" origin-path oncare-frontend)"
for bad in "/releases/abc" "/releases/$SHA/" "/other" "releases/$SHA" "/releases/$(printf %s "$SHA" | tr a-f A-F)"; do
  reset; FAKE_ORIGIN_PATH="$bad"
  check "형식 밖 경로 '$bad'" "fail" "$(runs bash "$script" origin-path oncare-frontend)"
done

# --- deploy: 현재 경로를 ReleaseOriginPath 로 붙이고 다른 파라미터·플래그를 그대로 넘긴다
reset
bash "$script" deploy oncare-frontend > /dev/null 2>&1
check "deploy 기본" \
  "CALL cloudformation deploy --template-file infra/frontend-hosting.yml --stack-name oncare-frontend --capabilities CAPABILITY_IAM --region ap-northeast-2 --parameter-overrides ReleaseOriginPath=/releases/$SHA" \
  "$(deploy_line)"
reset
bash "$script" deploy oncare-frontend AlternateDomainName=app.example.com \
  AcmCertificateArn=arn:aws:acm:us-east-1:123456789012:certificate/x --no-execute-changeset > /dev/null 2>&1
check "deploy 파라미터·변경 세트만" \
  "CALL cloudformation deploy --template-file infra/frontend-hosting.yml --stack-name oncare-frontend --capabilities CAPABILITY_IAM --region ap-northeast-2 --parameter-overrides ReleaseOriginPath=/releases/$SHA AlternateDomainName=app.example.com AcmCertificateArn=arn:aws:acm:us-east-1:123456789012:certificate/x --no-execute-changeset" \
  "$(deploy_line)"
reset; FAKE_ORIGIN_PATH=""
bash "$script" deploy oncare-frontend > /dev/null 2>&1
case "$(deploy_line)" in
  *"--parameter-overrides ReleaseOriginPath=") check "deploy 버킷 루트" "ok" "ok" ;;
  *) check "deploy 버킷 루트" "ok" "$(deploy_line)" ;;
esac
reset
TEMPLATE=/tmp/t.yml AWS_REGION=us-east-1 bash "$script" deploy s > /dev/null 2>&1
case "$(deploy_line)" in
  *"--template-file /tmp/t.yml --stack-name s "*"--region us-east-1 "*) check "deploy 템플릿·리전 변경" "ok" "ok" ;;
  *) check "deploy 템플릿·리전 변경" "ok" "$(deploy_line)" ;;
esac

# --- deploy: 현재 경로를 못 읽으면 스택을 건드리지 않는다
for broken in FAKE_STACK_FAIL=1 FAKE_TARGET_ORIGIN=None FAKE_ORIGIN_PATH=None FAKE_ORIGIN_PATH=/other; do
  reset; export "${broken?}"
  check "deploy 실패 '$broken'" "fail" "$(runs bash "$script" deploy oncare-frontend)"
  check "deploy 호출 없음 '$broken'" "" "$(deploy_line)"
done

# --- deploy: ReleaseOriginPath 를 직접 넘기거나 형식 밖 인자는 거부한다
for args in "ReleaseOriginPath=/releases/$SHA" "ReleaseOriginPath=" "--force" "1Bad=x" "notakeyvalue"; do
  reset
  check "deploy 거부 '$args'" "fail" "$(runs bash "$script" deploy oncare-frontend "$args")"
  check "deploy 거부 호출 없음 '$args'" "" "$(deploy_line)"
done

# --- 잘못된 사용
check "명령 없음" "fail" "$(runs bash "$script")"
check "알 수 없는 명령" "fail" "$(runs bash "$script" nope)"
check "origin-path 인자 없음" "fail" "$(runs bash "$script" origin-path)"
check "deploy 인자 없음" "fail" "$(runs bash "$script" deploy)"

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
