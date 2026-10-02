# Oncare Flutter — 디렉토리 구조 & 아키텍처

> [PLAN.md](./PLAN.md)의 §3을 보완하는 문서입니다. 폴더별 책임 경계와 import 규칙을 정의합니다.

---

## 1. 최상위 디렉토리

```
frontend/flutter/       # 모노레포 안의 회원 앱 (워크플로는 저장소 루트 .github/workflows/)
├─ .github/             # 별도 저장소 시절의 잔재 — GitHub Actions 가 실행하지 않음
├─ android/             # Android 네이티브 (flutter create 산출)
├─ ios/                 # iOS 네이티브 (flutter create 산출)
├─ web/                 # 웹 진입 파일 (index.html, manifest.json, favicon)
├─ assets/              # 정적 리소스 (이미지/폰트/아이콘)
├─ docs/                # 본 문서 등 설계·계획 문서
├─ lib/                 # Dart 소스
├─ test/                # 단위·위젯 테스트 (lib 미러 구조)
├─ integration_test/    # E2E 테스트
├─ scripts/             # 빌드/배포/codegen 보조 스크립트
├─ analysis_options.yaml
├─ pubspec.yaml
├─ pubspec.lock
└─ README.md
```

### 1.1 자동 생성 폴더(`android/`, `ios/`, `web/`)
- `flutter create .` 명령으로 생성되며, 네이티브 부분은 가능한 한 직접 수정하지 않습니다.
- 직접 수정이 불가피한 경우(서명, manifest, 권한 등) 변경 사유를 commit message에 기록합니다.

### 1.2 `assets/`

```
assets/
├─ fonts/         # 커스텀 폰트 (.ttf/.otf) — pubspec.yaml에 등록
├─ icons/         # 단색 아이콘 SVG/PNG
├─ images/        # 일반 이미지 (로고, 일러스트 등)
│  ├─ 1.0x/
│  ├─ 2.0x/
│  └─ 3.0x/
└─ i18n/          # (옵션) ARB 외 다국어 리소스
```

---

## 2. `lib/` — 애플리케이션 코드

### 2.1 최상위 레이아웃

```
lib/
├─ main.dart             # 공통 부트스트랩 (환경별 main_*.dart에서 호출)
├─ main_dev.dart         # dev 엔트리 (선택)
├─ main_prod.dart        # prod 엔트리 (선택)
├─ app/                  # 앱 셸 — App 위젯, 라우터, 테마 연결
├─ core/                 # 도메인 무관 인프라
├─ shared/               # 도메인 횡단 공용 (위젯/모델/서비스)
├─ design_system/        # 자체 UI 키트 (토큰 + atom/molecule)
├─ features/             # 피처 모듈 (수직 슬라이스)
│  ├─ auth/              # 소셜 로그인 (Apple/Google/Kakao/Naver) — Q4 결정
│  ├─ dashboard/         # 메인 탭 1
│  ├─ diet/              # 메인 탭 2
│  ├─ exercise/          # 메인 탭 3
│  ├─ my_health/         # 메인 탭 4
│  ├─ ai_coach/
│  ├─ notification/
│  └─ place/             # Google Maps 통합
├─ l10n/                 # ARB 다국어 리소스 → flutter gen-l10n
└─ gen/                  # 자동 생성 산출 (.g.dart, .freezed.dart, l10n.dart)
```

### 2.2 `lib/app/` — 앱 셸

```
app/
├─ app.dart              # MaterialApp.router 진입 위젯
├─ router/
│  ├─ app_router.dart    # GoRouter 정의
│  ├─ routes.dart        # 라우트 이름/path 상수
│  └─ shell.dart         # BottomNav ShellRoute scaffold
└─ bootstrap.dart        # ProviderScope, error zone, log/Sentry init
```

### 2.3 `lib/core/` — 인프라

```
core/
├─ config/               # AppConfig, Environment(dev/staging/prod)
├─ network/              # Dio 인스턴스, 인터셉터(auth/logging), retrofit clients
├─ storage/              # drift database, secure_storage wrapper, prefs wrapper
├─ errors/               # AppError sealed, Failure 정의, Result<T>
├─ logging/              # Logger 설정
├─ analytics/            # (선택) 이벤트 전송
└─ utils/                # 순수 유틸 (date, formatter, validator)
```

**Import 규칙**
- `core/`는 **다른 어떤 레이어에도 의존하지 않습니다**.
- `core/` ↔ `core/` 간 의존만 허용.

### 2.4 `lib/shared/` — 도메인 횡단 공용

```
shared/
├─ widgets/              # 도메인과 무관하나 디자인 시스템보다 구체적인 위젯
│                        # 예: ErrorView, EmptyState, AppScaffold
├─ models/               # 여러 feature에서 공유되는 모델 (예: UserProfile)
├─ services/             # 여러 feature에서 공유되는 서비스 (예: AuthService)
└─ extensions/           # BuildContext, DateTime 확장
```

**Import 규칙**
- `core/`에 의존 가능, `features/`에는 의존 불가.

### 2.5 `lib/design_system/` — UI 키트

```
design_system/
├─ tokens/
│  ├─ colors.dart        # AppColors (light/dark)
│  ├─ typography.dart    # AppTypography
│  ├─ spacing.dart       # AppSpacing
│  ├─ radius.dart        # AppRadius
│  └─ elevation.dart
├─ theme/
│  ├─ app_theme.dart     # ThemeData light/dark 빌더
│  └─ component_themes.dart
├─ atoms/                # Button, Input, Badge, Avatar, IconButton
├─ molecules/            # MetricCard, ChartCard, ListTile variants
├─ charts/               # fl_chart 래퍼 (LineChart, BarChart, DonutChart)
└─ catalog/              # /dev/ui-catalog 라우트에 노출되는 데모 화면
```

**Import 규칙**
- `core/` 의존 가능. `features/`에는 의존 불가.
- 모든 위젯은 **테마/토큰에서 색·간격·타이포를 읽어야 함** (하드코딩 금지).

### 2.6 `lib/features/` — 피처 모듈

각 feature는 **수직 슬라이스(data/domain/presentation)**로 독립합니다.

```
features/<feature_name>/
├─ data/
│  ├─ models/            # API DTO (json_serializable)
│  ├─ sources/
│  │  ├─ <name>_remote_data_source.dart  # retrofit/dio
│  │  └─ <name>_local_data_source.dart   # drift dao
│  └─ repositories/
│     └─ <name>_repository_impl.dart
├─ domain/
│  ├─ entities/          # 순수 도메인 객체 (freezed)
│  ├─ repositories/      # 추상 인터페이스
│  └─ usecases/          # (옵션) 복잡한 비즈니스 로직만
└─ presentation/
   ├─ pages/             # 라우트 진입 화면 (StatelessWidget + ConsumerWidget)
   ├─ widgets/           # 이 feature 전용 위젯
   └─ controllers/       # Riverpod Notifier/AsyncNotifier
```

**Import 규칙**
- 동일 feature 내 자유 import.
- 다른 feature를 **직접 import 하지 않습니다**. 필요한 경우:
  - 데이터는 `shared/services/`나 `core/`로 끌어올리거나,
  - 화면 이동만 필요하면 `app/router/routes.dart`로 우회.
- `core/`, `shared/`, `design_system/` 의존 가능.

### 2.7 `lib/l10n/`, `lib/gen/`

```
l10n/
├─ app_ko.arb
└─ app_en.arb
```

- `flutter gen-l10n` 결과는 `lib/gen/l10n/`에 생성됩니다.
- `gen/`은 `.gitignore`에 추가하거나(권장) 또는 커밋합니다. 결정은 Stage 1에서.

---

## 3. 테스트 디렉토리

```
test/
├─ core/
├─ shared/
├─ design_system/
├─ features/
│  ├─ dashboard/
│  ├─ diet/
│  └─ …
└─ helpers/              # mock factory, pumpApp helper

integration_test/
├─ app_test.dart         # 전체 부팅 smoke
└─ flows/                # 핵심 시나리오
```

- 파일명: 대상 파일과 같은 경로, 접미사 `_test.dart`.

---

## 4. 의존성 다이어그램

```
        ┌──────────────┐
        │   features   │
        └──────┬───────┘
               │
   ┌───────────┼───────────┐
   ▼           ▼           ▼
shared    design_system   app(router)
   │           │
   └─────┬─────┘
         ▼
       core
```

- 위에서 아래로만 의존. 역방향 import는 금지.
- `app/`(라우터·셸)은 `features/`를 알지만, `features/`는 `app/`을 알면 안 됩니다(라우트 상수는 `app/router/routes.dart`를 통해 노출).

---

## 5. 네이밍 규칙

| 대상 | 규칙 | 예 |
| --- | --- | --- |
| 파일 | `snake_case.dart` | `diet_record_page.dart` |
| 클래스 | `PascalCase` | `DietRecordPage` |
| Provider | `<noun>Provider` | `dashboardSummaryProvider` |
| Notifier | `<Noun>Controller` 또는 `<Noun>Notifier` | `DietRecordController` |
| Route name | `kebab-case` | `/diet-record` |
| ARB key | `lowerCamelCase` | `dietRecordTitle` |

---

## 6. 환경 분리

- 환경: `dev`, `staging`(선택), `prod`.
- `--dart-define`으로 주입: `API_BASE_URL`, `SENTRY_DSN`, `ENV`.
- 엔트리: `lib/main_dev.dart`, `lib/main_prod.dart` (각각 `bootstrap(config)` 호출).
- 또는 단일 `main.dart` + dart-define 만으로 처리(MVP는 후자 권장).

---

## 7. 향후 확장 포인트

- **패키지 분리**: feature 규모가 커지면 `packages/<feature>/`로 분리하고 `melos`로 monorepo 운영.
- **Flavor**: Android `applicationIdSuffix` / iOS `Scheme`로 dev/prod 동시 설치.
- **Federated plugin**: 네이티브 기능 필요 시 `plugins/` 하위에 자체 패키지.

---

> 본 문서는 코드 작성 전에 의존성 규칙을 미리 합의하기 위한 것입니다. Stage 2(코어 인프라) 종료 시점에 1차 점검, Stage 4(피처) 종료 시점에 2차 점검합니다.
