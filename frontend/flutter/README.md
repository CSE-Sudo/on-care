# oncare-flutter

[Oncare Prototype (React/TS)](https://github.com/subin21cc/Oncareprototype) 에서 출발해 이후 **Figma 디자인 기준으로 재구성**한 On-Care 사용자 앱입니다.
**Android / iOS / Web** 3개 타깃을 단일 코드베이스로 빌드하며, 웹은 GitHub Pages에 CI 배포됩니다.

> 현재 상태: **Stage 10 — Figma 리디자인 · 실데이터 재연결 반영** (기반: Stage 9 로컬 백엔드, v0.3.0+3)
> (drift + LocalApiInterceptor 기반 로컬 백엔드 — `--dart-define=USE_MOCK_API=false` 한 줄로 FastAPI 전환 가능)

## 문서

- [docs/PLAN.md](./docs/PLAN.md) — 이식 로드맵과 [결정 이력](./docs/PLAN.md#9-결정-이력-decision-log) *(완료된 계획 문서 — 현재 구조는 STRUCTURE.md)*
- [docs/STRUCTURE.md](./docs/STRUCTURE.md) — Flutter 디렉토리 구조 및 아키텍처 의존성 규칙
- [docs/DESIGN_TOKENS.md](./docs/DESIGN_TOKENS.md) — 디자인 토큰 초안 (Figma 접근 후 보강)
- [docs/CONTRIBUTING_NOTES.md](./docs/CONTRIBUTING_NOTES.md) — 커밋 컨벤션, AI co-author trailer 미사용 정책, Phase/Stage 커밋·푸시 케이던스
- [docs/RELEASE.md](./docs/RELEASE.md) — Web/Android/iOS 수동 릴리즈 절차, SemVer 정책
- [backend/API_CONTRACT.md](../../backend/API_CONTRACT.md) — **백엔드 API 계약(단일 출처)**
- [docs/API_CATALOG.md](./docs/API_CATALOG.md) — 백엔드 구현 전 작성한 endpoint 제안 초안 *(계약의 정답은 위 API_CONTRACT.md)*
- [docs/DUMMY_BACKEND.md](./docs/DUMMY_BACKEND.md) — dummy backend 옵션 비교 *(결론이 난 검토 문서 — 채택안이 현재 LocalApiInterceptor)*
- [CHANGELOG.md](./CHANGELOG.md) — 버전별 변경 이력

## 빌드 / 실행

```bash
# 의존성
flutter pub get

# Web (개발)
flutter run -d chrome \
  --dart-define=ENV=dev \
  --dart-define=API_BASE_URL=https://dev.api.oncare.example.com

# Web (배포 빌드, GitHub Pages용 — 커스텀 도메인 ewhasudo.zapto.org/frontend)
flutter build web --release \
  --base-href "/frontend/" \
  --dart-define=ENV=prod \
  --dart-define=API_BASE_URL=https://api.oncare.example.com

# 기능별 실 백엔드 전환 (REAL_API)
# USE_MOCK_API 는 전역이라 끄면 로그인·홈·식단·운동·채팅이 한꺼번에 실서버로 넘어간다.
# 준비된 기능만 골라 실연동해 보여주고 싶을 때 쓴다. 지정하지 않으면 지금까지의
# 데모 동작과 완전히 동일하다(기본 꺼짐).
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost:8000/v1 \
  --dart-define=REAL_API=ai-coach       # AI 코치만 실 Gemini, 나머지는 목업
# 사용 가능한 키: ai-coach(/ai-coach) · auth(/auth) · diet(/diet)
# 키 → 경로 대응은 lib/core/config/app_config.dart 의 kRealApiFeatures 참고.

# Android
flutter run -d <android-device>  # debug
flutter build appbundle --release  # android/key.properties 필요(docs/mobile_release.md)

# iOS
flutter run -d <ios-device>      # debug
flutter build ios --release      # Xcode에서 archive
```

## CI / CD

`.github/workflows/`:

- **`deploy.yml`** — `push`(main) / `workflow_dispatch` 시 `flutter build web --base-href "/frontend/"` 후 정적 소개 페이지(`index.html`)와 함께 GitHub Pages에 자동 배포 → 커스텀 도메인 `https://ewhasudo.zapto.org/frontend/`

### 최초 1회 설정

워크플로우의 `actions/configure-pages@v5`에 `enablement: true`를 줘서 첫 실행 시 Pages site를 자동 provision 합니다.
권한 정책으로 자동 활성화가 막힐 경우(organization 레포 등) **수동으로 한 번만** 활성화하세요:

1. 레포 → **Settings → Pages**
2. **Source**: `GitHub Actions` 로 변경
3. Actions 탭에서 실패한 `Deploy GitHub Pages` 워크플로우를 **Re-run**

(선택) **Settings → Secrets and variables → Actions → Variables** 에 `API_BASE_URL` 등록 — 미설정 시 dev 기본값 사용

## Stage 진행 현황

- [x] **Stage 0 — Discovery & Decision** (PLAN, STRUCTURE, DESIGN_TOKENS, 결정 Q1–Q12)
- [x] **Stage 1 — Bootstrap** (flutter create, deps, lint, AppConfig, CI/CD)
- [x] **Stage 2 — Core Infrastructure** (router, theme, dio, drift, errors, l10n)
- [x] **Stage 3 — Design System** (tokens / atoms / molecules / charts / responsive / UI 카탈로그)
- [x] **Stage 4 — Features MVP** (Dashboard / Diet / Exercise / MyHealth / AICoach / Notification / Place / Auth — 모두 mock 데이터)
- [x] **Stage 5 — Integration & Polish** (nav logger, dashboard animation, MetricCard a11y, dashboard responsive layout, dashboard i18n)
- [x] **Stage 6 — Quality** (model/widget tests, golden infra w/ tag, integration smoke)
- [x] **Stage 7 — Release** (RELEASE.md guides, CHANGELOG v0.1.0+1, web Pages live)
- [x] **Stage 8 — UX Alignment** (shadcn tokens / 홈·식단·운동·My / OncareHeader / Dashboard 5-card / Calendar·QuickInput·AddEvent modals / Notification·AI-coach right-slide panels)
- [x] **Stage 9 — Local Backend** (drift schema v2 6-table / `LocalApiInterceptor` dio dispatcher / seed bootstrap / `USE_MOCK_API` 플래그로 FastAPI 단일 전환)
- [x] **Stage 10 — Figma 리디자인** (figma_kit 기준 홈·식단·운동·MY·코칭 재구성 / 핵심 데이터 흐름을 실 provider로 재연결)
