#!/usr/bin/env bash
# 두 웹 앱 릴리스의 캐시 헤더 규칙(#3023).
#
# Flutter 웹 산출물의 진입 파일(index.html·flutter_bootstrap.js·main.dart.js 등)은 이름에
# 해시가 없다. 모든 파일에 같은 `max-age` 를 주면 브라우저가 배포 뒤에도 옛 진입 파일을
# 들고 있고, 서로 다른 릴리스의 진입 파일이 섞일 수 있다. 그래서
#
#   * 이름이 고정된 진입 파일: `no-cache` — 매번 재검증하고 바뀌지 않았으면 304 로 받는다.
#   * 그 밖(canvaskit/·assets/·글꼴 등): 지금처럼 짧게 `public,max-age=300`.
#
# 사용:
#   web_cache_headers.sh classify <상대 경로>        # 그 파일이 받을 Cache-Control 을 출력
#   web_cache_headers.sh upload <원본 폴더> <s3://버킷/접두사>
#   web_cache_headers.sh verify <버킷> <접두사>       # 올린 대표 파일의 헤더 확인
#
# AWS_CLI 로 aws 명령을 바꿀 수 있다(검사 스크립트가 가짜 명령을 넣는다).
set -euo pipefail

AWS_CLI="${AWS_CLI:-aws}"
ENTRY_CACHE_CONTROL="no-cache"
ASSET_CACHE_CONTROL="public,max-age=300"

# 이름이 고정된 진입 파일. 폴더(member/·trainer/)와 무관하게 파일 이름으로 가른다.
ENTRY_FILES=(
  index.html
  flutter_bootstrap.js
  flutter.js
  flutter_service_worker.js
  main.dart.js
  main.dart.mjs
  main.dart.wasm
  version.json
  version.txt
  manifest.json
  drift_worker.js
  sqlite3.wasm
)

# 배포 뒤 헤더를 확인할 대표 파일(접두사 기준 상대 경로)과 기대 값.
VERIFY_KEYS=(
  "index.html=$ENTRY_CACHE_CONTROL"
  "version.txt=$ENTRY_CACHE_CONTROL"
  "member/index.html=$ENTRY_CACHE_CONTROL"
  "member/flutter_bootstrap.js=$ENTRY_CACHE_CONTROL"
  "member/main.dart.js=$ENTRY_CACHE_CONTROL"
  "member/version.txt=$ENTRY_CACHE_CONTROL"
  "member/canvaskit/canvaskit.wasm=$ASSET_CACHE_CONTROL"
  "trainer/index.html=$ENTRY_CACHE_CONTROL"
  "trainer/flutter_bootstrap.js=$ENTRY_CACHE_CONTROL"
  "trainer/main.dart.js=$ENTRY_CACHE_CONTROL"
  "trainer/version.txt=$ENTRY_CACHE_CONTROL"
  "trainer/canvaskit/canvaskit.wasm=$ASSET_CACHE_CONTROL"
)

usage() {
  echo "usage: $0 classify <path> | upload <src> <s3-dest> | verify <bucket> <prefix>" >&2
  exit 2
}

is_entry() {
  local name="${1##*/}" entry
  for entry in "${ENTRY_FILES[@]}"; do
    [ "$name" = "$entry" ] && return 0
  done
  return 1
}

classify() {
  if is_entry "$1"; then
    echo "$ENTRY_CACHE_CONTROL"
  else
    echo "$ASSET_CACHE_CONTROL"
  fi
}

# s3 의 include/exclude 패턴은 원본 폴더 기준 상대 경로에 맞추고 `*` 는 `/` 도 넘는다.
entry_patterns() {
  local entry
  for entry in "${ENTRY_FILES[@]}"; do
    printf '%s\n' "--include" "$entry" "--include" "*/$entry"
  done
}

upload() {
  local src="$1" dest="$2" patterns=()
  [ -d "$src" ] || { echo "::error::원본 폴더가 없습니다: $src" >&2; exit 1; }
  while IFS= read -r line; do patterns+=("$line"); done < <(entry_patterns)
  local excludes=()
  local i
  for ((i = 0; i < ${#patterns[@]}; i += 2)); do
    excludes+=("--exclude" "${patterns[i + 1]}")
  done

  # 1) 진입 파일을 뺀 나머지 — `--delete` 는 이 접두사 안에서만 작용한다(재실행 잔여 정리).
  #    진입 파일은 제외 패턴이라 여기서 지워지지 않는다.
  "$AWS_CLI" s3 sync "$src/" "$dest/" --delete "${excludes[@]}" \
    --cache-control "$ASSET_CACHE_CONTROL"
  # 2) 진입 파일만 — sync 는 크기·시각이 같으면 건너뛰어 헤더가 안 바뀔 수 있으므로 cp 로
  #    매번 다시 올린다. 작은 파일 몇 개뿐이다.
  "$AWS_CLI" s3 cp "$src/" "$dest/" --recursive --exclude "*" "${patterns[@]}" \
    --cache-control "$ENTRY_CACHE_CONTROL"
}

verify() {
  local bucket="$1" prefix="$2" item key want got failures=0
  for item in "${VERIFY_KEYS[@]}"; do
    key="${item%%=*}"
    want="${item#*=}"
    got=$("$AWS_CLI" s3api head-object --bucket "$bucket" --key "$prefix/$key" \
      --query 'CacheControl' --output text)
    if [ "$got" != "$want" ]; then
      echo "::error::Cache-Control mismatch: $prefix/$key expected='$want' actual='$got'"
      failures=$((failures + 1))
    else
      echo "ok: $prefix/$key -> $got"
    fi
  done
  [ "$failures" -eq 0 ]
}

[ "$#" -ge 1 ] || usage
command="$1"
shift
case "$command" in
  classify) [ "$#" -eq 1 ] || usage; classify "$1" ;;
  upload) [ "$#" -eq 2 ] || usage; upload "$1" "$2" ;;
  verify) [ "$#" -eq 2 ] || usage; verify "$1" "$2" ;;
  *) usage ;;
esac
