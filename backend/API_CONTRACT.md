# On-Care 백엔드 API 계약 명세 (STEP 0)

> 이 문서는 **프론트엔드(Flutter)의 `LocalApiInterceptor` 를 정답으로 삼아** 역으로 추출한
> 백엔드 API 계약입니다. 백엔드는 이 명세에 맞춰 구현합니다.
> 출처: `frontend/flutter/lib/core/network/interceptors/local_api_interceptor.dart`,
> `core/storage/app_database.dart`, `core/network/case_mapper.dart`, `app_config.dart`

## 공통 규약

- **Base URL**: 빌드 타임 `API_BASE_URL` 로 주입. 경로에 `/api` prefix 없음.
- **버전**: `/version` 이 `api_version: "v1"` 반환 → 실제 서버는 **`/v1` prefix** 사용 가정.
  (프론트 base URL 에 `/v1` 을 포함시키거나 서버가 `/v1` 라우터를 둠. 본 백엔드는 **`/v1` prefix** 채택.)
- **JSON 표기**: **snake_case** (Pydantic alias 규약). 프론트의 case_mapper 가 camelCase 로 변환.
- **인증**: `Authorization: Bearer <token>` (JWT). `auth_interceptor` 가 붙인다. 자세한 것은 아래 "인증" 절.
- **에러**: `{ "code": "...", "message": "..." }` 형태. 4xx/5xx 는 DioException 으로 처리됨.
- **사용자 id**: **문자열** (`"user-7d4e9a2c5f18"`). 정수 아님.
- **목록 페이지네이션**: 계속 자라는 목록은 **한 쪽**만 돌려줍니다. 파라미터 없이 부르면
  기본 50건이라 기존 클라이언트는 그대로 동작합니다. 커서 모양은 한 가지입니다 —
  받은 마지막 항목의 `(정렬키, id)` 를 `(before, before_id)` 로 되돌려 줍니다
  (`limit` 은 1~100, 벗어나면 **422**. `before` 파싱 실패도 422이고, 오프셋 없는 값은
  UTC 로 읽습니다).
  적용된 곳: 채팅 스레드(`/me/coach/chat`, `/trainer/clients/{id}/chat`),
  알림(`/notifications`, #965), 예약(`/reservations/me`), 상담(`/consultations/me`,
  `/trainer/consultations`), 로스터(`/trainer/clients`) — 뒤의 넷은 #980.
  **로스터만 커서가 다릅니다**(아래 트레이너 도메인 문서 참고) — 정렬키가 시각이 아니라
  트레이너가 정한 순서라 마지막 카드의 `after_id` 하나만 넘깁니다.
  집계 값(`/notifications/unread-count`, `/trainer/consultations/pending-count` 등)은
  쪽 나눔과 무관하게 **전체 기준**입니다.

## 프론트에 실제 구현된 엔드포인트 (이번에 완성할 대상)

### 시스템

| Method | Path | 응답 |
|---|---|---|
| GET | `/ping` | `{ message }` |
| GET | `/healthz` | `{ status, backend }` |
| GET | `/version` | `{ api_version, app_version }` |

### 사용자

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/users/me` | `{ id(str), name, email }` |
| GET | `/users/me/health` | `{ profile, risk, activity_points, activity_rank, settings[] }` |

`risk`: `{ title, body, level(low|medium|high) }`

`indicators[]`(체중·혈압·혈당 추이)는 **없다.** 바이탈 기능과 함께 제거됐다 — 아래
"바이탈" 절 참조. 대시보드의 `indicators[]` 는 이름만 같고 칼로리·나트륨·당류로,
전혀 다른 값이다.

### 대시보드

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/dashboard/summary` | `{ indicators[], diet_entries(int), exercise_minutes, today_schedule[], week_score, week_score_delta, sodium_warning(nullable), exercise_feedback }` |

`indicators[]`: `{ label, current(float), max(int), unit, over_budget?(bool) }` — 칼로리/나트륨/당류 3종.
`current` 는 당류가 소수(17.8g)라 float. 칼로리·나트륨은 정수 값이 그대로 실린다. 목표치(`max`)는 셋 다 정수.

### 식단 (핵심: 나트륨·당류·고혈압 관점)

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/diet/days/today` | `{ entries[], total_calories, total_sodium_mg, total_sugar_g, macros, ai_coach_message }` |
| POST | `/diet/analyze` | multipart `{ image, meal_type, idempotency_key? }` → `{ entry_id, analysis }` (분석과 동시에 diet_entries 저장) |

`entries[]`: `{ id(str), meal_type(breakfast|lunch|dinner|snack), time_label, foods[], total_calories(int), sodium_mg(int), sugar_g(float) }`
당류만 소수다 — 항목 단위 당류가 6.3g·8.5g 처럼 소수로 들어오고 합계도 절삭 없이 유지된다(`total_sugar_g` 도 float).
`foods[]`: `[{ name, calories }]` (drift 주석 기준)
`macros`: `{ carbs_pct, protein_pct, fat_pct }`
`idempotency_key`(선택): 재시도 중복 저장 방지. 클라 요청당 1회 생성해 재시도 시 재사용하면, 서버는 (user_id, key) 유니크 제약으로 같은 키의 재요청에 대해 **인식·저장을 건너뛰고 기존 entry 를 반환**한다(중복 기록·RAG 재적재 없음).

### 운동

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/exercise/weeks/current` | 질의 `?week_start=YYYY-MM-DD`(생략 시 이번 주) → `{ sessions[], daily_minutes[7], daily_calories[7], cardio_minutes[7], strength_minutes[7], stretching_minutes[7], day_labels[7], total_minutes, total_calories, streak_days, ai_coach_message }` |
| POST | `/exercise/sessions` | 입력 `{ type, minutes(>0), calories, intensity(light\|moderate\|high), day_label? }` → 생성된 `sessions[]` 항목 |
| PUT | `/exercise/sessions/{id}` | 입력 동일(부분 갱신) → 갱신된 항목 |
| POST | `/exercise/calories` | 입력 `{ type, name(필수), minutes(>0), intensity }` → `{ calories, source, matched_name }` |

`sessions[]`: `{ id(str), day_label, type(cardio|strength|yoga|walking), minutes, calories, calorie_source, intensity(light|moderate|high), source(member|trainer_pt), date_label, time_label, items[str] }`
`week_start`: 그 주의 월요일. 월요일이 아닌 날짜를 줘도 그 날이 속한 주로 맞춘다. 형식이 깨지면 422. 회원 앱이 지난 날짜를 골랐을 때 그 주를 받는다. (#671)
`intensity`: 생략 시 `moderate`. 수정 시트가 저장된 강도로 복원되고 칼로리 추정 배수(0.85/1.0/1.2)의 근거가 된다.
`calories`(입력): **서버가 다시 계산하므로 쓰이지 않는다.** 이 필드를 채워 보내는 옛 클라이언트를 422 로 막지 않으려고 받아만 둔다. 앱이 화면에 띄우는 미리보기는 `POST /exercise/calories` 로 같은 계산을 받아 오므로, 저장 뒤 숫자가 달라지지 않는다. (#1312)
`calorie_source`: 그 칼로리가 어디서 나왔나 — `db`(운동 이름이 종목 참조표에 붙고 회원 체중 반영) · `mixed`(수치는 참조표, 이름 해석만 AI) · `estimate`(유형 평균 어림값). 식단(`RecognizedFood.source`)과 같은 어휘다. 이 필드가 생기기 전 기록은 전부 `estimate` 다. (#1312)
`POST /exercise/calories`: 운동 이름이 **비어 있으면 400**. 이름 없이 확정된 숫자를 내주지 않는 것이 이 계산의 요점이다. 폼이 조작될 때마다가 아니라 이름 입력이 끝난 시점에 부른다 — 이름 해석이 외부 호출을 탈 수 있고, 해석 결과는 서버가 캐시해 같은 이름을 두 번 묻지 않는다. 참조 데이터도 자격증명도 없는 환경에서는 유형 평균(`estimate`)으로 떨어지고, 저장은 어느 경우에도 실패하지 않는다. (#1312)
`source`: 생략 시 `member`. `trainer_pt` 는 트레이너가 PT 세션을 완료 처리해 서버가 파생시킨 기록(id 는 `sched-ex-{session_id}`)으로, 근거가 트레이너에게 있어 **회원의 PUT/DELETE 는 409** 로 거절된다. 지우려면 트레이너가 그 세션을 삭제해야 하고 그러면 이 기록도 함께 사라진다. (#499)
`day_labels`: `["월","화","수","목","금","토","일"]`
`daily_calories`: 요일별 소모 칼로리(합 = `total_calories`). 홈 '주간 추이' 차트가 이 시리즈를 읽으며, 비어 있으면 클라이언트가 데모 상수로 폴백한다.

### 일정 (캘린더 상세 CRUD)

| Method | Path | 응답 |
|---|---|---|
| GET | `/schedule/events?date=YYYY-MM-DD` | `[{ id, date, time, title, category, emoji, color_hex }]` (배열) |
| GET | `/schedule/events?month=YYYY-MM` | 그 달 전체(캘린더 뷰) |
| GET | `/schedule/events/{id}` | 단건(없으면 404) |
| POST | `/schedule/events` | 입력 `{ date, time?, title, category, emoji?, color_hex? }` → 생성 항목 |
| PUT | `/schedule/events/{id}` | 부분 수정(본인 소유만, 아니면 404) |
| DELETE | `/schedule/events/{id}` | 삭제 → `{ status: "deleted" }` |

category: hospital|exercise|meal|medication|other
- **검증**: `date`(YYYY-MM-DD)·`month`(YYYY-MM)·`time`(HH:MM 또는 빈값)·`color_hex`(#RGB/#RRGGBB)는
  형식 위반 시 **422**. 특히 `month`는 미검증 시 `month=%` 같은 값이 LIKE 와일드카드로 새므로 필수.

### 알림 (액션)

| Method | Path | 응답 |
|---|---|---|
| GET | `/notifications` | `[{ id, title, body, category, read(bool), created_at(ISO), time_ago }]` (배열, 최신순, 기본 50건) |
| GET | `/notifications/unread-count` | `{ unread(int) }` |
| POST | `/notifications/{id}/read` | 단건 읽음 → `{ id, read: true }` |
| POST | `/notifications/read-all` | 전체 읽음 → `{ marked_read(int) }` |
| DELETE | `/notifications/{id}` | 삭제 → `{ status: "deleted" }` |

category: reminder|health_check|achievement|system

#### 목록 페이지네이션 (#965)

`GET /notifications` 는 **한 쪽**만 돌려줍니다. 파라미터 없이 부르면 최신 50건입니다.

| 파라미터 | 기본 | 설명 |
|---|---|---|
| `limit` | 50 | 1~100. 범위를 벗어나면 **422** |
| `before` | — | 다음 쪽 커서. 받은 마지막 알림의 `created_at`(ISO) 을 그대로 되돌려 줍니다. 파싱 실패는 **422** |
| `before_id` | — | 복합 커서 tie-break. 받은 마지막 알림의 `id` |

- 커서는 채팅 스레드(`GET /me/coach/chat`)와 **같은 모양**입니다.
- `(created_at, id)` 복합 커서를 쓰는 이유: 훅 하나가 여러 알림을 한 트랜잭션에 넣어
  같은 `created_at` 이 실제로 나옵니다. 시각만으로 자르면 그 경계에서 알림이 빠지거나 겹칩니다.
- **미확인 배지 수(`/notifications/unread-count`)는 쪽 나눔과 무관합니다** — DB 에서 세므로
  전체 기준입니다.
- 오프셋 없는 `before` 는 UTC 로 읽습니다(`created_at` 은 UTC 로 저장).

#### 보존 기간 (#965)

**읽은 알림은 90일까지 보존합니다**(`notification_service.READ_RETENTION_DAYS`).

- 대상은 `read = true` 이고 `created_at` 이 90일보다 오래된 행뿐입니다.
- **미확인 알림은 아무리 오래돼도 지우지 않습니다.** 사용자가 보지 않은 알림을 서버가
  지우면 무엇이 사라졌는지 알 길이 없고, 배지 수도 그만큼 조용히 줄어듭니다.
- 자동으로 돌지 않습니다. 삭제는 되돌릴 수 없어 **사람이 실행**합니다:

  ```
  python -m scripts.purge_notifications --dry-run   # 대상만 본다
  python -m scripts.purge_notifications             # 실제로 지운다
  ```

- 정리 대상 선정(`expired_notifications`)은 지우는 일과 분리돼 있고 테스트가 있습니다
  (`tests/test_notification_pagination.py`).

### AI 코치

| Method | Path | 응답 |
|---|---|---|
| GET | `/ai-coach/feedback` | `{ greeting, suggestions[{ tag, title, body }] }` |

tag: diet|exercise|hydration|...

### 바이탈 (체중/혈압/혈당) — 제거됨

**이 엔드포인트들은 존재하지 않는다.** 입력이 번거로워 제품에서 빼기로 했고, 테이블과
목표 컬럼까지 걷어냈다(`migrations/versions/0016_drop_vitals.py`, 2026-07-31).

없는 것: `POST /vitals/{weight|blood-pressure|blood-sugar}`, `GET /vitals/{kind}/latest`,
`vitals` 테이블, `health_profiles` 의 체중·목표 컬럼, `/users/me/health` 의 `indicators[]`.

남은 것: 식단 일일 영양 목표(`daily_calories`, `daily_sodium_mg`, `daily_sugar_g`,
`daily_carbs_g`, `daily_protein_g`, `daily_fat_g`)와 주간 운동 목표.

이 절을 지우지 않고 남겨 두는 이유: 프론트의 옛 목업(`local_api_interceptor`)과
`frontend/flutter/docs/API_CATALOG.md` 에 아직 이 경로가 남아 있어, "계약에 없으니
백엔드가 안 만든 것" 으로 오해할 여지가 있다. 만들지 않기로 한 것이다.

### 장소 (온오프라인 연결, O2O)

| Method | Path | 응답 |
|---|---|---|
| GET | `/places/nearby?lat=&lng=&category=&radius_m=` | `[{ id, name, category, address, distance_meters, lat, lng }]` (거리순 배열) |

category: medical|fitness|healthy_food|pharmacy (생략 가능)
- **공급자**: `places_provider` 설정에 따라 **카카오 Local 실검색**(서버가 키를 쥐고 프록시,
  60초 TTL 캐시) 또는 **시드 폴백**. 키가 없거나 호출 실패 시 자동으로 시드로 폴백.
- **무카테고리**: `category` 생략 시 네 카테고리를 **모두 검색·병합**하고 각 결과를 해당
  카테고리로 태깅한다(공급자 간 의미 일치, 빈 category 없음).
- **검증**: `lat`(-90~90)·`lng`(-180~180)·`category`(허용값)는 위반 시 **422**.

### 헬스장 (`fitness` 장소 + 프로필)

| Method | Path | 응답 |
|---|---|---|
| GET | `/gyms?lat=&lng=&partner_only=` | `[GymOut]` — 좌표를 주면 거리순, 없으면 이름순 |
| GET | `/gyms/{gym_id}` | 단건(없으면 404) |
| GET | `/gyms/{gym_id}/trainers` | 그 헬스장 소속 트레이너 |
| GET | `/me/gym` | 내 헬스장(`member_gyms`) |

- **`is_partner` 는 표시 값이다.** `GymOut` 으로 내려가고 `partner_only=true` 로 목록을
  좁히는 기준이 된다(현재 두 앱은 이 값을 읽지 않는다). **접근 제어가 아니다** — 상담 대상 검증과
  트레이너 노출 경로(`/trainers`, `/trainers/recommended`, `/gyms/{id}/trainers`)는 이 값을
  보지 않고, 소속 장소가 `category='fitness'` 인 활성 트레이너인지로 판단한다. 따라서
  비제휴 헬스장의 트레이너에게도 상담을 걸 수 있다. (#1626)
- **`partner_only` 기본값은 `false`** 다. 지정하지 않으면 카카오 검색으로 발견한 비제휴
  헬스장(`app/db/seed_gyms.py`)도 함께 온다 — 회원이 다니는 헬스장이 목록에 없으면 상담
  자체를 시작할 수 없기 때문이다.

### 트레이너 디렉터리 (회원앱 탐색)

| Method | Path | 응답 |
|---|---|---|
| GET | `/trainers` | `[{ id, gym_id, name, role, reason, career, intro, certifications[] }]` |
| GET | `/trainers/recommended` | 같은 형태 — 홈·운동 탭 추천 레일 |
| GET | `/trainers/{trainer_id}` | 단건(없으면 404) |

- **노출 조건**: 소속(`gym_id`)이 있고 그 장소가 `category='fitness'` 인 트레이너만. 상담 요청 시의 대상 검증과 같은 조건이라, 목록에 뜬 트레이너는 상담을 걸 수 있다. (#451)
- **`/trainers/recommended` 순서**: 회원마다 다르다. 회원의 만성질환(`conditions`)·목표(`goals`)·가장 최근 상담의 `exercise_goal`·내 헬스장(`MemberGym`)을 신호로 점수를 매겨 내림차순 정렬한다. 동점은 경력 → id 로 갈라 같은 회원이 새로고침해도 순서가 흔들리지 않는다. (#500)
- **신호가 없는 회원**(온보딩 전 등)은 운영자가 `recommend_reason` 을 적어 둔 트레이너만 **기존 순서 그대로** 받는다. 빈 목록을 주지 않는다.
- **`reason`**: 운영자가 쓴 `recommend_reason` 이 우선이고, 비어 있을 때만 점수 근거에서 만든 문구가 채워진다(예: `회원님이 다니는 헬스장 소속 · 체중 감량 지도 경험`).

### 예약 (회원 ↔ 트레이너 슬롯)

| Method | Path | 응답 |
|---|---|---|
| GET | `/trainers/{trainer_id}/slots` | `[{ id, trainer_id, starts_at, capacity, remaining, is_closed }]` |
| POST | `/reservations` | 입력 `{ slot_id }` → `{ id, slot_id, schedule_id, status, created_at }` |
| GET | `/reservations/me` | `[{ id, slot_id, trainer_id, starts_at, cancellable }]` — 내 예약 (다가오는 것부터, 기본 50건·커서) |
| DELETE | `/reservations/{id}` | 취소 → `{ status: "cancelled" }` |

- **예약은 트레이너 일정을 만듭니다.** 확정 시 `trainer_schedule` 에 `1:1 PT` 세션이 생기고, 취소하면 그 일정과 좌석이 함께 돌아갑니다. 회원 탈퇴 경로와 **같은 함수**(`reservation_service._release`)를 씁니다. (#502)
- **취소 마감**: 슬롯 시작 시각까지. 이미 시작한 수업은 **409** — 자리를 비우는 게 아니라 기록을 지우는 일이라 트레이너가 판단할 몫입니다.
- **남의 예약·없는 예약은 404** 로 같습니다. 존재 여부조차 드러내지 않습니다(상담 요청과 같은 규칙).
- `cancellable` 은 **서버 판단**입니다. 앱이 자기 시계로 다시 계산하면 시각이 어긋난 기기에서 버튼은 눌리는데 서버가 409 를 주는 상태가 됩니다.
- 취소는 트레이너에게 알림 행을 남깁니다(`notifications`). 트레이너는 `/trainer/notifications` 로 읽습니다(#503).

#### 목록 페이지네이션과 순서 (#980)

`GET /reservations/me` 는 **한 쪽**만 돌려줍니다. 파라미터 없이 부르면 50건입니다.

| 파라미터 | 기본 | 설명 |
|---|---|---|
| `limit` | 50 | 1~100. 범위를 벗어나면 **422** |
| `before` | — | 다음 쪽 커서. 받은 마지막 예약의 `starts_at`(ISO) |
| `before_id` | — | 복합 커서 tie-break. 받은 마지막 예약의 `id` |

- **순서가 `starts_at` 내림차순으로 바뀌었습니다.** 예약은 취소해도 이력이 남아야 해
  계정마다 계속 쌓이는데, 예전의 오름차순에 상한만 씌우면 첫 쪽이 **가장 오래된 지난
  예약**으로 차서 정작 다가오는 예약이 화면에서 사라집니다. 내림차순이면 첫 쪽이 항상
  예정된 예약이고, 지난 예약은 이어 받는 쪽으로 밀립니다.
- 지난 예약을 여전히 숨기지 않습니다 — "내가 그 시간에 예약했었나" 를 확인하는
  자리이기도 합니다. `cancellable` 로 취소 가능 여부만 서버가 갈라 줍니다.
- 한 트레이너가 같은 시각에 슬롯을 여러 개 열 수 있어 동시각이 실제로 나옵니다.
  시각만으로 자르면 그 경계에서 예약이 빠지거나 겹쳐 `(starts_at, id)` 복합 커서를 씁니다.

### 상담 요청 (회원 → 트레이너)

| Method | Path | 응답 |
|---|---|---|
| POST | `/consultations` | 입력 `{ trainer_id, exercise_goal, health_purpose_type, preferred_date, preferred_time_slot, message? }` |
| GET | `/consultations/me` | 내가 보낸 요청 (최신순, 기본 50건·커서) |
| DELETE | `/consultations/{consultation_id}` | 내가 보낸 대기 중 상담 요청 취소 |
| GET | `/consultations/{id}` | 단건(남의 것·없는 것 404) |

- 같은 트레이너에게 **대기 중인 요청은 한 건**입니다(`uq_consultation_requests_pending_trainer`,
  중복은 409). 그래서 목록이 자라는 쪽은 처리된 지난 요청입니다 — 상태 필터가 없어
  그대로 함께 쌓이고, 그 때문에 상한이 필요합니다. (#980)
- `preferred_time_slot` 입력은 단일 `"HH:MM"` 또는 `"HH:MM-HH:MM"` 시작–종료 범위만 허용합니다.
  시각 없는 `"flexible"` 은 더 이상 받지 않습니다(422) — 승인해도 잡을 시각이 없어 상담이
  승인만 되고 일정은 만들어지지 않았습니다. (#1587)
  과거 `flexible`·`morning`/`afternoon`/`evening` 값은 이미 저장된 행에 남아 있을 수 있어
  **응답**에서는 그대로 내려줍니다 — 컬럼이 `String(20)` 이라 마이그레이션 없이 값 형식만
  바뀐 것입니다.
- 커서는 `(created_at, id)` 로 알림과 같은 모양입니다(`before`·`before_id`).
- 트레이너 인박스(`GET /trainer/consultations`)도 같은 파라미터를 받습니다. 기본값인
  `status=pending` 은 처리하는 만큼 줄지만 `status=all` 은 그 트레이너에게 들어온 요청
  전체입니다. 미처리 배지(`/trainer/consultations/pending-count`)는 **쪽 나눔과 무관하게**
  전체를 셉니다.

### 트레이너 알림함

| Method | Path | 응답 |
|---|---|---|
| GET | `/trainer/notifications` | `[{ id, title, body, category, read, created_at, time_ago }]` (최신순, 최대 100건) |
| GET | `/trainer/notifications/unread-count` | `{ unread(int) }` |
| POST | `/trainer/notifications/{id}/read` | `{ id, read: true }` |
| POST | `/trainer/notifications/read-all` | `{ marked_read(int) }` |

- **회원용 `/notifications` 를 재사용하지 않습니다.** `get_current_user` 가 트레이너 계정을 **403** 으로 막는 회원 전용 경로입니다(역할 분리). 저장되는 행은 같은 `notifications` 테이블이고 `user_id` 가 일반 사용자 FK라 스키마 변경은 없습니다. (#503)
- `category` 는 트레이너 전용 값입니다 — `message`|`consultation`|`reservation`. 회원 알림의 집합(`reminder|health_check|achievement|system`)과 겹치지 않습니다. 한 테이블을 공유하지만 읽는 화면과 이동할 곳이 다릅니다.
- **생성 지점**: 회원의 새 메시지(`POST /me/coach/chat`), 새 상담 요청(`POST /consultations` — 지정된 트레이너 한 사람), 새 예약·예약 취소.
- **수신 설정**: 메시지 알림만 `trainer_profiles.notify_new_message` 로 끌 수 있습니다. 상담 요청·예약은 끄는 스위치가 설정 화면에 없고, 놓쳐도 되는 종류가 아니라 항상 남깁니다.
- 남의 알림 읽음 처리는 **404** 입니다.

### 트레이너 도메인 / 회원측 코치 미러

트레이너 웹 백엔드(`/v1/trainer/*`)와 회원측 "내 담당 코치" 미러(`/v1/me/coach/*`),
그리고 트레이너↔회원 **실데이터 공유** 설계는 별도 문서로 분리했다:
**[`docs/TRAINER_DOMAIN.md`](docs/TRAINER_DOMAIN.md)**.

핵심: `users.role`(member|trainer)로 두 앱 계정을 구분하되, 트레이너가 담당하는 회원은
실제 회원 User이고 트레이너 API는 회원의 실제 `diet_entries`·`routine_history`를 그대로
읽어 집계한다.

---

## 인증

두 앱 모두 로그인과 토큰 저장이 붙어 있다(`session_controller.dart`, `secure_token_store.dart`,
`auth_interceptor.dart`). 발급은 `POST /auth/login`·`POST /auth/refresh`·`POST /auth/social/{provider}`
이고, 이후 요청은 `Authorization: Bearer <access>` 를 단다.

### 세션 폐기 (#966)

refresh 토큰은 **일회용**이다. `POST /auth/refresh` 는 회전할 때 쓰인 토큰을 그 자리에서
폐기하므로, 회전 결과를 저장하지 못하면 다음 회전은 401 이다. 이미 쓴 토큰이 다시 오면
재사용으로 보고 거부하고 `auth.refresh_reuse` 감사 로그를 남긴다.

`POST /auth/logout` 은 `{refresh_token}` 을 받아 그 토큰을 폐기하고 **204** 로 답한다.
못 알아본 토큰에도 204 다 — 클라이언트가 할 일(로컬 저장소 비우기)은 어느 쪽이든 같고,
상태 코드로 "이 토큰은 살아 있다"를 알려 줄 이유가 없다. access 토큰은 요구하지 않는다
(이미 만료된 상태에서도 로그아웃할 수 있어야 한다).

폐기는 토큰 문자열이 아니라 `jti` 만 `revoked_refresh_tokens` 에 적는다. 만료된 항목은
새 폐기가 생길 때마다 함께 정리되므로 별도 배치가 없다. `jti` 가 없는 예전 토큰
(#966 이전 발급)은 폐기할 이름이 없어 회전에서 거부된다 — 한 번의 재로그인이 필요하다.

발급된 access 토큰 자체는 남은 수명(기본 하루)까지 유효하다. 상태 없는 JWT 의 성질이며,
로그아웃이 끊는 것은 **세션을 계속 되살리는 능력**이다.

### 의존성 네 갈래

엔드포인트가 어떤 의존성을 쓰느냐로 동작이 갈린다 (`app/api/deps.py`).

| 의존성 | 토큰 없을 때 | 역할 제한 |
|---|---|---|
| `CurrentUser` | 환경에 따라 데모 사용자 폴백 또는 401 (아래) | 트레이너 계정이면 **403** |
| `RequireUser` | 401 | 없음 |
| `RequireMember` | 401 | 회원만. 트레이너면 403 |
| `RequireTrainer` | 401 | 트레이너만. 회원이면 403 |
| `RequireAdmin` | 401 | `is_admin` 아니면 403 |

읽기 화면은 `CurrentUser`, 쓰기·삭제는 `RequireMember`, 트레이너 앱(`/v1/trainer/*`)은
`RequireTrainer` 를 쓴다. **데모 폴백이 있는 것은 `CurrentUser` 하나뿐**이고 나머지는 모두
유효 토큰을 요구한다 — 회원 데모 사용자가 트레이너 엔드포인트나 쓰기 경로로 새어 들어가지
않게 하기 위해서다.

### 데모 폴백은 환경으로 갈린다

`CurrentUser` 에 유효한 토큰이 없을 때의 동작은 설정이 정한다 (`app/core/config.py`).

```python
demo_fallback_enabled = allow_demo_fallback and not is_prod
```

- **dev / staging** — 데모 사용자(`user-7d4e9a2c5f18`)로 응답한다. 프론트가 `USE_MOCK_API=false` 로
  전환할 때 로그인 없이도 화면이 뜨게 하려는 것이다.
- **prod** — `ALLOW_DEMO_FALLBACK` 값과 무관하게 **항상 비활성**이고 401 을 낸다.

운영은 이 외에도 기동 시점에 막는 것이 있다(`_guard_prod_secrets`): 기본 `JWT_SECRET`,
CORS 와일드카드, 기본·짧은 `DEMO_LOGIN_PASSWORD` 로 켠 데모 시드, `AUTO_CREATE_TABLES=true`
는 모두 기동을 거부한다.

### 역할 분리

`users.role` 이 `member | trainer` 다. 두 앱은 **완전히 별개의 계정**을 쓴다 — 한 사람이 회원과
트레이너를 겸하지 않는다. 그래서 회원 API 는 트레이너 토큰을 403 으로 막고, 그 반대도 같다.
자세한 것은 [`docs/TRAINER_DOMAIN.md`](docs/TRAINER_DOMAIN.md).

### 사용자 id

**문자열**이다(`user-7d4e9a2c5f18`). 정수가 아니다. 데모 시드도 같은 규약을 따른다.

## 도메인 핵심 (놓치면 안 되는 차별점)

On-Care 는 **고혈압·당뇨 위험군 특화**다. 식단은 칼로리뿐 아니라 **나트륨(sodium_mg)·당류(sugar_g)**
가 1급 지표다. Gemini 식단 분석 프롬프트도 **DASH 식단/고혈압 관점**(기존 PoC 의 프롬프트)을 반영한다.
