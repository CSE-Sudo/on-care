# 백엔드 배포 가이드 — AWS App Runner + Neon(pgvector)

컨테이너 + Postgres(pgvector) 구조라 컴퓨트는 **App Runner**(HTTPS 자동, 운영 부담 최소),
DB 는 **Neon Postgres(pgvector)** 를 쓴다. DB 를 컴퓨트와 분리해 두면 컴퓨트 플랫폼을 바꿔도
`DATABASE_URL` 을 그대로 옮기면 된다. 배포가 켜져 있으면(저장소 변수 `BACKEND_DEPLOY_ENABLED=true`)
`main`의 Backend CI가 성공할 때 해당 커밋 이미지를 ECR에 올리고, 불변 digest로 App Runner 소스를
갱신한다(`.github/workflows/backend-deploy.yml`). 변수가 없거나 `true` 가 아니면 배포 잡은 건너뛴다.

```
GitHub(main push) ──> Actions ──> ECR(이미지) ──> App Runner(:8000, /v1/healthz)
                                                        │
                                                        └── Neon Postgres (CREATE EXTENSION vector)
```

기동 흐름: 컨테이너가 `scripts/start.sh` 로 **마이그레이션 → uvicorn(--proxy-headers)**.
마이그레이션은 `scripts/migrate.py` 가 **PostgreSQL advisory lock 으로 직렬화**하므로, App Runner
가 여러 인스턴스를 동시에 띄워도 하나만 마이그레이션하고 나머지는 대기 후 no-op 이다(리뷰 #3).
운영은 `AUTO_CREATE_TABLES=false` 로 두고 Alembic 을 스키마의 유일한 소스로 삼는다.

> **DB 연결 한도**: `scripts/migrate.py` 는 `MIGRATE_CONNECT_TIMEOUT`(기본 10초) 안에 DB 에 붙지
> 못하면 실패한다(#2912). 잘못된 호스트·막힌 보안 그룹에서 OS TCP 타임아웃(수 분)까지 기다려 헬스체크
> 한도를 넘기지 않게 하려는 값이다.
>
> **확장 생성은 마이그레이션 몫**: 앱 기동의 `init_db` 는 `AUTO_CREATE_TABLES=true`(로컬 개발)일 때만
> `CREATE EXTENSION vector` 를 부른다(#2912). 운영은 Alembic 첫 리비전이 확장을 만들므로, 앱 계정에
> 확장 생성 권한이 없어도 기동 경고가 남지 않는다.
>
> **무거운 마이그레이션 주의**: lock 획득 대기 한도는 `MIGRATE_LOCK_TIMEOUT`(기본 120초)다.
> 데이터가 쌓인 뒤 120초를 넘길 수 있는 마이그레이션을 배포하기 전에는, 동시에 뜬 다른 인스턴스가
> fail-fast·재시작 루프에 빠지지 않도록 이 값을 넉넉히(예: `MIGRATE_LOCK_TIMEOUT=600`) 올려 둔다.

**배포 활성 조건**: 배포 잡은 GitHub 저장소 변수(Settings > Secrets and variables > Actions >
Variables) **`BACKEND_DEPLOY_ENABLED` 가 `true`** 일 때만 돈다. 이 값이 없으면 main 에 병합돼도
Backend CI 만 돌고 **배포 잡은 건너뛴다(skipped)** — 자동 배포·수동 실행 모두 같다. 리전은 저장소 변수
**`AWS_BACKEND_REGION`**(없으면 기본 `ap-southeast-1`)으로 정한다.

| 저장소 변수 | 값 | 없으면 |
|---|---|---|
| `BACKEND_DEPLOY_ENABLED` | `true` | 배포 잡 skipped |
| `AWS_BACKEND_REGION` | 예: `ap-southeast-1` | `ap-southeast-1` |

**배포 게이팅**: 활성 상태에서 `.github/workflows/backend-deploy.yml` 은 **"Backend CI" 가 성공**했을 때만
(workflow_run) 실행되며, 자동 배포는 **동일 저장소의 `main` push**에서 발생한 성공 run만
허용한다. PR·fork 등 다른 이벤트의 CI 결과로는 배포할 수 없다. 따라서 테스트/마이그레이션
실패 커밋이나 병합되지 않은 코드는 운영에 배포되지 않는다. Backend CI 는
`alembic heads` 가 **정확히 1개**인지 검사해 마이그레이션 head 분기(선형화 누락)를 막는다.
배포 잡은 `concurrency` 로 한 번에 하나만 돌고, `update-service`가 반환한 정확한 OperationId와
`/v1/healthz` 를 폴링해 **실제 배포·기동 성공까지 확인**한 뒤, healthz 가 싣는 설정(`env`·
`demo_fallback`·`demo_seed`)이 운영 기대값인지 확인하고(#2821), `/v1/readyz` 로 **DB 까지 닿는지**
확인하고 나서야 워크플로우를 통과시킨다(#2912). App Runner 헬스체크는 계속 healthz 다 — DB 일시
장애로 인스턴스를 갈아 치우지 않게 프로세스 생존만 본다.

**수동 실행**(workflow_dispatch)도 `BACKEND_DEPLOY_ENABLED=true` 가 필요하고 CI 게이트를 우회하지 않는다. `main`에서 워크플로우를 실행하며 배포할 40자리
커밋 SHA를 입력해야 하고, 워크플로우가 GitHub Actions API에서 그 SHA의 `main` push에 대한
`Backend CI` 성공 기록을 확인한 뒤에만 배포한다. 따라서 최초 배포나 롤백도 이미 CI를 통과한
`main` 커밋 중에서 선택해야 한다.

---

## 1) ECR 리포지토리

Neon DB와 같은 싱가포르(`ap-southeast-1`)를 기본 리전으로 사용한다. 서울
(`ap-northeast-2`)에는 App Runner 엔드포인트가 없고, DB와 컴퓨트를 같은 리전에 두면
데모 환경의 리전 간 지연과 데이터 전송을 피할 수 있다.

Neon 연결정보가 나오기 전에는 비용이 없는 부트스트랩 스택만 먼저 생성한다. 이 스택은 ECR,
GitHub OIDC 배포 역할, App Runner의 ECR pull 역할을 만들며 App Runner 컴퓨트는 만들지 않는다.

```bash
aws cloudformation deploy \
  --template-file infra/backend-bootstrap.yml \
  --stack-name oncare-backend-bootstrap \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ExistingGitHubOidcProviderArn=arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com \
  --region ap-southeast-1
```

ECR에는 최근 이미지 10개만 유지하는 lifecycle policy가 적용된다. GitHub 저장소 변수
`AWS_BACKEND_REGION`도 `ap-southeast-1`로 설정한다.

## 2) Neon Postgres (pgvector)

- Neon 프로젝트를 만들고 DB 를 생성한 뒤 pgvector 확장을 1회 활성화한다:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

- 접속은 공용 엔드포인트 + TLS 라 App Runner 에 VPC 커넥터·보안그룹 설정이 필요 없다.
- `DATABASE_URL` 은 Neon 이 준 문자열(`sslmode=require` 등 쿼리 파라미터 포함)을 **그대로** 넣어도 된다.
  `config.sqlalchemy_database_url` 이 bare `postgresql://` 를 `postgresql+psycopg://` 로 정규화한다.
- **풀러(`-pooler`) 엔드포인트가 아니라 직접 엔드포인트를 쓴다.** 기동 시 마이그레이션이
  `pg_try_advisory_lock`(세션 단위 lock, `scripts/migrate.py`)으로 인스턴스를 직렬화하는데,
  트랜잭션 풀링을 거치면 lock 을 잡은 세션과 alembic 이 쓰는 세션이 달라질 수 있어 직렬화가 깨진다.

## 3) 환경변수 / Secrets (App Runner)

| 키 | 값/설명 |
|---|---|
| `ENV` | `prod` (fail-fast 하드닝 활성). **비우면 컨테이너가 뜨지 않는다**(`scripts/start.sh`, #2821) |
| `ALLOW_DEMO_FALLBACK` | `false`(기본값). `ENV=prod` 면 값과 무관하게 꺼진다 |
| `JWT_SECRET` | `openssl rand -hex 32` (기본값이면 기동 거부) |
| `DATABASE_URL` | 위 Neon 접속 문자열(직접 엔드포인트) |
| `AUTO_CREATE_TABLES` | `false` (Alembic 이 정답) |
| `CORS_ALLOW_ORIGINS` | 회원 앱·트레이너 웹이 실제로 서비스되는 도메인(콤마 구분). `*` 면 기동 거부 |
| `TZ` | `Asia/Seoul` (오늘/어제 라벨 KST 기준) |
| `SEED_DEMO_DATA` | `false`(기본값). 운영에서 `true` 면 기동 거부 — 시연은 데모 전용 DB 를 둔 별도 환경에서 |
| `DEMO_LOGIN_PASSWORD` | 운영에서는 쓰지 않는다(데모 시드를 켠 환경 전용) |
| `GYM_BENEFITS_ENABLED` | `false`(기본값). 제휴 헬스장이 생기면 `true` — PT 재등록 할인·락커 쿠폰·분석용 식판을 연다(#2822) |
| `GEMINI_API_KEY` 또는 LiteLLM(`LITELLM_*`) | 식단 인식/임베딩. **운영 필수** — `RECOGNIZER`·`EMBEDDER` 에 맞는 키가 없거나 `stub`·`hash` 면 기동 거부(#2812) |
| `GEMINI_MODEL` | 운영은 **고정 버전** 모델 이름(아래 "모델 고정"). 비우면 코드 기본 별칭 |
| `RECOGNIZER_TIMEOUT_SECONDS` | 식단 사진 인식 한 건의 대기 한도(초, 기본 60, #2912) |
| `MIGRATE_CONNECT_TIMEOUT` | 기동 마이그레이션의 DB 연결 한도(초, 기본 10, #2912) |
| `KAKAO_REST_API_KEY` | 장소(O2O) 실검색. `PLACES_PROVIDER=auto` 기본. 데모 시드가 꺼진 서버는 카카오 0건이면 빈 목록, 실패면 503 이고 시드 장소로 채우지 않는다(#2914) |
| `TRUSTED_PROXY_HOPS` | rate limit·감사 로그가 믿는 앞단 프록시 수(#2815). 비우면 운영 1. 프록시가 둘 이상 붙으면 그 수로 맞춘다 |
| `FORWARDED_ALLOW_IPS` | uvicorn 프록시 헤더 신뢰 대역(`scripts/start.sh`, 기본 `*`). 고정 대역이 있으면 좁힌다. 클라이언트 IP 는 이 값과 무관하게 위 홉 수로 읽는다 |
| `LOGIN_MAX_FAILURES`·`LOGIN_LOCKOUT_SECONDS` | 같은 이메일 로그인 연속 실패 잠금(기본 5회·900초) |
| `PAIRING_REDEEM_PER_DAY` | 회원 연결 코드 미리보기·사용의 트레이너 하루 상한(기본 30) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | 접근 토큰 수명(분, #2913). 기본 60. 두 앱은 만료되면 refresh 로 이어 가므로 운영은 짧게 둔다. 데모·개발 환경만 길게 |
| `REGISTER_PER_EMAIL_PER_HOUR` | 같은 이메일 가입 시도 시간당 상한(회원·트레이너 공용, 기본 5, #2913) |
| `PASSWORD_CHANGE_MAX_FAILURES` | 비밀번호 변경의 현재 비밀번호 연속 실패 잠금(사용자 단위, 기본 5회, 창은 `LOGIN_LOCKOUT_SECONDS`, #2913) |
| `EXPOSE_API_DOCS` | `/docs`·`/redoc`·`/openapi.json` 공개 여부(#2834). 비우면 운영은 닫힘(404). 스키마는 스테이징·로컬에서 본다 |
| `SENTRY_DSN` | 에러 추적 수신 주소(#2839). 비우면 보내지 않음. 값은 #480 에서 채운다 |
| `SENTRY_ENVIRONMENT` / `SENTRY_SAMPLE_RATE` | 선택. 비우면 `ENV` 값 / 기본 `1.0` |

> **시도 제한은 인스턴스 메모리에 둔다**(`app/core/rate_limit.py`). App Runner 최소·최대 인스턴스가
> 1 이 아니게 되거나 `WEB_CONCURRENCY` 를 늘리면 한도가 인스턴스·워커 수만큼 늘어나므로, 그때 공유 저장소(Redis 등) 구현으로 바꾼다.
> 기동 로그에 `TRUSTED_PROXY_HOPS=0` 경고가 보이면 프록시 홉 수 설정을 확인한다.

> 참고: 장소는 키가 없어도 시드 폴백으로 동작한다. 사진 인식·임베딩은 운영에서 폴백하지 않는다(#2812). 운영 시크릿은 Secrets Manager/SSM 에 두고
> App Runner 에 주입한다. 키 전체 목록과 형식은 `backend/.env.aws.example` 에 있다.

**운영에서 기본값을 그대로 두면 안 되는 키** — 기동은 되지만 개발용 동작이 남는다(#2840).
전체 키와 기본값·운영 권장값은 `backend/.env.example` 이 `config.py` 와 1:1 로 갖고 있다
(`tests/test_env_example.py` 가 빠진 키를 잡는다).

| 키 | 운영 값 | 기본값 그대로면 |
|---|---|---|
| `FORCE_HTTPS` | `true` | HTTP 요청이 HTTPS 로 넘어가지 않는다 |
| `ALLOW_DEMO_FALLBACK` | `false` | `ENV=prod` 면 어차피 꺼지지만, 스테이징·시연 서버를 `ENV=dev` 로 띄우면 토큰 없는 요청이 데모 계정으로 처리된다 |
| `ADMIN_EMAILS` | 운영 담당자 이메일(콤마 구분) | 관리자가 없어 공공 RAG 문서 적재·`/v1/system/metrics` 를 쓸 수 없다 |
| `REPORT_PDF_STORAGE_DIR`·`CHAT_IMAGE_STORAGE_DIR` | 영속 저장소를 붙인 경로 | 컨테이너 안 `data/` 에 쌓인다. 영속 디스크가 없는 컴퓨트(App Runner 등)에서는 재배포·재시작 때 주간 리포트 PDF·채팅 사진이 사라진다(저장소 구성은 #480 범위) |
| `SECURITY_HEADERS`·`RATE_LIMIT_ENABLED` | `true`(기본값 유지) | 끄면 보안 헤더·시도 제한이 빠진다 |
| `LOG_LEVEL` | `INFO` | — |

## 4) App Runner 서비스

- 소스: ECR 이미지, 포트 `8000`. CI는 **커밋 SHA 태그** 이미지(`oncare-backend:<sha>`)만 push하고
  ECR에서 그 이미지의 digest를 조회한다. 가변 `:latest` 태그는 만들거나 배포하지 않는다.
- **배포 방식**: CI가 `update-service`로 App Runner의
  `SourceConfiguration.ImageRepository.ImageIdentifier`를 `oncare-backend@sha256:...` 형식의
  불변 digest로 갱신하고 자동배포를 끈다. 기존 이미지 환경변수·시크릿·ECR 액세스 역할은
  `describe-service` 결과에서 보존한다.
- 워크플로우는 `update-service`의 OperationId를 `list-operations`로 추적하고, 성공 후 서비스에
  설정된 이미지 식별자가 요청한 digest와 같은지도 검증한다.
- 헬스체크: HTTP `GET /v1/healthz`.
- 환경변수: 위 표(민감값은 Secrets 참조).
- 컨테이너가 기동 시 마이그레이션을 수행하므로 별도 마이그레이션 스텝 불필요.

## 워커 수와 이벤트 루프 (#2835)

- `WEB_CONCURRENCY` 로 uvicorn 워커 수를 정한다(`scripts/start.sh`, 기본 `1`, 1 이상 정수가
  아니면 기동 거부). 실제 운영 값은 배포 설정에서 정한다(#480).
- 워커를 늘릴 때의 영향:
  - **인메모리 분당 한도**(로그인·AI 코치·사진 분석 분당 한도 등)는 워커마다 따로 센다 — 워커 N 개면
    한 사용자가 최대 N 배까지 통과할 수 있다. DB 에서 세는 하루 상한(AI 챗봇·사진 분석)은 영향 없다.
  - **`/v1/system/metrics`** 는 그 요청을 받은 워커 하나의 값만 보여 준다(합산되지 않는다).
  - **DB 연결 수**가 워커 수만큼 곱해진다(아래 계산식).
- `async def` 라우트 안에서 동기 DB·Pillow·파일 저장을 돌리지 않는다 — 이벤트 루프가 막혀 같은 워커의
  다른 요청(헬스체크 포함)이 모두 멈춘다. 외부 호출만 `await` 하고 나머지는 `run_in_threadpool` 로
  넘기거나 라우트를 `def` 로 둔다. `tests/test_async_route_guard.py` 가 이 규칙을 검사한다.

## DB 커넥션 풀·쿼리 실행 상한 (#2836)

| 키 | 기본값 | 설명 |
|---|---|---|
| `DB_POOL_SIZE` | `5` | 워커 하나가 유지하는 연결 수 |
| `DB_MAX_OVERFLOW` | `10` | 붐빌 때 잠깐 더 여는 연결 수 |
| `DB_POOL_TIMEOUT_SECONDS` | `10` | 풀이 말랐을 때 기다리는 상한. 기본값(30초)보다 짧게 실패시켜 클라이언트 재시도로 넘긴다 |
| `DB_POOL_RECYCLE_SECONDS` | `300` | 유휴 연결 재활용 주기. 관리형 DB 가 유휴 연결을 먼저 끊는 시간보다 짧게 둔다 |
| `DB_STATEMENT_TIMEOUT_MS` | `10000` | 쿼리 하나의 실행 상한. 연결 시작 옵션(`-c statement_timeout`)으로 건다. `0` 이면 끈다 |

- **연결 수 계산:** `(DB_POOL_SIZE + DB_MAX_OVERFLOW) × WEB_CONCURRENCY × 인스턴스 수` 가 DB 플랜의
  동시 연결 상한보다 작아야 한다. 기본값·워커 1·인스턴스 1 이면 최대 15 다. 마이그레이션은 기동 때
  별도 연결 하나를 잠깐 더 쓴다.
- 실행 상한은 앱 엔진에만 걸린다. 마이그레이션(`scripts/migrate.py`·Alembic)은 자기 엔진을 쓰므로 긴
  DDL 이 끊기지 않는다. readiness(`/readyz`)는 따로 3초 상한을 건다.
- 시작 옵션을 받지 않는 풀러 엔드포인트(PgBouncer 등)로 바꾸면 연결이 거부된다 — 그때는
  `DB_STATEMENT_TIMEOUT_MS=0` 으로 끄고 DB 역할 쪽에 상한을 건다. 지금은 직접 엔드포인트를 쓴다.
- AI 코치 채팅·홈 코칭은 LLM 응답을 기다리기 전에 읽기 트랜잭션을 끝내 연결을 풀로 돌려준다 —
  LLM 대기(수 초~수십 초) 동안 연결을 쥐지 않는다.
- 풀 상태는 관리자 전용 `GET /v1/system/metrics` 의 `db_pool`(`size`·`checked_out`·`overflow`)로
  본다. `checked_out` 이 자주 `size + max_overflow` 에 닿으면 풀을 키우거나 느린 경로를 찾는다.

## 5) CI 용 GitHub Secrets & IAM 역할

- `AWS_DEPLOY_ROLE_ARN` — GitHub OIDC 로 assume 하는 IAM 역할. 필요 권한: ECR push 및 digest 조회
  (`ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`,
  `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`,
  `ecr:DescribeImages`) + `apprunner:UpdateService`, `apprunner:ListOperations`,
  `apprunner:DescribeService`.
- `APPRUNNER_SERVICE_ARN` — 배포 대상 App Runner 서비스 ARN.
- **App Runner ECR 액세스 역할(별도)**: App Runner 가 **private ECR 에서 이미지를 pull** 하려면
  서비스의 `AuthenticationConfiguration.AccessRoleArn` 에 지정하는 IAM 역할이 필요하다.
  신뢰 주체 `build.apprunner.amazonaws.com`, 정책은 `ecr:GetAuthorizationToken`(리소스 `*`) +
  `ecr:BatchGetImage`·`ecr:GetDownloadUrlForLayer`·`ecr:BatchCheckLayerAvailability`·`ecr:DescribeImages`
  (해당 리포 리소스). 이 역할이 없으면 배포/기동 시 이미지 pull 이 실패한다.

## 5-1) 채팅 첨부 저장소 — S3 (#2817)

채팅 사진과 주간 리포트 PDF 의 **바이트**는 DB 가 아니라 저장소에 둔다(메타데이터만 DB).
App Runner 의 컨테이너 디스크는 재배포·재시작·스케일 아웃 때 비거나 인스턴스마다 달라서,
운영은 S3 버킷을 쓴다. 로컬 개발·테스트는 지금처럼 디스크(`data/chat-images`,
`data/report-pdfs`)에 쓴다.

| 키 | 값/설명 |
|---|---|
| `ATTACHMENT_STORAGE` | `auto`(기본: 버킷 이름이 있으면 `s3`, 없으면 `local`) · `local` · `s3`. `s3` 인데 버킷이 비면 기동 거부 |
| `ATTACHMENT_S3_BUCKET` | 첨부 버킷 이름. 비면 로컬 디스크(운영이면 기동 때 WARN) |
| `ATTACHMENT_S3_REGION` | 버킷 리전. 비면 AWS 기본 체인(App Runner 리전) |
| `ATTACHMENT_S3_PREFIX` | 키 접두사(기본 `chat-attachments`). 키는 `<접두사>/chat-images/<id>.<ext>`·`<접두사>/report-pdfs/<id>.pdf` |
| `ATTACHMENT_S3_ENDPOINT_URL` | S3 호환 저장소를 쓸 때만. AWS 는 비운다 |

- **자격 증명은 환경변수로 주지 않는다.** App Runner **인스턴스 역할**에 버킷 권한을 준다:
  `s3:PutObject`·`s3:GetObject`·`s3:DeleteObject`(리소스 `arn:aws:s3:::<버킷>/<접두사>/*`)와
  `s3:ListBucket`(리소스 `arn:aws:s3:::<버킷>`, 조건 `s3:prefix` = `<접두사>/*`).
  **`ListBucket` 을 빼면 안 된다** — 없으면 S3 가 없는 키에 404 대신 403 을 주어, 사진의
  확장자를 차례로 찾는 조회와 이전 스크립트의 존재 확인이 저장소 장애로 읽힌다.
- 버킷은 **퍼블릭 접근 차단**을 켠다. 다운로드는 늘 백엔드가 권한(스레드의 두 사람·담당 링크·
  동의)을 확인한 뒤 흘려보내므로 버킷을 공개할 이유가 없다. 서명 URL 도 쓰지 않는다.
- 기본 암호화(SSE-S3)를 켜 둔다. 버전 관리를 켜면 탈퇴로 지운 객체가 이전 버전으로 남으니,
  켤 경우 **이전 버전 만료 수명 주기 규칙**(예: 30일)을 함께 건다.
- 탈퇴 시 그 계정이 낀 스레드의 첨부를 지운다. 삭제 실패는 `탈퇴 첨부 삭제 실패` 경고 로그에
  `file_id` 와 함께 남으니, 로그 알림으로 받아 수동으로 지운다.

### 전환 절차 (로컬 디스크 → S3)

1. 버킷·인스턴스 역할 권한을 만든다(#480).
2. 기존 파일이 있는 환경(지금 떠 있는 컨테이너 또는 그 디스크 사본)에서 DB 를 운영 값으로 두고
   이전 스크립트로 옮긴다. **DB 가 가리키는 파일만** 옮기고, 이미 있는 키는 건너뛴다(여러 번 돌려도 같다).

   ```bash
   ATTACHMENT_S3_BUCKET=<버킷> ATTACHMENT_S3_REGION=<리전> \
     python -m scripts.migrate_attachments --dry-run   # 옮길 목록·로컬에 없는 파일 확인
   ATTACHMENT_S3_BUCKET=<버킷> ATTACHMENT_S3_REGION=<리전> \
     python -m scripts.migrate_attachments
   ```

   `DB 에는 있는데 로컬에 없는 파일` 은 이미 재배포로 잃은 파일이라 복구할 수 없다.
3. App Runner 서비스 환경변수에 `ATTACHMENT_S3_BUCKET`(필요하면 `ATTACHMENT_S3_REGION`)을 넣고
   재배포한다. 배포 뒤 `/v1/healthz` 의 `attachment_storage` 가 `s3` 인지 확인한다.
4. 대화방에서 예전 사진·리포트가 열리는지 확인한 뒤 컨테이너 쪽 사본을 지운다.

데모 시드 첨부(#2788)는 기동마다 같은 `file_id` 로 다시 쓰므로 옮기지 않아도 된다.

## 5-2) 운영 체크리스트 (#2821)

배포 전에 한 번, 환경변수를 바꿀 때마다 다시 본다.

- [ ] App Runner 환경변수가 `backend/.env.aws.example` 의 키를 모두 갖는다. `ENV=prod`,
      `AUTO_CREATE_TABLES=false`, `SEED_DEMO_DATA=false`, `ALLOW_DEMO_FALLBACK=false`.
- [ ] **운영 DB 와 데모 DB 가 다르다.** 운영 서비스의 `DATABASE_URL` 은 데모 시드가 한 번도
      들어가지 않은 DB(또는 Neon 브랜치)를 가리킨다. 데모 시연이 필요하면 **별도 App Runner 서비스**
      (`ENV=staging`, `SEED_DEMO_DATA=true`, 강한 `DEMO_LOGIN_PASSWORD`)를 **별도 DB** 로 띄운다.
      같은 DB 를 쓰면 운영 화면에 데모 계정·기록이 섞이고, 데모 계정 비밀번호가 운영 자격 증명이 된다.
- [ ] `JWT_SECRET` 은 서비스마다 다르다(데모 서비스에서 발급한 토큰이 운영에서 통하지 않게).
- [ ] `CORS_ALLOW_ORIGINS` 는 실제 프론트 도메인만.
- [ ] `ATTACHMENT_S3_BUCKET` 이 있다(아래 5-1). 없으면 기동 로그에 WARN.
- [ ] 배포 뒤 워크플로의 `Verify running configuration` 단계가 통과했다 — `/v1/healthz` 가
      `env=prod`·`demo_fallback=false`·`demo_seed=false` 를 돌려줘야 통과한다. 기대 환경은 저장소
      변수 `BACKEND_EXPECTED_ENV`(기본 `prod`)다. 데모 서비스를 이 워크플로로 배포한다면 그 서비스용
      설정에서 이 값을 `staging` 으로 둔다.
- [ ] 기동 로그에 `[startup]` WARN 이 없다(데모 폴백·운영 데모 시드·로컬 첨부 저장소).

## 5-3) 모델 고정 (#2912)

코드 기본값 `GEMINI_MODEL=gemini-flash-latest` 는 **별칭**이라 제공자가 가리키는 모델을 바꾸면
배포 없이 응답 품질·형식·비용이 바뀐다. 로컬·데모는 별칭으로 두되(핀 모델이 은퇴해 깨지는 일을
피한다), 운영은 고정 버전을 넣는다.

1. 제공자 문서에서 현재 별칭이 가리키는 고정 버전 이름과 은퇴 예정일을 확인한다.
2. 데모(스테이징) 서비스의 `GEMINI_MODEL` 을 그 이름으로 바꿔 식단 사진 인식·코치 답변을 확인한다.
3. 운영 App Runner 환경변수 `GEMINI_MODEL` 을 같은 값으로 바꾼다(재배포 없이 서비스 갱신).
4. 은퇴 예정일 한 달 전에 같은 절차로 다음 버전으로 옮긴다. 담당자는 배포 담당(#480)이다.

임베딩 설정(`EMBEDDER`·`EMBED_DIM` 등)은 바꾸면 저장된 벡터와 차원·공간이 어긋나므로 여기서 다루지
않는다 — 바꿀 때는 재임베딩(`scripts/reembed`)이 함께 필요하다.

## 5-4) 정기 운영 작업 (#2912)

| 작업 | 주기 | 방법 | 담당 |
|---|---|---|---|
| 읽은 알림 정리 | 매월 1회 | `python -m scripts.purge_notifications --dry-run` 으로 대상 확인 → 같은 명령에서 `--dry-run` 을 빼고 실행. 읽은 알림 중 90일 지난 것만 지운다 | 배포 담당(#480) |
| 모델 은퇴 확인 | 분기 1회 | 위 5-3 | 배포 담당(#480) |

알림 정리는 되돌릴 수 없어 자동 스케줄로 돌리지 않는다. 운영 DB 를 향한 `DATABASE_URL` 로
컨테이너(또는 같은 이미지의 일회성 작업)에서 실행한다.

## 리전 (#2912)

리전은 **아직 확정하지 않았다**(#480 에서 결정). 현재 설정은 백엔드 `ap-southeast-1`(Neon DB 와
같은 리전, 위 1절), 프론트 정적 호스팅 `ap-northeast-2` 다. 첨부 저장소 S3 버킷은 **백엔드와 같은
리전**에 둔다(`ATTACHMENT_S3_REGION`) — 다른 리전이면 업로드·다운로드마다 리전 간 전송 지연·요금이 붙는다.

## 6) 프론트 연결

```bash
flutter build web --release \
  --dart-define=ENV=prod \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=https://<apprunner-domain>/v1
```

`ENV=prod` 를 빠뜨리면 릴리스 빌드가 기동할 때 구성 오류 안내만 띄운다(#3022). 운영 웹은
`aws-frontend-deploy.yml` 이 위 값과 `SENTRY_DSN` 을 함께 넘긴다.

지도 핀은 프론트 카카오맵 **JS SDK**(JS키 + 도메인 등록) 담당. 백엔드는 좌표+정보만 제공한다.

**운영 체크리스트 — 카카오 JavaScript 키 허용 도메인(#2913).** `KAKAO_JS_KEY` 는 웹 빌드에 들어가
브라우저에 그대로 보인다. 키를 지키는 것은 카카오 개발자 콘솔의 **JavaScript SDK 도메인** 목록뿐이다.
배포·도메인을 바꿀 때마다 아래를 확인한다.

- 목록에 운영 회원 웹·트레이너 웹 주소만 있는가(`https://` 포함, 경로 없이 출처 단위).
- 개발용 주소(`localhost` 등)·옛 배포 주소·임시 미리보기 주소가 남아 있지 않은가. 로컬 개발이
  필요하면 운영 키가 아닌 개발용 앱 키를 따로 쓴다.
- 확인한 날짜와 결과를 담당 이슈에 남긴다.

---

## 데모 데이터 정리 (#2811)

예전에는 `SEED_DEMO_DATA` 기본값이 켜져 있어, 값을 빠뜨린 채 띄운 서버가 데모 계정·데모 회원
기록·가상 트레이너·가상 헬스장을 DB 에 심었습니다. 지금은 기본값이 꺼져 있고 운영에서는 켤 수도
없지만, 이미 심긴 행은 그대로 남습니다. 회원 앱 트레이너 찾기·추천·상세와 상담 신청은 데모가 꺼진
서버에서 데모 트레이너를 거르므로 노출은 막혀 있고, 행 자체는 아래 절차로 지웁니다.

1. 서버 설정이 `SEED_DEMO_DATA=false`(또는 미지정)인지 확인합니다. 켜진 채 재기동하면 지운
   데이터가 다시 심깁니다.
2. DB 백업을 떠 둡니다(Neon 이면 브랜치 생성).
3. 미리보기로 건수를 확인합니다. 아무것도 지우지 않습니다.
   ```bash
   cd backend && DATABASE_URL=<운영 DB> python -m scripts.purge_demo_data
   ```
   데모 사용자 id 목록, 예약 건수(그중 실제 회원의 예약), `users.id` 를 참조하는 표별 행 수,
   지울 데모 장소와 **남기는 장소**(실제 트레이너 소속·실제 회원 연결이 있는 곳)가 나옵니다.
4. 건수가 맞으면 `--apply` 를 붙여 지웁니다.
   ```bash
   cd backend && DATABASE_URL=<운영 DB> python -m scripts.purge_demo_data --apply
   ```

지우는 대상은 시드 id 목록(`app/db/demo_ids.py`)뿐이고, 카카오에서 찾은 실재 업체 행은 지우지
않습니다. 데모 사용자의 식단·운동·채팅·알림·포인트는 `users.id` CASCADE 로 함께 지워집니다.

## 헬스장 혜택 쿠폰 정리 (#2822)

PT 재등록 할인·개인 락커·분석용 식판은 헬스장이 현장에서 주는 혜택입니다. 제휴 헬스장이 없는
동안에는 `GYM_BENEFITS_ENABLED=false`(기본값)로 닫아 둡니다. 닫힌 서버는 사용처 목록에서 두
항목을 빼고, 교환(404)과 식판 받기(409)를 거부하며, 회원 앱은 식판 카드를 그리지 않습니다.

닫기 전에 이미 발급된 쿠폰은 아래 절차로 취소하고 포인트를 돌려줍니다. 담당·헬스장 해제 때와
같은 취소 경로라 포인트 내역에 `refund` 로 남고 회원에게 쿠폰 취소 알림이 갑니다. 기한이 지난
쿠폰은 돌려주지 않고 만료로 내립니다.

1. 서버 설정이 `GYM_BENEFITS_ENABLED=false`·`SEED_DEMO_DATA=false` 인지 확인합니다. 혜택이 열린
   서버에서는 `--apply` 가 거부됩니다.
2. 미리보기로 대상 회원 수·항목별 장수·돌려줄 포인트를 확인합니다.
   ```bash
   cd backend && DATABASE_URL=<운영 DB> python -m scripts.cancel_gym_benefit_coupons
   ```
3. 건수가 맞으면 `--apply` 를 붙여 취소합니다. 두 번 돌려도 같습니다.
   ```bash
   cd backend && DATABASE_URL=<운영 DB> python -m scripts.cancel_gym_benefit_coupons --apply
   ```

## 마이그레이션 head 선형화 (머지 순서 주의)

병렬 브랜치가 같은 부모에서 각자 새 마이그레이션을 만들면 Alembic head 가 여러 개가 되어
`alembic upgrade head` 가 실패한다. 체인은 계속 자라므로 이 문서에 끝을 적지 않는다 —
**현재 head 는 `cd backend && alembic heads` 로 확인**하고, Backend CI 가 head 가 정확히 1개인지
검사한다.

아래는 초기 트레이너 스택을 머지할 때(0009~0020) 분기를 합쳐 한 줄로 이었던 **당시 기록**이다:

```
0009_diet_idempotency_key → 0010_diet_entry_macros(#207) → 0011_health_daily_sugar_g(#231)
                          → 0012_trainer_domain(트레이너 도메인) → 0013_trainer_active_coach_uq(active 담당 unique index)
                          → 0014_consultation_requests ─┐
                          → 0014_drop_trainer_prof_ix ──┴→ 0015_merge_alembic_heads
                          → 0016_drop_vitals → 0017_add_diet_exercise_goals
                          → 0018_diet_entry_sugar_g_float → 0019_trainer_noti_settings
                          → 0020_gym_profiles_trainer_fk
```

**원칙**: 나중에 머지되는 마이그레이션의 `down_revision` 을 그 시점 main 의 head(`alembic heads`)로
맞춰 한 줄로 잇는다(파일명 숫자도 위치에 맞게).

> 단, **한쪽 브랜치가 이미 staging/production DB 에 적용된 뒤**라면 위 "down_revision 만 바꾸기"를
> 쓰면 안 된다. 먼저 `alembic current` 로 그 DB 의 현재 revision 을 확인하고, 이미 적용된 경우
> `alembic merge` 로 병합 revision 을 만들거나 실제 적용 상태에 맞춰 head 를 선형화한다.
> CI 의 single-head 검사(`alembic heads` == 1)로 분기 재발을 막는다.

---

## 대안 — Railway (예비/대비용, AWS 이전 대상)

> **성격**: 운영 기본값은 여전히 **AWS App Runner + Neon** 이며, Railway 이전이
> 확정된 것은 아니다. 이 절과 관련 파일(`railway.json`·`.env.railway.example` 등)은
> **AWS 설정이 과하게 어렵거나 비용/운영 부담이 될 때 즉시 갈아탈 수 있게 해두는
> 예비용**이다. 지금 당장 Railway 를 쓰지 않아도 두어도 무해하며(런타임·CI 에 영향 없음),
> 필요해지는 순간 반나절 안에 이전할 수 있도록 이식성만 확보해 둔다.

App Runner 설정이 복잡하면 **같은 Docker 이미지를 그대로** Railway 에 올릴 수 있다.
코드 변경 없이 플랫폼만 바뀌며, 이 저장소는 그렇게 이식 가능하도록 준비돼 있다:

- **`backend/railway.json`** — Dockerfile 빌더 · 헬스체크(`/v1/healthz`) · 재시작 정책을 코드로 선언.
- **`scripts/start.sh`** — `--port ${PORT:-8000}`. Railway 가 주입하는 **동적 $PORT** 로 바인딩하고,
  없으면(App Runner·로컬·compose) 8000 으로 폴백한다(한 이미지가 양쪽 다 뜬다).
- **DB URL 자동 정규화** — Railway/Neon/Supabase 는 `postgres://…`·bare `postgresql://…` 를 준다.
  이 프로젝트는 psycopg **v3** 만 있어 bare URL 은 기동에 실패하는데, `config.sqlalchemy_database_url`
  이 `postgresql+psycopg://` 로 자동 변환하므로 플랫폼이 준 값을 **그대로** 붙여도 된다.

**배포 절차**

1. Railway 새 프로젝트 → GitHub 레포 연결 → 서비스의 **Root Directory = `backend`** 로 지정
   (그래야 `railway.json`·`Dockerfile` 을 찾는다).
2. DB 는 **기존 Neon 을 그대로 쓴다** — 컴퓨트만 바뀌므로 `DATABASE_URL` 을 옮기면 된다.
   Railway 안에 DB 를 새로 두려면 **반드시 `pgvector` 템플릿**으로 추가한다. 일반 Postgres
   이미지에는 **pgvector 바이너리가 없어** `CREATE EXTENSION vector` 자체가 실패하고,
   0007 마이그레이션(vector 타입)이 동작하지 않는다.
3. **Variables** 에 `backend/.env.railway.example` 값을 채워 넣는다
   (`DATABASE_URL`, `JWT_SECRET`, `CORS_ALLOW_ORIGINS`, `ENV=prod` 등). Neon 을 계속 쓰면
   `DATABASE_URL` 에 Neon 문자열을 그대로 넣고, Railway 안에 DB 를 두면
   `${{Postgres.DATABASE_URL}}` 로 참조한다 — 이 참조는 **DB 서비스명이 정확히 `Postgres` 일 때만**
   연결되므로 서비스명을 맞추거나 실제 서비스명으로 바꾼다(`${{<서비스명>.DATABASE_URL}}`).
   `PORT` 는 직접 넣지 않는다(Railway 가 주입).
4. 배포되면 컨테이너가 `scripts/start.sh` 로 **마이그레이션 → uvicorn** 을 수행하고,
   Railway 가 `/v1/healthz` 로 헬스체크한다. 발급된 도메인을 프론트 `API_BASE_URL` 에 연결
   (아래 "6) 프론트 연결" 과 동일, `/v1` 포함).

> DB 가 이미 Neon 에 있으므로 컴퓨트(App Runner ↔ Railway)를 바꿔도 데이터 이전은 없고,
> 새 플랫폼에 `DATABASE_URL` 을 넣어 주면 끝난다.

## 대안 — 저비용 EC2 (수동)

`docker-compose.yml` 거의 그대로 EC2 1대에 올리고 Nginx + Let's Encrypt 로 HTTPS.
가장 저렴하지만 HTTPS/DB백업/재시작을 직접 관리해야 한다.
