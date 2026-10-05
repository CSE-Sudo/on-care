#!/usr/bin/env bash
# 두 웹 앱(회원 앱·트레이너 웹)의 drift WASM 자산을 받아 web/ 에 넣는다.
# 쓰는 법: fetch_drift_wasm.sh <앱 디렉터리>
# 각 앱의 tool/fetch_drift_wasm.sh 가 이 스크립트를 부른다.
#
# 받는 곳은 두 GitHub 릴리스다.
# - `sqlite3.wasm`: https://github.com/simolus3/sqlite3.dart (태그 `sqlite3-X.Y.Z`).
#   X.Y.Z 는 pubspec.lock 의 Dart `sqlite3` 패키지 버전이다 — WASM ABI 가 그 버전에
#   묶여 있어서, drift_worker.js 와 ABI 가 어긋나면 `function import requires a
#   callable`(`dart.dispatch_xFunc`)로 WASM 생성이 실패한다.
# - `drift_worker.js`: https://github.com/simolus3/drift (태그 `drift-X.Y.Z`,
#   pubspec.lock 의 drift 버전).
#
# 받은 파일은 앱과 같은 출처로 배포되고 워커는 앱 출처 권한으로 돈다. 릴리스 자산은
# 올린 쪽이 바꿀 수 있으므로 버전 고정만으로는 부족하다 — 같은 디렉터리의 SHA256SUMS
# 에 적힌 해시와 맞을 때만 web/ 에 넣는다(#3089). drift·sqlite3 버전을 올리면 그 PR 에서
# 새 버전의 해시를 SHA256SUMS 에 더한다.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "쓰는 법: $0 <앱 디렉터리>" >&2
  exit 2
fi
app_dir=$(cd "$1" && pwd)
sums="$(cd "$(dirname "$0")" && pwd)/SHA256SUMS"

# lock_version <패키지>: pubspec.lock 에서 버전을 읽는다.
lock_version() {
  awk -v pkg="  $1:" '$0 == pkg {f=1; next} f && /version:/ {gsub(/[" ]/, "", $2); print $2; exit}' \
    "$app_dir/pubspec.lock"
}

DRIFT_VERSION=$(lock_version drift)
if [[ -z "$DRIFT_VERSION" ]]; then
  echo "Could not resolve drift version from pubspec.lock" >&2
  exit 1
fi
SQLITE3_VERSION=$(lock_version sqlite3)
if [[ -z "$SQLITE3_VERSION" ]]; then
  echo "Could not resolve sqlite3 package version from pubspec.lock" >&2
  exit 1
fi

echo "Resolved drift version    : $DRIFT_VERSION"
echo "Resolved sqlite3 version  : $SQLITE3_VERSION"

wasm_key="sqlite3-${SQLITE3_VERSION}/sqlite3.wasm"
worker_key="drift-${DRIFT_VERSION}/drift_worker.js"

# 받기 전에 표부터 본다 — 해시가 없는 버전은 받아 봐야 확인할 수 없다.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
missing=0
for key in "$wasm_key" "$worker_key"; do
  if ! grep -E "^[0-9a-f]{64}  ${key//./\\.}\$" "$sums" >> "$work/expected.sha256"; then
    echo "::error::${key} 의 SHA-256 이 tool/drift_wasm/SHA256SUMS 에 없습니다." >&2
    missing=1
  fi
done
if [[ $missing -ne 0 ]]; then
  cat >&2 <<'EOF'
pubspec.lock 의 drift·sqlite3 버전이 바뀌었으면 새 버전의 해시를 SHA256SUMS 에 추가하세요.
GitHub 공식 릴리스에서 받아 계산하고, 릴리스 API 의 digest 와 같은지 확인합니다.
  gh api repos/simolus3/sqlite3.dart/releases/tags/sqlite3-<버전> --jq '.assets[] | select(.name=="sqlite3.wasm") | .digest'
  gh api repos/simolus3/drift/releases/tags/drift-<버전> --jq '.assets[] | select(.name=="drift_worker.js") | .digest'
EOF
  exit 1
fi

# GitHub 릴리스 다운로드가 가끔 504 를 돌려 CI 빌드가 멈춘다 — 잠깐 쉬었다 다시 받는다.
RETRY=(--retry 5 --retry-delay 5 --retry-all-errors)

# 릴리스 자산 하나를 받는다: fetch_release <owner/repo> <tag> <asset> <out>
#
# 릴리스 주소(`/releases/download/...`)가 재시도 끝에도 실패하면 GitHub API 의
# 자산 경로로 한 번 더 받는다(#2135). 릴리스 주소가 몇 분씩 504 인 동안에도 API
# 경로는 받아졌다. CI 는 `GITHUB_TOKEN` 으로 부른다 — 러너끼리 IP 를 나눠 써서
# 인증 없는 API 호출은 한도에 걸릴 수 있다. 토큰이 없으면(로컬) 인증 없이 부른다.
# 어느 경로로 받든 아래에서 같은 해시로 확인한다.
fetch_release() {
  local repo=$1 tag=$2 asset=$3 out=$4
  mkdir -p "$(dirname "$out")"
  if curl --fail --location --silent --show-error "${RETRY[@]}" \
    -o "$out" "https://github.com/${repo}/releases/download/${tag}/${asset}"; then
    return 0
  fi
  echo "릴리스 주소에서 ${asset} 를 받지 못해 GitHub API 로 다시 받는다." >&2
  local auth=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  local id
  id=$(curl --fail --silent --show-error "${RETRY[@]}" ${auth[@]+"${auth[@]}"} \
    "https://api.github.com/repos/${repo}/releases/tags/${tag}" |
    python3 -c 'import json, sys
name = sys.argv[1]
print(next(a["id"] for a in json.load(sys.stdin)["assets"] if a["name"] == name))' "$asset")
  curl --fail --location --silent --show-error "${RETRY[@]}" ${auth[@]+"${auth[@]}"} \
    -H "Accept: application/octet-stream" \
    -o "$out" "https://api.github.com/repos/${repo}/releases/assets/${id}"
}

fetch_release simolus3/sqlite3.dart "sqlite3-${SQLITE3_VERSION}" sqlite3.wasm "$work/$wasm_key"
fetch_release simolus3/drift "drift-${DRIFT_VERSION}" drift_worker.js "$work/$worker_key"

# macOS 에는 sha256sum 이 없어 shasum 으로 같은 형식을 확인한다.
if command -v sha256sum > /dev/null; then
  check=(sha256sum --check --strict)
else
  check=(shasum -a 256 --check --strict)
fi
if ! (cd "$work" && "${check[@]}" expected.sha256); then
  echo "::error::받은 drift 자산의 SHA-256 이 tool/drift_wasm/SHA256SUMS 와 다릅니다 — web/ 에 넣지 않습니다." >&2
  exit 1
fi

mkdir -p "$app_dir/web"
cp "$work/$wasm_key" "$app_dir/web/sqlite3.wasm"
cp "$work/$worker_key" "$app_dir/web/drift_worker.js"

echo "Downloaded (SHA-256 verified):"
ls -l "$app_dir/web/sqlite3.wasm" "$app_dir/web/drift_worker.js"
