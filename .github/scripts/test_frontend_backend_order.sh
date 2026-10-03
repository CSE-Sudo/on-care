#!/usr/bin/env bash
# frontend_backend_order.sh 판정 검사(#3018).
# 임시 git 저장소에 커밋을 만들고, 가짜 curl 이 FAKE_VERSION_BODY 를 /version 응답으로 돌려준다.
# 사용: bash .github/scripts/test_frontend_backend_order.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/frontend_backend_order.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "${*: -1}" >> "$FAKE_CALLS"
if [ "${FAKE_VERSION_FAIL:-}" = 1 ]; then
  echo "curl: (22) The requested URL returned error: 503" >&2
  exit 22
fi
printf '%s' "$FAKE_VERSION_BODY"
FAKE
chmod +x "$work/bin/curl"

repo="$work/repo"
git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.com "$@"; }
commit() { mkdir -p "$repo/$(dirname "$1")"; printf '%s\n' "$2" >> "$repo/$1"; g add -A; g commit -q -m "$3"; g rev-parse HEAD; }

c_base=$(commit backend/app.py v1 'backend base')
c_front=$(commit frontend/flutter/a.dart a 'front only')
c_back=$(commit backend/app.py v2 'backend change')
c_front2=$(commit frontend/flutter/a.dart b 'front after backend')
g checkout -q -b side "$c_base"
c_side=$(commit backend/side.py s 'diverged')
g checkout -q main

body() { printf '{"api_version":"v1","app_version":"0.1.0","commit_sha":"%s"}' "$1"; }

# expect <기대 코드> <설명> <응답 본문> <대상 SHA> [기대 state]
expect() {
  local want="$1" label="$2" resp="$3" target="$4" state="${5:-}" got
  : > "$work/calls"
  (cd "$repo" && FAKE_CALLS="$work/calls" FAKE_VERSION_BODY="$resp" PATH="$work/bin:$PATH" \
    bash "$tool" https://api.oncare.test/v1/ "$target") > "$work/out" 2>&1
  got=$?
  if [ "$got" != "$want" ] || { [ -n "$state" ] && ! grep -qx "state=$state" "$work/out"; }; then
    echo "FAIL: $label -> $got (기대: $want ${state})"
    sed 's/^/    /' "$work/out"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got ${state}"
  fi
}

expect 0  '백엔드가 같은 커밋'                         "$(body "$c_front2")" "$c_front2" same
expect 0  '그 뒤 프론트만 바뀜'                         "$(body "$c_back")"   "$c_front2" no-backend-change
expect 0  '백엔드 커밋 이후 backend/ 변경 없음(앞쪽)'   "$(body "$c_base")"   "$c_front"  no-backend-change
expect 10 '아직 배포되지 않은 backend/ 변경'             "$(body "$c_front")"  "$c_front2" pending
expect 0  '백엔드가 더 새 커밋'                         "$(body "$c_front2")" "$c_front"  backend-ahead
expect 0  '대문자 SHA 도 같은 커밋'                      "$(body "$(printf '%s' "$c_back" | tr '[:lower:]' '[:upper:]')")" "$c_back" same
expect 11 'commit_sha 필드 없음'                         '{"api_version":"v1","app_version":"0.1.0"}' "$c_front2" unknown
expect 11 'commit_sha 가 unknown'                         '{"commit_sha":"unknown"}' "$c_front2" unknown
expect 11 'JSON 이 아님'                                 '<html>bad gateway</html>' "$c_front2" unknown
expect 1  '저장소에 없는 커밋'                           "$(body 1111111111111111111111111111111111111111)" "$c_front2" error
expect 1  '이력이 갈라짐'                                "$(body "$c_side")"   "$c_front2" error
expect 1  '대상 SHA 형식 오류'                           "$(body "$c_back")"   abc

: > "$work/calls"
if (cd "$repo" && FAKE_CALLS="$work/calls" FAKE_VERSION_FAIL=1 PATH="$work/bin:$PATH" \
    bash "$tool" https://api.oncare.test/v1 "$c_front2") > /dev/null 2>&1; then
  echo "FAIL: 백엔드 응답 실패 -> 0"; failures=$((failures + 1))
else
  echo "ok:   백엔드 응답 실패 -> 1"
fi
if grep -qx 'https://api.oncare.test/v1/version' "$work/calls"; then
  echo "ok:   /v1/version 주소(끝 / 정리)"
else
  echo "FAIL: 요청 주소"; sed 's/^/    /' "$work/calls"; failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "frontend_backend_order.sh 검사 통과"
