#!/usr/bin/env bash
# check_release_defines.sh 의 통과·실패 경계 검사(#3022).
# 사용: bash frontend/flutter/tool/test_check_release_defines.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/check_release_defines.sh"
example="$here/../config/release.example.json"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
case_no=0

GOOD_URL='https://api.oncare.kr/v1'
GOOD_DSN='https://abc123@o1.ingest.sentry.io/42'

# expect <pass|fail> <설명> <JSON 본문>
expect() {
  local want="$1" label="$2" body="$3" got file
  case_no=$((case_no + 1))
  file="$work/case$case_no.json"
  printf '%s' "$body" > "$file"
  if bash "$guard" "$file" > /dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> $got (기대: $want)"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got"
  fi
}

good() {
  printf '{"ENV":"%s","USE_MOCK_API":%s,"API_BASE_URL":"%s","SENTRY_DSN":"%s"%s}' \
    "${1:-prod}" "${2:-\"false\"}" "${3:-$GOOD_URL}" "${4:-$GOOD_DSN}" "${5:-}"
}

# 정상
expect pass '운영 prod' "$(good)"
expect pass '내부 staging' "$(good staging)"
expect pass 'USE_MOCK_API 를 JSON false 로' "$(good prod false)"
expect pass '모르는 키는 경고만' "$(good prod '"false"' "$GOOD_URL" "$GOOD_DSN" ',"EXTRA":"1"')"
expect pass '지도 출처 운영 주소' "$(good prod '"false"' "$GOOD_URL" "$GOOD_DSN" ',"KAKAO_MAP_ORIGIN":"https://app.oncare.kr"')"
expect fail '지도 출처 localhost' "$(good prod '"false"' "$GOOD_URL" "$GOOD_DSN" ',"KAKAO_MAP_ORIGIN":"http://localhost"')"
expect fail '지도 출처 https localhost' "$(good prod '"false"' "$GOOD_URL" "$GOOD_DSN" ',"KAKAO_MAP_ORIGIN":"https://localhost"')"
expect fail '지도 출처 경로 포함' "$(good prod '"false"' "$GOOD_URL" "$GOOD_DSN" ',"KAKAO_MAP_ORIGIN":"https://app.oncare.kr/frontend"')"

# 필수 키 누락
expect fail 'ENV 누락' "{\"USE_MOCK_API\":\"false\",\"API_BASE_URL\":\"$GOOD_URL\",\"SENTRY_DSN\":\"$GOOD_DSN\"}"
expect fail 'USE_MOCK_API 누락' "{\"ENV\":\"prod\",\"API_BASE_URL\":\"$GOOD_URL\",\"SENTRY_DSN\":\"$GOOD_DSN\"}"
expect fail 'API_BASE_URL 누락' "{\"ENV\":\"prod\",\"USE_MOCK_API\":\"false\",\"SENTRY_DSN\":\"$GOOD_DSN\"}"
expect fail 'SENTRY_DSN 누락' "{\"ENV\":\"prod\",\"USE_MOCK_API\":\"false\",\"API_BASE_URL\":\"$GOOD_URL\"}"
expect fail 'SENTRY_DSN 빈 값' "$(good prod '"false"' "$GOOD_URL" ' ')"

# 형식 오류
expect fail 'ENV=dev' "$(good dev)"
expect fail 'USE_MOCK_API=true' "$(good prod '"true"')"
expect fail 'http 주소' "$(good prod '"false"' 'http://api.oncare.kr/v1')"
expect fail '/v1 없음' "$(good prod '"false"' 'https://api.oncare.kr')"
expect fail '끝 슬래시' "$(good prod '"false"' 'https://api.oncare.kr/v1/')"
expect fail '코드 기본값 예시 주소' "$(good prod '"false"' 'https://dev.api.oncare.example.com/v1')"
expect fail '.test 주소' "$(good prod '"false"' 'https://api.oncare.test/v1')"
expect fail 'localhost' "$(good prod '"false"' 'https://localhost/v1')"
expect fail '자리표시자 꺾쇠' "$(good prod '"false"' 'https://<운영 API 도메인>/v1')"
expect fail 'http DSN' "$(good prod '"false"' "$GOOD_URL" 'http://abc@o1.ingest.sentry.io/42')"
expect fail '데모 빌드 표시' "$(good prod '"false"' "$GOOD_URL" "$GOOD_DSN" ',"DEMO_BUILD":"true"')"
expect fail '데모 진입 노출' "$(good prod '"false"' "$GOOD_URL" "$GOOD_DSN" ',"SHOW_DEMO_ENTRY":true')"
expect fail 'REAL_API 남김' "$(good prod '"false"' "$GOOD_URL" "$GOOD_DSN" ',"REAL_API":"auth"')"
expect fail 'JSON 아님' 'ENV=prod'
expect fail 'JSON 배열' '["ENV","prod"]'

# 파일 없음·예시 그대로
if bash "$guard" "$work/none.json" > /dev/null 2>&1; then
  echo "FAIL: 없는 파일 -> pass (기대: fail)"; failures=$((failures + 1))
else
  echo "ok:   없는 파일 -> fail"
fi
if bash "$guard" "$example" > /dev/null 2>&1; then
  echo "FAIL: 예시 파일을 그대로 쓰면 -> pass (기대: fail)"; failures=$((failures + 1))
else
  echo "ok:   예시 파일을 그대로 쓰면 -> fail"
fi
# 예시 파일의 꺾쇠만 채우면 통과한다 — 예시가 필수 키를 모두 갖고 있다.
sed -e "s#https://<운영 API 도메인>/v1#$GOOD_URL#" \
    -e "s#https://<공개 키>@<조직>.ingest.sentry.io/<회원 앱 프로젝트 번호>#$GOOD_DSN#" \
    "$example" > "$work/filled.json"
if bash "$guard" "$work/filled.json" > /dev/null 2>&1; then
  echo "ok:   예시를 채우면 -> pass"
else
  echo "FAIL: 예시를 채워도 -> fail (기대: pass)"; failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
