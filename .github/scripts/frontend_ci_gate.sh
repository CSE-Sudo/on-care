#!/usr/bin/env bash
# 운영 프론트 배포 전 CI 판정(#3018).
#
# 대상 커밋의 main push CI 결과를 GitHub API 로 읽어 배포해도 되는지 판정한다.
#  - E2E CI(e2e-ci.yml): paths 필터가 없어 모든 main push 에서 돈다 → 반드시 성공해야 한다.
#  - User App CI·Trainer CI: paths 필터가 있어 경로 밖 커밋에서는 실행이 없다 →
#    실행이 없으면 통과, 있으면 가장 최근 실행이 성공이어야 한다.
#
# 사용: GH_TOKEN=... GITHUB_REPOSITORY=owner/repo bash .github/scripts/frontend_ci_gate.sh <40자 SHA>
# 종료 코드: 0 배포 가능, 10 아직 도는 CI 가 있음(잠시 뒤 다시), 1 실패·오류
# 표준 출력의 `- <워크플로>: <판정>` 줄은 Step Summary 에 그대로 붙일 수 있다.
set -uo pipefail

sha="${1:-}"
repo="${GITHUB_REPOSITORY:-}"
REQUIRED_WORKFLOWS="${REQUIRED_WORKFLOWS:-e2e-ci.yml}"
OPTIONAL_WORKFLOWS="${OPTIONAL_WORKFLOWS:-user-app-ci.yml trainer-ci.yml}"

if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::대상 SHA 는 40자리 소문자 커밋 SHA 여야 합니다: '$sha'" >&2
  exit 1
fi
if [ -z "$repo" ]; then
  echo "::error::GITHUB_REPOSITORY 가 비어 있습니다." >&2
  exit 1
fi

# 가장 최근 실행 한 건의 "status conclusion" (실행이 없으면 빈 줄).
latest_run() {
  local workflow="$1"
  gh api --method GET "repos/$repo/actions/workflows/$workflow/runs" \
    -f head_sha="$sha" -f branch=main -f event=push -f per_page=20 \
    --jq '.workflow_runs | sort_by(.run_started_at) | reverse | .[0] // empty | "\(.status) \(.conclusion // "")"'
}

pending=0
failed=0

judge() {
  local workflow="$1" kind="$2" line status conclusion
  if ! line=$(latest_run "$workflow"); then
    echo "::error::$workflow 실행 기록을 읽지 못했습니다."
    failed=1
    return
  fi
  status="${line%% *}"
  conclusion="${line#* }"
  [ "$line" = "$status" ] && conclusion=""

  if [ -z "$line" ]; then
    if [ "$kind" = required ]; then
      # 필수 CI 는 모든 push 에서 돈다. 아직 생성되지 않았을 수 있어 기다린다.
      echo "- $workflow: 실행 없음(대기)"
      pending=1
    else
      echo "- $workflow: 실행 없음(경로 밖 — 통과)"
    fi
    return
  fi

  if [ "$status" != "completed" ]; then
    echo "- $workflow: 진행 중($status)"
    pending=1
    return
  fi

  if [ "$conclusion" = "success" ]; then
    echo "- $workflow: 성공"
  else
    echo "- $workflow: 실패($conclusion)"
    echo "::error::$workflow 가 $sha 에서 '$conclusion' 입니다. 운영 프론트 배포를 멈춥니다."
    failed=1
  fi
}

for workflow in $REQUIRED_WORKFLOWS; do judge "$workflow" required; done
for workflow in $OPTIONAL_WORKFLOWS; do judge "$workflow" optional; done

if [ "$failed" -ne 0 ]; then exit 1; fi
if [ "$pending" -ne 0 ]; then exit 10; fi
exit 0
