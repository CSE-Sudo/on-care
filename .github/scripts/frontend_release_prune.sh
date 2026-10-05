#!/usr/bin/env bash
# 운영 프론트 릴리스 정리(#3128).
#
# 릴리스는 `releases/<40자 SHA>/` 아래에 통째로 올라간다. 릴리스마다 루트 `version.txt` 가
# 있고, 열린 탭의 새 배포 감지용으로 `frontend/version.txt`·`trainer/version.txt` 도 같이
# 있다(#3023). `*/version.txt` 키를 그대로 "릴리스" 로 세면 릴리스 하나가 셋으로 세어지고,
# 보호 목록(`releases/<sha>/`)과 하위 prefix(`releases/<sha>/trainer/`)가 같은 문자열이 아니라
# 직전 릴리스의 앱 폴더가 지워진다. 그래서 여기서는 모든 키를 릴리스 루트로 정규화해
# "릴리스 하나 = 항목 하나" 로 세고, 삭제도 언제나 루트 단위로만 한다.
#
# 사용:
#   frontend_release_prune.sh plan <KEEP> <현재 SHA> [직전 OriginPath]
#       표준 입력: `<LastModified>\t<Key>` 줄(목록 조회의 text 출력 그대로)
#       표준 출력: 지울 릴리스 루트 prefix(`releases/<sha>/`) 를 한 줄씩
#   frontend_release_prune.sh prune <버킷> <KEEP> <현재 SHA> [직전 OriginPath]
#       버킷의 `releases/` 를 조회해 plan 결과를 지운다.
#
# 규칙
#   * 최신 KEEP 개 릴리스(루트 기준 가장 늦은 version.txt 시각)는 남긴다.
#   * 지금 서비스 중인 릴리스와 되돌아갈 직전 릴리스는 순번과 상관없이 남긴다.
#   * `releases/<40자 SHA>/` 형식이 아닌 키는 세지도 지우지도 않는다.
#
# AWS_CLI 로 aws 명령을 바꿀 수 있다(검사 스크립트가 가짜 명령을 넣는다).
set -euo pipefail

AWS_CLI="${AWS_CLI:-aws}"
ROOT_PREFIX_LEN=50 # "releases/"(9) + SHA(40) + "/"(1)

usage() {
  echo "usage: $0 plan <keep> <current-sha> [previous-origin-path] < listing" >&2
  echo "       $0 prune <bucket> <keep> <current-sha> [previous-origin-path]" >&2
  exit 2
}

# OriginPath(`/releases/<sha>`) 를 비교용 루트 prefix(`releases/<sha>/`) 로 바꾼다.
# 빈 값(버킷 루트)이나 릴리스 형식이 아닌 값은 빈 문자열이 된다.
origin_root() {
  local path="${1#/}"
  path="${path%/}"
  if [[ "$path" =~ ^releases/[0-9a-f]{40}$ ]]; then
    printf '%s/' "$path"
  fi
}

plan() {
  local keep="${1:-}" current="${2:-}" previous="${3:-}"
  if ! [[ "$keep" =~ ^[1-9][0-9]*$ ]] || ! [[ "$current" =~ ^[0-9a-f]{40}$ ]]; then
    usage
  fi
  local current_root="releases/$current/"
  local previous_root
  previous_root=$(origin_root "$previous")
  if [ -n "$previous" ] && [ -z "$previous_root" ]; then
    echo "::warning::직전 OriginPath '$previous' 가 릴리스 형식이 아니어서 보호 목록에 넣지 않습니다." >&2
  fi

  # 1) 릴리스 안의 version.txt 만 남긴다(루트·앱 폴더 어느 쪽이든).
  # 2) 키를 릴리스 루트로 줄이고, 루트마다 가장 늦은 시각 하나만 남긴다.
  # 3) 시각 내림차순(같으면 이름순)으로 줄 세운다.
  local roots
  roots=$(
    { grep -E $'^[^\t]+\treleases/[0-9a-f]{40}/([^\t]*/)?version\\.txt$' || true; } \
      | awk -F'\t' -v len="$ROOT_PREFIX_LEN" '
          {
            root = substr($2, 1, len)
            if (!(root in latest) || $1 > latest[root]) latest[root] = $1
          }
          END { for (root in latest) printf "%s\t%s\n", latest[root], root }
        ' \
      | sort -t $'\t' -k1,1r -k2,2 \
      | cut -f2
  )

  local index=0 root
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    index=$((index + 1))
    if [ "$root" = "$current_root" ] || [ "$root" = "$previous_root" ]; then
      continue
    fi
    if [ "$index" -le "$keep" ]; then
      continue
    fi
    printf '%s\n' "$root"
  done <<< "$roots"
}

prune() {
  local bucket="${1:-}"
  [ -n "$bucket" ] || usage
  shift
  local listing targets root
  listing=$("$AWS_CLI" s3api list-objects-v2 --bucket "$bucket" --prefix 'releases/' \
    --query "Contents[?ends_with(Key, '/version.txt')].[LastModified, Key]" \
    --output text)
  targets=$(printf '%s\n' "$listing" | plan "$@")
  if [ -z "$targets" ]; then
    echo "지울 릴리스가 없습니다."
    return 0
  fi
  while IFS= read -r root; do
    # plan 은 루트 형식만 내보내지만, 지우기 직전에 한 번 더 막는다.
    if ! [[ "$root" =~ ^releases/[0-9a-f]{40}/$ ]]; then
      echo "::error::릴리스 루트가 아닌 prefix 는 지우지 않습니다: $root" >&2
      return 1
    fi
    echo "오래된 릴리스 삭제: $root"
    "$AWS_CLI" s3 rm "s3://$bucket/$root" --recursive > /dev/null
  done <<< "$targets"
}

command="${1:-}"
[ -n "$command" ] || usage
shift
case "$command" in
  plan) plan "$@" ;;
  prune) prune "$@" ;;
  *) usage ;;
esac
