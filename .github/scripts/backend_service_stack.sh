#!/usr/bin/env bash
# 백엔드 서비스 스택(infra/backend-service.yml) 조회·갱신(#3016, #3019).
#
# 사용
#   backend_service_stack.sh current-image <stack>
#       지금 스택이 선언한 이미지 digest 를 출력한다. 스택이 없으면 종료 코드 3.
#   backend_service_stack.sh deploy <stack> <template> <cfn-role-arn> <image>
#       ImageIdentifier 만 바꿔 스택을 갱신한다. 나머지 파라미터는 직전 값을 쓴다.
#       바뀐 것이 없으면(같은 digest) 그대로 성공한다.
#   backend_service_stack.sh endpoint <stack>
#       ServiceEndpoint 출력을 호스트 이름만 남겨 출력한다(scheme·끝 / 제거).
#
# 서비스 설정의 원본은 템플릿과 스택 파라미터다. 콘솔에서 서비스를 직접 고치면 다음
# 배포가 템플릿 값으로 되돌린다.
set -euo pipefail

IMAGE_PATTERN='^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/oncare-backend@sha256:[0-9a-f]{64}$'

usage() {
  echo "사용: $0 current-image <stack> | deploy <stack> <template> <cfn-role-arn> <image> | endpoint <stack>" >&2
  exit 2
}

stack_exists() {
  aws cloudformation describe-stacks --stack-name "$1" > /dev/null 2>&1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  current-image)
    [ "$#" -eq 1 ] || usage
    stack="$1"
    if ! stack_exists "$stack"; then
      echo "::error::서비스 스택 $stack 이 없습니다. 첫 생성은 backend/docs/DEPLOY.md 3절대로 먼저 만듭니다(#480)." >&2
      exit 3
    fi
    image="$(aws cloudformation describe-stacks --stack-name "$stack" \
      --query "Stacks[0].Parameters[?ParameterKey=='ImageIdentifier'].ParameterValue | [0]" \
      --output text)"
    if ! [[ "$image" =~ $IMAGE_PATTERN ]]; then
      echo "::error::스택 $stack 의 ImageIdentifier 를 읽지 못했습니다: '$image'" >&2
      exit 1
    fi
    printf '%s\n' "$image"
    ;;
  deploy)
    [ "$#" -eq 4 ] || usage
    stack="$1" template="$2" role="$3" image="$4"
    if ! [[ "$image" =~ $IMAGE_PATTERN ]]; then
      echo "::error::불변 digest 형식의 이미지가 아닙니다: '$image'" >&2
      exit 1
    fi
    if [ ! -f "$template" ]; then
      echo "::error::템플릿 파일이 없습니다: $template" >&2
      exit 1
    fi
    if ! stack_exists "$stack"; then
      echo "::error::서비스 스택 $stack 이 없습니다. 워크플로는 스택을 새로 만들지 않습니다(#480)." >&2
      exit 3
    fi
    aws cloudformation deploy \
      --stack-name "$stack" \
      --template-file "$template" \
      --role-arn "$role" \
      --parameter-overrides "ImageIdentifier=$image" \
      --no-fail-on-empty-changeset
    ;;
  endpoint)
    [ "$#" -eq 1 ] || usage
    stack="$1"
    raw="$(aws cloudformation describe-stacks --stack-name "$stack" \
      --query "Stacks[0].Outputs[?OutputKey=='ServiceEndpoint'].OutputValue | [0]" \
      --output text)"
    host="${raw#https://}"
    host="${host#http://}"
    host="${host%%/*}"
    if [ -z "$host" ] || [ "$host" = "None" ]; then
      echo "::error::스택 $stack 에 ServiceEndpoint 출력이 없습니다." >&2
      exit 1
    fi
    printf '%s\n' "$host"
    ;;
  *)
    usage
    ;;
esac
