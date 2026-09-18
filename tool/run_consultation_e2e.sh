#!/usr/bin/env bash
#
# 회원↔트레이너 상담 처리 실 API E2E (#640).
#
# `tool/run_reservation_e2e.sh`(#637)·`tool/run_chat_e2e.sh`(#639)와 같은 구조다 —
# 두 앱은 서로 다른 Dart 패키지라 한 프로세스에 함께 띄울 수 없어, 한 시나리오를
# 단계로 쪼개 번갈아 실행한다.
#
#   1. (회원)     member-request       새 회원 둘이 트레이너가 연 자리를 UI 폼으로 골라 신청한다
#   2. (트레이너) trainer-accept       인박스에서 내용 확인 → 승인(고른 자리에 일정이 생긴다)
#   3. (회원)     member-after-accept  승인·담당·일정이 회원에게 돌아온다(재로그인 포함)
#   4. (트레이너) trainer-reject       다른 요청을 사유와 함께 거절
#   5. (회원)     member-after-reject  같은 사유가 보이고 다시 신청할 수 있다
#   6. (트레이너) empty-inbox          처리한 요청이 대기 목록에서 빠진다
#   7. (회원)     edge-cases           중복 제출·남의 상담 조회
#   8. 정리                            승인이 만든 일정·이번 실행이 연 자리·계정 둘 정리
#
# **정리가 이 스위트의 일부다.** 계정을 지우면 상담·담당 연결은 FK CASCADE 로 함께
# 사라지지만, `trainer_schedule.member_id` 는 SET NULL 이라 승인이 만든 상담 일정은
# 주인 없이 남는다. 그래서 일정을 먼저 지우고 계정을 지운다. 상담이 고를 자리도
# 이 스위트가 열었으니 닫는다(#1873). 앞 단계가 실패해도 정리는 돈다 — 지우지
# 않으면 다음 실행마다 트레이너 달력과 자리 목록에 유령이 쌓인다.
#
# 사용법:
#   bash tool/run_consultation_e2e.sh
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly API_BASE_URL="${API_BASE_URL:-http://localhost:8000/v1}"
readonly STATE_FILE="${E2E_STATE_FILE:-$(mktemp -t oncare_consult_e2e_XXXXXX.json)}"
readonly FLUTTER="${FLUTTER:-flutter}"

if ! curl --fail --silent --max-time 10 "${API_BASE_URL%/v1}/v1/healthz" >/dev/null; then
  echo "백엔드가 준비되지 않았습니다: ${API_BASE_URL%/v1}/v1/healthz" >&2
  echo "  docs/local_fullstack.md 참고" >&2
  exit 1
fi

echo "{}" >"$STATE_FILE"
echo "상태 파일: $STATE_FILE"
echo

run_phase() {
  local package="$1" target="$2" phase="$3"
  echo "── [$phase] $package"
  (
    cd "$ROOT/$package"
    "$FLUTTER" test "$target" \
      --dart-define=USE_MOCK_API=false \
      --dart-define=API_BASE_URL="$API_BASE_URL" \
      --dart-define=E2E_PHASE="$phase" \
      --dart-define=E2E_STATE_FILE="$STATE_FILE"
  )
  echo
}

member() {
  run_phase frontend/flutter test_e2e/consultation_member_test.dart "$1"
}
trainer() {
  run_phase frontend/flutter_trainer test_e2e/consultation_trainer_test.dart "$1"
}

cleanup() {
  local status=$?
  echo "── [정리] 상담 일정·자리와 E2E 계정 정리"
  if ! run_phase frontend/flutter test_e2e/consultation_member_test.dart cleanup; then
    echo "::error::정리에 실패했습니다. 남은 상태: $STATE_FILE" >&2
    echo "  계정과 상담 일정이 서버에 남아 있습니다. 파일의 id 로 직접 지우세요." >&2
    status=1
  fi
  if [ -n "${failed_phase:-}" ]; then
    echo "::error::[$failed_phase] 에서 실패했습니다. 상태 파일: $STATE_FILE" >&2
  elif [ "$status" -eq 0 ]; then
    echo "✅ 상담 실 API E2E 전 단계 통과"
  fi
  exit "$status"
}
trap cleanup EXIT

failed_phase='member-request'
member member-request

failed_phase='trainer-accept'
trainer trainer-accept

failed_phase='member-after-accept'
member member-after-accept

failed_phase='trainer-reject'
trainer trainer-reject

failed_phase='member-after-reject'
member member-after-reject

failed_phase='empty-inbox'
trainer empty-inbox

failed_phase='edge-cases'
member edge-cases

failed_phase=''
