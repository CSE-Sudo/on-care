#!/usr/bin/env bash
# 소개(랜딩) 페이지가 특정 도메인에 묶이지 않게 하는 검사·치환·배포 후 확인(#2841).
#
# 같은 index.html 이 GitHub Pages(데모)와 AWS CloudFront(운영)에 그대로 올라간다. 두 배포 모두
# 랜딩을 루트에, 회원 앱을 /frontend/, 트레이너 웹을 /trainer/ 에 두므로 앱 바로가기는 상대 경로
# (`frontend/#/dashboard`, `trainer/`)여야 각 배포에서 자기 앱으로 간다. 공개 정책 페이지(#3005)도 같은 이유로
# `legal/privacy.html` 상대 경로다 — 스토어에 적는 처리방침 주소가 배포마다 자기 도메인을 가리킨다. 절대 주소가 다시 들어오면
# 운영 방문자가 데모로 넘어가고, 무료 DNS 이름이 끊기면 운영 랜딩의 버튼까지 함께 죽는다.
# og:url·canonical 은 상대 경로를 쓸 수 없어 원본에는 표시 줄(<!-- SITE_URL_META -->)만 두고,
# 각 배포 워크플로가 자기 도메인으로 바꾼다.
#
# 사용
#   bash landing_site_url.sh check  <index.html>
#       앱 바로가기에 절대 주소가 없고, 상대 경로 바로가기와 표시 줄이 있는지 확인
#   bash landing_site_url.sh stamp  <배포용 index.html> <사이트 주소>
#       표시 줄을 og:url·canonical 태그로 바꿈(사이트 주소는 https://도메인/ 형식)
#   bash landing_site_url.sh verify <배포 주소> <사이트 주소> [대기 초]
#       배포된 랜딩을 받아 바로가기가 상대 경로인지, canonical 이 사이트 주소인지,
#       같은 도메인의 /frontend/·/trainer/·/legal/privacy.html 이 응답하는지 확인(캐시가 바뀔 때까지 재시도)
set -euo pipefail

MARKER='<!-- SITE_URL_META -->'
# 바로가기 href 가 http(s):// 로 시작하면서 frontend·trainer·legal 경로를 가리키면 절대 주소로 본다.
ABSOLUTE_APP_LINK='href="https?://[^"]*/(frontend|trainer|legal)([/"#?])'

fail() {
  echo "::error title=landing::$1"
  exit 1
}

usage() {
  echo "사용: $0 check <index.html> | stamp <index.html> <site_url> | verify <base_url> <site_url> [wait_seconds]" >&2
  exit 2
}

# 랜딩 HTML 본문을 검사한다. 실패 사유를 표준 출력으로 내고 0/1 을 돌려준다.
inspect_html() {
  local file="$1" found
  if found=$(grep -nE "$ABSOLUTE_APP_LINK" "$file"); then
    echo "앱 바로가기에 절대 주소가 있습니다. frontend/·trainer/ 상대 경로를 쓰세요."
    echo "$found"
    return 1
  fi
  if ! grep -qE 'href="(\./)?frontend/' "$file"; then
    echo "회원 앱 상대 경로 바로가기(href=\"frontend/...\")가 없습니다."
    return 1
  fi
  if ! grep -qE 'href="(\./)?trainer/' "$file"; then
    echo "트레이너 웹 상대 경로 바로가기(href=\"trainer/\")가 없습니다."
    return 1
  fi
  if ! grep -qE 'href="(\./)?legal/privacy\.html"' "$file"; then
    echo "개인정보 처리방침 상대 경로 링크(href=\"legal/privacy.html\")가 없습니다."
    return 1
  fi
  return 0
}

validate_site_url() {
  local url="$1"
  case "$url" in
    https://*) ;;
    *) fail "사이트 주소는 https:// 로 시작해야 합니다: '$url'" ;;
  esac
  # sed 치환·HTML 속성에 그대로 들어가므로 구분자·따옴표·공백이 섞인 값은 받지 않는다.
  if printf '%s' "$url" | grep -qE '[|"<>[:space:]]'; then
    fail "사이트 주소에 쓸 수 없는 문자가 있습니다: '$url'"
  fi
}

# 끝에 / 를 붙인다. 검사는 validate_site_url 이 먼저 한다(서브셸 안의 실패는 메시지가 묻히므로).
normalize_site_url() {
  local url="$1"
  case "$url" in
    */) printf '%s' "$url" ;;
    *) printf '%s/' "$url" ;;
  esac
}

cmd_check() {
  local file="$1" reason count
  [ -f "$file" ] || fail "파일이 없습니다: $file"
  if ! reason=$(inspect_html "$file"); then
    fail "$file: $reason"
  fi
  count=$({ grep -oF "$MARKER" "$file" || true; } | wc -l | tr -d ' ')
  if [ "$count" != "1" ]; then
    fail "$file: og:url·canonical 표시 줄 '$MARKER' 이 정확히 한 번 있어야 합니다(현재 ${count}번)."
  fi
  echo "랜딩 바로가기 확인 완료: $file"
}

cmd_stamp() {
  local file="$1" site_url tags tmp
  cmd_check "$file"
  validate_site_url "$2"
  site_url=$(normalize_site_url "$2")
  tags="<meta property=\"og:url\" content=\"${site_url}\" /><link rel=\"canonical\" href=\"${site_url}\" />"
  tmp="$(mktemp)"
  sed "s|${MARKER}|${tags}|" "$file" > "$tmp"
  mv "$tmp" "$file"
  grep -qF "rel=\"canonical\" href=\"${site_url}\"" "$file" || fail "canonical 치환 결과를 찾지 못했습니다."
  grep -qF "property=\"og:url\" content=\"${site_url}\"" "$file" || fail "og:url 치환 결과를 찾지 못했습니다."
  echo "og:url·canonical = ${site_url}"
}

cmd_verify() {
  local base="${1%/}" site_url wait_seconds deadline page reason path
  validate_site_url "$2"
  site_url=$(normalize_site_url "$2")
  wait_seconds="${3:-300}"
  deadline=$(( $(date +%s) + wait_seconds ))
  page="$(mktemp)"
  while :; do
    reason=""
    if curl -fsSL --max-time 20 -H 'Cache-Control: no-cache' \
        "$base/?landingcheck=$(date +%s)" -o "$page"; then
      if ! reason=$(inspect_html "$page"); then
        :
      elif ! grep -qF "rel=\"canonical\" href=\"${site_url}\"" "$page"; then
        reason="canonical 이 ${site_url} 이 아닙니다."
      fi
    else
      reason="$base/ 응답 없음"
    fi
    if [ -z "$reason" ]; then
      break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      rm -f "$page"
      fail "배포된 랜딩 확인 실패($base): $reason"
    fi
    echo "  아직 아님: $reason — 다시 확인합니다."
    sleep 10
  done
  rm -f "$page"
  # 상대 경로 바로가기는 같은 도메인의 이 경로들로 열린다. 처리방침은 스토어 심사가 여는
  # 공개 주소라 함께 본다(#3005).
  for path in frontend/ trainer/ legal/privacy.html; do
    curl -fsS --max-time 20 -o /dev/null "$base/$path" || fail "바로가기 목적지 $base/$path 가 응답하지 않습니다."
  done
  echo "배포된 랜딩 확인 완료: $base/ → $base/frontend/, $base/trainer/, $base/legal/privacy.html (canonical ${site_url})"
}

[ $# -ge 1 ] || usage
command="$1"
shift
case "$command" in
  check) [ $# -eq 1 ] || usage; cmd_check "$1" ;;
  stamp) [ $# -eq 2 ] || usage; cmd_stamp "$1" "$2" ;;
  verify) [ $# -ge 2 ] && [ $# -le 3 ] || usage; cmd_verify "$@" ;;
  *) usage ;;
esac
