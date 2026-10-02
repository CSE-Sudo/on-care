# 파이썬 버전의 기준은 backend/.python-version 이다(#2837). Dockerfile 은 그 파일을
# 읽을 수 없어 기본값을 같은 값으로 적어 두고, 백엔드 CI 가 둘이 같은지 검사한다.
# CI 의 테스트·이미지 빌드도 같은 파일에서 버전을 읽는다.
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim
WORKDIR /code

# 로그 타임스탬프를 KST 로 맞춘다. 도메인 날짜 계산은 여기에 기대지 않는다 —
# 기준 시각은 app/core/clock.py 가 ZoneInfo 로 직접 고정한다(#557).
ENV TZ=Asia/Seoul

# psycopg[binary] 휠이 libpq 를 번들하므로 apt 빌드 툴체인(build-essential/libpq-dev)이
# 불필요하다 — 이미지에서 수백 MB 를 덜어낸다. (소스 빌드로 바꾸면 psycopg[c] + libpq-dev 필요)
#
# requirements.txt 는 requirements.in 에서 만든 잠금 파일이다(버전·해시 고정, #2837).
# --require-hashes 로 잠금 파일에 없는 패키지나 다른 내용의 파일이 끼면 빌드를 멈춘다 —
# 같은 커밋을 다시 빌드하면 같은 의존성이 깔린다.
COPY requirements.txt .
RUN pip install --no-cache-dir --require-hashes -r requirements.txt

# 앱 + 마이그레이션 자산(운영은 Alembic 이 스키마의 정답이므로 반드시 포함).
COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./alembic.ini
COPY scripts ./scripts
RUN chmod +x scripts/start.sh

# 비루트 유저로 실행 (컨테이너 탈출 시 피해 범위 축소)
RUN useradd --create-home --uid 10001 appuser && chown -R appuser:appuser /code
USER appuser

EXPOSE 8000
# 기동: alembic upgrade head 후 uvicorn(프록시 뒤이므로 --proxy-headers).
CMD ["scripts/start.sh"]
