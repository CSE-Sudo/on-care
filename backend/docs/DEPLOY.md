# 백엔드 배포 가이드 — Amazon ECS Express Mode + Neon(pgvector)

컨테이너 + Postgres(pgvector) 구조라 컴퓨트는 **Amazon ECS Express Mode**(Fargate·ALB·HTTPS
주소를 서비스 하나로 만들어 준다), DB 는 **Neon Postgres(pgvector)** 를 쓴다(#3016). App Runner 는
신규 고객을 받지 않고 ECS Express Mode 로 옮기기를 권하므로
([App Runner availability change](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html))
대상에서 뺐다. 리전은 Neon DB 와 같은 `ap-southeast-1` 이다(아래 "리전"). DB 를 컴퓨트와 분리해
두었으므로 컴퓨트를 바꿔도 `DATABASE_URL` 을 그대로 옮기면 된다.

배포는 ECS 전용 배포 action 대신 **서비스 스택(CloudFormation)의 이미지 파라미터만 바꾸는 방식**으로 한다.
서비스를 스택과 action 이 함께 고치면 스택이 실제 서비스와 어긋나(drift) 다음 스택 적용이 배포를 되돌리기
때문이다.

배포가 켜져 있으면(저장소 변수 `BACKEND_DEPLOY_ENABLED=true`) `main` 의 Backend CI 가 성공할 때
그 커밋 이미지를 ECR 에 한 번 올리고, **staging → production** 순서로 같은 불변 digest 를 배포한다
(`.github/workflows/backend-deploy.yml`). 변수가 없거나 `true` 가 아니면 배포 잡은 전부 건너뛴다.

```
GitHub(main push) ─> Backend CI ─> backend-deploy.yml
   build  : 이미지 푸시 역할(브랜치 OIDC) ─> ECR oncare-backend:<sha> ─> digest
   staging: Environment "staging"    ─> 배포 역할 ─> CloudFormation ─> oncare-backend-staging
   prod   : Environment "production" ─> 배포 역할 ─> CloudFormation ─> oncare-backend-production
                                                                 │  (ALB → Fargate :8000)
                                                                 └── Neon Postgres (CREATE EXTENSION vector)
```

기동 흐름: 컨테이너가 `scripts/start.sh` 로 **마이그레이션 → uvicorn(--proxy-headers --no-access-log)**.
마이그레이션은 `scripts/migrate.py` 가 **PostgreSQL advisory lock 으로 직렬화**하므로, 배포 중 새
태스크와 옛 태스크가 잠깐 함께 떠도 하나만 마이그레이션하고 나머지는 대기 후 no-op 이다(리뷰 #3).
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
> 데이터가 쌓인 뒤 120초를 넘길 수 있는 마이그레이션을 배포하기 전에는, 동시에 뜬 다른 태스크가
> fail-fast·재시작 루프에 빠지지 않도록 서비스 템플릿의 이 값을 넉넉히(예: `600`) 올려 둔다.

## 0) 구성 요약

| 스택 | 템플릿 | 개수 | 비용 | 내용 |
|---|---|---|---|---|
| `oncare-backend-bootstrap` | `infra/backend-bootstrap.yml` | 계정에 1개 | 없음(이미지 저장량만) | ECR `oncare-backend`(불변 태그, 최근 20개 유지), 이미지 푸시 역할 |
| `oncare-backend-env-<environment>` | `infra/backend-environment.yml` | 환경마다 1개 | 없음 | 첨부 버킷, 태스크·실행·인프라 역할, CloudFormation 서비스 역할, GitHub 배포 역할 |
| `oncare-backend-<environment>` | `infra/backend-service.yml` | 환경마다 1개 | **생성 순간부터 과금** | ECS Express Mode 서비스(Fargate 태스크 1개 + ALB) |

`<environment>` 는 `production`·`staging` 이다. staging 은 데모 시연용이고 **운영과 다른 DB·비밀·버킷**을
쓴다(#3020). staging 이 필요 없으면 staging 스택을 만들지 않고 `BACKEND_STAGING_DEPLOY_ENABLED` 를 비워 둔다.

**태스크는 1개로 고정한다.** 로그인 실패 잠금·가입 상한 같은 시도 제한이 프로세스 메모리에 있어
(`app/core/rate_limit.py`) 태스크가 늘면 한도가 그만큼 느슨해진다. 템플릿은 `MinTaskCount`·
`MaxTaskCount` 를 `1` 만 받는다. 늘리려면 먼저 시도 제한을 공유 저장소(Redis 등)로 옮긴다.

**서비스 설정의 원본은 템플릿과 스택 파라미터다.** 콘솔에서 서비스를 직접 고치면 다음 배포가
템플릿 값으로 되돌린다. 설정을 바꿀 때는 `infra/backend-service.yml` 을 PR 로 고치거나 스택
파라미터를 바꿔 스택을 다시 적용한다. 배포 워크플로는 `ImageIdentifier` 파라미터 하나만 바꾼다.

## 1) 권한 구조 (#3019)

| 주체 | 믿는 OIDC subject | 할 수 있는 일 |
|---|---|---|
| 이미지 푸시 역할(bootstrap) | `repo:…:ref:refs/heads/main` | ECR `oncare-backend` 에 이미지 푸시·digest 조회만 |
| 배포 역할(env, 환경마다) | `repo:…:environment:<environment>` | 그 환경 서비스 스택의 변경 세트 생성·실행, CloudFormation 서비스 역할 넘기기만 |
| CloudFormation 서비스 역할(env) | — (cloudformation.amazonaws.com) | ECS Express 서비스 갱신, 태스크·실행·인프라 역할 넘기기 |
| 태스크 역할(env) | — (ecs-tasks) | 그 환경 첨부 버킷의 `<접두사>/*` 읽기·쓰기·지우기와 접두사 목록 |
| 실행 역할(env) | — (ecs-tasks) | 이미지 pull, 로그, `oncare/backend/<environment>-*` 비밀 읽기 |

- 배포 역할은 **GitHub Environment 에서 돈 job 만** 맡을 수 있다. 브랜치 형식 토큰으로는 서비스를
  바꿀 수 없으므로 Environment 의 승인 규칙을 건너뛰는 길이 없다.
- 배포 역할에는 ECS·IAM 권한이 없다. 서비스 변경은 CloudFormation 이 서비스 역할로 한다.
- 저장소에는 이미 `Production`·`Preview`·`github-pages` Environment 가 있다. Environment 이름은
  대소문자를 가리지 않으므로 `Production` 이 곧 `production` 이다.

**GitHub Environment 설정**(Settings > Environments)

| Environment | 보호 규칙 | 배포 브랜치 | 변수 |
|---|---|---|---|
| `production` | Required reviewers(운영 승인자), 필요하면 대기 시간 | `main` 만 | `AWS_BACKEND_DEPLOY_ROLE_ARN`·`AWS_BACKEND_CFN_ROLE_ARN`·`BACKEND_STACK_NAME` |
| `staging` | 없음(자동) | `main` 만 | 같은 세 변수(staging 스택 출력값) |

프런트 AWS 배포(`aws-frontend-deploy.yml`)도 `production` Environment 에서 돈다. 그래서 운영 승인자를
걸면 프런트 배포도 같은 승인을 기다린다.

**저장소 변수**(Settings > Secrets and variables > Actions > Variables)

| 저장소 변수 | 값 | 없으면 |
|---|---|---|
| `BACKEND_DEPLOY_ENABLED` | `true` | 배포 잡 전부 skipped |
| `BACKEND_STAGING_DEPLOY_ENABLED` | `true` | staging 을 건너뛰고 바로 운영(승인 뒤) |
| `AWS_BACKEND_REGION` | 예: `ap-southeast-1` | `ap-southeast-1` |
| `AWS_BACKEND_IMAGE_PUSH_ROLE_ARN` | bootstrap 스택 출력 `GitHubImagePushRoleArn` | build 잡 실패 |
| `STAGING_API_BASE_URL` | `https://<staging 주소>/v1` | 데모 사이트 real 빌드 실패(#3020) |

App Runner 시절의 `AWS_DEPLOY_ROLE_ARN`·`APPRUNNER_SERVICE_ARN` 시크릿과 `BACKEND_EXPECTED_ENV`
변수는 더 이상 읽지 않는다. 기대 환경은 Environment 이름으로 정해진다(production → `prod`,
staging → `staging`).

## 2) 배포 게이팅과 흐름

- 배포는 **"Backend CI" 가 성공**했을 때만(workflow_run) 실행되며, 자동 배포는 **동일 저장소의 `main`
  push** 에서 발생한 성공 run 만 허용한다. PR·fork 등 다른 이벤트의 CI 결과로는 배포할 수 없다.
  Backend CI 는 `alembic heads` 가 **정확히 1개**인지 검사해 마이그레이션 head 분기를 막는다.
- 배포는 `concurrency` 로 한 번에 하나만 돈다.
- **build**: 커밋 SHA 태그(`oncare-backend:<sha>`)로 한 번 빌드·푸시하고 digest 를 얻는다. 같은 커밋을
  다시 배포하면(되돌리기 포함) 새로 빌드하지 않고 있는 이미지의 digest 를 쓴다. 빌드 때
  `--build-arg GIT_SHA=<sha>` 를 넘겨 이미지가 자기 커밋을 품는다 — `/v1/version`·`/v1/healthz` 의
  `commit_sha` 와 Sentry release(`oncare-backend@<APP_VERSION>+<SHA 앞 12자>`)가 이 값을 쓴다(#3029).
- **deploy-staging**(`BACKEND_STAGING_DEPLOY_ENABLED=true` 일 때) → **deploy-production**. staging 이
  실패·취소되면 운영으로 가지 않는다. 두 환경은 같은 digest 를 쓴다.
- 각 환경 배포(`backend-deploy-service.yml`)는
  1. 스택이 지금 선언한 이미지(되돌릴 지점)를 기록하고,
  2. `aws cloudformation deploy --role-arn <서비스 역할>` 로 `ImageIdentifier` 만 바꾸고,
  3. `/v1/healthz` 가 그 환경의 기대 설정인지(아래 표), `/v1/readyz` 로 **DB 까지 닿는지**, `/v1/version`
     의 `commit_sha` 가 배포한 커밋과 같은지 확인한다(`.github/scripts/backend_verify_service.sh`). healthz·
     version 판정은 `.github/scripts/verify_backend_health.sh`(#3029)와 같은 규칙이고, 필드가 없거나
     다르면 실패다. PR 게이트·Infra CI 가 두 스크립트의 경계를 시험한다.
  4. 검증에서 떨어지면 **직전 digest 로 스택을 되돌리고** 다시 검증한다. 잡은 실패로 남는다.

| healthz 필드 | production | staging |
|---|---|---|
| `env` | `prod` | `staging` |
| `demo_fallback` | `false` | 무엇이든(기록만) |
| `demo_seed` | `false` | 무엇이든(기록만) |
| `attachment_storage` | `s3` | `s3` |

서비스 헬스체크 경로는 계속 healthz 다 — DB 일시 장애로 태스크를 갈아 치우지 않게 프로세스 생존만 본다.

**수동 실행**(workflow_dispatch)도 `BACKEND_DEPLOY_ENABLED=true` 가 필요하고 CI 게이트를 우회하지
않는다. `main` 에서 실행하며 40자리 커밋 SHA 와 대상(`all`·`staging`·`production`)을 고른다. 워크플로가
GitHub Actions API 에서 그 SHA 의 `main` push 에 대한 Backend CI 성공 기록을 확인한 뒤에만 배포한다.

### 되돌리기

- **자동**: 위 4단계. 스택 갱신 자체가 실패하면 CloudFormation 이 스스로 직전 상태로 돌아간다.
- **수동**: 되돌릴 커밋(이미 CI 를 통과한 `main` 커밋)의 SHA 로 workflow_dispatch 를 실행한다.
  ECR 에 그 이미지가 남아 있으면(최근 20개) 다시 빌드하지 않는다. 대상은 보통 `production`.
- **마이그레이션은 되돌리지 않는다.** 그래서 **마이그레이션 호환 규칙**을 지킨다 — 한 배포의 스키마
  변경은 **직전 이미지와도 함께 돌 수 있어야** 한다. 칸·표를 지우거나 이름을 바꿀 때는 (1) 새 코드가
  옛 칸을 더 이상 읽지 않게 배포하고 (2) 다음 배포에서 지운다. NOT NULL 칸을 더할 때는 기본값을 함께 둔다.

## 3) 처음 만들기 (#480)

순서대로 한 번씩. 1~2 와 4 는 비용이 없고, **5 부터 과금된다.**

1. **bootstrap 스택**(계정에 한 번):

   ```bash
   aws cloudformation deploy \
     --template-file infra/backend-bootstrap.yml \
     --stack-name oncare-backend-bootstrap \
     --capabilities CAPABILITY_IAM \
     --parameter-overrides \
       ExistingGitHubOidcProviderArn=arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com \
     --region ap-southeast-1
   ```

   App Runner 용으로 이미 만든 bootstrap 스택이 있으면 같은 명령으로 갱신한다 — App Runner ECR 액세스
   역할과 App Runner 권한이 지워지고 이미지 푸시 역할이 생긴다. ECR 저장소는 그대로 남는다.
   출력 `GitHubImagePushRoleArn` → 저장소 변수 `AWS_BACKEND_IMAGE_PUSH_ROLE_ARN`.
2. **환경 스택**(환경마다):

   ```bash
   aws cloudformation deploy \
     --template-file infra/backend-environment.yml \
     --stack-name oncare-backend-env-production \
     --capabilities CAPABILITY_IAM \
     --parameter-overrides \
       EnvironmentName=production \
       ExistingGitHubOidcProviderArn=arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com \
     --region ap-southeast-1
   ```

   출력 `GitHubDeployRoleArn`·`CloudFormationDeployRoleArn`·`ServiceStackName` → 그 Environment 의 변수
   `AWS_BACKEND_DEPLOY_ROLE_ARN`·`AWS_BACKEND_CFN_ROLE_ARN`·`BACKEND_STACK_NAME`.
3. **비밀**: Secrets Manager 에 `oncare/backend/<environment>` 이름으로 JSON 비밀을 만든다(아래 5절 "비밀 키").
   전체 ARN(끝 6자 접미사 포함)을 적어 둔다.
4. **GitHub Environment** `production`·`staging` 의 보호 규칙·배포 브랜치·변수를 1절 표대로 둔다.
5. **서비스 스택**(환경마다, 여기서부터 과금). 첫 이미지는 이미 CI 를 통과한 `main` 커밋으로 build 잡만
   돌려 얻거나(`BACKEND_DEPLOY_ENABLED=true` 후 수동 실행 — 서비스 스택이 없으면 build 뒤 배포 잡이
   "스택이 없습니다" 로 멈춘다), 로컬에서 같은 Dockerfile 로 올린다.

   ```bash
   aws cloudformation deploy \
     --template-file infra/backend-service.yml \
     --stack-name oncare-backend-production \
     --parameter-overrides \
       EnvironmentName=production \
       ImageIdentifier=<ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/oncare-backend@sha256:<digest> \
       SecretArn=<3단계 비밀 ARN> \
       CorsAllowOrigins=https://<회원 앱 도메인>,https://<트레이너 웹 도메인> \
       GeminiModel=<고정 모델 이름> \
     --region ap-southeast-1
   ```

   출력 `ServiceEndpoint`(`<서비스 이름>.ecs.<리전>.on.aws` 형식)가 API 호스트다. 운영 프런트 저장소 변수
   `API_BASE_URL` 은 `https://<운영 주소>/v1`, staging 은 `STAGING_API_BASE_URL` 에 넣는다.
6. 저장소 변수 `BACKEND_DEPLOY_ENABLED=true`(staging 을 쓰면 `BACKEND_STAGING_DEPLOY_ENABLED=true`).
   다음 `main` 병합부터 자동으로 배포된다.

선택 파라미터: `Cpu`(기본 1024)·`Memory`(기본 2048), `AdminEmails`, `AppleClientIds`·`GoogleClientIds`·`KakaoAppId`(#3035), 메일
(`MailFrom`·`SmtpHost`·`SmtpPort`·`PasswordResetMemberUrl`·`PasswordResetTrainerUrl`), staging 전용
`AllowDemoFallback`, 기본 VPC 가 아닌 곳에 둘 때 `SubnetIds`·`SecurityGroupIds`.

## 4) Neon Postgres (pgvector)

- Neon 프로젝트를 만들고 DB 를 생성한 뒤 pgvector 확장을 1회 활성화한다:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

- 접속은 공용 엔드포인트 + TLS 라 서비스에 별도 네트워크 설정이 필요 없다(태스크는 공인 서브넷에서 나간다).
- `DATABASE_URL` 은 Neon 이 준 문자열(`sslmode=require` 등 쿼리 파라미터 포함)을 **그대로** 넣어도 된다.
  `config.sqlalchemy_database_url` 이 bare `postgresql://` 를 `postgresql+psycopg://` 로 정규화한다.
- **풀러(`-pooler`) 엔드포인트가 아니라 직접 엔드포인트를 쓴다.** 기동 시 마이그레이션이
  `pg_try_advisory_lock`(세션 단위 lock, `scripts/migrate.py`)으로 태스크를 직렬화하는데,
  트랜잭션 풀링을 거치면 lock 을 잡은 세션과 alembic 이 쓰는 세션이 달라질 수 있어 직렬화가 깨진다.
- 운영과 staging 은 **다른 DB**(또는 Neon 브랜치)를 쓴다.

## 5) 환경변수 / 비밀

서비스 템플릿이 넣는 키 전체와 값은 `backend/.env.aws.example` 에 있다. 키 목록은 템플릿과 같고
`tests/test_deploy_template.py` 가 둘이 어긋나거나 Settings 에 없는 키가 들어가면 잡는다.

**비밀 키** — Secrets Manager `oncare/backend/<environment>` JSON 의 키. 쓰지 않는 키도 빈 문자열로
만들어 둔다(없는 키를 참조하면 태스크가 뜨지 않는다).

| 키 | 값 | 필수 |
|---|---|---|
| `DATABASE_URL` | 그 환경 DB 의 직접 엔드포인트 | 예 |
| `JWT_SECRET` | `openssl rand -hex 32`. **환경마다 다르게**. 32바이트 미만이면 운영 기동 거부(#3029) | 예 |
| `GEMINI_API_KEY` | 사진 인식·임베딩. 운영은 없으면 기동 거부(#2812). **결제가 연결된 프로젝트의 키(유료 등급)만**(#3032) — 무료 등급은 입력(회원 음식 사진·건강 기록·코치 대화)이 제공자의 서비스 개선에 쓰일 수 있고 한도가 낮다. 결제 연결은 #480 | 예 |
| `KAKAO_REST_API_KEY` | 장소 실검색. 빈 값이면 헬스장 찾기가 사실상 빈다(시드로 채우지 않음, #2914) | 키는 있어야 함 |
| `SENTRY_DSN` | 오류 수집(#2839). 빈 값이면 꺼짐 | 키는 있어야 함 |
| `SMTP_USERNAME`·`SMTP_PASSWORD` | `MailFrom` 파라미터를 채웠을 때만 읽는다 | 메일을 켤 때 |
| `DEMO_LOGIN_PASSWORD` | staging 만. 강한 값 | staging |

**템플릿이 고정하는 값** — 바꾸려면 템플릿 PR.

| 키 | 값/설명 |
|---|---|
| `ENV` | production `prod`, staging `staging` (fail-fast 하드닝은 `prod` 에서만). **비우면 컨테이너가 뜨지 않는다**(`scripts/start.sh`, #2821) |
| `SEED_DEMO_DATA` | production `false`, staging `true` |
| `ALLOW_DEMO_FALLBACK` | production `false`, staging 은 파라미터 `AllowDemoFallback` |
| `AUTO_CREATE_TABLES` | `false` (Alembic 이 정답) |
| `TZ` | `Asia/Seoul` (오늘/어제 라벨 KST 기준) |
| `FORCE_HTTPS`·`LOG_LEVEL` | `true`·`INFO` |
| `TRUSTED_PROXY_HOPS` | `1` — ALB 하나 뒤다(#2815) |
| `WEB_CONCURRENCY` | `1` (아래 "워커 수") |
| `ATTACHMENT_STORAGE`·`ATTACHMENT_S3_*` | `s3`, 환경 스택 버킷, 서비스 리전, `chat-attachments` |
| `RECOGNIZER`·`COACH_LLM`·`EMBEDDER` | `gemini` |
| `GEMINI_TIMEOUT_SECONDS`·`RECOGNIZER_TIMEOUT_SECONDS` | `30`·`60`(#2912) |
| `EMBED_DIM` | `768` |
| `MIGRATE_LOCK_TIMEOUT`·`MIGRATE_LOCK_RETRY_INTERVAL`·`MIGRATE_CONNECT_TIMEOUT` | `120`·`2`·`10`(#2912) |
| `SECURITY_HEADERS`·`RATE_LIMIT_ENABLED` | `true`·`true` — 끄면 보안 헤더·시도 제한이 빠진다 |
| `GYM_BENEFITS_ENABLED`·`EXPOSE_API_DOCS` | `false`·`false` — 제휴 헬스장 전까지 혜택을 닫고(#2822) 운영 API 문서를 닫는다(#2834) |
| `PLACES_PROVIDER` | `auto` — `KAKAO_REST_API_KEY` 가 있으면 카카오(#2914) |
| `ACCESS_TOKEN_EXPIRE_MINUTES`·`REFRESH_TOKEN_EXPIRE_DAYS`·`WEB_REFRESH_TOKEN_EXPIRE_DAYS` | `60`·`30`·`7`(#2913·#2828) — 데모 서비스에서 길게 바꾼 값이 운영으로 복사되지 않게 |
| `AUDIT_RETENTION_DAYS`·`AUDIT_SENSITIVE_RETENTION_DAYS` | `365`·`730`(#2830) — 처리방침 보관 기간과 묶여 있다 |
| `MAIL_PROVIDER`·`SMTP_STARTTLS`·`SMTP_SSL` | `smtp`·`true`·`false` — `MailFrom` 파라미터를 채웠을 때만 들어간다(#3033). `smtp` 라 서버·발신 주소가 비면 기동이 거부돼 빠뜨린 것이 바로 드러난다. 587 STARTTLS 기준 |
| `GOOGLE_CLIENT_IDS`·`KAKAO_APP_ID`·`APPLE_CLIENT_IDS` | 스택 파라미터(`GoogleClientIds`·`KakaoAppId`·`AppleClientIds`). 소셜 로그인 허용 `aud`(#3035) — Google 은 iOS·Android·웹 client_id(콤마 구분), 카카오는 콘솔의 숫자 앱 ID(`KAKAO_REST_API_KEY` 와 다른 값), Apple 은 번들 ID·Service ID. **비우면 그 로그인은 401 로 거부**. 네이버 로그인은 서버 측 코드 교환 전까지 501 로 닫혀 있어 설정이 없다 |
| `AI_GLOBAL_CALLS_PER_DAY`·`TRAINER_AI_CALLS_PER_DAY`·`LLM_MAX_OUTPUT_TOKENS` | `0`·`200`·`4096`(#3032) — 서버 전체 하루 AI 호출 합(DB 에서 KST 날짜로 셈, 0 이면 끔, 넘으면 폴백이 있는 기능은 규칙형 폴백·AI 코치 채팅·사진 분석은 503 `ai_capacity` + `Retry-After`)·트레이너 한 계정 하루 AI 호출(넘으면 429 `daily_limit`)·호출 한 번의 출력 토큰 천장. 출시 전 `AI_GLOBAL_CALLS_PER_DAY` 를 공급자 하루 예산 ÷ 호출당 비용으로 바꾼다(#480) |

위 값 중 코드 기본값과 같은 것도 템플릿에 못 박는다(#3034) — 데모 서비스에서 바꾼 값이 운영으로
복사되지 않게 하고, 운영에서 무엇이 들어가는지 `.env.aws.example` 한 곳에서 보이게 한다.

**메일·재설정 값**(#3033)

| 키 | 설명 |
|---|---|
| `MAIL_FROM` | 발신 주소(`no-reply@<운영 도메인>` 또는 `OnCare <no-reply@…>`). 업체·도메인 인증은 #480 |
| `SMTP_HOST`·`SMTP_PORT` | 업체 SMTP 엔드포인트(SES 는 `email-smtp.<리전>.amazonaws.com`)·`587` |
| `SMTP_USERNAME`·`SMTP_PASSWORD` | SMTP 자격 증명. 비밀 JSON 에 넣는다(SES 는 IAM 에서 만든 SMTP 자격 증명, #480) |
| `PASSWORD_RESET_MEMBER_URL` | 회원 앱 재설정 화면 — **해시형** `https://<운영 도메인>/frontend/#/auth/password-reset`. 서버가 `…#/auth/password-reset?token=…` 꼴로 토큰을 붙인다. 비우면 메일에 코드만 보낸다 |
| `PASSWORD_RESET_TRAINER_URL` | 트레이너 웹 재설정 화면 — **해시형** `https://<운영 도메인>/trainer/#/auth/password-reset`. 해시 없는 경로형(`/auth/password-reset`)은 정적 경로를 가리켜 코드가 버려진다. 운영에서 경로형·`http://` 면 기동 로그에 WARN(#3033) |

**스택 파라미터로 정하는 값**: `CORS_ALLOW_ORIGINS`(https 만, `*`·빈 값·localhost 금지 — 운영 기동 거부, #3029), `GEMINI_MODEL`(아래 5-3),
`ADMIN_EMAILS`, 소셜 로그인 `aud`(`APPLE_CLIENT_IDS`·`GOOGLE_CLIENT_IDS`·`KAKAO_APP_ID` — 비우면 그 로그인은 401, #3035), 메일(`MAIL_FROM`·`SMTP_HOST`·`SMTP_PORT`·`PASSWORD_RESET_*_URL`).

그 밖의 키(`LOGIN_MAX_FAILURES` 같은 시도 제한·`SENTRY_ENVIRONMENT`·DB 풀 등)는 코드 기본값이 운영 값이라
템플릿에 넣지 않았다(사유는 `tests/test_env_aws_example.py`, #3034). 바꿔야 하면 템플릿에 키를 더하고
`.env.aws.example` 에서 그 키의 주석을 푼다. 전체 키와 기본값은 `backend/.env.example` 이
`config.py` 와 1:1 로 갖고 있다(`tests/test_env_example.py`).

> **시도 제한은 태스크 메모리에 둔다**(`app/core/rate_limit.py`). 태스크가 1 이 아니게 되거나
> `WEB_CONCURRENCY` 를 늘리면 한도가 그 수만큼 늘어나므로, 그때 공유 저장소(Redis 등) 구현으로 바꾼다.
> 기동 로그에 `TRUSTED_PROXY_HOPS=0` 경고가 보이면 프록시 홉 수 설정을 확인한다.
> 기동 로그에 `소셜 로그인 허용 앱 설정이 비어` 경고가 보이면, 거기 적힌 provider 의 로그인은 모두 401 이다.

> 참고: 장소는 시드로 채우지 않는다(#2914). 운영에서 `KAKAO_REST_API_KEY` 가 없으면 DB 장소에서 데모 시드 장소를 빼고 읽어 헬스장 찾기가 사실상 비고, 키가 있어도 카카오 0건이면 빈 목록·실패면 503 이다. 사진 인식·임베딩은 운영에서 폴백하지 않고 키가 없으면 기동을 거부한다(#2812).

**운영에서 기본값을 그대로 두면 안 되는 키** — 기동은 되지만 개발용 동작이 남는다(#2840).
전체 키와 기본값·운영 권장값은 `backend/.env.example` 이 `config.py` 와 1:1 로 갖고 있다
(`tests/test_env_example.py` 가 빠진 키를 잡는다).

| 키 | 운영 값 | 기본값 그대로면 |
|---|---|---|
| `FORCE_HTTPS` | `true` | HTTP 요청이 HTTPS 로 넘어가지 않는다 |
| `ALLOW_DEMO_FALLBACK` | `false` | `ENV=prod` 면 어차피 꺼지지만, 스테이징·시연 서버를 `ENV=dev` 로 띄우면 토큰 없는 요청이 데모 계정으로 처리된다 |
| `ADMIN_EMAILS` | 운영 담당자 이메일(콤마 구분) | 관리자가 없어 공공 RAG 문서 적재·`/v1/system/metrics` 를 쓸 수 없다 |
| `REPORT_PDF_STORAGE_DIR`·`CHAT_IMAGE_STORAGE_DIR` | 쓰지 않음 | 운영 첨부는 S3(`ATTACHMENT_STORAGE=s3`, 아래 5-1, #2817)다. 로컬 디스크로 두면 컨테이너 안 `data/` 에 쌓여 재배포·재시작 때 주간 리포트 PDF·채팅 사진이 사라진다 |
| `SECURITY_HEADERS`·`RATE_LIMIT_ENABLED` | `true`(기본값 유지) | 끄면 보안 헤더·시도 제한이 빠진다 |
| `LOG_LEVEL` | `INFO` | — |

## 워커 수와 이벤트 루프 (#2835)

- `WEB_CONCURRENCY` 로 uvicorn 워커 수를 정한다(`scripts/start.sh`, 기본 `1`, 1 이상 정수가
  아니면 기동 거부). 운영 값은 서비스 템플릿이 `1` 로 고정한다(#3016).
- 워커를 늘릴 때의 영향:
  - **인메모리 분당 한도**(로그인·AI 코치·사진 분석 분당 한도 등)는 워커마다 따로 센다 — 워커 N 개면
    한 사용자가 최대 N 배까지 통과할 수 있다. DB 에서 세는 하루 상한(AI 챗봇·사진 분석)은 영향 없다.
  - **`/v1/system/metrics`** 는 그 요청을 받은 워커 하나의 값만 보여 준다(합산되지 않는다).
  - **DB 연결 수**가 워커 수만큼 곱해진다(아래 계산식).
- `async def` 라우트 안에서 동기 DB·Pillow·파일 저장을 돌리지 않는다 — 이벤트 루프가 막혀 같은 워커의
  다른 요청(헬스체크 포함)이 모두 멈춘다. 외부 호출만 `await` 하고 나머지는 `run_in_threadpool` 로
  넘기거나 라우트를 `def` 로 둔다. `tests/test_async_route_guard.py` 가 이 규칙을 검사한다.

## 요청 로그 (#3031)

컨테이너 표준 출력(ECS 태스크 → CloudWatch Logs)에 남는 요청 로그는 앱의 `app.access` 한 곳이다 —
`GET '/v1/places/nearby' -> 200 (12.3ms)` 처럼 method·경로(쿼리 제외)·상태·소요시간과 줄 앞의
request_id 만 남긴다. uvicorn 기본 액세스 로그는 `scripts/start.sh` 가 `--no-access-log` 로 끈다.
그 로그는 쿼리를 포함한 요청 줄 전체와 프록시 헤더로 읽은 사용자 IP 를 남겨, 헬스장 찾기의
위치 좌표(`lat`·`lng`)·검색어가 IP 와 함께 쌓이기 때문이다(처리방침은 위치를 "저장 안 함"으로 적는다).
Backend CI 가 컨테이너를 띄워 좌표 쿼리 요청 뒤 로그에 좌표·IP 가 없는지 확인한다. 로그 그룹의
보관 기간·열람 권한은 인프라 설정(#480)이다.

## DB 커넥션 풀·쿼리 실행 상한 (#2836)

| 키 | 기본값 | 설명 |
|---|---|---|
| `DB_POOL_SIZE` | `5` | 워커 하나가 유지하는 연결 수 |
| `DB_MAX_OVERFLOW` | `10` | 붐빌 때 잠깐 더 여는 연결 수 |
| `DB_POOL_TIMEOUT_SECONDS` | `10` | 풀이 말랐을 때 기다리는 상한. 기본값(30초)보다 짧게 실패시켜 클라이언트 재시도로 넘긴다 |
| `DB_POOL_RECYCLE_SECONDS` | `300` | 유휴 연결 재활용 주기. 관리형 DB 가 유휴 연결을 먼저 끊는 시간보다 짧게 둔다 |
| `DB_STATEMENT_TIMEOUT_MS` | `10000` | 쿼리 하나의 실행 상한. 연결 시작 옵션(`-c statement_timeout`)으로 건다. `0` 이면 끈다 |

- **연결 수 계산:** `(DB_POOL_SIZE + DB_MAX_OVERFLOW) × WEB_CONCURRENCY × 태스크 수` 가 DB 플랜의
  동시 연결 상한보다 작아야 한다. 기본값·워커 1·태스크 1 이면 최대 15 다(배포 중 옛 태스크와 겹치는 동안은 두 배). 마이그레이션은 기동 때
  별도 연결 하나를 잠깐 더 쓴다.
- 실행 상한은 앱 엔진에만 걸린다. 마이그레이션(`scripts/migrate.py`·Alembic)은 자기 엔진을 쓰므로 긴
  DDL 이 끊기지 않는다. readiness(`/readyz`)는 따로 3초 상한을 건다.
- 시작 옵션을 받지 않는 풀러 엔드포인트(PgBouncer 등)로 바꾸면 연결이 거부된다 — 그때는
  `DB_STATEMENT_TIMEOUT_MS=0` 으로 끄고 DB 역할 쪽에 상한을 건다. 지금은 직접 엔드포인트를 쓴다.
- AI 코치 채팅·홈 코칭은 LLM 응답을 기다리기 전에 읽기 트랜잭션을 끝내 연결을 풀로 돌려준다 —
  LLM 대기(수 초~수십 초) 동안 연결을 쥐지 않는다.
- 풀 상태는 관리자 전용 `GET /v1/system/metrics` 의 `db_pool`(`size`·`checked_out`·`overflow`)로
  본다. `checked_out` 이 자주 `size + max_overflow` 에 닿으면 풀을 키우거나 느린 경로를 찾는다.

## 5-1) 채팅 첨부 저장소 — S3 (#2817)

채팅 사진과 주간 리포트 PDF 의 **바이트**는 DB 가 아니라 저장소에 둔다(메타데이터만 DB).
Fargate 태스크의 디스크는 재배포·재시작 때 비므로 운영은 S3 버킷을 쓴다. 버킷은 환경 스택이
환경마다 하나씩 만들고(`oncare-attachments-<계정>-<리전>-<environment>`), 서비스 템플릿이 이름을 넣는다. 로컬 개발·테스트는 지금처럼 디스크(`data/chat-images`,
`data/report-pdfs`)에 쓴다.

| 키 | 값/설명 |
|---|---|
| `ATTACHMENT_STORAGE` | `auto`(기본: 버킷 이름이 있으면 `s3`, 없으면 `local`) · `local` · `s3`. `s3` 인데 버킷이 비면 기동 거부 |
| `ATTACHMENT_S3_BUCKET` | 첨부 버킷 이름. 비면 로컬 디스크 — 운영(`ENV=prod`)이면 기동 거부, 스테이징이면 기동 때 WARN(#3029) |
| `ATTACHMENT_S3_REGION` | 버킷 리전. 비면 AWS 기본 체인(서비스 리전) |
| `ATTACHMENT_S3_PREFIX` | 키 접두사(기본 `chat-attachments`). 키는 `<접두사>/chat-images/<id>.<ext>`·`<접두사>/report-pdfs/<id>.pdf` |
| `ATTACHMENT_S3_ENDPOINT_URL` | S3 호환 저장소를 쓸 때만. AWS 는 비운다 |

- **자격 증명은 환경변수로 주지 않는다.** 환경 스택의 **태스크 역할**이 버킷 권한을 갖는다:
  `s3:PutObject`·`s3:GetObject`·`s3:DeleteObject`(리소스 `arn:aws:s3:::<버킷>/<접두사>/*`)와
  `s3:ListBucket`(리소스 `arn:aws:s3:::<버킷>`, 조건 `s3:prefix` = `<접두사>/*`).
  **`ListBucket` 을 빼면 안 된다** — 없으면 S3 가 없는 키에 404 대신 403 을 주어, 사진의
  확장자를 차례로 찾는 조회와 이전 스크립트의 존재 확인이 저장소 장애로 읽힌다.
- 버킷은 **퍼블릭 접근 차단**을 켠다(환경 스택이 켜고, TLS 가 아닌 요청은 버킷 정책으로 막는다). 다운로드는 늘 백엔드가 권한(스레드의 두 사람·담당 링크·
  동의)을 확인한 뒤 흘려보내므로 버킷을 공개할 이유가 없다. 서명 URL 도 쓰지 않는다.
- 기본 암호화(SSE-S3)를 켜 둔다. 버전 관리를 켜면 탈퇴로 지운 객체가 이전 버전으로 남으니,
  켤 경우 **이전 버전 만료 수명 주기 규칙**(예: 30일)을 함께 건다.
- 탈퇴 시 그 계정이 낀 스레드의 첨부를 지운다. 삭제 실패는 `탈퇴 첨부 삭제 실패` 경고 로그에
  `file_id` 와 함께 남으니, 로그 알림으로 받아 수동으로 지운다.

### 전환 절차 (로컬 디스크 → S3)

1. 환경 스택을 만든다(위 3절 2단계, #480).
2. 기존 파일이 있는 환경(지금 떠 있는 컨테이너 또는 그 디스크 사본)에서 DB 를 운영 값으로 두고
   이전 스크립트로 옮긴다. **DB 가 가리키는 파일만** 옮기고, 이미 있는 키는 건너뛴다(여러 번 돌려도 같다).

   ```bash
   ATTACHMENT_S3_BUCKET=<버킷> ATTACHMENT_S3_REGION=<리전> \
     python -m scripts.migrate_attachments --dry-run   # 옮길 목록·로컬에 없는 파일 확인
   ATTACHMENT_S3_BUCKET=<버킷> ATTACHMENT_S3_REGION=<리전> \
     python -m scripts.migrate_attachments
   ```

   `DB 에는 있는데 로컬에 없는 파일` 은 이미 재배포로 잃은 파일이라 복구할 수 없다.
3. 서비스 스택으로 배포한다(템플릿이 버킷을 넣는다). 배포 워크플로가 `/v1/healthz` 의
   `attachment_storage` 가 `s3` 인지 확인한다.
4. 대화방에서 예전 사진·리포트가 열리는지 확인한 뒤 컨테이너 쪽 사본을 지운다.

데모 시드 첨부(#2788)는 기동마다 같은 `file_id` 로 다시 쓰므로 옮기지 않아도 된다.

## 5-2) 운영 체크리스트 (#2821, #3020)

배포를 켜기 전에 한 번, 스택 파라미터·비밀을 바꿀 때마다 다시 본다.

- [ ] 서비스 스택이 `infra/backend-service.yml` 로 만들어졌고 `EnvironmentName` 이 맞다.
      `ENV`·`SEED_DEMO_DATA`·`ALLOW_DEMO_FALLBACK`·`AUTO_CREATE_TABLES` 는 템플릿이 정한다.
      `backend/.env.aws.example` 의 주석 키(`# KEY=값`)는 기본값이 이 서비스에 맞는지 확인했다(#3034).
- [ ] 비밀 `oncare/backend/<environment>` 이 위 "비밀 키" 표의 키를 모두 갖는다(빈 값이라도).
- [ ] **비밀번호 재설정 메일이 실제로 온다(#3033).** 회원·트레이너 계정으로 재설정을 한 번씩 요청해 메일을
      받고, 링크를 눌러 두 앱 재설정 화면이 **코드가 채워진 채** 열리는지 본다. 기동 로그에 `PASSWORD_RESET_` WARN 이 없다.
- [ ] **운영 DB 와 staging(데모) DB 가 다르다.** 운영 `DATABASE_URL` 은 데모 시드가 한 번도 들어가지
      않은 DB(또는 Neon 브랜치)를 가리킨다. 같은 DB 를 쓰면 운영 화면에 데모 계정·기록이 섞이고,
      데모 계정 비밀번호가 운영 자격 증명이 된다.
- [ ] `JWT_SECRET` 은 환경마다 다르고(staging 에서 발급한 토큰이 운영에서 통하지 않게) 32바이트 이상이다
      (짧으면 운영 기동 거부, #3029).
- [ ] `CorsAllowOrigins` 는 그 환경의 실제 프런트 도메인(`https://`)만. 비우거나 localhost·`http://`
      출처가 섞이면 운영 기동이 거부된다(#3029).
- [ ] 프런트 저장소 변수 `API_BASE_URL`(운영)과 `STAGING_API_BASE_URL`(데모 사이트 real 빌드)이 다르다.
      같으면 두 프런트 배포 워크플로가 빌드 전에 멈춘다.
- [ ] 배포 뒤 워크플로의 `Verify service` 단계가 통과했다(2절 표 + `/v1/version` 의 `commit_sha` 가
      배포한 커밋). 실패했다면 `Roll back to previous image` 단계 결과와 잡 요약을 본다.
- [ ] 기동 로그에 `[startup]` WARN 이 없다(데모 폴백, staging 의 로컬 첨부 저장소). 운영 데모 시드·운영
      로컬 첨부 저장소는 WARN 이 아니라 기동 거부다.
- [ ] **AI 비용 상한이 정해져 있다(#3032).** `GEMINI_API_KEY` 가 결제가 연결된 프로젝트의 키다
      (무료 등급 금지). 공급자 콘솔에 예산 알림을 걸고, 그 예산으로 `AI_GLOBAL_CALLS_PER_DAY` 를 0 이
      아닌 값으로 둔다. 운영 중에는 `ai_calls.rejected{reason=global_cap}` 메트릭이 늘면 상한이나
      예산을 다시 본다(`backend/README.md` 메트릭 표).

## 5-3) 모델 고정 (#2912)

코드 기본값 `GEMINI_MODEL=gemini-flash-latest` 는 **별칭**이라 제공자가 가리키는 모델을 바꾸면
배포 없이 응답 품질·형식·비용이 바뀐다. 로컬·데모는 별칭으로 두되(핀 모델이 은퇴해 깨지는 일을
피한다), 운영은 고정 버전을 넣는다.

1. 제공자 문서에서 현재 별칭이 가리키는 고정 버전 이름과 은퇴 예정일을 확인한다.
2. staging 서비스 스택의 `GeminiModel` 파라미터를 그 이름으로 바꿔 다시 적용하고 식단 사진 인식·코치
   답변을 확인한다.
3. 운영 서비스 스택의 `GeminiModel` 을 같은 값으로 바꿔 다시 적용한다(이미지는 그대로 —
   `aws cloudformation deploy … --parameter-overrides GeminiModel=<값>`, 나머지 파라미터는 직전 값).
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

백엔드는 `ap-southeast-1` 이다 — Neon DB 와 같은 리전이라 리전 간 지연·전송 요금이 없다(#3016).
프론트 정적 호스팅은 `ap-northeast-2` 다. ECS Express Mode 가 그 리전에서 제공되는지는 스택을 만들기 전에
확인한다(#480). 첨부 저장소 S3 버킷은 **백엔드와 같은
리전**에 둔다(`ATTACHMENT_S3_REGION`) — 다른 리전이면 업로드·다운로드마다 리전 간 전송 지연·요금이 붙는다.

## 6) 프론트 연결

```bash
flutter build web --release \
  --dart-define=ENV=prod \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=https://<서비스 주소>/v1
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
- 회원 앱 모바일 빌드는 지도 문서를 `KAKAO_MAP_ORIGIN` 출처로 띄운다(#3043). 이 값은 목록에 이미 있는
  운영 회원 웹 주소로 빌드하고, 모바일 때문에 목록에 주소를 더하지 않는다(`docs/mobile_release.md`).
- 확인한 날짜와 결과를 담당 이슈에 남긴다.

운영 프론트 도메인을 붙이거나 바꿀 때 함께 바꾸는 곳(카카오 SDK 도메인, 이 서비스의 `CORS_ALLOW_ORIGINS`,
CloudFront 스택 파라미터)은 [`docs/aws-frontend-deployment.md`](../../docs/aws-frontend-deployment.md#운영-도메인을-바꿀-때-함께-바꾸는-곳)
표에 모아 두었다. 데모 사이트 도메인은 운영 도메인이 아니다(#3021). 운영 API 주소를 바꾸면 프론트 스택의
`ApiOrigin`(응답 헤더 CSP 의 `connect-src`)도 함께 바꾼다(#3017).

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

> **성격**: 운영 기본값은 **AWS ECS Express Mode + Neon** 이며, Railway 이전이
> 확정된 것은 아니다. 이 절과 관련 파일(`railway.json`·`.env.railway.example` 등)은
> **AWS 설정이 과하게 어렵거나 비용/운영 부담이 될 때 즉시 갈아탈 수 있게 해두는
> 예비용**이다. 지금 당장 Railway 를 쓰지 않아도 두어도 무해하며(런타임·CI 에 영향 없음),
> 필요해지는 순간 반나절 안에 이전할 수 있도록 이식성만 확보해 둔다.

AWS 설정이 복잡하면 **같은 Docker 이미지를 그대로** Railway 에 올릴 수 있다.
코드 변경 없이 플랫폼만 바뀌며, 이 저장소는 그렇게 이식 가능하도록 준비돼 있다:

- **`backend/railway.json`** — Dockerfile 빌더 · 헬스체크(`/v1/healthz`) · 재시작 정책을 코드로 선언.
- **`scripts/start.sh`** — `--port ${PORT:-8000}`. Railway 가 주입하는 **동적 $PORT** 로 바인딩하고,
  없으면(ECS·로컬·compose) 8000 으로 폴백한다(한 이미지가 양쪽 다 뜬다).
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

> DB 가 이미 Neon 에 있으므로 컴퓨트(ECS ↔ Railway)를 바꿔도 데이터 이전은 없고,
> 새 플랫폼에 `DATABASE_URL` 을 넣어 주면 끝난다.

## 대안 — 저비용 EC2 (수동)

`docker-compose.yml` 거의 그대로 EC2 1대에 올리고 Nginx + Let's Encrypt 로 HTTPS.
가장 저렴하지만 HTTPS/DB백업/재시작을 직접 관리해야 한다.
