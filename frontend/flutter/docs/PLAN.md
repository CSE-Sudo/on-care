# Oncare Flutter — 재구성 계획서

> **[완료된 계획 문서]** React 프로토타입 → Flutter 이식은 끝났고, 이후 Figma 재구성까지
> 반영된 상태입니다. 아래 로드맵과 화면 구성은 **당시 계획 시점의 기록**이라 현재 코드와
> 다를 수 있습니다. 결정 이력(§9)을 되짚을 때 참고하고, **현재 구조는 아래를 보세요.**
>
> - 디렉토리 구조·의존성 규칙 → [STRUCTURE.md](./STRUCTURE.md)
> - 커밋 규약 → [CONTRIBUTING_NOTES.md](./CONTRIBUTING_NOTES.md)
> - 백엔드 API 계약 → [backend/API_CONTRACT.md](../../../backend/API_CONTRACT.md)

---

## 1. 프로젝트 개요

| 항목 | 값 |
| --- | --- |
| 코드명 | `oncare-flutter` |
| 목적 | Oncare 프로토타입(React/TS)을 Flutter로 재구현하여 **Android / iOS / Web** 단일 코드베이스로 제공 |
| 도메인 | 헬스케어(식단·운동·건강 기록·AI 코치·알림·장소 추천) |
| Flutter | `3.38.x` (stable) / Dart `3.10+` |
| 빌드 타깃 | `android`, `ios`, `web` (web은 GitHub Pages 정적 호스팅) |
| 디자인 원본 | Figma — `on-care prototype` (별도 링크 확인 필요) |
| 라이브 데모(원본) | `oncare-prototype.vercel.app` |

### 1.1 원본 앱 구조 요약

원본 React 앱은 SPA 단일 라우트에서 `activeTab` state로 네 개 메인 화면을 스위치합니다.

```
원본 화면 트리
├─ BottomNav (4 tabs)
│   ├─ Dashboard         ← 홈
│   ├─ DietRecord        ← 식단 기록
│   ├─ Exercise          ← 운동
│   └─ MyHealth          ← 내 건강
└─ 보조 화면/컴포넌트
    ├─ AICoach           ← AI 코칭 (모달 또는 별도 진입)
    ├─ NotificationPanel ← 알림 패널
    ├─ Place             ← 장소 추천
    └─ Header            ← 상단 헤더
```

UI 의존: MUI + Radix UI + Tailwind + shadcn/ui + Recharts + react-hook-form + framer-motion.
Flutter 재구성 시 위 의존성은 **Flutter native 위젯 + 자체 디자인 시스템 + fl_chart**로 치환합니다.

---

## 2. 기술 스택 (제안)

| 영역 | 채택안 | 이유 / 대안 |
| --- | --- | --- |
| 상태관리 | **Riverpod v2 + riverpod_generator** | 컴파일타임 안전성, DI 통합, 테스트 용이. 대안: Bloc(보일러플레이트↑), Provider(기능↓) |
| 라우팅 | **go_router** + ShellRoute | Web URL/딥링크/BottomNav 셸 라우트 1급 지원 |
| 모델/직렬화 | **freezed + json_serializable** | 불변 데이터 클래스, sealed union |
| 네트워크 | **dio + retrofit** | 인터셉터·캐싱, mock-first 진행 |
| 로컬 저장소 | **drift**(시계열/관계 데이터) + **flutter_secure_storage**(토큰) + **shared_preferences**(설정) | 헬스 기록 같은 시계열은 SQLite/drift가 적합. 대안: isar |
| 차트 | **fl_chart** | Recharts 대체. 활성 메인테인, 커스텀 범례·툴팁 OK |
| 폼 | **flutter_hooks + reactive_forms** 또는 자체 컨트롤러 | react-hook-form 대체. MVP는 자체 컨트롤러로 단순화 권장 |
| 애니메이션 | **flutter_animate** + 기본 `AnimatedXxx` | framer-motion 대체 |
| 아이콘 | **material_symbols_icons** 또는 자체 SVG 세트 | shadcn icon 대체 |
| 다국어 | **flutter_localizations + intl + slang** 중 택1 | MVP는 intl, 본격화되면 slang 검토 |
| 푸시/알림 | **firebase_messaging** | (선택) 백엔드 결정 후 |
| 로깅 | **logger** + **sentry_flutter**(선택) | Crashlytics와 양자택일 |
| 테스트 | flutter_test + **mocktail** + **golden_toolkit** | mockito 대비 codegen 불필요 |
| 린트 | **flutter_lints** + 일부 커스텀 룰 | 또는 `very_good_analysis` |

> 위 스택은 1차 제안입니다. Stage 0에서 사용자가 결정 후 확정합니다.

---

## 3. 디렉토리 구조 (요약)

상세 설명·각 폴더 책임은 [STRUCTURE.md](./STRUCTURE.md) 참고.

```
oncare-flutter/
├─ .github/
│  └─ workflows/           # CI/CD (analyze, test, deploy web)
├─ android/                # Flutter 자동 생성 (네이티브)
├─ ios/                    # Flutter 자동 생성 (네이티브)
├─ web/                    # Flutter 자동 생성 (HTML/manifest)
├─ assets/
│  ├─ fonts/
│  ├─ icons/
│  ├─ images/
│  └─ i18n/                # 다국어 리소스 (선택)
├─ docs/
│  ├─ PLAN.md              # 본 문서
│  ├─ STRUCTURE.md         # 디렉토리/아키텍처 상세
│  └─ CONTRIBUTING_NOTES.md# 커밋/기여 규약 (co-author 미표시 포함)
├─ lib/
│  ├─ main.dart            # 엔트리 (환경별 main_dev.dart 등 분기 가능)
│  ├─ app/                 # 앱 셸 (App 위젯, 라우터, 테마)
│  ├─ core/                # 설정·네트워크·저장소·에러·유틸
│  ├─ shared/              # 도메인 무관 공용 위젯/모델/서비스
│  ├─ design_system/       # 토큰·테마·atom 위젯 (자체 UI 키트)
│  ├─ features/            # 피처 모듈 (수직 슬라이스)
│  │  ├─ dashboard/
│  │  ├─ diet/
│  │  ├─ exercise/
│  │  ├─ my_health/
│  │  ├─ ai_coach/
│  │  ├─ notification/
│  │  └─ place/
│  ├─ l10n/                # ARB 파일
│  └─ gen/                 # 자동 생성(.g.dart, .freezed.dart, l10n)
├─ test/                   # 단위·위젯 테스트 (lib/ 미러)
├─ integration_test/       # E2E
├─ scripts/                # build, release, gen 스크립트
├─ analysis_options.yaml
├─ pubspec.yaml
└─ README.md
```

각 `features/<name>/` 하위는 다음 패턴을 따릅니다:

```
features/dashboard/
├─ data/         # DTO, API/local source, repository 구현
├─ domain/       # 엔티티, repository 인터페이스, usecase (선택)
└─ presentation/
   ├─ pages/     # 라우트 진입 화면
   ├─ widgets/   # 화면 전용 위젯
   └─ controllers/  # Riverpod notifier / provider
```

---

## 4. 전체 로드맵 (Stage × Phase)

각 Phase는 **산출물(Deliverables)** 기준으로 종료 판단합니다. 표의 ⏱은 대략적인 작업 단위(MD = man-day) 추정이며 실제 실행 후 조정합니다.

### Stage 0 — Discovery & Decision  *(현재 단계)*

| Phase | 내용 | 산출물 | ⏱ |
| --- | --- | --- | --- |
| 0.1 | 원본 React 코드/Figma 정밀 분석 | 화면별 컴포넌트 매핑 표 | 1 MD |
| 0.2 | 기술 스택 결정 (§2 검토) | 본 문서 §2 확정 | 0.5 MD |
| 0.3 | 디자인 토큰 추출 (color/spacing/radius/typo) | `docs/DESIGN_TOKENS.md` | 1 MD |
| 0.4 | 백엔드 전략 확정 (mock / Firebase / 자체) | 결정 기록 | 0.5 MD |

**Exit 조건**: §2 표 확정, 디자인 토큰 표 작성, 백엔드 전략 결정.

---

### Stage 1 — Project Bootstrap

| Phase | 내용 | 산출물 | ⏱ |
| --- | --- | --- | --- |
| 1.1 | `flutter create .` (org/platforms 지정) | `android/`, `ios/`, `web/` 생성 | 0.5 MD |
| 1.2 | 디렉토리 골격 생성 (lib 하위) | §3 디렉토리 트리 | 0.5 MD |
| 1.3 | `pubspec.yaml` 의존성 추가 + lock | 빌드 통과 | 0.5 MD |
| 1.4 | `analysis_options.yaml` 린트 규칙 | `flutter analyze` 통과 | 0.5 MD |
| 1.5 | 환경별 엔트리포인트(main_dev/main_prod) | flavors 또는 `--dart-define` | 0.5 MD |
| 1.6 | GitHub Actions CI (analyze + test) | `ci.yml` 통과 | 1 MD |
| 1.7 | GitHub Actions CD (web → gh-pages) | PR 머지 시 자동 배포 | 1 MD |

**Exit 조건**: 빈 앱이 Android/iOS/Web 모두 빌드되고 main 브랜치 푸시 시 GitHub Pages가 자동 갱신.

---

### Stage 2 — Core Infrastructure

| Phase | 내용 | 산출물 | ⏱ |
| --- | --- | --- | --- |
| 2.1 | 라우터 골격 (go_router + ShellRoute + BottomNav) | 4탭 스켈레톤 | 1 MD |
| 2.2 | Riverpod 통합 (ProviderScope, observer) | 글로벌 상태 골격 | 0.5 MD |
| 2.3 | 테마/디자인 토큰 → ThemeData | light/dark 토글 | 1 MD |
| 2.4 | API 클라이언트 (dio + retrofit + mock) | 더미 API 호출 성공 | 1 MD |
| 2.5 | 로컬 저장소 (drift schema, secure storage) | 더미 read/write | 1 MD |
| 2.6 | 에러 핸들링 / 로깅 (Result 타입, AppError sealed) | 글로벌 에러 페이지 | 0.5 MD |
| 2.7 | l10n 골격 (`ko`, `en` ARB) | 텍스트 외부화 동작 | 0.5 MD |

**Exit 조건**: BottomNav 셸에서 4개 빈 페이지 이동, 더미 API/DB 호출 데모, 다국어 토글.

---

### Stage 3 — Shared UI Kit (디자인 시스템)

| Phase | 내용 | 산출물 | ⏱ |
| --- | --- | --- | --- |
| 3.1 | 디자인 토큰 위젯화 (`AppColors`, `AppTypography`, `AppSpacing`) | `design_system/tokens/` | 1 MD |
| 3.2 | Atom 위젯 (Button, Card, Input, Badge, Avatar) | 카탈로그 페이지 | 2 MD |
| 3.3 | Molecule (ListTile 변형, MetricCard, ChartCard) | 카탈로그 페이지 | 1 MD |
| 3.4 | 반응형 레이아웃 헬퍼 (mobile/tablet/desktop breakpoints) | `AppBreakpoints` | 0.5 MD |
| 3.5 | 차트 래퍼 (fl_chart) — 라인/바/도넛 | 데모 페이지 | 1 MD |

**Exit 조건**: `/dev/ui-catalog` 라우트에서 모든 토큰/위젯 시연 가능.

---

### Stage 4 — Feature Implementation (MVP)

각 Feature는 동일 패턴: **mock 데이터 → repository → controller(Riverpod) → page/widget → 단위 테스트**.

| Phase | 화면 | 핵심 요소 | ⏱ |
| --- | --- | --- | --- |
| 4.1 | Dashboard | 오늘 요약 카드(영양/운동/건강 지표), AI 코치 진입, 알림 진입 | 2 MD |
| 4.2 | Diet Record | 식단 입력(폼), 식사별 카드 리스트, 영양소 차트 | 3 MD |
| 4.3 | Exercise | 운동 기록 입력, 주간/월간 통계, 차트 | 2 MD |
| 4.4 | My Health | 체중/혈압 등 생체 지표 입력, 추세 차트, 목표 | 2 MD |
| 4.5 | AI Coach | 대화/추천 카드 UI (응답은 mock 또는 외부 API) | 2 MD |
| 4.6 | Notification Panel | 알림 리스트, 읽음 상태, 카테고리 필터 | 1 MD |
| 4.7 | Place | 추천 장소 카드/지도(웹은 map 라이브러리 제약 검토) | 2 MD |

**Exit 조건**: 모든 화면 mock 데이터로 동작, 단위 테스트 커버리지 60%+.

---

### Stage 5 — Integration & Polish

| Phase | 내용 | 산출물 | ⏱ |
| --- | --- | --- | --- |
| 5.1 | 네비게이션 흐름 통합 (모달/딥링크) | 사용자 시나리오 OK | 1 MD |
| 5.2 | 애니메이션/트랜지션 다듬기 | 60fps 체감 | 1 MD |
| 5.3 | 접근성 (Semantics, 텍스트 스케일, 대비) | a11y 체크리스트 | 1 MD |
| 5.4 | 반응형 / 웹 최적화 (lazy load, 분할 빌드) | Lighthouse Performance ≥ 80 | 1 MD |
| 5.5 | i18n 적용 (ko/en 텍스트 100%) | ARB 누락 0 | 1 MD |

**Exit 조건**: 사용자 시나리오 워크스루, 웹 Lighthouse 80+, 접근성 위반 0.

---

### Stage 6 — Quality

| Phase | 내용 | 산출물 |
| --- | --- | --- |
| 6.1 | 단위 테스트 (model/repo/controller) | 커버리지 ≥ 70% |
| 6.2 | 위젯 테스트 (page별 happy/edge) | 주요 페이지 100% |
| 6.3 | 골든 테스트 (디자인 시스템 atom/molecule) | 시각 회귀 가드 |
| 6.4 | 통합 테스트 (`integration_test/`) | 핵심 플로우 1~3개 |

**Exit 조건**: CI에서 모든 테스트 그린, 커버리지 게이트 통과.

---

### Stage 7 — Release

| Phase | 내용 | 산출물 |
| --- | --- | --- |
| 7.1 | Web → GitHub Pages 정식 배포 | `https://<user>.github.io/oncare-flutter/` |
| 7.2 | Android release build (서명, 버전 코드 자동화) | `.aab` |
| 7.3 | iOS release build (provisioning, TestFlight) | `.ipa` |
| 7.4 | 버전 정책 / CHANGELOG / 릴리즈 노트 | `CHANGELOG.md` |

**Exit 조건**: 세 플랫폼 모두 검증 가능한 빌드 산출. 웹은 라이브 URL 보유.

---

## 5. CI/CD 전략

### 5.1 워크플로우 구성

```
.github/workflows/
├─ ci.yml             # PR/push: format + analyze + test (필수)
├─ deploy-web.yml     # main 푸시: flutter build web → gh-pages 배포
├─ android-release.yml# 태그 푸시: aab 빌드 + 아티팩트 업로드
└─ ios-release.yml    # 태그 푸시: ipa 빌드 (macOS runner)
```

### 5.2 GitHub Pages 배포 노트

- **base-href**는 레포 이름과 일치시켜야 함:
  `flutter build web --release --base-href "/oncare-flutter/"`
- **URL 전략**: GitHub Pages는 SPA fallback이 없으므로 둘 중 하나
  - (A) `setUrlStrategy(const HashUrlStrategy())` — 안전, URL에 `#` 들어감
  - (B) `404.html`을 `index.html`과 동일하게 두고 PathUrlStrategy 사용 — URL 깔끔
- **렌더러**: 초기 MVP는 `--web-renderer canvaskit`(품질) / 경량화는 `html`. WASM은 추후 검토.
- **배포 방식**: `peaceiris/actions-gh-pages` 또는 공식 `actions/deploy-pages`(권장).

### 5.3 환경 변수 / 시크릿

| 시크릿 | 용도 |
| --- | --- |
| `IOS_DIST_CERT_P12` / `IOS_PROVISIONING_PROFILE` | iOS 서명 |
| `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` | Android 서명 |
| `SENTRY_DSN`(선택) | 크래시 리포트 |
| `API_BASE_URL` | 환경별 API 엔드포인트 |

---

## 6. 커밋·기여 규약 (요지)

- **AI co-author trailer 금지** — `Co-Authored-By: Claude …` 같은 줄을 어떤 커밋에도 포함하지 않습니다. 사용자가 직접 자신의 이름으로만 커밋합니다.
- 커밋 메시지: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- 자세한 내용은 [CONTRIBUTING_NOTES.md](./CONTRIBUTING_NOTES.md) 참고.

---

## 7. 결정 필요 사항 (사용자 확인 요청)

> ✅ **모두 결정됨 (2026-05-20)**. 아래 표는 의사결정 원본 옵션이며, 최종 결과 및 영향은 [§9 결정 이력](#9-결정-이력-decision-log) 참고.

다음 항목을 결정해 주시면 Stage 0을 종료하고 Stage 1에 진입할 수 있습니다.

| # | 결정 항목 | 옵션 | 영향 |
| --- | --- | --- | --- |
| Q1 | **백엔드 전략** | (a) Mock-only(현재 prototype 수준) / (b) Firebase(Auth+Firestore+FCM) / (c) 자체 REST 서버 / (d) 추후 결정 | 데이터 모델·인증·푸시 설계 |
| Q2 | **상태관리** | (a) Riverpod (제안) / (b) Bloc / (c) Provider | 학습 곡선, 보일러플레이트 |
| Q3 | **로컬 DB** | (a) drift(SQLite) (제안) / (b) isar(NoSQL) / (c) prefs만 (당장은 단순) | 모델 복잡도, 마이그레이션 |
| Q4 | **인증** | (a) 없음(프로토타입) / (b) 이메일+비번 / (c) 소셜(Apple/Google/Kakao) | UI/UX, 정책 |
| Q5 | **다국어** | (a) 한국어 only / (b) ko + en | 텍스트 외부화 부하 |
| Q6 | **디자인 충실도** | (a) Figma 1:1 pixel-perfect / (b) Material 3 기반 + Oncare 토큰 (제안) | 개발 속도 / 디자인 정합성 |
| Q7 | **AI Coach 백엔드** | (a) Mock 응답 / (b) Anthropic·OpenAI API 직결 / (c) 자체 백엔드 프록시 | 키 관리·비용 |
| Q8 | **지도(Place)** | (a) 카드 리스트만 / (b) Google Maps Flutter / (c) Naver/Kakao Map (web 제약 있음) | 라이선스, 웹 호환 |
| Q9 | **푸시 알림** | (a) 인앱 패널만 (MVP) / (b) FCM 통합 | 백엔드 결정과 연동 |
| Q10 | **GitHub Pages URL 전략** | (a) Hash (`/#/dashboard`) (안전) / (b) Path + 404 fallback (깔끔) | 배포 안정성 vs URL 미관 |
| Q11 | **레포 가시성/위치** | 어느 GitHub 계정/조직에 push할지 (`<user>/oncare-flutter`?) | base-href, Pages 도메인 |
| Q12 | **CI에서 iOS/Android 릴리즈 빌드도 자동화할지** | (a) 웹만 / (b) 전체 | 시크릿 셋업 부하 |

---

## 8. 다음 단계 (Immediate Next Steps)

1. 위 §7 결정 사항 확인 (특히 Q1, Q2, Q11)
2. `docs/STRUCTURE.md` 검토
3. Stage 1.1 — `flutter create .` 실행 (사용자 승인 후)
4. `pubspec.yaml` 초안 작성
5. GitHub Actions CI 초안 `.github/workflows/ci.yml` 작성

> 본 계획은 살아있는 문서입니다. Stage 종료 시점마다 회고를 반영해 갱신합니다.

---

## 9. 결정 이력 (Decision Log)

### 9.1 2026-05-20 — Stage 0 종료, 사용자 확정

| # | 항목 | 결정 | 영향 / 후속 작업 |
| --- | --- | --- | --- |
| Q1 | 백엔드 | **자체 REST 서버** | `core/network`에 dio + retrofit 기반 클라이언트. `API_BASE_URL`을 `--dart-define`으로 주입. 환경별 base URL은 `AppConfig`에서 노출. |
| Q2 | 상태관리 | **Riverpod v2 + riverpod_generator** *(제안 채택)* | §2 채택안 그대로. ProviderScope는 `app/bootstrap.dart`에서 설치. |
| Q3 | 로컬 DB | **drift (SQLite)** + secure_storage + shared_preferences *(제안 채택)* | `core/storage/`에 drift database. 마이그레이션 정책은 Stage 2.5에서 결정. |
| Q4 | 인증 | **소셜 4종 — Apple / Google / Kakao / Naver** | `features/auth/` 모듈 신설. `AuthRepository`가 4개 provider를 추상화. SDK 키는 dart-define + native placeholder. |
| Q5 | 다국어 | **ko + en** | `lib/l10n/app_ko.arb`, `app_en.arb`. 기본 로케일은 ko. |
| Q6 | 디자인 충실도 | **Material 3 + Oncare 토큰** *(제안 채택)* | 자체 `design_system/tokens/`에서 토큰 정의 후 `ThemeData`로 매핑. |
| Q7 | AI Coach | **Mock 응답** | `features/ai_coach/data/`에 mock JSON 시드. repository 인터페이스는 그대로 두고 추후 백엔드 프록시로 교체. |
| Q8 | 지도(Place) | **google_maps_flutter** | iOS/Android/Web 모두 지원. API 키 3종(또는 통합 1종) 필요 — Stage 4.7 진입 전에 확보. |
| Q9 | 푸시 알림 | **인앱 패널 + 가상 push 시뮬레이션** | `firebase_messaging` 미사용. `features/notification/`에 NotificationCenter 구현 — 타이머/이벤트로 알림 카드가 등장하는 형태. |
| Q10 | Web URL 전략 | **Hash URL** | `main.dart` 부트스트랩에서 `setUrlStrategy(const HashUrlStrategy())`. GitHub Pages 404 fallback 불필요. |
| Q11 | GitHub 레포 | **개인 저장소 `oncare-flutter`** (당시) | base-href `/oncare-flutter/`. *(지금은 팀 저장소 `CSE-Sudo/on-care` 의 `main` 에서 <https://cse-sudo.github.io/on-care/member/> 로 배포한다.)* |
| Q12 | CI 자동화 | **Web만 자동화** | `.github/workflows/ci.yml`(검사) + `deploy-web.yml`(Pages). Android/iOS 릴리즈 빌드는 수동. |

### 9.2 §2 기술 스택 변경 영향

위 결정으로 §2 채택안에서 다음이 조정됩니다.

- **추가 의존성**
  - `google_maps_flutter` (Q8)
  - `sign_in_with_apple` (Q4 — Apple)
  - `google_sign_in` (Q4 — Google)
  - `kakao_flutter_sdk_user` (Q4 — Kakao)
  - `flutter_naver_login` (Q4 — Naver)
- **제거/연기**
  - `firebase_messaging` (Q9 → 인앱 패널만)
- **유지**
  - 나머지 §2 채택안 그대로(Riverpod / go_router / freezed / dio·retrofit / drift / fl_chart / intl / mocktail 등)

### 9.3 보안·키 관리 노트

- 소셜 SDK 키(특히 Kakao Native App Key, Naver Client ID/Secret)는 **빌드 시점에** 주입:
  - Dart 쪽: `--dart-define=KAKAO_NATIVE_KEY=… --dart-define=NAVER_CLIENT_ID=…`
  - 네이티브 쪽: `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`의 placeholder + `String.xml` / `xcconfig`로 분리
- 비밀값은 절대 `lib/` 하드코딩 금지. `core/config/AppConfig`에서 dart-define 읽기.
- 자체 REST 토큰은 `flutter_secure_storage`에 저장, dio interceptor가 갱신.

### 9.4 커밋·푸시 케이던스 (운영 규칙)

- 각 **Phase** 종료 시 → `git commit` (push 없음).
- 각 **Stage** 종료 시 → `git commit && git push origin main`.
- 자세한 규약: [CONTRIBUTING_NOTES.md](./CONTRIBUTING_NOTES.md).

### 9.5 2026-05-20 — Stage 9 (Local backend) 결정 사항

Stage 9 시작 전 사용자가 결정한 6개 항목 (D1..D6).

| # | 항목 | 결정 | 구현 |
| --- | --- | --- | --- |
| D1 | 더미 백엔드 방식 | **drift 기반 LocalApiInterceptor (옵션 C)** | `core/network/interceptors/local_api_interceptor.dart` — `_routes` 맵 + per-handler 메서드. `USE_MOCK_API=true` 일 때 wire. |
| D2 | 케이스 매핑 | **snake_case (FastAPI Pydantic alias 컨벤션)** ↔ **camelCase (Dart)** | `core/network/case_mapper.dart` — `toCamelCaseJson` / `toSnakeCaseJson` 재귀 변환. fromJson 팩토리들이 snake_case 키를 읽음. |
| D3 | drift 스키마 v2 | **6개 테이블** (AppKeyValues / DietEntries / ExerciseSessions / Vitals / ScheduleEvents / NotificationItems) | `core/storage/app_database.dart` schemaVersion=2 + onUpgrade 마이그레이션. |
| D4 | seed 정책 | **첫 실행 1회만** (`seeded_v1` 플래그) | `core/storage/seed_data.dart` `seedIfEmpty(db)`. React mock 데이터를 그대로 주입. |
| D5 | swap 전략 | **interceptor 우선 dispatch → 미매핑 path는 fall-through** | `LocalApiInterceptor.onRequest()` 가 `null` 반환 시 다음 인터셉터로. `USE_MOCK_API=false` 빌드면 FastAPI에 그대로 도달. |
| D6 | 테스트 | **각 endpoint LocalApi 단위 + 기존 controller mock-repo 전환** | `test/core/network/local_api_interceptor_*_test.dart` (7 파일) + 각 feature controller test override. |

### 9.6 Stage 9 — 엔드포인트 매트릭스

| Phase | 엔드포인트 | drift 의존 테이블 | 비고 |
| --- | --- | --- | --- |
| 9.4 | `GET /diet/days/today` | DietEntries | 칼로리/나트륨/당류 누계 |
| 9.5 | `POST /vitals/{kind}`, `GET /vitals/{kind}/latest` | Vitals | weight / blood-pressure / blood-sugar 3종 |
| 9.6 | `GET /exercise/weeks/current` | ExerciseSessions | 월~일 daily_minutes 집계 + streak |
| 9.7 | `GET /schedule/events?date=`, `GET /notifications` | ScheduleEvents, NotificationItems | time_ago Korean formatter |
| 9.8 | `GET /dashboard/summary` | Diet + Exercise + Vitals + Schedule | week_score 휴리스틱 (50 + cal*25 + ex*25) |
| 9.9 | `GET /ai-coach/feedback`, `GET /users/me`, `GET /users/me/health`, `GET /places/nearby` | (정적) | drift 사용 안 함 — 정적 demo payload |
| — | `GET /ping`, `GET /healthz`, `GET /version` | — | 기존 헬스체크 (Stage 9.3에서 도입) |

### 9.7 FastAPI 전환 시 (D5 swap)

- 빌드 명령에 `--dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=https://api.oncare.dev` 추가 → `LocalApiInterceptor`가 wire되지 않고 모든 호출이 FastAPI로 라우팅.
- 응답 contract는 그대로 (snake_case + 동일 JSON shape). fromJson 팩토리는 재사용.
- 검증: integration test (smoke) → `assets/api/contract_*.json` 으로 fixture를 두고 LocalApi 응답과 동일한 shape인지 확인.
