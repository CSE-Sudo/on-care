#!/usr/bin/env bash
# 프론트 호스팅 스택(infra/frontend-hosting.yml) 조회·갱신(#3129).
#
# 릴리스 전환은 배포 워크플로가 CloudFront distribution 의 OriginPath 를 직접 바꾼다. 스택은
# 그 값을 ReleaseOriginPath 파라미터로만 알기 때문에, 이 값을 빼고(또는 옛 값으로) 스택을
# 갱신하면 CloudFormation 이 OriginPath 를 되돌려 사이트 전체가 빈 버킷 루트(403/404)나 옛
# 릴리스를 서비스한다. 그래서 스택 갱신은 이 스크립트로만 한다 — 살아 있는 distribution 에서
# 현재 OriginPath 를 읽어 언제나 ReleaseOriginPath 로 넘긴다.
#
# 사용
#   frontend_hosting_stack.sh origin-path <stack>
#       스택의 distribution 이 지금 기본 동작으로 서비스하는 오리진의 OriginPath 를 출력한다
#       (빈 값 또는 /releases/<40자 SHA>).
#   frontend_hosting_stack.sh deploy <stack> [Key=Value ...] [--no-execute-changeset]
#       현재 OriginPath 를 ReleaseOriginPath 로 붙여 `aws cloudformation deploy` 를 부른다.
#       Key=Value 는 함께 바꿀 다른 파라미터다(넘기지 않은 파라미터는 직전 값을 쓴다).
#       ReleaseOriginPath 를 직접 넘기면 거부한다.
#
# TEMPLATE(기본 infra/frontend-hosting.yml)·AWS_REGION(기본 ap-northeast-2) 으로 바꿀 수 있고,
# AWS_CLI 로 aws 명령을 바꿀 수 있다(검사 스크립트가 가짜 명령을 넣는다).
set -euo pipefail

AWS_CLI="${AWS_CLI:-aws}"
TEMPLATE="${TEMPLATE:-infra/frontend-hosting.yml}"
REGION="${AWS_REGION:-ap-northeast-2}"
ORIGIN_PATH_PATTERN='^(/releases/[0-9a-f]{40})?$'

usage() {
  echo "사용: $0 origin-path <stack> | deploy <stack> [Key=Value ...] [--no-execute-changeset]" >&2
  exit 2
}

distribution_id() {
  local stack="$1" id
  if ! id=$("$AWS_CLI" cloudformation describe-stacks --stack-name "$stack" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue | [0]" \
    --output text); then
    echo "::error::프론트 스택 $stack 을 읽지 못했습니다. 첫 생성은 docs/aws-frontend-deployment.md 2절대로 합니다." >&2
    return 3
  fi
  if ! [[ "$id" =~ ^[A-Z0-9]+$ ]]; then
    echo "::error::스택 $stack 의 DistributionId 출력을 읽지 못했습니다: '$id'" >&2
    return 1
  fi
  printf '%s\n' "$id"
}

origin_path() {
  local stack="$1" id origin path
  id=$(distribution_id "$stack") || return $?
  origin=$("$AWS_CLI" cloudfront get-distribution-config --id "$id" \
    --query 'DistributionConfig.DefaultCacheBehavior.TargetOriginId' --output text) || return 1
  if [ -z "$origin" ] || [ "$origin" = "None" ]; then
    echo "::error::distribution $id 의 기본 동작 오리진을 읽지 못했습니다." >&2
    return 1
  fi
  path=$("$AWS_CLI" cloudfront get-distribution-config --id "$id" \
    --query "DistributionConfig.Origins.Items[?Id=='$origin'].OriginPath | [0]" --output text) || return 1
  # text 출력에서 빈 문자열은 빈 줄로 나온다. 오리진이 없으면 None 이다.
  if [ "$path" = "None" ]; then
    echo "::error::distribution $id 에서 오리진 $origin 을 찾지 못했습니다." >&2
    return 1
  fi
  if ! [[ "$path" =~ $ORIGIN_PATH_PATTERN ]]; then
    echo "::error::지금 OriginPath '$path' 가 릴리스 형식(/releases/<40자 SHA>)이 아닙니다. 콘솔에서 직접 바꾼 값인지 확인합니다." >&2
    return 1
  fi
  printf '%s\n' "$path"
}

deploy() {
  local stack="$1"
  shift
  local overrides=() flags=() arg path
  for arg in "$@"; do
    case "$arg" in
      --no-execute-changeset) flags+=("$arg") ;;
      ReleaseOriginPath=*)
        echo "::error::ReleaseOriginPath 는 살아 있는 distribution 에서 읽습니다. 직접 넘기지 않습니다." >&2
        return 2
        ;;
      *=*)
        if ! [[ "$arg" =~ ^[A-Za-z][A-Za-z0-9]*= ]]; then
          echo "::error::파라미터는 Key=Value 형식이어야 합니다: '$arg'" >&2
          return 2
        fi
        overrides+=("$arg")
        ;;
      *)
        echo "::error::알 수 없는 인자: '$arg'" >&2
        return 2
        ;;
    esac
  done

  path=$(origin_path "$stack") || return $?
  if [ -z "$path" ]; then
    echo "::warning::distribution 이 아직 버킷 루트를 서비스합니다(첫 릴리스 전환 전). ReleaseOriginPath 를 빈 값으로 둡니다." >&2
  fi
  echo "ReleaseOriginPath=$path"

  # macOS 기본 bash 3.2 는 빈 배열을 "${a[@]}" 로 펼치면 set -u 에 걸린다.
  "$AWS_CLI" cloudformation deploy \
    --template-file "$TEMPLATE" \
    --stack-name "$stack" \
    --capabilities CAPABILITY_IAM \
    --region "$REGION" \
    --parameter-overrides "ReleaseOriginPath=$path" ${overrides[@]+"${overrides[@]}"} \
    ${flags[@]+"${flags[@]}"}
}

cmd="${1:-}"
shift || true

case "$cmd" in
  origin-path)
    [ "$#" -eq 1 ] || usage
    origin_path "$1"
    ;;
  deploy)
    [ "$#" -ge 1 ] || usage
    deploy "$@"
    ;;
  *) usage ;;
esac
