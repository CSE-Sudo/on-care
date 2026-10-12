#!/usr/bin/env bash
#
# 앱의 테스트 파일을 묶음으로 나눠 그중 하나만 `flutter test` 로 돌린다(#3321).
#
# `flutter test --total-shards` 를 쓰지 않는 이유: 그 옵션은 파일이 아니라 **테스트**를
# 나눈다. 모든 묶음이 모든 파일을 컴파일하므로 시간이 거의 줄지 않고, 한 파일 안의
# 테스트가 서로 다른 러너로 흩어진다. 여기서는 파일을 통째로 나눈다 — 파일 안의 테스트는
# 나누기 전과 같은 프로세스에서 같은 순서로 돈다.
#
# 대상은 `flutter test` 를 인자 없이 돌릴 때와 같다: `test/` 아래의 `*_test.dart` 전부.
# 이름순으로 줄 세워 번갈아 나누므로 어느 파일도 빠지거나 두 묶음에 들어가지 않는다.
#
# 사용법(앱 폴더에서):
#   bash ../../.github/scripts/flutter_test_shard.sh <묶음 번호(1부터)> <전체 묶음 수> [flutter test 인자...]
set -euo pipefail

shard="${1:-}"
total="${2:-}"
case "$shard$total" in
  ''|*[!0-9]*) echo "::error::묶음 번호와 전체 묶음 수는 양의 정수여야 합니다: '$shard' '$total'" >&2; exit 2 ;;
esac
if [ -z "$shard" ] || [ -z "$total" ] || [ "$shard" -lt 1 ] || [ "$shard" -gt "$total" ]; then
  echo "::error::묶음 번호는 1 이상 전체 묶음 수 이하여야 합니다: $shard/$total" >&2
  exit 2
fi
shift 2

if [ ! -d test ]; then
  echo "::error::test/ 폴더가 없습니다. 앱 폴더에서 실행하세요: $PWD" >&2
  exit 2
fi

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(find test -type f -name '*_test.dart' | LC_ALL=C sort)

picked=()
for i in "${!files[@]}"; do
  if [ $((i % total)) -eq $((shard - 1)) ]; then
    picked+=("${files[$i]}")
  fi
done

# 빈 묶음을 통과로 두면, 파일을 못 찾은 날에도 체크가 초록으로 남는다.
if [ ${#picked[@]} -eq 0 ]; then
  echo "::error::묶음 $shard/$total 에 돌릴 테스트 파일이 없습니다(전체 ${#files[@]}개)." >&2
  exit 1
fi

echo "묶음 $shard/$total: 테스트 파일 전체 ${#files[@]}개 중 ${#picked[@]}개를 맡음"
exec "${FLUTTER:-flutter}" test "$@" "${picked[@]}"
