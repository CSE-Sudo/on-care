#!/usr/bin/env bash
# 운영 CloudFront 응답 보안 헤더 확인(#3017).
#
# infra/frontend-hosting.yml 의 응답 헤더 정책이 실제 응답에 붙어 있는지 배포 직후에 본다.
# 스택을 갱신하지 않았거나 ApiOrigin 이 API_BASE_URL 과 어긋나면 두 앱이 운영 API 를 부르지
# 못하거나(connect-src 차단), 다른 사이트가 iframe 에 넣을 수 있는 상태로 남는다.
#
# 사용: bash .github/scripts/frontend_security_headers.sh <https://배포 주소> <API 출처>
#   API 출처는 API_BASE_URL 에서 경로를 뺀 값(예: https://api.example.org)
#
# 모든 경로: HSTS(max-age 1년 이상), X-Frame-Options DENY, nosniff, Referrer-Policy,
#            CSP frame-ancestors 'none'
# 앱 경로(/frontend/, /trainer/): CSP connect-src 에 API 출처가 있고 https: 전체·http:// ·
#            localhost·127.0.0.1 이 없음
set -uo pipefail

base="${1:-}"
api_origin="${2:-}"
if [ -z "$base" ] || [ -z "$api_origin" ]; then
  echo "사용: $0 <배포 주소> <API 출처>" >&2
  exit 2
fi
base="${base%/}"
api_origin="${api_origin%/}"
api_origin=$(printf '%s' "$api_origin" | tr '[:upper:]' '[:lower:]')

failures=0
fail() {
  echo "::error title=Security headers::$1"
  failures=$((failures + 1))
}

# 헤더 이름은 소문자로, 값은 그대로. 같은 헤더가 여러 번이면 첫 값만 본다.
header() {
  local headers="$1" name="$2"
  printf '%s\n' "$headers" | tr -d '\r' \
    | awk -v n="$name" '{ split($0, a, ":"); if (tolower(a[1]) == n) { sub(/^[^:]*:[ \t]*/, ""); print; exit } }'
}

# CSP 에서 지시어 하나의 출처 목록(공백 구분, 소문자).
directive() {
  local csp="$1" name="$2"
  printf '%s\n' "$csp" | tr ';' '\n' \
    | awk -v n="$name" '{ $1 = tolower($1) } $1 == n { $1 = ""; sub(/^ +/, ""); print tolower($0); exit }'
}

check_path() {
  local path="$1" app="$2" headers hsts maxage frame nosniff referrer csp fa connect
  if ! headers=$(curl --fail --silent --show-error --max-time 20 -o /dev/null -D - "$base$path"); then
    fail "$path 응답을 받지 못했습니다."
    return
  fi

  hsts=$(header "$headers" strict-transport-security)
  maxage=$(printf '%s' "$hsts" | sed -n 's/.*max-age=\([0-9][0-9]*\).*/\1/p')
  if [ -z "$maxage" ] || [ "$maxage" -lt 31536000 ]; then
    fail "$path: Strict-Transport-Security 가 없거나 max-age 가 1년 미만입니다('$hsts')."
  fi

  frame=$(header "$headers" x-frame-options)
  if [ "$(printf '%s' "$frame" | tr '[:lower:]' '[:upper:]')" != "DENY" ]; then
    fail "$path: X-Frame-Options 가 DENY 가 아닙니다('$frame')."
  fi

  nosniff=$(header "$headers" x-content-type-options)
  if [ "$(printf '%s' "$nosniff" | tr '[:upper:]' '[:lower:]')" != "nosniff" ]; then
    fail "$path: X-Content-Type-Options nosniff 가 없습니다."
  fi

  referrer=$(header "$headers" referrer-policy)
  if [ -z "$referrer" ]; then
    fail "$path: Referrer-Policy 가 없습니다."
  fi

  csp=$(header "$headers" content-security-policy)
  if [ -z "$csp" ]; then
    fail "$path: Content-Security-Policy 헤더가 없습니다."
    return
  fi
  fa=$(directive "$csp" frame-ancestors)
  if [ "$fa" != "'none'" ]; then
    fail "$path: CSP frame-ancestors 가 'none' 이 아닙니다('$fa')."
  fi

  if [ "$app" = "app" ]; then
    connect=$(directive "$csp" connect-src)
    if [ -z "$connect" ]; then
      fail "$path: CSP connect-src 가 없습니다."
      return
    fi
    case " $connect " in
      *" $api_origin "*) ;;
      *) fail "$path: CSP connect-src 에 API 출처($api_origin)가 없습니다 — 스택 파라미터 ApiOrigin 을 확인하세요." ;;
    esac
    for source in $connect; do
      case "$source" in
        https:|http:|'*'|http://*|*localhost*|*127.0.0.1*)
          fail "$path: CSP connect-src 가 좁혀지지 않았습니다('$source')." ;;
      esac
    done
  fi
  echo "ok: $path"
}

check_path / landing
check_path /frontend/ app
check_path /trainer/ app

if [ "$failures" -gt 0 ]; then
  echo "응답 보안 헤더 확인 실패: $failures 건" >&2
  exit 1
fi
echo "응답 보안 헤더 확인 완료."
