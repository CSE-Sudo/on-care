#!/usr/bin/env bash
# backend_service_stack.sh 검사(#3016, #3019). AWS CLI 를 가짜 실행 파일로 바꿔
# 스택 조회·갱신·엔드포인트 정규화와 롤백에 쓰는 직전 이미지 읽기를 확인한다.
# 사용: bash .github/scripts/test_backend_service_stack.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/backend_service_stack.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

IMAGE_A='123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/oncare-backend@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
IMAGE_B='123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/oncare-backend@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

# 가짜 aws: FAKE_STACK_EXISTS·FAKE_IMAGE·FAKE_ENDPOINT 로 응답을 정하고 호출 인자를 기록한다.
mkdir -p "$work/bin"
cat > "$work/bin/aws" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
if [ "$1 $2" = "cloudformation describe-stacks" ]; then
  [ "${FAKE_STACK_EXISTS:-1}" = "1" ] || exit 254
  case "$*" in
    *ImageIdentifier*) printf '%s\n' "${FAKE_IMAGE:-None}" ;;
    *ServiceEndpoint*) printf '%s\n' "${FAKE_ENDPOINT:-None}" ;;
    *) echo '{}' ;;
  esac
  exit 0
fi
if [ "$1 $2" = "cloudformation deploy" ]; then
  exit "${FAKE_DEPLOY_RC:-0}"
fi
exit 0
FAKE
chmod +x "$work/bin/aws"
touch "$work/template.yml"

run() {
  PATH="$work/bin:$PATH" FAKE_LOG="$work/log" bash "$script" "$@"
}

check() {
  local label="$1" want_rc="$2" want_out="$3" got_rc got_out
  shift 3
  : > "$work/log"
  got_out="$(run "$@" 2> /dev/null)"
  got_rc=$?
  if [ "$got_rc" != "$want_rc" ] || { [ -n "$want_out" ] && [ "$got_out" != "$want_out" ]; }; then
    echo "FAIL: $label -> rc=$got_rc out='$got_out' (기대: rc=$want_rc out='$want_out')"
    failures=$((failures + 1))
  else
    echo "ok:   $label"
  fi
}

# current-image — 롤백 지점
FAKE_IMAGE="$IMAGE_A" check "직전 이미지 읽기" 0 "$IMAGE_A" current-image oncare-backend-production
export FAKE_IMAGE="$IMAGE_A"
FAKE_STACK_EXISTS=0 check "스택 없음은 종료 코드 3" 3 "" current-image oncare-backend-production
FAKE_IMAGE='None' check "이미지 파라미터 없음" 1 "" current-image oncare-backend-production
FAKE_IMAGE='oncare-backend:latest' check "digest 가 아닌 이미지" 1 "" current-image oncare-backend-production

# deploy — ImageIdentifier 하나만 넘기고, 빈 변경도 성공
check "새 digest 로 갱신" 0 "" deploy oncare-backend-production "$work/template.yml" arn:aws:iam::123456789012:role/cfn "$IMAGE_B"
if ! grep -q -- "--parameter-overrides ImageIdentifier=$IMAGE_B --no-fail-on-empty-changeset" "$work/log"; then
  echo "FAIL: deploy 가 ImageIdentifier 만 덮어쓰고 빈 변경을 허용해야 합니다"; failures=$((failures + 1))
else
  echo "ok:   deploy 인자(ImageIdentifier 만, 빈 변경 허용)"
fi
if ! grep -q -- "--role-arn arn:aws:iam::123456789012:role/cfn" "$work/log"; then
  echo "FAIL: deploy 가 CloudFormation 서비스 역할을 넘겨야 합니다"; failures=$((failures + 1))
else
  echo "ok:   deploy 가 CloudFormation 서비스 역할을 넘김"
fi
check "태그 이미지는 거부" 1 "" deploy oncare-backend-production "$work/template.yml" arn:aws:iam::123456789012:role/cfn 'oncare-backend:latest'
check "템플릿 없음" 1 "" deploy oncare-backend-production "$work/missing.yml" arn:aws:iam::123456789012:role/cfn "$IMAGE_B"
FAKE_STACK_EXISTS=0 check "스택이 없으면 만들지 않음" 3 "" deploy oncare-backend-production "$work/template.yml" arn:aws:iam::123456789012:role/cfn "$IMAGE_B"
FAKE_DEPLOY_RC=255 check "스택 갱신 실패 전달" 255 "" deploy oncare-backend-production "$work/template.yml" arn:aws:iam::123456789012:role/cfn "$IMAGE_B"
check "인자 부족" 2 "" deploy oncare-backend-production

# endpoint — 호스트만
FAKE_ENDPOINT='oncare-backend-production.ecs.ap-southeast-1.on.aws' check "호스트 그대로" 0 'oncare-backend-production.ecs.ap-southeast-1.on.aws' endpoint s
FAKE_ENDPOINT='https://oncare-backend-production.ecs.ap-southeast-1.on.aws/' check "scheme·끝 / 제거" 0 'oncare-backend-production.ecs.ap-southeast-1.on.aws' endpoint s
FAKE_ENDPOINT='None' check "엔드포인트 없음" 1 "" endpoint s

check "알 수 없는 명령" 2 "" status s

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
