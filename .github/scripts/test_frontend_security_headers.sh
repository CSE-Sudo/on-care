#!/usr/bin/env bash
# frontend_security_headers.sh 의 통과·실패 경계 검사(#3017).
# 실제 네트워크 대신 PATH 앞에 둔 가짜 curl 이 경로별 응답 헤더 픽스처를 돌려준다.
# 사용: bash .github/scripts/test_frontend_security_headers.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/frontend_security_headers.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
url="${*: -1}"
path="${url#https://*/}"
case "$path" in
  "") slug=root ;;
  frontend/) slug=frontend ;;
  trainer/) slug=trainer ;;
  *) slug=other ;;
esac
file="$FAKE_HEADERS_DIR/$slug"
if [ ! -f "$file" ]; then
  echo "curl: (22) The requested URL returned error: 404" >&2
  exit 22
fi
cat "$file"
FAKE
chmod +x "$work/bin/curl"

api='https://api.oncare.test'
app_csp="default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self' $api https://www.gstatic.com https://fonts.gstatic.com; frame-ancestors 'none'"
landing_csp="default-src 'self'; script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'"

# 정상 응답 헤더를 세 경로에 쓴다. 인자로 받은 경로 하나만 바꿔 실패 경우를 만든다.
write_fixture() {
  local dir="$1" slug csp
  mkdir -p "$dir"
  for slug in root frontend trainer; do
    if [ "$slug" = root ]; then csp="$landing_csp"; else csp="$app_csp"; fi
    printf 'HTTP/2 200\r\ncontent-type: text/html\r\nstrict-transport-security: max-age=31536000; includeSubDomains\r\nx-frame-options: DENY\r\nx-content-type-options: nosniff\r\nreferrer-policy: strict-origin-when-cross-origin\r\ncontent-security-policy: %s\r\n\r\n' "$csp" > "$dir/$slug"
  done
}

expect() {
  local want="$1" label="$2" dir="$3" origin="${4:-$api}" got
  if FAKE_HEADERS_DIR="$dir" PATH="$work/bin:$PATH" bash "$tool" https://d111.cloudfront.net/ "$origin" > "$work/out" 2>&1; then
    got=pass
  else
    got=fail
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> $got (기대: $want)"
    sed 's/^/    /' "$work/out"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got"
  fi
}

case_dir() { local d="$work/case-$1"; rm -rf "$d"; write_fixture "$d"; printf '%s' "$d"; }

d=$(case_dir ok); expect pass '세 경로 모두 정상' "$d"
d=$(case_dir origin-case); expect pass 'API 출처 대소문자·끝 / 무시' "$d" 'https://API.oncare.test/'

d=$(case_dir hsts-missing)
sed -i.bak '/strict-transport-security/d' "$d/frontend"; expect fail 'HSTS 누락' "$d"

d=$(case_dir hsts-short)
sed -i.bak 's/max-age=31536000/max-age=300/' "$d/root"; expect fail 'HSTS max-age 1년 미만' "$d"

d=$(case_dir frame)
sed -i.bak 's/x-frame-options: DENY/x-frame-options: SAMEORIGIN/' "$d/trainer"; expect fail 'X-Frame-Options SAMEORIGIN' "$d"

d=$(case_dir nosniff)
sed -i.bak '/x-content-type-options/d' "$d/root"; expect fail 'nosniff 누락' "$d"

d=$(case_dir referrer)
sed -i.bak '/referrer-policy/d' "$d/frontend"; expect fail 'Referrer-Policy 누락' "$d"

d=$(case_dir csp-missing)
sed -i.bak '/content-security-policy/d' "$d/trainer"; expect fail 'CSP 헤더 누락' "$d"

d=$(case_dir fa)
sed -i.bak "s/frame-ancestors 'none'/frame-ancestors 'self'/" "$d/root"; expect fail "frame-ancestors 'self'" "$d"

d=$(case_dir wide)
sed -i.bak "s#connect-src 'self' $api#connect-src 'self' https: $api#" "$d/frontend"
expect fail 'connect-src 에 https: 전체가 그대로' "$d"

d=$(case_dir local)
sed -i.bak "s#connect-src 'self'#connect-src 'self' http://localhost:*#" "$d/trainer"
expect fail 'connect-src 에 localhost' "$d"

d=$(case_dir wrong-origin); expect fail 'ApiOrigin 이 API_BASE_URL 과 다름' "$d" 'https://other-api.oncare.test'

d=$(case_dir down); rm "$d/trainer"; expect fail '경로 응답 실패' "$d"

# 소개 페이지는 connect-src 를 API 로 열 필요가 없다 — 앱 경로 규칙을 적용하지 않는다.
d=$(case_dir landing-self); expect pass "소개 페이지 connect-src 'self' 만" "$d"

if FAKE_HEADERS_DIR="$work" PATH="$work/bin:$PATH" bash "$tool" > /dev/null 2>&1; then got=pass; else got=fail; fi
if [ "$got" = fail ]; then echo "ok:   인자 없음 -> fail"; else echo "FAIL: 인자 없음 -> pass"; failures=$((failures + 1)); fi

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "frontend_security_headers.sh 검사 통과"
