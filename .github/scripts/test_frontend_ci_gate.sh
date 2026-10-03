#!/usr/bin/env bash
# frontend_ci_gate.sh 판정 검사(#3018).
# 가짜 gh 가 워크플로별 픽스처(FAKE_RUNS_DIR/<워크플로>)를 "status conclusion" 한 줄로 돌려준다.
# 파일이 없으면 실행 없음, 내용이 ERROR 면 API 오류.
# 사용: bash .github/scripts/test_frontend_ci_gate.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/frontend_ci_gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
sha=0123456789abcdef0123456789abcdef01234567

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_RUNS_DIR/calls"
for arg in "$@"; do
  case "$arg" in
    repos/*/actions/workflows/*/runs) workflow="${arg%/runs}"; workflow="${workflow##*/}" ;;
  esac
done
file="$FAKE_RUNS_DIR/$workflow"
[ -f "$file" ] || exit 0
if [ "$(cat "$file")" = ERROR ]; then
  echo "gh: HTTP 502" >&2
  exit 1
fi
cat "$file"
FAKE
chmod +x "$work/bin/gh"

# expect <기대 종료 코드> <설명> <e2e> <user-app> <trainer>  (값 '-' 는 실행 없음)
expect() {
  local want="$1" label="$2" dir="$work/case" got
  rm -rf "$dir"; mkdir -p "$dir"
  [ "$3" = - ] || printf '%s\n' "$3" > "$dir/e2e-ci.yml"
  [ "$4" = - ] || printf '%s\n' "$4" > "$dir/user-app-ci.yml"
  [ "$5" = - ] || printf '%s\n' "$5" > "$dir/trainer-ci.yml"
  FAKE_RUNS_DIR="$dir" GITHUB_REPOSITORY=CSE-Sudo/on-care PATH="$work/bin:$PATH" \
    bash "$tool" "${6:-$sha}" > "$work/out" 2>&1
  got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> $got (기대: $want)"
    sed 's/^/    /' "$work/out"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got"
  fi
}

expect 0  'E2E 성공, 앱 CI 실행 없음(경로 밖)'      'completed success' -                   -
expect 0  '셋 다 성공'                               'completed success' 'completed success' 'completed success'
expect 0  '사용자 앱만 실행돼 성공'                  'completed success' 'completed success' -
expect 1  'E2E 실패'                                 'completed failure' -                   -
expect 1  '트레이너 CI 실패'                         'completed success' -                   'completed failure'
expect 1  '사용자 앱 CI 취소'                        'completed success' 'completed cancelled' -
expect 10 '트레이너 CI 진행 중'                      'completed success' -                   'in_progress '
expect 10 'E2E 대기열'                               'queued '           -                   -
expect 10 'E2E 실행이 아직 생성되지 않음'            -                   -                   -
expect 1  '진행 중이 있어도 실패가 우선'             'completed success' 'completed failure' 'in_progress '
expect 1  'API 오류'                                 ERROR               -                   -
expect 1  '짧은 SHA 거부'                            'completed success' -                   -                   0123456

# 대상 SHA·main·push 로 좁혀 조회하는지 확인한다.
dir="$work/case"; rm -rf "$dir"; mkdir -p "$dir"; printf 'completed success\n' > "$dir/e2e-ci.yml"
FAKE_RUNS_DIR="$dir" GITHUB_REPOSITORY=CSE-Sudo/on-care PATH="$work/bin:$PATH" bash "$tool" "$sha" > /dev/null 2>&1
if grep -q "head_sha=$sha" "$dir/calls" && grep -q 'branch=main' "$dir/calls" && grep -q 'event=push' "$dir/calls" \
   && grep -q 'repos/CSE-Sudo/on-care/actions/workflows/trainer-ci.yml/runs' "$dir/calls"; then
  echo "ok:   조회 조건(head_sha·main·push·세 워크플로)"
else
  echo "FAIL: 조회 조건"; sed 's/^/    /' "$dir/calls"; failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "frontend_ci_gate.sh 검사 통과"
