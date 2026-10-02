# Dummy Backend Strategy — 실 FastAPI 서버 전까지

> **[결론이 난 검토 문서]** 이 비교의 전제(실 백엔드가 아직 없다)는 끝났습니다.
> 권장안이던 **옵션 C(drift 기반 로컬 인터셉터)** 를 채택해 구현했고, 실 FastAPI
> 백엔드도 존재합니다. 지금은 `--dart-define=USE_MOCK_API=false` 로 실 백엔드에
> 붙습니다.
>
> 아래는 그 선택에 이르기까지의 비교 기록입니다. **현재 동작은 아래를 보세요.**
>
> - 데모 응답 구현 → `lib/core/network/interceptors/local_api_interceptor.dart`
> - 백엔드 API 계약 → [backend/API_CONTRACT.md](../../../backend/API_CONTRACT.md)

---

## 1. 옵션 비교

| 옵션 | 영속성 | 플랫폼 | 추가 의존성 | 코드 변경 | Production 전환 |
| --- | --- | --- | --- | --- | --- |
| A. 현재 `MockApiInterceptor` (in-memory) | ❌ 앱 재시작 시 초기화 | 모두 | 없음 (기존) | 거의 없음 | interceptor 제거 |
| B. **브라우저 `localStorage`** | ✅ (브라우저 한정) | **Web만** | 없음 (dart:html / package:web) | interceptor 추가 | interceptor 제거 |
| C. **drift (SQLite) backed interceptor** ⭐ | ✅ 영구 | **Android / iOS / Web** | 없음 (이미 설치됨, drift_flutter) | schema 정의 + interceptor 확장 | interceptor 제거, schema는 그대로 |
| D. 외부 mock 서버 (Mockoon / JSON Server / Hoverfly) | ✅ 파일/메모리 | 모두 (서버 켜진 동안) | 사용자가 별도 실행 | dart-define으로 base URL만 변경 | base URL 교체 |
| E. OpenAPI-prism / WireMock | ✅ | 모두 | 사용자가 별도 실행 | API_CATALOG.md → openapi.yaml 작성 | spec 기반 자동 |

### 1.1 옵션 B (localStorage) 자세히

- **장점**: 가장 단순. `window.localStorage` 호출만으로 끝.
- **단점**:
  - **Web 전용**. 모바일 빌드에서 컴파일 자체가 안 됨 (`dart:html` /
    `package:web`은 web만).
  - 검색·정렬·필터링이 모두 클라이언트 측 JS — `WHERE meal_type='lunch'`
    같은 쿼리도 매번 전 객체를 JSON 디코드해 직접 filter.
  - 5–10MB 한도 (브라우저별). 7일 vital + 1개월 일정 정도면 충분하나,
    사진 등은 못 담음.
  - **Flutter 모바일에서 같은 인터셉터를 켤 수 없음** → 코드가 web/mobile
    분기됨.

만약 굳이 localStorage를 쓴다면, web 전용 `WebLocalStorageInterceptor`를
conditional import로 분리하고 모바일은 옵션 C로 fallback — 즉 결국 옵션 C가
필요합니다. → **단독 사용은 비권장**.

### 1.2 옵션 C (drift) 자세히

이미 `lib/core/storage/app_database.dart`로 drift가 설치되어 있고, drift_flutter
가 Android/iOS는 NativeDatabase(sqlite3), Web은 sqlite3 WASM + IndexedDB로
자동 backed 됩니다. 즉:

- **한 코드로 3 플랫폼 모두 영속 백엔드**가 됩니다.
- SQL 쿼리 + transaction이 가능 → "오늘 식단의 합산 칼로리" 등이 자연스럽.
- 마이그레이션 패턴이 그대로 — Stage 후속에 새 테이블 추가 쉽다.
- 실 FastAPI로 전환 시 **interceptor만 끄면 됩니다** (이미 USE_MOCK_API
  플래그 보유).

단점:

- 첫 셋업에 schema 정의가 필요 (DietEntries / ExerciseSessions / Vitals /
  ScheduleEvents / Notifications / …).
- drift codegen (`dart run build_runner build`)이 필요.

### 1.3 옵션 D (Mockoon 등 외부 서버) 자세히

- **장점**: 실제 네트워크 통신을 그대로 검증, HTTP 코드/지연/오류 시뮬레이션
  쉬움. CORS·인증 등 production 상황 미리 점검.
- **단점**: 사용자가 따로 켜야 함. CORS 설정 필요 for web. CI에서 e2e
  돌리려면 컨테이너 실행 추가.

이미 FastAPI를 곧 만들 계획이므로, **Mockoon은 굳이 거치지 않고 바로 FastAPI
서버를 가볍게 띄우는 게 더 유익**합니다 (옵션 E와 결합).

---

## 2. 권장 — 옵션 C (drift backed `LocalApiInterceptor`)

### 2.1 동작 흐름

```
DioClient
  └ MockApiInterceptor (현재)  ──→  LocalApiInterceptor (신규)
                                         │
                                         ├─ /diet/days/today → drift query
                                         ├─ /diet/entries POST → drift insert
                                         ├─ /vitals/weight POST → drift insert
                                         ├─ /notifications GET → drift query
                                         └─ ... (API_CATALOG.md 전부)
```

요청 path를 보고 SQL을 실행한 결과를 `Response`로 즉시 resolve. dio는 실제
네트워크를 타지 않습니다.

### 2.2 schema 확장 계획 (drift 테이블)

- `DietEntries(id, date, meal_type, time_label, foods_json, total_calories,
  sodium_mg, sugar_g)`
- `ExerciseSessions(id, date, day_label, type, minutes, calories)`
- `Vitals(id, kind, value_json, recorded_at)`
- `ScheduleEvents(id, date, time, title, category, emoji)`
- `Notifications(id, created_at, title, body, category, read)`
- `KvSeed(key, value_json)` — 첫 실행에 React 원본의 mock 데이터를 seed
  (이미 `AppKeyValues` 테이블이 비슷한 역할).

### 2.3 단계적 도입

1. **Phase A**: schema 추가 + codegen. seed 데이터 삽입 (앱 첫 실행 시).
2. **Phase B**: `MockApiInterceptor`를 점진적으로 `LocalApiInterceptor`로
   대체. 한 path씩 교체.
3. **Phase C**: 모든 endpoint가 drift로 흘러가면 `USE_MOCK_API=true`가
   사실상 "local backend" 모드.
4. **Phase D (FastAPI 도착)**: `USE_MOCK_API=false`로 바꾸면 동일 path 시그
   니처의 실 백엔드로 자동 전환.

### 2.4 보너스 — DevTools / 로그

`ApiLoggingInterceptor`가 이미 dev에서 한 줄로 매 요청을 찍기 때문에 drift
backed mock도 그대로 확인 가능. drift는 별도로 `LogInterceptor`를 attach해
SQL을 찍을 수 있어 디버깅이 편합니다.

---

## 3. FastAPI 본격 도입 시 시나리오

본격 FastAPI 서버 도입 후의 흐름은 다음과 같습니다.

1. `docs/API_CATALOG.md`의 endpoint를 FastAPI에서 그대로 구현
   (`fastapi.APIRouter` + Pydantic 모델). snake_case로.
2. CI/CD: docker compose로 FastAPI + Postgres + Redis 띄우고 staging에 배포.
3. Flutter:
   ```bash
   flutter run -d chrome \
     --dart-define=ENV=staging \
     --dart-define=API_BASE_URL=https://staging.api.oncare.example.com \
     --dart-define=USE_MOCK_API=false
   ```
4. 로컬 개발은 그대로 `USE_MOCK_API=true` → drift backed mock으로 동작.
5. 인증 토큰은 `AuthInterceptor`(이미 stub)가 `SecureTokenStore`에서 읽어
   `Authorization: Bearer …` 헤더로 첨부.

CORS는 FastAPI 측에서 웹 배포 출처와 dev origin을 허용하면
됩니다. *(당시 검토 기준. 지금 허용 출처는 백엔드 `CORS_ALLOW_ORIGINS` 설정으로 정하며,
`backend/.env.example`·`backend/docs/DEPLOY.md` 를 본다.)*

---

## 4. 결정 필요 사항

| # | 결정 항목 | 옵션 | 권장 |
| --- | --- | --- | --- |
| D1 | dummy backend 방식 | A/B/C/D/E | **C (drift backed)** |
| D2 | snake_case ↔ camelCase 변환 위치 | 서버 (Pydantic alias) / 클라이언트 (freezed @JsonKey) | 서버에서 alias로 양쪽 변환 |
| D3 | 응답 envelope 사용? | `{data, meta}` / 그냥 객체 직접 | 직접 객체 (간결) + paginated list만 `{items, next_cursor}` |
| D4 | API 버전 prefix | `/api/v1` / 없음 | `/api/v1` (forward-compat) |
| D5 | Pagination | cursor / offset | cursor |
| D6 | OpenAPI 스펙 자동 생성 활용 | FastAPI 기본 `/openapi.json` → Flutter codegen | yes (`openapi-generator-cli`로 retrofit 클라이언트 자동 생성 검토) |

위 결정만 받으면 옵션 C 구현부터 들어갈 수 있습니다.
