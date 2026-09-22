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
| DELETE | `/users/me` | `{ status: "deleted" }` |

`DELETE /users/me` 는 본문으로 `{ reasons: [코드] }` 를 받는다(#2019). 본문은 없어도 되고,
사유는 탈퇴의 조건이 아니다 — 아는 코드만 `account_deletion_reasons` 에 사유와 시각으로만
남고(누가 골랐는지는 남기지 않는다), 모르는 코드는 조용히 버린다. 아는 코드는
`privacy` · `rarely_used` · `hard_to_use` · `too_many_notifications` · `found_alternative` ·
`other`. 계정과 그에 매인 기록은 예전처럼 그대로 지워진다.

`risk`: `{ title, body, level(low|medium|high) }`

### 채팅 이모티콘 (#2020)

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/me/emotes` | `{ pass: {expires_at, remaining_seconds}\|null, cost, hours, balance }` |
| POST | `/me/emotes/pass` | 같은 모양 — 산 뒤의 상태 |

이용권은 **24시간 전체 사용**이다. 한 번 사면 그동안 모든 이모티콘을 보낸다.
남은 시간은 `remaining_seconds` 로 준다 — 기기 시계가 틀어져도 어긋나지 않는다.
이용 중에 또 사면 409 이고, 포인트가 모자라면 400 이다. `client_request_id` 가 같은
재시도는 두 번 쓰지 않는다. MY 탭에서는 같은 이용권을 포인트 사용처의
`emote_pass_24h` 항목으로 산다(`POST /me/points/exchange`) — 이용 중이면 그 항목이
`blocked_reason: "active_pass"` 로 막힌다.

이모티콘은 채팅 메시지에 실려 간다: `POST /me/coach/chat` 과
`POST /trainer/clients/{id}/chat` 이 `emote_id` 를 받고, `ChatMessageOut` 이 같은 값을
돌려준다. **회원은 이용권이 있어야 보낸다**(없으면 402). **트레이너는 이용권 없이
보낸다** — 이용권은 회원이 포인트를 쓰는 자리다. 모르는 id 는 400 이다. 본문(`body`)은
이모티콘을 그리지 못하는 자리(알림·로스터의 마지막 메시지)가 읽을 글로 채워 둔다.
그림과 목록은 앱이 들고 있다(공용 패키지 `oncare_ui` 의 에셋).

**이용권이 끝나도 이미 보낸 이모티콘은 그대로 보인다.** 지난 대화는 기록이라
새로 보내는 것만 막힌다.

`activity_points`: 포인트 잔액(`health_profiles.activity_points`) 그대로다. 프로필 행이 없으면 0.
예전에는 위험 문구(`risk_title`)가 없는 프로필에 데모 숫자 1240 을 지어 보냈다 — 이제 데모 회원의
시작 잔액(`DEMO_OPENING_POINTS`, 25,000)은 시드가 프로필에 넣는다. 적립 규칙은 아래 "활동 포인트" 절 참조. (#1786)

`indicators[]`(체중·혈압·혈당 추이)는 **없다.** 바이탈 기능과 함께 제거됐다 — 아래
"바이탈" 절 참조. 대시보드의 `indicators[]` 는 이름만 같고 칼로리·나트륨·당류로,
전혀 다른 값이다.

### 대시보드

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/dashboard/summary` | `{ indicators[], diet_entries(int), exercise_minutes, week_score, week_score_delta, sodium_warning(nullable), exercise_feedback, ai_advice_key(nullable) }` |

`ai_advice_key` 는 홈 `오늘의 AI 통합 조언` 이 고른 문장의 로케일 독립 식별자다(#1943). 앱이 이 키를 먼저 보고 자기 문장을 그린다 — 키가 없으면 위 두 문장을 받은 그대로 쓴다. 음식 이름이 들어간 나트륨 경고처럼 번역할 수 없는 문장에는 키를 주지 않는다.

`indicators[]`: `{ label, current(float), max(int), unit, over_budget?(bool) }` — 칼로리/나트륨/당류 3종.
`current` 는 당류가 소수(17.8g)라 float. 칼로리·나트륨은 정수 값이 그대로 실린다. 목표치(`max`)는 셋 다 정수.

### 식단 (핵심: 나트륨·당류·고혈압 관점)

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/diet/days/today` | `{ entries[], total_calories, total_sodium_mg, total_sugar_g, macros, ai_coach_message }` |
| POST | `/diet/analyze` | multipart `{ image, meal_type, idempotency_key? }` → `{ entry_id, analysis, time_label, photo_url?, points }` (분석과 동시에 diet_entries 저장·포인트 적립) |
| PUT | `/diet/entries/{id}` | 부분 수정 `{ date?, meal_type?, time_label?, foods?, total_calories?, carbs_g?, protein_g?, fat_g?, sodium_mg?, sugar_g? }` → 고쳐진 `entries[]` 항목 하나 |
| DELETE | `/diet/entries/{id}` | `{ status: "deleted" }` — 그 끼니로 받은 포인트를 회수한다 |
| POST | `/diet/nutrition` | `{ name(필수), amount_g? }` → `{ matched_name?, match(exact\|similar)?, source, amount_g?, calories?, carbs_g?, protein_g?, fat_g?, sodium_mg?, sugar_g? }` — 이름으로 찾은 공공 DB 값(#1896). 못 찾았거나 양을 정할 수 없으면 `matched_name`·`match` 가 null |

`entries[]`: `{ id(str), meal_type(breakfast|lunch|dinner|snack|lateNight), time_label, foods[], total_calories(int), sodium_mg(int), sugar_g(float), ai_comment(str), photo_url(str?) }`
`meal_type` 값은 회원 앱 `MealType.name` 그대로다 — 그래서 `lateNight`(야식, #1988)만 camelCase 다. DB 는 `String(20)` 자유 문자열이라 이 값을 검증하지 않으므로, 앱이 이름과 다른 문자열을 보내면 조용히 저장되고 트레이너 웹에서 다른 끼니로 읽힌다. 새 끼니를 더할 때도 enum 이름과 전송값을 일치시킨다.
`lateNight` 이전에 저장된 `snack` 은 그대로 `snack` 이다 — 백필하지 않는다. 앱은 모르는 `meal_type` 을 간식으로 접어 읽고 죽지 않는다.
`ai_comment` 는 사진 분석이 만든 식단평이다(#1932). 손으로 고쳐 만든 끼니와 분석이 식단평을 내지 못한 끼니는 빈 문자열이고, 앱은 비어 있으면 그 줄을 그리지 않는다.
당류만 소수다 — 항목 단위 당류가 6.3g·8.5g 처럼 소수로 들어오고 합계도 절삭 없이 유지된다(`total_sugar_g` 도 float).
`foods[]`: `[{ name, amount_g(float?), calories(int?), sodium_mg(int?), sugar_g(float?), carbs_g(float?), protein_g(float?), fat_g(float?), source(db|estimate|mixed|member) }]` — 음식별 영양은 회원이 식단 상세에서 고칠 수 있는 값이고, 그대로 저장된다(#1856, #1892).

`source` 는 그 음식의 숫자가 어디서 왔나다. `db`(공공 DB × 양) · `mixed`(DB 행에 탄단지가 비어 인식기 값을 남김) · `estimate`(매칭이나 양이 없어 인식기 추정 그대로) · `member`(회원이 수정 화면에서 영양 칸을 직접 고침, #2105). **`PUT` 의 `foods[].source` 는 앱이 정해 보낸다** — 손대지 않은 음식과 섭취량만 바꾼 음식은 원래 값을, 공공 DB 값으로 채운 음식은 `db` 를, 영양 칸을 고친 음식은 `member` 를 싣는다. 네 값 밖은 422 이고, **빠지면 `member` 로 저장한다**(인식기 쪽 기본값 `estimate` 를 쓰면 수정 경로로 들어온 숫자를 인식기 추정이라 부르게 된다). 이 필드 이전 기록은 `source` 가 없을 수 있고, 읽는 쪽은 `estimate` 로 읽는다.

`POST /diet/nutrition` 의 `match` 는 찾은 음식이 **같은 음식**(`exact` — 이름·별칭·양 표기를 뗀 이름·`계란`→`달걀` 표기 변형이 표 이름과 같다)인지, 이름 끝말로 붙은 **비슷한 음식**(`similar` — `야채비빔밥` → `비빔밥`)인지다(#2107). 수정 화면은 이름을 바꾼 음식이 같은 음식에 붙으면 곧바로 그 값으로 채우고, 비슷한 음식이면 제안만 한다. 매칭은 사진 분석 보정과 같은 것이다.

`amount_g` 는 **그 영양이 무엇을 재고 나온 값인가** 다. 공공 DB 는 100g 기준이라 보정이 이 양으로 환산하며, 환산에 실제로 쓴 값(인식기 추정 또는 알려진 1회 섭취량)이 그대로 실린다. 양을 못 얻어 추정치를 그대로 둔 음식과 이 필드 이전 기록은 `null` 이다 — 읽는 쪽이 null 을 견뎌야 한다. 앱은 이 값으로 나머지 여섯 값을 비례 환산한다(#1876).

**`PUT` 에 `foods` 를 실으면 그 끼니의 음식 목록이 통째로 갈리고, 끼니 합계(`total_calories`·`carbs_g`·`protein_g`·`fat_g`·`sodium_mg`·`sugar_g`)도 그 목록에서 다시 계산된다** — 같은 요청에 합계를 함께 보내도 음식 쪽이 이긴다. 원본을 하나로 두지 않으면 음식을 고칠 때마다 합계와 내역이 갈린다. `foods` 를 보내지 않으면 음식 목록은 그대로고 보낸 합계만 바뀐다. 빈 배열(`[]`)은 422 다 — 음식이 하나도 없는 끼니는 수정이 아니라 삭제다.

당류가 탄수화물보다 크면 422 다(#1863). 당류는 탄수화물의 일부라 그보다 클 수 없고, 같은 값(전부 당인 음식)은 통과한다. **`foods` 를 보내면 음식 하나하나를 견준다**(#1893) — 합계로만 보면 탄수화물이 넉넉한 다른 음식이 어긋난 음식을 가려 준다. 응답 `detail` 이 몇 번째 음식인지 말해 준다. `foods` 없이 합계만 보내면 저장된 값과 합친 결과로 견준다.

탄수화물 0 을 어떻게 볼지는 **그 0 이 어디서 왔는지**가 정한다. 컬럼이 `NOT NULL` 기본 0 이라 "탄수화물이 없다" 와 "아직 안 적혔다" 가 같은 0 으로 보이기 때문이다.

- 저장된 끼니의 `carbs_g` 가 0 이고 이번 요청이 탄수화물을 **보내지 않았다면** 견주지 않는다 — 인식기가 그 값을 못 준 옛 기록이고, 여기서 막으면 그 기록의 당류를 영영 고칠 수 없다(#1877).
- 탄수화물을 **실어 보냈다면** 그 값이 0 이어도 회원이 적은 값으로 보고 견준다. 탄수화물을 지워 검사를 피할 수 없다(#1893). 그래서 합계를 0 으로 초기화할 때는 `sugar_g` 도 함께 0 으로 보내야 한다.

회원 앱도 수정 모드를 열었을 때의 값으로 **같은 판단**을 해서, 저장을 누르기 전에 그 음식의 당류 칸 아래에 이유를 보인다(#1869). 앱이 서버보다 엄격하지도, 느슨하지도 않다.
`macros`: `{ carbs_pct, protein_pct, fat_pct }`
`idempotency_key`(선택): 재시도 중복 저장 방지. 클라 요청당 1회 생성해 재시도 시 재사용하면, 서버는 (user_id, key) 유니크 제약으로 같은 키의 재요청에 대해 **인식·저장을 건너뛰고 기존 entry 를 반환**한다(중복 기록·RAG 재적재 없음).

### 운동

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/exercise/weeks/current` | 질의 `?week_start=YYYY-MM-DD`(생략 시 이번 주) → `{ sessions[], daily_minutes[7], daily_calories[7], cardio_minutes[7], strength_minutes[7], stretching_minutes[7], day_labels[7], total_minutes, total_calories, streak_days, ai_coach_message }` — `streak_days` 는 **운동만** 센다(식단도 세는 기록 연속은 아래 "연속 기록 보호권" 절) |
| POST | `/exercise/sessions` | 입력 `{ type, minutes(>0) 또는 duration_seconds(>0), calories, intensity(light\|moderate\|high), sets?, reps?, hold_seconds?, weight?, day_label? }` → 생성된 `sessions[]` 항목 + `points` |
| PUT | `/exercise/sessions/{id}` | 입력 동일(부분 갱신) → 갱신된 항목(`points` 없음) |
| DELETE | `/exercise/sessions/{id}` | `{ status: "deleted" }` — 그 기록으로 받은 포인트를 회수한다 |
| POST | `/exercise/calories` | 입력 `{ type, name(필수), minutes(>0), intensity }` → `{ calories, source, matched_name, isometric }` |

`sessions[]`: `{ id(str), day_label, type(cardio|strength|yoga|walking), minutes, duration_seconds, calories, calorie_source, intensity(light|moderate|high), sets, reps, hold_seconds, weight, source(member|trainer_pt), date_label, time_label, items[str] }`
`week_start`: 그 주의 월요일. 월요일이 아닌 날짜를 줘도 그 날이 속한 주로 맞춘다. 형식이 깨지면 422. 회원 앱이 지난 날짜를 골랐을 때 그 주를 받는다. (#671)
`intensity`: 생략 시 `moderate`. 수정 시트가 저장된 강도로 복원되고 칼로리 추정 배수(0.85/1.0/1.2)의 근거가 된다.
`calories`(입력): **서버가 다시 계산하므로 쓰이지 않는다.** 이 필드를 채워 보내는 옛 클라이언트를 422 로 막지 않으려고 받아만 둔다. 앱이 화면에 띄우는 미리보기는 `POST /exercise/calories` 로 같은 계산을 받아 오므로, 저장 뒤 숫자가 달라지지 않는다. (#1312)
`calorie_source`: 그 칼로리가 어디서 나왔나 — `db`(운동 이름이 종목 참조표에 붙고 회원 체중 반영) · `mixed`(수치는 참조표, 이름 해석만 AI) · `estimate`(유형 평균 어림값). 식단(`RecognizedFood.source`)과 같은 어휘다. 이 필드가 생기기 전 기록은 전부 `estimate` 다. (#1312)
`POST /exercise/calories`: 운동 이름이 **비어 있으면 400**. 이름 없이 확정된 숫자를 내주지 않는 것이 이 계산의 요점이다. 폼이 조작될 때마다가 아니라 이름 입력이 끝난 시점에 부른다 — 이름 해석이 외부 호출을 탈 수 있고, 해석 결과는 서버가 캐시해 같은 이름을 두 번 묻지 않는다. 참조 데이터도 자격증명도 없는 환경에서는 유형 평균(`estimate`)으로 떨어지고, 저장은 어느 경우에도 실패하지 않는다. (#1312)
`hold_seconds`: 플랭크·행잉처럼 **버티는** 근력 기록이 한 세트를 버틴 시간(초). `reps` 와 **한 자리를 나눠 쓴다** — 이 값이 오면 서버가 `reps` 를 비우고, 없으면 반대다. 한 세트를 회로든 초로든 한 번만 재기 때문이다. 근력이 아닌 유형에서 와도 세트·횟수·중량과 같은 규칙으로 버린다. 상한은 한 세트 3600초. 주간 집계는 이 값을 세지 않는다 — 홀드도 세트로 세고(`strength_sets`), 초는 그 세트가 얼마짜리였는지를 말할 뿐이다. 이 칸이 없던 동안 홀드는 이름에 적히거나(`플랭크 3세트 · 60초`) 45초가 `reps: 3` 으로 적혔다. (#1969)

`duration_seconds`: 그 운동에 쓴 시간(초). `minutes` 와 같은 것을 더 잘게 잰 값이다. **둘 중 하나는 있어야 하고**(둘 다 없으면 422), 초가 오면 그쪽이 맞고 서버가 `minutes = max(1, round(초/60))` 로 다시 채운다 — 주간 집계와 트레이너웹이 분을 읽으므로 분 칸은 늘 차 있어야 하고, 두 값이 어긋난 채 저장되면 같은 기록이 화면마다 다른 길이로 읽힌다. 초를 모르는 옛 기록은 응답에서 `null` 이고, 그때는 `minutes × 60` 으로 읽는다. 상한은 `minutes` 와 같은 길이(36000초). (#1969, #2071)

`isometric`(`/exercise/calories` 응답): 이 이름이 버티는 운동인가 — 폼이 `횟수` 대신 `초` 를 물을지의 **기본값**이다. 종목 참조표(`exercise_catalog.isometric`)에서 나오고, 표에 붙지 않는 이름은 `false` 다. 칼로리와 함께 내려 주는 이유는 폼이 이름을 다 적은 그 시점에 이미 이 요청을 보내기 때문이다. 확정이 아니라 기본값이라, 회원이 폼에서 곧바로 바꿀 수 있다. (#1969)

`source`: 생략 시 `member`. `trainer_pt` 는 트레이너가 PT 세션을 완료 처리해 서버가 파생시킨 기록(id 는 `sched-ex-{session_id}`)으로, 근거가 트레이너에게 있어 **회원의 PUT/DELETE 는 409** 로 거절된다. 지우려면 트레이너가 그 세션을 삭제해야 하고 그러면 이 기록도 함께 사라진다. (#499)
`day_labels`: `["월","화","수","목","금","토","일"]`
`daily_calories`: 요일별 소모 칼로리(합 = `total_calories`). 홈 '주간 추이' 차트가 이 시리즈를 읽으며, 비어 있으면 클라이언트가 데모 상수로 폴백한다.

### 활동 포인트 (#1786)

잔액은 `health_profiles.activity_points`, 움직임은 `points_ledger`(적립 `earn`·사용 `spend`·회수 `revoke`·
반환 `refund`)에 한 줄씩 남는다. 둘은 같은 트랜잭션에서 함께 바뀐다. 사용처는 아래 "포인트 사용처·쿠폰" 절 참조.

| 규칙(`reason`) | 언제 | 포인트 | 하루 한도 |
|---|---|---|---|
| `diet_entry` | `POST /diet/analyze` 로 끼니가 새로 저장될 때 | +50 | 3회 |
| `exercise_manual` | `POST /exercise/sessions` (회원이 직접 추가) | +20 | 3회 |
| `routine_complete` | `POST /me/coach/routines/{id}/complete` — AI 추천(`source: "ai"`)·트레이너 배정(`source: "trainer"`) 모두 | +50 | 1회(두 출처 합산) |

생성 응답의 `points`: `{ awarded(int), balance(int) }` — 이번에 받은 포인트와 그 뒤의 잔액.

- **하루**는 KST 달력 날짜다. 한도를 넘으면 기록은 저장되고 `awarded: 0` 이다.
- **같은 기록은 한 번만** 받는다(`(user_id, kind, source_type, source_id)` 유니크). 멱등키 재시도·완료
  재전송은 새로 적립하지 않고 처음 받은 `awarded` 를 그대로 싣는다.
- **기록을 지우면 회수**한다(`DELETE /diet/entries/{id}`, `DELETE /exercise/sessions/{id}`,
  `DELETE /me/coach/routines/{id}/complete`). 잔액은 0 아래로 내려가지 않는다 — 모자라면 남은 만큼만
  빼고 내역에 실제로 뺀 값을 적는다. 회수된 적립은 그날 한도에서 빠진다. 다시 만든 기록은 새 기록이다.
- 배정 루틴 완료 응답은 `RoutineOut` + `points` 다. 앱의 안내 문구는 `추천·배정 운동 완료` 로, AI 추천과
  트레이너 배정이 **하루 1회를 함께** 쓴다 — 배정 루틴으로 받은 날은 AI 루틴을 완료해도 `awarded: 0`.
  목록·수정 응답에는 `points` 가 붙지 않는다.

### 포인트 사용처·쿠폰 (#1787)

| Method | Path | 권한 | 응답 |
|---|---|---|---|
| GET | `/me/points/shop` | 회원(데모 폴백) | `{ balance, has_trainer, has_gym, items[] }` |
| POST | `/me/points/exchange` | 회원 | 입력 `{ item, option?, client_request_id? }` → **201** `{ coupon, spent, balance }` |
| GET | `/me/coupons` | 회원(데모 폴백) | `coupon[]` — 사용 가능 먼저, 그다음 최신순(최대 100) |
| GET | `/me/points/history?before=` | 회원(데모 폴백) | `{ balance, items[], next_before }` — 포인트 내역(#2146) |
| POST | `/me/coupons/{id}/use` | 회원 | `coupon` — 회원 휴대폰에서 사용 완료 |

사용처는 앱에 있는 헬스장이 현장에서 주는 혜택이다. 가격은 혜택 1만원 = 7,000P 기준이다.
트레이너웹에는 쿠폰 경로가 없다. 모든 쿠폰은 헬스장에서 회원이 쿠폰 화면을 열고, 직원(PT 재등록은 트레이너·헬스장
직원)이 확인한 뒤 **회원 휴대폰에서** `사용 완료` 를 누른다(직원 확인 버튼).

교환 항목(가격·기한의 원본은 서버다):

| `item` | 이름 | 포인트 | 기한 | 조건 |
|---|---|---|---|---|
| `pt_renewal` | PT 재등록 3만원 할인(30,000원) | 21000 | 30일 | 활성 담당 필요, 사용 가능한 쿠폰은 회원당 1장 |
| `locker_month` | 개인 락커 1개월 무료 | 7000 | 30일 | 연결한 헬스장(`GET /me/gym`) 필요, 사용 가능한 쿠폰은 회원당 1장, 교환은 KST 달마다 1회 |
| `streak_shield` | 연속 기록 보호권(#1788, 쿠폰 아님) | 300 | 없음(0) | 쓰지 않은 보호권 최대 4개, 회원이 포인트 화면에서 사용 |
| `graph_color` | 그래프 색 바꾸기(#2076, 쿠폰 아님) | 150 | 없음(0) | `option` 에 열 색 하나, 이미 연 색은 409, 모두 열면 목록에서 빠짐 |
| `emote_pass_24h` | 채팅 이모티콘 24시간(#2020, 쿠폰 아님) | 300 | 24시간 | 이용 중이면 `active_pass` |
| `profile_pet` | 프로필 펫 이모지(#2021, 쿠폰 아님) | 200 | 7일 | `option` 에 `dog`\|`cat`, 달고 있으면 `active_pet`(409) |
| `weekly_report` | 주간 리포트(#2022, 쿠폰 아님) | 300 | 없음(0) | **담당이 없는 회원만** — 담당이 있으면 목록에서 빠지고 409, 지난주를 이미 받았으면 `week_owned`(409) |

사용 가능한(`issued`, 기한 전) 쿠폰은 **종류마다** 회원당 1장이다 — `(user_id, item) WHERE status='issued'`
partial unique index. 가진 종류는 교환 목록에서 `active_coupon` 으로 막히고, 교환하면 409 다. 사용·만료·취소되면
다시 교환할 수 있다. 연속 기록 보호권은 쿠폰 표에 들지 않고 보유 한도(4개)를 따로 센다.

`locker_month` 는 **KST 달력 한 달에 한 번**만 교환한다. 그 달(1일 0시~다음 달 1일 0시, KST)에 교환한 쿠폰이
사용 가능·사용·만료 상태로 있으면 `monthly_limit` 으로 막히고 교환하면 409 다. 헬스장 해제로 취소돼 포인트를
돌려받은(`cancelled`) 쿠폰은 세지 않는다.

`items[]`: `{ id, title, benefit, description, cost, valid_days, requires_trainer, requires_gym,
available, blocked_reason, shortfall, active_option, active_until, remaining_seconds }`. `blocked_reason` 은
`no_trainer` → `no_gym` → `active_coupon` → `shield_limit` → `active_pass` → `active_pet` → `week_owned` → `monthly_limit` →
`insufficient_points` 순으로 하나만, 교환할 수 있으면 null. `shortfall` 은 모자란
포인트(모자라지 않으면 0). `has_gym` 은 회원 헬스장 링크(`member_gyms`)가 있는지다. 교환 응답은 쿠폰이면 `coupon`,
보호권이면 `coupon: null` 과 `shield`, 그래프 색이면 `graph_color` 다(아래 두 절).

`active_option`·`active_until`·`remaining_seconds` 는 기간제 항목을 쓰고 있을 때 고른 갈래·끝나는 시각·남은 초다 —
지금은 `profile_pet` 이 달고 있는 펫과 남은 기간을 싣는다(카드가 `강아지 · 5일 남음` 을 적는다). 아니면 null·null·0.

`option` 은 항목이 여러 갈래일 때 고른 갈래다 — `graph_color` 에서 어느 색을 열지, `profile_pet` 에서 어느 펫을 달지
싣는다. 다른 항목은 보지 않는다.

**포인트 내역(#2146).** `items[]`: `{ id, kind, reason, delta, count, kst_date, created_at }` — 원장(`points_ledger`) 한 줄씩, 최신순.
`kind` 는 `earn`(적립)·`spend`(사용)·`revoke`(회수 — 기록을 지워 적립을 되돌림)·`refund`(반환 — 쿠폰 취소 등). `delta` 는 잔액 변화량(적립·반환
양수, 사용·회수 0 이하). `reason` 은 사유 코드(`diet_entry`·`exercise_manual`·`routine_complete`·`coupon_<항목>`·`streak_shield`·`graph_color`·
`emote_pass_24h`·`profile_pet`·`weekly_report`·`challenge_stake`·`challenge_reward`·`ai_chat`)이고 앱이 문구로 바꾼다.
- **날짜 단위로 넘긴다.** 기록이 있는 날 기준 최근 14일치를 주고, 더 있으면 `next_before`(받은 날 중 가장 앞 날짜)를 `before` 로 넘겨 그보다 앞을 받는다.
- **AI 코치 대화는 하루 한 줄로 묶는다**(#2145) — `count` 에 대화 수, `delta` 에 합계. 한 통마다 한 줄이면 내역이 채팅 기록처럼 길어진다.

`coupon`: `{ id, item, title, benefit, cost, status, trainer_name, gym_name, issued_at, issued_on,
expires_at, expires_on, days_left, used_at?, cancelled_at? }`. `trainer_name` 은 PT 재등록 쿠폰을 교환할 때의 담당
트레이너, `gym_name` 은 교환할 때의 헬스장 사본이다(PT 재등록은 코치 요약의 헬스장, 락커는 회원 헬스장 — 쿠폰 화면
표시용).

- **상태** `issued`(사용 가능)|`used`|`expired`|`cancelled`. 기한이 지난 쿠폰은 서버가 아직 만료로 내리지 않았어도
  `expired` 로 싣는다. 스케줄러가 없어 조회·교환·사용 경로가 만날 때 만료로 내린다.
- **기한** 쓸 수 있는 마지막 날(`expires_on`, KST)은 교환일 + 30일이다. `expires_at` 은 그 다음 날 KST 0시.
  `days_left` 는 마지막 날까지 남은 날(당일 0).
- **교환** 잔액 행을 잠근 채 확인하고 `spend`(음수)를 남긴다. 없는 항목 404, 담당 없음·헬스장 없음·같은 종류의
  사용 가능한 쿠폰 보유·이번 달 교환(락커)·잔액 부족은 409. 같은 `client_request_id` 재전송은 새로 쓰지 않고
  처음 쿠폰을 돌려준다.
- **사용 처리** 회원 휴대폰의 `POST /me/coupons/{id}/use` 하나다. `issued` 이고 기한 전일 때만 바꾸는 조건부
  UPDATE 한 번이라 더블 탭·재전송은 한 번만 처리되고, 이미 사용된 쿠폰은 같은 응답 200(`used_at` 은 처음 값), 만료·
  취소는 409, 남의 쿠폰은 404. 되돌리기는 없다. 처리한 사람은 늘 그 회원이라 따로 적지 않고 `used_at` 만 남긴다.
  처음 처리한 요청에 감사 로그(`points.coupon_redeem`, user_id = 회원)를 남긴다. 회원 휴대폰에서 누른 사용이라
  알림은 만들지 않는다.
- **만료** 포인트는 돌려주지 않는다(소멸). 남은 날이 3일 이하가 되면 쿠폰마다 한 번 알림을 만든다 — `GET /me/coupons`
  나 `GET /notifications` 를 부를 때 생긴다.
- **담당 해제** (`DELETE /me/coach`, `DELETE /me/coach/trainer`, `DELETE /trainer/clients/{member_id}`, 트레이너
  탈퇴) 사용 가능한 PT 재등록 쿠폰을 `cancelled` 로 바꾸고 같은 source 로 `refund`(양수)를 남겨 포인트를 돌려준다.
- **헬스장 해제** (`DELETE /me/coach` — 헬스장과 담당을 함께 끊는다) 사용 가능한 락커 쿠폰도 같은 방식으로 취소하고
  돌려준다. 회원 헬스장은 한 곳뿐이라 사용 가능한 락커 쿠폰은 모두 끊기는 헬스장의 쿠폰이다. 트레이너만 해제하면 락커
  쿠폰은 그대로다. 기한이 지난 쿠폰은 두 해제 모두 돌려주지 않고 만료로 내리며, 다시 불러도 두 번 돌려주지 않는다.
- **알림** 연결 해제로 인한 취소(`재등록 쿠폰이 취소됐어요`·`락커 쿠폰이 취소됐어요`)·만료 임박 알림의 `category` 는
  `benefits`, `action` 은 `{ label: "내 혜택 보기", target: "my_benefits" }`. 수신 설정 스위치는 없다.

### 연속 기록 보호권 (#1788)

| Method | Path | 권한 | 응답 |
|---|---|---|---|
| POST | `/me/points/exchange` | 회원 | 입력 `{ item: "streak_shield", client_request_id? }` → **201** `{ coupon: null, shield, spent, balance }` |
| GET | `/me/streak-shields` | 회원(데모 폴백) | `{ held, max_held, cost, used[], record_streak_days, protectable_from?, protectable_to? }` |
| POST | `/me/streak-shields/use` | 회원 | 입력 `{ date: "YYYY-MM-DD" }` → 같은 모양(사용 뒤) |

`shield`: `{ id, cost, status(held|used), acquired_at, protected_on?, used_at? }`. `used[]`: `{ date, used_at }` — 보호한 날,
최근 먼저(최대 100).

**보호권이 지키는 것은 기록 연속이다.** 기록 연속(`record_streak_days`)은 **식단 한 끼든 운동 한 건이든** 남긴 날이 이어진
길이로, 오늘부터 거슬러 세고(오늘이 비었으면 어제부터) 보호한 날도 기록한 날로 본다. 주 단위가 아니라 날짜를 거슬러 이어진다.
운동 주간 응답의 `streak_days`(운동만, 그 주 안)와는 **다른 값**이고, 운동 주간 응답에는 보호권이 실리지 않는다.

- **교환** 사용처 항목 `streak_shield`, 300P, 기한 없음(`valid_days: 0`), 회원이 쓴다. 쓰지 않은 보호권은 **최대 4개**다 —
  가득 차면 사용처 항목의 `blocked_reason` 이 `shield_limit`(잔액 부족보다 먼저), 교환은 409. 잔액 행을 잠근 채 보유 수와
  잔액을 보고 `spend`(source `streak_shield`)를 남긴다. 같은 `client_request_id` 재전송은 처음 보호권을 돌려준다.
- **사용** 회원이 직접 한다. 보호할 수 있는 날은 **어제부터 거슬러 30일(KST)** 안의 날이다. 오늘·미래·창보다 오래된 날은 409.
  그날 기록(식단 한 건 또는 운동 분 > 0)이 있으면 409, 보호권이 없으면 409. 요일은 보지 않는다 — 기록 연속이 주 단위가 아니라
  월요일에도 어제(일요일)를 보호한다. 가장 먼저 교환한 보호권부터 쓴다. 하루에 보호는 한 번이며(회원·날짜 partial unique),
  이미 보호한 날을 다시 보내면 보호권을 더 쓰지 않고 200 이다. 날짜 형식이 깨지면 422.
  창이 어제 하나가 아닌 이유: 어제를 놓친 뒤에 산 보호권이 쓸 데가 없으면 안 되고, 그렇다고 무제한이면 몇 달 전 기록까지 칠해
  연속 숫자의 뜻이 가벼워진다.
- **`protectable_from`·`protectable_to`** 지금 보호권을 쓸 수 있는 날의 구간(양끝 포함). 보호권이 없으면 둘 다 null 이다.
  **구간 안이라고 다 보호할 수 있는 것은 아니다** — 기록이 있거나 이미 보호한 날은 빠진다. 앱은 이 구간과 날짜별 기록
  (`GET /me/activity-calendar` 의 `days[]`)을 겹쳐 누를 수 있는 칸을 가리고, 마지막 판정은 사용 요청이 한다. 그 자리는 포인트
  화면 기록 그래프(#2075)이고, 운동 탭에는 두지 않는다.
- **집계** 보호한 날은 `record_streak_days` 에만 들어간다. 운동 주간 응답의 `streak_days`·`daily_minutes`·`daily_calories`·
  `total_*`·`sessions[]` 는 보호와 상관없이 실제 운동 기록만으로 만든다.
- **기록이 생기면 보호권 되돌리기** 보호한 날에 기록이 생기면(식단 `POST /diet/analyze`·`PUT /diet/entries/{id}` 로 그날로 옮김,
  운동 `POST /exercise/sessions`·`PUT /exercise/sessions/{id}`, `POST /me/coach/routines/{id}/complete`(AI 추천·트레이너 배정),
  트레이너 PT 완료 `POST /trainer/schedule/{id}/complete`) 같은 트랜잭션에서 보호를 풀고 그 보호권을 `held` 로 돌린다. 포인트는
  오가지 않는다. 멱등이며, 되돌린 뒤 그 기록을 지워도 보호는 다시 걸리지 않는다. 최대 보유 수는 **교환**의 규칙이라 되돌리기는
  보지 않는다 — 이미 4개를 가진 회원은 5개가 될 수 있고(`held` > `max_held`), 그동안 사용처 항목은 `shield_limit` 으로 막힌다.
- 트레이너 화면은 기록 연속도 보호한 날도 보지 않는다 — 트레이너가 보는 연속 일수는 회원 앱 운동 탭과 같은 **운동만** 센다.

### 기록 그래프·그래프 색 (#2075, #2076)

| Method | Path | 권한 | 응답 |
|---|---|---|---|
| GET | `/me/activity-calendar?from=&to=` | 회원(데모 폴백) | `{ from_date, to_date, days[], record_streak_days, shields_held, protectable_from?, protectable_to?, color }` |
| POST | `/me/points/exchange` | 회원 | 입력 `{ item: "graph_color", option: "<색>", client_request_id? }` → **201** `{ coupon: null, shield: null, graph_color, spent, balance }` |
| PUT | `/me/graph-color` | 회원 | 입력 `{ color }` → `{ current, unlocked[], palette[], cost }` |

포인트 화면의 **기록 그래프**이 읽는 하나다. 하루에 칸 하나를 칠해 어느 날 기록이 끊겼는지 보여 준다. 앱은 월간 그래프
(날짜 숫자가 든 7열 × 5~6줄)으로 그리고 한 달씩 앞뒤로 넘긴다 — 달마다 그 달의 1일~말일(이번 달은 오늘까지)을 부른다.

`days[]`: `{ date, has_diet, has_exercise, protected }` — `from_date`…`to_date` 를 하루도 빠짐없이 채운 오름차순
배열이다(기록이 없는 날도 빈 칸으로 온다). 날짜는 모두 KST.

- **칸의 세 단계** 아무 기록도 없음 / 식단·운동 중 하나만 / 둘 다. 식단은 **끼니 하나라도** 있으면 `has_diet` 이고
  (적립 규칙 #1786 과 같은 눈금), 운동은 분 > 0 이면 `has_exercise` 다.
- **보호한 날**(#1788)은 실제 기록이 아니다 — `has_diet`·`has_exercise` 가 둘 다 false 이고 `protected` 만 true 다.
  앱은 그 칸에 방패를 얹어 실제 기록과 구분한다.
- **구간** `from`·`to` 는 `YYYY-MM-DD`. 주지 않으면 **오늘로 끝나는 371일**(앱이 그리는 격자와 같다)이다. `to` 가 오늘보다 뒤면 오늘로 당기고(오늘
  이후 날짜는 싣지 않는다 — 빈 칸이 끊긴 날처럼 보인다), 구간이 371일보다 길면 뒤에서부터 371일만 싣는다.
  **연속은 구간과 무관하다** — 지난달을 보고 있어도 `record_streak_days` 는 오늘 기준 값이다.
- **`record_streak_days`·`shields_held`·`protectable_from`·`protectable_to`** 는 `GET /me/streak-shields` 와 **같은 값**이다 — 한
  화면의 두 자리에 다른 연속이 보이지 않게 같은 계산을 쓴다. 운동 탭의 `연속 N일`(운동만, 그 주 안)과는 다른 숫자이고,
  이 기능은 운동 탭과 트레이너웹을 바꾸지 않는다.

`color`: `{ current, unlocked[], palette[], cost }` — 지금 그래프 색, 고를 수 있는 색, 서버가 파는 색 전부, 한 색의 값.

- **팔레트** `blue`(기본) · `green` · `purple` · `orange` · `pink`. `blue` 는 회원앱 파랑이고 포인트가 들지 않아 늘
  `unlocked` 첫 칸에 있다. 앱은 가격·목록을 따로 들고 있지 않고 이 응답을 쓴다.
- **교환** 한 색에 150P, **색 하나씩** 연다. 연 색은 그 자리에서 `current` 가 된다. 파는 색이 아니거나(`blue`·모르는
  색·`option` 없음) 404, 이미 연 색은 409, 잔액 부족은 409. 같은 `client_request_id` 재전송은 두 번 쓰지 않는다.
  네 색을 모두 열면 `GET /me/points/shop` 의 `items[]` 에서 이 항목이 **빠진다**.
- **고르기** `PUT /me/graph-color` 는 포인트가 들지 않는다 — 이미 연 색 사이는 언제든 오간다. `blue` 는 늘 고를 수
  있고(고른 행을 푸는 일이다), 아직 열지 않은 색은 409, 팔레트에 없는 색은 404. 고른 색은 서버에 있어 기기를 바꿔도
  유지된다. 기한은 없다.

### MY 프로필 펫 이모지 (#2021)

| Method | Path | 권한 | 응답 |
|---|---|---|---|
| GET | `/me/profile-pet` | 회원(데모 폴백) | `{ pet: {kind, expires_at, remaining_seconds}\|null, cost, days, kinds[] }` |
| POST | `/me/points/exchange` | 회원 | 입력 `{ item: "profile_pet", option: "dog"\|"cat", client_request_id? }` → **201** `{ coupon: null, profile_pet, spent, balance }` |

MY 탭 프로필 카드의 이름 옆에 강아지나 고양이 하나를 단다. 꾸미기용이고 기능에는 영향이 없다. 그림은 채팅
이모티콘(#2020)의 강아지·고양이를 앱이 그리고, 서버는 `kind` 만 안다.

- **기간제** 200P 에 산 때부터 7일이다. 끝나는 시각은 서버가 들고 있고(`expires_at`), 스케줄러 없이 조회할 때
  비교한다 — 지나면 `pet` 이 null 이 되어 저절로 떨어진다. 남은 기간은 `remaining_seconds` 로 준다.
- **달고 있는 동안에는 다시 사지 못한다.** 사용처 카드가 `active_pet` 으로 막히고 409 다. 모르는 펫·`option` 없음은
  404, 잔액 부족은 409. 같은 `client_request_id` 재전송은 두 번 쓰지 않는다.

### 포인트로 받는 주간 리포트 (#2022)

| Method | Path | 권한 | 응답 |
|---|---|---|---|
| GET | `/me/weekly-reports` | 회원(데모 폴백) | `{ reports: [{week_start, purchased_at}], next_week_start, cost }` — 최근 주 먼저(최대 60) |
| POST | `/me/points/exchange` | 회원 | 입력 `{ item: "weekly_report", client_request_id? }` → **201** `{ coupon: null, weekly_report_week, spent, balance }` |

주간 리포트는 트레이너가 등록해 주는 것이라 담당이 없는 회원은 받을 길이 없었다. 그 회원이 포인트로 한 주를 받는다.

- **담당이 없는 회원만** 산다. 담당이 있으면 `GET /me/points/shop` 의 `items[]` 에서 항목이 빠지고, 교환하면 409 다.
- 사는 주는 **지난주**(가장 최근에 끝난 KST 월~일)다. `next_week_start` 가 그 주의 월요일이다. **같은 주는 한 번만** 산다
  (`(user_id, week_start)` 유일) — 이미 받았으면 사용처 항목이 `week_owned` 로 막히고 409 다. 잔액 부족은 409.
- **리포트 내용은 저장하지 않는다.** 서버는 어느 주를 샀는지만 들고 있고, 앱이 회원의 식단·운동 기록과 AI 코치 감지 기록
  (`GET /ai-coach/insights`)으로 트레이너 리포트와 같은 문서를 세운다. 트레이너 코멘트 자리는 비운다.
- 산 뒤에 담당이 생겨도 산 리포트는 목록에 남는다 — 회원 자신의 기록이다.

### 주간 운동 챌린지 (#1789)

| Method | Path | 권한 | 응답 |
|---|---|---|---|
| GET | `/me/challenges/weekly` | 회원(데모 폴백) | 이번 주 `weekly_challenge` |
| POST | `/me/challenges/weekly/join` | 회원 | 입력 `{ client_request_id? }`(본문 생략 가능) → **201** `{ challenge, spent, balance }` |
| GET | `/me/challenges` | 회원(데모 폴백) | `challenge[]` — 최근 주 먼저(최대 20) |

`weekly_challenge`: `{ week_start, week_end, join_until, stake, reward, goal, progress, balance, joinable,
blocked_reason, shortfall, challenge? }`. `goal` 은 참가했으면 고정된 목표, 아니면 지금 참가하면 걸릴 목표.
`progress` 는 이번 주 오늘까지 운동 기록이 있는 날 수(참가 여부와 무관). `blocked_reason` 은 `already_joined` →
`join_closed` → `insufficient_points` 순으로 하나만, 참가할 수 있으면 null. `challenge` 는 이번 주 참가 기록(없으면 null).

`challenge`: `{ id, week_start, week_end, goal, progress, stake, reward, status, achieved, rewarded, joined_at,
settled_at? }`. `status` 는 `active`|`succeeded`|`failed`, `rewarded` 는 받은 보상(성공이 아니면 0).

- **한 주** KST 월요일~일요일. **참가**는 그 주 월·화요일에만, 한 주에 한 번. 그 밖의 날·두 번째 참가·잔액 부족은 409.
  같은 `client_request_id` 재전송은 새로 걸지 않고 처음 기록을 돌려준다.
- **건 포인트** 참가할 때 100P 를 `spend`(`reason: challenge_stake`, `source_type: weekly_challenge`)로 뺀다.
- **목표** 참가 시점의 `weekly_workout_goal` 을 고정한다. 없거나 1 미만이면 3, 7 초과는 7(한 주에 셀 수 있는 최대 날 수).
- **진행** 그 주에 운동 기록이 있는 날 수. 같은 날 여러 번은 1회, 출처(직접 추가·PT·배정 루틴)는 가리지 않는다.
  날짜는 운동 화면과 같은 논리 운동일이고, 오늘 이후 날짜의 기록은 세지 않는다.
- **판정** 주가 끝난 뒤 한 번. 일요일까지 목표를 채웠으면 200P 를 `earn`(`reason: challenge_reward`)으로 적립하고,
  못 채웠으면 건 포인트는 사라진다. 주 중간에 목표를 채워도 보상은 주가 끝나야 받는다(`achieved: true`,
  `status: active`). 판정 때 센 날 수를 남겨, 판정 뒤 지난 주 기록이 바뀌어도 결과는 그대로다.
- **늦은 판정** 스케줄러가 없어 `GET /me/challenges/weekly`, `GET /me/challenges`, `POST /me/challenges/weekly/join`,
  `GET /me/points/shop`, `GET /users/me/health`, `GET /notifications` 를 부를 때 끝난 주의 진행 중 챌린지를 판정한다.
  조건부 UPDATE 한 번이라 보상·결과 알림은 챌린지마다 한 번뿐이다.
- **알림** 판정마다 결과 알림 한 건. `category` 는 `points_shop`, `action` 은
  `{ label: "포인트 사용처 보기", target: "points_shop" }` — 결과를 읽고 할 일(다음 주 참가·돌려받은 포인트 확인)이 그
  화면에 있다. 내 혜택은 교환해 **가진 것**(쿠폰·보호권)만 두므로 챌린지를 싣지 않는다. 수신 설정 스위치는 없다.

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
| GET | `/notifications` | `[{ id, title, body, category, read(bool), created_at(ISO), time_ago, action, invite_id }]` (배열, 최신순, 기본 50건) |
| GET | `/notifications/unread-count` | `{ unread(int) }` |
| POST | `/notifications/{id}/read` | 단건 읽음 → `{ id, read: true }` |
| POST | `/notifications/read-all` | 전체 읽음 → `{ marked_read(int) }` |
| DELETE | `/notifications/{id}` | 삭제 → `{ status: "deleted" }` |

category: reminder|health_check|achievement|system|coach_chat|routine|member_schedule|coach_invite|consultation_result|consult_decision|health_goals

#### 담당 요청 알림 (#1802)

`GET /notifications`는 `action: { label, target } | null` 및
`invite_id: string | null`을 포함합니다. 새 담당 요청은 `category: "coach_invite"`,
`invite_id: "tci-…"`, `action: { label: "요청 확인", target: "exercise" }`로 전달됩니다.
앱은 `/me/coach/invites`의 최신 대기 목록에서 해당 ID를 찾아 기존 수락·거절 창을 엽니다.
처리·취소되어 목록에 없으면 안내 후 기존 목적지로 이동합니다. 조회 오류는 처리 완료로
간주하지 않습니다. 코드 연결 안내는 `consultation_result`, 상담 결과는 `consult_decision`을 유지합니다.
과거 알림과 다른 종류의 알림은 `invite_id: null`이며 기존 이동을 유지합니다.

#### 갈래와 이동할 곳

각 알림에는 누르면 갈 곳 `action: { label, target }` 이 실립니다(없으면 `null` — 읽음 처리만 하고
제자리에 둡니다). 앱은 모르는 `target` 을 받으면 목록에는 싣고 이동만 하지 않습니다.

| category | 무엇 | action.target |
|---|---|---|
| `reminder`·`health_check`·`achievement` | 기록·점검·성취 | `dashboard` |
| `coach_chat` | 트레이너 메시지·리포트 | `coach_chat` |
| `routine` | 루틴 배정 | `exercise` |
| `member_schedule` | 일정 등록 | 없음(회원 앱에 일정 화면이 없음, #1928) |
| `coach_invite` | 담당 요청 도착 — `invite_id`로 수락·거절 창 열기 | `exercise`(처리·취소 시 이동) |
| `consultation_result` | 담당 연결 — 연결됨·연결 해제 및 과거 담당 요청 | `exercise` |
| `consult_decision` | **내 상담 요청의 승인·거절·만료**(#2067) | `consultations`(내 상담 요청) |
| `health_goals` | 담당 트레이너의 건강 목표 변경 | `health_goals` |
| `system` | 공지 | 없음 |

`consult_decision` 은 #2067 에서 `consultation_result` 에서 떼어 냈습니다. 같은 갈래였을 때는 거절
알림을 눌러도 운동 탭으로 가서, 사유를 보려면 내 상담 요청을 따로 찾아가야 했습니다. 이미 저장된
옛 결과 알림은 `consultation_result` 그대로라 운동 탭으로 갑니다(백필하지 않음).

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
| GET | `/ai-coach/insights` | `{ window_days, insights[{ message_id, created_at, kind, body_part, text }] }` — 최근 30일 회원 메시지의 통증·부정적 반응 감지 |
| DELETE | `/ai-coach/insights/{message_id}` | `{ status }` — 그 줄의 감지를 기록에서 치움 |
| GET | `/ai-coach/quota` | `{ free_limit, free_left, paid_limit, paid_left, cost, balance, next }` — 오늘 남은 대화(#2145) |
| POST | `/ai-coach/chat` | 입력 `{ message, history?, pay_with_points?, client_request_id? }` → `{ reply, sources, user_insight, points_spent, balance_after, quota }` |

tag: diet|exercise|hydration|...

**하루 대화 한도(#2145).** AI 챗봇(담당 트레이너가 없는 회원)은 KST 하루 **무료 10회**다. 다 쓰면 **한 번에 50P** 로 하루 **10회**까지
더 보낸다(세 값은 서버 설정 `coach_chat_free_per_day`·`coach_chat_paid_cost`·`coach_chat_paid_per_day`).

- `next` 는 다음 대화가 무엇으로 나가는가 — `free` · `paid` · `exhausted`.
- 무료를 넘겨 보내려면 `pay_with_points: true` 가 있어야 한다. 앱은 무료를 다 쓴 뒤 처음 한 번만 확인창을 띄운다.
- 거절은 `detail: { code, message }` 다. 동의 없음 402 `points_required`, 오늘 다 씀 429 `daily_limit`, 잔액 부족 409
  `insufficient_points`(+`shortfall`).
- **AI 가 답했을 때만 센다.** 검색 기반 대체 답은 무료 횟수도 포인트도 쓰지 않는다. 포인트로 산 답은 원장에 `ai_chat` 사용 줄로 남고,
  `points_spent`·`balance_after` 가 답변 아래 차감 표시(`−50P · 남은 포인트`)를 채운다. `GET /ai-coach/messages` 의 코치 답변도 같은
  두 값을 싣는다.
- 같은 `client_request_id` 재전송은 저장한 답을 그대로 돌려주고 다시 세지 않는다.

`DELETE /ai-coach/insights/{message_id}` 는 **메시지를 지우지 않는다**(#1975). 감지는 저장하지 않고 대화에서 매번 계산하므로 지울 행이 없다 — 그 줄에 `더 보지 않음` 표시만 남기고 `GET` 이 건너뛴다. 회원이 쓴 말은 대화에 그대로 남고 AI 가 맥락으로 읽는 것도 그대로다. 이미 치운 줄을 다시 눌러도 200 이고, 남의 대화·없는 id 는 404 다.

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
- **`/trainers/recommended` 순서**: 회원마다 다르다. 회원의 건강 목표(`conditions`, 옛 질환 이름은 새 목표로 읽는다)·목표(`goals`)·가장 최근 상담의 `exercise_goal`·내 헬스장(`MemberGym`)을 신호로 점수를 매겨 내림차순 정렬한다. 동점은 경력 → id 로 갈라 같은 회원이 새로고침해도 순서가 흔들리지 않는다. (#500)
- **트레이너 화면의 회원 목표(`TrainerClientOut.goal`, `MemberCoachOut.goal`, 루틴 추천 분석의 `goal`)**: 회원 건강 목표(`conditions` 중 목표, 최대 2개)를 ` · ` 로 이은 값이다. 트레이너가 `PUT /trainer/clients/{id}/health-profile` 로 `conditions` 를 고치면 회원앱과 같은 칸이 바뀐다. 옛 질환 이름은 저장 때 정리하고, 목표가 아닌 글(건강상태·주의사항)은 남는다. 상담 수락 때 회원 목표가 비어 있으면 상담의 `exercise_goal` 을 목표로 채운다(#1818). 상담 운동 목표가 건강 목표 여덟 종과 1:1 이 되면서 `other` 를 뺀 모든 값이 빠짐없이 채워진다(#1992).
- **회원 건강 목표 숫자의 범위**: 회원 경로(`PUT /users/me/health-goals`·`POST /users/me/onboarding`)와 트레이너 경로(`PUT /trainer/clients/{id}/health-profile`)가 **같은 범위**를 쓴다 — 같은 컬럼을 고치는 문들이라 기준이 갈라지면 한쪽으로 들어온 값을 다른 쪽이 고칠 수 없다. 범위는 `app/schemas/health_goal_ranges.py` 한 곳에 있고, 어긋나면 422 다. `null` 은 그대로 목표 해제다. 자세한 사정은 [TRAINER_DOMAIN.md](docs/TRAINER_DOMAIN.md) 참조. (#1888)
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
| POST | `/consultations` | 입력 `{ trainer_id, slot_id, exercise_goal, health_purpose_type, message? }` |
| GET | `/consultations/slots?trainer_id=` | 상담 신청 폼이 고를 수 있는 그 트레이너의 빈 자리 |
| GET | `/consultations/me` | 내가 보낸 요청 (최신순, 기본 50건·커서) |
| DELETE | `/consultations/{consultation_id}` | 내가 보낸 대기 중 상담 요청 취소 |
| GET | `/consultations/{id}` | 단건(남의 것·없는 것 404) |

- 같은 트레이너에게 **대기 중인 요청은 한 건**입니다(`uq_consultation_requests_pending_trainer`,
  중복은 409). 그래서 목록이 자라는 쪽은 처리된 지난 요청입니다 — 상태 필터가 없어
  그대로 함께 쌓이고, 그 때문에 상한이 필요합니다. (#980)
- **신청 한도** (#1628) — 트래픽이 아니라 남에게 주는 피해를 막습니다. 답을 기다리는 요청
  하나가 트레이너 자리 하나를 최대 24시간 잠그고, 신청·취소를 되풀이하면 트레이너 알림함이
  찹니다. 둘 다 **DB 에서 셉니다** — 재기동하면 비워지는 메모리 창으로는 반복을 막지 못합니다.

  | 한도 | 기본값(설정) | 넘으면 |
  |---|---|---|
  | 동시에 답을 기다리는 요청 수(모든 트레이너 합) | 3 (`CONSULTATION_MAX_PENDING`) | **409** `detail = { code: "too_many_pending", message, limit }` |
  | 24시간에 만든 요청 수(취소·거절·만료 포함) | 10 (`CONSULTATION_CREATE_PER_DAY`) | **429** `detail = { code: "consultation_rate_limited", message, limit }` + `Retry-After` |

  - 판정 순서는 같은 트레이너 대기 중복(409, 문자열 detail) → 동시 대기 상한 → 24시간 한도입니다.
    중복은 "이미 신청함" 상태라 앱이 기존 신청을 보여 줘야 하므로 한도 코드로 바꾸지 않습니다.
  - 동시 대기 상한을 세기 전에, 이 회원의 대기 요청이 걸린 트레이너들의 지난 `pending` 을
    만료 처리합니다 — 아무도 그 트레이너 화면을 열지 않아 아직 `pending` 인 요청이 회원을
    막지 않게 합니다.
  - `Retry-After` 는 한 건 여유가 생기는 시각까지의 초입니다(가장 먼저 창을 벗어나야 하는
    신청 기준). 앱은 한 시간 이상이면 시간, 미만이면 분으로 올려 안내합니다.
  - 값이 0 이면 그 한도를 끕니다. 24시간 한도는 다른 한도처럼 `RATE_LIMIT_ENABLED=false`
    에서도 꺼집니다(실 API E2E 가 그렇게 돕니다).
  - 거절·만료된 트레이너에게 곧바로 다시 신청하는 길은 막지 않습니다(#2067). 같은 트레이너
    재신청 쿨다운은 두지 않습니다.
- `exercise_goal` 입력은 회원앱 온보딩·MY 의 **건강 목표 여덟 종과 1:1** 입니다 —
  `weight_loss`·`strength`·`fitness`·`posture`·`rehab`·`eating`·`exercise_habit`·`blood_pressure`,
  그리고 여덟 중 어디에도 넣기 어려운 회원을 위한 `other` 입니다. 상담이 수락되면
  여덟 목표는 회원 건강 목표(`HealthProfile.conditions`)로 그대로 이어집니다
  (`health_focus.EXERCISE_GOAL_FOCUS`). `other` 는 무엇을 원하는지 알려주는 바가 없어
  잇지 않습니다. (#1992)
  없앤 `health`(건강 관리)는 **입력에서 받지 않습니다**(422) — 여덟 목표 중 하나로 옮길
  수 없어 그 회원만 건강 목표가 비어 있었고, 그게 이 통일의 이유입니다. 이미 저장된
  `health` 행은 백필하지 않고 **응답에서 그대로 내려줍니다**(응답 타입이 `str` 입니다).
  `fitness` 는 부르는 이름만 `체력 향상` → `체력 강화` 로 바뀌었고 뜻은 같아 그대로 읽습니다.
- **시각은 회원이 적어 보내지 않고 트레이너가 열어 둔 자리에서 고릅니다.** (#1873)
  `preferred_date`+`preferred_time_slot` 입력은 `slot_id` 하나로 바뀌었습니다. 자리가
  시작·길이·종류를 모두 들고 있어 승인이 시각을 다시 정하지 않습니다 — 예전에는 회원이
  고른 종료 시각이 쓰이지 않고 승인이 늘 시작+30분으로 일정을 만들었습니다.
- `GET /consultations/slots` 는 그 트레이너의 **`1:1 PT`** 자리 중 닫히지 않았고 비어 있고
  **시작까지 4시간 이상** 남은 것만 줍니다(`CONSULT_SLOT_MIN_LEAD_HOURS`). 헬스장 탭의
  예약 가능 시간 목록(`GET /trainers/{id}/slots`)과 종류 기준은 같고(#1849 유지) 하한과
  잠김 여부만 다릅니다. 비면 앱은 신청 버튼을 잠그고 헬스장 전화를 안내합니다.
- **신청하는 순간 자리가 잠깁니다**(`remaining` 감소). 승인할 때 잠그면 두 회원이 같은
  자리를 신청할 수 있고, 둘 중 하나는 트레이너가 수락한 뒤에야 거절당합니다. 이미 잠긴
  자리를 보내면 **409** 이고, 없는 자리는 **404** 입니다.
- **만료** — 신청 후 **24시간**과 **자리 시작 2시간 전** 중 **먼저 오는 쪽**에 요청이
  `expired` 가 되고 자리가 다시 열리며 회원에게 알림이 갑니다. `rejected`(트레이너의 판단)와
  구분해 회원 화면 문구가 다릅니다. 목록 하한(4시간)을 만료 기준(2시간)보다 크게 둔 이유는
  경계에서 트레이너의 확인 시간이 0 이 되지 않게 하기 위해서입니다 — 둘이 같으면 19:30 자리가
  17:29 에 보이는데 만료는 17:30 이라 신청 1분 뒤에 만료됩니다. 차이(2시간)가 트레이너가
  보장받는 최소 확인 시간입니다.
- **정리 시점** — 스케줄러가 없어 **읽는 시점에** 정리합니다. 트레이너 자리 목록
  (`GET /trainer/reservation-slots`)·상담 인박스(`GET /trainer/consultations`)·미처리 배지·
  상담 신청 생성·`GET /consultations/slots` 가 해당 트레이너의 지난 `pending` 을 먼저
  만료 처리한 뒤 결과를 돌려줍니다. 범위를 그 트레이너의 행으로 한정합니다.
- **데모 트레이너의 자리** (#2067) — `SEED_DEMO_DATA` 가 켜진 서버는 기동할 때 데모
  트레이너(윤재희 `trainer-yoon` 제외)마다 `1:1 PT` 60분 자리를 둘씩 깝니다(내일 13:00,
  모레 19:30). `GET /consultations/slots` 와 `GET /trainers/{id}/slots` 는 그 트레이너에게
  고를 자리가 하나도 없으면 같은 규칙으로 다시 깐 뒤 결과를 돌려줍니다 — 기동할 때만 깔면
  재기동 없이 오래 켜 둔 서버에서 날짜가 지나 다시 빕니다. 고를 자리가 하나라도 있으면
  (트레이너가 연 자리 포함) 아무것도 하지 않고, 잡혔거나 닫힌 시각은 다시 열지 않고 그 뒤
  날짜로 밉니다. 데모 트레이너가 아닌 계정에는 깔지 않습니다. 윤재희는 빈 상태(헬스장 전화
  안내)를 보여 주려고 비워 둡니다.
- **거절·회원 취소·만료·회원 탈퇴는 자리를 되돌려 줍니다.** 탈퇴하면 요청 행은 회원과 함께 CASCADE 로 사라지므로, 그 전에 자리부터 풉니다 — 아니면 `remaining = 0` 으로 영영 잠깁니다. 예약(`TrainerReservation`)과 달리 상담이
  잡은 자리에는 예약 행도 일정도 없어, 좌석만 되돌리는 별도 경로(`release_consultation_hold`)를
  씁니다.
- 응답에 `slot_id`·`slot_starts_at`·`slot_duration_minutes` 가 실립니다 — 회원 화면이 **확정된
  일시**를 그리는 값입니다. 승인 알림 본문에도 확정 일시가 들어갑니다.
- `preferred_date`·`preferred_time_slot` 은 **응답에 남습니다.** 새 요청에서는 고른 자리의
  시각 사본이고, 자리 선택 이전 요청에는 회원이 적어 보낸 희망 시각이 그대로 있습니다.
  과거 `flexible`·`morning`/`afternoon`/`evening` 값도 저장된 그대로 내려갑니다.
- 자리 없이 접수돼 있던 `pending` 요청은 배포 마이그레이션(`0073_consultation_slot`)이
  `expired` 로 정리하고 회원에게 알립니다 — 새 흐름으로는 트레이너가 수락해도 잡을 자리가
  없기 때문입니다. `accepted`·`rejected`·`cancelled` 인 지난 요청은 건드리지 않습니다.
- 커서는 `(created_at, id)` 로 알림과 같은 모양입니다(`before`·`before_id`).
- 트레이너 인박스(`GET /trainer/consultations`)도 같은 파라미터를 받습니다. 기본값인
  `status=pending` 은 처리하는 만큼 줄지만 `status=all` 은 그 트레이너에게 들어온 요청
  전체입니다. 미처리 배지(`/trainer/consultations/pending-count`)는 **쪽 나눔과 무관하게**
  전체를 셉니다. 상태 필터에 `expired` 가 있습니다(#1873).
- **승인은 시각을 받지 않습니다.** `POST /trainer/consultations/{id}/accept` 본문은 `note`
  하나뿐이고, 날짜·시각·종류·소요 시간 인자와 겹침 검사는 없앴습니다 — 자리를 연 사람이
  트레이너 자신이고 한 자리는 한 사람 몫이라 겹침이 구조적으로 나지 않습니다. 회원이 고른
  자리가 사라진 뒤 승인하면 **409** 입니다.

### 트레이너 알림함

| Method | Path | 응답 |
|---|---|---|
| GET | `/trainer/notifications` | `[{ id, title, body, category, read, created_at, time_ago }]` (최신순, 최대 100건) |
| GET | `/trainer/notifications/unread-count` | `{ unread(int) }` |
| POST | `/trainer/notifications/{id}/read` | `{ id, read: true }` |
| POST | `/trainer/notifications/read-all` | `{ marked_read(int) }` |

- **회원용 `/notifications` 를 재사용하지 않습니다.** `get_current_user` 가 트레이너 계정을 **403** 으로 막는 회원 전용 경로입니다(역할 분리). 저장되는 행은 같은 `notifications` 테이블이고 `user_id` 가 일반 사용자 FK라 스키마 변경은 없습니다. (#503)
- `category` 는 트레이너 전용 값입니다 — `message`|`consultation`|`reservation`|`health_goal`|`member_name`. 회원 알림의 집합(`reminder|health_check|achievement|system`)과 겹치지 않습니다. 한 테이블을 공유하지만 읽는 화면과 이동할 곳이 다릅니다. `health_goal`·`member_name` 은 `subject_id` 에 그 회원 id 를 실어 회원 상세로 갑니다.
- **생성 지점**: 회원의 새 메시지(`POST /me/coach/chat`), 새 상담 요청(`POST /consultations` — 지정된 트레이너 한 사람), 새 예약·예약 취소, 담당 회원의 건강 목표 변경(#1832), 담당 회원의 이름 변경(`PUT /users/me`·`POST /users/me/onboarding`, #2065).
- **이름은 알림을 만든 순간의 것입니다.** 제목·본문을 완성된 글자로 저장하므로, 이름을 바꿔도 이미 받은 알림은 그때 이름으로 남고 바꾼 뒤의 알림부터 새 이름을 씁니다(받은 순간의 기록이라 고쳐 쓰지 않습니다). 대신 담당 회원이 이름을 바꾸면 트레이너에게 `member_name` 알림(`{옛 이름} 회원이 이름을 바꿨어요: {새 이름}`)을 한 번 보내 옛 이름과 새 이름을 잇습니다. 트레이너는 아직 이름을 바꿀 길이 없고(`PUT /trainer/me` 는 이름을 받지 않음), 그 길을 열 때 담당 회원에게 같은 알림을 보냅니다. (#2065)
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

### 가입 연락처 형식 (#1780)

`POST /auth/register` 와 `POST /auth/trainer/register` 는 `email`·`phone` 의 **형식을 서버가
본다**. 두 앱의 가입 화면(`oncare_ui` 의 `AppInputRules`)이 같은 것을 미리 걸러 주지만, 앱을
거치지 않은 요청까지 막는 것은 여기다. 어긋나면 **422** 이고, 중복 이메일(409)·초대 코드
오류보다 먼저 걸린다.

| 필드 | 기준 | 저장 |
|---|---|---|
| `email` | `AppInputRules.email` 과 **같은 규칙**(로컬@도메인.최상위, 최대 255자) | 앞뒤 공백만 잘라낸 **입력 그대로** |
| `phone` | `010` 으로 시작하는 숫자 11자리. 하이픈·공백은 세지 않는다. 빈 값 허용(선택) | `010-1234-5678` 한 가지 표기 |

`email-validator`(`EmailStr`)를 쓰지 않는다. 그쪽은 RFC 2606 이 시험용으로 비워 둔 최상위
도메인(`.test`·`.invalid`·`localhost`)을 막는데, 앱은 통과시키므로 기준이 갈라진다 — 실 API
E2E 가 쓰는 `@oncare.test` 계정이 가입에서 떨어졌다. 두 규칙은 **함께 고쳐야 한다.**

이메일을 소문자로 고치지 않는 이유는 로그인 조회와 중복 확인이 `users.email` 을 그대로
비교하기 때문이다 — 저장만 정규화하면 대문자 도메인으로 가입한 사람이 자기가 친 주소로
로그인하지 못한다(정규화는 그 조회까지 함께 옮겨야 하는 별개의 일, #1551).

전화번호는 `01012345678` 처럼 하이픈 없이 보내도 받는다. **표기에 대해서만** 앱보다 느슨한
쪽이라 앱을 통과한 값이 서버에서 막히는 일은 생기지 않는다. 시드와 기존 프로필이 이미 하이픈
표기라 정리할 데이터는 없다.

앞자리도 함께 본다. 숫자 개수만 세던 때는 `123-4567-8901` 처럼 걸 수 없는 번호가 그대로
저장됐다 — 트레이너가 담당 회원에게 연락하려고 보는 값이라, 자릿수만 맞는 값을 받아 두면
연락할 방법이 없는 것과 같다. 01X 번호는 2021-06-30 에 서비스가 끝나 지금 쓰이는 휴대전화는
전부 `010` 이다. **헬스장 대표번호는 이 규칙을 타지 않는다** — 지역번호·안심번호(`02-332-1720`·
`0502-5552-4212`)가 섞여 있어 휴대전화 3-4-4 를 걸면 정상 번호가 422 로 막힌다.

`PUT /users/me`(프로필 수정)도 **같은 기준**이다(#1883). 전에는 이 경로만 비어 있어, 이메일을
`asdf` 로 고친 회원이 원래 주소로 다시 로그인할 수 없었다(비밀번호 찾기 경로가 없어 스스로
되돌릴 수도 없다). 전화번호도 여기서 정리가 되돌려졌다.

여기에 한 가지가 더 붙는다: **있던 전화번호는 지울 수 없다**(422). 회원 가입 화면이 전화번호를
필수로 받는데(#1634) 이 화면에서 비울 수 있으면 그 필수가 무의미해지고, 트레이너가 담당 회원에게
연락할 방법이 사라진다. 반대로 **처음부터 없던 회원**(소셜 로그인 가입자와 #1634 이전 가입자는
연락처를 넣을 자리가 없었다)에게는 요구하지 않는다 — 이름만 고치려는 사람을 전화번호로 막는
화면이 된다. 이메일은 어느 쪽이든 비울 수 없다.

`PUT /trainer/me` 의 `phone` 도 **같은 기준**이다(#1914). 트레이너는 이메일을 바꿀 수 없어
계정 잠김 위험은 원래 없었지만, 같은 종류의 값을 두 앱이 다른 기준으로 받으면 나중에 이 번호를
회원 화면에 보일 때 그 자리에서 정리부터 해야 한다. 회원 쪽과 달리 **빈 값은 언제든 허용한다** —
트레이너 가입은 전화번호를 받지 않으므로(`TrainerRegister` 는 초대 코드만 더한다) 처음부터
없는 값이다.

같은 요청의 `gym_phone` 에는 **이 기준을 걸지 않는다.** 헬스장 대표번호는 휴대전화 3-4-4 가
아니다 — 시드에만도 `02-1234-5678`(10자리) · `02-332-1720`(9자리) · `0502-5552-4212`(12자리)가
섞여 있고, 소속을 설정하면 `Place.phone` 이 이 칸에 그대로 들어온다(`set_trainer_gym`).
휴대전화 규칙을 걸면 정상 번호가 422 가 되고, 그 뒤로는 프로필 저장 자체가 막힌다. 대표번호
표기를 통일하려면 지역번호·안심번호까지 읽는 별도 규칙이 필요하다.

### 이름·생년월일 형식 (#1887)

같은 이야기가 `name` 과 `birth_date` 에도 적용된다. 전에는 두 칸에만 기준이 없어, 컬럼 길이를
넘기면 **500**(`value too long`)이고 들어가는 길이면 아무 값이나 **200** 이었다. 기준을 두는
곳은 `backend/app/services/profile_format.py` 이고, 회원 앱은 `AppInputRules` 로 같은 것을 미리
보여 준다.

| 필드 | 기준 | 적용 경로 |
|---|---|---|
| `name` | 앞뒤 공백을 자른 뒤 **1~100자**(`users.name` 컬럼과 같다) | `POST /auth/register`(보낸 경우) · `POST /users/me/onboarding` · `PUT /users/me` |
| `birth_date` | `YYYY-MM-DD` 이거나 **빈 값**. 표기뿐 아니라 실제 날짜인지도 본다 | `POST /users/me/onboarding` · `PUT /users/me` |

**이름은 비울 수 없다**(422). 가입 화면이 필수로 받는 값인데 프로필 수정에서 빈 값이 통과하면
그 필수가 무의미해지고, 이름이 빈 회원이 트레이너 로스터·채팅·상담 카드에 공백으로 뜬다.

**가입에서 `name` 을 생략하면** 서버가 이메일 로컬 파트로 채우는데, 이때 100자로 **자른다**.
이메일은 255자까지 받으므로(#1780) 자르지 않으면 긴 주소로 가입하는 사람이 *이름을 안 보냈을
뿐인데* 500 을 받았다 — 무엇을 잘못했는지 알 방법이 없는 실패다. 빈 문자열도 생략과 같이 본다:
여기서 422 를 내면 이름을 넣을 자리가 없는 경로(옛 빌드)가 가입에서 막힌다.

**생년월일은 비울 수 있다.** 넣을 자리가 없던 시절에 가입한 회원과 소셜 로그인 가입자에게는
처음부터 없는 값이라, 이름만 고치려는 사람을 생년월일로 막는 화면이 되면 안 된다. 대신 날짜가
아닌 값은 받지 않는다 — 저장되면 트레이너의 담당 요청 확인 화면에서 나이가 조용히 비어 보이고
(`trainer_client_invite_service._age_on` 이 파싱에 실패한다), 6자리 코드로 연결할 때 "이 사람이
맞나" 를 확인하는 근거 하나가 사라진다.

표기(`YYYY-MM-DD`)와 실제 날짜를 **둘 다** 본다. 표기만 보면 `1990-13-45` 가 통과하고, 파서에만
맡기면 `19900101`·`1990-01-01T00:00:00Z` 처럼 컬럼 길이(10)를 넘는 값이 지나간다.

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
