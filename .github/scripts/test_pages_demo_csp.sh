#!/usr/bin/env bash
# pages_demo_csp.sh 의 자체 테스트(#3089).
#
# Pages 데모 배포는 이 스크립트로 두 앱 index.html 의 connect-src 를 좁히고 확인한다.
# 좁히기가 다른 지시어를 건드리거나, 확인이 넓은 목록을 놓치면 데모가 깨지거나 넓은 채
# 나간다. 저장소의 실제 index.html 사본으로 목업·실서버 빌드를 흉내 낸다.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/.github/scripts/pages_demo_csp.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# expect <name> <pass|fail> <command...>
expect() {
  local name=$1 want=$2 out code=0
  shift 2
  out=$("$@" 2>&1) || code=$?
  if { [ "$want" = pass ] && [ "$code" = 0 ]; } || { [ "$want" = fail ] && [ "$code" != 0 ]; }; then
    echo "ok   $name"
  else
    echo "FAIL $name (종료 $code, 기대 $want)"
    printf '%s\n' "$out" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
}

# contains <name> <file> <text>: 파일에 문구가 있어야 한다.
contains() {
  if grep -qF -- "$3" "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1: '$3' 이 없다"
    failures=$((failures + 1))
  fi
}

# lacks <name> <file> <text>: meta CSP 줄에 문구가 없어야 한다(주석의 설명은 보지 않는다).
lacks() {
  if grep -F 'http-equiv="Content-Security-Policy"' "$2" | grep -qF -- "$3"; then
    echo "FAIL $1: '$3' 이 남아 있다"
    failures=$((failures + 1))
  else
    echo "ok   $1"
  fi
}

for app in flutter flutter_trainer; do
  src="$root/frontend/$app/web/index.html"

  # 원본은 로컬 개발용으로 넓다 — check 가 그것을 잡아야 한다.
  cp "$src" "$work/$app.html"
  expect "$app 원본 meta 는 넓어서 확인에 걸린다" fail bash "$script" check "$work/$app.html"

  # 목업 빌드: API 출처 없이 정적 출처만.
  cp "$src" "$work/$app-mock.html"
  expect "$app 목업 빌드 좁히기" pass bash "$script" narrow "$work/$app-mock.html"
  expect "$app 목업 빌드 확인" pass bash "$script" check "$work/$app-mock.html"
  contains "$app 목업 connect-src" "$work/$app-mock.html" \
    "connect-src 'self' https://www.gstatic.com https://fonts.gstatic.com https://dapi.kakao.com https://accounts.google.com/gsi/;"
  lacks "$app 목업에 localhost 없음" "$work/$app-mock.html" "localhost"
  lacks "$app 목업에 127.0.0.1 없음" "$work/$app-mock.html" "127.0.0.1"
  # 다른 지시어(img-src·media-src 의 https:)는 그대로다.
  contains "$app img-src 유지" "$work/$app-mock.html" "img-src 'self' data: blob: https:;"
  contains "$app script-src 유지" "$work/$app-mock.html" \
    "script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com https://dapi.kakao.com https://t1.daumcdn.net https://accounts.google.com/gsi/client;"
  # meta 밖 본문은 바뀌지 않는다(바뀐 줄은 CSP 한 줄뿐).
  changed=$(diff "$src" "$work/$app-mock.html" | grep -c '^>' || true)
  if [ "$changed" = 1 ]; then
    echo "ok   $app 바뀐 줄은 하나"
  else
    echo "FAIL $app 바뀐 줄이 $changed 개"
    failures=$((failures + 1))
  fi

  # 실서버 빌드: API 출처가 들어간다.
  cp "$src" "$work/$app-real.html"
  expect "$app 실서버 빌드 좁히기" pass \
    bash "$script" narrow "$work/$app-real.html" "https://api.oncare.test/v1"
  expect "$app 실서버 빌드 확인" pass \
    bash "$script" check "$work/$app-real.html" "https://api.oncare.test/v1"
  contains "$app 실서버 connect-src" "$work/$app-real.html" \
    "connect-src 'self' https://api.oncare.test https://www.gstatic.com"
  # 목업으로 좁힌 산출물은 실서버 API 출처를 요구하면 걸린다.
  expect "$app API 출처가 빠지면 실패" fail \
    bash "$script" check "$work/$app-mock.html" "https://api.oncare.test/v1"
done

# 넓은 출처 하나만 남아도 걸린다.
make_csp() {
  printf '<meta http-equiv="Content-Security-Policy" content="default-src %s; connect-src %s; img-src https:">\n' \
    "'self'" "$1" > "$work/case.html"
}
make_csp "'self' https:"
expect "https: 전체는 실패" fail bash "$script" check "$work/case.html"
make_csp "'self' *"
expect "* 는 실패" fail bash "$script" check "$work/case.html"
make_csp "'self' http://localhost:*"
expect "localhost 는 실패" fail bash "$script" check "$work/case.html"
make_csp "'self' http://api.oncare.test"
expect "http 출처는 실패" fail bash "$script" check "$work/case.html"
make_csp "'self' https://api.oncare.test"
expect "좁은 목록은 통과" pass bash "$script" check "$work/case.html" "https://api.oncare.test/v1"

# 운영 헤더 검사(frontend_security_headers.sh)와 같은 차단 기준(#3255). `*` 가 파일 이름으로
# 펼쳐지면 차단 분기를 지나치므로 파일이 있는 폴더에서 돌린다.
in_work() { (cd "$work" && "$@"); }
for source in 'wss:' 'ws:' 'ws://api.oncare.test' 'wss://*' 'https://*' 'http://*'   'https://*:443' 'https://*/v1' 'wss://*:443'; do
  make_csp "'self' https://api.oncare.test $source"
  expect "$source 는 실패" fail in_work bash "$script" check "$work/case.html"
done
for source in 'https://*.oncare.test' 'wss://*.oncare.test' 'wss://realtime.oncare.test'; do
  make_csp "'self' https://api.oncare.test $source"
  expect "$source 는 통과(하위 도메인 묶음·좁은 출처)" pass     in_work bash "$script" check "$work/case.html" "https://api.oncare.test/v1"
done
printf '<html></html>\n' > "$work/none.html"
expect "meta CSP 가 없으면 실패" fail bash "$script" check "$work/none.html"
expect "http API 주소는 실패" fail bash "$script" narrow "$work/case.html" "http://api.oncare.test/v1"

if [ "$failures" -ne 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
