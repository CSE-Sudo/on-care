#!/usr/bin/env bash
# GitHub Pages 데모 빌드의 meta CSP connect-src 를 좁히고 확인한다(#3089).
#
# 두 앱 web/index.html 의 meta CSP 는 로컬 개발(`flutter run -d chrome`)을 위해
# `connect-src 'self' https: http://localhost:* http://127.0.0.1:*` 로 넓게 열려 있다.
# 운영(CloudFront)은 응답 헤더 CSP 가 API 출처로 좁히지만(#3017), Pages 는 응답 헤더를
# 바꿀 수 없어 meta 가 전부다. 그래서 데모 빌드 산출물의 connect-src 를 그 빌드가 실제로
# 부르는 출처만으로 바꾼다 — 운영 헤더와 같은 목록이다.
#   'self' · API 출처(실서버 빌드만, 목업은 네트워크를 쓰지 않는다) · CanvasKit(www.gstatic.com)
#   · 대체 글꼴(fonts.gstatic.com) · 카카오맵 SDK(dapi.kakao.com)
#   · 구글 로그인 버튼(accounts.google.com/gsi/, #330)
#
# 사용:
#   pages_demo_csp.sh narrow <index.html> [API_BASE_URL]   산출물의 connect-src 를 바꾼다
#   pages_demo_csp.sh check  <index.html> [API_BASE_URL]   좁혀졌는지 확인한다
# check 의 차단 기준은 운영 헤더 검사(frontend_security_headers.sh)와 같다(#3255) — scheme 전체
# (https:·http:·wss:·ws:)·`*`·호스트가 `*` 인 출처(https://*·https://*:443·https://*/…)·http://·ws://
# 평문 출처·localhost·127.0.0.1. 하위 도메인 묶음(https://*.example.com)은 허용한다.
# API_BASE_URL 을 주면(실서버 빌드) 그 출처(`https://호스트[:포트]`)를 넣고·요구한다.
set -euo pipefail
# connect-src 의 `*` 가 파일 이름으로 펼쳐지지 않게 한다.
set -f

STATIC_SOURCES="https://www.gstatic.com https://fonts.gstatic.com https://dapi.kakao.com https://accounts.google.com/gsi/"

fail() {
  echo "::error title=Pages 데모 CSP::$1" >&2
  exit 1
}

# api_origin <API_BASE_URL>: https://host[:port] 만 남긴다.
api_origin() {
  local url=$1
  case "$url" in
    https://*) ;;
    *) fail "API_BASE_URL 은 https:// 로 시작해야 합니다: $url" ;;
  esac
  local rest=${url#https://}
  local host=${rest%%/*}
  case "$host" in
    '' | *[!A-Za-z0-9.:-]*) fail "API_BASE_URL 의 호스트가 올바르지 않습니다: $url" ;;
  esac
  printf 'https://%s' "$host"
}

# meta_csp <file>: meta CSP 의 content 값을 한 줄로 낸다. 정확히 하나여야 한다.
meta_csp() {
  local found
  found=$(grep -o '<meta http-equiv="Content-Security-Policy" content="[^"]*"' "$1" || true)
  if [ -z "$found" ]; then
    fail "$1 에 meta CSP 가 없습니다."
  fi
  if [ "$(printf '%s\n' "$found" | wc -l)" -ne 1 ]; then
    fail "$1 에 meta CSP 가 여러 개입니다."
  fi
  found=${found#*content=\"}
  printf '%s' "${found%\"}"
}

# connect_src <csp>: connect-src 지시어의 출처 목록.
connect_src() {
  printf '%s' "$1" | tr ';' '\n' | sed -n 's/^[[:space:]]*connect-src[[:space:]]\{1,\}//p' | head -n 1
}

cmd=${1:-}
file=${2:-}
base_url=${3:-}
if [ -z "$cmd" ] || [ -z "$file" ]; then
  echo "사용: $0 narrow|check <index.html> [API_BASE_URL]" >&2
  exit 2
fi
if [ ! -f "$file" ]; then
  fail "$file 이 없습니다."
fi

origin=""
if [ -n "$base_url" ]; then
  origin=$(api_origin "$base_url")
fi

case "$cmd" in
  narrow)
    csp=$(meta_csp "$file")
    if [ -z "$(connect_src "$csp")" ]; then
      fail "$file 의 meta CSP 에 connect-src 가 없습니다."
    fi
    sources="'self'${origin:+ $origin} $STATIC_SOURCES"
    # connect-src 지시어 하나만 바꾼다(다음 `;` 전까지). 다른 지시어의 https: 는 그대로 둔다.
    tmp=$(mktemp)
    sed -E "/<meta http-equiv=\"Content-Security-Policy\"/ s#connect-src [^;\"]*#connect-src ${sources}#" \
      "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "$file: connect-src ${sources}"
    ;;
  check)
    csp=$(meta_csp "$file")
    connect=$(connect_src "$csp")
    if [ -z "$connect" ]; then
      fail "$file 의 meta CSP 에 connect-src 가 없습니다."
    fi
    for source in $connect; do
      case "$source" in
        https: | http: | wss: | ws: | '*' | *://\* | *://\*:* | *://\*/*)
          fail "$file: connect-src 가 좁혀지지 않았습니다('$source')." ;;
        http://* | ws://*)
          fail "$file: connect-src 에 평문(http·ws) 출처가 남아 있습니다('$source')." ;;
        *localhost* | *127.0.0.1*)
          fail "$file: connect-src 에 로컬 개발 주소가 남아 있습니다('$source')." ;;
      esac
    done
    if [ -n "$origin" ]; then
      case " $connect " in
        *" $origin "*) ;;
        *) fail "$file: connect-src 에 API 출처($origin)가 없습니다." ;;
      esac
    fi
    echo "$file: connect-src $connect"
    ;;
  *)
    echo "사용: $0 narrow|check <index.html> [API_BASE_URL]" >&2
    exit 2
    ;;
esac
