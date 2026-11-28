#!/usr/bin/env bash
# 운영 배포 직전 DB 백업(#1552, backend/docs/DEPLOY.md 2-1).
#
# 사용
#   backend_db_backup.sh run <stack> <sha>
#       서비스 스택(infra/backend-service.yml)의 백업 작업 정의를 서비스와 같은 클러스터·서브넷·
#       보안 그룹으로 한 번 띄우고, 끝날 때까지 기다린 뒤 S3 에 덤프가 올라왔는지 본다.
#       성공하면 올린 객체 키(`db/<UTC 시각>-<커밋 앞 12자>.dump`)를 출력한다.
#
# 종료 코드: 0 성공, 1 백업 실패(배포를 멈춘다), 2 사용법, 3 스택에 백업 작업 정의가 없음.
#
# 환경변수(시험용): BACKUP_WAIT_SECONDS(기본 1800), BACKUP_POLL_SECONDS(기본 10).
set -euo pipefail

CONTAINER=db-backup

usage() {
  echo "사용: $0 run <stack> <sha>" >&2
  exit 2
}

stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue | [0]" \
    --output text
}

# 실패한 작업의 로그 끝부분을 남긴다. 읽지 못해도 백업 실패 판정은 바뀌지 않는다.
show_logs() {
  local group="$1" task_id="$2"
  [ -n "$group" ] && [ "$group" != "None" ] || return 0
  echo "::group::백업 작업 로그($group)" >&2
  aws logs get-log-events --log-group-name "$group" \
    --log-stream-name "$CONTAINER/$CONTAINER/$task_id" \
    --limit 50 --query 'events[].message' --output text >&2 || true
  echo "::endgroup::" >&2
}

cmd="${1:-}"
shift || true
[ "$cmd" = "run" ] || usage
[ "$#" -eq 2 ] || usage
stack="$1" sha="$2"
if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::40자리 커밋 SHA 가 아닙니다: '$sha'" >&2
  exit 2
fi

task_def="$(stack_output "$stack" BackupTaskDefinitionArn)"
if [ -z "$task_def" ] || [ "$task_def" = "None" ]; then
  echo "::error::스택 $stack 에 BackupTaskDefinitionArn 출력이 없습니다. 이 커밋의 infra/backend-service.yml 로 스택을 한 번 갱신하고, 환경 스택에 백업 버킷이 있는지 봅니다(DEPLOY.md 2-1)." >&2
  exit 3
fi
service_arn="$(stack_output "$stack" ServiceArn)"
bucket="$(stack_output "$stack" BackupBucketName)"
log_group="$(stack_output "$stack" BackupLogGroupName)"

# arn:aws:ecs:<리전>:<계정>:service/<클러스터>/<서비스>
if ! [[ "$service_arn" =~ ^arn:aws[a-z-]*:ecs:[a-z0-9-]+:[0-9]{12}:service/([^/]+)/([^/]+)$ ]]; then
  echo "::error::스택 $stack 의 ServiceArn 을 읽지 못했습니다: '$service_arn'" >&2
  exit 1
fi
cluster="${BASH_REMATCH[1]}"
service="${BASH_REMATCH[2]}"

# 서비스가 쓰는 서브넷·보안 그룹·공인 IP 설정을 그대로 쓴다 — 서비스와 같은 길로 DB 에 닿는다.
# Express Mode 서비스는 최상위 networkConfiguration 이 비어(null) 있고 지금 배포(PRIMARY)에만
# 들어 있다. 보안 그룹은 빈 목록일 수 있다 — 그러면 VPC 기본 보안 그룹으로 나간다(밖으로 나가는
# 연결만 쓰므로 충분하다).
network="$(aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query "services[0].deployments[?status=='PRIMARY'] | [0].networkConfiguration" --output json)"
if ! grep -q '"subnet-' <<< "$network"; then
  echo "::error::서비스 $service 의 네트워크 설정(서브넷)을 읽지 못했습니다." >&2
  exit 1
fi

# 키는 여기서만 만든다(영숫자·`-`·`.` 뿐이라 JSON 에 그대로 넣어도 된다).
key="db/$(date -u +%Y%m%dT%H%M%SZ)-${sha:0:12}.dump"
overrides="{\"containerOverrides\":[{\"name\":\"$CONTAINER\",\"environment\":[{\"name\":\"BACKUP_OBJECT_KEY\",\"value\":\"$key\"}]}]}"

started="$(aws ecs run-task --cluster "$cluster" --task-definition "$task_def" \
  --launch-type FARGATE --count 1 --started-by github-deploy-backup \
  --network-configuration "$network" --overrides "$overrides" \
  --query '[tasks[0].taskArn, length(failures), join(`; `, failures[].reason)]' --output text)"
IFS=$'\t' read -r task_arn failures reasons <<< "$started"
if [ "$failures" != "0" ] || [ -z "$task_arn" ] || [ "$task_arn" = "None" ]; then
  echo "::error::백업 작업을 띄우지 못했습니다: ${reasons:-$started}" >&2
  exit 1
fi
task_id="${task_arn##*/}"
echo "백업 작업 시작: $task_arn → s3://$bucket/$key" >&2

# 시간 초과·조회 오류·잡 취소로 여기서 끝나면 작업을 멈춘다 — 다시 돌릴 때 백업이 겹쳐 DB 부하와
# Fargate 요금이 쌓이지 않게.
task_stopped=0
stop_task() {
  [ "$task_stopped" = "1" ] && return 0
  echo "백업 작업을 멈춥니다: $task_arn" >&2
  aws ecs stop-task --cluster "$cluster" --task "$task_arn" \
    --reason "deploy backup step ended" > /dev/null 2>&1 || true
}
trap stop_task EXIT

# 마감은 실제 경과 시간으로 잰다(AWS 호출 시간 포함).
wait_seconds="${BACKUP_WAIT_SECONDS:-1800}"
poll="${BACKUP_POLL_SECONDS:-10}"
deadline=$((SECONDS + wait_seconds))
while :; do
  state="$(aws ecs describe-tasks --cluster "$cluster" --tasks "$task_arn" \
    --query "tasks[0].[lastStatus, containers[?name=='$CONTAINER'] | [0].exitCode, stoppedReason]" \
    --output text)"
  IFS=$'\t' read -r status exit_code reason <<< "$state"
  if [ "$status" = "STOPPED" ]; then
    task_stopped=1
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "::error::백업 작업이 ${wait_seconds}초 안에 끝나지 않았습니다(상태 ${status:-알 수 없음}). 배포를 멈춥니다." >&2
    exit 1
  fi
  sleep "$poll"
done

if [ "$exit_code" != "0" ]; then
  [ "$reason" = "None" ] && reason=""
  echo "::error::백업 작업 실패(종료 코드 $exit_code${reason:+, $reason}). 운영 배포를 멈춥니다." >&2
  show_logs "$log_group" "$task_id"
  exit 1
fi

size="$(aws s3api list-objects-v2 --bucket "$bucket" --prefix "$key" \
  --query "Contents[?Key=='$key'].Size | [0]" --output text)"
if ! [[ "$size" =~ ^[0-9]+$ ]] || [ "$size" -eq 0 ]; then
  echo "::error::백업 작업은 끝났지만 s3://$bucket/$key 에 덤프가 없습니다('$size'). 운영 배포를 멈춥니다." >&2
  show_logs "$log_group" "$task_id"
  exit 1
fi

echo "백업 완료: s3://$bucket/$key ($size bytes)" >&2
printf '%s\n' "$key"
