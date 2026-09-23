# RAG (pgvector + Gemini) 로컬 셋업 · 재현 가이드

이슈 #155 결과물. 공공문서 **적재 → pgvector 검색 → 근거 코칭**까지 로컬에서 재현하는 절차.
임베딩 제공자는 **Gemini `gemini-embedding-001`(768차원)**, 코치/인식은 **`gemini-flash-latest`**.

## 0. 전제
- PostgreSQL 14+ (+ `pgvector` 확장), Python 3.11+
- 결제된 `GEMINI_API_KEY`

## 1. 의존성
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r backend/requirements.txt        # 실행
pip install -r backend/requirements-dev.txt     # 테스트까지
```

## 2. `.env` (반드시 `backend/.env` — config 의 env_file 이 cwd=backend 기준)
```
DATABASE_URL=postgresql+psycopg://oncare:oncare@localhost:5432/oncare
GEMINI_API_KEY=<발급받은 키>
RECOGNIZER=gemini
COACH_LLM=gemini
EMBEDDER=gemini
EMBED_DIM=768            # ★ Gemini gemini-embedding-001 = 768 (1536 아님)
```
키가 없으면 임베더/코치는 **hash·규칙 폴백**, 인식은 **stub** 으로 자동 폴백(개발/CI 동작).

## 3. DB 준비
```bash
# 역할·DB (슈퍼유저로 1회)
psql -d postgres -c "CREATE ROLE oncare LOGIN PASSWORD 'oncare' CREATEDB;"
psql -d postgres -c "CREATE DATABASE oncare OWNER oncare;"
psql -d oncare  -c "CREATE EXTENSION IF NOT EXISTS vector; GRANT ALL ON SCHEMA public TO oncare;"
```
스키마 생성은 둘 중 하나:
- **개발**: `AUTO_CREATE_TABLES=true`(기본) → 기동 시 `create_all` 이 모델 기준 `Vector(EMBED_DIM=768)` 로 생성
- **운영**: `cd backend && alembic upgrade head` → `0007_coach_embedding_768` 이 벡터 컬럼을 768 로 생성/전환

> **기존 DB가 1536 이면**: `alembic upgrade head`(컬럼 768 로 재생성) 후 `python -m scripts.reembed`(기존 문서 재임베딩). `create_all` 은 이미 있는 컬럼 차원을 바꾸지 않으므로, 예전 1536 테이블은 drop 후 재기동하거나 alembic 을 쓴다.

## 4. 기동 + 공공 가이드 시드(자동)
```bash
cd backend && uvicorn app.main:app --reload
```
기동 시 `init_db` 가 공개 근거 문서(`app/data/coach_public_docs.py` 의 목록, 본문은 `app/data/coach_docs/*.txt`)를 **Gemini 임베딩(768)** 으로 시드합니다. 목록의 지문이 `reference_data_versions` 에 남아, 문서가 그대로면 다시 임베딩하지 않고 바뀌면 시드가 넣은 문서를 통째로 갈아 끼웁니다(#1652).

근거 문서는 한국인을 위한 신체활동 지침서(2023 개정판, 보건복지부)와 2025 한국인 영양소 섭취기준(보건복지부/한국영양학회)의 원문 발췌입니다. 원본 PDF 에서 다시 뽑으려면 `python -m scripts.extract_coach_docs` 를 돌립니다(받는 경로는 그 스크립트의 머리말에 적혀 있습니다).

## 5. 공공문서 추가 적재 (선택)
시드 목록에 없는 공식 출처 텍스트를 `.txt` 로 준비 후:
```bash
python -m scripts.ingest_public docs/public_guidelines/sodium_dash_sample.txt \
  --domain diet --title "저염·DASH 식단 가이드"
```
이렇게 넣은 문서는 `source` 가 달라(`public`) 시드 재적재가 지우지 않습니다.
샘플 템플릿: [`docs/public_guidelines/sodium_dash_sample.txt`](public_guidelines/sodium_dash_sample.txt) (공식 텍스트로 교체용).

## 6. 임베딩 모델/차원 변경 시
`EMBED_DIM` 이나 임베딩 모델을 바꾸면 컬럼 재생성(alembic) 후 재임베딩:
```bash
python -m scripts.reembed        # 기존 content 유지, embedding 만 재계산
```

## 7. 검증
```bash
# (a) Gemini 실동작(챗·임베딩[·인식])
python -m scripts.check_gemini [food.jpg]

# (b) 벡터가 실제 768 로 적재됐는지
psql "$DATABASE_URL_PSQL" -c \
  "select count(*), vector_dims(embedding) from coach_documents where embedding is not null group by 2;"

# (c) 코치가 폴백 아닌 RAG 근거 답변(sources) 반환
curl -s localhost:8000/v1/ai-coach/chat -H 'content-type: application/json' \
  -d '{"message":"나트륨을 줄이려면 어떻게 하나요?"}' | jq '{reply, sources}'
#   → sources 가 채워지면 pgvector 검색이 실제로 동작(규칙 폴백 아님)

# (d) 전체 회귀
cd backend && pytest -q     # 개인문서 격리·공공 검색 포함 (인식 테스트는 stub 고정)
```

## 부록 A. Gemini 모델명 주의 (은퇴 대응)
핀 버전은 은퇴하면 404 가 난다. 확인된 동작 모델:
- 챗·인식: **`gemini-flash-latest`** (`gemini-2.0-flash`·`gemini-2.5-flash` 는 404 사례 있음)
- 임베딩: **`gemini-embedding-001`** + `output_dimensionality=768` (기본 3072 → 768 로 축소, rag 는 cosine 거리라 정규화 불필요)
사용 가능 모델은 `client.models.list()` 로 확인.

## 부록 B. macOS 에서 pgvector 를 PostgreSQL 16 에 설치
Homebrew `pgvector` bottle 이 pg17/18 파일만 담는 경우 pg16 엔 확장이 없다. 소스 빌드:
```bash
git clone --branch v0.8.5 https://github.com/pgvector/pgvector.git && cd pgvector
PGC=/usr/local/opt/postgresql@16/bin/pg_config
SDK="$(xcrun --show-sdk-path)"
# pg_config 가 없어진 MacOSX14.sdk 를 참조하는 경우 현재 SDK 로 치환
make PG_CONFIG="$PGC" \
  CPPFLAGS="$("$PGC" --cppflags | sed "s|MacOSX14.sdk|$(basename "$SDK")|")" \
  LDFLAGS="$("$PGC" --ldflags  | sed "s|MacOSX14.sdk|$(basename "$SDK")|")"
make install PG_CONFIG="$PGC"
```
