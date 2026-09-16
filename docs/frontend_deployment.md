# 프론트엔드 배포 구조 및 운영 절차

## 현재 운영 환경

프론트엔드 배포 경로는 **두 개**이고, 둘 다 `main` 브랜치 push 에 걸려 있습니다.

| 배포 경로 | 워크플로 | 주소 | 비용 | 실행 조건 |
| --- | --- | --- | --- | --- |
| GitHub Pages | [`deploy.yml`](../.github/workflows/deploy.yml) | `ewhasudo.zapto.org` | 무료 | 조건 없음 — 항상 실행 |
| AWS S3 · CloudFront | [`aws-frontend-deploy.yml`](../.github/workflows/aws-frontend-deploy.yml) | CloudFront 기본 도메인 | **발생** | `AWS_FRONTEND_DEPLOY_ENABLED` 가 `true` 일 때만 |

사용자에게 제공하는 **커스텀 도메인은 여전히 GitHub Pages** 를 가리킵니다. AWS 경로는 도메인 전환 전 병행 검증용이며, 전환 절차는 [`aws-frontend-deployment.md`](aws-frontend-deployment.md) 를 따릅니다.

> **현재 AWS 배포는 꺼져 있습니다.** 이유와 다시 켜는 기준은 아래 [AWS 배포 스위치](#aws-배포-스위치) 를 참고합니다.

### GitHub Pages 서비스 경로

루트 랜딩페이지와 두 Flutter Web 앱을 하나의 Pages artifact로 묶어 같은 도메인에서 제공합니다.

| 경로 | 서비스 | 배포 산출물 |
| --- | --- | --- |
| `https://ewhasudo.zapto.org/` | 랜딩페이지 | `public/index.html` |
| `https://ewhasudo.zapto.org/frontend/` | 사용자 앱 | `public/frontend/` |
| `https://ewhasudo.zapto.org/trainer/` | 트레이너 웹 | `public/trainer/` |

- 배포 워크플로: [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)
- 커스텀 도메인 설정: [`CNAME`](../CNAME)
- 자동 배포 조건: `main` 브랜치 push
- 수동 배포: GitHub Actions의 `Deploy GitHub Pages` → `Run workflow`

## GitHub Pages 배포 과정

1. 회원 앱과 트레이너 웹의 Flutter 의존성을 설치합니다.
2. 두 앱에 필요한 drift WASM 파일을 내려받습니다.
3. 회원 앱을 `/frontend/`, 트레이너 웹을 `/trainer/` base path로 빌드합니다.
4. 루트 `index.html`과 두 앱의 빌드 결과를 `public/` 아래에 모읍니다.
5. Pages artifact를 업로드하고 `github-pages` 환경에 배포합니다.
6. 배포 action이 제한 시간 안에 완료를 확인하지 못하면 `version.txt`로 실제 반영 여부를 추가 검증합니다.

## AWS 배포 스위치

AWS 배포는 워크플로 파일이 아니라 **저장소 Actions 변수 하나로** 켜고 끕니다.

- 변수: `AWS_FRONTEND_DEPLOY_ENABLED`
- 위치: 저장소 `Settings` → `Secrets and variables` → `Actions` → `Variables`
- 값이 정확히 `true` 일 때만 [`aws-frontend-deploy.yml`](../.github/workflows/aws-frontend-deploy.yml) 의 job 이 실행되고, 그 밖의 값이면 job 이 건너뛰어집니다.

```bash
gh api repos/CSE-Sudo/on-care/actions/variables --jq '.variables[] | "\(.name)=\(.value)"'
```

워크플로 YAML 의 실행 조건을 지우거나 주석 처리하지 않습니다. **변수 하나만 되돌리면 원래대로 켜지는 구조**를 유지해야 다시 켤 때 코드 변경과 리뷰 없이 끝납니다. 나머지 세 변수(`AWS_FRONTEND_DEPLOY_ROLE_ARN`, `AWS_FRONTEND_BUCKET`, `AWS_FRONTEND_DISTRIBUTION_ID`)는 꺼 둔 동안에도 그대로 둡니다.

### 현재 상태: 꺼 둠 (`false`)

회원 앱 UI 정리를 여러 명이 나눠 진행하는 중이라 하루에도 여러 번 `main` 에 머지되고, 트레이너 웹 수정도 남아 있습니다. 어느 시점에 배포해도 절반만 정리된 화면이 올라가는데 S3·CloudFront 는 그때마다 비용이 발생합니다. **작업 중 불필요한 배포 비용을 줄이려고 잠시 꺼 두었습니다.**

GitHub Pages 배포는 무료이므로 그대로 두고, 작업 중 확인은 `ewhasudo.zapto.org` 에서 합니다.

AWS 배포 자체에 문제가 생겼을 때도 같은 방법으로 추가 배포를 즉시 중단할 수 있습니다. Pages 와 커스텀 도메인은 영향을 받지 않습니다.

### 다시 켜는 기준

아래를 모두 만족한 뒤에 `AWS_FRONTEND_DEPLOY_ENABLED` 를 `true` 로 되돌립니다.

1. 나눠 진행 중인 회원 앱 UI 정리가 모두 머지되었다.
2. 남아 있는 트레이너 웹 수정이 머지되었다.
3. GitHub Pages 에서 랜딩페이지·회원 앱·트레이너 웹 전체를 아래 [배포 확인](#배포-확인) 절차로 확인했다.

되돌린 뒤에는 `Deploy Frontend to AWS` 를 `main` 에서 한 번 실행해 CloudFront 기본 도메인의 세 경로와 `version.txt` 가 정상인지 확인합니다.

## Vercel 자동 배포 정리

Vercel 프로젝트가 이 Git 저장소와 연결되어 있으면 저장소 안에 `vercel.json`이 없어도 다음 배포가 별도로 생성될 수 있습니다.

- `main` 갱신: Vercel Production 배포
- PR 브랜치 갱신: Vercel Preview 배포 및 GitHub Bot 댓글

이 배포는 GitHub Pages로 전달되는 중간 단계가 아니라 **Vercel이 같은 커밋을 독립적으로 배포하는 중복 경로**입니다. 공식 서비스에서 Vercel을 사용하지 않으므로 아래 순서로 연결을 정리합니다.

1. 루트 [`vercel.json`](../vercel.json)의 `git.deploymentEnabled: false`를 반영해 모든 브랜치의 자동 배포를 차단합니다.
2. Vercel Dashboard에서 이 저장소와 연결된 프로젝트를 엽니다. Vercel 프로젝트 이름은 GitHub 저장소 이름 변경을 따라가지 않으므로, 저장소가 `on-care`로 바뀐 뒤에도 목록에는 이전 이름인 `sudo-capstone-project`로 남아 있을 수 있습니다.
3. `Settings` → `Git`에서 연결된 GitHub 저장소를 `Disconnect`합니다.
4. GitHub 저장소의 Rulesets 또는 Branch protection에서 Vercel 관련 required check가 있으면 제거합니다.
5. 새 PR을 갱신해 Vercel Preview와 Bot 댓글이 더 생성되지 않는지 확인합니다.
6. `main` 갱신 후 Vercel Production 배포가 생성되지 않는지 확인합니다.
7. 기존 `*.vercel.app` 주소가 필요하지 않다면 Pages 검증 후 Vercel 프로젝트를 별도로 삭제합니다.

> `vercel.json`은 자동 배포를 코드 수준에서 막는 안전장치입니다. Git 연결 해제와 프로젝트 삭제는 외부 서비스 설정이므로 저장소 변경만으로 실행되지 않습니다.

## 배포된 앱은 목 데이터로 돕니다

지금 배포되는 회원 앱과 트레이너 웹은 **백엔드를 보지 않습니다.** 두 앱 모두 `USE_MOCK_API` 기본값이 `true` 인데, [`aws-frontend-deploy.yml`](../.github/workflows/aws-frontend-deploy.yml) 의 빌드 스텝이 그 값을 넘기지 않습니다.

```yaml
flutter build web --release --base-href "/frontend/"
--dart-define=KAKAO_JS_KEY=${{ secrets.KAKAO_JS_KEY }}
```

`API_BASE_URL` 기본값도 `https://dev.api.oncare.example.com` 이라는 자리표시자입니다. 그래서 [`backend-deploy.yml`](../.github/workflows/backend-deploy.yml) 이 App Runner 에 백엔드를 올려 두어도 배포된 프론트는 그것을 쓰지 않고, 각 브라우저의 drift DB 안에서만 돕니다.

**의도된 상태입니다** — 백엔드 없이도 화면을 보여 줄 수 있습니다. 대신 회원↔트레이너 연동은 배포 주소에서 확인되지 않습니다. 브라우저마다 자기 DB 를 보기 때문에, 트레이너 화면에서 회원이 올린 식단을 보려면 실 API 로 넘겨야 합니다.

### 실 API 로 넘길 때 — 데모 데이터는 옮기지 않습니다

김민수 계정의 데모 데이터는 **옮길 일이 없습니다.** 회원 앱의 목 데이터와 백엔드 시드가 이미 같은 픽스처를 읽습니다(#757).

| 역할 | 경로 |
| --- | --- |
| 단일 원본 | `shared/demo_fixture/assets/kim_minsu.json` |
| 백엔드 사본 | `backend/app/db/demo_fixture_data.json` — 내용이 같고 `tool/gen_demo_fixture.py` 가 두 곳에 함께 씁니다(백엔드 이미지가 `backend/` 만 담기 때문) |
| 회원 앱 | `demo_fixture` 패키지로 읽습니다 (`lib/core/storage/seed_data.dart`) |
| 백엔드 | 같은 픽스처를 김민수(`user-7d4e9a2c5f18`) 계정의 DB 행으로 심습니다 |

`USE_MOCK_API=false` 로 넘겨도 김민수로 로그인하면 목 모드에서 보던 값이 그대로 보입니다. 두 가지만 다릅니다.

- **김민수만 픽스처입니다.** 이지수·박성호와 4~15번 회원은 `backend/app/db/seed_member_data.py` 의 상수가 만들어서, 목 모드 값과 반드시 일치하지 않습니다.
- **목 모드에서 직접 만든 데이터는 따라오지 않습니다.** 브라우저나 폰에서 저장한 식단은 그 기기의 drift DB 에만 남습니다.

넘기려면 빌드 스텝에 dart-define 두 개를 더합니다.

```yaml
flutter build web --release --base-href "/frontend/"
--dart-define=KAKAO_JS_KEY=${{ secrets.KAKAO_JS_KEY }}
--dart-define=USE_MOCK_API=false
--dart-define=API_BASE_URL=https://<App Runner 도메인>/v1
```

트레이너 웹 빌드 스텝에는 dart-define 이 하나도 없으므로, 거기에도 위 두 값을 새로 줘야 합니다.

실기기에 설치한 APK 는 **다시 빌드해야 합니다.** `String.fromEnvironment` 는 컴파일 타임 상수라서 dart-define 값이 APK 안에 박히고, 이미 설치된 앱의 서버 주소는 나중에 바꿀 수 없습니다. 절차는 [`local_fullstack.md`](local_fullstack.md) 의 안드로이드 실기기 절에 있습니다.

### `ENV=prod` 로 띄울 때 걸리는 것

`backend/app/core/config.py` 는 `env=prod` 에서 아래를 만족하지 않으면 **기동을 거부합니다.** `.env.example` 기본값을 그대로 가져가면 둘이 바로 걸립니다.

| 항목 | `.env.example` | prod 요구 |
| --- | --- | --- |
| `CORS_ALLOW_ORIGINS` | `*` | 와일드카드 금지 — 배포 도메인을 명시 |
| `DEMO_LOGIN_PASSWORD` | `oncare123` | `SEED_DEMO_DATA=true` 면 기본값이 아닌 12자 이상 |
| `JWT_SECRET` | 기본값 | 안전한 값 필수 |
| `AUTO_CREATE_TABLES` | — | `false` — Alembic 을 스키마의 유일한 경로로 둡니다 |

시연용으로 `SEED_DEMO_DATA=true` 를 켜면 `DEMO_LOGIN_PASSWORD` 를 바꿔야 하고, 그러면 [`local_fullstack.md`](local_fullstack.md) 의 데모 계정 표(`oncare123`)와 갈리므로 그쪽도 함께 손봅니다.

`ENV` 를 `dev`·`staging` 으로 두면 이 가드가 걸리지 않는 대신 **CORS 가 `*` 로 열린 채 배포됩니다.**

## 배포 확인

배포 완료 후 다음 항목을 확인합니다.

- 랜딩페이지 `https://ewhasudo.zapto.org/`가 정상 응답하는지 확인
- 사용자 앱 `https://ewhasudo.zapto.org/frontend/`이 정상 응답하는지 확인
- 트레이너 웹 `https://ewhasudo.zapto.org/trainer/`이 정상 응답하는지 확인
- `https://ewhasudo.zapto.org/version.txt`의 값이 배포한 전체 커밋 SHA와 일치하는지 확인

## AWS 이전 원칙

AWS 이전은 Vercel 정리와 별도 이슈 및 PR로 진행합니다.

구체적인 인프라 생성, 비활성 배포 설정, 병행 검증 절차는 [`aws-frontend-deployment.md`](aws-frontend-deployment.md)를 따릅니다.

1. GitHub Pages 배포를 유지한 상태에서 S3, CloudFront, OIDC 인프라를 준비합니다.
2. CloudFront 기본 도메인으로 랜딩페이지와 두 Flutter 앱을 검증합니다.
3. 검증이 끝난 뒤 커스텀 도메인의 DNS를 CloudFront로 전환합니다.
4. 전환과 롤백 가능 여부를 확인한 다음 GitHub Pages 배포를 중단합니다.

이 순서를 따르면 AWS 준비 중에도 현재 서비스 주소를 계속 사용할 수 있습니다.

현재는 1번이 끝나고 2번 검증 단계에 있습니다. 회원 앱 UI 정리와 트레이너 웹 수정이 끝날 때까지 [AWS 배포 스위치](#aws-배포-스위치)를 꺼 둔 상태로 멈춰 있고, 3번 이후는 아직 시작하지 않았습니다.
