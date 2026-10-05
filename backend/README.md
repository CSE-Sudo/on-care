# On-Care Backend

> 회원 앱(`frontend/flutter`)과 트레이너 웹(`frontend/flutter_trainer`)이 함께 쓰는 FastAPI 백엔드입니다.
> 엔드포인트 계약은 [`API_CONTRACT.md`](API_CONTRACT.md)(이 문서가 기준이고 두 앱의 목업이 따라감),
> 회원↔트레이너 공유 규칙은 [`docs/TRAINER_DOMAIN.md`](docs/TRAINER_DOMAIN.md), 배포는
> [`docs/DEPLOY.md`](docs/DEPLOY.md) 를 봅니다.

## 현재 상태
- 모든 경로는 `/v1` prefix, JSON 은 snake_case, 사용자 id 는 문자열(데모 유저 `user-7d4e9a2c5f18`).
- 라우터 목록은 `app/main.py` 의 `include_router` 가 기준입니다 — 인증·사용자, 대시보드, 식단, 운동,
  알림, 장소·헬스장·트레이너 디렉터리, 예약·상담, 트레이너 도메인과 회원측 코치 미러, 채팅 첨부,
  AI 코치(RAG + 규칙 기반 폴백), 포인트·챌린지·보호권, 기록 그래프.
- 시스템: `GET /v1/ping` · `GET /v1/healthz` · `GET /v1/version`, DB 연결까지 보는 readiness `GET /v1/readyz`.
- 테이블 목록은 `app/models/models.py` 와 마이그레이션(`migrations/versions/`)이 기준입니다. 수가 계속
  바뀌므로 이 문서에 숫자로 적지 않습니다.
- **제거된 기능**: 바이탈(체중·혈압·혈당, `0016_drop_vitals`)과 회원 일정(`/schedule/events`,
  `0069_drop_schedule_events`)은 테이블·엔드포인트가 없습니다. 트레이너 일정은 `/trainer/schedule*` 입니다.

<details>
<summary>초기 재작업 기록 (STEP 0~7, 당시 상태)</summary>

처음에는 회원 앱 프로토타입의 `LocalApiInterceptor` 를 정답 계약으로 삼아 백엔드를 단계별로 다시 짰습니다.
아래는 그때의 단계 기록이라 지금 상태와 다른 줄이 있습니다(예: STEP 6 의 회원 일정은 이후 제거됨).

- **STEP 0** API 계약 명세 (API_CONTRACT.md)
- **STEP 1** 골격 재구성: /v1 prefix · 문자열 id · snake_case · 시스템 엔드포인트 · DB/Docker
- **STEP 2** 사용자/인증: /users/me, /users/me/health
- **STEP 3** 식단: /diet/days/today + POST /diet/analyze (Gemini, 엔진 교체 가능)
- **STEP 4** 운동: /exercise/weeks/current + POST /exercise/sessions
- **STEP 5** 바이탈(체중·혈압·혈당) — 이후 제거(`0016_drop_vitals`)
- **STEP 6** 일정/알림/장소/AI코치 — 회원 일정 `/schedule/events` 는 이후 제거(`0069_drop_schedule_events`)
- **STEP 7** RAG 코치: 임베더/LLM factory, 개인·공공 문서 격리, 도메인 필터, 청킹, 규칙 기반 폴백, 적재/재임베딩 스크립트

</details>

## 실행
```bash
cp .env.example .env          # JWT_SECRET 교체
docker compose up --build
```
→ http://localhost:8000/docs  (경로는 모두 /v1/...)

## 의존성
파이썬 버전과 의존성 버전은 **운영 이미지·CI·로컬이 모두 같은 값**을 씁니다(#2837).

| 파일 | 역할 |
| --- | --- |
| `.python-version` | 파이썬 버전의 기준(현재 3.12). CI 가 이 파일을 읽고, `Dockerfile` 의 `ARG PYTHON_VERSION` 기본값이 같은지 검사합니다 |
| `requirements.in` | 운영 직접 의존 목록(버전 범위만) |
| `requirements.txt` | 위에서 만든 **잠금 파일**(전 패키지 버전·해시 고정). 이미지·CI 는 `--require-hashes` 로 이것만 설치합니다 |
| `requirements-dev.in` / `requirements-dev.txt` | 테스트 전용 의존(pytest)과 그 잠금 파일. 운영 잠금 파일로 제약해 버전이 같습니다 |

```bash
pip install --require-hashes -r requirements-dev.txt   # 로컬 개발·테스트
```

의존성을 더하거나 범위를 바꿀 때는 `.in` 파일을 고친 뒤 잠금 파일을 다시 만듭니다.
잠금 파일은 손으로 고치지 않습니다. 기존 버전은 유지되고 바뀐 것만 다시 풀립니다.

```bash
pip install uv
uv pip compile --universal --python-version 3.12 --generate-hashes requirements.in -o requirements.txt
uv pip compile --universal --python-version 3.12 --generate-hashes requirements-dev.in -o requirements-dev.txt
# 전체를 최신으로 올릴 때만 --upgrade, 한 패키지만 올릴 때는 --upgrade-package <이름>
```

`--universal` 은 운영(리눅스)과 팀원 PC(macOS·Windows)에서 함께 쓰이는 잠금 파일을 만듭니다
(예: `uvloop` 은 Windows 에서 빠지도록 조건이 붙습니다). Dependabot 이 매주 업데이트 PR 을
올리고, 백엔드 CI 가 잠금 파일의 알려진 취약점(pip-audit, 허용 목록 `audit-allowlist.toml` 밖이면
실패), 린트(ruff, `ruff.toml`), 이미지 빌드와 개발·운영 설정 기동(`tests/fixtures/prod_smoke.env`)을 확인합니다.
처리 규칙은 [docs/team_workflow.md](../docs/team_workflow.md) "의존성 업데이트 PR".

## DB 마이그레이션 (Alembic)
스키마는 **Alembic 마이그레이션**으로 관리합니다(베이스라인: `migrations/versions/0001_baseline.py` + pgvector). 현재 head 는 `alembic heads` 로 확인하고, Backend CI 가 head 가 정확히 1개인지 검사합니다.
DB URL 은 `.env` 의 `DATABASE_URL` 을 그대로 사용합니다(`migrations/env.py` 가 app 설정에서 읽음).

```bash
cd backend
alembic upgrade head          # 최신 스키마로 반영 (운영/CI 는 이 명령으로 스키마 생성)
alembic revision --autogenerate -m "설명"   # 모델 변경 후 새 마이그레이션 생성
alembic downgrade -1          # 한 단계 롤백
```
> 로컬 개발 편의를 위해 앱 기동 시 `create_all()` 로도 테이블을 만들지만(멱등, 기본 `AUTO_CREATE_TABLES=true`), **CI·운영은 `AUTO_CREATE_TABLES=false`** 로 두고 `alembic upgrade head` 만을 스키마의 정답으로 삼습니다(운영 `ENV=prod` 에서 `true` 면 기동을 거부합니다). 스키마 보정 코드는 앱에 두지 않고 마이그레이션으로만 합니다. (#2838)
>
> 백엔드 CI 는 `alembic upgrade head` 뒤에 `alembic check` 로 모델과 마이그레이션 결과가 같은지 확인합니다. 모델을 바꾸고 마이그레이션을 빠뜨리면 여기서 실패하므로, 모델을 고친 PR 은 로컬에서 빈 DB 에 `alembic upgrade head && alembic check` 를 한 번 돌려 보십시오.

> **`alembic.ini` 에는 한글을 넣지 마십시오(ASCII 전용).** Alembic 이 그 파일을 로케일 인코딩으로 읽어서, 한국어 Windows(cp949)에서는 한글 한 글자만 있어도 위 세 명령이 전부 `UnicodeDecodeError` 로 죽습니다. 리눅스 CI 는 UTF-8 로케일이라 통과하므로 드러나지 않고, `PYTHONUTF8=1` 로도 잡히지 않습니다. 설명은 `migrations/env.py` 나 이 문서에 적습니다. (#2004)

## 테스트
```bash
cd backend
pytest -q
```
DB 는 개발·데모 DB 가 아니라 **전용 테스트 DB**(기본값 `oncare_test`)를 씁니다. 최초 1회만 만들어 두면 됩니다 — 스키마와 시드는 실행이 채웁니다.

```bash
createdb -h 127.0.0.1 -U oncare oncare_test
psql -h 127.0.0.1 -d oncare_test -c 'CREATE EXTENSION IF NOT EXISTS vector'   # superuser 필요
```

> **여러 명이(또는 워크트리 여러 개에서) 동시에 돌릴 때는 각자 다른 DB 를 가리키십시오.** 스위트는 시작할 때 `TRUNCATE <모든 테이블> RESTART IDENTITY CASCADE` 로 DB 를 비웁니다(`tests/conftest.py`). 기본값이 모두 같은 `oncare_test` 라, 나중에 시작한 실행이 먼저 돌던 실행의 데이터를 지워 **관계없는 테스트가 무더기로 깨집니다.** 원인이 코드처럼 보여 찾는 데 시간이 걸립니다.
>
> ```bash
> createdb -h 127.0.0.1 -U oncare oncare_test_<내이름>
> psql -h 127.0.0.1 -d oncare_test_<내이름> -c 'CREATE EXTENSION IF NOT EXISTS vector'
> DATABASE_URL=postgresql+psycopg://oncare:oncare@localhost:5432/oncare_test_<내이름> pytest -q
> ```

## RAG (pgvector + Gemini)
공공문서 적재 → pgvector 검색 → 근거 코칭까지의 로컬 셋업·재현 절차는 **[docs/rag_gemini_setup.md](docs/rag_gemini_setup.md)** 참고.
임베딩 `gemini-embedding-001`(768) · 코치/인식 `gemini-flash-latest` · `.env`: `EMBEDDER=gemini`, `EMBED_DIM=768`.
검증: `python -m scripts.check_gemini` · `/v1/ai-coach/chat` 응답의 `sources` 가 채워지면 RAG 가 실제로 동작(규칙 폴백 아님).

## AI 폴백 지표
루틴 생성·식단 추천은 실패해도 규칙 기반으로 조용히 폴백한다 — 사용자는 그럴듯한
결과를 계속 받으므로 AI 가 죽어도 신고가 들어오지 않는다. 관리자 토큰으로 확인한다:
```bash
curl -H "Authorization: Bearer $ADMIN_TOKEN" http://localhost:8000/v1/system/metrics
```
응답의 `counters` 에 들어오는 키(전체 이름 그대로 조회):

| 키 | 뜻 |
| --- | --- |
| `routine_options.generated{by=ai}` | LLM 이 만든 루틴. **0 이면 AI 경로가 죽은 것** |
| `routine_options.generated{by=rule}` | 폴백으로 만든 루틴 |
| `routine_options.fallback{reason=busy}` | 동시 호출 한도 초과 → `LLM_MAX_CONCURRENCY` 를 본다 |
| `routine_options.fallback{reason=timeout}` | `LLM_TIMEOUT_SEC` 초과 → 아래 `llm_ms` 와 함께 본다 |
| `routine_options.fallback{reason=contract}` | 응답 규격 위반 → 프롬프트·스키마를 본다 |
| `routine_options.fallback{reason=infra}` | 키 미설정·설정 오타·네트워크·5xx |
| `routine_options.fallback{reason=global_cap}` | 서버 전체 하루 AI 상한(`AI_GLOBAL_CALLS_PER_DAY`) 도달(#3032) |
| `routine_options.with_chat_context` | 채팅 근거가 실린 채 AI 가 성공한 횟수(#580) |
| `diet_recommendations.generated{by=llm}` | LLM 이 만든 추천 |
| `diet_recommendations.generated{by=rules}` | LLM 실패 후 규칙으로 만든 추천 |
| `diet_recommendations.generated{by=no_data}` | 근거가 없어 LLM 을 부르지 않음(신규 가입자) |
| `diet_recommendations.fallback{reason=busy\|timeout\|error}` | 동시 호출 한도·타임아웃·그 외 실패 |
| `diet_recommendations.fallback{reason=global_cap}` | 서버 전체 하루 AI 상한 도달(#3032) |
| `ai_calls.acquired{feature=…}` | 하루 상한 안에서 모델을 부른 횟수(기능별, #3032). 기능 키는 `ai_call_quota.FEATURE_*` |
| `ai_calls.rejected{feature=…,reason=trainer_daily\|global_cap}` | 하루 상한에 걸려 모델을 부르지 않은 횟수 — 트레이너 한 계정(429)·서버 전체 |

사유가 넷인 이유는 볼 곳이 다르기 때문이다. `busy`·`timeout` 은 **공급자는 멀쩡한데
우리 쪽 상한에 걸린 것**이라 동시성·타임아웃 설정을 조정할 신호이고, `contract` 는
프롬프트나 스키마를, `infra` 는 키·네트워크를 본다. 한 칸에 뭉쳐 세면 이 구분이
사라진다.

`durations` 에는 `routine_options.llm_ms` 가 count/avg/max 로 들어온다. `timeout` 이
쌓이는데 `avg_ms` 가 `LLM_TIMEOUT_SEC` 에 못 미치면 몇 건이 유난히 느린 것이므로
`max_ms` 를 본다.

관리자는 `python -m scripts.grant_admin --email … --confirm-id …` 로 지정한다(#3037,
[DEPLOY.md](docs/DEPLOY.md) "관리자 지정"). `ADMIN_EMAILS` 는 더 이상 쓰지 않는다.
값은 프로세스 메모리에 있어 재시작하면 사라진다(단일 인스턴스 기준).

## 프론트 연동 (실서버 전환)
회원 앱(모바일)·트레이너 웹 **양쪽 모두** 같은 방식으로 전환합니다.
```bash
flutter run --dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=http://localhost:8000/v1
```
(LocalApiInterceptor 가 꺼지고 실제 /v1 서버로 요청)

둘을 함께 띄워 회원↔트레이너 상호작용을 확인하는 절차·데모 계정·기동 실패 대처는
**[docs/local_fullstack.md](../docs/local_fullstack.md)** 에 정리했습니다.

## 준비물
- Docker Desktop (무료, 가입 없음)
- (선택) Gemini 키 — 없으면 식단 인식·AI 코치가 규칙/스텁으로 폴백

## 식단 인식 실제 예시 (Diet Analysis PoC — live output)

식단 인식은 인식 엔진을 교체할 수 있습니다(factory 구조).
현재 Gemini 무료 티어가 지역에서 회수되어(quota=0) 라이브 호출이 막혔으므로,
**LiteLLM Virtual Key 로 프록시 뒤의 비전 모델을 써서 우회**하여 라이브 호출을 확인했습니다.
Gemini 키가 확보되면 `.env` 의 `RECOGNIZER=gemini` 로 즉시 전환 가능합니다.

**설정 (.env)**
```
RECOGNIZER=litellm
COACH_LLM=litellm
LITELLM_BASE_URL=http://<litellm-host>:4000
LITELLM_API_KEY=<Virtual Key>          # gitignored
LITELLM_VISION_MODEL=<비전 모델 이름>
```

**요청**
```
POST /v1/diet/analyze   (multipart: image=<음식 사진>, meal_type=lunch)
```

**응답 (engine=litellm, 실제 호출 결과 — 엔진 이름은 현재 키로 표기)**
```json
{
  "entry_id": "diet-c62ce45833ba",
  "analysis": {
    "engine": "litellm",
    "foods": [
      {"name": "혼합 견과류 및 건포도", "calories": 180, "sodium_mg": 95, "sugar_g": 15, "confidence": 0.75},
      {"name": "오이 및 채소 샐러드", "calories": 35, "sodium_mg": 45, "sugar_g": 3, "confidence": 0.85},
      {"name": "치즈(옐로우)", "calories": 110, "sodium_mg": 190, "sugar_g": 1, "confidence": 0.7},
      {"name": "과일 음료", "calories": 95, "sodium_mg": 25, "sugar_g": 22, "confidence": 0.65}
    ],
    "total_calories": 420,
    "total_sodium_mg": 355,
    "total_sugar_g": 41,
    "coach_comment": "치즈의 높은 나트륨(190mg)이 주의 대상입니다. DASH 식단 관점에서 저나트륨 치즈로 교체하거나 양을 줄이고, 과일 음료의 당류(22g)도 물이나 무가당 음료로 대체하는 것을 권장합니다. 신선한 채소 샐러드는 훌륭한 선택이므로 이를 더 늘리면 좋습니다."
  }
}
```

인식 엔진 선택: `RECOGNIZER=gemini`(기본) | `litellm`(LiteLLM 프록시 경유 비전 모델).
엔진을 바꿔도 응답 형식(DietAnalysis)은 동일하므로 프론트는 영향받지 않습니다.
