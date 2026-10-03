#!/usr/bin/env bash
# 운영 프론트 배포 전 백엔드 선후 확인(#3018).
#
# 한 커밋이 백엔드 API 와 두 앱 화면을 함께 바꾸면, 프론트가 먼저 전환될 때 운영 화면이
# 아직 없는 API 를 부른다. 지금 떠 있는 백엔드의 커밋(`/version` 의 `commit_sha`)과 배포할
# 커밋을 비교해, 배포할 커밋에 아직 운영에 없는 backend/ 변경이 있는지 본다.
#
# 사용: bash .github/scripts/frontend_backend_order.sh <API_BASE_URL> <대상 40자 SHA>
#   API_BASE_URL 은 두 앱이 쓰는 값 그대로(…/v1). 저장소 checkout 안에서 실행한다
#   (전체 이력 필요 — actions/checkout 의 fetch-depth: 0).
# 종료 코드
#   0  진행해도 됨(백엔드가 같은 커밋이거나, 그 뒤로 backend/ 변경이 없거나, 백엔드가 더 새 커밋)
#   10 아직 배포되지 않은 backend/ 변경이 있음(백엔드 배포를 기다린다)
#   11 백엔드가 커밋을 알려 주지 않음(commit_sha 없음·unknown)
#   1  오류(응답 실패, 저장소에 없는 커밋, 갈라진 이력)
# 표준 출력의 `backend_sha=`·`state=` 줄은 GITHUB_OUTPUT 에 그대로 붙일 수 있다.
set -uo pipefail

api="${1:-}"
target="${2:-}"
BACKEND_PATHS="${BACKEND_PATHS:-backend/}"

if [ -z "$api" ] || ! [[ "$target" =~ ^[0-9a-f]{40}$ ]]; then
  echo "사용: $0 <API_BASE_URL> <40자 SHA>" >&2
  exit 1
fi
api="${api%/}"

if ! body=$(curl --fail --silent --show-error --max-time 15 "$api/version"); then
  echo "::error::운영 백엔드 $api/version 응답을 받지 못했습니다."
  exit 1
fi

backend=$(printf '%s' "$body" | python3 -c '
import json, sys
try:
    value = json.load(sys.stdin).get("commit_sha") or ""
except (ValueError, AttributeError):
    value = ""
print(str(value).strip().lower())
')

if ! [[ "$backend" =~ ^[0-9a-f]{40}$ ]]; then
  echo "backend_sha=${backend:-none}"
  echo "state=unknown"
  echo "::warning::운영 백엔드가 commit_sha 를 알려 주지 않습니다('${backend:-없음}'). 선후를 판단할 수 없습니다."
  exit 11
fi
echo "backend_sha=$backend"

if [ "$backend" = "$target" ]; then
  echo "state=same"
  exit 0
fi

if ! git cat-file -e "$backend^{commit}" 2> /dev/null; then
  echo "state=error"
  echo "::error::운영 백엔드 커밋 $backend 을 저장소 이력에서 찾지 못했습니다(전체 이력 checkout 인지 확인)."
  exit 1
fi

# 백엔드가 더 새 커밋이면(대상이 백엔드의 조상) 프론트가 뒤따라가는 경우라 문제없다 —
# 백엔드 API 는 하위 호환을 지킨다(backend/docs/DEPLOY.md 마이그레이션 호환 규칙).
if git merge-base --is-ancestor "$target" "$backend"; then
  echo "state=backend-ahead"
  exit 0
fi

if git merge-base --is-ancestor "$backend" "$target"; then
  # shellcheck disable=SC2086 # 경로 목록은 공백으로 나눈다.
  if git diff --quiet "$backend" "$target" -- $BACKEND_PATHS; then
    echo "state=no-backend-change"
    exit 0
  fi
  echo "state=pending"
  echo "변경된 백엔드 파일(일부):"
  # shellcheck disable=SC2086
  git diff --name-only "$backend" "$target" -- $BACKEND_PATHS | head -20 | sed 's/^/  /'
  exit 10
fi

echo "state=error"
echo "::error::운영 백엔드 커밋 $backend 과 대상 $target 의 이력이 갈라져 있습니다."
exit 1
