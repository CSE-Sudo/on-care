#!/usr/bin/env bash
# 운영 컨테이너 기동 엔트리포인트.
# 1) 스키마를 Alembic head 까지 마이그레이션(운영은 AUTO_CREATE_TABLES=false 권장 →
#    Alembic 이 유일한 스키마 소스). 2) uvicorn 시작.
# 로드 밸런서(프록시) 뒤이므로 --proxy-headers 로 X-Forwarded-Proto 를 신뢰(HTTPS 판정).
set -euo pipefail

# ENV 는 반드시 명시한다(#2821). 백엔드의 운영 안전장치(JWT·CORS·데모 비밀번호 검사,
# 데모 폴백 차단)는 ENV=prod 일 때만 켜지는데, 값을 빠뜨리면 설정 기본값(dev)으로
# 조용히 떠서 그 장치가 전부 꺼진다. 컨테이너는 값이 없으면 아예 뜨지 않는다.
# 로컬 개발은 uvicorn 을 직접 띄우므로 이 검사를 거치지 않는다.
ENV_TRIMMED="$(printf '%s' "${ENV:-}" | tr -d '[:space:]')"
if [[ -z "${ENV_TRIMMED}" ]]; then
  echo "[start] ENV 가 비어 있습니다 — 배포 환경에서는 ENV=prod(또는 staging) 를 명시해야 합니다." >&2
  exit 1
fi
echo "[start] ENV=${ENV_TRIMMED}"

# 포트: Railway 등 일부 플랫폼은 동적 $PORT 를 주입한다. 없거나 비어 있으면
# (ECS·로컬·docker-compose) 8000 으로 폴백 → 한 이미지가 두 플랫폼 모두에서
# 그대로 뜬다. 검증은 마이그레이션보다 먼저 한다 — DB 가 unavailable 할 때 포트
# 오류가 마이그레이션 오류에 가려지지 않고 "명확한 포트 검증"이 먼저 작동하도록.
PORT="${PORT:-8000}"
# 잘못 주입된 $PORT(비숫자·범위 밖)를 그대로 uvicorn 에 넘기면 불명확한 오류로
# 기동에 실패하므로, 여기서 1~65535 정수인지 검증하고 아니면 명확히 종료한다.
if ! [[ "${PORT}" =~ ^[0-9]+$ ]]; then
  echo "[start] invalid PORT='${PORT}' — 1~65535 범위의 정수여야 합니다." >&2
  exit 1
fi
# 10진수로 정규화 — '08000' 같은 leading-zero 입력을 Bash 산술이 8진수로 오해해
# 범위 검사가 어긋나는 것을 막고, 정규화된 값만 uvicorn 에 넘긴다.
PORT=$((10#$PORT))
if (( PORT < 1 || PORT > 65535 )); then
  echo "[start] invalid PORT='${PORT}' — 1~65535 범위의 정수여야 합니다." >&2
  exit 1
fi

# 워커 수(#2835). 기본 1 — 인메모리 rate limiter·메트릭은 워커마다 따로 세므로
# 늘리면 분당 한도가 사실상 워커 수만큼 느슨해지고 /system/metrics 는 요청을 받은
# 워커 하나의 값만 보여 준다(하루 상한처럼 DB 에서 세는 값은 영향 없음). DB 연결
# 상한도 워커 수만큼 곱해진다 — 계산법은 docs/DEPLOY.md. 값은 배포 설정에서 정한다.
WEB_CONCURRENCY="${WEB_CONCURRENCY:-1}"
if ! [[ "${WEB_CONCURRENCY}" =~ ^[0-9]+$ ]] || (( 10#$WEB_CONCURRENCY < 1 )); then
  echo "[start] invalid WEB_CONCURRENCY='${WEB_CONCURRENCY}' — 1 이상의 정수여야 합니다." >&2
  exit 1
fi
WEB_CONCURRENCY=$((10#$WEB_CONCURRENCY))

echo "[start] migrate (advisory-lock serialized)"
python scripts/migrate.py

# 프록시 헤더를 믿을 앞단 주소(#2815). uvicorn 은 여기 든 주소에서 온 요청의
# X-Forwarded-Proto(HTTPS 판정)와 X-Forwarded-For 를 받아들인다. 관리형 ALB 처럼
# 프록시 주소 대역이 고정되지 않은 플랫폼은 좁힐 수 없어 기본값을 "*" 로 둔다 —
# 그래도 안전한 이유는 rate limit·감사 로그가 이 값으로 고쳐진 소켓 주소가 아니라
# app/core/client_ip.py 가 X-Forwarded-For 를 오른쪽에서 TRUSTED_PROXY_HOPS 번째로
# 읽은 값을 쓰기 때문이다. 프록시 대역이 고정된 환경은 그 대역으로 좁힌다.
FORWARDED_ALLOW_IPS="${FORWARDED_ALLOW_IPS:-*}"

echo "[start] launching uvicorn on :${PORT} (workers=${WEB_CONCURRENCY})"
exec uvicorn app.main:app \
  --host 0.0.0.0 --port "${PORT}" \
  --workers "${WEB_CONCURRENCY}" \
  --proxy-headers --forwarded-allow-ips="${FORWARDED_ALLOW_IPS}"
