#!/usr/bin/env bash
# tool/drift_wasm/fetch_drift_wasm.sh 의 자체 테스트(#3089).
#
# drift 자산은 앱과 같은 출처로 배포되므로 해시가 다르면 반드시 실패해야 하고, 표에
# 없는 버전이면 해시를 더하라는 안내와 함께 실패해야 한다. 네트워크 없이 가짜 curl 로
# 릴리스 응답을 흉내 내고, 표도 임시 사본을 쓴다.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# 가짜 curl: `-o <파일>` 에 주소 끝 경로(<태그>/<자산>)를 내용으로 쓴다. FAKE_CURL_BODY_<자산>
# 이 있으면 그 내용을 쓴다(변조 흉내). 릴리스 API 경로는 쓰지 않는다.
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  */releases/download/*) ;;
  *) echo "unexpected url: $url" >&2; exit 22 ;;
esac
asset=${url##*/}
tag=${url%/*}; tag=${tag##*/}
var="FAKE_CURL_BODY_${asset//[^A-Za-z0-9]/_}"
if [ -n "${!var:-}" ]; then
  printf '%s' "${!var}" > "$out"
else
  printf '%s/%s' "$tag" "$asset" > "$out"
fi
EOF
chmod +x "$work/bin/curl"

sha() {
  if command -v sha256sum > /dev/null; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

# setup <drift> <sqlite3> [표에 넣을 키...]: 임시 앱·스크립트 사본을 만든다.
setup() {
  local drift=$1 sqlite=$2
  shift 2
  rm -rf "$work/case"
  mkdir -p "$work/case/tool" "$work/case/app"
  cp "$root/tool/drift_wasm/fetch_drift_wasm.sh" "$work/case/tool/"
  : > "$work/case/tool/SHA256SUMS"
  local key
  for key in "$@"; do
    printf '%s  %s\n' "$(sha "$key")" "$key" >> "$work/case/tool/SHA256SUMS"
  done
  cat > "$work/case/app/pubspec.lock" <<EOF
packages:
  drift:
    dependency: "direct main"
    source: hosted
    version: "$drift"
  sqlite3:
    dependency: transitive
    source: hosted
    version: "$sqlite"
EOF
}

# expect <name> <pass|fail> [출력에 있어야 할 문구]
expect() {
  local name=$1 want=$2 needle=${3:-} out code=0
  out=$(PATH="$work/bin:$PATH" bash "$work/case/tool/fetch_drift_wasm.sh" "$work/case/app" 2>&1) || code=$?
  local ok=1
  if [ "$want" = pass ]; then
    [ "$code" = 0 ] || ok=0
    [ -s "$work/case/app/web/sqlite3.wasm" ] && [ -s "$work/case/app/web/drift_worker.js" ] || ok=0
  else
    [ "$code" != 0 ] || ok=0
    # 실패하면 확인하지 못한 파일을 web/ 에 남기지 않는다.
    [ ! -e "$work/case/app/web/sqlite3.wasm" ] && [ ! -e "$work/case/app/web/drift_worker.js" ] || ok=0
  fi
  if [ -n "$needle" ] && ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
    ok=0
  fi
  if [ "$ok" = 1 ]; then
    echo "ok   $name"
  else
    echo "FAIL $name (종료 $code, 기대 $want)"
    printf '%s\n' "$out" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
}

setup 2.28.2 2.9.4 sqlite3-2.9.4/sqlite3.wasm drift-2.28.2/drift_worker.js
expect "해시가 맞으면 web/ 에 넣는다" pass "SHA-256 verified"

setup 2.28.2 2.9.4 sqlite3-2.9.4/sqlite3.wasm drift-2.28.2/drift_worker.js
FAKE_CURL_BODY_sqlite3_wasm=tampered expect "sqlite3.wasm 이 바뀌면 실패" fail "SHA-256 이 tool/drift_wasm/SHA256SUMS 와 다릅니다"

setup 2.28.2 2.9.4 sqlite3-2.9.4/sqlite3.wasm drift-2.28.2/drift_worker.js
FAKE_CURL_BODY_drift_worker_js=tampered expect "drift_worker.js 가 바뀌면 실패" fail "SHA-256 이 tool/drift_wasm/SHA256SUMS 와 다릅니다"

setup 2.29.0 2.9.4 sqlite3-2.9.4/sqlite3.wasm drift-2.28.2/drift_worker.js
expect "표에 없는 drift 버전은 안내와 함께 실패" fail "drift-2.29.0/drift_worker.js 의 SHA-256 이 tool/drift_wasm/SHA256SUMS 에 없습니다"

setup 2.28.2 2.9.5 sqlite3-2.9.4/sqlite3.wasm drift-2.28.2/drift_worker.js
expect "표에 없는 sqlite3 버전은 안내와 함께 실패" fail "SHA256SUMS 에 추가하세요"

# 버전의 점이 정규식 와일드카드로 새지 않는다(2.28.2 표가 2x28x2 를 통과시키지 않음).
setup 2.28.2 2.9.4 sqlite3-2.9.4/sqlite3.wasm drift-2x28x2/drift_worker.js
expect "버전 문자열은 그대로 맞춘다" fail "drift-2.28.2/drift_worker.js 의 SHA-256 이"

# 저장소의 실제 표가 두 앱 pubspec.lock 의 버전을 모두 덮는다.
for app in frontend/flutter frontend/flutter_trainer; do
  for pkg in drift sqlite3; do
    v=$(awk -v pkg="  $pkg:" '$0 == pkg {f=1; next} f && /version:/ {gsub(/[" ]/, "", $2); print $2; exit}' "$root/$app/pubspec.lock")
    case $pkg in
      drift) key="drift-$v/drift_worker.js" ;;
      sqlite3) key="sqlite3-$v/sqlite3.wasm" ;;
    esac
    if grep -qE "^[0-9a-f]{64}  ${key//./\\.}\$" "$root/tool/drift_wasm/SHA256SUMS"; then
      echo "ok   $app 의 $key 해시가 표에 있다"
    else
      echo "FAIL $app 의 $key 해시가 tool/drift_wasm/SHA256SUMS 에 없다"
      failures=$((failures + 1))
    fi
  done
done

if [ "$failures" -ne 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
