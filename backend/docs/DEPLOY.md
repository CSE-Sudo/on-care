# 백엔드 배포 가이드 — AWS App Runner + Neon(pgvector)

컨테이너 + Postgres(pgvector) 구조라 컴퓨트는 **App Runner**(HTTPS 자동, 운영 부담 최소),
DB 는 **Neon Postgres(pgvector)** 를 쓴다. DB 를 컴퓨트와 분리해 두면 컴퓨트 플랫폼을 바꿔도
`DATABASE_URL` 을 그대로 옮기면 된다. `main`의 Backend CI가 성공하면 해당 커밋 이미지를 ECR에 올리고,
불변 digest로 App Runner 소스를 갱신한다(`.github/workflows/backend-deploy.yml`).

```
GitHub(main push) ──> Actions ──> ECR(이미지) ──> App Runner(:8000, /v1/healthz)
                                                        │
                                                        └── Neon Postgres (CREATE EXTENSION vector)
```

기동 흐름: 컨테이너가 `scripts/start.sh` 로 **마이그레이션 → uvicorn(--proxy-headers)**.
마이그레이션은 `scripts/migrate.py` 가 **PostgreSQL advisory lock 으로 직렬화**하므로, App Runner
가 여러 인스턴스를 동시에 띄워도 하나만 마이그레이션하고 나머지는 대기 후 no-op 이다(리뷰 #3).
운영은 `AUTO_CREATE_TABLES=false` 로 두고 Alembic 을 스키마의 유일한 소스로 삼는다.

> **무거운 마이그레이션 주의**: lock 획득 대기 한도는 `MIGRATE_LOCK_TIMEOUT`(기본 120초)다.
> 데이터가 쌓인 뒤 120초를 넘길 수 있는 마이그레이션을 배포하기 전에는, 동시에 뜬 다른 인스턴스가
> fail-fast·재시작 루프에 빠지지 않도록 이 값을 넉넉히(예: `MIGRATE_LOCK_TIMEOUT=600`) 올려 둔다.

**배포 게이팅**: `.github/workflows/backend-deploy.yml` 은 **"Backend CI" 가 성공**했을 때만
(workflow_run) 실행되며, 자동 배포는 **동일 저장소의 `main` push**에서 발생한 성공 run만
허용한다. PR·fork 등 다른 이벤트의 CI 결과로는 배포할 수 없다. 따라서 테스트/마이그레이션
실패 커밋이나 병합되지 않은 코드는 운영에 배포되지 않는다. Backend CI 는
`alembic heads` 가 **정확히 1개**인지 검사해 마이그레이션 head 분기(선형화 누락)를 막는다.
배포 잡은 `concurrency` 로 한 번에 하나만 돌고, `update-service`가 반환한 정확한 OperationId와
`/v1/healthz` 를 폴링해 **실제 배포·기동 성공까지 확인**한 뒤 워크플로우를 통과시킨다.

**수동 실행**도 CI 게이트를 우회하지 않는다. `main`에서 워크플로우를 실행하며 배포할 40자리
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
| `ENV` | `prod` (fail-fast 하드닝 활성) |
| `JWT_SECRET` | `openssl rand -hex 32` (기본값이면 기동 거부) |
| `DATABASE_URL` | 위 Neon 접속 문자열(직접 엔드포인트) |
| `AUTO_CREATE_TABLES` | `false` (Alembic 이 정답) |
| `CORS_ALLOW_ORIGINS` | GitHub Pages 도메인 (예: `https://ewhasudo.zapto.org`) |
| `TZ` | `Asia/Seoul` (오늘/어제 라벨 KST 기준) |
| `SEED_DEMO_DATA` | 운영 권장 `false`. 데이터 든 데모 계정을 두려면 `true` + `DEMO_LOGIN_PASSWORD` 필수 |
| `DEMO_LOGIN_PASSWORD` | `SEED_DEMO_DATA=true` 일 때 12자+ 강한 값(아니면 기동 거부) |
| `GEMINI_API_KEY` 또는 LiteLLM(`LITELLM_*`) | 식단 인식/코치. 없으면 stub 폴백 |
| `KAKAO_REST_API_KEY` | 장소(O2O) 실검색. 없으면 시드 폴백. `PLACES_PROVIDER=auto` 기본 |
| `TRUSTED_PROXY_HOPS` | rate limit·감사 로그가 믿는 앞단 프록시 수(#2815). 비우면 운영 1. 프록시가 둘 이상 붙으면 그 수로 맞춘다 |
| `FORWARDED_ALLOW_IPS` | uvicorn 프록시 헤더 신뢰 대역(`scripts/start.sh`, 기본 `*`). 고정 대역이 있으면 좁힌다. 클라이언트 IP 는 이 값과 무관하게 위 홉 수로 읽는다 |
| `LOGIN_MAX_FAILURES`·`LOGIN_LOCKOUT_SECONDS` | 같은 이메일 로그인 연속 실패 잠금(기본 5회·900초) |
| `PAIRING_REDEEM_PER_DAY` | 회원 연결 코드 미리보기·사용의 트레이너 하루 상한(기본 30) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | 접근 토큰 수명(분, #2913). 기본 60. 두 앱은 만료되면 refresh 로 이어 가므로 운영은 짧게 둔다. 데모·개발 환경만 길게 |
| `REGISTER_PER_EMAIL_PER_HOUR` | 같은 이메일 가입 시도 시간당 상한(회원·트레이너 공용, 기본 5, #2913) |
| `PASSWORD_CHANGE_MAX_FAILURES` | 비밀번호 변경의 현재 비밀번호 연속 실패 잠금(사용자 단위, 기본 5회, 창은 `LOGIN_LOCKOUT_SECONDS`, #2913) |
| `EXPOSE_API_DOCS` | `/docs`·`/redoc`·`/openapi.json` 공개 여부(#2834). 비우면 운영은 닫힘(404). 스키마는 스테이징·로컬에서 본다 |

> **시도 제한은 인스턴스 메모리에 둔다**(`app/core/rate_limit.py`). App Runner 최소·최대 인스턴스가
> 1 이 아니게 되면 한도가 인스턴스 수만큼 늘어나므로, 그때 공유 저장소(Redis 등) 구현으로 바꾼다.
> 기동 로그에 `TRUSTED_PROXY_HOPS=0` 경고가 보이면 프록시 홉 수 설정을 확인한다.

> 참고: 키가 없어도 인식/장소는 폴백으로 동작(기동은 됨). 운영 시크릿은 Secrets Manager/SSM 에 두고
> App Runner 에 주입한다.

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

## 6) 프론트 연결

```bash
flutter build web --release \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=https://<apprunner-domain>/v1
```

지도 핀은 프론트 카카오맵 **JS SDK**(JS키 + 도메인 등록) 담당. 백엔드는 좌표+정보만 제공한다.

**운영 체크리스트 — 카카오 JavaScript 키 허용 도메인(#2913).** `KAKAO_JS_KEY` 는 웹 빌드에 들어가
브라우저에 그대로 보인다. 키를 지키는 것은 카카오 개발자 콘솔의 **JavaScript SDK 도메인** 목록뿐이다.
배포·도메인을 바꿀 때마다 아래를 확인한다.

- 목록에 운영 회원 웹·트레이너 웹 주소만 있는가(`https://` 포함, 경로 없이 출처 단위).
- 개발용 주소(`localhost` 등)·옛 배포 주소·임시 미리보기 주소가 남아 있지 않은가. 로컬 개발이
  필요하면 운영 키가 아닌 개발용 앱 키를 따로 쓴다.
- 확인한 날짜와 결과를 담당 이슈에 남긴다.

---

## 마이그레이션 head 선형화 (머지 순서 주의)

병렬 브랜치가 같은 부모에서 각자 새 마이그레이션을 만들면 Alembic head 가 여러 개가 되어
`alembic upgrade head` 가 실패한다. 현재는 아래처럼 **단일 선형 체인**으로 정리돼 있다:

```
0009_diet_idempotency_key → 0010_diet_entry_macros(#207) → 0011_health_daily_sugar_g(#231)
                          → 0012_trainer_domain(트레이너 도메인) → 0013_trainer_active_coach_uq(active 담당 unique index)
                          → 0014_consultation_requests ─┐
                          → 0014_drop_trainer_prof_ix ──┴→ 0015_merge_alembic_heads
                          → 0016_drop_vitals → 0017_add_diet_exercise_goals
                          → 0018_diet_entry_sugar_g_float → 0019_trainer_noti_settings
                          → 0020_gym_profiles_trainer_fk
```

**원칙**: 나중에 머지되는 마이그레이션의 `down_revision` 을 현재 main head 로 맞춰 한 줄로 잇는다
(파일명 숫자도 위치에 맞게). 트레이너 스택은 위 순서대로 **가장 마지막**에 머지한다.

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
