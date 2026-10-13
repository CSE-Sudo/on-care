#!/usr/bin/env bash
# 자동 배포가 운영에 이미 떠 있는 커밋이나 그보다 옛 커밋을 다시 올리지 않게 한다(#3254).
#
# 운영 프런트·백엔드 배포는 E2E CI·Backend CI 완료(workflow_run)로 시작한다. 취소된 main CI 를
# 나중에 Re-run 하면 그 완료가 옛 커밋 배포를 부르고, main 이력에 있는지만 보는 확인은 이를
# 막지 못한다. 배포 전에 운영에 떠 있는 커밋을 읽어 대상이 그 커밋과 같거나 그 조상이면
# 건너뛴다. 사람이 일부러 되돌리는 수동 실행(workflow_dispatch)에는 부르지 않는다.
#
# 사용
#   bash .github/scripts/deploy_freshness.sh frontend <CloudFront 배포 ID> <대상 40자 SHA>
#     지금 서비스 중인 릴리스의 origin path(`/releases/<SHA>`)에서 커밋을 읽는다. 배포가 그
#     릴리스에 넣는 version.txt 와 같은 값이다. aws 자격 증명이 필요하다.
#   bash .github/scripts/deploy_freshness.sh backend <API_BASE_URL> <대상 40자 SHA>
#     운영 백엔드 `<API_BASE_URL>/version` 의 commit_sha 를 읽는다(API_BASE_URL 은 …/v1).
#   저장소 checkout 안에서 실행한다(전체 이력 필요 — actions/checkout 의 fetch-depth: 0).
# 종료 코드
#   0  배포한다 — 대상이 더 새 커밋이거나, 운영 커밋을 읽지 못해 판단할 수 없음(경고만)
#   20 건너뛴다 — 대상이 운영 커밋과 같거나 그 조상
#   1  사용 오류(모드·SHA 형식, 저장소에 없는 대상)
# 표준 출력의 `live_sha=`·`state=` 줄은 GITHUB_OUTPUT 에 그대로 붙일 수 있다.
#   state: newer · same · older · unknown(운영 커밋을 못 읽음) · not-found(저장소에 없음) · diverged
set -uo pipefail

mode="${1:-}"
source="${2:-}"
target=$(printf '%s' "${3:-}" | tr '[:upper:]' '[:lower:]')

if ! [[ "$mode" =~ ^(frontend|backend)$ ]] || ! [[ "$target" =~ ^[0-9a-f]{40}$ ]]; then
  echo "사용: $0 <frontend|backend> <CloudFront 배포 ID|API_BASE_URL> <40자 SHA>" >&2
  exit 1
fi
if ! git cat-file -e "$target^{commit}" 2> /dev/null; then
  echo "::error::배포 대상 $target 을 저장소 이력에서 찾지 못했습니다(전체 이력 checkout 인지 확인)."
  exit 1
fi

# 운영 커밋을 읽지 못하면 지금처럼 배포하고 경고만 남긴다(첫 배포, 응답 없음 등).
proceed_unknown() {
  echo "live_sha=${1:-none}"
  echo "state=unknown"
  echo "::warning::운영 $mode 커밋을 읽지 못해 옛 커밋 재배포 여부를 판단하지 않고 배포합니다($2)."
  exit 0
}

live=""
if [ -z "$source" ]; then
  proceed_unknown "" "읽을 곳이 비어 있음"
elif [ "$mode" = frontend ]; then
  if ! config=$(aws cloudfront get-distribution-config --id "$source"); then
    proceed_unknown "" "CloudFront 배포 설정 조회 실패"
  fi
  # 기본 동작이 가리키는 origin 의 path 가 지금 서비스 중인 릴리스다(배포의 전환 단계와 같은 규칙).
  origin_path=$(printf '%s' "$config" | python3 -c '
import json, sys
try:
    config = json.load(sys.stdin)["DistributionConfig"]
    origin_id = config["DefaultCacheBehavior"]["TargetOriginId"]
    path = next(o.get("OriginPath") or "" for o in config["Origins"]["Items"] if o["Id"] == origin_id)
except (ValueError, KeyError, TypeError, StopIteration):
    path = ""
print(str(path).strip())
')
  if ! [[ "$origin_path" =~ ^/releases/[0-9a-fA-F]{40}$ ]]; then
    proceed_unknown "" "origin path '${origin_path:-없음}' 가 릴리스 경로가 아님"
  fi
  live="${origin_path#/releases/}"
else
  api="${source%/}"
  if ! body=$(curl --fail --silent --show-error --max-time 15 "$api/version"); then
    proceed_unknown "" "$api/version 응답 없음"
  fi
  live=$(printf '%s' "$body" | python3 -c '
import json, sys
try:
    value = json.load(sys.stdin).get("commit_sha") or ""
except (ValueError, AttributeError):
    value = ""
print(str(value).strip())
')
fi

live=$(printf '%s' "$live" | tr '[:upper:]' '[:lower:]')
if ! [[ "$live" =~ ^[0-9a-f]{40}$ ]]; then
  proceed_unknown "$live" "commit_sha '${live:-없음}'"
fi
echo "live_sha=$live"

if [ "$live" = "$target" ]; then
  echo "state=same"
  exit 20
fi
if ! git cat-file -e "$live^{commit}" 2> /dev/null; then
  echo "state=not-found"
  echo "::warning::운영 커밋 $live 을 저장소 이력에서 찾지 못해 선후를 판단하지 않고 배포합니다."
  exit 0
fi
if git merge-base --is-ancestor "$target" "$live"; then
  echo "state=older"
  exit 20
fi
if git merge-base --is-ancestor "$live" "$target"; then
  echo "state=newer"
  exit 0
fi
echo "state=diverged"
echo "::warning::운영 커밋 $live 과 대상 $target 의 이력이 갈라져 있어 선후를 판단하지 않고 배포합니다."
exit 0
