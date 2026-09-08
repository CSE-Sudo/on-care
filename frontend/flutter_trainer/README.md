# oncare-trainer

On-Care **트레이너 전용 웹**입니다. [On-Care Figma 트레이너 목업](../../docs)을 기준으로
사용자 앱([frontend/flutter](../flutter))과 **완전히 분리된 코드베이스**로 구현했습니다
(아키텍처 패턴만 미러링, `package:oncare` import 0건 — 계정도 별도).

> 현재 상태: **웹 콘솔 리디자인 완료** — 좌측 세로 사이드바 셸 +
> 5개 목적지(대시보드/회원/스케줄/AI 코칭/리포트) + 사이드바 하단 내 정보·설정.
> 경로 기반 URL(`/clients/<id>/<section>`), 대시보드 딥링크, 주 캘린더,
> 프로그램 템플릿, 주간 리포트 전송까지. 데모는 drift 로컬 DB, 실 API 모드는
> `/v1/trainer/*` 연동(스케줄·알림 설정 포함)

## 아키텍처 방향 (하이브리드)

| 대상 | 플랫폼 |
| --- | --- |
| 일반 회원 | 네이티브 앱(iOS/Android) — 사용자 앱(`frontend/flutter`) |
| 트레이너 | **웹 전용** (센터 PC·태블릿) — 본 프로젝트. 수요가 생기면 앱 패키징 검토 |

이에 따라 콘텐츠 폭 제한(`AppLayout.contentMaxWidth`), drift 웹 런타임
(`tool/fetch_drift_wasm.sh`)이 포함되어 있습니다.

### 정보 구조 (사이드바 5 + 프로필)

탭은 **명사(장소)**여야 하고, 하루에 한 번 이상 여는 것만 남긴다는 기준으로 재구성했다.

| 그룹 | 목적지 | 경로 | 내용 |
| --- | --- | --- | --- |
| 운영 | 대시보드 | `/dashboard` | 오늘 할 일 한 화면 — KPI 4장(전부 딥링크) · 오늘 일정 · 주간 이행률 · 주의 회원 · 회원별 상태·근거·운동 중심 AI 요약 |
| 운영 | 회원 | `/clients/:id/:section` | 명단 │ 상세(개요·채팅·식단·운동·루틴). 안읽음 뱃지 |
| 운영 | 스케줄 | `/schedule?v=day\|week&d=` | 일 타임라인 / 주 캘린더, CRUD·완료 처리 |
| 코칭 | AI 코칭 | `/coaching?client=` | 루틴 생성 + 프로그램 템플릿 + 전송 이력 |
| 코칭 | 리포트 | `/reports?client=` | 운영 지표 + 회원 주간 리포트 → 회원에게 전송 |
| — | 내 정보 · 설정 | `/my?t=profile\|settings` | 사이드바 **footer**(nav 항목 아님) |

설계 판단:

- **`AI루틴` → `AI 코칭`으로 승격.** 옛 탭은 들어가면 먼저 회원을 골라야 시작됐다 —
  "장소"가 아니라 "회원에게 하는 행동"이라는 신호. 그렇다고 회원 상세에 숨기면 이
  제품의 차별점이 보이지 않으므로, 템플릿·근거·전송 이력을 갖춘 워크스페이스로 만들었다.
- **`메시지` 탭은 만들지 않는다.** 채팅은 식단·운동 데이터 옆에서 봐야 코칭이 된다.
  분리하면 컨텍스트가 끊기고 같은 대화로 가는 길이 둘이 된다. 대신 대시보드의 답장
  큐 + 사이드바 뱃지로 접근성만 얻는다.
- **`MY`는 nav에서 제거.** 한 달에 몇 번 여는 화면이 매일 여는 다섯 개 옆에 있을 이유가 없다.
- **`설정`은 독립 탭이 아니라 `/my` 안의 섹션.** 알림·계정 API가 아직 없어 독립 탭으로
  만들면 빈 껍데기가 된다. 자리는 만들어 두고(준비 중 표시) 엔드포인트가 생기면 채운다.

### 반응형

| 뷰포트 | 사이드바 | 본문 |
| --- | --- | --- |
| ≥ 1280 | 펼침(248px, 아이콘+라벨+프로필) | 2컬럼 대시보드, 마스터-디테일 |
| ≥ 1024 | 아이콘 레일(76px, 라벨은 툴팁) | 동일 |
| < 1024 | 드로어 + 상단 메뉴 버튼 | 단일 컬럼 |

콘텐츠 영역 기준(뷰포트 − 사이드바)이 `AppLayout.splitBreakpoint`(900) 이상이면
회원 탭이 마스터-디테일로 갈라지고, `twoColumnBreakpoint`(1080) 이상이면 대시보드가
2컬럼이 된다.

### URL 규약

선택 상태는 전부 주소에 있다 — 대시보드 KPI가 필터된 목록으로, 주의 회원 행이 그
회원의 **해당 섹션**으로 바로 들어가야 하기 때문이다(답장 대기 → `/chat`,
나트륨 초과 → `/diet`). 새로고침·뒤로가기·링크 공유가 모두 같은 화면을 복원한다.

## 다국어 (ko / en)

사용자 앱과 같은 `gen-l10n` 파이프라인입니다 — arb 는 `lib/l10n`, 생성물은
`lib/gen/l10n`, 설정은 `l10n.yaml`. 기기 로케일을 따르고, 위젯 테스트는
`pumpTrainerApp(locale: …)` 로 언어를 명시합니다.

**번역하지 않는 값이 있습니다.** 화면 문구처럼 보이지만 실제로는 DB·서버로 나가는
계약값입니다. 번역하면 저장된 행이 쿼리에 걸리지 않거나 서버가 422 를 돌려줍니다.

| 값 | 어디에 | 표시 문구는 |
|---|---|---|
| `예정`·`완료`·`공백` | `TrainerSchedule.status` | `scheduleStatusLabel(l, …)` |
| `1:1 PT`·`상담` | `TrainerSchedule.type` | `sessionTypeLabel(l, …)` |
| `걷기`·`유산소`·`근력`·`요가`·`스트레칭`·`기타` | 서버 `RoutineType` Literal | `routineTypeLabel(l, …)` |
| `A`·`B`·`recommended` | AI 루틴 후보 선택 식별자 | `_optionDisplayName(l, …)` |
| `all`·`unread`·`attention` | `ClientFilter.query` (URL) | `ClientFilter.label(l)` |

**한국어로 남는 데이터도 있습니다.** 앱이 쓴 문구가 아니라 콘텐츠라서입니다 —
데모 시드(가상 회원 이름·채팅·메모), 데모 트레이너 프로필, 프로그램 템플릿과 목 AI
루틴 본문. 실계정에서는 그 사람이 입력한 값이 그대로 그려지는 자리입니다.

리포지토리 계층은 문구 대신 **오류 코드**(`AuthFailure`, `SlotErrorCodes`)나 타입을
던지고, 화면이 자기 로케일의 문구를 붙입니다. 컨텍스트가 없는 곳에서 한국어 문장을
들고 있으면 영어 로케일에서 그 문장만 한국어로 남기 때문입니다.

`test/l10n/english_locale_test.dart` 가 영어로 화면을 띄워 한글이 남지 않았는지
확인합니다.

## 빌드 / 실행

```bash
flutter pub get

# 웹에서 drift(로컬 DB)가 동작하려면 최초 1회 (CI/배포에도 동일 단계 필요)
bash tool/fetch_drift_wasm.sh

# 실행 (웹)
flutter run -d chrome

# 테스트 / 정적 분석 / drift codegen
flutter test
flutter analyze
dart run build_runner build --delete-conflicting-outputs
```

#### drift codegen 이 `Failed to compile build script` 로 죽을 때 (#902)

```
Error: Error when reading '.../build_runner-x.y.z/lib/src/build_plan/builder_factories.dart':
No such file or directory
Error: Undefined name 'ChildProcess'.
E Failed to compile build script.
```

`pub` 이 `.dart_tool/pub/bin/` 에 캐시해 둔 **build_runner 스냅샷이 지금 해석된 버전과
어긋날 때** 나온다. 스냅샷이 만들어 내는 진입점(`.dart_tool/build/entrypoint/build.dart`)이
다른 버전의 내부 구조를 가리키기 때문에, 진입점만 지우면 같은 스냅샷이 같은 파일을 다시
만들어 증상이 반복된다. 둘을 함께 지워야 풀린다.

```bash
rm -rf .dart_tool/pub/bin .dart_tool/build
dart run build_runner build --delete-conflicting-outputs
```

`pubspec.yaml` 의 버전 제약 문제가 아니다 — 실제로 이 증상 때문에 제약을 조정해 본
적이 있는데(#902), 잠긴 버전을 그대로 두고 위 두 캐시만 지워도 생성이 정상으로 돌아왔고
생성 결과도 커밋된 산출물과 같았다. `.dart_tool` 은 git 이 추적하지 않으므로 지워도
안전하다.

로그인: 비어있지 않은 아무 이메일/비밀번호 → 시드 트레이너(김트레이너)로 로그인.
"로그인 없이 데모 둘러보기"로 바로 진입할 수도 있습니다.

### 실 API 로 실행 (회원 앱과 데이터 공유)

위 명령은 목업 모드입니다(`useMockApi` 기본값 `true`). 이 모드에서는 트레이너 웹이 자기
로컬 drift DB 를 보기 때문에 **회원 앱에서 만든 데이터가 보이지 않습니다.**

```bash
flutter run -d chrome   --dart-define=USE_MOCK_API=false   --dart-define=API_BASE_URL=http://localhost:8000/v1
```

백엔드 기동과 데모 계정, 상호작용 확인 방법은
**[docs/local_fullstack.md](../../docs/local_fullstack.md)** 를 보세요.

## 구조

[frontend/flutter/docs/STRUCTURE.md](../flutter/docs/STRUCTURE.md)의 레이어 규칙
(app / core / shared / design_system / features, 단방향 의존)을 그대로 따릅니다.

```
lib/
├─ app/            # 부트스트랩, GoRouter(+세션 인증 게이트)
│  ├─ router/      # routes(경로 상수·빌더) · app_router(6 브랜치 셸)
│  └─ shell/       # app_shell(반응형 셸) · app_sidebar · nav_destinations
├─ core/           # drift DB·시드, 토큰 저장, 날짜 유틸(ymd·koreanDateLabel)
├─ shared/         # 여러 feature 공유: TrainerClient·ClientAlert 모델,
│                  # ClientRepository/ChatRepository, PageScaffold·SectionCard·
│                  # StatCard·ActionButton·mini_charts(BarSeriesChart)
│                  # metric_trend_chart(주간 추이 꺾은선)
├─ design_system/  # 토큰(남색 primary + 오렌지 액센트), 테마
└─ features/       # auth / dashboard / clients / schedule / coaching / reports / my
```

## 이슈 여정 (1 → 12)

| # | 내용 | 비고 (추가/삭제) |
| --- | --- | --- |
| 1 | 프로젝트 스캐폴딩 + 디자인 토큰 | Flutter 기본 브랜딩(파비콘/런처) → 온케어 로고로 교체 |
| 2 | 세션/인증 로직 (mock 로그인·데모·복원) | 사용자 앱 auth 미재사용(역할 개념 부재) — 신규 설계 |
| 3 | 트레이너 로그인 화면 | 소셜/회원가입 제외(1:1 계정) |
| 4 | drift 스키마 + 회원 3명 시드 | `seed-` prefix·날짜 슬라이드·단일 트랜잭션(리뷰 반영) |
| 5 | 4탭 셸 + 인증 게이트 | 스캐폴딩 placeholder 삭제 |
| 6 | 회원 리스트 (예약 배지·AI 요약) | drift `.watch` 테스트 헬퍼 도입(pumpAndSettle 회피) |
| 7 | 회원 상세 — 채팅 | 아바타 3중복 → 공유 `ClientAvatar` 추출(리뷰 반영) |
| 8 | 회원 상세 — 식단 | 나트륨/당류 임계값을 도메인 상수로 통합(리뷰 반영) |
| 9 | 회원 상세 — 운동기록 | + 블루 팔레트 스왑·BrandHeader·웹 drift 런타임(별도 PR 분리) |
| 10 | 스케줄 탭 (타임라인·PT 전송) | + 웹 폭 제한, `ymd()` 중복 3곳 통합, 당류 보라 토큰 삭제 |
| 11 | AI 루틴 탭 (회원 선택·수정·전송) | `TrainerClient`/`ClientRepository` → shared 승격, Oni 마스코트 채택 |
| 12 | MY 탭 (프로필·자격증·통계·헬스장) | **역할 전환 미구현**(계정 분리 정책) → 로그아웃만, `TabPlaceholder` 삭제 |

### 이후 확장 (웹 와이드 + 관리 기능)

| 브랜치 | 내용 |
| --- | --- |
| `feature/trainer-split-view` | 회원 탭 마스터-디테일 스플릿(URL 동기화·닫기 버튼), 나트륨 초과 우선 정렬(동순위 → 최근 채팅순), 채팅 초안 회원 간 누수 수정, 포맷/LF 정규화 |
| `fix/trainer-chat-send-guard` | 채팅 중복 전송 가드(`_sending`)·dispose 후 접근 방지·메시지 도착 시에만 자동 스크롤 |
| `fix/trainer-client-detail-states` | 회원 상세 로딩/오류/미존재 상태 분리 + 다시 시도 |
| `feature/trainer-schedule-manage` | 스케줄 추가/수정/삭제(15분 단위 시간), 예정 세션 확장(계획 미리보기·계획 없음 안내·💬 채팅 바로가기), 오늘 중심 주간 스트립, 와이드 2컬럼 |
| `feature/trainer-routine-programs` | AI 루틴 → 오늘 PT 스케줄 등록(예정 세션에 부착 or 신규 슬롯), AI 추천 항목 삭제, 회원 피커 가로 스크롤, 와이드 분할 |
| `feature/trainer-session-complete` | 예정 세션 ✓ 완료 처리(메모 입력) → 회원 운동기록 자동 기록 — 예약→수업→기록 루프 완성 |
| `feature/trainer-send-to-chat` | 숙제/PT 프로그램 전송 시 채팅 스레드에 영속 메시지 + 회원 카드 미리보기 갱신 (`ChatRepository` shared 승격) |
| `feature/trainer-unread-badge` | 회원 카드 안읽은 메시지 뱃지(스레드 열람 시 해제, KV 마커 — 스키마 무변경) |
| `feature/trainer-client-onboarding` | ＋ 신규 회원 등록 시트(이름 *필수 표시), 상세 헤더 ● 활성/○ 휴면 토글, 아웃라인 버튼 공용화 |
| `feature/trainer-date-nav` | 스케줄·AI 루틴 날짜 이동 — 스케줄 주간 스트립(사용자 앱 식단 스트립 스타일, 예약일 dot·빈 날짜 안내), AI 루틴 등록 오늘…+6일 칩. 리포지토리 `watchDate`/날짜 파라미터화 |
| `feature/trainer-diet-trend` | 식단 탭 최근 7일 나트륨 추이 미니 차트(초과일 강조·주간 평균) — `sodiumWeekJson` 컬럼(schema v2·addColumn 마이그레이션). 막대 라벨 오늘 기준 실제 요일(리뷰 반영) |

## 주요 결정

- **색상**: 서비스 메인 = 남색(#2E7DAB). 오렌지는 "트레이너" 브랜드 워드·경고·수동 추가
  구분에만 (`brandOrange`/`warning`). 사이드바 활성 표시는 연한 남색 면 + 좌측
  인디케이터 — 본문이 이미 남색을 강조에 쓰므로 진한 pill 은 서로 부딪힌다
- **차트는 직접 그린다**: 필요한 형태가 막대 시리즈(`shared/widgets/mini_charts.dart`)와
  주간 추이 꺾은선(`shared/widgets/metric_trend_chart.dart`) 둘뿐이라 차트 라이브러리를
  넣지 않았다. 축·툴팁·줌이 필요한 분석 화면이 생기면 그때 도입한다
- **주간 추이는 사용자 앱과 같은 그림**: 리포트 탭의 칼로리·나트륨·당류 꺾은선은
  사용자 앱 홈 탭과 같은 규칙으로 그린다(선은 오늘까지만, 점 색은 목표 초과 여부,
  목표선 없음). 두 앱은 패키지가 갈라져 있어 코드를 공유하지 못하므로 한쪽만
  고치지 않는다
- **역할 전환 없음**: Figma의 "역할 전환" UI는 구현하지 않음 — 트레이너/회원은 계정으로 분리
- **mock-first**: 전송 등 상호작용은 Figma와 동일한 in-memory mock.
  채팅과 스케줄(추가/수정/삭제·AI 루틴 등록)은 drift에 영속
  (재시딩에도 `seed-` 아닌 행은 보존)
- **프로그램 이원화**: AI 루틴은 "회원 숙제 전송(mock)"과
  "PT 스케줄 등록(drift 영속)" 두 액션으로 분리 — 스케줄 탭의 예정
  세션에서 계획 미리보기로 이어짐. 등록일은 오늘…+6일 선택 가능
- **디자인 일관성**: 사용자 앱 리디자인(figma kit)의 Oni 마스코트·AI 필 패턴 채택

## 리디자인 (웹 콘솔)

| 영역 | 내용 |
| --- | --- |
| 셸 | 하단 탭바 → 좌측 세로 사이드바(펼침/레일/드로어 3단계), `PageScaffold` 공통 헤더 |
| 라우팅 | `?c=` 쿼리 → 경로 기반 `/clients/:id/:section`, 6 브랜치(5 nav + 내 정보) |
| 대시보드 | 신규. KPI 4장 전부 딥링크, 오늘 일정, 주간 이행률, 주의 회원(사유 뱃지 → 해당 섹션), 회원별 상태·근거·오늘 운동 중심 AI 요약 |
| 회원 | `개요` 서브탭 신설(경고 스트립·오늘 요약·주간 이행률·나트륨 추이·최근 활동), `루틴` 서브탭 신설 |
| 스케줄 | 주 캘린더(7열, 한 번의 범위 쿼리) + 일/주 전환, 날짜가 URL에 |
| AI 코칭 | `AI루틴`에서 승격 — 프로그램 템플릿, 전송 이력 추가 |
| 리포트 | 신규. 운영 지표 + 회원 주간 리포트 → 회원 채팅으로 전송 |
| 내 정보 | nav에서 사이드바 footer로, `내 정보`/`설정` 2섹션 |
| 백엔드 | `PUT /trainer/me`, `POST /trainer/clients/{id}/ai-coach`, `GET·POST .../report[/send]` |

## 로드맵

- 트레이너 CI/배포 파이프라인 (analyze·test·web build + wasm fetch,
  `dart format --set-exit-if-changed` 포함)
- **오늘 예약 배지 실 API**: `DioClientRepository.watchTodayReservationCount()` 가
  아직 빈 스트림이다(예약 수 출처가 없어 배지를 숨김). 스케줄이 붙었으니 여기서
  파생할 수 있다
- 실 백엔드(FastAPI) 연동 — `TrainerAuthRepository`(Dio 구현)/`SecureTokenStore` 참조
- 자정 넘김 시 '오늘' 스케줄/예약 수 자동 갱신, DB JSON 역직렬화 방어
  (백엔드 연동과 함께 처리)
- **복수 헬스장 소속**: 현재 트레이너는 헬스장 1곳(seedTrainerProfile.gym)에
  고정 — 여러 센터를 담당하려면 센터-트레이너 소속(N:N) 모델과 회원·스케줄의
  센터 스코프가 필요. 계정/권한과 함께 백엔드 단계에서 도입 예정
