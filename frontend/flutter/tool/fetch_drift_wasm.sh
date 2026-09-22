#!/usr/bin/env bash
# Fetch the sqlite3 WASM module + drift_worker.js into web/ for
# `flutter run -d chrome` and `flutter build web`.
#
# Two upstream sources:
# - `drift_worker.js` is published per-release on
#   https://github.com/simolus3/drift (tag `drift-X.Y.Z`).
# - `sqlite3.wasm` is published on
#   https://github.com/simolus3/sqlite3.dart (tag `sqlite3-X.Y.Z`).
#   Its X.Y.Z is the sqlite3 C library version, NOT the Dart
#   package version — pin a known-good build here.
#
# CI does the same thing inline in .github/workflows/deploy-web.yml.
set -euo pipefail

cd "$(dirname "$0")/.."

DRIFT_VERSION=$(awk '/^  drift:$/{f=1;next} f && /version:/{gsub(/[" ]/,"",$2); print $2; exit}' pubspec.lock)
if [[ -z "$DRIFT_VERSION" ]]; then
  echo "Could not resolve drift version from pubspec.lock" >&2
  exit 1
fi

# The WASM ABI is tied to the Dart `sqlite3` package version — the
# release tag uses the same X.Y.Z. drift_worker.js (from the drift
# release) and sqlite3.wasm (from the sqlite3.dart release) must
# share that ABI, otherwise WASM instantiation fails with
# `function import requires a callable` for `dart.dispatch_xFunc`.
SQLITE3_VERSION=$(awk '/^  sqlite3:$/{f=1;next} f && /version:/{gsub(/[" ]/,"",$2); print $2; exit}' pubspec.lock)
if [[ -z "$SQLITE3_VERSION" ]]; then
  echo "Could not resolve sqlite3 package version from pubspec.lock" >&2
  exit 1
fi

echo "Resolved drift version    : $DRIFT_VERSION"
echo "Resolved sqlite3 version  : $SQLITE3_VERSION"

mkdir -p web
# GitHub 릴리스 다운로드가 가끔 504 를 돌려 CI 빌드가 멈춘다 — 잠깐 쉬었다 다시 받는다.
RETRY=(--retry 5 --retry-delay 5 --retry-all-errors)

# 릴리스 자산 하나를 받는다: fetch_release <owner/repo> <tag> <asset> <out>
#
# 릴리스 주소(`/releases/download/...`)가 재시도 끝에도 실패하면 GitHub API 의
# 자산 경로로 한 번 더 받는다(#2135). 릴리스 주소가 몇 분씩 504 인 동안에도 API
# 경로는 받아졌다. CI 는 `GITHUB_TOKEN` 으로 부른다 — 러너끼리 IP 를 나눠 써서
# 인증 없는 API 호출은 한도에 걸릴 수 있다. 토큰이 없으면(로컬) 인증 없이 부른다.
fetch_release() {
  local repo=$1 tag=$2 asset=$3 out=$4
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

fetch_release simolus3/sqlite3.dart "sqlite3-${SQLITE3_VERSION}" sqlite3.wasm web/sqlite3.wasm
fetch_release simolus3/drift "drift-${DRIFT_VERSION}" drift_worker.js web/drift_worker.js

echo "Downloaded:"
ls -l web/sqlite3.wasm web/drift_worker.js
