#!/usr/bin/env bash
# Fetch the sqlite3 WASM module + drift_worker.js into web/ for
# `flutter run -d chrome` and `flutter build web`.
#
# 받기·SHA-256 확인은 두 웹 앱이 공용으로 쓰는 tool/drift_wasm/fetch_drift_wasm.sh 가
# 한다(#3089). drift·sqlite3 버전을 올리면 tool/drift_wasm/SHA256SUMS 에 해시를 더한다.
# CI 는 .github/workflows/deploy.yml·aws-frontend-deploy.yml 에서 이 스크립트를 부른다.
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$app_dir/../../tool/drift_wasm/fetch_drift_wasm.sh" "$app_dir"
