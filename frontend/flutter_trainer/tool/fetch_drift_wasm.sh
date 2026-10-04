#!/usr/bin/env bash
# Fetch the sqlite3 WASM module + drift_worker.js into web/ so the
# trainer app's drift-backed local DB works on the web — the trainer
# surface ships web-first (responsive/tablet), so this is required for
# `flutter run -d chrome` and `flutter build web`.
#
# 받기·SHA-256 확인은 두 웹 앱이 공용으로 쓰는 tool/drift_wasm/fetch_drift_wasm.sh 가
# 한다(#3089). drift·sqlite3 버전을 올리면 tool/drift_wasm/SHA256SUMS 에 해시를 더한다.
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$app_dir/../../tool/drift_wasm/fetch_drift_wasm.sh" "$app_dir"
