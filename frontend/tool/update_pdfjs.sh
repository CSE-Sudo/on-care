#!/usr/bin/env bash
# 두 웹(회원 앱·트레이너 웹)이 싣는 pdf.js 를 같은 버전으로 바꾼다. (#2818)
#
#   frontend/tool/update_pdfjs.sh 4.10.38
#
# npm 레지스트리의 공식 `pdfjs-dist` 꾸러미를 받아 레지스트리가 알려 준 무결성 값과
# 맞는지 확인한 뒤, **레거시 빌드**(오래된 사파리용 폴리필 포함)의 본체·워커를 두 앱의
# `web/pdfjs/` 에 같은 이름(`pdf.min.js`·`pdf.worker.min.js`)으로 넣는다. 확장자를
# `.js` 로 바꾸는 이유는 `web/js/pdfjs_loader.js` 주석에 있다.
#
# 함께 바꾸는 것:
#   * 두 앱 `web/pdfjs/bundle.txt` — 버전과 두 파일의 sha256
#   * 두 앱 `web/js/pdfjs_loader.js` 의 `PDFJS_VERSION` 상수
#
# 두 사본·상수·bundle.txt 가 서로 어긋나거나 버전이 CVE-2024-4367 수정판(4.2.67)보다
# 낮으면 두 앱의 `test/web/pdfjs_bundle_test.dart` 가 실패한다.
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
  echo "사용법: $0 <pdfjs-dist 버전>" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

expected="$(npm view "pdfjs-dist@${version}" dist.integrity)"
(cd "$work" && npm pack "pdfjs-dist@${version}" --silent >/dev/null)
tarball="$work/pdfjs-dist-${version}.tgz"
actual="sha512-$(openssl dgst -sha512 -binary "$tarball" | openssl base64 -A)"
if [[ "$expected" != "$actual" ]]; then
  echo "무결성 값이 레지스트리와 다릅니다: $actual != $expected" >&2
  exit 1
fi
tar -xzf "$tarball" -C "$work"
build="$work/package/legacy/build"

for app in flutter flutter_trainer; do
  dest="$root/$app/web/pdfjs"
  mkdir -p "$dest"
  cp "$build/pdf.min.mjs" "$dest/pdf.min.js"
  cp "$build/pdf.worker.min.mjs" "$dest/pdf.worker.min.js"
  {
    echo "version=${version}"
    echo "source=pdfjs-dist@${version} legacy/build"
    echo "integrity=${expected}"
    echo "pdf.min.js=$(shasum -a 256 "$dest/pdf.min.js" | cut -d' ' -f1)"
    echo "pdf.worker.min.js=$(shasum -a 256 "$dest/pdf.worker.min.js" | cut -d' ' -f1)"
  } > "$dest/bundle.txt"
  # 로더의 버전 상수(캐시 무효화용 `?v=`)도 함께 맞춘다.
  sed -i.bak -E "s/const PDFJS_VERSION = \"[^\"]+\";/const PDFJS_VERSION = \"${version}\";/" \
    "$root/$app/web/js/pdfjs_loader.js"
  rm -f "$root/$app/web/js/pdfjs_loader.js.bak"
  echo "$app: pdf.js ${version}"
done
