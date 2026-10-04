# 팀 작업 규약

본 문서는 On-Care 팀이 따르는 브랜치·커밋·PR·리뷰 규약을 정리한 것입니다.

---

## 1. 시작하기 전에

1. 작업할 이슈가 없다면 먼저 [Issues](https://github.com/CSE-Sudo/on-care/issues) 에 새 이슈를 등록하고, 작업 내용·기대 결과를 명시합니다.
2. 모든 작업은 main 브랜치에서 분기한 별도 브랜치에서 진행합니다.

---

## 2. 브랜치 네이밍 컨벤션

`<type>/<short-kebab-description>` 형식을 따릅니다.

| Type | 용도 | 예시 |
|---|---|---|
| `feat/` | 새 기능 | `feat/diet-add-camera-flow` |
| `fix/` | 버그 수정 | `fix/exercise-fab-overlap` |
| `docs/` | 문서 변경 | `docs/restore-repo-structure` |
| `chore/` | 빌드·설정·잡무 | `chore/add-community-files` |
| `test/` | 테스트 추가·수정 | `test/dashboard-controller` |
| `ci/` | CI/CD 워크플로우 | `ci/add-lint-step` |
| `refactor/` | 리팩토링 | `refactor/extract-mock-data` |
| `style/` | 코드 포맷팅(의미 변경 없음) | `style/lint-fix` |

---

## 3. 커밋 메시지 컨벤션

**Conventional Commits** 규격을 따릅니다. 모든 커밋 제목 앞에 type + scope 접두사를 붙입니다.

```text
<type>(<scope>): <short imperative summary>

<optional body — what & why, not how>

<optional footer — Closes #N, Co-authored-by, etc.>
```

**예시**

```text
feat(my): add 건강 지표 추이 modal for weight/BP/blood-sugar tiles
fix(deploy): use /frontend/ base-href to match custom domain
docs(readme): restore Repository Structure section reflecting current layout
chore(repo): remove unused api/ and package.json from old calculator demo
```

**Scope 표기 가이드**

- 코드 변경: 가장 가까운 feature/디렉토리명 (`diet`, `exercise`, `my`, `ui`, `flutter`, `deploy`, ...)
- 문서 변경: 대상 문서 (`readme`, `meeting`, `landing`, ...)
- 리포지토리 전체 영향: `repo`

---

## 4. Pull Request 흐름

### 4.1 PR 생성

- PR 제목은 커밋 메시지와 동일한 Conventional Commits 형식을 사용합니다.
- 본문은 [`.github/pull_request_template.md`](../.github/pull_request_template.md) 의 모든 섹션(Summary / Changes / Commits / Notes / Screenshots (Optional) / Test Plan / Related Issues / Checklist) 을 채웁니다.
- 관련 이슈가 있으면 본문에 `Closes #<issue-number>` 를 명시해 머지 시 자동 close 되도록 합니다.

### 4.2 Reviewers & Assignees

- 작성자(자기 자신)를 **Assignee** 로 지정합니다.
- 팀원 1~2명 이상을 **Reviewer** 로 지정합니다.
- 라벨은 변경 type 에 맞춰 1개 이상 부여합니다 (`documentation`, `enhancement`, `bug`, `chore`, `test`, `deploy` ...).

### 4.3 머지 정책

- 최소 1명의 reviewer approval 필요
- CI 체크(있다면) 통과 필수
- 머지 방식: **Merge commit** (히스토리 보존)
- 머지된 브랜치는 가능하면 즉시 삭제

---

## 5. 코드 리뷰 가이드

- **Bug · correctness > Design > Style** 순으로 코멘트 우선순위
- 사소한 스타일 제안은 `nit:` 접두사로 표시
- 차단성 코멘트는 `Request changes`, 의견만 남길 때는 `Comment`
- 리뷰어는 24시간 내 1차 응답을 목표로 합니다.

---

## 6. 로컬 검증 (Flutter)

`frontend/flutter/` 디렉토리에서 다음을 수행한 후 PR 을 생성합니다.

```bash
flutter analyze
flutter test
```

### 골든 테스트 (#2054)

공용 버튼(`AppButton` · `AppButtonPair`)의 생김새는 `shared/oncare_ui/test/button_goldens_test.dart` 가 기준 이미지(`shared/oncare_ui/test/goldens/*.png`)와 픽셀 단위로 비교합니다. 다른 위젯 테스트는 동작만 보므로, 색·크기·간격·변형이 조용히 바뀌는 것은 여기서만 잡힙니다. 회원 앱 CI 의 공용 패키지 단계에서 돕니다.

**골든은 Linux(CI)에서만 비교합니다.** 같은 Flutter 3.44.9 라도 Windows·macOS 는 글자 가장자리를 조금 다르게 그려 기준과 1% 남짓 어긋납니다. 그래서 기준 이미지는 CI 가 그린 것이고, 다른 OS 에서 `flutter test` 를 돌리면 골든만 `Skip` 으로 건너뜁니다(나머지 테스트는 그대로 돕니다). 글자가 네모 블록으로 나오는 것도 정상입니다 — 글자 모양이 아니라 크기·색·간격을 지키는 테스트입니다.

**CI 에서 골든이 깨지면** 실행 화면의 **Artifacts → `oncare-ui-golden-failures`** 에 이미지가 올라옵니다. 기준(`_masterImage`)·실제(`_testImage`)·차이(`_isolatedDiff`)를 열어 봅니다.

- 의도하지 않은 변화면 코드를 고칩니다.
- **의도한 변화면 CI 가 그린 실제 이미지를 새 기준으로 받습니다.** 저장소 루트에서, `<run-id>` 는 실패한 실행 주소의 숫자입니다.

```bash
gh run download <run-id> -n oncare-ui-golden-failures -D /tmp/goldens
for f in /tmp/goldens/*_testImage.png; do
  cp "$f" "shared/oncare_ui/test/goldens/$(basename "$f" _testImage.png).png"
done
```

  바뀐 PNG 를 커밋하고, PR 본문에 무엇이 왜 바뀌었는지 적습니다. 리뷰어는 GitHub 의 이미지 diff 로 전후를 비교합니다.

Linux 에서 작업한다면 `cd shared/oncare_ui && flutter test --update-goldens test/button_goldens_test.dart` 로 바로 뽑아도 같은 결과가 나옵니다.

---

## 6.1 GitHub Actions 고정

`.github/workflows/` 의 모든 `uses:` 는 **커밋 SHA 로 고정**하고 뒤에 `# vX.Y.Z` 주석을 답니다.
태그는 옮길 수 있어서, 태그로 두면 아무도 코드를 건드리지 않았는데 파이프라인이 하는 일이
바뀝니다. 그 파이프라인이 공개 사이트를 올립니다.

올릴 때는 의도적으로 올립니다 — 새 SHA 와 주석을 함께 바꾸고, 그 워크플로가 실제로 도는 것을
확인한 뒤 머지합니다. SHA 는 이렇게 확인합니다.

```bash
gh api repos/actions/checkout/git/ref/tags/v4 --jq .object.sha
```

---

## 6.2 의존성 업데이트 PR (#2837)

Dependabot 이 매주 월요일 오전에 생태계별로 묶은 업데이트 PR 을 엽니다
([`.github/dependabot.yml`](../.github/dependabot.yml)) — 백엔드(pip), GitHub Actions,
회원 앱·트레이너 웹(pub). 백엔드·두 앱의 주 버전 변경은 자동 PR 로 받지 않습니다(#2978).

- **부·수 버전 묶음**: CI 가 모두 초록이면 담당 영역 사람이 변경 기록(릴리스 노트)만 훑고
  병합합니다. 한 패키지 때문에 깨지면 그 패키지만 묶음에서 빼고(`@dependabot ignore this
  minor version`) 나머지를 병합합니다.
- **주 버전 변경**: Dependabot 이 열지 않습니다. 올려야 할 때는 패키지별로 이슈를 만들어
  마이그레이션 안내와 필요한 코드 수정 범위를 적고, 그 이슈의 PR 에서 버전과 코드를 함께
  올립니다. 취약점 때문에 열리는 보안 업데이트 PR 은 주 버전이어도 열리므로 우선 처리합니다.
- **백엔드 잠금 파일**: `requirements.txt`·`requirements-dev.txt` 는 손으로 고치지 않습니다.
  직접 의존을 바꿀 때는 `requirements.in`(·`requirements-dev.in`)을 고친 뒤 잠금 파일을
  다시 만듭니다(절차는 [backend/README.md](../backend/README.md) "의존성").
- **취약점 경고**: 백엔드 CI 의 `Dependency audit (pip-audit)` 잡이 잠금 파일의 알려진
  취약점을 요약에 남깁니다. 지금은 경고 모드라 병합을 막지 않지만, 경고가 뜨면 해당
  패키지 업데이트를 우선 처리합니다.

## 6.3 비밀값 스캔 (#2837)

PR gate 가 PR 의 새 커밋을 gitleaks 로 검사합니다([`.gitleaks.toml`](../.gitleaks.toml)).
걸리면 값을 지우는 커밋을 더하는 것만으로는 부족합니다 — 이력에 남으므로 그 커밋을
고쳐 다시 푸시하고, 실제 키였다면 즉시 교체합니다. 예시 파일에는 `CHANGE_ME_…` 처럼
자리표시자임이 이름에서 드러나는 값만 둡니다. 정말 오탐인 한 줄은 줄 끝에
`gitleaks:allow` 주석을 달고 PR 에 이유를 적습니다.

저장소 설정의 Secret scanning·Push protection(Settings → Code security)도 켜 두면 푸시
단계에서 한 번 더 막습니다. 저장소 관리자가 확인합니다.

## 6.4 운영 배포 승인 (#3019)

운영 배포(백엔드 `Backend Deploy`, 프런트 `Deploy Frontend to AWS`)는 GitHub Environment `production` 에서
돕니다. 배포 브랜치는 `main` 만이고, Environment 에 승인자가 지정돼 있으면 **병합 뒤 배포가 승인을 기다립니다.**

- 승인자는 Actions 실행 화면의 "Review deployments" 에서 커밋·변경 내용을 보고 승인합니다. 배포 기록은
  저장소 Environments 화면에 남아 "지금 운영에 무엇이 떠 있는지"를 거기서 봅니다.
- 백엔드는 staging 이 켜져 있으면 staging 을 먼저 배포·검증하고, 통과해야 운영 승인 단계로 갑니다.
- 배포 뒤 검증(healthz·readyz)이 실패하면 백엔드는 직전 이미지로, 프런트는 직전 릴리스 경로로 스스로
  되돌립니다. 워크플로는 실패로 남으니 원인을 고친 PR 을 다시 병합합니다.
- 스키마를 바꾸는 PR 은 **직전 이미지와도 함께 돌 수 있게** 나눕니다(칸 삭제·이름 변경은 두 번에 나눠 병합) —
  되돌리기는 이미지만 되돌리고 마이그레이션은 되돌리지 않습니다([`backend/docs/DEPLOY.md`](../backend/docs/DEPLOY.md) 2절).

---

## 7. 이슈 사용

- 새 작업은 가능한 한 **이슈 → PR → Closes** 흐름을 유지합니다.
- 이슈 본문 구조: **Background / Tasks / Expected Result** 3개 섹션 권장.

---

## 8. 질문이 있다면

- 협업 규약 관련: [Issues](https://github.com/CSE-Sudo/on-care/issues) 에 `question` 라벨로 등록
