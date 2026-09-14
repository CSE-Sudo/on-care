#!/usr/bin/env bash
# Fetch the sqlite3 WASM module + drift_worker.js into web/ so the
# trainer app's drift-backed local DB works on the web — the trainer
# surface ships web-first (responsive/tablet), so this is required for
# `flutter run -d chrome` and `flutter build web`.
#
# Mirrors frontend/flutter/tool/fetch_drift_wasm.sh:
# - `drift_worker.js` from https://github.com/simolus3/drift
#   (tag `drift-X.Y.Z`, version from pubspec.lock).
# - `sqlite3.wasm` from https://github.com/simolus3/sqlite3.dart
#   (tag `sqlite3-X.Y.Z`, Dart package version from pubspec.lock —
#   the WASM ABI is tied to it).
set -euo pipefail

cd "$(dirname "$0")/.."

DRIFT_VERSION=$(awk '/^  drift:$/{f=1;next} f && /version:/{gsub(/[" ]/,"",$2); print $2; exit}' pubspec.lock)
if [[ -z "$DRIFT_VERSION" ]]; then
  echo "Could not resolve drift version from pubspec.lock" >&2
  exit 1
fi

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
