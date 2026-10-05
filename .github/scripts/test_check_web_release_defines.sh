#!/usr/bin/env bash
# check_web_release_defines.sh 의 통과·실패 경계 검사(#3147).
# 사용: bash .github/scripts/test_check_web_release_defines.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/check_web_release_defines.sh"
failures=0

# expect <pass|fail> <설명> <인자...>
expect() {
  local want="$1" label="$2" got
  shift 2
  if bash "$guard" "$@" > /dev/null 2>&1; then
    got=pass
  else
    got=fail
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> $got (기대: $want)"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got"
  fi
}

# 운영 웹 빌드가 실제로 넘기는 모양(aws-frontend-deploy.yml).
GOOD=(
  --release --base-href "/frontend/"
  --dart-define=RELEASE_SHA=abc123
  --dart-define=KAKAO_JS_KEY=
  --dart-define=USE_MOCK_API=false
  --dart-define=API_BASE_URL=https://api.oncare.kr/v1
  --dart-define=ENV=prod
  --dart-define=SENTRY_DSN=
)

expect pass '운영 웹 빌드 인자' "${GOOD[@]}"
expect pass 'staging 실서버' "${GOOD[@]/ENV=prod/ENV=staging}"
expect pass '두 칸 모양 --dart-define KEY=VALUE' \
  --release --dart-define ENV=prod --dart-define USE_MOCK_API=false
expect pass 'SHOW_DEMO_ENTRY=false 는 기본값과 같다' "${GOOD[@]}" --dart-define=SHOW_DEMO_ENTRY=false
expect pass 'REAL_API 가 빈 값' "${GOOD[@]}" --dart-define=REAL_API=
expect pass '도구가 붙인 엉뚱한 인자는 건너뛴다' "${GOOD[@]}" --no-tree-shake-icons --pwa-strategy=none

# 이 이슈의 두 값(#3147)
expect fail '데모 진입 노출' "${GOOD[@]}" --dart-define=SHOW_DEMO_ENTRY=true
expect fail '데모 진입 노출(대문자)' "${GOOD[@]}" --dart-define=SHOW_DEMO_ENTRY=TRUE
expect fail '데모 진입 노출(두 칸 모양)' "${GOOD[@]}" --dart-define SHOW_DEMO_ENTRY=true
expect fail 'REAL_API 한 기능' "${GOOD[@]}" --dart-define=REAL_API=ai-coach
expect fail 'REAL_API 여러 기능' "${GOOD[@]}" --dart-define=REAL_API=ai-coach,auth

# 모바일 검사와 같은 나머지 규칙
expect fail '데모 빌드 표시' "${GOOD[@]}" --dart-define=DEMO_BUILD=true
expect fail 'ENV 누락' --release --dart-define=USE_MOCK_API=false
expect fail 'ENV=dev' "${GOOD[@]/ENV=prod/ENV=dev}"
expect fail 'USE_MOCK_API 누락' --release --dart-define=ENV=prod
expect fail 'USE_MOCK_API=true' "${GOOD[@]/USE_MOCK_API=false/USE_MOCK_API=true}"
expect fail '파일로 넘긴 값' "${GOOD[@]}" --dart-define-from-file=config/release.json
expect fail '형식이 아닌 dart-define' "${GOOD[@]}" --dart-define=SHOW_DEMO_ENTRY
expect fail '값 없는 끝 --dart-define' "${GOOD[@]}" --dart-define
# 뒤에 온 값이 이긴다 — flutter 도 마지막 값을 쓴다.
expect fail '좋은 값 뒤에 덮어쓴 데모 진입' \
  "${GOOD[@]}" --dart-define=SHOW_DEMO_ENTRY=false --dart-define=SHOW_DEMO_ENTRY=true
expect pass '데모 진입을 다시 끈 경우' \
  "${GOOD[@]}" --dart-define=SHOW_DEMO_ENTRY=true --dart-define=SHOW_DEMO_ENTRY=false

# 운영 배포 워크플로가 이 검사를 실제로 거쳐 빌드하는지 본다 — 검사가 있어도 빌드
# 단계가 다른 인자로 빌드하면 소용없다.
workflow="$here/../workflows/aws-frontend-deploy.yml"
checks=$(grep -cF 'check_web_release_defines.sh" "${args[@]}"' "$workflow" || true)
builds=$(grep -cF 'flutter build web "${args[@]}"' "$workflow" || true)
if [ "$checks" -ne 2 ] || [ "$builds" -ne 2 ]; then
  echo "FAIL: aws-frontend-deploy.yml 의 두 앱 빌드가 검사한 인자로 빌드하지 않습니다(검사 $checks, 빌드 $builds, 기대 2·2)"
  failures=$((failures + 1))
else
  echo "ok:   aws-frontend-deploy.yml 두 앱이 검사한 인자로 빌드"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
