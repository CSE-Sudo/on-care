# 프론트엔드 배포 구조 및 운영 절차

## 현재 운영 환경

프론트엔드 배포 경로는 **두 개**이고, 둘 다 `main` 브랜치 push 에 걸려 있습니다.

| 배포 경로 | 워크플로 | 주소 | 두 웹이 보는 백엔드 | 비용 | 실행 조건 |
| --- | --- | --- | --- | --- | --- |
| GitHub Pages (**데모**) | [`deploy.yml`](../.github/workflows/deploy.yml) | 데모 도메인 `ewhasudo.zapto.org` | 목업(브라우저 drift DB). 수동 실행에서만 실서버 선택 가능 | 무료 | 조건 없음 — 항상 실행 |
| AWS S3 · CloudFront (**운영**) | [`aws-frontend-deploy.yml`](../.github/workflows/aws-frontend-deploy.yml) | 운영 도메인(#2000 에서 확정 — 그 전에는 CloudFront 기본 도메인) | **실서버 고정** (`API_BASE_URL` 저장소 변수) | **발생** | `AWS_FRONTEND_DEPLOY_ENABLED` 가 `true` 일 때만 |

두 웹 앱의 백엔드 설정은 [아래 절](#운영-빌드는-실서버를-봅니다)에 정리했습니다.

**데모와 운영은 서로 다른 도메인입니다(#3021).** 데모 도메인은 계속 GitHub Pages 를 가리키고 운영 근거로 쓰지 않습니다 — 사람이 주기적으로 갱신해야 살아 있는 무료 DNS 라서다(#2000). 운영은 팀이 소유·갱신 책임을 지는 별도 도메인을 CloudFront 에 붙이며, 붙이는 절차와 함께 바꿀 곳은 [`aws-frontend-deployment.md`](aws-frontend-deployment.md#6-운영-도메인-연결) 에 있습니다. 데모 Pages 배포를 중단하는 단계는 없습니다.

> **현재 AWS 배포는 꺼져 있습니다.** 이유와 다시 켜는 기준은 아래 [AWS 배포 스위치](#aws-배포-스위치) 를 참고합니다.

### GitHub Pages 서비스 경로

루트 랜딩페이지와 두 Flutter Web 앱을 하나의 Pages artifact로 묶어 같은 도메인에서 제공합니다.

| 경로 | 서비스 | 배포 산출물 |
| --- | --- | --- |
| `https://ewhasudo.zapto.org/` | 랜딩페이지 | `public/index.html` |
| `https://ewhasudo.zapto.org/frontend/` | 사용자 앱 | `public/frontend/` |
| `https://ewhasudo.zapto.org/trainer/` | 트레이너 웹 | `public/trainer/` |
| `https://ewhasudo.zapto.org/legal/privacy.html`, `…/legal/terms.html` | 개인정보 처리방침·이용약관 공개 페이지(#3005) | `public/legal/` |

- 검색 색인: 랜딩만 색인합니다. 두 앱의 `web/index.html` 은 `<meta name="robots" content="noindex, nofollow">` 로 색인에서 빠집니다(로그인해야 쓰는 화면, #3015). 운영 정적 호스팅에서 응답 헤더(`X-Robots-Tag`)로 같은 정책을 거는 일은 배포 설정 몫입니다(#480).
- 배포 워크플로: [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)
- 데모 도메인 설정: [`CNAME`](../CNAME) — 운영 도메인이 아닙니다([위](#현재-운영-환경))
- 자동 배포 조건: `main` 브랜치 push
- 수동 배포: GitHub Actions의 `Deploy GitHub Pages` → `Run workflow`

### 한 출처를 쓰는 두 앱의 브라우저 저장소 규칙 (#3054)

두 앱은 경로만 다를 뿐 **같은 출처**(`https://ewhasudo.zapto.org`)라, 브라우저의 `sessionStorage`·`localStorage`·IndexedDB 를 함께 봅니다. 경로(`/frontend/`, `/trainer/`)로는 나뉘지 않습니다.

- 브라우저 저장소에 쓰는 키에는 **앱 이름공간을 붙입니다.** 토큰 키는 `oncare.member.*`(회원 앱)·`oncare.trainer.*`(트레이너 웹)이고, 정의는 `shared/oncare_core/lib/storage/token_keys.dart` 한 곳에 둡니다.
- 한 앱의 로그아웃·세션 만료는 **자기 이름공간의 키만** 지웁니다. 저장소 전체 비우기(`clear()`)는 쓰지 않습니다.
- 예전 빌드가 쓰던 이름공간 없는 키(`access_token`·`refresh_token`)는 처음 읽을 때 자기 이름공간으로 옮기고 지웁니다. 웹에서는 그 토큰이 어느 앱 것인지 모르므로 세션 복원에서 역할을 확인합니다(회원 앱: `GET /users/me` 의 `role`, 403 이면 갱신 없이 이 앱만 로그아웃 / 트레이너 웹: `GET /trainer/me`).
- 키 이름이 바뀌는 변경은 **두 앱을 같은 배포로** 내보냅니다. 같은 Pages artifact 로 묶여 있어 기본 배포는 이 조건을 지킵니다.
- 경로나 하위 도메인을 나눠 출처를 분리하더라도 이 규칙은 그대로 둡니다(모바일 빌드도 같은 키 이름을 씁니다).

## GitHub Pages 배포 과정

1. 랜딩 `index.html` 의 앱 바로가기를 검사합니다([아래 절](#랜딩-바로가기와-ogurlcanonical)).
2. 회원 앱과 트레이너 웹의 Flutter 의존성을 설치합니다.
3. 두 앱에 필요한 drift WASM 파일을 내려받습니다.
4. 빌드 모드를 정합니다. `main` push 는 항상 `mock`(목업)이고, 수동 실행에서 `backend` 입력으로 `real` 을 고를 때만 실서버 빌드가 됩니다. `real` 이면 **staging 백엔드**(`STAGING_API_BASE_URL` 저장소 변수)를 보며, 그 값을 먼저 검사합니다. 운영 주소(`API_BASE_URL`)와 같으면 멈춥니다(#3020).
5. 회원 앱을 `/frontend/`, 트레이너 웹을 `/trainer/` base path로 빌드합니다.
6. 루트 `index.html`, 공개 정책 페이지 `legal/*.html`, 두 앱의 빌드 결과를 `public/` 아래에 모으고, 랜딩의 og:url·canonical 을 `CNAME` 도메인으로 채웁니다.
7. Pages artifact를 업로드하고 `github-pages` 환경에 배포합니다.
8. 배포 action이 제한 시간 안에 완료를 확인하지 못하면 `version.txt`로 실제 반영 여부를 추가 검증합니다.
9. 배포된 랜딩을 받아 앱 바로가기·canonical·같은 도메인의 `/frontend/`·`/trainer/`·`/legal/privacy.html` 응답을 확인합니다.

두 앱 화면에 보이는 버전(`… · 버전 <이름>`)은 각 앱 `pubspec.yaml` 의 `version` 에서 옵니다. 워크플로는 버전을 주입하지 않으므로, 버전을 바꾸려면 `pubspec.yaml` 을 올리는 커밋을 main 에 넣습니다([mobile_release.md 1절](mobile_release.md#1-버전빌드-번호-규칙)). `version.txt` 는 배포한 커밋 SHA 로, 화면의 버전과 다릅니다.

## 랜딩 바로가기와 og:url·canonical

루트 `index.html` 은 Pages(데모)와 AWS(운영)에 **같은 파일**로 올라갑니다. 두 배포 모두 랜딩을 루트에, 회원 앱을 `/frontend/`, 트레이너 웹을 `/trainer/` 에 두므로 앱 바로가기는 **상대 경로**(`frontend/#/dashboard`, `trainer/`)로 씁니다. 그래야 각 배포의 방문자가 자기 배포의 앱으로 가고, 무료 DNS 이름이 끊겨도 운영 랜딩의 버튼은 영향을 받지 않습니다(#2841). 데모 영상·GitHub 같은 외부 링크는 절대 주소 그대로 둡니다.

`og:url`·`canonical` 은 상대 경로를 쓸 수 없어 원본에는 표시 줄 `<!-- SITE_URL_META -->` 만 두고, 배포 워크플로가 자기 도메인으로 바꿉니다.

| 배포 | og:url·canonical 에 들어가는 주소 |
| --- | --- |
| GitHub Pages | [`CNAME`](../CNAME) 의 도메인 |
| AWS CloudFront | 배포에 연결된 대체 도메인(운영 도메인)의 첫 번째, 없으면 CloudFront 기본 도메인. 운영 도메인을 붙이면 워크플로 수정 없이 다음 배포부터 반영 |

검사·치환·배포 후 확인은 [`.github/scripts/landing_site_url.sh`](../.github/scripts/landing_site_url.sh) 하나로 합니다.

- `check` — 앱 바로가기·처리방침 링크에 `http(s)://…/frontend`·`…/trainer`·`…/legal` 절대 주소가 없고, 상대 경로 바로가기·`legal/privacy.html` 링크와 표시 줄이 있는지. PR Gate 와 두 배포 워크플로의 빌드 전에 돕니다.
- `stamp` — 표시 줄을 og:url·canonical 태그로 바꿉니다(https 주소만 받음).
- `verify` — 배포된 랜딩을 받아 바로가기가 상대 경로인지, canonical 이 그 배포 주소인지, 같은 도메인의 `/frontend/`·`/trainer/`·`/legal/privacy.html` 이 응답하는지 확인합니다. AWS 배포에서 실패하면 직전 릴리스로 되돌립니다.

경계 검사는 `bash .github/scripts/test_landing_site_url.sh` 로 돌립니다.

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

AWS 배포 자체에 문제가 생겼을 때도 같은 방법으로 추가 배포를 즉시 중단할 수 있습니다. 데모 사이트(Pages)는 영향을 받지 않습니다.

### 다시 켜는 기준

아래를 모두 만족한 뒤에 `AWS_FRONTEND_DEPLOY_ENABLED` 를 `true` 로 되돌립니다.

1. 나눠 진행 중인 회원 앱 UI 정리가 모두 머지되었다.
2. 남아 있는 트레이너 웹 수정이 머지되었다.
3. GitHub Pages 에서 랜딩페이지·회원 앱·트레이너 웹 전체를 아래 [배포 확인](#배포-확인) 절차로 확인했다.

되돌린 뒤에는 `Deploy Frontend to AWS` 를 `main` 에서 배포할 커밋 SHA 로 한 번 실행해 운영 주소의 세 경로와 `version.txt`, 응답 보안 헤더가 정상인지 확인합니다. 켜 둔 동안 자동 배포는 `main` push 마다가 아니라 **같은 커밋의 E2E CI 가 성공한 뒤** 시작하고, 앱 CI 결과와 운영 백엔드 커밋을 먼저 확인합니다([배포 순서](aws-frontend-deployment.md#8-배포-순서--ci-판정과-백엔드-선후-3018)).

## Vercel 연동 정리

공식 서비스는 Vercel 을 쓰지 않습니다. 예전에는 Vercel 프로젝트가 이 저장소에 연결되어 `main` 갱신마다 Production 배포를, PR 마다 Preview 배포와 Bot 댓글을 만들었습니다(마지막 Vercel 배포 기록은 2026-08-08). GitHub Pages 로 가는 중간 단계가 아니라 같은 커밋을 따로 배포하는 중복 경로였고, 2026-08-08 에 루트 `vercel.json`(`git.deploymentEnabled: false`)으로 자동 배포를 막았습니다.

#3133 에서 남은 잔재를 걷어 냈습니다.

- 루트 `vercel.json` 을 지웠습니다. 저장소 안의 설정 파일이 아니라 Vercel 쪽 Git 연결 자체가 없어야 배포가 생기지 않습니다.
- GitHub `Preview` Environment(Vercel 미리보기 기록)는 지웁니다. `Production` 은 운영 배포가 쓰는 `production` 과 같은 Environment 라 지우지 않고 보호 규칙을 채워 이어 씁니다 — 이름·보호 규칙·OIDC subject 의 관계는 [`backend/docs/DEPLOY.md`](../backend/docs/DEPLOY.md) 1절에 있습니다.

`vercel.json` 이 없으므로 아래가 끝나 있어야 합니다(저장소 관리자·Vercel 계정 작업).

1. Vercel Dashboard 에서 이 저장소와 연결된 프로젝트(이전 이름 `sudo-capstone-project` 로 남아 있을 수 있음)의 `Settings` → `Git` 에서 `Disconnect` 하거나 프로젝트를 삭제합니다. 또는 GitHub 조직 설정의 Vercel 앱 설치에서 이 저장소 접근을 뺍니다.
2. GitHub Rulesets·Branch protection 에 Vercel 관련 required check 가 없는지 확인합니다.
3. 다음 PR·`main` 갱신에서 `vercel[bot]` 배포·댓글이 생기지 않는지 확인합니다(`gh api "repos/CSE-Sudo/on-care/deployments?environment=Preview"` 가 새 항목 없이 비어 있어야 합니다).

## 운영 빌드는 실서버를 봅니다

두 웹 앱은 `--dart-define` 을 받지 못하면 **목업·개발 설정으로** 빌드됩니다(`USE_MOCK_API` 기본 `true`, `ENV` 기본 `dev`, `API_BASE_URL` 기본은 자리표시자). 그래서 배포 워크플로가 이 세 값을 **명시해서** 넘깁니다(#2810).

| 배포 | `USE_MOCK_API` | `API_BASE_URL` | `ENV` |
| --- | --- | --- | --- |
| 운영 — [`aws-frontend-deploy.yml`](../.github/workflows/aws-frontend-deploy.yml) | `false` | 저장소 변수 `vars.API_BASE_URL` | `prod` |
| 데모 — [`deploy.yml`](../.github/workflows/deploy.yml), `main` push·수동 `mock` | `true` | 넘기지 않음 | `dev` |
| 데모 — [`deploy.yml`](../.github/workflows/deploy.yml), 수동 `real` | `false` | 저장소 변수 `vars.STAGING_API_BASE_URL`(staging 백엔드) | `staging` |

- **운영 경로는 실서버 고정입니다.** 목업으로 되돌리는 입력이 없습니다. 회원이 남긴 기록이 같은 백엔드를 거쳐 트레이너 웹에 보이고, 트레이너의 코칭·루틴이 회원 앱으로 돌아옵니다.
- **`ENV=prod`** 이면 회원 앱의 GoRouter 진단 로그(`debugLogDiagnostics`)·provider 로그(`LoggingProviderObserver`)·화면 이동 로그와, 두 앱의 API 요청 로그 인터셉터가 꺼집니다. UI 카탈로그 경로도 열리지 않습니다.
- **데모는 다른 주소·다른 워크플로로 분리했습니다.** `ewhasudo.zapto.org` 의 Pages 배포는 소개 페이지와 함께 목업 데모를 계속 올립니다. 브라우저마다 자기 drift DB 를 보므로 회원↔트레이너 연동은 데모 주소에서 확인되지 않습니다.

### `API_BASE_URL` 저장소 변수

- 위치: 저장소 `Settings` → `Secrets and variables` → `Actions` → `Variables`
- 형식: `https://<운영 API 도메인>/v1` — **`/v1` 까지 포함하고 끝에 `/` 를 붙이지 않습니다.** 두 앱 모두 요청 경로를 `/auth/login` 처럼 `/v1` 없이 씁니다.
- 주소는 워크플로에 적지 않고 이 변수에서만 읽습니다. 값을 바꾸면 다음 배포부터 반영됩니다.
- 데모 사이트의 `real` 빌드는 같은 형식의 **`STAGING_API_BASE_URL`** 을 씁니다. staging 백엔드는 운영과 다른 DB·비밀로 뜨는 데모 시연용 서비스입니다([`backend/docs/DEPLOY.md`](../backend/docs/DEPLOY.md) 0절).

빌드 전에 [`check_web_api_base_url.sh`](../.github/scripts/check_web_api_base_url.sh) 가 값을 검사하고, 아래 경우 **빌드를 시작하지 않고 워크플로를 실패시킵니다.** 빈 값으로 빌드하면 빌드는 성공하지만 자리표시자 주소를 부르는 앱이 배포되기 때문입니다.

- 변수가 없거나 비어 있음
- `https://` 로 시작하지 않음 (배포 웹은 https 로 서빙되므로 http 주소는 브라우저가 막습니다)
- `/v1` 로 끝나지 않음, 또는 끝에 `/` 가 붙음
- 코드 기본값의 자리표시자 도메인(`example.com` 계열)
- **다른 환경의 주소와 같음** — 운영 빌드에는 `STAGING_API_BASE_URL` 을, 데모 `real` 빌드에는 `API_BASE_URL` 을 금지 주소로 넘깁니다. 두 변수를 같은 값으로 두면 데모 사이트가 운영 DB 에 기록을 남기거나 운영 웹이 시연용 DB 를 보게 되므로 둘 다 멈춥니다(#3020)

검사 규칙 자체는 `bash .github/scripts/test_check_web_api_base_url.sh` 로 확인합니다.

운영 백엔드가 이 프론트 주소의 요청을 받으려면 백엔드 `CORS_ALLOW_ORIGINS` 에 프론트 배포 도메인이 들어 있어야 합니다(아래 [`ENV=prod` 로 띄울 때 걸리는 것](#envprod-로-띄울-때-걸리는-것)).

### 데모 데이터와 실서버

김민수 계정의 데모 데이터는 **옮길 일이 없습니다.** 회원 앱의 목 데이터와 백엔드 시드가 이미 같은 픽스처를 읽습니다(#757).

| 역할 | 경로 |
| --- | --- |
| 단일 원본 | `shared/demo_fixture/assets/kim_minsu.json` |
| 백엔드 사본 | `backend/app/db/demo_fixture_data.json` — 내용이 같고 `tool/gen_demo_fixture.py` 가 두 곳에 함께 씁니다(백엔드 이미지가 `backend/` 만 담기 때문) |
| 회원 앱 | `demo_fixture` 패키지로 읽습니다 (`lib/core/storage/seed_data.dart`) |
| 백엔드 | 같은 픽스처를 김민수(`user-7d4e9a2c5f18`) 계정의 DB 행으로 심습니다 |

실서버 빌드에서 김민수로 로그인하면 목 모드에서 보던 값이 그대로 보입니다(백엔드가 시드를 심은 경우). 두 가지만 다릅니다.

- **김민수만 픽스처입니다.** 이지수·박성호와 4~15번 회원은 `backend/app/db/seed_member_data.py` 의 상수가 만들어서, 목 모드 값과 반드시 일치하지 않습니다.
- **목 모드에서 직접 만든 데이터는 따라오지 않습니다.** 브라우저나 폰에서 저장한 식단은 그 기기의 drift DB 에만 남습니다.

트레이너 웹 지도(소속 헬스장 찾기, #2543)가 뜨려면 카카오 콘솔의 JavaScript SDK 도메인에 트레이너 웹 주소도 등록돼 있어야 합니다.

`KAKAO_JS_KEY` 는 웹 빌드에 들어가 브라우저에 그대로 보이므로, 이 허용 도메인 목록이 키를 지키는 유일한 장치입니다(#2913). 배포·도메인을 바꿀 때마다 목록에 **운영 회원 웹·트레이너 웹 주소만** 남아 있는지, 개발용(`localhost` 등)·옛 배포·임시 미리보기 주소가 지워졌는지 확인합니다. 체크리스트는 [`backend/docs/DEPLOY.md`](../backend/docs/DEPLOY.md) 의 "프론트 연결" 절에 있습니다.

실기기에 설치한 APK 는 **다시 빌드해야 합니다.** `String.fromEnvironment` 는 컴파일 타임 상수라서 dart-define 값이 APK 안에 박히고, 이미 설치된 앱의 서버 주소는 나중에 바꿀 수 없습니다. 절차는 [`local_fullstack.md`](local_fullstack.md) 의 안드로이드 실기기 절에 있습니다.

### 에러 추적(Sentry, #2839)

두 앱은 처리하지 못한 오류를 Sentry 로 보낼 수 있습니다. **`SENTRY_DSN` 이 비어 있거나, `USE_MOCK_API=true`(데모)이거나, `ENV=dev` 이면 보내지 않고 SDK 도 초기화하지 않습니다.**

| 빌드 | ENV·백엔드 | DSN | 오류 보고 |
| --- | --- | --- | --- |
| 운영 웹(`aws-frontend-deploy.yml`) | `prod`·실서버 | 회원 앱 `secrets.SENTRY_DSN_MEMBER`, 트레이너 웹 `secrets.SENTRY_DSN_TRAINER` | 비밀이 있으면 보냄 |
| 데모 Pages(`deploy.yml`) | `dev`·목업(기본) | 넘기지 않음 | 보내지 않음 |
| 스토어 모바일 | `prod`·실서버 | `config/release.json` 의 `SENTRY_DSN`([mobile_release.md](mobile_release.md) 5절) | 보냄 |

운영 웹 워크플로는 DSN 비밀이 비어 있으면 **경고만 남기고 배포를 계속합니다**(그 앱의 운영 오류가 모이지 않음). 값이 `https://` 로 시작하지 않으면 멈춥니다. 앱마다 Sentry 프로젝트가 따로라 비밀도 둘입니다(#3022).

사용자 식별·요청 본문·헤더·쿼리·화면 캡처·터치 기록·print 로그는 싣지 않고, 태그는 오류 출처·화면 경로 패턴·환경입니다(`lib/core/observability/error_reporter.dart`). Sentry 프로젝트·DSN 발급과 비밀 등록, 웹 소스맵 업로드 여부는 #480 에서 정합니다.

### 릴리스 기본값 가드 (#3022)

두 앱의 컴파일 타임 기본값은 로컬 개발용(`ENV=dev`·`USE_MOCK_API=true`·예시 주소)입니다. 릴리스 빌드(`--release`, 웹 배포 빌드 포함)는 기동할 때 `AppConfig.releaseProblems()` 로 설정을 검사하고, 아래 중 하나면 기능 화면 대신 **"이 빌드는 잘못 구성됐어요"** 안내와 고칠 설정 목록을 띄웁니다.

- `ENV` 가 `prod`·`staging` 이 아님(데모 빌드 표시가 있는 목업 빌드는 예외)
- `USE_MOCK_API=true` 인데 데모 빌드 표시 `DEMO_BUILD=true` 가 없음
- 실서버를 부르는데 `API_BASE_URL` 이 `https://` 가 아니거나 예시·로컬 주소(`example.com` 계열·`.test`·`localhost` 등)

데모 Pages 빌드(`deploy.yml`)는 두 앱 모두 `--dart-define=DEMO_BUILD=true` 를 넘겨 지금처럼 목업으로 뜹니다. 운영 웹 빌드는 이 표시를 넘기지 않습니다. `flutter run`(디버그)과 테스트에는 가드가 적용되지 않습니다.

### `ENV=prod` 로 띄울 때 걸리는 것

`backend/app/core/config.py` 는 `env=prod` 에서 아래를 만족하지 않으면 **기동을 거부합니다.** `.env.example` 기본값을 그대로 가져가면 둘이 바로 걸립니다.

| 항목 | `.env.example` | prod 요구 |
| --- | --- | --- |
| `CORS_ALLOW_ORIGINS` | `*` | 와일드카드 금지 — 배포 도메인을 명시 |
| `SEED_DEMO_DATA` | `true` | `false` — 켜면 기동 거부(#2811) |
| `JWT_SECRET` | 기본값 | 안전한 값 필수 |
| `AUTO_CREATE_TABLES` | — | `false` — Alembic 을 스키마의 유일한 경로로 둡니다 |

운영에서는 데모 시드를 켤 수 없습니다. 시연용 데모 계정이 필요하면 데모 전용 DB 를 둔 별도 환경(`ENV=dev`·`staging`)에서 켭니다. 예전 기본값으로 운영 DB 에 데모 데이터가 이미 심겼다면 [`backend/docs/DEPLOY.md`](../backend/docs/DEPLOY.md) 의 데모 데이터 정리 절차를 따릅니다.

`ENV` 를 `dev`·`staging` 으로 두면 이 가드가 걸리지 않는 대신 **CORS 가 `*` 로 열린 채 배포됩니다.**

## 배포 확인

데모(Pages) 배포 완료 후 다음 항목을 확인합니다. 운영(AWS)은 같은 항목을 운영 주소에서 봅니다.

- 랜딩페이지 `https://ewhasudo.zapto.org/`가 정상 응답하는지 확인
- 사용자 앱 `https://ewhasudo.zapto.org/frontend/`이 정상 응답하는지 확인
- 트레이너 웹 `https://ewhasudo.zapto.org/trainer/`이 정상 응답하는지 확인
- `https://ewhasudo.zapto.org/version.txt`의 값이 배포한 전체 커밋 SHA와 일치하는지 확인
- 랜딩의 '회원 앱 바로가기'·'트레이너 웹 바로가기'가 **같은 도메인**의 `/frontend/`·`/trainer/` 로 열리고, 페이지 소스의 `canonical` 이 그 배포 주소인지 확인(워크플로의 `Verify landing app links` 단계가 같은 내용을 자동으로 봅니다)

운영(AWS) 배포는 위 응답 확인에 더해 다음을 봅니다.

- 회원 앱·트레이너 웹 모두 로그인 화면이 뜨고, 운영 계정으로 로그인한 뒤 브라우저 개발자 도구 Network 탭의 요청이 `API_BASE_URL` 로 나가는지 확인
- 회원 앱에서 식단을 하나 기록하고, **다른 브라우저**의 트레이너 웹에서 담당 회원 화면에 그 기록이 보이는지 확인
- 개발자 도구 Console 에 GoRouter 진단 로그·provider 로그·API 요청 로그가 찍히지 않는지 확인
- 개발자 도구 Console 에 CSP 위반(`Refused to connect`·`Refused to load`)이 없는지, 카카오 지도·사진 업로드·리포트 PDF 인쇄가 동작하는지 확인(응답 헤더 CSP 가 meta 보다 좁습니다 — [응답 보안 헤더](#응답-보안-헤더3017))

## 캐시 헤더와 새 버전 안내 (#3023)

Flutter 웹 산출물의 진입 파일은 이름에 해시가 없습니다. 모든 파일에 같은 `max-age` 를 주면 배포 뒤에도 브라우저가 옛 `index.html`·`flutter_bootstrap.js`·`main.dart.js` 를 들고 있고, 서로 다른 릴리스의 진입 파일이 섞일 수 있습니다. 이미 열려 있는 탭은 아예 옛 번들을 계속 실행합니다.

### 캐시 헤더 (운영 AWS)

`Upload release to S3` 단계는 [`.github/scripts/web_cache_headers.sh`](../.github/scripts/web_cache_headers.sh) 로 두 번에 나눠 올립니다. 규칙은 이 스크립트 한 곳에 있습니다.

| 파일 | `Cache-Control` |
| --- | --- |
| 진입 파일 — `index.html`·`flutter_bootstrap.js`·`flutter.js`·`main.dart.js`(`.mjs`·`.wasm`)·`version.json`·`version.txt`·`manifest.json`·`drift_worker.js`·`sqlite3.wasm` (폴더 무관) | `no-cache` — 매번 재검증하고, 바뀌지 않았으면 304 |
| 그 밖 — `canvaskit/`·`assets/`·글꼴·아이콘 | `public,max-age=300` |

업로드 뒤 `Verify cache headers of the uploaded release` 단계가 대표 파일(두 앱의 `index.html`·`flutter_bootstrap.js`·`main.dart.js`·`version.txt`·`canvaskit/canvaskit.wasm`)의 헤더를 확인하고, 다르면 트래픽을 전환하지 않고 멈춥니다. CloudFront 캐시 정책은 `MinTTL: 0` 이라 오리진의 `no-cache` 를 따릅니다. GitHub Pages(데모)는 응답 헤더를 바꿀 수 없어 아래 새 버전 안내만 적용됩니다.

### 새 버전 안내

- 두 웹 빌드는 `--dart-define=RELEASE_SHA=<커밋 SHA>` 로 자기 릴리스를 내장합니다(운영·데모 모두). 로컬 실행·테스트 빌드에는 값이 없어 확인이 꺼집니다.
- 배포는 루트 `version.txt` 를 두 앱 폴더에도 복사합니다(`/frontend/version.txt`·`/trainer/version.txt`).
- 앱은 자기 `<base href>version.txt` 를 `cache: no-store` 로 읽어 내장 SHA 와 비교합니다. 시점은 시작 직후 한 번, 탭이 다시 보일 때, 그 밖에는 10분 간격입니다. 읽기 실패·SHA 가 아닌 응답은 조용히 넘깁니다.
- 다르면 트레이너 웹은 콘텐츠 영역 맨 위, 회원 웹은 셸 맨 위에 정보 배너 "새 버전이 배포되었어요 · 새로고침" 이 뜹니다. `새로고침` 은 페이지를 다시 읽고(트레이너 웹은 작성 중인 폼이 있으면 브라우저 확인창이 먼저 뜹니다), 닫기(X)는 같은 배포에 대해 그 탭에서 다시 띄우지 않습니다. 자동 새로고침은 하지 않습니다.
- 모바일 앱 빌드는 확인 자체가 없습니다.

배포 뒤 확인: 브라우저 개발자 도구 Network 탭에서 `/trainer/main.dart.js` 응답의 `Cache-Control: no-cache` 와 `/trainer/version.txt` 의 SHA 를 봅니다. 배포 전부터 열어 둔 탭은 다시 보이게 하면 배너가 떠야 합니다.

## 운영 도메인과 보안 헤더

AWS 이전은 Vercel 정리와 별도 이슈 및 PR로 진행합니다. 인프라 생성·배포 설정·검증 절차는 [`aws-frontend-deployment.md`](aws-frontend-deployment.md)를 따릅니다.

1. S3, CloudFront, OIDC 인프라를 준비하고 CloudFront 기본 도메인으로 랜딩페이지와 두 Flutter 앱을 검증합니다.
2. 운영 도메인이 정해지면(#2000) `us-east-1` ACM 인증서를 발급해 스택 파라미터 `AlternateDomainName`·`AcmCertificateArn` 으로 붙이고, 카카오 SDK 허용 도메인·백엔드 CORS 를 함께 바꿉니다([운영 도메인 연결](aws-frontend-deployment.md#6-운영-도메인-연결)).
3. 데모 사이트(Pages)는 그대로 둡니다.

현재는 1번 검증 단계에 있습니다. 회원 앱 UI 정리와 트레이너 웹 수정이 끝날 때까지 [AWS 배포 스위치](#aws-배포-스위치)를 꺼 둔 상태로 멈춰 있습니다.

### 응답 보안 헤더(#3017)

운영 CloudFront 는 HSTS·`X-Frame-Options: DENY`·`frame-ancestors 'none'`·`nosniff`·Referrer-Policy 와, 두 앱 `web/index.html` 의 meta CSP 에서 `connect-src` 만 운영 API 출처로 좁힌 CSP 를 응답 헤더로 붙입니다. 브라우저는 meta 와 헤더 CSP 를 함께 적용합니다. **GitHub Pages 데모는 응답 헤더를 바꿀 수 없어 meta CSP 만 적용됩니다**(HSTS·`frame-ancestors` 없음 — 데모는 목업이라 실제 회원 데이터가 없습니다). 자세한 내용과 확인 방법은 [`aws-frontend-deployment.md`](aws-frontend-deployment.md#9-응답-보안-헤더-3017) 에 있습니다.
