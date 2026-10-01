#!/usr/bin/env bash
# check_demo_divergence.sh 의 자체 테스트(#2791).
#
# 검사가 오탐하면 필수 검사인 PR gate 의 경고가 쓸모없어지고, 실패 모드로
# 바꾼 뒤에는 모든 PR 병합을 막는다. 임시 저장소에 base·head 커밋을 만들어
# 걸림·안 걸림·예외 통과를 확인한다.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/check_demo_divergence.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# new_repo: 빈 base 커밋이 있는 임시 저장소로 들어간다.
new_repo() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo"
  cd "$work/repo"
  git init -q
  git config user.email test@example.com
  git config user.name test
  git commit -q --allow-empty -m base
  base=$(git rev-parse HEAD)
}

# put <path> <content>: 파일을 쓰고 head 커밋에 담는다.
put() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
  git add "$1"
  git commit -q -m head
}

# expect <name> <warnings> [mode]: 경고 수와 종료 코드를 확인한다.
expect() {
  local name="$1" want="$2" mode="${3:-warn}" out code=0 got
  out=$(DEMO_DIVERGENCE_MODE="$mode" GITHUB_STEP_SUMMARY="$work/summary" \
    bash "$script" "$base" 2>&1) || code=$?
  got=$(printf '%s\n' "$out" | grep -c '^::warning file=frontend' || true)
  local want_code=0
  if [ "$mode" = fail ] && [ "$want" -gt 0 ]; then want_code=1; fi
  if [ "$got" = "$want" ] && [ "$code" = "$want_code" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: 경고 $got건(기대 $want), 종료 $code(기대 $want_code)"
    printf '%s\n' "$out" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
}

page=frontend/flutter/lib/features/diet/presentation/pages/diet_page.dart
widget=frontend/flutter_trainer/lib/features/clients/presentation/widgets/card.dart
shared=frontend/flutter/lib/shared/widgets/sheet.dart
controller=frontend/flutter/lib/features/diet/presentation/controllers/diet_providers.dart
repo=frontend/flutter_trainer/lib/features/my/data/account_repository.dart

new_repo
put "$page" 'final demo = ref.watch(appConfigProvider).useMockApi;'
expect '화면(pages)의 새 useMockApi 는 걸린다' 1

new_repo
put "$widget" 'if (ref.read(appConfigProvider).useMockApi) {}'
put "$shared" 'final m = config.useMockApi;'
expect 'presentation/widgets 와 shared/widgets 도 걸린다' 2

new_repo
put "$controller" 'final repo = config.useMockApi ? Mock() : Dio();'
expect 'presentation/controllers 의 분기는 걸리지 않는다' 0

new_repo
put "$page" '  // useMockApi 를 직접 읽지 않는다.
final notMockApi = useMockApiish;'
expect '주석과 이름이 비슷한 식별자는 걸리지 않는다' 0

new_repo
put "$page" 'final demo = config.useMockApi;'
base=$(git rev-parse HEAD)
put "$page" 'final demo = config.useMockApi;
final other = 1;'
expect 'base 에 이미 있던 줄은 보지 않는다' 0

new_repo
put "$page" 'final demo = config.useMockApi;'
base=$(git rev-parse HEAD)
git rm -q "$page"
git commit -q -m remove
expect '지운 줄은 보지 않는다' 0

new_repo
put "$repo" 'class MockAccountRepository implements AccountRepository {
  @override
  bool get supportsDeletion => false;
}
class DioAccountRepository implements AccountRepository {
  @override
  bool get supportsExport => false;
}'
expect '목업 클래스의 supports… => false 만 걸린다' 1

new_repo
put frontend/flutter_trainer/lib/features/x/data/demo_x_repository.dart '  bool get supportsInbox => false;'
expect '파일 이름에 demo 가 있으면 걸린다' 1

new_repo
put frontend/flutter_trainer/lib/features/x/data/demo_x_repository.dart '  bool get supportsInbox => true;'
expect '=> true 는 걸리지 않는다' 0

new_repo
mkdir -p .github
printf '%s\n' '# 주석' "$page · 데모 전용 안내 · #1" > .github/demo-divergence-allowlist.txt
put "$page" 'final demo = config.useMockApi;'
put "$widget" 'final demo = config.useMockApi;'
expect '예외 목록의 파일은 통과하고 나머지는 걸린다' 1

new_repo
mkdir -p .github
printf '%s\n' "$page · 이슈 번호 없음" > .github/demo-divergence-allowlist.txt
put "$page" 'final demo = config.useMockApi;'
expect '이슈 번호가 없는 예외 줄은 무시된다' 1

new_repo
put "$page" 'final demo = config.useMockApi;'
expect '실패 모드에서는 걸리면 1 로 끝난다' 1 fail

new_repo
put "$controller" 'final repo = config.useMockApi;'
expect '실패 모드에서도 걸린 것이 없으면 0 으로 끝난다' 0 fail

if [ "$failures" -gt 0 ]; then
  echo "실패 ${failures}건"
  exit 1
fi
echo "모두 통과"
