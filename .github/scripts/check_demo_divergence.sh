#!/usr/bin/env bash
# 화면 코드에 새로 들어온 데모 분기를 드러낸다(#2791).
#
# 데모(`USE_MOCK_API`)와 실서버 화면이 다르면 데모가 기준이고, 실서버에 있는데
# 데모에 없는 것은 데모에 추가한다. 이 검사는 그 원칙을 어길 수 있는 변경을
# PR 단계에서 보이게 한다. base 와의 diff 에서 **추가된 줄**만 본다.
#
#   1. 화면 코드(presentation/pages·widgets, shared/widgets)의 `useMockApi` 참조
#   2. 데모·목업 저장소(파일·클래스 이름에 demo·mock)의 `bool get supports… => false`
#
# 저장소를 고르는 provider·controller(presentation/controllers)는 정상 구조라 보지
# 않는다. 일부러 다르게 둔 곳은 예외 목록에 `경로 · 이유 · #이슈` 로 적으면 통과한다.
#
# 사용: check_demo_divergence.sh <base-rev>   (저장소 루트에서, HEAD 와 비교)
# 환경: DEMO_DIVERGENCE_ALLOWLIST  예외 목록 경로(기본 .github/demo-divergence-allowlist.txt)
#       DEMO_DIVERGENCE_MODE       warn(기본, 항상 0 으로 끝남) | fail(걸리면 1)
#       GITHUB_STEP_SUMMARY        있으면 job 요약에 결과를 덧붙인다
set -euo pipefail

base="${1:?base rev 가 필요합니다}"
allowlist="${DEMO_DIVERGENCE_ALLOWLIST:-.github/demo-divergence-allowlist.txt}"
mode="${DEMO_DIVERGENCE_MODE:-warn}"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

# --- 예외 목록: `경로 · 이유 · #이슈`. `#` 로 시작하는 줄과 빈 줄은 건너뛴다.
declare -A allowed=()
if [ -f "$allowlist" ]; then
  n=0
  while IFS= read -r raw || [ -n "$raw" ]; do
    n=$((n + 1))
    line="${raw%$'\r'}"
    case "$line" in '' | '#'*) continue ;; esac
    path=$(printf '%s' "$line" | awk -F ' · ' '{ print $1 }')
    issue=$(printf '%s' "$line" | awk -F ' · ' 'NF >= 3 { print $3 }')
    if ! printf '%s' "$issue" | grep -qE '#[0-9]+'; then
      echo "::warning file=$allowlist,line=$n,title=예외 목록 형식::'경로 · 이유 · #이슈' 형식이 아니라 무시합니다: $line"
      continue
    fi
    allowed["$path"]=1
  done < "$allowlist"
fi

# --- 추가된 줄: kind<TAB>path<TAB>line<TAB>text
hits=$(git -c core.quotePath=false diff -U0 --no-color --no-ext-diff "$base" HEAD -- 'frontend/' | awk '
  /^\+\+\+ / { path = substr($0, 7); next }   # "+++ b/<path>"
  /^@@ / {
    split($3, a, ",")                          # "+start,count"
    ln = substr(a[1], 2) + 0
    next
  }
  /^\+/ {
    text = substr($0, 2)
    code = text
    sub(/^[ \t]+/, "", code)
    if (code !~ /^\/\//) {
      screen = path ~ /^frontend\/[^\/]+\/lib\/(.*\/)?presentation\/(pages|widgets)\// \
            || path ~ /^frontend\/[^\/]+\/lib\/shared\/widgets\//
      if (screen && text ~ /(^|[^A-Za-z0-9_])useMockApi([^A-Za-z0-9_]|$)/)
        printf "mock\t%s\t%d\t%s\n", path, ln, text
      if (path ~ /^frontend\/[^\/]+\/lib\/.*\.dart$/ \
          && text ~ /bool[ \t]+get[ \t]+supports[A-Za-z0-9_]*[ \t]*=>[ \t]*false/)
        printf "flag\t%s\t%d\t%s\n", path, ln, text
    }
    ln++
  }
')

# 줄이 속한 클래스 이름(그 줄 위에서 가장 가까운 class 선언).
class_at() {
  git show "HEAD:$1" | awk -v n="$2" '
    NR > n { exit }
    match($0, /class[ \t]+[A-Za-z0-9_]+/) && $0 !~ /^[ \t]*\/\// {
      name = substr($0, RSTART, RLENGTH); sub(/class[ \t]+/, "", name)
    }
    END { print name }'
}

warned=0
passed=0
report=""
while IFS=$'\t' read -r kind path line text; do
  [ -n "${kind:-}" ] || continue
  if [ "$kind" = flag ]; then
    cls=$(class_at "$path" "$line")
    if ! printf '%s %s' "${path##*/}" "$cls" | grep -qiE 'demo|mock'; then
      continue # 실서버 저장소가 끈 기능은 데모 분기가 아니다
    fi
    what="데모 저장소가 기능을 끕니다(${cls:-?})"
  else
    what="화면 코드가 useMockApi 로 갈라집니다"
  fi
  if [ -n "${allowed[$path]:-}" ]; then
    passed=$((passed + 1))
    echo "예외 목록으로 통과: $path:$line"
    continue
  fi
  warned=$((warned + 1))
  echo "::warning file=$path,line=$line,title=데모 분기::$what. 데모가 기준입니다 — 실서버에만 있는 것은 데모에도 넣고, 일부러 다르게 둔다면 $allowlist 에 '경로 · 이유 · #이슈' 로 적어 주세요(#2791)."
  report="$report| \`$path:$line\` | $what |"$'\n'
done <<< "$hits"

{
  echo "### 데모 분기 검사 (#2791, ${mode} 모드)"
  echo
  if [ "$warned" -eq 0 ]; then
    echo "새로 들어온 데모 분기 없음 (예외 목록 통과 ${passed}건)."
  else
    echo "예외 목록에 없는 데모 분기 ${warned}건 (예외 목록 통과 ${passed}건)."
    echo
    echo "| 위치 | 내용 |"
    echo "| --- | --- |"
    printf '%s' "$report"
    echo
    echo "데모가 기준입니다. 일부러 다르게 둔 것이라면 \`$allowlist\` 에 \`경로 · 이유 · #이슈\` 한 줄을 더하세요."
  fi
} >> "$summary"

echo "데모 분기: 경고 ${warned}건, 예외 목록 통과 ${passed}건 ($base..HEAD)."
if [ "$mode" = fail ] && [ "$warned" -gt 0 ]; then
  exit 1
fi
exit 0
