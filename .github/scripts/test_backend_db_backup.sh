#!/usr/bin/env bash
# backend_db_backup.sh 검사(#1552). AWS CLI 를 가짜 실행 파일로 바꿔, 백업 작업이 실패하거나
# 덤프가 없으면 0 이 아닌 값으로 끝나(운영 배포를 멈추고) 성공하면 객체 키만 출력하는지 본다.
# 사용: bash .github/scripts/test_backend_db_backup.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/backend_db_backup.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

SHA=0123456789abcdef0123456789abcdef01234567
SERVICE_ARN='arn:aws:ecs:ap-southeast-1:123456789012:service/default/oncare-backend-production'
TASK_ARN='arn:aws:ecs:ap-southeast-1:123456789012:task/default/abc123'
NETWORK='{"awsvpcConfiguration":{"subnets":["subnet-1","subnet-2"],"securityGroups":["sg-1"],"assignPublicIp":"ENABLED"}}'

# 가짜 aws: FAKE_* 로 응답을 정하고 호출 인자를 기록한다. describe-tasks 는 FAKE_RUNNING_POLLS 번
# RUNNING 을 돌려준 뒤 STOPPED 가 된다.
mkdir -p "$work/bin"
cat > "$work/bin/aws" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$1 $2" in
  "cloudformation describe-stacks")
    case "$*" in
      *BackupTaskDefinitionArn*) printf '%s\n' "${FAKE_TASK_DEF-arn:aws:ecs:ap-southeast-1:123456789012:task-definition/oncare-backend-production-db-backup:3}" ;;
      *ServiceArn*) printf '%s\n' "$FAKE_SERVICE_ARN" ;;
      *BackupBucketName*) echo oncare-db-backups-123456789012-ap-southeast-1-production ;;
      *BackupLogGroupName*) echo /oncare/backend/production/db-backup ;;
    esac ;;
  "ecs describe-services") printf '%s\n' "$FAKE_NETWORK" ;;
  "ecs run-task") printf '%s\t%s\t%s\n' "${FAKE_TASK_ARN-None}" "${FAKE_RUN_FAILURES:-0}" "${FAKE_RUN_REASON:-}" ;;
  "ecs describe-tasks")
    n=$(cat "$FAKE_POLLS" 2> /dev/null || echo 0)
    echo $((n + 1)) > "$FAKE_POLLS"
    if [ "$n" -lt "${FAKE_RUNNING_POLLS:-0}" ]; then
      printf 'RUNNING\tNone\tNone\n'
    else
      printf 'STOPPED\t%s\t%s\n' "${FAKE_EXIT_CODE:-0}" "${FAKE_STOPPED_REASON:-Essential container in task exited}"
    fi ;;
  "s3api list-objects-v2") printf '%s\n' "${FAKE_SIZE:-2048}" ;;
  "logs get-log-events") echo "[backup] ERROR: pg_dump 실패" ;;
esac
exit 0
FAKE
chmod +x "$work/bin/aws"

export FAKE_SERVICE_ARN="$SERVICE_ARN" FAKE_NETWORK="$NETWORK" FAKE_TASK_ARN="$TASK_ARN"

run() {
  rm -f "$work/polls"
  PATH="$work/bin:$PATH" FAKE_LOG="$work/log" FAKE_POLLS="$work/polls" \
    BACKUP_POLL_SECONDS=0 bash "$script" "$@"
}

check() {
  local label="$1" want_rc="$2" want_out="$3" got_rc got_out
  shift 3
  : > "$work/log"
  got_out="$(run "$@" 2> /dev/null)"
  got_rc=$?
  if [ "$got_rc" != "$want_rc" ] || { [ -n "$want_out" ] && ! [[ "$got_out" =~ $want_out ]]; }; then
    echo "FAIL: $label -> rc=$got_rc out='$got_out' (기대: rc=$want_rc out=~'$want_out')"
    failures=$((failures + 1))
  else
    echo "ok:   $label"
  fi
}

expect_log() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$work/log"; then
    echo "ok:   $label"
  else
    echo "FAIL: $label — 호출 기록에 '$needle' 없음"
    failures=$((failures + 1))
  fi
}

KEY_RE='^db/[0-9]{8}T[0-9]{6}Z-0123456789ab\.dump$'

# 성공 — 키만 출력, 서비스의 클러스터·네트워크를 그대로 넘긴다
FAKE_RUNNING_POLLS=2 check "작업이 끝나고 덤프가 있으면 성공" 0 "$KEY_RE" run oncare-backend-production "$SHA"
expect_log "서비스 클러스터에서 띄움" "ecs run-task --cluster default --task-definition arn:aws:ecs:ap-southeast-1:123456789012:task-definition/oncare-backend-production-db-backup:3 --launch-type FARGATE"
expect_log "서비스 네트워크 설정을 그대로 넘김" "--network-configuration $NETWORK"
expect_log "객체 키를 컨테이너 환경변수로 넘김" '"name":"BACKUP_OBJECT_KEY","value":"db/'
expect_log "서비스 이름으로 네트워크 조회" "ecs describe-services --cluster default --services oncare-backend-production"
# Express Mode 는 최상위 networkConfiguration 이 null 이라 지금 배포(PRIMARY)의 값을 읽어야 한다.
expect_log "PRIMARY 배포의 네트워크 설정을 읽음" "deployments[?status=='PRIMARY'] | [0].networkConfiguration"

# 실패 — 모두 0 이 아니어야 운영 배포가 멈춘다
FAKE_EXIT_CODE=1 check "백업 컨테이너 종료 코드 1" 1 "" run oncare-backend-production "$SHA"
expect_log "실패하면 작업 로그를 읽음" "logs get-log-events --log-group-name /oncare/backend/production/db-backup --log-stream-name db-backup/db-backup/abc123"
FAKE_EXIT_CODE=None FAKE_STOPPED_REASON='CannotPullContainerError' check "컨테이너가 뜨지도 못함" 1 "" run oncare-backend-production "$SHA"
FAKE_SIZE=None check "작업은 끝났지만 덤프가 없음" 1 "" run oncare-backend-production "$SHA"
FAKE_SIZE=0 check "빈 덤프" 1 "" run oncare-backend-production "$SHA"
FAKE_RUN_FAILURES=1 FAKE_RUN_REASON=RESOURCE:ENI FAKE_TASK_ARN=None check "작업을 띄우지 못함" 1 "" run oncare-backend-production "$SHA"
FAKE_RUNNING_POLLS=100 BACKUP_WAIT_SECONDS=0 check "시간 안에 끝나지 않음" 1 "" run oncare-backend-production "$SHA"
expect_log "시간 초과면 작업을 멈춤" "ecs stop-task --cluster default --task $TASK_ARN"

# 끝난 작업은 멈추지 않는다
FAKE_RUNNING_POLLS=1 check "성공(멈춤 호출 확인용)" 0 "$KEY_RE" run oncare-backend-production "$SHA"
if grep -q "ecs stop-task" "$work/log"; then
  echo "FAIL: 이미 끝난 작업에 stop-task 를 불렀습니다"; failures=$((failures + 1))
else
  echo "ok:   끝난 작업은 멈추지 않음"
fi
FAKE_NETWORK='null' check "서비스 네트워크를 못 읽음" 1 "" run oncare-backend-production "$SHA"
FAKE_SERVICE_ARN='None' check "서비스 ARN 을 못 읽음" 1 "" run oncare-backend-production "$SHA"
FAKE_TASK_DEF='None' check "백업 작업 정의 없는 스택은 종료 코드 3" 3 "" run oncare-backend-production "$SHA"

# 사용법
check "짧은 SHA 거부" 2 "" run oncare-backend-production 0123456
check "인자 부족" 2 "" run oncare-backend-production
check "모르는 명령" 2 "" backup oncare-backend-production "$SHA"

if [ "$failures" -ne 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
