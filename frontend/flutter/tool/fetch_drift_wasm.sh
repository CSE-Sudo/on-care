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
curl --fail --location --silent --show-error "${RETRY[@]}" \
  -o web/sqlite3.wasm \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${SQLITE3_VERSION}/sqlite3.wasm"
curl --fail --location --silent --show-error "${RETRY[@]}" \
  -o web/drift_worker.js \
  "https://github.com/simolus3/drift/releases/download/drift-${DRIFT_VERSION}/drift_worker.js"

echo "Downloaded:"
ls -l web/sqlite3.wasm web/drift_worker.js
