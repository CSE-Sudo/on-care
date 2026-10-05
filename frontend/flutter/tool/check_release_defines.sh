#!/usr/bin/env bash
# 회원 앱 스토어 릴리스 빌드의 dart-define 파일을 빌드 전에 검사한다(#3022).
#
# 앱의 컴파일 타임 기본값은 로컬 개발용이다(ENV=dev·USE_MOCK_API=true·예시 주소).
# define 하나를 빠뜨려도 `flutter build appbundle/ipa` 는 성공하므로, 개발 환경으로
# 판정된 운영 앱·목업으로 도는 앱이 그대로 스토어에 올라갈 수 있다. 앱도 기동 시
# 같은 조합을 거부하지만(AppConfig.releaseProblems), 그 전에 빌드 단계에서 멈춘다.
# 운영 웹 빌드의 .github/scripts/check_web_api_base_url.sh 와 같은 역할의 모바일판이다.
#
# 사용: bash tool/check_release_defines.sh config/release.json
#       flutter build appbundle --release --dart-define-from-file=config/release.json
#
# 규칙
#  - JSON 객체, 값은 문자열·숫자·참거짓
#  - ENV: prod 또는 staging
#  - USE_MOCK_API: false
#  - API_BASE_URL: https:// 로 시작, /v1 로 끝(끝 / 금지), 자리표시자(<…>·example·.test·localhost) 금지
#  - SENTRY_DSN: 비어 있지 않은 https:// 주소, 자리표시자 금지
#  - DEMO_BUILD·SHOW_DEMO_ENTRY 가 true 이면 실패, REAL_API 는 비어 있어야 함(목업 전용 스위치)
#  - KAKAO_NATIVE_APP_KEY: 있으면 영숫자 16~64자(카카오 네이티브 앱 키, #330)
#  - GOOGLE_WEB_CLIENT_ID·GOOGLE_IOS_CLIENT_ID: 있으면 <번호>-<해시>.apps.googleusercontent.com,
#    iOS client_id 는 웹 client_id 와 함께 있어야 함(iOS 구글 로그인이 둘 다 쓴다)
#  - 모르는 키는 경고만
set -euo pipefail

file="${1:-}"
if [ -z "$file" ]; then
  echo "사용: bash tool/check_release_defines.sh <define 파일>" >&2
  exit 2
fi
if [ ! -f "$file" ]; then
  echo "::error title=release defines::$file 이 없습니다. config/release.example.json 을 복사해 값을 채우세요." >&2
  exit 1
fi

python3 - "$file" <<'PY'
import json
import re
import sys

path = sys.argv[1]
errors: list[str] = []
warnings: list[str] = []

try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, ValueError) as exc:
    print(f"::error title=release defines::{path} 을 JSON 으로 읽지 못했습니다: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print(f"::error title=release defines::{path} 은 JSON 객체여야 합니다.", file=sys.stderr)
    sys.exit(1)

KNOWN = {"ENV", "USE_MOCK_API", "API_BASE_URL", "SENTRY_DSN", "DEMO_BUILD",
         "SHOW_DEMO_ENTRY", "REAL_API", "KAKAO_JS_KEY",
         "KAKAO_MAP_ORIGIN", "IOS_APP_STORE_ID", "KAKAO_NATIVE_APP_KEY",
         "GOOGLE_WEB_CLIENT_ID", "GOOGLE_IOS_CLIENT_ID"}
PLACEHOLDER = re.compile(
    r"[<>]|(^|[./@])example\.(com|org|net)([/:]|$)|\.(example|test|invalid|localhost)([/:]|$)"
    r"|//(localhost|127\.0\.0\.1)([/:]|$)",
    re.IGNORECASE,
)


def text(key: str) -> str | None:
    if key not in data:
        return None
    value = data[key]
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (str, int, float)):
        return str(value).strip()
    errors.append(f"{key} 값은 문자열·숫자·참거짓이어야 합니다.")
    return None


for key in data:
    if key not in KNOWN:
        warnings.append(f"알 수 없는 키 {key} — 앱이 읽지 않습니다. 오타인지 확인하세요.")

env = text("ENV")
if env is None or env == "":
    errors.append("ENV 가 없습니다. prod(스토어) 또는 staging(내부 배포)을 적으세요.")
elif env not in ("prod", "staging"):
    errors.append(f"ENV 는 prod 또는 staging 이어야 합니다(지금: {env}).")

mock = text("USE_MOCK_API")
if mock is None or mock == "":
    errors.append("USE_MOCK_API 가 없습니다. 빠지면 앱이 목업 데이터로 돕니다 — false 를 적으세요.")
elif mock.lower() != "false":
    errors.append(f"USE_MOCK_API 는 false 여야 합니다(지금: {mock}).")

url = text("API_BASE_URL")
if url is None or url == "":
    errors.append("API_BASE_URL 이 없습니다. 형식: https://<운영 API 도메인>/v1")
else:
    if not url.startswith("https://"):
        errors.append("API_BASE_URL 은 https:// 로 시작해야 합니다.")
    if not url.endswith("/v1"):
        errors.append("API_BASE_URL 은 /v1 로 끝나야 합니다(끝에 / 없이).")
    if PLACEHOLDER.search(url):
        errors.append("API_BASE_URL 이 자리표시자·예시·로컬 주소입니다.")

dsn = text("SENTRY_DSN")
if dsn is None or dsn == "":
    errors.append("SENTRY_DSN 이 없습니다. 빠지면 운영 크래시가 하나도 수집되지 않습니다.")
else:
    if not dsn.startswith("https://"):
        errors.append("SENTRY_DSN 은 https:// 주소여야 합니다.")
    if PLACEHOLDER.search(dsn):
        errors.append("SENTRY_DSN 이 자리표시자입니다.")

for flag in ("DEMO_BUILD", "SHOW_DEMO_ENTRY"):
    value = text(flag)
    if value is not None and value.lower() == "true":
        errors.append(f"{flag}=true 는 데모 빌드 전용입니다. 릴리스 파일에서 지우세요.")

map_origin = text("KAKAO_MAP_ORIGIN")
if map_origin:
    # 모바일 지도 문서의 출처(#3043). 운영 키 허용 목록에 이미 있는 운영 회원 웹 주소여야 한다.
    if not re.fullmatch(r"https://[^/\s?#]+", map_origin):
        errors.append("KAKAO_MAP_ORIGIN 은 경로 없는 https:// 출처여야 합니다(예: https://<운영 회원 웹 주소>).")
    elif PLACEHOLDER.search(map_origin):
        errors.append("KAKAO_MAP_ORIGIN 이 자리표시자·예시·로컬 주소입니다.")
store_id = text("IOS_APP_STORE_ID")
if store_id and not store_id.isdigit():
    errors.append("IOS_APP_STORE_ID 는 App Store Connect 의 숫자 Apple ID 여야 합니다(#3045).")

# 카카오·구글 로그인(#330). 비우면 그 버튼이 '준비 중'으로 남을 뿐이지만, 틀린 값은
# 버튼을 켠 채 누를 때마다 실패하게 만드므로 빌드 전에 막는다.
kakao_native = text("KAKAO_NATIVE_APP_KEY")
if kakao_native and not re.fullmatch(r"[A-Za-z0-9]{16,64}", kakao_native):
    errors.append("KAKAO_NATIVE_APP_KEY 는 카카오 콘솔의 네이티브 앱 키(영숫자)여야 합니다.")
GOOGLE_CLIENT_ID = re.compile(r"[A-Za-z0-9-]+\.apps\.googleusercontent\.com")
google_web = text("GOOGLE_WEB_CLIENT_ID")
google_ios = text("GOOGLE_IOS_CLIENT_ID")
for key, value in (("GOOGLE_WEB_CLIENT_ID", google_web), ("GOOGLE_IOS_CLIENT_ID", google_ios)):
    if value and not GOOGLE_CLIENT_ID.fullmatch(value):
        errors.append(f"{key} 는 구글 OAuth client_id(<번호>-<해시>.apps.googleusercontent.com)여야 합니다.")
if google_ios and not google_web:
    errors.append("GOOGLE_IOS_CLIENT_ID 만 있습니다. iOS 구글 로그인은 GOOGLE_WEB_CLIENT_ID 도 씁니다.")
if google_web and google_ios and google_web == google_ios:
    errors.append("GOOGLE_WEB_CLIENT_ID 와 GOOGLE_IOS_CLIENT_ID 가 같습니다. 클라이언트 유형별 값을 넣으세요.")

real_api = text("REAL_API")
if real_api:
    errors.append("REAL_API 는 목업 빌드에서 일부 기능만 실서버로 여는 스위치입니다. 릴리스 파일에서 지우세요.")

for message in warnings:
    print(f"::warning title=release defines::{message}")
for message in errors:
    print(f"::error title=release defines::{message}")
if errors:
    print(f"{path}: {len(errors)}건을 고친 뒤 다시 빌드하세요.", file=sys.stderr)
    sys.exit(1)
print(f"{path} 확인 완료 (ENV={env}).")
PY
