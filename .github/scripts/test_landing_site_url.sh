#!/usr/bin/env bash
# landing_site_url.sh 의 통과·실패 경계 검사(#2841).
# 사용: bash .github/scripts/test_landing_site_url.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/landing_site_url.sh"
repo_root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

record() {
  local want="$1" got="$2" label="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> $got (기대: $want)"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got"
  fi
}

# 본문을 받아 임시 파일로 만들고 check 결과를 기록한다.
expect_check() {
  local want="$1" label="$2" body="$3" file got
  file="$work/check.html"
  printf '%s\n' "$body" > "$file"
  if bash "$tool" check "$file" > /dev/null 2>&1; then got=pass; else got=fail; fi
  record "$want" "$got" "check: $label"
}

head_ok='<head><!-- SITE_URL_META --></head>'
links_ok='<a href="frontend/#/dashboard" target="_blank">회원</a><a href="trainer/" target="_blank">트레이너</a>'

# 현재 저장소의 랜딩 원본은 통과해야 한다.
if bash "$tool" check "$repo_root/index.html" > /dev/null 2>&1; then got=pass; else got=fail; fi
record pass "$got" "check: 저장소 index.html"

expect_check pass '상대 경로 바로가기' "$head_ok$links_ok"
expect_check pass './ 로 시작하는 상대 경로' "$head_ok<a href=\"./frontend/\">회원</a><a href=\"./trainer/\">트레이너</a>"
expect_check pass '외부 링크(데모 영상·GitHub)는 그대로' "$head_ok$links_ok<a href=\"https://github.com/CSE-Sudo/on-care\">GitHub</a><a href=\"https://youtu.be/abc\">영상</a>"
expect_check fail '무료 DNS 절대 주소 회원 앱' "$head_ok<a href=\"https://ewhasudo.zapto.org/frontend/#/dashboard\">회원</a><a href=\"trainer/\">트레이너</a>"
expect_check fail '다른 도메인 절대 주소 트레이너 웹' "$head_ok<a href=\"frontend/\">회원</a><a href=\"http://example.cloudfront.net/trainer/\">트레이너</a>"
expect_check fail '끝 슬래시 없는 절대 주소' "$head_ok<a href=\"https://ewhasudo.zapto.org/trainer\">트레이너</a>$links_ok"
expect_check fail '회원 앱 바로가기 없음' "$head_ok<a href=\"trainer/\">트레이너</a>"
expect_check fail '트레이너 웹 바로가기 없음' "$head_ok<a href=\"frontend/#/dashboard\">회원</a>"
expect_check fail '표시 줄 없음' "<head></head>$links_ok"
expect_check fail '표시 줄 두 번' "<head><!-- SITE_URL_META --><!-- SITE_URL_META --></head>$links_ok"

# stamp: 표시 줄이 사이트 주소의 og:url·canonical 로 바뀐다.
expect_stamp() {
  local want="$1" label="$2" site_url="$3" expected="$4" file got
  file="$work/stamp.html"
  printf '%s\n' "$head_ok$links_ok" > "$file"
  if bash "$tool" stamp "$file" "$site_url" > /dev/null 2>&1 \
    && grep -qF "<meta property=\"og:url\" content=\"$expected\" /><link rel=\"canonical\" href=\"$expected\" />" "$file" \
    && ! grep -qF '<!-- SITE_URL_META -->' "$file"; then
    got=pass
  else
    got=fail
  fi
  record "$want" "$got" "stamp: $label"
}

expect_stamp pass '끝 슬래시 있음' 'https://ewhasudo.zapto.org/' 'https://ewhasudo.zapto.org/'
expect_stamp pass '끝 슬래시 없음' 'https://d111111abcdef8.cloudfront.net' 'https://d111111abcdef8.cloudfront.net/'
expect_stamp fail 'https 아님' 'http://ewhasudo.zapto.org/' 'http://ewhasudo.zapto.org/'
expect_stamp fail '빈 값' '' 'https:///'
expect_stamp fail '구분자 섞임' 'https://a.example|b/' 'https://a.example|b/'
expect_stamp fail '따옴표 섞임' 'https://a.example/"x' 'https://a.example/"x'

# stamp 는 치환 전에 check 를 거친다 — 절대 주소가 남은 파일은 치환하지 않는다.
file="$work/stamp-bad.html"
printf '%s\n' "$head_ok<a href=\"https://ewhasudo.zapto.org/frontend/\">회원</a><a href=\"trainer/\">트레이너</a>" > "$file"
if bash "$tool" stamp "$file" 'https://ewhasudo.zapto.org/' > /dev/null 2>&1; then got=pass; else got=fail; fi
record fail "$got" "stamp: 절대 주소가 남은 파일"

# verify: 로컬 정적 서버로 배포된 사이트를 흉내 낸다(python3 가 있을 때만).
if command -v python3 > /dev/null 2>&1 && command -v curl > /dev/null 2>&1; then
  site="$work/site"
  mkdir -p "$site/frontend" "$site/trainer"
  echo ok > "$site/frontend/index.html"
  echo ok > "$site/trainer/index.html"
  port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$site" > /dev/null 2>&1 &
  server=$!
  # 끝에서 서버를 내릴 때 셸이 작업 종료 안내를 찍지 않게 작업 목록에서 뗀다.
  disown "$server"
  for _ in $(seq 1 50); do
    curl -fs -o /dev/null "http://127.0.0.1:$port/frontend/" && break
    sleep 0.1
  done
  base="http://127.0.0.1:$port"
  stamped='https://ewhasudo.zapto.org/'

  expect_verify() {
    local want="$1" label="$2" body="$3" got
    printf '%s\n' "$body" > "$site/index.html"
    if bash "$tool" verify "$base" "$stamped" 0 > /dev/null 2>&1; then got=pass; else got=fail; fi
    record "$want" "$got" "verify: $label"
  }

  canonical="<head><meta property=\"og:url\" content=\"$stamped\" /><link rel=\"canonical\" href=\"$stamped\" /></head>"
  expect_verify pass '치환된 랜딩' "$canonical$links_ok"
  expect_verify fail '표시 줄이 남은 랜딩' "$head_ok$links_ok"
  expect_verify fail '다른 canonical' "<head><link rel=\"canonical\" href=\"https://other.example/\" /></head>$links_ok"
  expect_verify fail '절대 주소 바로가기' "$canonical<a href=\"https://ewhasudo.zapto.org/frontend/\">회원</a><a href=\"trainer/\">트레이너</a>"
  rm -rf "$site/trainer"
  expect_verify fail '트레이너 웹 경로 없음' "$canonical$links_ok"

  kill "$server" || true
else
  echo "skip: python3·curl 이 없어 verify 경계 검사를 건너뜁니다."
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
