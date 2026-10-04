# AWS 프론트엔드 배포 준비

Flutter 회원 앱과 트레이너 웹을 하나의 private S3 버킷에 올리고 CloudFront로 제공합니다. GitHub Actions는 장기 액세스 키 대신 OIDC 임시 자격 증명을 사용합니다.

이 변경을 `main`에 병합해도 AWS 배포는 즉시 시작되지 않습니다. `AWS_FRONTEND_DEPLOY_ENABLED` 저장소 변수가 정확히 `true`일 때만 별도 AWS 워크플로가 실행됩니다. GitHub Pages 데모 사이트는 이 배포와 별개로 계속 운영됩니다 — **데모와 운영은 서로 다른 도메인**입니다([5절](#5-데모pages와-운영cloudfront)).

> **현재 상태(2026-09-16): AWS 배포는 꺼져 있습니다.** 아래 1~3단계(인프라 생성·변수 등록)와 4단계(첫 활성화)는 이미 끝냈습니다. 지금은 회원 앱 UI 정리와 트레이너 웹 수정이 진행 중이라 작업 기간의 배포 비용을 줄이려고 `AWS_FRONTEND_DEPLOY_ENABLED` 를 `false` 로 되돌려 둔 상태입니다. 다시 켜는 기준은 [`frontend_deployment.md`](frontend_deployment.md#aws-배포-스위치) 에 정리했습니다.

## 사전 조건

- AWS 계정 MFA 설정
- 배포 리전: `ap-northeast-2`(서울)
- AWS Budget 알림 유지
- CloudFormation을 실행할 IAM 관리자 계정
- GitHub 저장소의 `KAKAO_JS_KEY` secret 유지

## 1. 템플릿 검증

AWS CloudShell에서 브랜치를 받은 뒤 템플릿을 먼저 검증합니다.

템플릿은 기본적으로 GitHub의 immutable OIDC subject를 사용합니다. 저장소 설정값은 다음 명령으로
확인합니다. 응답의 `sub_claim_prefix`에 표시된 owner ID와 repository ID가 템플릿 기본값과 다르면
배포 시 `GitHubOwnerId`, `GitHubRepositoryId` 파라미터로 전달합니다.

```bash
gh api repos/CSE-Sudo/on-care/actions/oidc/customization/sub
```

`use_immutable_subject=false`만으로 이름 기반 subject라고 판단하지 않습니다. GitHub는
2026년 7월 15일 이후 저장소 이름 변경·이전 시에도 ID를 포함한 형식으로 전환합니다.
`sub_claim_prefix`, 실제 AWS 신뢰 정책과 성공한 인증 기록을 함께 확인합니다.
형식이 불명확하면 실행 토큰의 `sub`와 `aud`만 확인하며, 토큰 원문이나 자격 증명은 로그에 남기지 않습니다.

OnCare에서 사용하는 `main` 브랜치 subject는 다음과 같습니다. ID가 포함되어도 조직명은
문자열의 일부이므로 조직명 변경 후 AWS 신뢰 정책을 갱신해야 합니다.

```text
repo:CSE-Sudo@265976266/on-care@1174354664:ref:refs/heads/main
```

배포 역할은 이 ID 기반 형식 하나만 신뢰합니다(#3089). 이름 기반 형식(`repo:<소유자>/<저장소>:…`)은
같은 이름을 다시 쓰는 다른 저장소도 맞출 수 있어 템플릿에서 선택지를 없앴습니다(백엔드 역할과 같습니다).
예전 스택에 남아 있던 `UseImmutableGitHubOidcSubject` 파라미터는 값이 이미 `true` 였으므로 최신 템플릿을
적용해도 신뢰 정책은 바뀌지 않습니다. 저장소와 `main` 브랜치의 정확한 일치를 유지하고 와일드카드로
신뢰 범위를 넓히지 않습니다.
근거: [GitHub OIDC subject 형식](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims).

```bash
git clone https://github.com/CSE-Sudo/on-care.git
cd on-care
git switch main

aws cloudformation validate-template \
  --template-body file://infra/frontend-hosting.yml \
  --region ap-northeast-2
```

계정에 GitHub Actions용 OIDC 공급자가 이미 있는지도 확인합니다.

```bash
aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[*].Arn' \
  --output table
```

`token.actions.githubusercontent.com` 공급자가 없다면 아래 기본 명령으로 새 공급자를 함께 생성합니다.

## 2. AWS 리소스 생성

`ApiOrigin` 은 필수입니다. 운영 API 출처(`API_BASE_URL` 에서 `/v1` 을 뺀 값, 예 `https://<운영 API 도메인>`)를 넣습니다. 응답 헤더 CSP 의 `connect-src` 가 이 값으로 좁혀지므로 틀리면 두 앱이 API 를 부르지 못합니다([9절](#9-응답-보안-헤더-3017)).

```bash
aws cloudformation deploy \
  --template-file infra/frontend-hosting.yml \
  --stack-name oncare-frontend \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ApiOrigin=https://<운영 API 도메인> \
  --region ap-northeast-2
```

이미 GitHub OIDC 공급자가 있다면 그 ARN을 전달해 재사용합니다.

```bash
aws cloudformation deploy \
  --template-file infra/frontend-hosting.yml \
  --stack-name oncare-frontend \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ApiOrigin=https://<운영 API 도메인> \
    ExistingGitHubOidcProviderArn=arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com \
  --region ap-northeast-2
```

이미 있는 스택을 이 템플릿으로 처음 갱신할 때도 `ApiOrigin` 을 함께 넘겨야 합니다(기존 값이 없는 새 파라미터라 생략하면 실패합니다).

> **이미 생성된 스택을 갱신하는 경우 주의합니다.** `aws cloudformation deploy`는 `--parameter-overrides`에 없는 기존 파라미터 값을 유지합니다. 조직명은 `CSE-Sudo-26`에서 `CSE-Sudo`로, 저장소명은 `sudo-capstone-project`에서 `on-care`로 바뀌었습니다. 템플릿 기본값 변경만으로 이미 배포된 스택의 `GitHubOwner`와 `GitHubRepository`가 갱신되지는 않습니다. 최신 템플릿 전체를 적용할 때는 아래처럼 값을 명시하고 변경 세트를 먼저 검토합니다. 조직명만 복구할 때는 아래의 **기존 템플릿을 유지하는 복구 절차**를 사용합니다.
>
> ```bash
> aws cloudformation deploy \
>   --template-file infra/frontend-hosting.yml \
>   --stack-name oncare-frontend \
>   --capabilities CAPABILITY_IAM \
>   --parameter-overrides \
>     GitHubOwner=CSE-Sudo \
>     GitHubRepository=on-care \
>     GitHubOwnerId=265976266 \
>     GitHubRepositoryId=1174354664 \
>   --no-execute-changeset \
>   --region ap-northeast-2
> ```

### GitHub Environment 전환 (#3019)

배포 job 에 `environment: production` 이 붙으면 OIDC 토큰의 `sub` 가
`repo:CSE-Sudo@<id>/on-care@<id>:ref:refs/heads/main` 에서 `…:environment:production` 으로 바뀝니다.
신뢰 정책이 브랜치 형식만 허용하면 워크플로를 바꾸는 순간 배포가 인증 단계에서 실패하므로, 아래 순서를 지킵니다.

1. **스택 먼저**: 최신 `infra/frontend-hosting.yml` 로 스택을 갱신합니다. 새 파라미터 `GitHubEnvironment`(기본
   `production`)·`AllowBranchOidcSubject`(기본 `true`)가 생기고, 역할은 Environment 형식과 브랜치 형식을 **둘 다**
   믿습니다. 변경 세트에서 `GitHubFrontendDeployRole` 의 신뢰 정책·설명만 바뀌는지 확인합니다.
2. 저장소 Settings → Environments 에서 `production`(이미 있는 `Production` 이 같은 환경입니다)의 배포 브랜치를
   `main` 으로 두고, 필요하면 승인자를 지정합니다. 승인자를 두면 프런트·백엔드 운영 배포가 같은 승인을 기다립니다.
3. 이 워크플로를 `main` 에서 한 번 돌려 `Configure AWS credentials` 가 통과하는지 봅니다.
4. **브랜치 형식 제거**: `AllowBranchOidcSubject=false` 로 스택을 다시 적용합니다. 이제 Environment 밖에서 돈
   job 은 이 역할을 맡을 수 없습니다.

Environment 이름은 대소문자를 가리지 않으므로 신뢰 정책은 `StringEqualsIgnoreCase` 로 비교합니다.

### 조직명 변경으로 OIDC 인증이 실패할 때

`Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`가
발생하면 `AWS_FRONTEND_DEPLOY_ROLE_ARN`이 가리키는 IAM 역할의 **신뢰 관계**를 확인합니다.
`aud`는 `sts.amazonaws.com`, `sub`는 현재 저장소와 실행 Environment(전환 기간에는 브랜치도)에 맞아야 합니다.

조직명만 변경된 기존 스택은 다음 순서로 복구합니다.

1. 서울(`ap-northeast-2`) CloudFormation에서 `oncare-frontend`의 **파라미터**를 확인합니다.
2. **스택 업데이트 → 변경 세트 생성 → 표준 변경 세트 → 기존 템플릿 사용**을 선택합니다.
3. `GitHubOwner`만 `CSE-Sudo`로 변경합니다. 저장소명, 두 ID, 브랜치, OIDC 공급자 ARN 등
   나머지는 기존 값을 유지합니다.
4. 변경 세트에서 `GitHubFrontendDeployRole`의 `AssumeRolePolicyDocument`만 수정되는지 확인합니다.
   리소스 교체·삭제, S3·CloudFront 변경 또는 배포 권한 추가가 포함되면 원인을 확인한 뒤 진행합니다.
5. 변경 세트를 실행하고 스택이 `UPDATE_COMPLETE`가 될 때까지 확인합니다.
6. IAM 역할의 `sub`에서 조직명만 갱신되고 ID와 `main` 제한이 유지되는지 확인합니다.
7. GitHub Actions에서 최신 실패한 `main` 배포를 재실행합니다. OIDC 인증, 업로드, 릴리스 전환과
   배포 검증까지 모두 성공해야 복구 완료입니다. CloudFront의 `/version.txt`가 실행 커밋 SHA와
   일치하고 `/`, `/member/`, `/trainer/`가 응답하는지도 확인합니다.

이 방법은 AWS에 적용된 템플릿을 재사용하므로 최신 코드의 다른 인프라 변경을 함께 적용하지 않습니다.
IAM 콘솔에서 역할만 직접 수정하면 CloudFormation 파라미터에 옛 조직명이 남을 수 있으므로
스택 파라미터를 통해 갱신합니다. AWS 인증 실패 상태에서는 GitHub 배포 역할이 스스로 신뢰 정책을
고칠 수 없으므로, CloudFormation을 갱신할 수 있는 AWS 세션에서 작업합니다.

CloudFront 배포가 포함되어 있어 스택 생성에는 몇 분이 걸릴 수 있습니다. 완료되면 출력값을 확인합니다.

```bash
aws cloudformation describe-stacks \
  --stack-name oncare-frontend \
  --region ap-northeast-2 \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table
```

## 3. GitHub Actions 변수 등록

GitHub 저장소의 `Settings` → `Secrets and variables` → `Actions` → `Variables`에 스택 출력값을 등록합니다.

| 변수 | 값 |
| --- | --- |
| `AWS_FRONTEND_DEPLOY_ROLE_ARN` | `GitHubDeployRoleArn` 출력값 |
| `AWS_FRONTEND_BUCKET` | `BucketName` 출력값 |
| `AWS_FRONTEND_DISTRIBUTION_ID` | `DistributionId` 출력값 |
| `API_BASE_URL` | 운영 백엔드 주소 + `/v1` (예: `https://<운영 API 도메인>/v1`). 두 웹 앱이 이 주소로 실서버를 봅니다 |

`API_BASE_URL` 이 없거나 형식이 틀리면 `Deploy Frontend to AWS` 가 빌드 전에 실패합니다. 규칙은 [`frontend_deployment.md`](frontend_deployment.md#api_base_url-저장소-변수) 에 있습니다.

준비 단계에서는 `AWS_FRONTEND_DEPLOY_ENABLED`를 만들지 않거나 `false`로 둡니다. AWS 액세스 키는 GitHub Secrets에 만들거나 저장하지 않습니다.

## 4. 첫 AWS 배포 활성화

CloudFormation 스택과 세 변수를 확인하고 배포할 `main` 커밋이 준비된 뒤에만 다음 변수를 추가합니다.

| 변수 | 값 |
| --- | --- |
| `AWS_FRONTEND_DEPLOY_ENABLED` | `true` |

배포 job 은 GitHub Environment `production` 에서 돌고(아래 "GitHub Environment 전환"), Environment 의 배포 브랜치를 `main` 으로 묶으므로 AWS 워크플로의 첫 실행도 `main`에서 진행합니다.

이 단계는 이미 완료했습니다. 이후 작업 기간의 비용을 줄이려고 변수를 다시 `false`로 두었으므로, 아래 확인 절차는 **꺼 둔 배포를 다시 켤 때의 점검 절차**로도 그대로 사용합니다.

1. GitHub Actions에서 `Deploy Frontend to AWS`를 엽니다.
2. `Run workflow`에서 `main`을 고르고 배포할 커밋의 전체 SHA 를 넣습니다. 그 커밋의 CI 판정과 백엔드 선후 확인([8절](#8-배포-순서--ci-판정과-백엔드-선후-3018))을 먼저 거칩니다.
3. 워크플로가 출력한 CloudFront 기본 도메인을 확인합니다.

```text
https://<DistributionDomainName>/
https://<DistributionDomainName>/member/
https://<DistributionDomainName>/trainer/
https://<DistributionDomainName>/version.txt
```

세 서비스 경로가 정상 응답하고 `version.txt`가 배포한 전체 커밋 SHA와 일치해야 합니다. 카카오맵을 CloudFront 기본 도메인에서도 검증하려면 해당 도메인을 카카오 JavaScript SDK 허용 도메인에 임시 등록해야 합니다.

## 5. 데모(Pages)와 운영(CloudFront)

두 배포는 **목적도 도메인도 다릅니다.** 이 모델 하나만 따릅니다(#3021).

| | 데모 | 운영 |
| --- | --- | --- |
| 워크플로 | `.github/workflows/deploy.yml` | `.github/workflows/aws-frontend-deploy.yml` |
| 호스팅 | GitHub Pages | S3 + CloudFront |
| 백엔드 | 목업(브라우저 drift DB). 수동 `real` 은 staging 백엔드 | 운영 백엔드 고정 |
| 도메인 | GitHub Pages 기본 주소(`cse-sudo.github.io/on-care`) — 커스텀 도메인 없음 | **운영 도메인**(팀이 소유·갱신 책임을 지는 도메인). 정하기 전에는 CloudFront 기본 도메인 |
| 응답 헤더 | 바꿀 수 없음 — 앱 `index.html` 의 meta CSP 만 | 템플릿의 응답 헤더 정책(9절) |

- 데모 주소는 GitHub 이 소유한 Pages 기본 주소라 **운영 도메인·운영 인증서의 근거로 쓰지 않습니다.** 예전에 붙였던 무료 다이내믹 DNS 는 #2000 에서 뗐습니다. CloudFront 로 옮기지도 않고, Pages 배포를 중단하는 단계도 없습니다.
- 운영 도메인을 무엇으로 할지는 운영 배포를 다시 켤 때 정합니다. 이 문서와 템플릿은 그 값을 받을 자리만 둡니다(6절).
- AWS 배포에 문제가 생기거나 작업 기간 동안 배포 비용을 멈추고 싶으면 `AWS_FRONTEND_DEPLOY_ENABLED=false`로 변경해 추가 배포를 즉시 중단할 수 있습니다. 데모 사이트는 영향을 받지 않습니다. **현재가 이 상태이며**, 다시 켜는 기준은 [`frontend_deployment.md`](frontend_deployment.md#aws-배포-스위치)에 있습니다.

## 6. 운영 도메인 연결

운영 도메인이 정해진 뒤 스택 파라미터만 바꿔 붙입니다. 콘솔에서 distribution 을 직접 고치지 않습니다(다음 스택 적용이 되돌립니다).

1. `us-east-1`(CloudFront 규칙상 이 리전만 됩니다)에서 `<운영 도메인>` 용 ACM 인증서를 요청하고 **DNS 검증**으로 발급합니다. 도메인의 DNS 를 팀이 관리할 수 있어야 하고, 인증서 갱신도 같은 DNS 검증 레코드로 자동으로 됩니다.
2. 스택을 갱신합니다. 두 값은 함께 채우거나 함께 비웁니다(템플릿 `Rules` 가 한쪽만 채우면 막습니다).

   ```bash
   aws cloudformation deploy \
     --template-file infra/frontend-hosting.yml \
     --stack-name oncare-frontend \
     --capabilities CAPABILITY_IAM \
     --parameter-overrides \
       AlternateDomainName=<운영 도메인> \
       AcmCertificateArn=arn:aws:acm:us-east-1:<ACCOUNT_ID>:certificate/<ID> \
     --no-execute-changeset \
     --region ap-northeast-2
   ```

   변경 세트에서 `FrontendDistribution` 의 `Aliases`·`ViewerCertificate` 만 바뀌는지 확인한 뒤 실행합니다.
3. `<운영 도메인>` 의 DNS 를 스택 출력 `DistributionDomainName` 으로 향하게 합니다(CNAME 또는 별칭 레코드).
4. 아래 "함께 바꾸는 곳" 을 모두 반영합니다.
5. 다음 배포를 돌려 랜딩·두 앱·SPA 새로고침·카카오맵을 운영 도메인에서 확인합니다. 랜딩의 og:url·canonical 은 대체 도메인을 자동으로 씁니다([랜딩 바로가기와 og:url·canonical](frontend_deployment.md#랜딩-바로가기와-ogurlcanonical)).

되돌리려면 두 파라미터를 빈 값으로 다시 적용합니다. CloudFront 기본 도메인·기본 인증서로 돌아갑니다.

### 운영 도메인을 바꿀 때 함께 바꾸는 곳

| 위치 | 바꿀 값 | 담당 |
| --- | --- | --- |
| 카카오 개발자 콘솔 JavaScript SDK 도메인 | `https://<운영 도메인>` 추가, 옛 주소·임시 주소 제거([`backend/docs/DEPLOY.md`](../backend/docs/DEPLOY.md) "프론트 연결" 체크리스트) | #480 |
| 백엔드 `CORS_ALLOW_ORIGINS` | `https://<운영 도메인>` | #480 |
| 이 스택 `AlternateDomainName`·`AcmCertificateArn` | 위 2번 | #480 |
| 응답 헤더 CSP | 바꿀 것 없음 — 앱이 같은 출처에서 서빙되므로 `'self'` 로 충분합니다. API 주소가 바뀌면 `ApiOrigin` 을 바꿉니다 | #480 |
| 랜딩 og:url·canonical | 바꿀 것 없음 — 배포가 대체 도메인을 읽어 채웁니다 | 자동 |
| 비밀번호 재설정 메일 링크(쓰는 경우) | 백엔드 `PASSWORD_RESET_*_URL` | #480 |

## 7. 릴리스 전환과 롤백

배포는 운영 파일을 덮어쓰지 않습니다. 빌드는 커밋 SHA로 격리된 `releases/<SHA>/`에 올라가고, 그 릴리스가 온전한지 확인한 뒤에야 CloudFront distribution의 origin path를 그 prefix로 전환합니다. 전환 전에는 지금 서비스 중인 릴리스의 객체를 하나도 건드리지 않으므로, 업로드나 사전 검증이 실패하면 운영은 직전 빌드를 그대로 계속 서비스합니다.

| 단계 | 실패했을 때 |
| --- | --- |
| 빌드 · 업로드 · 릴리스 사전 검증 | 전환하지 않고 종료 — 운영은 직전 릴리스 유지 |
| origin path 전환 | 롤백 단계가 직전 origin path로 되돌리고 무효화 |
| 무효화 후 smoke check | 같음 — 자동 롤백 후 워크플로 실패 처리 |
| 응답 보안 헤더 확인([9절](#9-응답-보안-헤더-3017)) | 같음 — 헤더 정책은 스택 쪽이라 되돌린 뒤 스택 파라미터(`ApiOrigin`)를 확인 |

- 릴리스 보관: 최신 5개를 남기고 그보다 오래된 prefix는 배포 성공 시 정리합니다. 현재 릴리스와 직전 릴리스는 개수와 무관하게 항상 보존합니다.
- 버킷 버전 관리가 켜져 있어 실수로 덮어쓰거나 지운 객체도 30일 안에는 복구할 수 있습니다.
- 수동 롤백이 필요하면 distribution의 origin path를 되돌릴 릴리스로 바꾸고 `/*`를 무효화합니다.

```bash
aws cloudfront get-distribution-config --id <DISTRIBUTION_ID> \
  --query 'DistributionConfig.Origins.Items[0].OriginPath'
```

> **이 방식은 스택 갱신이 선행되어야 합니다.** 릴리스 전환에는 `cloudfront:GetDistributionConfig`·`cloudfront:UpdateDistribution` 권한이 필요하고, 버전 관리·수명 주기 규칙도 템플릿에 새로 들어갔습니다. 이 변경을 병합한 뒤 배포를 켜기 전에 `aws cloudformation deploy`를 한 번 더 실행해 주세요.
>
> 첫 전환 이후에는 버킷 루트에 남아 있는 옛 배포 파일이 더 이상 서비스되지 않습니다. 다만 그 시점의 롤백 대상이 루트이므로, 다음 릴리스가 정상 서비스되는 것을 확인한 뒤에 수동으로 정리하는 편이 안전합니다.

## 8. 배포 순서 — CI 판정과 백엔드 선후 (#3018)

운영 프론트 배포는 `main` push 에 바로 걸리지 않고 **같은 커밋의 E2E CI 가 성공으로 끝난 뒤** 시작합니다(`workflow_run`). E2E CI 는 paths 필터가 없어 모든 `main` push 에서 한 번씩 끝나므로 이것을 신호로 씁니다. 그다음 `gate` job 이 두 가지를 확인하고, 통과해야 `build-and-deploy` 가 돕니다.

1. **CI 판정**([`frontend_ci_gate.sh`](../.github/scripts/frontend_ci_gate.sh)) — 대상 커밋의 `main` push 실행을 읽습니다.

   | 워크플로 | 실행 없음 | 진행 중 | 성공 | 실패·취소 |
   | --- | --- | --- | --- | --- |
   | E2E CI | 기다림 | 기다림 | 통과 | **멈춤** |
   | User App CI·Trainer CI(paths 필터) | 통과(경로 밖) | 기다림 | 통과 | **멈춤** |

   최대 30분 기다립니다. 넘기면 실패하고, CI 가 끝난 뒤 수동으로 다시 실행합니다.
2. **백엔드 선후**([`frontend_backend_order.sh`](../.github/scripts/frontend_backend_order.sh)) — 운영 백엔드 `GET <API_BASE_URL>/version` 의 `commit_sha` 와 대상 커밋을 비교합니다.

   | 상태 | 뜻 | 결과 |
   | --- | --- | --- |
   | `same`·`no-backend-change` | 백엔드가 같은 커밋이거나, 그 뒤 `backend/` 변경이 없음 | 진행 |
   | `backend-ahead` | 백엔드가 더 새 커밋(백엔드 API 는 하위 호환을 지킴) | 진행 |
   | `pending` | 대상 커밋에 운영에 아직 없는 `backend/` 변경이 있음 | 백엔드 배포를 최대 45분 기다림. `BACKEND_DEPLOY_ENABLED` 가 꺼져 있으면 바로 멈춤 |
   | `unknown` | 백엔드가 `commit_sha` 를 알려 주지 않음 | 멈춤 — 사람이 확인한 뒤 수동 실행에서 `skip_backend_order_check` 를 켬 |

   백엔드 운영 배포가 GitHub Environment 승인을 기다리는 동안은 `pending` 으로 남습니다. 45분을 넘기면 실패하므로, 승인 뒤 프론트 배포를 다시 실행합니다.

수동 실행(`Run workflow`)은 배포할 `main` 커밋 SHA 를 받아 같은 확인을 거칩니다. 결과(확인한 CI, 백엔드 커밋, 선후 상태)는 실행의 Step Summary 에 남습니다.

> `commit_sha` 는 백엔드가 빌드 인자 `GIT_SHA` 로 받아 `/v1/version` 에 싣는 값입니다(백엔드 기동 검증 이슈 #3029). 그 변경이 운영 백엔드에 올라가기 전에는 상태가 `unknown` 이라 자동 배포가 멈춥니다.

## 9. 응답 보안 헤더 (#3017)

CloudFront 가 모든 응답에 보안 헤더를 붙입니다. meta 태그로는 걸리지 않는 HSTS·`frame-ancestors` 를 여기서 처리합니다.

| 경로 | 정책 | 내용 |
| --- | --- | --- |
| `/member/*`, `/trainer/*` | `FrontendAppResponseHeadersPolicy` | HSTS 1년(`includeSubDomains`), `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`(카메라·위치만 자기 출처), CSP — 두 앱 `web/index.html` 의 meta CSP 와 같은 지시어 + `frame-ancestors 'none'`, `connect-src` 는 `'self'`·`ApiOrigin`·CanvasKit·글꼴·카카오 SDK 출처만 |
| 그 밖(`/`, `version.txt` 등) | `FrontendLandingResponseHeadersPolicy` | 같은 보안 헤더 + 소개 페이지용 CSP(인라인 스크립트 허용, 외부 요청 `connect-src 'self'` 만) |

- 브라우저는 meta CSP 와 헤더 CSP 를 **둘 다** 적용하므로 운영에서는 헤더 쪽이 실제 한도입니다. meta 의 `connect-src https: localhost` 는 로컬 개발·데모용으로 남겨 둡니다.
- 지시어를 바꿀 때는 템플릿과 두 `index.html` 을 같이 바꿉니다. PR Gate 의 `tool/ci/test_frontend_csp.py` 가 둘이 어긋나면 막습니다.
- 웹에서 오류 보고(Sentry)를 켜면 수집 출처를 `ExtraConnectSources` 에 넣습니다(예 `https://o123.ingest.us.sentry.io`).
- `/member`·`/trainer`(끝 `/` 없음)는 `/` 를 붙인 주소로 301 이동합니다. 앱 헤더 정책이 `/member/*`·`/trainer/*` 에만 걸리기 때문입니다.
- 배포 뒤 검증 단계가 [`frontend_security_headers.sh`](../.github/scripts/frontend_security_headers.sh) 로 세 경로의 헤더를 보고, 빠졌거나 `connect-src` 가 `API_BASE_URL` 출처로 좁혀져 있지 않으면 실패 → 직전 릴리스로 되돌립니다. 손으로 볼 때는 다음과 같습니다.

  ```bash
  curl -sI https://<배포 주소>/member/ | grep -iE 'strict-transport|x-frame|content-security|referrer|x-content-type'
  ```

- HSTS preload 목록 등록은 운영 도메인이 정해진 뒤 따로 판단합니다(지금은 `preload` 없음).

## 비용 및 삭제 주의사항

- S3와 CloudFront는 사용량에 따라 과금될 수 있으므로 AWS Budget 알림을 유지합니다.
- CloudFormation 스택을 삭제해도 데이터 보호를 위해 S3 버킷은 보존됩니다.
- 다른 워크플로가 재사용할 수 있도록 스택이 생성한 GitHub OIDC 공급자도 보존됩니다. 스택을 다시 만들 때는 기존 공급자 ARN을 전달합니다.
- 완전히 정리하려면 스택 삭제 후 보존된 버킷을 비우고 별도로 삭제해야 합니다.
- 준비만 하고 당장 검증하지 않는다면 스택 생성을 미뤄 불필요한 리소스 사용을 피할 수 있습니다.
