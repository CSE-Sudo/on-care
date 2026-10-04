#!/usr/bin/env bash
# web_cache_headers.sh 의 분류·업로드 인자·헤더 검증 경계 검사(#3023).
# 사용: bash .github/scripts/test_web_cache_headers.sh
# 실제 aws 를 부르지 않는다 — AWS_CLI 에 인자를 적어 두는 가짜 명령을 넣는다.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/web_cache_headers.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

check() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> '$got' (기대: '$want')"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> '$got'"
  fi
}

# --- classify: 진입 파일은 폴더와 무관하게 no-cache, 나머지는 짧은 max-age
for path in index.html frontend/index.html trainer/flutter_bootstrap.js \
  frontend/main.dart.js trainer/version.json frontend/version.txt version.txt \
  trainer/manifest.json frontend/drift_worker.js; do
  check "classify $path" "no-cache" "$(bash "$script" classify "$path")"
done
for path in frontend/canvaskit/canvaskit.wasm trainer/assets/AssetManifest.bin \
  frontend/assets/fonts/MaterialIcons-Regular.otf trainer/favicon.png \
  frontend/main.dart.js.map frontend/index.html.bak; do
  check "classify $path" "public,max-age=300" "$(bash "$script" classify "$path")"
done

# --- 가짜 aws: 받은 인자를 한 줄씩 적고, head-object 는 표에서 헤더를 돌려준다.
fake="$work/aws"
cat > "$fake" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "CALL $*" >> "$FAKE_LOG"
if [ "$1" = "s3api" ] && [ "$2" = "head-object" ]; then
  key=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--key" ]; then key="$2"; fi
    shift
  done
  value=$(grep -F "$key=" "$FAKE_HEADERS" | head -n 1 | cut -d= -f2-)
  printf '%s\n' "${value:-None}"
fi
FAKE
chmod +x "$fake"
export AWS_CLI="$fake" FAKE_LOG="$work/log" FAKE_HEADERS="$work/headers"

# --- upload: 나머지 sync(--delete·제외 패턴·max-age) 다음 진입 파일 cp(no-cache)
mkdir -p "$work/public/frontend"
: > "$FAKE_LOG"
bash "$script" upload "$work/public" "s3://bucket/releases/abc" > /dev/null
calls=$(grep -c '^CALL ' "$FAKE_LOG")
check "upload 호출 수" "2" "$calls"
sync_line=$(sed -n 1p "$FAKE_LOG")
cp_line=$(sed -n 2p "$FAKE_LOG")
case "$sync_line" in
  "CALL s3 sync $work/public/ s3://bucket/releases/abc/ --delete --exclude index.html --exclude */index.html"*"--cache-control public,max-age=300")
    check "sync 인자" "ok" "ok" ;;
  *) check "sync 인자" "ok" "$sync_line" ;;
esac
case "$cp_line" in
  "CALL s3 cp $work/public/ s3://bucket/releases/abc/ --recursive --exclude * --include index.html --include */index.html"*"--include */main.dart.js"*"--cache-control no-cache")
    check "cp 인자" "ok" "ok" ;;
  *) check "cp 인자" "ok" "$cp_line" ;;
esac
if bash "$script" upload "$work/missing" "s3://bucket/x" > /dev/null 2>&1; then
  check "없는 원본 폴더" "fail" "pass"
else
  check "없는 원본 폴더" "fail" "fail"
fi

# --- verify: 대표 파일이 모두 기대 값이면 통과, 하나라도 다르면 실패
good_headers() {
  local p
  for p in index.html version.txt frontend/index.html frontend/flutter_bootstrap.js \
    frontend/main.dart.js frontend/version.txt trainer/index.html \
    trainer/flutter_bootstrap.js trainer/main.dart.js trainer/version.txt; do
    echo "releases/abc/$p=no-cache"
  done
  echo "releases/abc/frontend/canvaskit/canvaskit.wasm=public,max-age=300"
  echo "releases/abc/trainer/canvaskit/canvaskit.wasm=public,max-age=300"
}
good_headers > "$FAKE_HEADERS"
if bash "$script" verify bucket releases/abc > /dev/null 2>&1; then
  check "verify 올바른 헤더" "pass" "pass"
else
  check "verify 올바른 헤더" "pass" "fail"
fi
# 예전처럼 모두 같은 max-age 로 올라간 릴리스
good_headers | sed 's/=no-cache$/=public,max-age=300/' > "$FAKE_HEADERS"
if bash "$script" verify bucket releases/abc > /dev/null 2>&1; then
  check "verify 옛 단일 헤더" "fail" "pass"
else
  check "verify 옛 단일 헤더" "fail" "fail"
fi
# 진입 파일 하나만 빠진 경우(헤더 없음)
good_headers | grep -v 'trainer/main.dart.js' > "$FAKE_HEADERS"
if bash "$script" verify bucket releases/abc > /dev/null 2>&1; then
  check "verify 헤더 누락" "fail" "pass"
else
  check "verify 헤더 누락" "fail" "fail"
fi

# --- 잘못된 사용
if bash "$script" nope > /dev/null 2>&1; then
  check "알 수 없는 명령" "fail" "pass"
else
  check "알 수 없는 명령" "fail" "fail"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
