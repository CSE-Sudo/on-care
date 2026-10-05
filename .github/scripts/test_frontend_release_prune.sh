#!/usr/bin/env bash
# frontend_release_prune.sh 의 릴리스 세기·보호·삭제 단위 검사(#3128).
# 사용: bash .github/scripts/test_frontend_release_prune.sh
# 실제 aws 를 부르지 않는다 — 가짜 키 목록을 넣고, prune 은 AWS_CLI 에 가짜 명령을 넣는다.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/frontend_release_prune.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

check() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label -> '$got' (기대: '$want')"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> '$got'"
  fi
}

# 40자 SHA 를 만든다: sha 1 → 1111…(40자)
sha() { printf "%040d" 0 | tr 0 "$1"; }

# 릴리스 하나의 version.txt 세 키(루트·회원 앱·트레이너 웹). 앱 폴더 파일은 몇 초 늦게 올라간다.
release_keys() {
  local stamp="$1" id="$2"
  printf '%s:00+00:00\treleases/%s/version.txt\n' "$stamp" "$id"
  printf '%s:05+00:00\treleases/%s/frontend/version.txt\n' "$stamp" "$id"
  printf '%s:07+00:00\treleases/%s/trainer/version.txt\n' "$stamp" "$id"
}

# 7개 릴리스: 1 이 가장 오래되고 7 이 가장 새롭다. 목록 순서는 일부러 섞는다.
seven_releases() {
  release_keys 2026-10-03T10:00 "$(sha 3)"
  release_keys 2026-10-01T10:00 "$(sha 1)"
  release_keys 2026-10-07T10:00 "$(sha 7)"
  release_keys 2026-10-05T10:00 "$(sha 5)"
  release_keys 2026-10-02T10:00 "$(sha 2)"
  release_keys 2026-10-06T10:00 "$(sha 6)"
  release_keys 2026-10-04T10:00 "$(sha 4)"
}

plan() { bash "$script" plan "$@" 2> /dev/null | tr '\n' ' ' | sed 's/ $//'; }

# --- 릴리스 단위로 센다: 7개면 오래된 2개 루트만
got=$(seven_releases | plan 5 "$(sha 7)" "/releases/$(sha 6)")
check "7개 중 오래된 2개" "releases/$(sha 2)/ releases/$(sha 1)/" "$got"

# --- 앱 폴더 version.txt 가 함께 있어도 하나로 센다: 5개 이하면 지울 것이 없다
got=$(seven_releases | grep -v "$(sha 1)\|$(sha 2)" | plan 5 "$(sha 7)" "/releases/$(sha 6)")
check "5개는 그대로" "" "$got"

# --- 삭제 대상은 모두 루트 prefix 다(하위 폴더만 따로 오르지 않는다)
got=$(seven_releases | plan 1 "$(sha 7)" "/releases/$(sha 6)" \
  | tr ' ' '\n' | grep -cvE '^releases/[0-9a-f]{40}/$')
check "루트가 아닌 삭제 대상 수" "0" "$got"
got=$(seven_releases | plan 1 "$(sha 7)" "/releases/$(sha 6)" | tr ' ' '\n' | grep -c .)
check "KEEP=1 삭제 대상 수(현재·직전 제외 5개)" "5" "$got"

# --- 현재·직전 릴리스는 어떤 하위 prefix 도 오르지 않는다(KEEP 을 넘어선 오래된 직전 릴리스 포함)
got=$(seven_releases | plan 1 "$(sha 7)" "/releases/$(sha 1)")
case " $got " in
  *"releases/$(sha 7)/"* | *"releases/$(sha 1)/"*) check "현재·직전 보호" "보호" "삭제 대상: $got" ;;
  *) check "현재·직전 보호" "보호" "보호" ;;
esac
check "롤백 뒤(직전이 오래된 릴리스) 정리" \
  "releases/$(sha 6)/ releases/$(sha 5)/ releases/$(sha 4)/ releases/$(sha 3)/ releases/$(sha 2)/" "$got"

# --- 현재 릴리스가 목록상 가장 새롭지 않아도(시각이 어긋나도) 지우지 않는다
got=$(seven_releases | plan 2 "$(sha 1)" "/releases/$(sha 2)")
check "오래된 현재·직전 보호" \
  "releases/$(sha 5)/ releases/$(sha 4)/ releases/$(sha 3)/" "$got"

# --- 직전 OriginPath 는 끝 슬래시가 있어도 같은 릴리스로 본다
got=$(seven_releases | plan 1 "$(sha 7)" "/releases/$(sha 6)/" | tr ' ' '\n' | grep -c "$(sha 6)")
check "끝 슬래시 직전 경로 보호" "0" "$got"

# --- 직전 OriginPath 가 비었으면(첫 배포·버킷 루트) 현재만 보호한다
got=$(seven_releases | plan 5 "$(sha 7)" "")
check "직전 없음" "releases/$(sha 2)/ releases/$(sha 1)/" "$got"

# --- 이미 앱 폴더가 지워진 반쪽 릴리스도 루트 단위로 센다
half=$(
  seven_releases | grep -v "$(sha 1)/frontend\|$(sha 1)/trainer"
  # 루트 version.txt 가 없고 앱 폴더만 남은 릴리스
  printf '2026-09-30T10:00:05+00:00\treleases/%s/trainer/version.txt\n' "$(sha 9)"
)
got=$(printf '%s\n' "$half" | plan 5 "$(sha 7)" "/releases/$(sha 6)")
check "반쪽 릴리스" "releases/$(sha 2)/ releases/$(sha 1)/ releases/$(sha 9)/" "$got"

# --- 릴리스 형식이 아닌 키·빈 목록은 무시한다
got=$(
  {
    printf '2026-09-01T00:00:00+00:00\treleases/version.txt\n'
    printf '2026-09-01T00:00:00+00:00\treleases/abc/version.txt\n'
    printf '2026-09-01T00:00:00+00:00\treleases/%s/notes.txt\n' "$(sha 8)"
    printf 'None\n'
  } | plan 1 "$(sha 7)" ""
)
check "형식 밖 키 무시" "" "$got"
got=$(printf 'None\n' | plan 5 "$(sha 7)" "")
check "빈 목록" "" "$got"

# --- 잘못된 인자
for args in "plan 0 $(sha 7)" "plan x $(sha 7)" "plan 5 abc" "plan 5" "nope" ""; do
  # shellcheck disable=SC2086
  if bash "$script" $args < /dev/null > /dev/null 2>&1; then
    check "잘못된 인자 '$args'" "fail" "pass"
  else
    check "잘못된 인자 '$args'" "fail" "fail"
  fi
done

# --- prune: 가짜 aws 로 조회 인자와 삭제 호출을 본다
fake="$work/aws"
cat > "$fake" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "CALL $*" >> "$FAKE_LOG"
if [ "$1" = "s3api" ] && [ "$2" = "list-objects-v2" ]; then
  cat "$FAKE_LISTING"
fi
FAKE
chmod +x "$fake"
export AWS_CLI="$fake" FAKE_LOG="$work/log" FAKE_LISTING="$work/listing"

seven_releases > "$FAKE_LISTING"
: > "$FAKE_LOG"
bash "$script" prune bucket 5 "$(sha 7)" "/releases/$(sha 6)" > /dev/null
list_line=$(sed -n 1p "$FAKE_LOG")
case "$list_line" in
  "CALL s3api list-objects-v2 --bucket bucket --prefix releases/ --query "*"[LastModified, Key]"*)
    check "조회 인자" "ok" "ok" ;;
  *) check "조회 인자" "ok" "$list_line" ;;
esac
rm_lines=$(grep '^CALL s3 rm ' "$FAKE_LOG" | tr '\n' '|')
check "삭제 호출" \
  "CALL s3 rm s3://bucket/releases/$(sha 2)/ --recursive|CALL s3 rm s3://bucket/releases/$(sha 1)/ --recursive|" \
  "$rm_lines"

# 지울 것이 없으면 rm 을 부르지 않는다
seven_releases | grep -v "$(sha 1)\|$(sha 2)" > "$FAKE_LISTING"
: > "$FAKE_LOG"
bash "$script" prune bucket 5 "$(sha 7)" "/releases/$(sha 6)" > /dev/null
check "지울 것 없음" "0" "$(grep -c '^CALL s3 rm ' "$FAKE_LOG")"

# 잘못된 인자면 아무것도 지우지 않고 실패한다
seven_releases > "$FAKE_LISTING"
: > "$FAKE_LOG"
if bash "$script" prune bucket 0 "$(sha 7)" "" > /dev/null 2>&1; then
  check "prune 잘못된 KEEP" "fail" "pass"
else
  check "prune 잘못된 KEEP" "fail" "fail"
fi
check "prune 잘못된 KEEP 삭제 없음" "0" "$(grep -c '^CALL s3 rm ' "$FAKE_LOG")"

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "모두 통과"
