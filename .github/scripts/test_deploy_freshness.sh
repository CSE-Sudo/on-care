#!/usr/bin/env bash
# deploy_freshness.sh 판정 검사(#3254).
# 임시 git 저장소에 커밋을 만들고, 가짜 curl 이 FAKE_BODY 를 /version 응답으로, 가짜 aws 가
# FAKE_BODY 를 CloudFront 배포 설정으로 돌려준다.
# 사용: bash .github/scripts/test_deploy_freshness.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/deploy_freshness.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

mkdir -p "$work/bin"
for name in curl aws; do
  cat > "$work/bin/$name" <<'FAKE'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$FAKE_CALLS"
if [ "${FAKE_FAIL:-}" = 1 ]; then
  echo "$(basename "$0"): 요청 실패" >&2
  exit 22
fi
printf '%s' "$FAKE_BODY"
FAKE
  chmod +x "$work/bin/$name"
done

repo="$work/repo"
git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.com "$@"; }
commit() { printf '%s\n' "$2" >> "$repo/$1"; g add -A; g commit -q -m "$2"; g rev-parse HEAD; }

c1=$(commit a.txt one)
c2=$(commit a.txt two)
c3=$(commit a.txt three)
g checkout -q -b side "$c1"
c_side=$(commit b.txt side)
g checkout -q main

version() { printf '{"api_version":"v1","app_version":"0.1.0","commit_sha":"%s"}' "$1"; }
# 기본 동작이 가리키는 origin(app)의 path 가 서비스 중인 릴리스다. 다른 origin 은 미끼다.
distribution() {
  printf '{"ETag":"E1","DistributionConfig":{"DefaultCacheBehavior":{"TargetOriginId":"app"},'
  printf '"Origins":{"Quantity":2,"Items":[{"Id":"other","OriginPath":"/releases/%s"},' "$c3"
  printf '{"Id":"app","OriginPath":"%s"}]}}}' "$1"
}

# expect <기대 코드> <설명> <모드> <응답 본문> <대상 SHA> [기대 state] [FAKE_FAIL]
expect() {
  local want="$1" label="$2" mode="$3" resp="$4" target="$5" state="${6:-}" fail="${7:-}" source got
  case "$mode" in
    frontend) source=E2EXAMPLE ;;
    backend) source=https://api.oncare.test/v1/ ;;
    *) source=x ;;
  esac
  : > "$work/calls"
  (cd "$repo" && FAKE_CALLS="$work/calls" FAKE_BODY="$resp" FAKE_FAIL="$fail" PATH="$work/bin:$PATH" \
    bash "$tool" "$mode" "$source" "$target") > "$work/out" 2>&1
  got=$?
  if [ "$got" != "$want" ] || { [ -n "$state" ] && ! grep -qx "state=$state" "$work/out"; }; then
    echo "FAIL: $label -> $got (기대: $want ${state})"
    sed 's/^/    /' "$work/out"
    failures=$((failures + 1))
  else
    echo "ok:   $label -> $got ${state}"
  fi
}

# --- 백엔드: /version 의 commit_sha
expect 0  '백엔드: 대상이 더 새 커밋'          backend "$(version "$c2")" "$c3" newer
expect 20 '백엔드: 같은 커밋'                   backend "$(version "$c3")" "$c3" same
expect 20 '백엔드: 대상이 운영의 조상(옛 커밋)' backend "$(version "$c3")" "$c1" older
expect 20 '백엔드: 대문자 SHA 도 같은 커밋'     backend "$(version "$(printf '%s' "$c2" | tr '[:lower:]' '[:upper:]')")" "$c2" same
expect 0  '백엔드: 응답 없음 → 경고만'           backend '' "$c1" unknown 1
expect 0  '백엔드: commit_sha 없음'              backend '{"api_version":"v1"}' "$c1" unknown
expect 0  '백엔드: commit_sha 가 unknown'        backend '{"commit_sha":"unknown"}' "$c1" unknown
expect 0  '백엔드: JSON 이 아님'                 backend '<html>bad gateway</html>' "$c1" unknown
expect 0  '백엔드: 저장소에 없는 운영 커밋'      backend "$(version 1111111111111111111111111111111111111111)" "$c1" not-found
expect 0  '백엔드: 이력이 갈라짐'                backend "$(version "$c_side")" "$c3" diverged

# --- 프런트: CloudFront origin path(/releases/<SHA>)
expect 0  '프런트: 대상이 더 새 커밋'           frontend "$(distribution "/releases/$c1")" "$c2" newer
expect 20 '프런트: 같은 커밋'                    frontend "$(distribution "/releases/$c2")" "$c2" same
expect 20 '프런트: 대상이 운영의 조상(옛 커밋)'  frontend "$(distribution "/releases/$c2")" "$c1" older
expect 0  '프런트: 첫 배포(origin path 비어 있음)' frontend "$(distribution '')" "$c1" unknown
expect 0  '프런트: 릴리스 경로가 아님'           frontend "$(distribution '/legacy')" "$c1" unknown
expect 0  '프런트: 배포 설정 조회 실패'          frontend '' "$c1" unknown 1
expect 0  '프런트: 설정 JSON 이 깨짐'            frontend '{"DistributionConfig":{}}' "$c1" unknown

# --- 사용 오류
expect 1  '모드 오류'                            nope "$(version "$c1")" "$c2"
expect 1  '대상 SHA 형식 오류'                   backend "$(version "$c1")" abc
expect 1  '저장소에 없는 대상'                   backend "$(version "$c1")" 2222222222222222222222222222222222222222

# 읽을 곳이 비어 있으면(변수 미설정) 요청 없이 경고만 남기고 배포한다.
: > "$work/calls"
(cd "$repo" && FAKE_CALLS="$work/calls" PATH="$work/bin:$PATH" bash "$tool" backend '' "$c1") > "$work/out" 2>&1
got=$?
if [ "$got" = 0 ] && grep -qx 'state=unknown' "$work/out" && [ ! -s "$work/calls" ]; then
  echo "ok:   읽을 곳이 비어 있음 -> 0 unknown(요청 없음)"
else
  echo "FAIL: 읽을 곳이 비어 있음 -> $got"; sed 's/^/    /' "$work/out" "$work/calls"; failures=$((failures + 1))
fi

# 요청 주소: 백엔드는 끝 / 를 정리한 /v1/version, 프런트는 받은 배포 ID 의 설정.
expect 0 '백엔드 요청 주소 확인용' backend "$(version "$c1")" "$c2" newer
if grep -qx 'curl --fail --silent --show-error --max-time 15 https://api.oncare.test/v1/version' "$work/calls"; then
  echo "ok:   /v1/version 주소(끝 / 정리)"
else
  echo "FAIL: 백엔드 요청 주소"; sed 's/^/    /' "$work/calls"; failures=$((failures + 1))
fi
expect 0 '프런트 요청 확인용' frontend "$(distribution "/releases/$c1")" "$c2" newer
if grep -qx 'aws cloudfront get-distribution-config --id E2EXAMPLE' "$work/calls"; then
  echo "ok:   CloudFront 배포 설정 조회"
else
  echo "FAIL: 프런트 요청"; sed 's/^/    /' "$work/calls"; failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures 건 실패"
  exit 1
fi
echo "deploy_freshness.sh 검사 통과"
