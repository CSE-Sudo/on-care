# On-Care 백엔드 API 계약 명세

> 회원 앱·트레이너 웹이 함께 쓰는 백엔드(`backend/app/api/v1/`)의 엔드포인트 계약입니다.
> **백엔드가 계약의 기준**이고, 두 앱의 데모(목업) 경로 — 회원 앱
> `frontend/flutter/lib/core/network/interceptors/local_api_interceptor.dart` 와 트레이너 웹 목업
> 저장소 — 는 이 문서와 백엔드 응답을 따라갑니다. 엔드포인트를 더하거나 바꾸면 이 문서를 함께 고칩니다.
>
> 처음에는 회원 앱 프로토타입의 `LocalApiInterceptor` 에서 계약을 역으로 뽑아 시작했지만, 지금은
> 방향이 반대입니다(목업이 백엔드를 따라감).

## 공통 규약

- **Base URL**: 빌드 타임 `API_BASE_URL` 로 주입. 경로에 `/api` prefix 없음.
- **버전**: `/version` 이 `api_version: "v1"` 반환 → 실제 서버는 **`/v1` prefix** 사용 가정.
  (프론트 base URL 에 `/v1` 을 포함시키거나 서버가 `/v1` 라우터를 둠. 본 백엔드는 **`/v1` prefix** 채택.)
- **JSON 표기**: **snake_case** (Pydantic alias 규약). 프론트의 case_mapper 가 camelCase 로 변환.
- **인증**: `Authorization: Bearer <token>` (JWT). `auth_interceptor` 가 붙인다. 자세한 것은 아래 "인증" 절.
- **에러**: FastAPI 형식 `{"detail": ...}` 이고 `detail` 은 **두 형식만** 쓴다(#2911). 4xx/5xx 는 DioException 으로 처리됨.
  - **문자열**: `{"detail": "문장"}` — 대부분의 오류. 앱은 그대로 보여 준다(한국어 화면).
  - **객체**: `{"detail": {"code", "message", …추가 필드}}` — 화면이 분기해야 하는 오류만. **`code` 는 반드시 있다.**
    예: 일정 겹침 `schedule_overlap`(+`conflicts`), 프로그램을 붙일 회차 미정 `attach_target_conflict`(+`candidates`),
    상담 `too_many_pending`·`slot_unavailable`, AI 코치 `points_required`·`daily_limit`·`insufficient_points`,
    AI 하루 상한 `daily_limit`(트레이너)·`ai_capacity`(서버 전체).
    앱 공용 처리(트레이너 웹 `serverDetailText`)는 문자열이면 그 문장, 객체면 `message` 를 읽는다.
  - 예외는 FastAPI 스키마 검증 422 의 목록형 `detail`(`[{loc, msg, type}]`) 하나다.
  - 경쟁 상황(같은 이메일로 동시에 바꾸기, 같은 회원 담당 복구·수락·연결 코드가 겹침)도 DB 제약 위반을 500 이 아니라
    앞선 조회로 막았을 때와 같은 409 로 돌려준다.
- **AI 하루 호출 상한(#3032).** 회원 한도(AI 코치 대화·사진 분석) 위에 두 상한을 더 둔다. 둘 다 DB 에서 KST 날짜로 세고
  (인스턴스 수와 무관), 모델을 **부르기 직전에** 센다 — 키가 없어 모델을 부르지 않는 폴백은 세지 않는다. 문구는 `Accept-Language` 를 따른다.
  - **트레이너 한 계정**(`TRAINER_AI_CALLS_PER_DAY`, 기본 200):
    `POST /trainer/clients/{member_id}/routine-options`·`GET /trainer/clients/{member_id}/report/summary` 의 AI 호출 합.
    넘으면 **429** `detail = { code: "daily_limit", message }` + `Retry-After`(다음 KST 자정까지 초). 분당 한도의 429(`detail` 이
    문자열)와 모양으로 구분된다. 트레이너 웹은 루틴 후보는 토스트로, 리포트 요약은 다시 시도 없이 "내일 다시" 안내로 보인다.
  - **서버 전체**(`AI_GLOBAL_CALLS_PER_DAY`, 기본 0 = 끔): 모든 AI 기능의 합. 넘으면 규칙형 폴백이 있는 기능(식단 조언·추천·메뉴,
    루틴 후보, 리포트 요약, 코치 피드백, 운동 이름 접기)은 폴백으로 답하고 응답 모양은 그대로다. 대안이 없는 **AI 코치 대화**
    (회원·트레이너)와 **사진 분석**만 **503** `detail = { code: "ai_capacity", message }` + `Retry-After` 를 받는다. 이때 회원 하루
    몫·포인트·끼니는 남기지 않는다.
  - 호출 한 번의 출력 토큰은 `LLM_MAX_OUTPUT_TOKENS`(기본 4096) 이하이고, 기능별로 더 작게 묶는다. 잘린 응답은 폴백(사진 분석은 502)이다.
- **언어(`Accept-Language`, #2297)**: 회원 앱·트레이너 웹은 **모든 요청**에 지금 화면 언어를
  `Accept-Language: ko` 또는 `Accept-Language: en` 으로 보냅니다(호출부가 직접 넣은 값은 덮지 않음).
  서버는 `app/core/locale.py` 에서 이 값을 읽어 **`ko` 또는 `en` 하나**로 정합니다.
  - 주 언어만 봅니다(`en-US` → `en`). 가중치(`q`)가 가장 큰 지원 언어를 고르고, 같으면 먼저 적힌 것.
    `q=0`·`*`·지원하지 않는 언어·깨진 항목은 건너뜁니다.
  - 헤더가 없거나 고를 언어가 없으면 **`ko`** — 헤더를 보내지 않는 옛 클라이언트는 지금과 같습니다.
  - 서비스 코드는 인자 없이 `current_locale()` 을 부르면 됩니다. `RequestLocaleMiddleware` 가
    요청마다 컨텍스트 변수를 채우고 요청이 끝나면 되돌려, 동시에 도는 요청끼리 섞이지 않습니다
    (동기 엔드포인트의 스레드풀에서도 같은 값). 요청 밖(배치·스케줄러)에서는 `ko`.
  - 라우터에서 받으려면 `locale: RequestLocale` 의존성. 두 문장 중 고를 때는
    `localized("한국어", "English")`.
  - 지금 이 값을 반영하는 서버 문장은 **전역 500 응답의 `detail`** 뿐입니다. 리포트 요약·조언·
    라벨·AI 추천·알림은 후속 이슈(#2298~#2302)에서 이 기반 위에 영어를 붙입니다.
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

## 엔드포인트

### 시스템

| Method | Path | 응답 |
|---|---|---|
| GET | `/ping` | `{ message }` |
| GET | `/healthz` | `{ status, backend, env, demo_fallback, demo_seed, attachment_storage, commit_sha }` (#2821·#3029). `attachment_storage` 는 `local`·`s3`·`misconfigured` |
| GET | `/version` | `{ api_version, app_version, min_app_version, commit_sha }` — `app_version` 은 서버 버전. `min_app_version` 은 회원 모바일 앱 최소 지원 버전(`MAJOR.MINOR.PATCH`, 설정 `MIN_MEMBER_APP_VERSION`), 비어 있으면 `null` 이고 앱은 검사하지 않는다(#3045). `commit_sha` 는 이미지를 만든 커밋 SHA(40자), 빌드 인자 없이 만든 이미지는 `"unknown"`(#3029). 인증 없음 |
| GET | `/readyz` | `{ status: "ready" }` — DB 에 `SELECT 1` 까지 확인한다(3초 제한). 실패하면 **503** `{"detail": "서비스가 아직 준비되지 않았습니다."}`, 원인은 서버 로그에만 남긴다. `/healthz` 는 프로세스만 본다(liveness) |

### 관리자 전용

`users.is_admin` 인 계정만 쓴다. 관리자는 운영자가 계정 id 를 확인한 뒤
`python -m scripts.grant_admin --email … --confirm-id …` 로만 지정한다(#3037, [DEPLOY.md](docs/DEPLOY.md)).
예전처럼 `ADMIN_EMAILS` 로 기동 때 올리지 않는다 — 그 주소로 먼저 가입한 사람이 관리자가 됐다.
미인증 401, 관리자가 아니면 403.

| Method | Path | 응답 |
|---|---|---|
| GET | `/system/metrics` | AI 경로 성공·폴백 카운터 스냅숏(#583). 예: `routine_options.generated{by=ai}` 가 0 이면 AI 호출이 모두 폴백으로 떨어진 것이다 |
| POST | `/coach/documents/public` | 입력 `{ content, domain, title, source? }` → **201** `{ ingested_chunks, domain, title }` — 공공 RAG 문서 적재. 본문이 비면 400, 임베딩을 쓸 수 없으면(키 미설정 등) 503, 그 밖의 적재 실패는 502. 오류 본문에 내부 상세를 싣지 않고, 상관은 `X-Request-ID` 로 한다 |

### 사용자

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/users/me` | `{ id(str), name, email, role, consent_required, consent_pending[] }` (아래 "가입 동의" 참고, #2819). `role` 은 계정 역할 — 이 API 는 회원 전용이라 늘 `member` 이고 트레이너 토큰은 403. 회원 앱은 세션 복원 때 `role` 이 있으면 `member` 인지 확인하고, 없으면(옛 서버) 그대로 들어간다(#3054) |
| POST | `/users/me/consents` | `{ consents: [항목] }` → `{ consent_required, consent_pending[] }` (#2819) |
| GET, PUT, DELETE | `/users/me/consents/{kind}` | 선택 동의(`location`) 상태 조회·동의·철회 → `{ kind, agreed, current_version, version, agreed_at, revoked_at }`. 회원 전용, 선택 항목 아닌 `kind` 는 422 (아래 "선택 동의 — 위치정보 이용" 참고, #3136) |
| GET | `/users/me/health` | `{ profile: { id, name, email }, activity_points }` — MY 계정 카드. 위험 문구(`risk`)·활동 순위(`activity_rank`)·설정 메뉴(`settings[]`)는 앱이 읽지 않는 고정값이라 뺐다(#2903) |
| DELETE | `/users/me` | 본문 `{ reasons?, current_password? \| social_provider?·social_token? }` → `{ status: "deleted" }`. 본인 확인 필수, 실패 400(#3039) |
| GET | `/users/me/deletion-preview` | `{ points, active_coupons, upcoming_reservations, pending_consultations }` — 탈퇴하면 사라지거나 취소되는 것의 수(#3006). 아래 [탈퇴 미리보기](#탈퇴-미리보기-3006). 회원 전용(트레이너 403) |
| GET | `/users/me/profile` | `ProfileView` — `{ id, name, email, phone, birth_date, gender, height_cm, weight_kg, conditions, daily_calories, daily_sodium_mg, daily_sugar_g, daily_carbs_g, daily_protein_g, daily_fat_g, weekly_workout_goal, weekly_exercise_minutes_goal, weekly_burn_goal, daily_burn_kcal, weekly_cardio_minutes, weekly_strength_sets, weekly_flexibility_minutes, onboarded, focus_changed_by, focus_changed_at }` — MY 프로필 통합 뷰 |
| PUT | `/users/me` | 부분 수정 `{ name?, email?, phone?, birth_date?, gender?, height_cm?, weight_kg? }` → `ProfileView`. 이메일을 실제로 바꿀 때만 `current_password`(소셜 전용은 `social_provider`·`social_token`)를 함께 보내고, 그때 응답에 새 `access_token`·`refresh_token` 이 실린다(#3039). 다른 계정이 쓰는 이메일은 409, 전화번호를 빈 값으로 보내면 422. 형식 규칙은 아래 "인증" 의 연락처·이름·생년월일 절과 같다 |
| POST | `/users/me/onboarding` | 최초 온보딩 `{ name?, birth_date?, gender?, height_cm?, weight_kg?, conditions?, daily_*?, daily_burn_kcal?, weekly_cardio_minutes?, weekly_strength_sets?, weekly_flexibility_minutes? }` → `ProfileView`(`onboarded: true`). 보낸 필드만 반영한다 |
| PUT | `/users/me/health-goals` | 건강 목표(식단 일일 6종 + 운동 7종) 부분 수정 → `ProfileView` |
| GET | `/users/me/notification-settings` | `{ diet_log, exercise_reminder, trainer_message, ai_coaching, weekly_report }` — 회원 알림 수신 설정. 저장한 적이 없으면 서버 기본값(#489) |
| PUT | `/users/me/notification-settings` | 위 다섯 키 중 보낸 것만 반영 → 같은 모양 |
| POST | `/users/me/pairing-code` | `{ code, expires_at, expires_in_seconds }` — 트레이너에게 불러 줄 6자리 코드(#1634). **이 호출이 데이터 공유 동의다**(#1022). 유효한 코드가 남아 있으면 같은 코드를 돌려준다. 회원 전용, rate limit 적용 |
| DELETE | `/users/me/pairing-code` | 204 — 띄워 둔 코드를 버린다(화면을 닫을 때) |
| POST | `/users/me/password` | `{ current_password, new_password }` → `PasswordChanged`(새 토큰 한 쌍) — 회원 비밀번호 변경(#2824). 현재 비밀번호를 연달아 틀리면 계정 단위 잠금 429(#3087). 아래 [회원 비밀번호 변경](#회원-비밀번호-변경-2824) |

`DELETE /users/me` 는 본문으로 `{ reasons: [코드], current_password | social_provider·social_token }`
을 받는다(#2019, #3039). 본인 확인 값은 **늘 필요하다** — 아래 [본인 확인](#탈퇴로그인-이메일-변경-전-본인-확인-3039).
사유는 탈퇴의 조건이 아니다 — 아는 코드만 `account_deletion_reasons` 에 사유와 시각으로만
남고(누가 골랐는지는 남기지 않는다), 모르는 코드는 조용히 버린다. 아는 코드는
`privacy` · `rarely_used` · `hard_to_use` · `too_many_notifications` · `found_alternative` ·
`other`. 계정과 그에 매인 기록은 예전처럼 그대로 지워진다.

탈퇴하면 그 회원이 낀 채팅 스레드의 **첨부 파일(사진·리포트 PDF)도 저장소에서 지운다**(#2817).
스레드 행이 CASCADE 로 사라지므로 남긴 파일은 열 수 없는 고아가 된다. 트레이너 탈퇴
(`DELETE /trainer/me`)도 그 트레이너의 스레드 첨부를 같은 규칙으로 지운다. 파일 삭제는 커밋
뒤에 하고, 실패해도 응답은 `deleted` 다(서버 로그에 남겨 다시 지운다).

#### 탈퇴 미리보기 (#3006)

회원 탈퇴 마지막 확인창이 열 때 읽는다. 아무것도 바꾸지 않는다.

| 필드 | 뜻 | 세는 기준 |
|---|---|---|
| `points` | 남은 포인트 | `GET /users/me/health` 의 `activity_points` 와 같은 값 |
| `active_coupons` | 아직 쓸 수 있는 쿠폰 | `issued` 이고 `expires_at` 이 지나지 않은 것. 사용·취소·만료 제외, 종류 무관(식판 쿠폰 포함) |
| `upcoming_reservations` | 취소되는 예정 PT 예약 | `booked` 이고 시작 전인 것. 트레이너가 일정을 취소한 예약 제외 — `GET /reservations/me` 의 예정 예약과 같다 |
| `pending_consultations` | 취소되는 대기 상담 요청 | `pending` 이고 만료 시각(신청 24시간 뒤·자리 시작 2시간 전 중 이른 쪽)이 지나지 않은 것 |

앱은 0 인 항목을 보여 주지 않는다. 읽기에 실패하면 숫자 없이 "남은 포인트와 쿠폰이 사라지고
예정된 예약·대기 중 상담 요청이 취소된다" 는 고정 문구로 알린다. 보유 보호권·이모티콘·프로필
펫도 탈퇴와 함께 사라지지만 숫자로 세지 않는다(약관 해지 조항이 함께 고지한다).

#### 첫 설정 완료·건너뛰기 (#1927·#2855)

| Method | Path | 응답 |
|---|---|---|
| GET | `/users/me/profile` | 프로필 통합 뷰 — `onboarded`(첫 설정 저장함)·`onboarding_skipped`(첫 설정 건너뜀) 포함 |
| POST | `/users/me/onboarding` | 보낸 칸만 저장하고 `onboarded=true`. 응답은 프로필 통합 뷰 |
| POST | `/users/me/onboarding/skip` | 본문 없음. `onboarding_skipped=true` 만 남기고 다른 값은 그대로(`onboarded` 도 그대로). 여러 번 불러도 같다. 응답은 프로필 통합 뷰. 회원 전용(트레이너 403) |

앱은 `onboarded` 또는 `onboarding_skipped` 가 참이면 로그인·세션 복구 뒤 첫 설정
화면으로 보내지 않는다. 둘 다 거짓이면(가입 직후 폼에서 앱을 닫은 회원) 다음 진입 때
다시 첫 설정으로 보낸다(#2630). 건너뛴 회원은 MY `건강 목표` 화면의 안내 카드에서 첫
설정을 다시 열 수 있다.

### 채팅 이모티콘 (#2020, #2153)

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/me/emotes` | `{ unlocked: [{emote_id, expires_at, remaining_seconds}], cost, days, balance }` |
| POST | `/me/emotes/{emote_id}/unlock` | 같은 모양 — 산 뒤의 상태. 요청 `{ client_request_id? }` |

이모티콘은 **하나씩 사서 산 때부터 7일 동안** 쓴다(하나에 50P). `unlocked` 는 지금 쓸 수 있는
이모티콘이고 먼저 끝나는 것이 앞이다. 남은 기간은 `remaining_seconds` 로 준다 — 기기 시계가 틀어져도
어긋나지 않는다. 모르는 id 는 404, 쓰고 있는 이모티콘을 또 사면 409, 포인트가 모자라면 400 이다.
**담당 트레이너가 없으면 409 다**(#2142) — 이모티콘은 트레이너 채팅에만 있어서 사도 쓸 곳이 없다.
이미 산 이모티콘은 쓰던 중 담당이 끊겨도 남은 기간을 그대로 둔다. `client_request_id` 가 같은 재시도는
두 번 쓰지 않는다(200, 지금 상태). 원장 사유는 `emote_unlock` 이다.

409·400 의 `detail` 은 `{ code, message }` 다(#2845): `already_unlocked`(쓰고 있는 이모티콘 — 다른 키로
다시 산 경우 포함), `trainer_required`(담당 없음), `insufficient_points`(400). 앱은 키를 **구매 시도마다
한 번** 만들어 응답을 못 받은 재시도에 같은 키를 다시 보내고, `already_unlocked` 는 실패가 아니라
"이미 열려 있음" 으로 안내한다.

포인트 사용처에서는 팔지 않는다 — 무엇을 사는지는 채팅의 이모티콘 창에서 봐야 알 수 있다. 예전 24시간
이용권(`emote_pass_24h`, `POST /me/emotes/pass`)은 없어졌고, 사용처 교환으로 보내면 404 다. 바뀌기 전에 산
이용권은 남은 시간 동안 모든 이모티콘을 쓰고, `unlocked` 에 이모티콘마다 그 끝나는 시각으로 실린다.

이모티콘은 채팅 메시지에 실려 간다: `POST /me/coach/chat` 과
`POST /trainer/clients/{id}/chat` 이 `emote_id` 를 받고, `ChatMessageOut` 이 같은 값을
돌려준다. **회원은 그 이모티콘을 산 뒤 기간 안에만 보낸다**(아니면 402). **트레이너는 사지 않고
모두 보낸다** — 이모티콘 구매는 회원이 포인트를 쓰는 자리다. 모르는 id 는 400 이다. 본문(`body`)은
이모티콘을 그리지 못하는 자리(알림·로스터의 마지막 메시지)가 읽을 글로 채워 둔다.
그림과 목록은 앱이 들고 있다(공용 패키지 `oncare_ui` 의 에셋).

운동을 보낸 일도 채팅에 남는다(#2672). 트레이너가 회원에게 운동을 보내면(`POST /trainer/clients/{id}/routines`
단건 배정·AI 제안 승인·`/program` 의 `개인운동만`·PT 프로그램 보내기·취소 뒤 개인운동 보내기) 알림과 함께
트레이너 발신 메시지가 하나 생기고, `ChatMessageOut.routine_delivery` 에
`{ kind, program_names, routine_names }` 가 실린다. `kind` 는 `pt_with_routine` · `routine_only` ·
`cancelled_routine_only` · `routine`(단건) · `program`. 두 앱은 리포트 안내(`report_week_start`)처럼 대화
가운데 카드로 그리고, 본문은 카드를 못 그리는 자리(마지막 메시지)가 읽을 한 줄이다. 일반 메시지는 `null`.

**기간이 끝나도 이미 보낸 이모티콘은 그대로 보인다.** 지난 대화는 기록이라
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
| GET | `/dashboard/summary` | `{ indicators[], macros, diet_entries(int), exercise_minutes, nutrition_week[], sodium_warning(nullable), exercise_feedback, ai_advice_key(nullable), ai_advice_params }` |

`ai_advice_key` 는 홈 `오늘의 AI 통합 조언` 이 고른 문장의 로케일 독립 식별자다(#1943). 앱이 이 키를 먼저 보고 자기 문장을 그린다 — 키가 없으면 위 두 문장을 받은 그대로 쓴다. 값은 `sodium_over` · `sodium_over_sources` · `exercise_on_track` · `exercise_more` · `exercise_start` 중 하나다.

`ai_advice_params` 는 그 문장에 끼울 값이다(#2644). 음식 이름이 들어간 나트륨 경고(`sodium_over_sources`)는 `{ "foods": ["라면", "김밥"] }` 처럼 나트륨 상위 급원 음식 이름(최대 두 개)을 싣고, 나머지 키는 빈 객체다. 음식 이름은 회원이 적은 데이터라 번역하지 않고 앱 ARB 의 문장 틀에 그대로 끼운다. `sodium_warning` · `exercise_feedback` 문장도 요청 `Accept-Language` 를 따른다.

`nutrition_week[]`: `{ date, label, calories, sodium_mg, sugar_g }` — 이번 주 월~일 7일. 홈 식단 카드는 칼로리를 그린다.

주간 점수(`week_score`, `week_score_delta`), 지난 주 비교선(`nutrition_week_prev`), `exercise_calories` · `exercise_count` · `exercise_burn_goal` 은 홈이 읽지 않아 응답에서 뺐다(#2646).

`indicators[]`: `{ label, current(float), max(int), unit, over_budget?(bool) }` — 칼로리/나트륨/당류 3종.
`current` 는 당류가 소수(17.8g)라 float. 칼로리·나트륨은 정수 값이 그대로 실린다. 목표치(`max`)는 셋 다 정수.

### 식단 (칼로리·나트륨·당류·탄단지)

| Method | Path | 응답 핵심 필드 |
|---|---|---|
| GET | `/diet/days/today` | `{ entries[], total_calories, total_sodium_mg, total_sugar_g, macros, ai_coach_message }` |
| GET | `/diet/days/{date}` | `today` 와 같은 모양으로 그 날짜(`YYYY-MM-DD`) 하루. 형식이 깨지면 422 |
| GET | `/diet/photos/{photo_id}` | 끼니 사진 바이트(이미지). `entries[].photo_url` 이 이 주소를 가리킨다. **남의 사진은 404** — 주소를 추측해도 열리지 않는다(#699) |
| GET | `/diet/days?from=&to=` | `{ from_date, to_date, days[] }` — 날짜별 합계 `{ date, total_calories, total_sodium_mg, total_sugar_g, carbs_g, protein_g, fat_g }`. 기간 그래프가 쓰는 길이라 끼니·사진은 싣지 않는다. `from` 을 생략하면 **첫 기록일**부터, `to` 를 생략하면 오늘까지. 기록이 없는 날도 0 으로 채워 온다 (#2236). 구간은 끝(`to`, 오늘 이후면 오늘)에서 거슬러 **최대 1100일**(`diet_service.MAX_PERIOD_DAYS`)이고, 더 이른 `from`·첫 기록일은 그 하한으로 잘린다 — 응답 `from_date` 가 실제 시작일이다 (#2833). `from > to` 면 `to` 하루다 |
| GET | `/diet/advice?period=&lang=` | `{ period, from_date, to_date, days_logged, message, analysis, analysis_key?, analysis_params, action, action_key?, action_params, action_source? }` — 식단 탭 AI 맞춤 조언. `period` 는 `today`(기본)·`week`·`all`, `lang` 은 `ko`(기본)·`en`. 규칙 한 줄(`analysis`) + 다음 할 일 한 문장(`action`)이다 (#1017, #2251) |
| GET | `/diet/recommendations?use_llm=` | `{ items[{ key, reason_key, reason_text? }], basis?, personalized, source, days_with_data, avg_sodium_mg, sodium_limit_mg, trainer_pick? }` — 홈 `추천 식단`. `trainer_pick` 은 담당 트레이너가 확정한 추천 `{ slot, name, tag, keyword, trainer_name }` 이고 없거나 해소됐으면 null (#2378) |
| POST | `/diet/analyze` | multipart `{ image, meal_type, idempotency_key?, date? }` → `{ entry_id, analysis, time_label, photo_url?, points }` (분석과 동시에 diet_entries 저장·포인트 적립). `date`(`YYYY-MM-DD`)는 기록을 남길 날로, 지난 날짜 화면에서 연 추가가 싣는다(#2849). 없으면 저장하는 날(KST), 앞날·작년 1월 1일 이전·형식 오류는 인식 전에 422. 포인트 하루 한도는 지금처럼 적립 시점 기준이다. `meal_type` 이 다섯 값 밖이면 인식 전에 422(#2882) |
| POST | `/diet/entries` | `{ date?, meal_type, foods[](1개 이상, 이름 필수), idempotency_key? }` → 201, 새 `entries[]` 항목 하나 — 사진 없이 회원이 직접 적은 끼니(#2151). 합계는 음식에서 내고, **포인트는 적립하지 않는다.** `date` 가 없으면 오늘(KST), 앞날은 422. 당류 > 탄수화물인 음식이 있으면 422. 같은 `idempotency_key` 재전송은 처음 끼니를 돌려주고, 같은 키에 끼니·음식·(보냈다면)날짜가 다르면 409 이고 아무것도 바뀌지 않는다(#3095) |
| PUT | `/diet/entries/{id}` | 부분 수정 `{ date?, meal_type?, time_label?, foods?, total_calories?, carbs_g?, protein_g?, fat_g?, sodium_mg?, sugar_g? }` → 고쳐진 `entries[]` 항목 하나. `meal_type` 은 다섯 값, `time_label` 은 `HH:MM` 또는 빈 문자열(그 밖은 422, #2882) |
| DELETE | `/diet/entries/{id}` | `{ status: "deleted" }` — 그 끼니로 받은 포인트를 회수한다 |
| POST | `/diet/nutrition` | `{ name(필수), amount_g? }` → `{ matched_name?, match(exact\|similar)?, source, amount_g?, calories?, carbs_g?, protein_g?, fat_g?, sodium_mg?, sugar_g? }` — 이름으로 찾은 공공 DB 값(#1896). 못 찾았거나 양을 정할 수 없으면 `matched_name`·`match` 가 null |

**`POST /diet/analyze` 사진 정리.** 받은 사진은 인식 전에 한 번 정리한다(#3041) — EXIF 회전을 픽셀에 적용하고, EXIF(촬영 위치·시각·기기)·XMP 등 메타데이터를 모두 버린 장변 1600px 이하 JPEG(품질 85, 앱 업로드 크기와 같음)이다. 외부 인식 모델(Gemini·LiteLLM 비전)은 **원본이 아니라 이 정리본만** 받고, 끼니 사진 저장(`photo_url`, 장변 1024px)도 같은 정리본에서 만든다. PNG·WebP 도 정리본은 JPEG 이다. 같은 멱등키 재전송은 정리·인식 없이 기존 결과를 준다.

**`POST /diet/analyze` 거절 응답.** 앱은 `detail.code` 로 일반 실패와 구분해 안내한다. 아래 거절은 끼니·포인트·사진을 남기지 않는다.

- `503 { code: "analysis_unavailable", message }` — 사진 인식을 쓸 수 없는 설정(운영에서 인식 키 없음). 고정 식단으로 저장하지 않는다(#2812). 운영은 키가 없으면 기동부터 거부하므로 정상 배포에서는 나오지 않는다.
- `503 { code: "ai_capacity", message }` + `Retry-After` — 서버 전체의 오늘 AI 호출 상한 도달(위 "AI 하루 호출 상한", #3032). 모델을 부르지 않았고 회원 하루 분석 횟수도 돌려준다. 앱은 다시 시도 대신 직접 추가로 안내한다.
- `422 { code: "no_food_detected", message }` — 사진에서 음식을 하나도 찾지 못했다. 0kcal 끼니를 저장하지 않고 포인트도 없으며, 멱등키도 쓰지 않아 같은 키로 다른 사진을 다시 보낼 수 있다(#2848).
- `415` — 바이트가 JPG·PNG·WebP 가 아니다. 요청의 `Content-Type` 과 무관하게 바이트 시그니처로 판정하며, 모델을 부르기 전에 거절한다(#2827).
- `415` — 형식은 맞지만 픽셀을 읽을 수 없는 사진(매직 넘버만 맞춘 손상·위장 파일). 인식 모델을 부르기 전, 하루 분석 한도를 예약하기 전에 거절하므로 한도를 깎지 않는다(#3041).
- `429 { code: "rate_limited", message }` — 한 회원의 분당 분석 한도(`DIET_ANALYZE_PER_MINUTE`, 기본 10) 초과. `Retry-After` 헤더가 붙는다. 회원 id 로 세므로 같은 Wi-Fi 의 다른 회원에게 번지지 않는다(#2827).
- `429 { code: "daily_limit", message }` — 한 회원의 하루(KST) 분석 상한(`DIET_ANALYZE_PER_DAY`, 기본 20) 도달. KST 자정 뒤 다시 열린다. 모델을 부르기 직전에 세며, 같은 멱등키 재전송(모델 호출 없음)과 모델 호출 실패(502·501)는 세지 않는다. 음식을 못 찾은 사진(422)은 모델을 불렀으므로 센다(#2827).
- `engine` 쿼리는 비교실험용이다. 운영에서는 관리자만 적용되고 회원이 붙이면 무시한다. 개발용 스텁(`engine: "stub"`) 결과는 끼니로는 남지만 포인트·분석용 식판 조건에 세지 않는다(#2812).

`GET /diet/advice` 는 **규칙 한 줄 + 다음 할 일 한 문장**이다(#2251). 수치는 규칙이 계산하고, 두 문장을 합쳐 45자 안이다.

- `analysis`·`action` 은 한국어 문장이고 굵게 보일 곳(메뉴 이름·수치)을 `**` 로 감싼다. `message` 는 두 문장을 이어 `**` 를 뗀 평문으로, 두 문장을 모르는 옛 앱이 읽는다.
- `analysis_key`·`action_key` 가 있으면 앱이 그 키와 `*_params` 로 자기 언어의 문장을 그린다(운동 조언 `advice_key` 와 같은 방식, #2210). 키가 없으면 받은 문장을 그대로 쓴다 — AI 가 `lang` 으로 만든 문장이다.
- `오늘` 의 `analysis_key`: `today_empty`·`today_missing_meal`(시각이 지났는데 비어 있는 아침·점심·저녁이 있다)·`today_sodium_over{sodium_mg}`·`today_calorie_over{kcal}`·`today_protein_left{protein_g}`·`today_balanced{kcal}`.
- `오늘` 의 `action_key`: `next_meal{slot, menu, keyword}`·`next_snack{menu, keyword}` 는 최근 4주 기록으로 만든 **끼니별 추천 메뉴 리스트**(#2250)에서 오늘 가장 급한 부족·초과를 메우는 메뉴다(`action_source: "plan"`). 그 이유가 충족되면 다른 메뉴로 바뀌고, 최근 3일 안에 추천한 메뉴는 뒤로 미룬다. `keyword`(추천 이유, 예: `저나트륨`)는 문장에 싣지 않고 값으로만 준다. `today_done` 은 저녁까지 적었고 채울 것이 없을 때, `today_log_first` 는 `today_missing_meal` 일 때다 — 이때는 메뉴를 고르지 않고 리스트도 열지 않는다(`action_source: "rules"`).
- `이번 주` 는 **하루에 한 번** 만들어 그날 내내 같은 조언을 준다(#2253). 경계는 운동 조언과 같다 — 월·화이고 이번 주에 끼니를 기록한 날이 이틀 미만이며 지난주 기록이 있으면 지난주(월~일)를 돌아본다(`scope: last`, `from_date`·`to_date` 도 지난주다). `analysis_key`: `week_empty`·`week_skip_breakfast{scope, days}`·`week_skip_breakfast_snack{scope, days, snack_days}`·`week_focus_sodium|calorie|sugar|protein{scope, days}`·`week_good{scope, days}` — 끼니 습관(아침을 3번 이상 건너뜀) → 집중 목표(가장 많이 넘긴 영양소) → 칭찬 순으로 하나다.
- `이번 주` 의 `action` 은 AI 가 `lang` 으로 만든 한 문장이다(`action_key` 없음, `action_source: "llm"`). 원인 메뉴를 짚거나 대안을 주고, **수치를 쓰지 않는다**(검사해서 걸러 낸다). AI 가 실패하면 규칙 문장 `tip_breakfast|sodium|calorie|sugar|protein` 을 주고 1시간 뒤 다시 만든다. 칭찬은 `tip_keep`, 기록이 없으면 `week_empty_hint` 로 AI 를 부르지 않는다.
- `전체` 는 **최근 4주(28일)** 를 읽고 **한 주(월~일)에 한 번** 만든다(#2254). 그래프의 `전체` 기간(#2079)과는 무관하다. 기록이 7일 미만이면 `all_few_records{days}` + `all_few_hint` 로 AI 를 부르지 않는다. 그 밖의 `analysis_key` 는 `all_slot_sodium{slot, days}`·`all_carb_heavy{pct}`·`all_protein_light{pct}`·`all_protein_trend_up|down{before, after}`·`all_frequent_menu{slot, food, count}`·`all_repeated_foods{food1, food2}` 중 하나이고, 지난주에 말한 종류는 한 번 건너뛴다. 말할 것이 없으면 `all_good{days}` + `tip_keep`. `action` 은 AI 가 쓴 다음 4주의 행동 목표·대안이고(수치 없음), 실패하면 `tip_sodium|carb|protein|keep|swap|variety` 를 주고 1시간 뒤 다시 만든다.
- 트레이너웹 `GET /trainer/clients/{id}/diet-advice` 는 **트레이너용 `식단 분석`** 이다(#2379). 회원 앱과 같은 기간·같은 판정(오늘 합계, 이번 주 `decide_week`, 전체 최근 4주 `decide_all`)에 원인 음식·끼니를 붙인 서술형 규칙 문장이고 AI 를 부르지 않는다. 문장은 `sentences[{ key, params }]` 로 오고 트레이너 웹이 ARB 로 그린다. `message` 는 그 문장들을 요청 언어(`Accept-Language`)로 이은 평문이다. 키: 오늘 `tr_today_empty|over{nutrient, slot, food, food_value, value, target, ratio}|over_meal|protein_short{value, gap}|protein_chronic{value, gap, avg}|missing{slot}|good{kcal}`, 이번 주 `tr_week_empty|skip_breakfast{scope, logged, days}|skip_breakfast_snack|over{scope, logged, days, nutrient}|cause{weekday, slot, food, food_value, nutrient}|protein_short|good{scope, days}`, 전체 `tr_all_few{days}|slot_sodium{slot, days}|carb_heavy{pct}|protein_light{pct}|protein_trend_up|down{before, after}|frequent{slot, food, count}|repeated{food1, food2}|good{days}` 와 원인 음식 `tr_foods_one|two{food1, count1, food2, count2}`. 음식 이름은 회원이 기록한 말 그대로다. 회원 경로의 `sentences` 는 비어 있다.

**트레이너 식단 추천(#2378).** 트레이너가 회원의 4주 추천 메뉴 리스트(#2250)에서 AI 후보를 골라 확정하면, 회원 `GET /diet/recommendations` 의 `trainer_pick` 이 되어 홈 `추천 식단` 첫 장에 `트레이너 추천` 으로 뜬다.

- `GET /trainer/clients/{id}/diet-recommendations` → `{ needs[], basis_days, pick?, candidates[] }`. `needs` 는 최근 4주 평균이 목표에서 벗어난 태그(`sodium_low`·`protein_high`·`calorie_low|high`·`sugar_low`)를 급한 순서로 담고, 비면 채울 점이 없어 `candidates` 도 빈다. `candidates[{ slot, name, tag, keyword, kcal, protein_g, sodium_mg, urgent }]` 는 급한 태그의 메뉴부터 끼니 순이며 지금 확정한 메뉴는 뺀다. 저장된 리스트를 읽기만 하므로 조회로 AI 를 부르지 않고, 리스트는 회원 언어 그대로다(없을 때만 요청 언어로 한 번 만든다).
- `pick{ slot, name, tag, keyword, status(active|resolved), confirmed_at, resolved_at? }` — 회원이 확정 뒤 기록한 끼니의 음식 이름이 메뉴 이름을 품으면(띄어쓰기·대소문자 무시) 즉시 `resolved` 가 되고 회원 홈에서 내려간다.
- `PUT /trainer/clients/{id}/diet-recommendations` `{ slot, name }` → 같은 응답. 회원당 한 건이라 다시 부르면 바꾸기다. 지금 리스트에 없는 메뉴는 422.
- 담당이 아니거나 해제·동의 철회된 회원은 다른 트레이너 경로와 같은 404. 담당을 해제하면 그 트레이너의 추천도 지운다.

`entries[]`: `{ id(str), meal_type(breakfast|lunch|dinner|snack|lateNight), time_label, foods[], total_calories(int), sodium_mg(int), sugar_g(float), ai_comment(str), photo_url(str?) }`
`meal_type` 값은 회원 앱 `MealType.name` 그대로다 — 그래서 `lateNight`(야식, #1988)만 camelCase 다. DB 는 `String(20)` 자유 문자열이지만 **API 가 다섯 값만 받는다** — 직접 기록·사진 분석(인식 전)·수정 모두 다섯 값 밖이면 422 다(#2882, `MealTypeLiteral`). 새 끼니를 더할 때는 enum 이름·전송값·`MealTypeLiteral` 을 함께 고친다. `PUT` 의 `time_label` 은 `HH:MM`(24시간)이거나 빈 문자열이고, 그 밖은 422 다.
`lateNight` 이전에 저장된 `snack` 은 그대로 `snack` 이다 — 백필하지 않는다. 앱은 모르는 `meal_type` 을 간식으로 접어 읽고 죽지 않는다.
`ai_comment` 는 사진 분석이 만든 식단평이다(#1932). 손으로 고쳐 만든 끼니와 분석이 식단평을 내지 못한 끼니는 빈 문자열이고, 앱은 비어 있으면 그 줄을 그리지 않는다.
당류만 소수다 — 항목 단위 당류가 6.3g·8.5g 처럼 소수로 들어오고 합계도 절삭 없이 유지된다(`total_sugar_g` 도 float).
`foods[]`: `[{ name, display_name(str?), amount_g(float?), calories(int?), sodium_mg(int?), sugar_g(float?), carbs_g(float?), protein_g(float?), fat_g(float?), source(db|estimate|mixed|member) }]` — 음식별 영양은 회원이 식단 상세에서 고칠 수 있는 값이고, 그대로 저장된다(#1856, #1892).

**사진 분석 값의 범위(#3090).** 인식 모델의 응답은 외부 입력으로 보고 서버가 걸러 저장한다. 음식 한 항목에서 `calories` 는 0~5000, `sodium_mg` 는 0~20000, `carbs_g`·`protein_g`·`fat_g`·`sugar_g` 는 0~1000, `amount_g` 는 0 초과~5000 이다. 음수·비유한값·숫자가 아닌 값·이 범위를 넘는 값은 모름(`null`)으로 저장하고 그 음식은 남긴다 — 앱은 `—` 로 보인다. 그래도 읽을 수 없는 항목(예: 확신도가 0~1 밖)은 그 항목만 빼고, 남은 음식이 없으면 `no_food_detected` 422 다. `name` 은 공백을 한 칸으로 접어 80자, `coach_comment` 는 300자까지 받고, 음식은 한 사진에 20개까지다. 비거나 문자열이 아닌 이름은 `알 수 없음` 이다. 공공 DB 보정(`source=db`·`mixed`)이 DB 밀도 × 양으로 다시 낸 값은 이 상한을 거치지 않는다. 음식별 `calories`·`sodium_mg` 는 수정 경로(`PUT`)를 포함해 음수면 422 다.

`source` 는 그 음식의 숫자가 어디서 왔나다. `db`(공공 DB × 양) · `mixed`(DB 행에 탄단지가 비어 인식기 값을 남김) · `estimate`(매칭이나 양이 없어 인식기 추정 그대로) · `member`(회원이 수정 화면에서 영양 칸을 직접 고침, #2105). **`PUT` 의 `foods[].source` 는 앱이 정해 보낸다** — 손대지 않은 음식과 섭취량만 바꾼 음식은 원래 값을, 공공 DB 값으로 채운 음식은 `db` 를, 영양 칸을 고친 음식은 `member` 를 싣는다. 네 값 밖은 422 이고, **빠지면 `member` 로 저장한다**(인식기 쪽 기본값 `estimate` 를 쓰면 수정 경로로 들어온 숫자를 인식기 추정이라 부르게 된다). 이 필드 이전 기록은 `source` 가 없을 수 있고, 읽는 쪽은 `estimate` 로 읽는다.

`POST /diet/nutrition` 의 `match` 는 찾은 음식이 **같은 음식**(`exact` — 이름·별칭·양 표기를 뗀 이름·`계란`→`달걀` 표기 변형이 표 이름과 같다)인지, 이름 끝말로 붙은 **비슷한 음식**(`similar` — `야채비빔밥` → `비빔밥`)인지다(#2107). 수정 화면은 이름을 바꾼 음식이 같은 음식에 붙으면 곧바로 그 값으로 채우고, 비슷한 음식이면 제안만 한다. 매칭은 사진 분석 보정과 같은 것이다.

`display_name` 은 화면 언어로 된 표시 이름이다(#2850). `Accept-Language: en` 으로 사진을 분석하면 인식기가 영어 이름을 함께 내고, `name` 은 공공 DB 매칭용이라 **한국어 그대로** 둔다 — 영양 보정은 화면 언어와 상관없이 같다. 같은 요청의 식단평(`analysis.coach_comment`, 저장되는 `ai_comment`)도 영어로 쓴다. 한국어 화면·수기 입력·이 필드 이전 기록에는 키가 없고, 읽는 쪽은 `display_name` 이 있으면 그것을, 없으면 `name` 을 보인다. `PUT` 은 앱이 이름을 바꾸지 않은 음식에만 되돌려 싣는다(바꾼 이름이 회원이 쓴 표시 이름이다). 저장된 식단평은 분석 당시 언어로 남는다.

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
| GET | `/exercise/weeks?from=&to=` | `{ from_week, to_week, weeks[] }` — 구간이 걸친 주들. 한 칸은 `{ week_start, day_labels[7], daily_minutes[7], daily_calories[7], cardio_minutes[7], strength_minutes[7], strength_sets[7], stretching_minutes[7], other_minutes[7], total_minutes, total_calories, streak_days, weekly_goal_minutes, weekly_goal_calories }` 다. 기간 그래프가 쓰는 길이라 `sessions` 와 코칭 문구는 싣지 않는다 — 한 주를 펼쳐 볼 때는 위 `weeks/current` 다. `from` 생략 시 **첫 기록 주**부터, `to` 생략 시 이번 주까지. 월요일이 아닌 날짜는 그 주의 월요일로 맞춘다. 기록이 없는 주도 0 으로 채워 온다 (#2247). 구간은 끝 주에서 거슬러 **최대 160주**(`exercise_service.MAX_PERIOD_WEEKS`)이고, 더 이른 `from`·첫 기록 주는 그 하한으로 잘린다 — 응답 `from_week` 가 실제 시작 주다 (#2833) |
| POST | `/exercise/sessions` | 입력 `{ sessions: [항목 1~20개], client_request_id? }` — 항목은 `{ type, name, minutes(>0) 또는 duration_seconds(>0), calories, intensity(light\|moderate\|high), sets?, reps?, hold_seconds?, weight?, date? }` → `{ sessions[](요청 순서), points(합계) }`. **한 트랜잭션**이라 항목 하나라도 잘못되면 전체가 422 이고 아무것도 저장되지 않는다. 한 건도 목록으로 감싸 보낸다 — 감싸지 않은 단건 입력은 422 (#2544). `date` 는 생략하면 오늘(KST)이고, **오늘보다 뒤 날짜는 422**(`date 는 오늘보다 뒤일 수 없습니다.` — 식단 기록과 같은 문구, #3042). 기록·포인트·코치 적재·보호권 환급을 하나도 남기지 않는다. `client_request_id`(1~64자)는 저장 시도 단위 멱등키다 — 같은 키로 저장한 기록이 남아 있으면 새로 저장·적립하지 않고 처음 응답(`points` 는 그 기록들이 처음 받은 적립의 합)을 다시 돌려주고, 항목 수나 항목 내용(칼로리 제외, `date` 는 보낸 경우만)이 다르면 409 이고 아무것도 바뀌지 않는다. 그 키의 기록이 모두 지워졌으면 처음 보는 키처럼 새로 저장한다. 키가 없으면 매번 새로 저장한다 (#3095) |
| PUT | `/exercise/sessions/{id}` | 입력은 위 **항목 하나**(부분 갱신) → 갱신된 항목(`points` 없음). `date` 를 주지 않으면 원래 날짜를 그대로 두고, 오늘보다 뒤로 옮기면 422 다 — 원래 날짜가 남는다(#3042) |
| DELETE | `/exercise/sessions/{id}` | `{ status: "deleted" }` — 그 기록으로 받은 포인트를 회수한다 |
| GET | `/exercise/advice?period=` | `{ period, from_date, to_date, days_logged, message, advice_key?, advice_params }` — 운동 탭 AI 조언. `period` 는 `today`(기본)·`week`·`all`. 식단 조언과 같은 규칙이고, 문장은 트레이너 웹의 `/trainer/clients/{member_id}/exercise-advice` 와 같다(#1574, #1025). 앱은 `advice_key`·`advice_params` 로 자기 언어 문장을 그린다(#2210) |
| POST | `/exercise/calories` | 입력 `{ type, name(필수), minutes(>0) 또는 duration_seconds(>0), intensity }` → `{ calories, source, matched_name, isometric }` — 초가 오면 분은 `/exercise/sessions` 와 같은 규칙으로 초에서 접는다 (#2547) |

추천 개인운동(`GET /me/coach/routines`, 트레이너 쪽 `RoutineOut` 도 같다)은 `effect` 를 싣는다 — 운동 이름 아래 서는 효과 한 줄로, 트레이너가 적은 값이거나 비었으면 운동 유형 × 회원 첫 건강 목표 문구표의 값이다. 운동 여럿으로 짠 세션·`기타` 유형은 빈 문자열이다. 규칙은 [TRAINER_DOMAIN.md](docs/TRAINER_DOMAIN.md) "추천 개인운동의 효과 한 줄" (#2570)

`sessions[]`: `{ id(str), day_label, type(cardio|strength|yoga|walking), minutes, duration_seconds, calories, calorie_source, intensity(light|moderate|high), sets, reps, hold_seconds, weight, source(member|trainer_pt|assigned_routine), date_label, time_label(str?), items[str], record(str?) }`
`time_label`: PT(`trainer_pt`) 기록만 그 수업 일정의 시각(`HH:MM`)을 싣는다. 배정 개인운동·회원 기록은 언제 했는지를 남기지 않아 `null` 이고, 수업을 찾지 못한 PT 도 `null` 이다 — 유형별 시각을 지어내지 않는다. 회원 앱은 이 값을 "○○ 수업 완료" 로 그린다. (#2692)
`record`: 개인 기록 태그 — `max_weight`(같은 근력 운동을 전에 든 어떤 중량보다 무겁다) · `longest`(같은 운동을 전에 한 어떤 시간보다 길다, 근력 외) · `first`(이 이름으로 처음 적은 운동) · `null`. 회원이 직접 적은 기록(`source == member`)에만, 한 기록에 하나 붙는다(우선순위도 이 순서). 같은 운동은 이름의 공백을 지우고 소문자로 맞춰 묶고, 지난 주 기록까지 견준다. 평가가 아니라 사실만 알린다 (#2971)
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
| `diet_entry` | `POST /diet/analyze` 로 끼니가 새로 저장될 때(직접 추가 `POST /diet/entries` 는 적립 없음, #2151) | +50 | 3회 |
| `exercise_manual` | `POST /exercise/sessions` (회원이 직접 추가) | +20 | 3회 |
| `routine_complete` | `POST /me/coach/routines/{id}/complete` — AI 추천(`source: "ai"`)·트레이너 배정(`source: "trainer"`) 모두 | +50 | 1회(두 출처 합산) |

생성 응답의 `points`: `{ awarded(int), balance(int) }` — 이번에 받은 포인트와 그 뒤의 잔액. 운동 여러 개를 한 번에 추가하면(`POST /exercise/sessions`) 한도는 항목마다 세고 `awarded` 는 그 합계다 — 다섯 개를 한 번에 저장해도 60P 다. (#2544)

- **하루**는 KST 달력 날짜다. 한도를 넘으면 기록은 저장되고 `awarded: 0` 이다.
- 한도는 **적립하는 날** 기준이다. 지난 날짜 기록(`POST /exercise/sessions` 의 `date`, 개인운동 완료의
  `?date=`, #2506)도 오늘 한도를 쓴다 — 지난 날짜를 몰아 체크해도 오늘 받는 만큼만 받는다.
- **같은 기록은 한 번만** 받는다(`(user_id, kind, source_type, source_id)` 유니크). 멱등키 재시도·완료
  재전송은 새로 적립하지 않고 처음 받은 `awarded` 를 그대로 싣는다.
- **기록을 지우면 회수**한다(`DELETE /diet/entries/{id}`, `DELETE /exercise/sessions/{id}`,
  `DELETE /me/coach/routines/{id}/complete`). 잔액은 0 아래로 내려가지 않는다 — 모자라면 남은 만큼만
  빼고 내역에 실제로 뺀 값을 적는다. **전액 회수된 적립만** 그날 한도에서 빠진다 — 잔액이 모자라 0P·일부만
  회수됐으면 그 칸은 그대로다(받은 포인트를 쓰고 지웠다 다시 기록해 한도를 넘지 못하게, #3084). 다시 만든
  기록은 새 기록이다.
- 배정 루틴 완료 응답은 `RoutineOut` + `points` 다. 앱의 안내 문구는 `추천·배정 운동 완료` 로, AI 추천과
  트레이너 배정이 **하루 1회를 함께** 쓴다 — 배정 루틴으로 받은 날은 AI 루틴을 완료해도 `awarded: 0`.
  목록·수정 응답에는 `points` 가 붙지 않는다.

### 포인트 사용처·쿠폰 (#1787)

| Method | Path | 권한 | 응답 |
|---|---|---|---|
| GET | `/me/points/shop` | 회원(데모 폴백) | `{ balance, has_trainer, has_gym, gym_benefits_enabled, items[] }` |
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
`no_trainer` → `no_gym` → `active_coupon` → `shield_limit` → `active_pet` → `week_owned` → `monthly_limit` →
`insufficient_points` 순으로 하나만, 교환할 수 있으면 null. `shortfall` 은 모자란
포인트(모자라지 않으면 0). `has_gym` 은 회원 헬스장 링크(`member_gyms`)가 있는지다. 교환 응답은 쿠폰이면 `coupon`,
보호권이면 `coupon: null` 과 `shield`, 그래프 색이면 `graph_color` 다(아래 두 절).

**헬스장 혜택 기능 플래그**(#2822): `pt_renewal`·`locker_month`·분석용 식판은 헬스장이 현장에서 주는 혜택이다.
서버 설정 `GYM_BENEFITS_ENABLED` 가 거짓이고 데모 시드도 꺼진 서버(제휴 확정 전 실서비스)는 `gym_benefits_enabled:
false` 를 주고 `items[]` 에서 두 항목을 **뺀다**. 이때 두 항목을 교환하면 404, 식판 받기는 409 다. 데모 시드가
켜진 서버는 플래그와 상관없이 연다. 이미 발급된 쿠폰은 `scripts/cancel_gym_benefit_coupons.py` 로 취소·반환한다
(알림 까닭 `service`, `backend/docs/DEPLOY.md` 참고).

`active_option`·`active_until`·`remaining_seconds` 는 기간제 항목을 쓰고 있을 때 고른 갈래·끝나는 시각·남은 초다 —
지금은 `profile_pet` 이 달고 있는 펫과 남은 기간을 싣는다(카드가 `강아지 · 5일 남음` 을 적는다). 아니면 null·null·0.

`option` 은 항목이 여러 갈래일 때 고른 갈래다 — `graph_color` 에서 어느 색을 열지, `profile_pet` 에서 어느 펫을 달지
싣는다. 다른 항목은 보지 않는다.

**포인트 내역(#2146).** `items[]`: `{ id, kind, reason, delta, count, kst_date, created_at }` — 원장(`points_ledger`) 한 줄씩, 최신순.
`kind` 는 `earn`(적립)·`spend`(사용)·`revoke`(회수 — 기록을 지워 적립을 되돌림)·`refund`(반환 — 쿠폰 취소 등). `delta` 는 잔액 변화량(적립·반환
양수, 사용·회수 0 이하). `reason` 은 사유 코드(`diet_entry`·`exercise_manual`·`routine_complete`·`coupon_<항목>`·`streak_shield`·`graph_color`·
`emote_unlock`·`emote_pass_24h`(지난 24시간 이용권)·`profile_pet`·`weekly_report`·`challenge_stake`·`challenge_reward`·`ai_chat`)이고 앱이 문구로 바꾼다.
- **날짜 단위로 넘긴다.** 기록이 있는 날 기준 최근 14일치를 주고, 더 있으면 `next_before`(받은 날 중 가장 앞 날짜)를 `before` 로 넘겨 그보다 앞을 받는다.
- **AI 코치 대화는 하루 한 줄로 묶는다**(#2145) — `count` 에 대화 수, `delta` 에 합계. 한 통마다 한 줄이면 내역이 채팅 기록처럼 길어진다.

`coupon`: `{ id, item, title, benefit, cost, status, trainer_name, gym_name, issued_at, issued_on,
expires_at, expires_on, days_left, no_expiry, used_at?, cancelled_at? }`. `no_expiry` 가 참이면 기한 없는
쿠폰(분석용 식판, #2150)이고 `expires_on`·`days_left` 는 뜻이 없다(`days_left` 0). `trainer_name` 은 PT 재등록 쿠폰을 교환할 때의 담당
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

### 분석용 식판 (#2150)

| Method | Path | 권한 | 응답 |
|---|---|---|---|
| GET | `/me/diet-tray` | 회원(데모 폴백) | `{ status, photo_days, required_days, window_days, window_from, window_to, has_trainer, coupon?, enabled }` |
| POST | `/me/diet-tray/claim` | 회원 | 입력 `{ client_request_id? }` → **201** 같은 모양(받은 뒤) |

식단 사진 분석에 맞춘 **규격 식판**을 사진 기록을 꾸준히 남긴 회원에게 무료로 준다. 포인트 교환이 아니라 달성
보상이다 — 사용처 목록(`/me/points/shop`)에 없고, `POST /me/points/exchange` 에 `diet_tray` 를 주면 404 다.

- **조건** 최근 `window_days`(28)일(KST, 오늘 포함 — `window_from`~`window_to`) 중 식단 사진을 남긴 날(`photo_days`)이
  `required_days`(20)일 이상이고 활성 담당이 있다. 사진 분석으로 저장한 끼니(`diet_entries.engine` 이 빈 값이 아님)만
  세고, 하루 여러 끼도 하루다. 손으로 적은 끼니와 보호권으로 이은 날은 세지 않는다.
- **`enabled`** 식판을 줄 수 있는 서버인가(#2822, 위 헬스장 혜택 기능 플래그). 거짓이면 `status` 가 `claimable` 이
  되지 않고 받기는 409, 회원 앱은 카드를 그리지 않는다. 이미 받은 쿠폰은 `coupon` 에 그대로 온다.
- **`status`** `progress`(조건을 채우는 중이거나 담당 없음) · `claimable`(지금 받을 수 있음) · `issued`(수령 쿠폰을
  받았고 아직 쓰지 않음) · `received`(식판을 받음). `coupon` 은 `issued`·`received` 일 때의 쿠폰, 그 밖에는 null.
- **받기** 조건을 서버가 다시 확인하고 `coupon`(item `diet_tray`, `cost` 0, **기한 없음** — `no_expiry: true`)을
  만든다. 담당 트레이너와 그 헬스장이 `trainer_name`·`gym_name` 에 남고, 그 헬스장에서 받는다. 식판이 헬스장에 언제
  닿을지는 우리 사정이라 기한을 두지 않는다 — 회원은 가기 전에 담당 트레이너에게 채팅으로 준비됐는지 묻는다(트레이너
  웹에 알림이 없어 "준비 완료" 를 알릴 길이 아직 없다). 만료 임박 알림도 없다. 쿠폰 목록·사용 처리는 위 쿠폰 절과 같다(직원 확인 뒤
  회원 휴대폰에서 `사용 완료`). 포인트 내역에는 남지 않는다. 담당 없음·사진 기록일 부족·이미 받음·받지 않은 식판 쿠폰
  보유는 409, 같은 `client_request_id` 재전송은 새로 만들지 않는다.
- **1인 1회** `used` 식판 쿠폰이 있으면 다시 받지 않는다. 담당 해제로 취소된 쿠폰은 식판을 받은 것이 아니라, 새 담당이
  생기고 조건을 채우고 있으면 다시 받는다.
- **담당 해제** PT 재등록 쿠폰과 같은 경로에서 받지 않은 식판 쿠폰을 `cancelled` 로 바꾸고 `식판 수령 쿠폰이
  취소됐어요` 알림(`benefits`)을 만든다. 0P 라 돌려줄 포인트는 없다.

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
- **`protectable_from`·`protectable_to`** 지금 보호권을 쓸 수 있는 날의 구간(양끝 포함). 보호권이 없어도 내려 준다 — 앱은 `held` 가 0 이면 그 칸에서 교환과 사용을 한 번에 잇는다.
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
| GET | `/me/records/span` | 회원(데모 폴백) | `{ diet_first_date, exercise_first_date }` — 식단·운동을 처음 남긴 날(없으면 null). `전체` 그래프가 어디서부터 그릴지 정하는 값이다 (#2079, #2236) |
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
  판정은 **미리 적은 기록**(기록 날짜가 저장된 날(`created_at` 의 KST 날짜)보다 뒤인 것)을 세지 않는다 — 운동 기록 API 가
  앞날을 받기 전에 저장된 기록으로 성공하지 못한다. 그날 적은 기록과 지난 날을 뒤늦게 적은 기록은 센다(#3042).
- **늦은 판정** 스케줄러가 없어 `GET /me/challenges/weekly`, `GET /me/challenges`, `POST /me/challenges/weekly/join`,
  `GET /me/points/shop`, `GET /users/me/health`, `GET /notifications` 를 부를 때 끝난 주의 진행 중 챌린지를 판정한다.
  조건부 UPDATE 한 번이라 보상·결과 알림은 챌린지마다 한 번뿐이다.
- **알림** 판정마다 결과 알림 한 건. `category` 는 `points_shop`, `action` 은
  `{ label: "포인트 사용처 보기", target: "points_shop" }` — 결과를 읽고 할 일(다음 주 참가·돌려받은 포인트 확인)이 그
  화면에 있다. 내 혜택은 교환해 **가진 것**(쿠폰·보호권)만 두므로 챌린지를 싣지 않는다. 수신 설정 스위치는 없다.

### 알림 (액션)

| Method | Path | 응답 |
|---|---|---|
| GET | `/notifications` | `[{ id, title, body, category, read(bool), created_at(ISO), time_ago, action, invite_id, template, args }]` (배열, 최신순, 기본 50건) |
| GET | `/notifications/unread-count` | `{ unread(int) }` |
| POST | `/notifications/{id}/read` | 단건 읽음 → `{ id, read: true }` |
| POST | `/notifications/read-all` | 전체 읽음 → `{ marked_read(int) }` |
| DELETE | `/notifications/{id}` | 삭제 → `{ status: "deleted" }` |

category: reminder|health_check|achievement|system|coach_chat|coach_report|routine|member_schedule|pt_done|coach_invite|consultation_result|consult_decision|health_goals|benefits|points_shop

`action` 은 `{ label, target }` 또는 `null`(읽음 처리만 하는 알림)입니다. `label` 은 요청 언어(`Accept-Language`)이고
`target` 은 회원 앱이 아는 목적지(`dashboard`|`coach_chat`|`exercise`|`diet`|`my_benefits`|`points_shop`|`health_goals`|
`consultations`)입니다.

- **알림별 목적지 우선(#2690·#3028)**: 알림 행의 `action_target` 이 있으면 그 목적지, 없으면 아래 갈래별 표를 씁니다.
  서버는 `notification_service.queue(action_target=...)` 로 이 칸을 채웁니다 — 갈래(아이콘)는 같은데 갈 곳만 다른 알림에
  씁니다. 허용 목록(`MEMBER_ACTION_TARGETS`) 밖의 값은 저장 전에 거부합니다.
- **갈래별 액션** (한국어 / 영어 → target)

  | category | label | target |
  | --- | --- | --- |
  | `reminder`·`health_check` | 기록하러 가기 / Log now | `dashboard` |
  | `achievement` | 대시보드 보기 / View dashboard | `dashboard` |
  | `coach_chat` | 대화 보기 / View chat | `coach_chat` |
  | `coach_report` | 리포트 보기 / View report | `coach_chat` |
  | `routine` | 운동 보기 / View workouts | `exercise` |
  | `member_schedule` | 일정 보기 / View schedule | `exercise` (#3028) |
  | `pt_done` | PT 기록 보기 / View PT record | `exercise` (#3027) |
  | `coach_invite` | 요청 확인 / View request | `exercise` |
  | `consultation_result` | 트레이너 보기 / View trainer | `exercise` |
  | `consult_decision` | 상담 요청 보기 / View consultation requests | `consultations` |
  | `benefits` | 내 혜택 보기 / View my benefits | `my_benefits` |
  | `points_shop` | 포인트 사용처 보기 / View points shop | `points_shop` |
  | `health_goals` | 목표 보기 / View goals | `health_goals` |
  | `system`·그 밖 | 없음 | — |

  `member_schedule`(PT 일정 등록·변경·취소·인계, 담당 해제·트레이너 탈퇴로 취소된 일정)은 예전에 회원 앱에 일정 화면이
  없어(#1928) 액션이 없었습니다. 이제 운동 탭이 트레이너 일정과 회원 예약을 합친 다음 PT 배지와 헬스장 패널 예약을
  보여 줍니다. 이미 저장된 일정 알림도 응답 때 액션을 만들어 바로 버튼이 보입니다.
- **PT 수업 완료·피드백(#3027)**: 트레이너가 회원 PT 를 완료(`POST /trainer/schedule/{session_id}/complete`)하면
  `pt_done` 알림 한 건 — 틀 `member_pt_completed`(인자 `trainer_name`·`session_number`(회원 앱 PT 카드와 같은 회차,
  없으면 생략)·`has_note`·`date`), 본문은 트레이너 피드백이 있으면 그 글, 없으면 "운동 기록에 남겼어요". 완료 뒤 PT 메모가
  **비어 있다가 처음 채워지면** `member_pt_feedback` 한 건 더(본문 = 피드백). 완료 재호출·동시 호출·상담 일정·회원 없는 슬롯·
  이미 있던 피드백 수정·예정 PT 메모에는 알림이 없습니다. 수신 설정 키는 `exercise_reminder` 입니다.
  회원 앱은 `pt_done` 을 일정(`member_schedule`)과 다른 'PT 기록' 갈래로 보여 주고, 두 알림 모두 운동 탭으로 가면서
  다음 PT 일정·내 예약을 다시 읽습니다. 데모(목 모드)도 같은 버튼을 붙입니다.

#### 회원 알림 수신 설정 (#489·#2854·#3024·#3025)

| 메서드 | 경로 | 응답 |
| --- | --- | --- |
| GET | `/users/me/notification-settings` | `{ diet_log, exercise_reminder, trainer_message, ai_coaching, weekly_report }` (bool) |
| PUT | `/users/me/notification-settings` | 보낸 항목만 반영, 응답은 GET 과 같음 |

- 회원 앱 스위치는 `exercise_reminder`·`trainer_message`·`weekly_report` 세 가지입니다.
  `diet_log`·`ai_coaching` 은 **이 kind 로 만드는 알림이 없어** 앱이 더는 그리거나 보내지 않고,
  이미 저장된 값과 예전 앱 버전을 위해 응답·저장에만 남아 있습니다.
- 각 키가 끄는 알림과 기본값(저장한 적이 없을 때). 키 이름은 서버·앱 계약이라 화면 라벨이
  바뀌어도 그대로입니다.

  | 키 | 회원 앱 라벨 | 끄는 알림 | 기본값 |
  | --- | --- | --- | --- |
  | `exercise_reminder` | 개인운동·프로그램 | 트레이너의 개인운동·PT 프로그램 전송(`routine`), PT 완료·피드백(`pt_done`) | 켬 |
  | `trainer_message` | 트레이너 메시지 | 코치 채팅 메시지(`coach_chat`) | 켬 |
  | `weekly_report` | 트레이너 주간 리포트 | 담당 트레이너가 보낸 주간 리포트(`coach_report`) | 켬 (#3025, 예전 끔) |

  `weekly_report` 기본값은 마이그레이션 0143 에서 켬으로 바뀌었고, 그때 저장돼 있던 `false` 도
  한 번 `true` 로 바꿨습니다(그 전까지 앱에서 끌 이유가 된 알림이 없었습니다). 그 뒤 회원이 끈
  값은 그대로 지킵니다. 포인트로 만드는 '주간 리포트'(`/me/points/exchange`)와는 다른 알림입니다.
- **끌 수 없는 알림**: 포인트 쿠폰(`points_coupon`)·주간 챌린지 결과(`weekly_challenge`)와
  **PT 일정·담당 관계 알림**(`pt_link_notice`, #3024)은 설정과 무관하게 늘 만듭니다
  (`notification_service.ALWAYS_DELIVERED`). `pt_link_notice` 는 PT 일정 등록·변경·취소·삭제·
  인계(`member_schedule`), 담당 연결(`consultation_result`)·담당 요청(`coach_invite`),
  담당 해제·트레이너 탈퇴와 그로 인한 예약 취소에 씁니다. 예전에는 이 알림이 `exercise_reminder`·
  `trainer_message` 를 따라, 회원이 루틴 알림을 끄면 PT 취소 알림까지 끊겼습니다.
  트레이너 탈퇴 알림은 **활성 담당 회원**에게만 가고, 담당이 끝난 회원은 예약이 남아 있을 때만
  '예약한 수업이 취소되었어요' 알림을 받습니다. 새 회원 알림 kind 는 설정 키이거나 이 집합에
  있어야 합니다.

#### 알림 문장의 언어 (#2302)

알림은 만든 순간의 한국어 문장만 저장해 영어 화면에서도 한국어로 보였습니다. 이제 **문장 틀
코드와 인자를 함께 저장하고, 읽을 때 요청 언어(`Accept-Language`)로 조립합니다.**
회원 알림(`/notifications`)과 트레이너 알림(`/trainer/notifications`)이 같은 규칙입니다.

- **저장**: `notifications.template`(틀 코드)·`template_args`(JSON 인자)와 함께, `title`·`body` 에는
  예전과 **같은 한국어 문장**을 계속 적습니다 — 틀을 모르는 옛 앱과 푸시가 이 값을 씁니다.
  인자에는 언어와 무관한 값(이름·날짜·수량·건강 목표 저장 값)만 담습니다. 회원·트레이너가
  직접 쓴 글(메시지·반려 사유)은 번역하지 않고 저장된 `body` 를 그대로 씁니다.
- **응답의 `title`·`body`**: 요청 언어로 조립한 문장입니다. 한국어(헤더 없음 포함)는 저장된
  문장 **그대로**입니다 — 틀 문구를 나중에 다듬어도 받은 알림은 받은 순간의 문장으로 남습니다.
  틀이 없는 옛 알림, 서버가 모르는 틀, 인자가 깨진 틀도 저장된 문장입니다(오류가 아닙니다).
- **응답의 `template`·`args`**: 틀 코드와 인자(없으면 `null`). 트레이너 웹은 이 둘로 ARB 문장을
  직접 조립하고, 모르는 틀일 때만 `title`·`body` 를 씁니다. 회원 앱은 `title`·`body` 를 그대로
  그립니다.
- **`action.label`** 도 요청 언어입니다(저장하지 않고 응답마다 만드는 말). 예: `운동 보기` / `View workouts`.
- 틀 목록과 문장은 `app/services/notification_templates.py` 에 있습니다. 트레이너가 받는 틀
  (`trainer_*`)은 트레이너 웹 `trainer_notification_text.dart` 가 같은 코드를 읽습니다.
- 일정 등록·변경·취소·반복 등록, 포인트 쿠폰 만료 예고·취소, 주간 챌린지 결과도 틀로
  저장합니다. 일정 종류는 저장 값(`1:1 PT`·`상담`)을 영어로 옮기고, 트레이너가 직접 적은 종류는
  그대로 둡니다. 쿠폰 혜택 이름은 항목 id 로 영어를 고릅니다.
- **`time_ago`** 도 요청 언어입니다. 한국어는 예전 그대로(`방금 전`·`5분 전`·`3시간 전`·`2일 전`),
  영어는 `just now`·`5 min ago`·`1 hour ago`·`3 hours ago`·`1 day ago`·`2 days ago` 입니다.
  회원 앱은 두 모양을 모두 읽어 자기 로케일 문장으로 옮기고, 트레이너 웹은 받은 값을 그대로
  그립니다(요청 언어가 곧 화면 언어).

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
| `coach_chat` | 트레이너 메시지·피드백 | `coach_chat` |
| `coach_report` | **트레이너가 등록한 주간 리포트**(#2085) | `coach_chat` |
| `routine` | 루틴 배정 | `exercise` |
| `member_schedule` | 일정 등록 | 없음(회원 앱에 일정 화면이 없음, #1928) |
| `coach_invite` | 담당 요청 도착 — `invite_id`로 수락·거절 창 열기 | `exercise`(처리·취소 시 이동) |
| `consultation_result` | 담당 연결 — 연결됨·연결 해제 및 과거 담당 요청 | `exercise` |
| `consult_decision` | **내 상담 요청의 승인·거절·만료**(#2067) | `consultations`(내 상담 요청) |
| `health_goals` | 담당 트레이너의 건강 목표 변경 | `health_goals` |
| `benefits` | 쿠폰 취소·만료 임박 | `my_benefits` |
| `points_shop` | 주간 챌린지 결과 | `points_shop` |
| `system` | 공지 | 없음 |

`consult_decision` 은 #2067 에서 `consultation_result` 에서 떼어 냈습니다. 같은 갈래였을 때는 거절
알림을 눌러도 운동 탭으로 가서, 사유를 보려면 내 상담 요청을 따로 찾아가야 했습니다. 이미 저장된
옛 결과 알림은 `consultation_result` 그대로라 운동 탭으로 갑니다(백필하지 않음).

`coach_report` 는 #2085 에서 `coach_chat` 에서 떼어 냈습니다. 목적지는 같은 코치 대화이고, 회원 앱 알림함이 갈래로 아이콘을 고르기 때문에(#2084) 리포트는 문서, 메시지는 말풍선으로 보이게 나눴습니다. 이미 `coach_chat` 으로 저장된 옛 리포트 알림은 그대로 둡니다(백필하지 않음).

회원 앱은 갈래를 접지 않고 갈래마다 알림함 아이콘을 고릅니다(#2084). 보내는 곳이 없는 `health_check` 는 `reminder` 와 같게, 모르는 갈래는 `system` 과 같게 그립니다.

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
| GET | `/ai-coach/feedback` | `{ greeting, suggestions[{ tag, title, body }] }` — 식단·운동 두 건(#2706). 문장은 `Accept-Language` 로 한국어·영어(#2707) |
| GET | `/ai-coach/insights` | `{ window_days, insights[{ message_id, created_at, kind, body_part, text }] }` — 최근 30일 회원 메시지의 통증·부정적 반응 감지 |
| DELETE | `/ai-coach/insights/{message_id}` | `{ status }` — 그 줄의 감지를 기록에서 치움 |
| GET | `/ai-coach/messages` | `{ messages[] }` — 저장된 대화 복원(재접속·다른 기기). 코치 답변은 `points_spent`·`balance_after` 를 함께 싣는다 |
| GET | `/ai-coach/quota` | `{ free_limit, free_left, paid_limit, paid_left, cost, balance, next }` — 오늘 남은 대화(#2145) |
| POST | `/ai-coach/chat` | 입력 `{ message, history?, pay_with_points?, client_request_id? }` → `{ reply, sources, user_insight, points_spent, balance_after, quota }` |

tag: diet|exercise (피드백은 식단·운동 두 건, #2706)

**하루 대화 한도(#2145).** AI 챗봇(담당 트레이너가 없는 회원)은 KST 하루 **무료 10회**다. 다 쓰면 **한 번에 50P** 로 하루 **10회**까지
더 보낸다(세 값은 서버 설정 `coach_chat_free_per_day`·`coach_chat_paid_cost`·`coach_chat_paid_per_day`).

- `next` 는 다음 대화가 무엇으로 나가는가 — `free` · `paid` · `exhausted`.
- 무료를 넘겨 보내려면 `pay_with_points: true` 가 있어야 한다. 앱은 무료를 다 쓴 뒤 처음 한 번만 확인창을 띄운다.
- 거절은 `detail: { code, message }` 다. 동의 없음 402 `points_required`, 오늘 다 씀 429 `daily_limit`, 잔액 부족 409
  `insufficient_points`(+`shortfall`). 서버 전체 AI 상한에 걸리면 503 `ai_capacity` + `Retry-After`(#3032) — 무료 횟수·포인트를
  쓰지 않고 대화도 저장하지 않는다. 앱은 보낸 말을 거두고 입력칸에 되돌려 안내한다.
- **AI 가 답했을 때만 센다.** 검색 기반 대체 답은 무료 횟수도 포인트도 쓰지 않는다. 포인트로 산 답은 원장에 `ai_chat` 사용 줄로 남고,
  `points_spent`·`balance_after` 가 답변 아래 차감 표시(`−50P · 남은 포인트`)를 채운다. `GET /ai-coach/messages` 의 코치 답변도 같은
  두 값을 싣는다.
- 같은 `client_request_id` 재전송은 저장한 답을 그대로 돌려주고 다시 세지 않는다.

**요청 크기·빈도 한도(#1548, #1549).** 한도를 넘는 요청은 LLM 을 부르기 전에 거절하고, 대화 저장·하루 한도 차감도 하지 않는다.

| 한도 | 값 | 넘으면 |
| --- | --- | --- |
| `message` 길이 | 1000자 | **422** |
| `history` 턴 수 | 20 | **422** |
| `history[].content` 길이 | 2000자 (`role` 은 16자) | **422** |
| 요청 본문 전체 — 회원·트레이너 AI 코치 공용(트레이너는 #3032) | 256KiB (`COACH_CHAT_MAX_BODY_BYTES`) | **413** `{"detail": "요청이 너무 큽니다. …"}` — 본문을 다 읽기 전에 끊는다 |
| 분당 요청 수 — 회원 `POST /ai-coach/chat` | 20 / IP (`COACH_CHAT_PER_MINUTE`) | **429** `{"detail": "요청이 너무 많습니다. …"}` + `Retry-After: 60` |

길이는 글자(유니코드 코드 포인트) 수다. 회원 앱은 입력칸을 1000자로 막고, `history` 는 최근 20턴·턴당 2000자로 잘라 보낸다(서버는
저장된 대화를 먼저 쓰고 프롬프트에는 최근 몇 턴만 넣으므로 답이 달라지지 않는다). 분당 한도(429 `detail` 이 문자열)는 하루 한도의
429 `daily_limit`(`detail` 이 객체)와 모양으로 구분된다.

**생성 실패 로그(#1559).** LLM 대신 검색 기반 대체 답으로 내려갈 때마다 `app.services.coach.chat` 로거가 `event=coach_llm_fallback` 레코드를
남긴다. 필드는 `fallback_reason`(`llm_unavailable` 설정·키 문제 / `provider_error` 호출 실패 / `empty_reply` 빈 응답 — 셋은 WARNING,
`internal_error` 우리 코드 오류 — ERROR+스택)·`llm_provider`·`llm_model`·`error_type`·`http_status`·`user_id` 이고, 요청 상관관계는
`request_id` 로 잇는다. 예외 메시지·프롬프트·건강정보·질문은 남기지 않는다. 응답 계약은 그대로다.

`DELETE /ai-coach/insights/{message_id}` 는 **메시지를 지우지 않는다**(#1975). 감지는 저장하지 않고 대화에서 매번 계산하므로 지울 행이 없다 — 그 줄에 `더 보지 않음` 표시만 남기고 `GET` 이 건너뛴다. 회원이 쓴 말은 대화에 그대로 남고 AI 가 맥락으로 읽는 것도 그대로다. 이미 치운 줄을 다시 눌러도 200 이고, 남의 대화·없는 id 는 404 다.

감지(`GET /ai-coach/insights`·치우기·AI 코치 프롬프트의 불편 요약·자동 추천 루틴·트레이너 회원 목록의 통증 신호)는 **회원 본인 대화**(`ai_conversations.trainer_id IS NULL`)만 읽는다(#3085). 예전 트레이너 AI 코칭(`/trainer/clients/{member_id}/ai-coach`, 삭제됨)이 남긴 스레드의 트레이너 질문이 회원 발화로 읽히지 않게 하기 위해서다. 그 스레드의 메시지 id 로 치우기를 부르면 404 다.

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
  60초 TTL 캐시) 또는 **DB 장소**(키가 없을 때).
- **시드 폴백은 데모 서버에서만**(#2914): 데모 시드가 켜진 서버는 카카오 결과가 0건이거나
  호출이 실패하면 DB 시드 장소로 채운다. 실서버(데모 시드 꺼짐)는 0건이면 **빈 배열**,
  실패하면 **503** 을 돌려주고 시드 장소를 섞지 않는다. 키 없이 DB 장소를 읽을 때도
  실서버는 데모 시드 장소(가상 헬스장·데모 장소 id)를 뺀다.
- **무카테고리**: `category` 생략 시 네 카테고리를 **모두 검색·병합**하고 각 결과를 해당
  카테고리로 태깅한다(공급자 간 의미 일치, 빈 category 없음).
- **검증**: `lat`(-90~90)·`lng`(-180~180)·`category`(허용값)는 위반 시 **422**.

### 헬스장 (`fitness` 장소 + 프로필)

| Method | Path | 응답 |
|---|---|---|
| GET | `/gyms?lat=&lng=&partner_only=` | `[GymOut]` — 좌표를 주면 거리순, 없으면 이름순 |
| GET | `/gyms/{gym_id}` | 단건(없으면 404) |
| GET | `/gyms/{gym_id}/trainers` | 그 헬스장 소속 트레이너 |
| GET | `/me/gym?lat=&lng=` | 내 헬스장(`member_gyms`) — `GymOut`. 연결이 없으면 404 |

- **`lat`·`lng` 는 둘 다 주거나 둘 다 뺀다**(하나만 오면 422). 좌표가 없으면 `distance_km` 는
  `0` 이고 **뜻이 없는 값**이다 — 거리로 그리지 않는다. 회원 앱은 회원 위치를 얻었을 때만 `/me/gym` 에
  좌표를 싣는다. `/gyms` 는 검색 중심이 필요해 위치를 얻기 전에는 기본 검색 영역(신촌) 좌표를 보내고,
  그 거리는 화면에 그리지 않는다(#3044).
- **`is_partner` 는 표시 값이다.** `GymOut` 으로 내려가고 `partner_only=true` 로 목록을
  좁히는 기준이 된다(현재 두 앱은 이 값을 읽지 않는다). **접근 제어가 아니다** — 상담 대상 검증과
  트레이너 노출 경로(`/trainers`, `/trainers/recommended`, `/gyms/{id}/trainers`)는 이 값을
  보지 않고, 소속 장소가 `category='fitness'` 인 활성 트레이너인지로 판단한다. 따라서
  비제휴 헬스장의 트레이너에게도 상담을 걸 수 있다. (#1626)
- **`partner_only` 기본값은 `false`** 다. 지정하지 않으면 비제휴 헬스장(트레이너가 소속
  헬스장 찾기로 등록한 곳, 데모 서버에서는 가상 비제휴 헬스장 `app/db/seed_gyms.py`)도 함께
  온다 — 회원이 다니는 헬스장이 목록에 없으면 상담 자체를 시작할 수 없기 때문이다.

### 트레이너 디렉터리 (회원앱 탐색)

| Method | Path | 응답 |
|---|---|---|
| GET | `/trainers` | `[{ id, gym_id, name, role, reason, career, intro, certifications[] }]` |
| GET | `/trainers/recommended` | 같은 형태 — 홈·운동 탭 추천 레일 |
| GET | `/trainers/{trainer_id}` | 단건(없으면 404) |
| POST | `/trainers/{trainer_id}/reports` | 회원 신고(`RequireMember`) — 아래 [트레이너 신고와 계정 관리](#트레이너-신고와-계정-관리-3008) |

- **노출 조건**: 소속(`gym_id`)이 있고 그 장소가 `category='fitness'` 인 트레이너만. 상담 요청 시의 대상 검증과 같은 조건이라, 목록에 뜬 트레이너는 상담을 걸 수 있다. (#451)
- **데모 트레이너 제외**: 데모 시드가 꺼진 서버(`SEED_DEMO_DATA=false`, 운영은 항상)에서는 데모 시드 트레이너(`app/db/demo_ids.py`)가 목록·추천·상세(404)·헬스장별 목록에 나오지 않고, `POST /consultations` 도 대상 없음(404)으로 막는다. 예전 기본값으로 운영 DB 에 심긴 가상 트레이너를 정리 스크립트(`scripts/purge_demo_data.py`)로 지우기 전에도 노출되지 않게 하는 장치다. (#2811)
- **운영자 승인 없음**: 트레이너는 가입하고 소속을 고르면 바로 목록·추천·상세에 나오고 상담 대상이 된다. 소속은 트레이너가 카카오 장소에서 직접 고른 값이고, 헬스장은 트레이너를 묶는 단위일 뿐 확인을 거치지 않는다. 사칭·부적절한 메시지는 회원 신고와 운영자의 계정 정지로 다룬다. (#3008, 예전 승인 게이트 #2825 를 대체)
- **`/trainers/recommended` 순서**: 회원마다 다르다. 회원의 건강 목표(`conditions`, 옛 질환 이름은 새 목표로 읽는다)·가장 최근 상담의 `exercise_goal`·내 헬스장(`MemberGym`)을 신호로 점수를 매겨 내림차순 정렬한다. 동점은 경력 → id 로 갈라 같은 회원이 새로고침해도 순서가 흔들리지 않는다. (#500)
- **트레이너 화면의 회원 목표(`TrainerClientOut.goal`, `MemberCoachOut.goal`, 루틴 추천 분석의 `goal`)**: 회원 건강 목표(`conditions` 중 목표, 최대 2개)를 ` · ` 로 이은 값이다. 트레이너가 `PUT /trainer/clients/{id}/health-profile` 로 `conditions` 를 고치면 회원앱과 같은 칸이 바뀐다. 옛 질환 이름은 저장 때 정리하고, 목표가 아닌 글(건강상태·주의사항)은 남는다. 회원이 6자리 코드로 연결될 때(`POST /trainer/pairing-code`) 회원 목표가 비어 있으면 그 트레이너에게 수락된 가장 최근 상담의 `exercise_goal` 을 목표로 채운다(#1818). 상담 수락은 담당 연결이 아니라 채우지 않는다(#2584). 상담 운동 목표가 건강 목표 여덟 종과 1:1 이 되면서 `other` 를 뺀 모든 값이 빠짐없이 채워진다(#1992).
- **회원 건강 목표 숫자의 범위**: 회원 경로(`PUT /users/me/health-goals`·`POST /users/me/onboarding`)와 트레이너 경로(`PUT /trainer/clients/{id}/health-profile`)가 **같은 범위**를 쓴다 — 같은 컬럼을 고치는 문들이라 기준이 갈라지면 한쪽으로 들어온 값을 다른 쪽이 고칠 수 없다. 범위는 `app/schemas/health_goal_ranges.py` 한 곳에 있고, 어긋나면 422 다. `null` 은 그대로 목표 해제다. 자세한 사정은 [TRAINER_DOMAIN.md](docs/TRAINER_DOMAIN.md) 참조. (#1888)
- **실효 단백질 목표(`effective_daily_protein_g`, 주간 리포트는 `effective_protein_target`)**: 회원이 하루 단백질 목표를 정하지 않아도 채워지는 값이다 — 개인 목표 → 체중 × 1.2g → 60g(`diet_coach_inputs.effective_protein_g`). 식단 분석·기간/주간/전체 조언·추천 식단이 이 값으로 판단하므로 두 앱의 영양 카드·리포트 막대도 개인 목표가 없으면 이 값을 분모로 쓴다. `GET /users/me/profile`(`ProfileView`), `GET·PUT /trainer/clients/{id}/health-profile`(`MemberHealthProfileOut`), `WeeklyReportOut` 에 실린다. 개인 목표 필드(`daily_protein_g`·`protein_target`)는 그대로 null 을 유지해 '이 회원의 목표'와 기본값을 가른다. 예전에는 카드가 100g, 분석이 60g 을 써 같은 날을 서로 다르게 판단했다. (#2898)
- **건강 목표·주의사항을 마지막으로 바꾼 사람**: `GET /users/me/profile`·`PUT /users/me`·`PUT /users/me/health-goals`·`POST /users/me/onboarding` 응답(`ProfileView`)과 `GET/PUT /trainer/clients/{id}/health-profile` 응답에 `focus_changed_by`·`focus_changed_at`(목표 칩, #1832)과 `notes_changed_by`·`notes_changed_at`(건강상태·주의사항, #2942)이 따로 실린다. `*_by` 는 `member`|`trainer`, 바꾼 적이 없으면 둘 다 `null` 이다. 목표 칩 집합이나 주의사항 조각이 실제로 달라진 저장에만 남는다(순서만 바뀐 저장은 아니다). 트레이너가 주의사항만 고치면 기록만 남고 회원 알림은 없다.
- **신호가 없는 회원**(온보딩 전 등)은 운영자가 `recommend_reason` 을 적어 둔 트레이너만 **기존 순서 그대로** 받는다. 빈 목록을 주지 않는다.
- **`reason`**: 운영자가 쓴 `recommend_reason` 이 우선이고, 비어 있을 때만 점수 근거에서 만든 문구가 채워진다(예: `회원님이 다니는 헬스장 소속 · 체중 감량 지도 경험`).

### 예약 (회원 ↔ 트레이너 슬롯)

| Method | Path | 응답 |
|---|---|---|
| GET | `/trainers/{trainer_id}/slots` | `[{ id, trainer_id, starts_at, capacity, remaining, is_closed, overlapped }]` |
| POST | `/reservations` | 입력 `{ slot_id }` → `{ id, slot_id, schedule_id, status, created_at }` |
| GET | `/reservations/me` | `[{ id, slot_id, trainer_id, starts_at, cancellable }]` — 내 예약 (다가오는 것부터, 기본 50건·커서). 회원·트레이너가 취소한 예약은 빠진다(#2283) |
| DELETE | `/reservations/{id}` | 취소 → `{ status: "cancelled" }` |

- **예약은 트레이너 일정을 만듭니다.** 확정 시 `trainer_schedule` 에 `1:1 PT` 세션이 생기고, 취소하면 그 일정과 좌석이 함께 돌아갑니다. 회원 탈퇴 경로와 **같은 함수**(`reservation_service._release`)를 씁니다. (#502)
- **취소 마감**: 슬롯 시작 시각까지. 이미 시작한 수업은 **409** — 자리를 비우는 게 아니라 기록을 지우는 일이라 트레이너가 판단할 몫입니다.
- **남의 예약·없는 예약은 404** 로 같습니다. 존재 여부조차 드러내지 않습니다(상담 요청과 같은 규칙).
- `cancellable` 은 **서버 판단**입니다. 앱이 자기 시계로 다시 계산하면 시각이 어긋난 기기에서 버튼은 눌리는데 서버가 409 를 주는 상태가 됩니다.
- 취소는 트레이너에게 알림 행을 남깁니다(`notifications`). 트레이너는 `/trainer/notifications` 로 읽습니다(#503).
- **트레이너의 다른 일정과 시간이 겹치면 409** `detail = { code: "schedule_overlap", message }` 입니다.
  자리를 연 뒤 트레이너가 그 시간에 다른 일정을 잡은 경우입니다. 겹친 일정 목록은 싣지 않습니다(남의 일정).
  트레이너 쪽 일정·자리·상담 승인 경로의 같은 409 는 `conflicts[]` 를 함께 줍니다 — 규칙은
  [TRAINER_DOMAIN.md](docs/TRAINER_DOMAIN.md) "시간 겹침" 참조. (#2284)
- **목록 단계에서도 겹침을 알립니다** (#2761). 자리를 연 뒤 트레이너가 그 시간에 일정을 잡거나
  옮겨 왔으면, 슬롯 응답의 `overlapped` 가 `true` 입니다. 회원용 목록(`GET /trainers/{id}/slots`)은
  그 자리의 `remaining` 을 0 으로 접어 **마감**으로 보내고, 상담 신청 폼(`GET /consultations/slots`)은
  그 자리를 빼고 줍니다. 트레이너용 목록(`GET /trainer/reservation-slots`)은 좌석 수를 그대로 두고
  `overlapped` 만 실어 `일정과 겹침` 으로 그리게 합니다. 일정이 취소·이동되면 다음 조회에서 다시
  빈 자리입니다. 목록과 경쟁하는 예약은 위 409 가 계속 막습니다.

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

- **담당 트레이너가 있는 회원은 담당에게만** 상담을 낼 수 있습니다(#2611). 다른 트레이너에게
  내면 **409** `detail = { code: "linked_to_other_trainer", message }` 입니다. 트레이너를 바꾸려면
  `DELETE /me/coach/trainer` 로 담당 연결을 해제한 뒤 신청합니다. 이 판정은 대기 중복·한도보다
  먼저 합니다.
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
  그리고 여덟 중 어디에도 넣기 어려운 회원을 위한 `other` 입니다. 상담 뒤 회원이 그
  트레이너와 6자리 코드로 연결되면 여덟 목표는 회원 건강 목표(`HealthProfile.conditions`)가
  비어 있을 때 그대로 이어집니다(`health_focus.EXERCISE_GOAL_FOCUS`, #2584). `other` 는 무엇을 원하는지 알려주는 바가 없어
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
  일시**를 그리는 값입니다. 수락으로 상담 일정이 생겼으면 두 시각 값은 **그 일정의 날짜·시각·길이**
  입니다 — 트레이너가 일정을 옮기면 회원 카드도 옮긴 시각을 보여 줍니다(#2758). 수락 알림 본문에도 확정 일시가 들어갑니다. 연결 전 회원은
  `/me/coach/sessions` 가 빈 목록이라, 수락된 상담은 내 상담 요청에서 확인합니다(#2584).
- **상담 일정과 트레이너 스케줄** (#2584) — `GET /trainer/schedule` 은 담당이 끊긴 회원의 일정을
  `해제 회원` 으로 가리지만(#2589), 상담 요청으로 생긴 `상담` 일정(`consultation_id` 있음)은
  연결 여부와 관계없이 이름 그대로 보입니다(`member_detached=false`). 담당 해제 때 남은 일정을
  거둘 때도 이 상담은 거두지 않습니다. 이 일정은 연결 전에도 메모 수정·
  완료·재개가 됩니다(상담은 완료해도 운동 기록을 만들지 않습니다). 응답의 `consultation` 에
  `{ id, exercise_goal, health_purpose_type, health_purpose_detail, message }` 가 실려 카드가
  `상담 요청 내용` 을 읽기 전용으로 그립니다 — 회원 응답(`/me/coach/sessions`)에서는 늘 `null`
  입니다. 코드로 연결되면 같은 일정이 담당 회원 일정으로 그대로 이어집니다. 예전 수락이
  만든 일정은 `0105_schedule_consultation_link` 가 요청과 시각이 같은 것만 잇고, 완료되지 않은
  것의 종류를 `상담` 으로, 문의 글과 똑같은 메모를 빈 값으로 바꿉니다.
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
- **수락은 상담 일정 확정이지 담당 연결이 아닙니다** (#2584). 수락하면 회원이 고른 자리에
  `type="상담"`·`note=""`·`consultation_id`(그 요청) 인 일정이 하나 생기고, 담당 링크·헬스장
  연결(`MemberGym`)·회원 건강 목표는 바뀌지 않습니다. 응답의 `client_connected` 는 늘
  `false` 입니다. 등록은 상담 뒤 회원이 띄운 6자리 코드로 합니다(`POST /trainer/pairing-code`).
  다른 트레이너의 담당 회원이어도 수락은 막지 않습니다 — 담당을 옮길지는 코드 연결이 정합니다
  (다른 트레이너가 담당 중이면 코드 연결이 409).
- 상담 신청의 `data_sharing_consent` 는 **상담 신청 정보(이름·운동 목표·문의 내용)를 그
  트레이너에게 전달하는 동의**입니다. 담당 링크로 옮겨 적지 않습니다 — 식단·운동 기록 공유
  동의는 연결 코드를 받을 때 받습니다(`POST /users/me/pairing-code`, 발급 시각이 동의 시각).
- **수락은 시각을 받지 않습니다.** `POST /trainer/consultations/{id}/accept` 본문은 `note`
  하나뿐이고, 날짜·시각·소요 시간은 회원이 고른 자리가 정합니다(종류는 늘 `상담`). 회원이
  고른 자리가 사라진 뒤 수락하면 **409** 입니다.
- 자리를 연 뒤 트레이너가 그 시간에 다른 일정을 잡았으면 승인은 **409**
  `detail = { code: "schedule_overlap", message, conflicts[] }` 이고 아무것도 바뀌지 않습니다
  (요청은 대기로 남습니다). 일정을 옮긴 뒤 다시 승인합니다. (#2284)
- **상담 일정을 거두면 요청도 정리됩니다** (#2758). 수락으로 생긴 상담 일정을 트레이너가
  취소(`POST /trainer/schedule/{id}/cancel`)하거나 아직 진행 전에 삭제하면, 같은 트랜잭션에서
  요청이 `cancelled`(처리자 = 그 트레이너)가 되고 신청 때 잠근 자리가 다시 열립니다. 회원
  응답의 `cancelled_by_trainer` 가 `true` 라 회원 취소와 구분됩니다(처리자 id 는 여전히 싣지
  않습니다). 회원 알림은 일정 취소·삭제의 기존 취소 알림입니다. 상담 일정을 다른 날짜·시각으로
  옮기면 요청은 `accepted` 그대로이고, 옛 자리는 풀려 요청의 `slot_id` 가 비며 시각은 일정을
  따릅니다. 트레이너 자리 목록의 `booked_by_name` 은 상담 신청(대기·수락)이 잡은 자리에도
  그 회원 이름을 싣습니다.

### 트레이너 알림함

| Method | Path | 응답 |
|---|---|---|
| GET | `/trainer/notifications` | `[{ id, title, body, category, read, created_at, time_ago, subject_id, target_date, template, args }]` (최신순, 한 쪽 기본 100건 — 아래 [쪽 나눔](#트레이너-알림함-쪽-나눔-2293)) |
| GET | `/trainer/notifications/unread-count` | `{ unread(int) }` |
| POST | `/trainer/notifications/{id}/read` | `{ id, read: true }` |
| POST | `/trainer/notifications/read-all` | `{ marked_read(int) }` |

- **회원용 `/notifications` 를 재사용하지 않습니다.** `get_current_user` 가 트레이너 계정을 **403** 으로 막는 회원 전용 경로입니다(역할 분리). 저장되는 행은 같은 `notifications` 테이블이고 `user_id` 가 일반 사용자 FK라 스키마 변경은 없습니다. (#503)
- `category` 는 트레이너 전용 값입니다 — `message`|`consultation`|`reservation`|`health_goal`|`member_name`|`member_left`|`invite_accepted`|`invite_rejected`|`consult_withdrawn`|`weekly_feedback`. 회원 알림의 집합(`reminder|health_check|achievement|system`)과 겹치지 않습니다. 한 테이블을 공유하지만 읽는 화면과 이동할 곳이 다릅니다. `health_goal`·`member_name` 은 `subject_id` 에 그 회원 id 를 실어 회원 상세로 갑니다. `health_goal` 중 틀이 `trainer_health_notes` 인 알림(회원이 건강상태·주의사항을 고침, 인자 `member_name`·`with_focus`)은 글을 싣지 않고, 앱은 회원 상세에서 신체·목표 창의 `건강 목표` 탭을 바로 엽니다. (#2619) `member_left` 는 담당 회원이 탈퇴(`DELETE /users/me`)했거나 담당 연결을 끊었을 때(`DELETE /me/coach`, `DELETE /me/coach/trainer`) 남고, 회원이 이미 목록에서 빠져 `subject_id` 없이 확인만 합니다. (#2174) `consult_withdrawn` 은 회원이 탈퇴(`DELETE /users/me`)하면서 대기 중(`pending`)이던 상담 요청이 함께 사라졌을 때 그 요청을 받은 트레이너에게 남습니다 — 틀 `trainer_consult_withdrawn`, 인자 `member_name`(탈퇴 직전 이름)·`preferred_date`, `target_date` 는 희망 날짜입니다. 처리된 요청과 만료 시각이 지난 요청은 알리지 않고, 담당 트레이너는 `member_left` 만 받습니다. 떠난 회원을 가리키지 않도록 `subject_id` 는 없고 앱은 상담 요청함으로 갑니다. (#1632)
- **회원 주간 피드백(#3026)**: 회원이 `PUT /me/coach/weekly-feedback` 로 그 주 답을 내면 담당 트레이너에게
  `weekly_feedback` 알림 — 틀 `trainer_member_weekly_feedback`, 인자 `member_name`·`condition`·`intensity`(저장 값)·
  `pain`(통증 유무)·`revised`(고쳐 낸 답), `subject_id` = 회원, `target_date` = 그 주 월요일. 통증이 있으면 제목이
  "{회원} 회원이 통증을 알렸어요"로 바뀝니다. 아픈 곳(회원이 쓴 글)은 알림에 싣지 않습니다(`trainer_health_notes` 와 같은
  이유, #2619). 같은 주에 다시 내면 트레이너가 **아직 읽지 않은** 그 주 알림을 최신 답으로 고쳐 맨 위로 올리고(건수 그대로),
  이미 읽었으면 `revised: true` 알림을 한 건 더 만듭니다. 앱은 그 회원 상세의 메모 창을 '피드백' 탭으로 엽니다. 수신 설정
  스위치는 아직 없습니다(종류별 설정은 #2420).
- **이동 목적지(#2292)**: `reservation` 은 `subject_id`(예약한 회원)와 `target_date`(수업 날짜, KST `YYYY-MM-DD`)를 실어 그 날짜의 스케줄로, `consultation` 은 `subject_id`(신청 회원)와 `target_date`(희망 날짜)를 실어 상담 요청함으로 갑니다. 담당 요청의 결과는 상담이 아니라 별도 종류입니다 — `invite_accepted` 는 `subject_id` 의 새 담당 회원 상세로, `invite_rejected` 는 고객 목록으로 갑니다. 대상이 기록되기 전의 옛 알림은 `subject_id`·`target_date` 가 `null` 이고 앱이 전처럼 오늘 스케줄로 보냅니다.
- **생성 지점**: 회원의 새 메시지(`POST /me/coach/chat`, 사진은 `POST /me/coach/chat/image` — #1665), 새 상담 요청(`POST /consultations` — 지정된 트레이너 한 사람), 새 예약·예약 취소, 담당 회원의 건강 목표 변경(#1832)·건강상태·주의사항 변경(#2619), 담당 회원의 이름 변경(`PUT /users/me`·`POST /users/me/onboarding`, #2065).
- **언어**: 제목·본문은 요청 언어로 조립합니다. 트레이너 웹은 `template`·`args` 로 ARB 문장을 직접 조립합니다 — 규칙은 위 [알림 문장의 언어](#알림-문장의-언어-2302) 와 같습니다. (#2302)
- **이름은 알림을 만든 순간의 것입니다.** 제목·본문을 완성된 글자로 저장하므로, 이름을 바꿔도 이미 받은 알림은 그때 이름으로 남고 바꾼 뒤의 알림부터 새 이름을 씁니다(받은 순간의 기록이라 고쳐 쓰지 않습니다). 대신 담당 회원이 이름을 바꾸면 트레이너에게 `member_name` 알림(`{옛 이름} 회원이 이름을 바꿨어요: {새 이름}`)을 한 번 보내 옛 이름과 새 이름을 잇습니다. 트레이너는 아직 이름을 바꿀 길이 없고(`PUT /trainer/me` 는 이름을 받지 않음), 그 길을 열 때 담당 회원에게 같은 알림을 보냅니다. (#2065)
- **수신 설정**: 메시지 알림만 `trainer_profiles.notify_new_message` 로 끌 수 있습니다. 상담 요청·예약은 끄는 스위치가 설정 화면에 없고, 놓쳐도 되는 종류가 아니라 항상 남깁니다.
- 남의 알림 읽음 처리는 **404** 입니다.

#### 트레이너 알림함 쪽 나눔 (#2293)

`GET /trainer/notifications` 는 **한 쪽**만 돌려줍니다. 파라미터 없이 부르면 전처럼 최신 100건이고,
본문은 그대로 배열입니다. 전에는 100건에서 끊기고 커서가 없어, 미읽음 배지는 전체를 세는데
그보다 오래된 미읽음은 목록 어디에서도 볼 수 없었습니다.

| 파라미터 | 기본 | 설명 |
|---|---|---|
| `limit` | 100 | 1~100. 범위를 벗어나면 **422** |
| `before` | — | 다음 쪽 커서(ISO datetime). 받은 `X-Next-Before` 헤더 값을 그대로 넘깁니다. 파싱 실패는 **422** |
| `before_id` | — | 복합 커서 tie-break. 받은 `X-Next-Before-Id` 헤더 값. `before` 없이 오면 **422** |

| 응답 헤더 | 설명 |
|---|---|
| `X-Next-Before` | 다음 쪽이 있을 때만. 이 쪽 마지막 알림의 `created_at`(UTC ISO) |
| `X-Next-Before-Id` | 다음 쪽이 있을 때만. 이 쪽 마지막 알림의 `id` |

- **두 헤더가 없으면 마지막 쪽입니다.** 서버가 한 건 더 읽어 보고 판단하므로, 마지막 쪽이 정확히
  `limit` 건이어도 빈 쪽을 한 번 더 부를 필요가 없습니다.
- 정렬은 `(created_at, id)` 내림차순이고 커서도 이 쌍입니다. 훅 하나가 여러 알림을 한 트랜잭션에
  넣어 같은 `created_at` 이 실제로 나오므로, 시각만으로 자르면 쪽 경계에서 알림이 빠지거나 겹칩니다.
  `before` 만 보내면 그 시각보다 이전만 받습니다(회원 알림 `/notifications` 와 같은 규칙).
- 오프셋 없는 `before` 는 UTC 로 읽습니다.
- 브라우저가 두 헤더를 읽을 수 있게 CORS `Access-Control-Expose-Headers` 에 올려 둡니다.
- **미읽음 배지(`/trainer/notifications/unread-count`)와 모두 읽음(`/trainer/notifications/read-all`)은
  쪽 나눔과 무관합니다** — 이 트레이너의 알림 전체를 세고 바꿉니다.
- 다른 쪽의 알림도 필드(`template`·`args`·`target_date`·`subject_id`)와 언어(`Accept-Language`)가
  첫 쪽과 같습니다.

### 트레이너 도메인 / 회원측 코치 미러

트레이너 웹 백엔드(`/v1/trainer/*`)와 회원측 "내 담당 코치" 미러(`/v1/me/coach/*`),
그리고 트레이너↔회원 **실데이터 공유** 설계는 별도 문서로 분리했다:
**[`docs/TRAINER_DOMAIN.md`](docs/TRAINER_DOMAIN.md)**.

핵심: `users.role`(member|trainer)로 두 앱 계정을 구분하되, 트레이너가 담당하는 회원은
실제 회원 User이고 트레이너 API는 회원의 실제 `diet_entries`·`routine_history`를 그대로
읽어 집계한다.

#### 경로 색인

아래 두 표는 **어떤 경로가 있는지**의 목록이다. 응답 필드의 뜻과 규칙(동의·해제·노쇼·리포트 주 경계 등)은
[`docs/TRAINER_DOMAIN.md`](docs/TRAINER_DOMAIN.md) 와 이 절의 뒤 문단이 기준이고, 여기서 다시 쓰지 않는다.
공통 규칙:

- `/trainer/*` 는 트레이너 계정만(회원 토큰 403), `/me/coach/*` 의 회원 동작(루틴 완료·취소, 요청 수락·거절)은 회원 계정만 받는다.
- **담당이 아닌 회원·남의 id 는 404** 다 — 있는지 없는지를 알려 주지 않는다. 담당을 해제했거나 동의를 철회한
  회원도 같은 404 다(#1631).
- 일정이 겹치면 409 `schedule_overlap`(+`conflicts`) — 모양은 위 "공통 규약" 의 객체 `detail` 표.
- 같은 동작을 두 번 보내도 한 번만 반영되는 쓰기는 `client_request_id` 를 받는다.

**회원측 코치 미러 (`/me/coach/*`)**

| Method | Path | 요청 → 응답 |
|---|---|---|
| GET | `/me/coach` | `{ trainer_id, name, specialty, career, intro, gym, goal }` — 내 담당 트레이너 요약. 없으면 404 |
| DELETE | `/me/coach` | 204 — 헬스장과 담당을 함께 해제(MY 탭 헬스장 휴지통). 이미 없어도 204. 트레이너에게 알리고 데이터 공유 동의를 철회한다(#444, #2174, #1631) |
| DELETE | `/me/coach/trainer` | 204 — 담당 트레이너만 해제, 헬스장 연결은 남는다. 위와 같이 멱등·동의 철회 |
| GET | `/me/coach/routines?date=` | `RoutineOut[]` — 그날 걸린 추천 개인운동과 그날 완료(#2161). 날짜 형식이 깨지면 422 |
| POST | `/me/coach/routines/{routine_id}/complete` | `{ minutes?, duration_seconds?, sets?, reps?, weight?, hold_seconds?, intensity? }` → `RoutineCompleteOut`(루틴 + 남긴 운동 기록·포인트). 없는 루틴 404 |
| DELETE | `/me/coach/routines/{routine_id}/complete` | `RoutineOut` — 완료 표시를 되돌리고 그 완료로 남은 운동 기록을 지운다(#1131) |
| DELETE | `/me/coach/routines/{routine_id}` | 204 — 내 개인운동 취소. **담당 트레이너가 있으면 403**(취소는 트레이너의 일), 없는 루틴 404 (#1020) |
| GET | `/me/coach/sessions` | `ScheduleSessionOut[]` — 담당 트레이너 일정 중 나와 매칭된 것, 최신순(완료 회차 `session_number`) |
| GET | `/me/coach/chat?limit=&before=&before_id=` | `ChatMessageOut[]`(오래된→최신, `sender` 는 `me`\|`trainer`). 담당이 없으면 404 |
| POST | `/me/coach/chat` | `{ text, emote_id?, client_request_id? }` → **201** `ChatMessageOut`. 빈 메시지 400, 이모티콘 규칙은 위 "채팅 이모티콘" |
| GET | `/me/coach/chat/unread` | `{ unread }` — 트레이너가 보낸 안 읽은 메시지 수 |
| POST | `/me/coach/chat/read` | `{ marked_read }` — 트레이너 메시지를 읽음 처리 |
| GET | `/me/coach/invites` | `[{ id, trainer_id, trainer_name, gym_name, message, status, created_at }]` — 나에게 온 대기 중인 담당 요청 |
| POST | `/me/coach/invites/{invite_id}/accept` | `{ data_sharing_consent: true }` → 같은 모양. 동의가 없으면 400, 없는 요청 404, 이미 결정했거나 다른 담당이 있으면 409. 담당 링크가 여기서 생긴다(#1022) |
| POST | `/me/coach/invites/{invite_id}/reject` | 같은 모양. 없는 요청 404, 이미 결정한 요청 409 |

**트레이너 웹 (`/trainer/*`)** — 이 절 위아래 문단과 앞 절(예약 슬롯·상담·알림함)에 따로 적은 경로는 빠져 있다.

| Method | Path | 요청 → 응답 |
|---|---|---|
| GET | `/trainer/me` | `TrainerMe` `{ id, name, email, phone, specialty, career, intro, certifications, gym, is_admin, has_password }` — `is_admin` 은 운영자 계정인지(#3008), `has_password` 는 비밀번호 로그인 계정인지(#3039) |
| PUT | `/trainer/me` | 부분 수정 `{ phone?, specialty?, career_years?, intro?, certifications?, gym_name?, gym_address?, gym_hours?, gym_phone? }` → `TrainerMe`. 이름·이메일은 바꾸지 않는다 |
| DELETE | `/trainer/me` | 본문 `{ reasons?, current_password? \| social_provider?·social_token? }` → `{ status: "deleted" }` — 탈퇴. 본인 확인 필수(#3039). 담당 회원에게 알린 뒤 계정과 딸린 데이터를 지운다(#505) |
| DELETE | `/trainer/me/gym` | `TrainerMe` — 소속 해제. 원래 없어도 200 |
| POST | `/trainer/me/password` | `{ current_password, new_password }` → `{ access_token, refresh_token, token_type, status }`. 아래 "비밀번호 변경과 토큰 세대" |
| GET | `/trainer/me/settings` | `{ notify_new_message, notify_session_reminder, reminder_lead_minutes }` — 기본값은 서버가 정한다 |
| PUT | `/trainer/me/settings` | 위 키 중 보낸 것만 → 같은 모양. 바꿀 칸이 하나도 없으면 400 |
| GET | `/trainer/clients?limit=&after_id=` | `TrainerClientOut[]` — 담당 고객 로스터 한 쪽(`after_id` 커서, 위 "공통 규약") |
| DELETE | `/trainer/clients/{member_id}` | 204 — 담당 관계만 해제. 회원 계정과 기록은 남는다 |
| PUT | `/trainer/clients/{member_id}/registration` | 204 — 미등록으로 남은 고객을 다시 담당으로. 다른 트레이너가 담당 중이면 409 |
| PUT | `/trainer/clients/{member_id}/status` | `{ active }` → `{ member_id, active }` — 활성·휴면 전환(#707) |
| GET | `/trainer/clients/{member_id}/health-profile` | `MemberHealthProfileOut` — 키·체중·성별·건강 목표(회원 `ProfileView` 의 목표 칸과 같은 이름) |
| PUT | `/trainer/clients/{member_id}/health-profile` | 같은 칸 부분 수정 → 같은 모양 |
| GET | `/trainer/clients/{member_id}/diet?date=` | `ClientDietEntryOut[]` — 그날 끼니(회원이 기록한 실데이터). 날짜 형식 422 |
| GET | `/trainer/clients/{member_id}/diet/days?from=&to=` | 회원 `GET /diet/days` 와 같은 모양·규칙 |
| GET | `/trainer/clients/{member_id}/diet/photos/{photo_id}` | 담당 고객의 끼니 사진. 남의 회원·남의 사진 404 (#699) |
| GET | `/trainer/clients/{member_id}/diet-advice?period=` | 회원 `GET /diet/advice` 모양 + `sentences` — 원인까지 짚는 서술형 식단 분석(#2379) |
| GET | `/trainer/clients/{member_id}/diet-recommendations` | `{ needs, basis_days, pick, candidates }` — 추천할 AI 식단 후보와 지금 확정한 추천(#2378) |
| PUT | `/trainer/clients/{member_id}/diet-recommendations` | `{ slot, name }` → 같은 모양. 회원 홈 `추천 식단` 첫 장(`trainer_pick`)이 된다 |
| GET | `/trainer/clients/{member_id}/exercise/weeks?from=&to=` | 회원 `GET /exercise/weeks` 와 같은 모양·규칙 |
| GET | `/trainer/clients/{member_id}/exercise-week?week_start=` | 회원 `GET /exercise/weeks/current` 모양의 한 주. `week_start` 형식이 깨지면 422 |
| GET | `/trainer/clients/{member_id}/exercise-advice?period=` | 회원 `GET /exercise/advice` 와 같은 문장(#1025) |
| GET | `/trainer/clients/{member_id}/records/span` | `{ diet_first_date, exercise_first_date }` — 회원 `GET /me/records/span` 과 같다 |
| GET | `/trainer/clients/{member_id}/history` | `RoutineHistoryOut[]` — 운동 완료 기록(최신순). 다른 트레이너의 기록·메모는 뺀다 |
| GET | `/trainer/clients/{member_id}/feedbacks` | `ClientFeedbackOut[]` — 그 회원과 주고받은 피드백 모아 보기(최신 먼저, 최근 90일). 완료 PT 피드백·보낸 주간 리포트·회원 주간 피드백. 읽기 전용, 해제·비담당 회원 404 (#2615) |
| GET | `/trainer/chat/unread` | `{ "<member_id>": 안 읽은 수 }` — 로스터 배지용 |
| GET | `/trainer/clients/{member_id}/chat?limit=&before=&before_id=` | `ChatMessageOut[]`(오래된→최신, 기본 최신 50건) |
| POST | `/trainer/clients/{member_id}/chat` | `{ text, emote_id?, client_request_id? }` → **201** `ChatMessageOut`. 빈 메시지·모르는 이모티콘 400 |
| POST | `/trainer/clients/{member_id}/chat/read` | `{ marked_read }` |
| GET | `/trainer/clients/{member_id}/memos` | `TrainerMemoOut[]`(최신 먼저) — 트레이너 혼자 보는 메모 |
| POST | `/trainer/clients/{member_id}/memos` | `{ body, source?, insight_id?, insight_kind?, ref_id?, ref_date?, ref_kind? }` → **201** `TrainerMemoOut`. `exercise_memo` 를 `ref_date` 로 남기면 `ref_kind`(`personal`·`member_log`) 상자, 없으면 그날 전체(`day`)에 다는 메모(#2508) |
| PUT | `/trainer/clients/{member_id}/memos/{memo_id}` | `{ body }` → `TrainerMemoOut` |
| DELETE | `/trainer/clients/{member_id}/memos/{memo_id}` | `{ status: "deleted" }` |
| GET | `/trainer/clients/{member_id}/follow-ups?include_completed=` | `TrainerFollowUpTaskOut[]`(예정일 순) |
| POST | `/trainer/clients/{member_id}/follow-ups` | `{ title, due_date, context_type?, client_request_id? }` → **201** `TrainerFollowUpTaskOut` |
| GET | `/trainer/follow-ups?scope=` | 내 할 일 전체(예정일 순, 지난 항목이 앞) |
| PUT | `/trainer/follow-ups/{task_id}` | `{ title?, due_date? }` → `TrainerFollowUpTaskOut` |
| POST | `/trainer/follow-ups/{task_id}/complete` | `TrainerFollowUpTaskOut` — 반복해도 성공, 완료 시각 유지 |
| GET | `/trainer/dashboard/task-progress` | `{ first_saved_date, days[] }` — 대시보드 오늘 할 일 진행 상태(#1633) |
| PUT | `/trainer/dashboard/task-progress/{day}` | `{ total, completed_today, completed_carried_over, pending_keys, dismissed_keys, completed_keys }` → 그날 한 칸. KST 오늘·어제만 받는다 |
| POST | `/trainer/dashboard/task-progress/{day}/keys` | `TrainerTaskKeyChange` → 반영 뒤의 그날 한 칸. 할 일 키 하나만 체크·해제·삭제해 다른 탭·기기의 변경을 덮지 않는다. KST 오늘·어제만, 그 밖은 422 (#2886) |
| GET | `/trainer/clients/{member_id}/routines` | `RoutineOut[]` — 배정한 루틴 |
| POST | `/trainer/clients/{member_id}/routines` | `RoutineAssignRequest` → **201** `RoutineOut` — 루틴 배정. 이름 없음 400 |
| PUT | `/trainer/clients/{member_id}/routines/{routine_id}` | `{ name?, minutes?, duration_seconds?, type?, reason? }` → `RoutineOut`(#504, #2547) |
| DELETE | `/trainer/clients/{member_id}/routines/{routine_id}` | `{ status: "deleted" }` — 철회, 회원 앱에서도 사라진다 |
| GET | `/trainer/clients/{member_id}/routines/unsent` | `RoutineOut[]` — PT 에 붙여 두고 아직 보내지 않은 개인운동(#2225) |
| GET | `/trainer/clients/{member_id}/routine-days` | `?from=&to=` → 날짜별 개인운동 이행(#2508) — 날마다 그날 걸린 배정과 결과(done/late/missed/pending), 배정 묶음. from 을 비우면 처음 걸린 날부터, 최대 371일. 담당 해제 회원 404 |
| GET | `/trainer/clients/{member_id}/deliveries/latest` | 가장 최근에 보낸 묶음 하나 또는 `null` (#2225) |
| GET | `/trainer/clients/{member_id}/routine-suggestions` | `RoutineOut[]` — 검토를 기다리는 AI 개인운동 제안 |
| POST | `/trainer/clients/{member_id}/routine-suggestions` | 후보 `{ name, minutes\|duration_seconds, type, …, evidence?, client_request_id? }` → **201** `RoutineOut`. 회원에게는 아직 안 보인다 |
| POST | `/trainer/routine-suggestions/{suggestion_id}/approve` | 고칠 칸만 → `RoutineOut` — 승인해 배정. 빈 이름 400, 없음 404, 이미 처리 409 |
| POST | `/trainer/routine-suggestions/{suggestion_id}/dismiss` | `RoutineOut` — 추천하지 않음. 없음 404, 이미 처리 409 |
| POST | `/trainer/clients/{member_id}/routine-options` | `{ available_minutes, intensity_preference, trainer_note?, sources? }` → `{ analysis, plan_a, plan_b, generated_by }` — AI 루틴 A/B 후보. 분당 한도 `ROUTINE_OPTIONS_PER_MINUTE`, 트레이너 하루 상한 429 `daily_limit`(서버 전체 상한은 규칙형 후보로 폴백, #3032) |
| POST | `/trainer/clients/{member_id}/program` | `{ name, sessions[], client_request_id?, delivery_kind?, trainer_message?, start_date?, active_days?, suggestion_ids? }` → **201** `RoutineOut[]` — 다중 세션 프로그램 배정(#709) |
| POST | `/trainer/clients/{member_id}/program-schedule` | 프로그램 + 날짜·시각(또는 붙일 `session_id`) → **201** `{ routines, session, attached_to_existing, personal_routines }` — 배정과 PT 일정 등록을 한 트랜잭션으로(#1580). 붙일 일정이 모호하면 409 `{ message, candidates }` |
| GET | `/trainer/programs?member_id=` | `[{ id, name, goal, period, session_count, exercise_count, member_id, updated_at }]` — 프로그램 초안 목록. `member_id` 를 주면 그 회원에게 자동 보관한 것만(#2873) |
| POST | `/trainer/programs` | `{ name, goal?, period?, memo?, sessions[], member_id?, workspace? }` → **201** 초안. `member_id` 는 코칭 화면의 회원별 자동 보관이며 담당 회원이 아니면 404, `workspace` 는 편집기 밖의 작성 상태 객체(JSON 64,000자 이하, 서버는 해석하지 않음)(#2873) |
| GET | `/trainer/programs/{draft_id}` | 초안 상세(편집기로 불러올 때). `member_id`·`workspace` 포함 |
| PUT | `/trainer/programs/{draft_id}` | 부분 수정, `sessions`·`workspace` 는 통째로 교체. `member_id` 는 바꾸지 않는다 |
| DELETE | `/trainer/programs/{draft_id}` | `{ status: "deleted" }` — 이미 배정한 루틴·일정은 남는다 |
| GET | `/trainer/program-templates` | `[{ id, name, goal, exercises, updated_at }]` — 내 템플릿(없으면 시작 구성) |
| POST | `/trainer/program-templates` | `{ name, goal?, exercises }` → **201**. 개수 상한을 넘으면 409 |
| PUT | `/trainer/program-templates/{template_id}` | 부분 수정. 없음 404 |
| DELETE | `/trainer/program-templates/{template_id}` | `{ status: "deleted" }`. 없음 404 |
| GET | `/trainer/schedule?date=&from=&to=&member_id=` | `ScheduleSessionOut[]` — 기본 하루, `from`/`to` 면 그 구간 |
| GET | `/trainer/schedule/booked-dates` | `["YYYY-MM-DD", …]` — 주간 스트립 점 표시용 |
| POST | `/trainer/schedule` | `{ date, time, client_name?, member_id?, type, duration_minutes, note?, program?, client_request_id? }` → **201** `ScheduleSessionOut`(예정). 겹치면 409 |
| POST | `/trainer/schedule/recurring/preview` | 반복 설정(`weekdays`, `count` 또는 `until`, `client_request_id?`) → `{ dates, conflicts, already_created }` (#870). 만들기와 같은 `client_request_id` 의 시리즈가 이미 있으면 그 회차는 `conflicts` 에서 빠지고 `already_created: true` — 응답만 잃은 재시도는 같은 키로 만들기를 다시 불러 그 회차를 받는다(#3102) |
| POST | `/trainer/schedule/recurring` | 같은 입력 → **201** `ScheduleSessionOut[]`. 겹치면 409 |
| PUT | `/trainer/schedule/{session_id}` | 보낸 칸만 수정 → `ScheduleSessionOut`. 겹치면 409 |
| DELETE | `/trainer/schedule/{session_id}` | `{ status: "deleted" }` — 잘못 만든 일정을 없앤다(취소와 다르다) |
| POST | `/trainer/schedule/{session_id}/complete` | `{ note? }` → 예정→완료. 매칭된 회원이 있으면 운동 기록으로 남긴다 |
| POST | `/trainer/schedule/{session_id}/cancel` | `{ source, reason? }` → 예정→취소, 기록으로 남는다(#871) |
| POST | `/trainer/schedule/{session_id}/no-show` | 예정→노쇼(#871) |
| POST | `/trainer/schedule/{session_id}/reopen` | `{ date, time, duration_minutes? }` → 완료를 앞날의 예정으로 되돌린다(#1396). 겹치면 409 |
| POST | `/trainer/schedule/{session_id}/program/send` | `{ client_request_id? }` → `ScheduleSessionOut` — 완료한 수업의 프로그램을 회원에게 보낸다(#822). 같은 세션은 한 번만 배정 |
| GET | `/trainer/schedule/{session_id}/routines` | `RoutineOut[]` — 그 PT 에 붙은, 아직 회원에게 가지 않은 개인운동(#2223) |
| PUT | `/trainer/schedule/{session_id}/routines` | `{ personal_routines, suggestion_ids? }` → `RoutineOut[]` — 붙은 개인운동을 통째로 교체 |
| POST | `/trainer/schedule/{session_id}/routines/send` | `{ personal_routines? }` → `RoutineOut[]` — 마무리된 PT 에 남은 개인운동을 보낸다(#2224). 상태가 맞지 않으면 400 |
| POST | `/trainer/schedule/{session_id}/routines/dismiss` | `{ dismissed }` — 보내지 않기로 정리(#2224) |
| GET | `/trainer/clients/{member_id}/report?week_start=` | `WeeklyReportOut` — 주간 리포트. 아무 요일을 줘도 그 주 월요일로 접는다 |
| GET | `/trainer/clients/{member_id}/report/summary?week_start=` | `{ member_id, week_start, headline, points, generated_by }` — `headline` 은 한 문장이다. AI 가 쓴 문장이 200자를 넘으면 계약 위반으로 보고 규칙 기반 요약(`generated_by: "rule"`)으로 바꾼다. 응답 상한은 400자(#3090). AI 로 만들 때 트레이너 하루 상한 429 `daily_limit`(서버 전체 상한은 규칙형 요약으로 폴백, #3032). |
| GET | `/trainer/clients/{member_id}/report/feedback?week_start=` | `{ member_id, week_start, body, updated_at }` — 저장해 둔 피드백 초안. 없으면 빈 본문(오류 아님, #821) |
| PUT | `/trainer/clients/{member_id}/report/feedback` | `{ week_start?, body }` → 같은 모양. 같은 주는 덮어쓰고, 회원에게는 아무것도 보내지 않는다 |
| POST | `/trainer/clients/{member_id}/report/send` | `{ week_start?, message? }` → **201** `ChatMessageOut` — 리포트를 회원 채팅으로 보낸다 |
| POST | `/trainer/pairing-code/preview` | `{ code }` → `{ member_id, name, gender, age, goal }` — 연결하지 않고 보여 준다(#1634) |
| POST | `/trainer/pairing-code` | `{ code }` → 같은 모양 — 6자리 코드로 담당 관계를 바로 만든다 |
| GET | `/trainer/client-invites?status=` | `TrainerClientInviteOut[]` — 보낸 담당 요청. `status` 는 `pending`(기본)\|`all` |
| POST | `/trainer/client-invites` | `{ member_id, message? }` → **201** `TrainerClientInviteOut`. 없는 회원 404, 회원 계정이 아니면 422, 이미 담당 중이거나 대기 요청이 있으면 409 |
| DELETE | `/trainer/client-invites/{invite_id}` | `{ status: "cancelled" }` — 보낸 요청을 거둔다. 없음 404, 이미 결정됨 409 |
| GET | `/trainer/consultations?status=&limit=&before=&before_id=` | `TrainerConsultationOut[]` — 나를 지정한 상담 요청 한 쪽(기본 미처리, 최신 50건, #980) |
| GET | `/trainer/consultations/pending-count` | `{ count }` — 인박스 배지(쪽 나눔과 무관한 전체 기준) |
| POST | `/trainer/consultations/{consultation_id}/accept` | `{ note? }` → `TrainerConsultationOut` + `{ client_connected, schedule_created, schedule_id }` — 수락하고 회원이 고른 자리에 상담 일정을 잡는다. 겹치면 409 `schedule_overlap` |
| POST | `/trainer/consultations/{consultation_id}/reject` | `{ note? }` → `TrainerConsultationOut`. 사유는 회원 알림 본문에 실린다 |
| GET | `/trainer/reservation-slots?include_past=` | `TrainerSlotOut[]` `{ id, trainer_id, starts_at, duration_minutes, capacity, remaining, is_closed, session_type, booked_by_name, overlapped }` |
| POST | `/trainer/reservation-slots` | `{ starts_at, duration_minutes, session_type }` → **201** `TrainerSlotOut`. 겹치면 409 `schedule_overlap` |
| PUT | `/trainer/reservation-slots/{slot_id}` | `{ starts_at?, duration_minutes?, session_type?, is_closed? }` → `TrainerSlotOut`. 겹치면 409 |
| DELETE | `/trainer/reservation-slots/{slot_id}` | `TrainerSlotOut` — 자리를 닫는다(행은 남는다) |

**로스터 카드의 나이 (#2744)**: `GET /trainer/clients` 의 각 카드는 `age`(정수 또는 `null`)를 싣는다 —
회원 건강 프로필의 `birth_date` 로 KST 오늘 기준 만 나이를 센 값이고, 생년월일이 없거나 날짜로 읽히지
않으면 `null` 이다. 6자리 코드 연결 확인(`POST /trainer/pairing-code/preview`)의 `age` 와 같은 함수
(`profile_format.age_on`)로 세므로 연결 전후 나이가 같다. 앱은 `null` 이면 나이를 적지 않는다.

**로스터의 PT 관리 신호 (#2203)**: `GET /trainer/clients` 의 각 카드는 `signals` 를 싣는다 —
`[{ kind, days?, count?, percent?, direction? }]`, 급한 순. `kind` 는 `discomfort`(통증·불편) ·
`record_gap`(기록 끊김, `days`) · `no_show`(노쇼·취소 반복, `count`) · `routine_missed`(배정 루틴
미수행, `days`) · `exercise_goal_low`(운동 목표 미달, `percent`) · `calorie_off`(칼로리 목표 이탈,
`percent`·`direction` over|under) · `protein_low`(단백질 부족, `percent`) 일곱 가지다. 담당 해제·휴면
회원은 빈 목록이다. 답장 대기는 여기 없다 — 앱이 `/trainer/chat/unread` 로 실시간으로 센다.

**트레이너 안읽음 집계 범위 (#2868)**: `GET /trainer/chat/unread` 는 **지금 담당 중이고 데이터 공유
동의가 유효한 회원**(`TrainerClient.active` 이고 동의가 철회되지 않았거나 새 동의가 있는 링크)의
안읽음만 돌려준다. 담당 해제·동의 철회 회원은 읽음 처리(`POST /trainer/clients/{id}/chat/read`)가
404 라 지울 수 없으므로 집계에서도 빠지고, 남의 회원과 같은 응답(키 없음)이다. 메시지 행의
`read_at` 은 건드리지 않으므로 같은 트레이너와 다시 연결(새 동의 포함)되면 남아 있던 안읽음이
다시 집계된다. 판단은 `data_consent_service.link_is_open`/`open_link_clause` 한 곳을
`_require_client` 와 함께 쓴다.
기준값과 예외 규칙은 [`docs/TRAINER_DOMAIN.md`](docs/TRAINER_DOMAIN.md) 의 "PT 관리 신호" 참조.

**이행률 (#2513)**: 로스터 `week_completion: (int | null)[7]`(월→일)과 주간 리포트
`week_completion`·`days[].completion`·`completion_avg` 는 그날 이행률 = (완료한 개인운동 + 완료한
PT) ÷ (그날 걸린 개인운동 + 그날 잡힌 PT) 다. 개인운동은 그 트레이너가 건 것이고 다음 날 이후
체크도 완료다. PT 는 `예정·완료` 만 분모다(취소·노쇼·상담 제외). 회원이 직접 추가한 운동은 넣지
않는다. 아무것도 걸리지 않은 날과 아직 오지 않은 날은 `null`, 걸렸는데 하나도 안 한 날은 `0` 이다.
예전 응답은 `routine_history` 의 그날 최댓값이라 `null` 이 없었다(0 = 기록 없음).

**날짜별 개인운동 이행 (#2508)**: `GET /trainer/clients/{member_id}/routine-days?from=&to=` →
`{ start, end, routines[], days[] }`. `days[]` 는 `start`~`end`(오늘을 넘지 않는다) 날마다
`{ date, items[{ routine_id, status, session_id }] }` 이고 `status` 는 `done`(그날 완료) ·
`late`(그날 완료를 다음 날 이후에 체크) · `missed`(안 함, 오늘 이전만) · `pending`(오늘 아직)이다.
`routines[]` 는 `{ id, name, type, source, sort_order, active_from, ended_on, sent_on, personal, minutes, duration_seconds, sets, reps, hold_seconds, weight, effect }` —
양 칸은 배정에 적힌 그대로이고 `effect` 는 회원 앱과 같은 효과 한 줄(적힌 값, 없으면 문구표)이다.
`ended_on` 날은 목록에 뜨지 않고(기한 없는 배정은 `null`), `sent_on` 은 보낸 날(미래 시작일로 보낸
`개인운동만` 은 `active_from` 보다 이르다, #2656), `personal` 이 거짓이면 기한 없는 따로 배정이다.
`from` 을 비우면 그 트레이너가 처음 건 배정의 첫날부터다. 걸린 적이 없으면
`{ start: null, end: null, routines: [], days: [] }`. 담당 해제 회원은 404.

**운동 기록의 개인운동 (#2510)**: `GET /trainer/clients/{member_id}/history` 는 그 트레이너가 건
개인운동의 완료를 하루 한 장으로 묶는다 — `kind: "personal_routine"`, `label: "개인운동"`,
`id: "personal-YYYY-MM-DD"`. `exercise_items[]` 는 그날 걸린 배정 순서이고 한 줄마다 `done` 과
완료의 `session_id`(트레이너 메모 `ref_id` 로 쓴다)를 싣는다. 지난 날 하지 않은 것은 `done: false`,
오늘 아직 안 한 것은 줄이 없다. 예전에는 완료 한 건마다 한 장(`assigned_routine_id` 를 단
항목)이었다. 강도(#2508): 한 줄의 `intensity` 는 회원이 고른 강도이고 `prescribed_intensity` 에
트레이너가 처방한 강도를 함께 싣는다(둘이 다르면 트레이너 화면이 `수행 …` 을 붙인다). 하지 않은
줄은 `intensity` 가 곧 처방 강도이고 `prescribed_intensity` 는 비어 있다.

**완료 PT 회차 (#2697)**: `GET /me/coach/sessions` 의 각 세션은 `session_number` 를 싣는다 —
완료(`status="완료"`)한 PT 가 현재 담당 트레이너와의 몇 번째 수업인지(1부터). 날짜·시각 순으로
처음부터 세므로, 목록이 최근 100건으로 잘려도 번호는 맞다. 상담은 세지 않는다. 예정·취소·노쇼·
상담 세션과 트레이너 응답(`/trainer/schedule`)은 `null` 이다. 회원 앱 운동 탭 `오늘 완료한 PT`
카드의 `N회차` 칩이 이 값을 읽는다.

**회원 주간 피드백 (#2232)**: 한 주가 끝난 뒤 회원이 남기는 세 문항이다. 수치만 보면 같은
한 주가 `게으름` 으로도 `과부하·일정 문제` 로도 읽히는데 그 둘은 다음 주 처방이 정반대라,
갈림길은 회원 본인에게 물어야 정해진다. 트레이너 주간 리포트의 `② 회원 주간 피드백` 칸이
이 값을 읽는다.

| 메서드 | 경로 | 쓰는 쪽 |
|---|---|---|
| `GET` | `/me/coach/weekly-feedback?week_start=` | 회원 앱 — 내가 낸 답 |
| `PUT` | `/me/coach/weekly-feedback` | 회원 앱 — 답 내기 |
| `GET` | `/trainer/clients/{member_id}/report/member-feedback?week_start=` | 트레이너 웹 — 담당 회원의 답 |

- **`week_start` 기본값은 지난 주**다(월요일, KST). 이 답은 끝난 한 주를 돌아보며 적는 것이고
  트레이너는 주 초에 그 주의 리포트를 쓴다 — 기본을 이번 주로 두면 아직 절반도 지나지 않은
  주에 "한 주 컨디션" 을 묻게 된다. 주 중간 날짜를 보내도 그 주 월요일 한 칸으로 접힌다.
- **답이 없는 주는 오류가 아니다.** 두 `GET` 모두 200 에 `submitted: false` 와 빈 칸을 준다.
  404 로 만들면 리포트의 ② 칸이 통째로 사라진다(`report/feedback` 과 같은 규칙).
- **같은 주에 다시 내면 덮어쓴다**(`PUT`, `(user_id, week_start)` 유니크). 한 주에 대한 회원의
  말은 마지막 것 하나다 — 고쳐 보낸 답이 먼저 보낸 답 옆에 서면 트레이너는 둘 중 무엇을
  믿을지 알 수 없다.
- `condition` 은 `great|good|ok|tired|bad`, `intensity` 는 `too_easy|right|hard|too_hard`.
  둘 다 DB `CheckConstraint` 와 같은 목록이고, 벗어나면 **422**. `note` 는 200자,
  `pain_area` 는 40자까지. **아픈 곳을 비운 채 `pain_on` 만 보내면 날짜도 함께 버린다** —
  화면이 "(빈칸) 이 아팠다" 를 그리지 않게 한다.
- 쓰기는 담당 트레이너가 있어야 한다(없으면 404). 받는 사람이 없는 피드백은 아무 데도 닿지
  않는다. **트레이너 없이 쓰는 주간 리포트(포인트 교환, #2022)와는 다른 기능**이라 그 경로와
  섞지 않는다.

**주간 리포트 요일별 끼니·배정 (#2772)**: `GET /trainer/clients/{member_id}/report?week_start=` 의
`WeeklyReportOut` 은 요일 표의 끼니 줄과 개인운동 칸 분모를 함께 준다. 둘 다 없던 옛 응답은 앱이
빈 값으로 읽어 끼니 줄을 `–` 로, 개인운동 분모를 실제로 한 운동 수로 둔다.

- `meal_counts: int[7]` — 월→일 요일별 끼니 기록 수(그날 `DietEntry` 수). 기록 없는 날과
  아직 오지 않은 날은 0 이고, 아직 오지 않은 날을 `–` 로 그리는 것은 화면 규칙이다.
- `days[].assigned: int | null` — 그날 회원 목록에 걸려 있던 **그 트레이너의** 추천 개인운동
  수(매일 리셋되는 목록, #2161). 배정이 없던 날과 아직 오지 않은 날은 `null` 이다 — 0 은
  쉬는 날과 구분되지 않아 쓰지 않는다(#2232, 데모와 같은 규칙).
- `days[].assigned_done: int | null` — 그중 그날 완료한 수, `assigned` 의 짝인 분자다(#3115).
  `assigned` 가 `null` 인 날은 이것도 `null` 이다. `exercises` 는 그날 남은 운동 기록 전부(직접
  기록·PT 기록 포함)라 개인운동 완료 수로 쓰지 않는다. 이 칸이 없는 옛 응답이면 앱이 `exercises` 로 센다.
- PT 프로그램은 회원의 매일 개인운동 목록에 걸리지 않는다(#3115) — 보낼 때 `ended_on == active_from`
  으로 남아 `assigned`·운동 조언·회원 신호 `routine_missed` 가 개인운동만 센다. 그날 내용은 PT 기록이 남긴다.

**칼로리 평소 기준 (#2863)**: 같은 `WeeklyReportOut` 에 `calorie_baseline: float | null` 이 실린다.
그 주 월요일 앞 **4주(28일)** 동안 칼로리를 기록한 날(하루 `DietEntry.total_calories` 합이 0 보다 큰
날)의 하루 평균이다. 기록한 날이 없으면 `null` 이고, 그 주 자신은 넣지 않는다. 트레이너 웹 ① 칼로리
줄의 `지난 4주 평균` 이 이 값이다 — 예전에는 앱이 직전 4주 리포트(와 회원 피드백)를 다시 불러
칼로리 배열만 꺼내 썼다. 데모는 drift 이력에서 같은 규칙으로 센다.

**회원 주간 리포트 (#2652)**: 회원 앱 결과지가 트레이너 웹 결과지와 같은 한 장을 그리게
하는 읽기 경로다. 응답은 트레이너의 `GET /trainer/clients/{member_id}/report` 와 같은
`WeeklyReportOut` 이다.

| 메서드 | 경로 | 쓰는 쪽 |
|---|---|---|
| `GET` | `/me/coach/weekly-report?week_start=` | 회원 앱 — 내 한 주 결과지 |

- `week_start` 기본값은 **이번 주**(트레이너 리포트와 같다). 주 중간 날짜는 그 주 월요일로
  접히고, 형식이 틀리거나 **아직 오지 않은 주는 422**.
- 같은 회원·같은 주면 `message` 를 뺀 모든 필드가 트레이너 응답과 같다.
- **`message` 는 항상 빈 문자열**이다 — 트레이너가 손보고 보낼 자동 초안이라 회원에게 먼저
  닿으면 안 된다. 회원이 읽는 코칭 글은 트레이너가 채팅으로 보낸 것뿐이다.
- 담당 트레이너가 없어도 200 이다(포인트로 교환한 리포트, #2022). 그때 `sessions_*` 는 0 이다.

**다음 주 목표 (#2232)**: 트레이너가 리포트 ② 에서 고른 목표다. 다음 주 리포트의
`③ 지난 주 목표 달성` 이 그대로 회수한다 — 목표는 **다음 주에 확인될 때** 비로소 목표이고,
확인되지 않는 목표를 매주 새로 고르는 화면은 트레이너에게 일만 늘린다.

| 메서드 | 경로 | 하는 일 |
|---|---|---|
| `GET` | `/trainer/clients/{member_id}/report/goals?week_start=` | 그 주에 **적용돼 있는** 목표 |
| `PUT` | `/trainer/clients/{member_id}/report/goals` | ②에서 고른 목표를 **다음 주**에 적용 |

- **저장은 고른 주가 아니라 지켜야 할 주에 한다.** `PUT` 의 `week_start` 는 지금 보고 있는
  주이고, 서버가 한 주를 더해 적용 주를 정한다 — 주 경계 계산이 앱과 서버 두 곳에 있으면
  한쪽만 틀리는 날이 온다. 응답의 `week_start` 는 **적용된 주**라, 앱이 저장 결과를 그대로
  믿을 수 있다. 주 중간 날짜로 보내도 그 주 월요일의 다음 주 하나로 접힌다.
- **빈 목록이 정상이다.** `GET` 은 200 에 `goals: []` 를 준다 — 지난 주에 아무것도 고르지
  않았거나 이 회원의 첫 주다. 404 면 리포트의 ③ 칸이 통째로 사라진다.
- `PUT` 은 화면이 들고 있는 **목록 전체로 통째로 바꾼다**. 뺀 목표가 다음 주에 살아 있으면
  트레이너는 목표를 뺄 방법이 없다. 빈 목록으로 지울 수도 있다.
- 앞뒤 공백은 잘라내고, 빈 줄과 **같은 목표의 중복은 한 줄로 접는다** — 두 줄로 서면 다음 주
  ③ 이 같은 판정을 두 번 적는다. 순서는 보낸 그대로 지킨다(③ 이 1·2·3 번호를 붙인다).
  한 줄 120자, 한 주 20줄까지. 넘으면 **422**.
- 키는 `(member_id, week_start)` 다. 담당이 바뀌어도 그 주의 목표는 회원의 것이라,
  트레이너까지 키에 넣으면 인수인계한 주에 목록이 둘로 갈라진다.

**리포트 PDF 전송 (#1378, #2771)**: 리포트 PDF 를 담당 회원 채팅으로 보낸다.

| 메서드 | 경로 | 응답 |
|---|---|---|
| `POST` | `/trainer/clients/{member_id}/report/send-pdf` | **201** 채팅 메시지(`attachment.type = "pdf"`, `report_week_start`) |

- 요청은 `multipart/form-data` 다: `pdf`(파일, 필수)·`week_start`(필수)·`message`(글, **필수**)·
  `client_request_id`(선택, 1~64자).
- `message` 는 앞뒤 공백을 걷어 저장한다. **비었거나 공백뿐이면 422** 이고 아무것도 저장하지 않는다.
  예전에는 서버가 한국어 기본 문장으로 채웠는데, 서버는 회원의 언어를 몰라 영어로 쓰는 회원에게도
  한국어가 나갔다 — 회원이 받을 글은 앱이 그 언어로 만든다.
- 같은 `client_request_id` 재시도는 처음 메시지를 그대로 돌려준다(한 번 전송). 같은 키에 **다른 본문**이면
  **409** 다. 트레이너 웹은 보낼 문구가 바뀌면 새 키를 쓴다(#2773).
- 담당이 아니거나 해제된 회원은 **404**, PDF 가 아니면 **415**, 용량 초과는 **413**. 요청 본문이
  `max_report_pdf_bytes`(8MB) + `UPLOAD_BODY_SLACK_BYTES`(multipart 여유, 기본 512KB)를 넘으면 본문을 다
  받기 전에 **413** `{"detail": "PDF 용량이 너무 큽니다(최대 8MB)."}` 로 끊는다(#2832). 그 안쪽에서 파일만
  8MB 를 넘으면 핸들러가 413 을 낸다.

**리포트 작업대 요약 (#2863)**: 트레이너 웹 리포트 첫 화면(작업대)의 큐를 세우는 값을 담당 회원
전원에 대해 **한 번에** 준다. 예전에는 회원마다 `/report` 와 `/report/member-feedback` 를 불러 회원
N명이면 첫 화면에서 요청이 2N개였다.

| 메서드 | 경로 | 응답 |
|---|---|---|
| `GET` | `/trainer/reports/queue?week_start=` | `{ week_start, items: [{ member_id, sessions_booked, sessions_done, completion_avg, week_completion }] }` |

- 각 값은 같은 회원·같은 주의 `GET /trainer/clients/{member_id}/report` 와 **같은 규칙**이다 —
  `sessions_booked` 는 예정+완료(취소·노쇼·상담 제외), `sessions_done` 은 완료, `week_completion`
  은 월→일 7칸 이행률(주간 리포트와 같은 계산 — 걸린 개인운동과 잡힌 PT, 아무것도 걸리지 않은 날은 `null`, #2513), `completion_avg` 는 걸린 날의 평균이고 걸린 날이 없으면 `null`(0 아님).
  식단·요일별 운동·회원 피드백은 싣지 않는다 — 편집기를 열 때 그 회원 리포트로 읽는다.
- 집계는 회원별 반복이 아니라 회원 id 목록으로 묶어 조회한다(세션 한 번, 이행 기록 한 번).
- **담당이 살아 있고 데이터 공유 동의가 유효한 회원만** 싣는다(회원 단위 경로가 404 를 주는 회원은
  빠진다). 다른 트레이너가 건 이행 기록은 세지 않는다. 담당 회원이 없으면 200 에 `items: []`.
  순서는 `member_id` 순이고, 화면 순서는 앱이 정한다.
- `week_start` 기본값은 이번 주이고, 주 중간 날짜는 그 주 월요일로 접힌다. 형식이 틀리거나
  아직 오지 않은 주는 **422**(리포트 조회와 같은 규칙). 회원 계정은 **403**.
- 데모(목업)는 같은 값을 회원별 리포트 계산에서 뽑는다 — 값이 실서버와 같은 규칙으로 나온다.

**리포트 전송 이력 (#2288)**: 그 주 리포트가 이미 나간 담당 회원들이다. 트레이너 웹 리포트
작업대가 `전송 완료` 열을 세우고, 이미 보낸 회원에게 다시 보내기 전에 확인을 받는 근거다.

| 메서드 | 경로 | 응답 |
|---|---|---|
| `GET` | `/trainer/reports/sent?week_start=` | `{ week_start, sends: [{ member_id, week_start, sent_at, message, read, has_pdf, send_count }] }` |

- **따로 저장하는 표가 없다.** 리포트 전송(`/report/send`·`/report/send-pdf`)이 채팅 메시지에
  남기는 `report_week_start` 를 그대로 읽는다 — 전송 기록을 두 곳에 두면 한쪽만 남는 날이 온다.
  앱 메모리에만 기록이 있던 때는 새로고침하면 보낸 회원이 미전송으로 돌아가 같은 리포트가
  두 번 나갔다.
- 한 회원에게 같은 주 리포트를 여러 번 보냈으면 **가장 최근 전송 하나로 접는다.** `sent_at`
  (ISO, UTC)·`message`(회원이 받은 본문)·`read`(회원이 연 적 있는가, `read_at`)·`has_pdf` 는
  모두 그 최근 전송의 값이고, `send_count` 는 그 주에 보낸 횟수다. 같은 `client_request_id`
  로 재시도한 PDF 전송은 한 번이다.
- `week_start` 기본값은 이번 주이고, 주 중간 날짜는 그 주 월요일로 접힌다. 형식이 틀리거나
  아직 오지 않은 주는 **422**(리포트 조회와 같은 규칙).
- **담당이 살아 있는 회원만** 싣는다. 해제된 회원의 기록은 빠진다(#2281). 보낸 적이 없는 주는
  200 에 `sends: []` 다. 회원 계정은 **403**.

**회원별 리포트 전송 이력 (#2393)**: 한 담당 회원에게 그동안 보낸 리포트를 주별로 모은다. 위 주 단위
조회는 한 주의 로스터 전체라, 회원별 지난 리포트 화면을 세우려면 주마다 따로 물어야 했다.

| 메서드 | 경로 | 응답 |
|---|---|---|
| `GET` | `/trainer/clients/{member_id}/reports/sent?limit=&before=` | `{ member_id, sends: [{ week_start, sent_at, read, send_count, message_id, has_pdf, feedback_preview }], next_before }` |

- 근거와 접는 규칙은 주 단위 조회와 **같다** — 채팅 메시지의 `report_week_start`(본문·PDF 전송 모두),
  한 주에 여러 번 보냈으면 가장 최근 전송 하나와 `send_count`. `sent_at`(ISO, UTC)·`read`(`read_at`)·
  `message_id`(그 최근 전송의 채팅 메시지 id)·`has_pdf` 는 모두 그 최근 전송의 값이다.
- `feedback_preview` 는 최근 전송 본문의 **비어 있지 않은 첫 줄**이고, 80자를 넘으면 잘라 `…` 를 붙인다.
  전문은 `message_id` 로 채팅에서 연다.
- 정렬은 `week_start` 내림차순(최신 주부터). 쪽은 **주 단위**로 나눈다 — `limit` 은 주 수(기본 12,
  1~100, 벗어나면 **422**). 더 오래된 주가 있으면 `next_before` 에 이 쪽 마지막 `week_start` 가 오고,
  그 값을 `before`(`YYYY-MM-DD`, 그 주 **제외**)로 다시 주면 다음 쪽이다. 더 없으면 `null`.
  주 중간 날짜를 주면 그 주 월요일로 접힌다. 형식이 틀리면 **422**.
- 담당이 아니거나 해제된 회원은 다른 `/trainer/clients/{member_id}/…` 경로와 같은 **404**(#2281).
  보낸 적이 없으면 200 에 `sends: []`·`next_before: null`. 회원 계정은 **403**.

**채팅 사진 (#921, #1665)**: 트레이너와 회원이 **서로** 사진을 보낸다. 식사·자세·인바디 결과지처럼
코칭에 바로 쓰이는 사진이 대화 안에서 오가야, 사진만큼은 개인 메신저로 보내는 일이 없다.

| 메서드 | 경로 | 보내는 쪽 |
|---|---|---|
| `POST` | `/trainer/clients/{member_id}/chat/image` | 트레이너 → 담당 회원 (#921) |
| `POST` | `/me/coach/chat/image` | 회원 → 담당 트레이너 (#1665) |
| `GET` | `/chat/attachments/{file_id}` | 그 스레드의 두 사람 — 내려받기 |

- 요청은 `multipart/form-data` 다: `image`(파일, 필수)·`message`(글, 선택, 1000자)·`client_request_id`
  (선택, 1~64자). 응답은 `201` 에 `ChatMessageOut` 이고 `attachment` 가
  `{ type: "image", file_name, file_id, file_size, download_path }` 다. 사진만 보내도 된다(`body` 는 빈 글).
- **형식은 바이트로 판정한다** — JPG·PNG·WebP 만 받고 나머지는 **415**. 확장자와 `Content-Type` 은
  보내는 쪽이 자유롭게 적을 수 있어 참고하지 않는다. 용량 상한은 `max_chat_image_bytes`(6MB)이고
  넘으면 **413**. 두 경로가 같은 규약을 한 함수(`chat_attachments.receive_chat_image`)로 쓴다.
  요청 본문이 6MB + `UPLOAD_BODY_SLACK_BYTES`(multipart 여유, 기본 512KB)를 넘으면 본문을 다 받기 전에
  **413** `{"detail": "사진 용량이 너무 큽니다(최대 6MB)."}` 로 끊는다(#2832). 이 413 에도 CORS 헤더가 붙는다.
- **저장 전에 사진을 정리한다(#2829).** 끝까지 디코딩해 EXIF 회전을 픽셀에 적용하고, EXIF(촬영
  위치·기기)·XMP·주석·PNG 텍스트 같은 메타데이터를 버린 뒤 **원본 형식 그대로** 다시 인코딩한다
  (PNG 투명도 유지, 색 프로필 ICC 만 유지). 장변은 2048px 로 줄인다. 매직 넘버만 맞고 디코딩할 수
  없는 파일은 저장하지 않고 **415**. `file_size` 와 내려받는 파일은 정리한 뒤의 값이다. 끼니
  사진(#699)도 같은 정리 함수(`image_sanitize`)를 쓴다. 이전에 쌓인 파일은
  `python -m scripts.sanitize_chat_images --apply` 로 다시 쓴다(기본은 점검만).
- **펼치기 전에 크기를 본다(#3040).** 헤더의 장변이 `MAX_IMAGE_DECODE_EDGE`(기본 12,000px)를 넘거나,
  실제로 펼칠 픽셀 수가 `MAX_IMAGE_DECODE_PIXELS`(기본 4,000만)를 넘으면 디코딩하지 않고 읽을 수 없는
  사진과 같은 **415** 다. JPEG 은 결과 크기 근처까지 축소 디코딩한 뒤의 크기로 센다. 애니메이션은 첫
  프레임만 쓰고, 프레임이 100장을 넘으면 받지 않는다. 끼니 사진도 같은 상한을 쓴다 — 넘는 사진은
  기록을 막지 않고 사진 없이 저장된다.
- **같은 `client_request_id` 재시도는 한 번만 보낸다.** 같은 키에 다른 글이나 사진이 아닌 메시지가
  있으면 **409**.
- **내려받기는 서버가 권한을 확인한 뒤 흘려보낸다**(#2817). 바이트는 운영에서 객체 저장소(S3),
  개발에서는 로컬 디스크에 있지만 응답은 같다 — 서명 URL 을 내주지 않는다(링크가 새면 권한
  확인 없이 열리고, 담당 해제·동의 철회 뒤에도 만료 전까지 열리기 때문). 응답에
  `Cache-Control: private, no-store` 가 붙고, 저장소에 바이트가 없으면 **404** 다.
- 회원 경로는 **활성 담당 링크가 있어야 한다** — 없으면 글 메시지(`POST /me/coach/chat`)와 같이
  **404**. 트레이너 계정은 **403**. 트레이너 경로는 담당 고객이 아니면 **404**.
- 알림: 트레이너가 보내면 회원에게, 회원이 보내면 트레이너에게 새 메시지 알림이 남는다(글 메시지와
  같은 종류). 사진만 보낸 메시지는 본문이 비어 있어 알림 본문을 `사진을 보냈어요`(`Sent a photo`)로
  채우고, 트레이너 로스터의 마지막 메시지는 `사진`(`Photo`)이다.
- 내려받기는 그 스레드의 회원 본인과 **활성 담당 트레이너**만 된다. 다른 사람에게는 존재 여부를
  숨기려 **404** 다. 사진은 `inline` 으로 준다(대화 안에서 그린다).
- **일반 파일은 받지 않는다.** 첨부 종류는 리포트 PDF(`pdf`, 리포트 전송 전용)와 사진(`image`)
  두 가지뿐이다 — 이 대화는 코칭을 위한 것이고, 받는 쪽이 그릴 수 없는 형식은 아이콘 하나로만 남는다.

**데이터 공유 동의 철회 (#1631)**: **담당 해제 = 데이터 공유 동의 철회**다. 링크
(`trainer_clients`)에 동의 시각 `data_consent_at` 과 철회 시각 `data_consent_revoked_at` 을 둔다.

| 경로 | 동의 |
|---|---|
| `DELETE /me/coach`, `DELETE /me/coach/trainer`(회원 해제), `DELETE /trainer/clients/{member_id}`(트레이너 해제) | `data_consent_at` 을 비우고 `data_consent_revoked_at` 에 그 시각. 두 번 해제해도 처음 시각이 남는다 |
| `DELETE /users/me`, `DELETE /trainer/me`(탈퇴) | 링크 행이 계정과 함께 `CASCADE` 로 지워진다 — 남는 동의가 없다 |
| 다른 트레이너로 옮김 | 옛 링크는 해제 때 철회, 새 링크에는 새 연결의 동의만 |
| 끊긴 링크 되살리기(`/me/coach/invites/{id}/accept`·`/trainer/pairing-code`) | 그 연결의 새 동의만 적는다. 옛 동의는 되살아나지 않는다. `data_consent_revoked_at` 은 이력으로 남긴다 |
| `PUT /trainer/clients/{member_id}/registration`(트레이너 혼자 재등록) | 동의가 철회된 링크면 **409** — 회원이 동의하는 경로(담당 요청·연결 코드)로 다시 연결한다. 철회 기록이 없는 옛 해제 링크는 예전처럼 204 |

- **동의 없이 살아 있는 링크**(철회 뒤 새 동의 없이 되살아난 링크)는 트레이너의
  `/trainer/clients/{member_id}/…` 회원 단위 요청이 전부 해제된 회원과 **같은 404·같은 문구**다.
  로스터 카드는 남지만 식단·마지막 대화·루틴·주간 수행률·PT 관리 신호를 싣지 않는다. 성별·나이·건강
  목표도 `gender=""`·`age=null`·`goal=""` 로 비운다(#2814) — 담당 해제(`registered=false`) 카드도 같다. 채팅 첨부
  (`/chat/attachments/{id}`)도 트레이너에게는 404. 해제·철회 전에 잡아 둔 일정을 id 로 여는
  쓰기(`/trainer/schedule/{id}` 의 `PUT`·`/complete`·`/reopen`·`/routines/send`)도 같은 404 이고
  회원 운동 기록·알림을 남기지 않는다. 취소·삭제는 그대로 열린다. 회원이 담당 요청을 수락하거나 연결 코드를 주면
  그 시각이 새 동의가 되어 다시 열린다.
- **마무리된 세션은 메모·아직 보내지 않은 프로그램만 고친다 (#2754).** 완료·취소·노쇼 세션의
  `PUT /trainer/schedule/{id}` 는 본문이 `note`·`program` 만이면 200 이다. `date`·`time`·`member_id`·
  `client_name`·`type`·`duration_minutes` 가 하나라도 섞이면 409 다(그 기록이 가리키는 약속이 바뀐다).
  이미 보낸 프로그램(`program_sent: true`)을 다른 내용으로 바꾸면 409 이고, 같은 내용을 함께 실은
  메모 수정은 막지 않는다.
- **완료 세션의 프로그램·메모를 고치면 회원 운동 기록과 트레이너 이력이 함께 바뀐다 (#3093).** 같은
  저장에서 회원 운동 기록(`sched-ex-{id}`, 분·유형·이름·세트·횟수·중량·강도·칼로리)과 트레이너 이력
  (`sched-hist-{id}`, 운동 목록·메모)을 완료 때와 같은 계산으로 다시 쓰고, 커밋 뒤 AI 코치 근거 문서도
  맞춘다. 메모만 고치면 회원 운동 기록은 그대로다. 완료 세션을 지우거나(`DELETE`) 되돌리면(`/reopen`)
  두 기록과 함께 코치 근거 문서도 지운다. 근거 문서 갱신은 best-effort 라 실패해도 응답은 200 이다.
- **회원 예약 일정은 `is_reservation: true` 로 실린다 (#2756).** 트레이너 스케줄 응답의 각 일정에
  회원이 예약 슬롯으로 잡은 일정인지를 싣는다. 이 일정은 `note`·`program` 수정만 되고, 그 밖의 수정·
  삭제·되돌리기는 409(`detail` 에 사유 문자열)다. 일정을 거두려면 `/cancel` 을 쓴다 — 예약과 좌석이
  함께 풀린다.
- **되돌리기는 겹침을 먼저 본다 (#2757).** `POST /trainer/schedule/{id}/reopen` 은 `date` 와 함께
  선택 `time`·`duration_minutes` 를 받는다(없으면 지금 값). 옮길 자리가 다른 일정과 겹치면 아무것도
  바꾸지 않고 409(`code: schedule_overlap`, `conflicts`)다 — 세션은 완료·원래 날짜 그대로이고 트레이너
  이력·회원 운동 기록도 남는다. 겹치지 않으면 날짜·시각·길이를 함께 옮기고 예정으로 바꾼다.
- **완료·노쇼는 시작 시각이 지나야 된다 (#2760).** `/complete`·`/no-show` 는 일정의 날짜+`time` 을 KST
  로 보고 지금보다 뒤면 400 이다. 날짜만 보던 예전에는 오늘 20:00 PT 를 오전에 완료·노쇼로 처리할
  수 있었다. 완료는 종료가 아니라 시작 시각부터 열린다. 취소 가능 시점은 그대로다.
- **해제·철회 회원의 일정은 트레이너 스케줄에 익명으로 남는다 (#2589).** `GET /trainer/schedule`(일·구간)·
  `GET /trainer/schedule/booked-dates`·겹침 거절(409 `conflicts`)은 그 일정을 빼지 않고 `member_detached: true`,
  `client_name: "해제 회원"`, `member_id: null` 로 싣는다. `note`·`program`·`cancellation_reason` 은 비우고
  `program_sent` 는 `false` 다. 날짜·시각·종류·길이·상태·취소/노쇼 시각·취소 주체는 남는다. `member_id` 필터
  조회는 지금처럼 404 다. 이 일정의 수정·완료·재개·전송은 위와 같은 404, 삭제·취소는 열린다.
- **해제하면 아직 시작하지 않은 `예정` 일정은 취소된다 (#2589).** 세 해제 경로 모두 그 트레이너·회원 쌍의 시작
  전 일정을 `취소`(주체: 트레이너 해제 `trainer`, 회원 해제 `member`, 사유 `담당 해제`)로 바꾸고, 예약으로 생긴
  일정은 예약을 거두고 좌석을 돌려준다. 시작 시각이 지난 `예정` 은 그대로 둔다. 일정마다 취소 알림을 보내지 않고
  해제 알림 한 건이 취소 수를 전한다 — 트레이너 해제는 회원에게 틀 `member_trainer_disconnected`(인자
  `trainer_name`·`cancelled_sessions`), 회원 해제는 트레이너의 `trainer_member_disconnected` 에
  `cancelled_sessions` 가 붙는다. 취소 수가 0 이면 일정 문장 없이 연결이 끊어졌다는 문장만 보낸다.
- 동의 기능(#1022) 이전에 만들어져 **동의도 철회도 없는** 링크는 막지 않는다.
- **이미 주고받은 기록은 지우지 않는다.** 철회 전에 보낸 채팅·리포트·일정·루틴은 그대로 남는다.
  철회는 **앞으로의 열람**만 막는다. 회원의 `/me/coach/chat`·`/me/coach/sessions`·`/me/coach/routines` 는
  활성 담당 기준이라 해제한 동안은 트레이너와의 기록이 보이지 않고(채팅 404, 일정 빈 목록, 루틴은 AI
  추천으로 바뀐다), 같은 트레이너와 다시 연결하면 다시 보인다(#2387).
- 마이그레이션 `0097_data_consent_revocation` 은 이미 해제된 링크(`active = false`)의 동의를 비우고
  마이그레이션 시각을 철회 시각으로 적는다.
- 담당이 끝나면 그 트레이너의 메시지로 만든 식단 AI 보관물을 내려놓는다(#2386) — 이번 주·전체
  조언(`/diet/advice`)은 다음 조회가 담당 없이 다시 만들고, 추천 메뉴 리스트는 오늘로 만료되어 다시 만든다.

---

## 인증

두 앱 모두 로그인과 토큰 저장이 붙어 있다(`session_controller.dart`, `secure_token_store.dart`,
`auth_interceptor.dart`). 발급은 `POST /auth/login`·`POST /auth/refresh`·`POST /auth/social/{provider}`
이고, 이후 요청은 `Authorization: Bearer <access>` 를 단다.

| Method | Path | 요청 → 응답 |
|---|---|---|
| POST | `/auth/register/email-code` | `{ email, purpose: "member_signup"\|"trainer_signup" }` → **202** `{ expires_in_minutes, resend_after_seconds }` — 가입 전 이메일 인증 코드(#3038). 가입 여부와 무관하게 같은 응답. 아래 [가입 이메일 인증](#가입-이메일-인증-3038) |
| POST | `/auth/register` | `{ email, password, name, phone, email_code }` → **201** `{ id, name, email, role: "member" }` — 회원(`role=member`). 이미 가입된 이메일 409, 코드 없음 422 `email_code_required`, 틀린·만료 코드 400 `invalid_email_code`(#3038) |
| POST | `/auth/trainer/register` | 같은 입력 → **201** `{ id, name, email, role: "trainer" }` — 트레이너(#475). 역할을 요청 필드로 가르지 않으려고 경로를 나눴다. 소속 헬스장은 가입 뒤 `PUT /trainer/me/gym`. 코드는 `purpose=trainer_signup` 으로 받은 것만 맞다 |
| POST | `/auth/login` | form(`application/x-www-form-urlencoded`) `username`(이메일)·`password` → `{ access_token, refresh_token, token_type }`. 틀리면 401 |
| POST | `/auth/refresh` | `{ refresh_token }` → 새 `{ access_token, refresh_token, token_type }`(회전). 무효·폐기된 토큰 401 |
| POST | `/auth/logout` | `{ refresh_token }` → **204**. 그 refresh 토큰을 폐기한다. access 토큰은 요구하지 않고, 못 알아본 토큰에도 204 |
| POST | `/auth/social/{provider}` | `{ token }` → `{ access_token, refresh_token, token_type }`. 실패 응답은 아래 절 |
| POST | `/auth/password-reset/request` | `{ email }` → **202** `{ status: "requested", expires_in_minutes }` — 계정 유무와 무관하게 같은 응답(#2824). 아래 [비밀번호 재설정](#비밀번호-재설정-2824) |
| POST | `/auth/password-reset/confirm` | `{ token, new_password }` → `{ status: "reset" }`. 코드 없음·만료·사용됨은 400 `invalid_reset_token`(#2824) |

인증 엔드포인트는 IP·엔드포인트당 분당 한도(`RATE_LIMIT_AUTH_PER_MINUTE`)를 받는다. 비밀번호·연락처·이름 규칙은
아래 절들에 있다.

### 소셜 로그인 실패 응답 (#1550)

`POST /auth/social/{provider}` 는 provider(google·kakao·apple, naver 는 아래 #3035 절)에 토큰을 확인한 뒤
결과에 따라 아래처럼 답한다. **500 은 내지 않는다** — provider 점검 페이지·WAF 차단 화면처럼
200 에 HTML 이 오거나, JSON 이 깨졌거나, 약속한 필드의 타입이 달라도 마찬가지다.

| 상황 | 상태 | `detail` |
|---|---|---|
| 지원하지 않는 provider | **400** | `지원하지 않는 소셜 로그인입니다.` |
| 토큰 거절(provider 가 200 아닌 응답)·요청 실패(연결·타임아웃)·필수 사용자 id 누락 | **401** | `소셜 인증에 실패했습니다.` |
| provider 응답 형식 이상 — JSON 이 아님(HTML·깨진 JSON·빈 본문), JSON 객체가 아님(배열·문자열·숫자·null), 필드 타입 이상(id 가 객체·bool 등, 하위 객체가 배열 등) | **502** | `소셜 로그인 제공자의 응답을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.` |
| 검증 중 예상하지 못한 예외 | **502** | 위와 같음 |

- 401 은 "이 토큰으로는 로그인할 수 없다", 502 는 "provider 쪽이 지금 제대로 답하지 않는다"
  이다. 앱은 502 를 잠시 뒤 재시도할 일로 다루면 된다.
- 선택 필드(이메일·이름·kakao `kakao_account`/`profile`·naver `response`)는 없거나 `null` 이면
  빈 값으로 받는다. 있는데 타입이 다르면 형식 이상(502)이다. kakao id 는 정수로 와도 문자열로
  저장한다.
- 401·502 모두 실패 감사 로그(`auth.social`, `success=false`, `detail`=provider)를 남긴다.
  감사·서버 로그·응답 어디에도 토큰과 provider 응답 본문은 남기지 않는다.

### 소셜 토큰 발급 앱 확인 (#3035)

provider 가 "유효한 토큰"이라고 답해도, 그 토큰이 **우리 앱 앞으로** 발급된 것이어야 로그인된다.
다른 앱이 받은 같은 사람의 토큰으로는 계정이 만들어지거나 같은 이메일의 기존 계정에 연결되지 않는다.

| provider | 서버가 확인하는 것 | 허용 설정 |
|---|---|---|
| google | tokeninfo 의 `aud` 가 허용 목록 안, `iss` 가 `accounts.google.com`·`https://accounts.google.com`, `exp` 가 미래 | `GOOGLE_CLIENT_IDS`(콤마 구분) |
| kakao | `GET /v1/user/access_token_info` 의 `app_id` 가 설정값과 같고, 그 `id` 가 `/v2/user/me` 의 `id` 와 같음(토큰 정보가 맞을 때만 사용자 정보를 부른다) | `KAKAO_APP_ID` |
| apple | id_token 서명(JWKS)·`aud`·`iss`·`exp` | `APPLE_CLIENT_IDS`(콤마 구분) |
| naver | 앱이 보낸 access_token 의 발급 앱을 확인할 수단이 없다. 서버 측 코드 교환 전까지 **501** `아직 지원하지 않는 소셜 로그인입니다.`(네이버로 요청도 보내지 않는다) | — |

- 발급 앱·발급자 불일치, 만료, 두 응답의 id 불일치는 위 표의 **401** `소셜 인증에 실패했습니다.` 와 같다.
  어느 검사에서 떨어졌는지는 서버 로그에만 남기고, 값(토큰·client_id·응답 본문)은 남기지 않는다.
- 허용 설정이 비어 있으면 그 provider 는 외부 호출 없이 **401** 이다(조용히 통과시키지 않는다). 기동
  점검이 비어 있는 provider 를 경고 로그로 남긴다.
- 발급 정보 필드의 타입이 약속과 다르면(예: `aud` 가 배열, `exp` 가 숫자가 아닌 문자열, `app_id` 가 bool)
  형식 이상 **502** 다.

### 가입 동의 (#2819)

두 앱의 가입은 약관·개인정보 수집·이용·만 14세 이상 확인에 **명시적으로** 동의해야 끝난다.
회원은 여기에 **건강정보(민감정보) 처리** 동의가 따로 하나 더 있다. 선택 항목은 없다.
항목마다 `user_consents` 에 `kind`·`version`·`agreed_at`(·`revoked_at`) 한 행이 남는다.

| 항목(`kind`) | 회원 | 트레이너 |
|---|---|---|
| `terms` 이용약관 | 필수 | 필수 |
| `privacy` 개인정보 수집·이용 | 필수 | 필수 |
| `health` 건강정보(민감정보) 처리 | 필수 | — |
| `age14` 만 14세 이상 | 필수 | 필수 |

`marketing`(마케팅 알림 수신)은 **더는 받지 않는다**(#3007) — 보내는 기능도, 거두는 화면도, 처리방침의
이용 목적도 없었다. 옛 앱 빌드가 이 값을 실어 보내도 422 가 아니며 **기록하지 않는다**. 이미 남은
`marketing` 행은 마이그레이션 0141 이 `revoked_at` 을 채웠고(행은 이력으로 남음), 동의 상태 계산에는
끼지 않는다.

- `POST /auth/register`·`POST /auth/trainer/register` 는 `consents: [항목]` 을 받는다. 보냈다면 그
  역할의 필수 항목이 모두 있어야 하고, 빠졌거나(빈 목록 포함) 모르는 항목이면 **422** 다 — 계정은
  만들어지지 않는다. **보내지 않으면(`null`) 가입은 받는다**: 동의 화면이 없는 옛 빌드의 가입이며,
  기록 없이 계정만 만들어진다. 다만 그 계정은 동의하기 전까지 회원 데이터·AI API 를 쓰지 못한다
  (아래 "필수 동의 확인").
- `POST /auth/login`·`POST /auth/social/{provider}` 응답에 `consent_required: bool` 이 붙는다.
  `GET /users/me` 는 같은 값과 아직 동의하지 않은 필수 항목 목록(`consent_pending`)을 준다.
  기록이 없는 계정(동의 절차 이전 가입·옛 빌드 가입·소셜 첫 가입)과, 문서 버전이 올라 지금 버전에
  동의하지 않은 계정이 `true` 다. 앱은 이때 다른 화면보다 먼저 동의 화면을 띄운다.
- `POST /users/me/consents`(토큰 필수, 회원·트레이너 공통)가 그 화면의 저장이다. 필수 항목이
  하나라도 빠지면 아무것도 남기지 않고 **422** `{ detail: { code: "consent_required", missing: [...] } }`.
  이미 지금 버전에 동의한 항목은 다시 쓰지 않는다 — 처음 동의한 시각이 남는다.
- 문서 버전은 `services/signup_consent.CURRENT_VERSIONS` 한 곳이 정한다. 약관·처리방침 본문을
  고치면 그 항목의 버전을 올린다. 처리방침은 위탁·국외 이전·파기 절차 절을 더하며 `privacy` 가
  `2026-10-03` 으로 올랐고(#2820), 보호책임자 연락처를 팀 수신 주소로 바꾸고 위치정보 이용 동의
  안내를 더하며 `2026-10-05` 로 다시 올랐다(#3132·#3136) — 그 전 버전에만 동의한 계정은 다시
  동의할 때까지 회원 데이터 API 가 403 이고, 동의 화면을 다시 거친다. 버전 날짜는 두 앱 처리방침
  본문의 시행일과 같아야 한다.
- **필수 동의 확인(#3088)** — 회원 계정은 역할의 필수 항목(`terms`·`privacy`·`health`·`age14`)에
  지금 버전으로 동의해 두어야 회원 의존성(`CurrentUser`·`RequireMember`)을 쓰는 API 를 부를 수 있다.
  남은 항목이 있으면 **403** `{ detail: { code: "consent_required", missing: [...] } }` — 위 422 와
  같은 모양이다. 핸들러보다 먼저 막으므로 음식 인식·AI 코치 같은 외부 AI 호출도 일어나지 않는다.
  기록이 없는 계정, 문서 버전이 오른 계정, 동의를 철회(`revoked_at`)한 계정이 모두 해당한다.
  - 동의 없이도 열려 있는 경로: `GET /users/me`(동의 필요 여부 조회), `POST /users/me/consents`,
    `DELETE /users/me`(탈퇴), `/auth/*`(로그인·refresh·로그아웃·비밀번호 재설정·소셜 로그인),
    계정 데이터가 없는 공개 경로. 목록은 `api/deps.CONSENT_EXEMPT_ROUTES` 한 곳에 있다.
  - 트레이너 계정은 이 확인을 거치지 않는다(트레이너 필수 동의 강제는 따로 정한다).
  - 회원 앱은 이 403 을 받으면 세션을 "동의 필요" 로 바꿔 동의 화면으로 보낸다. 앱을 쓰는 사이
    문서 버전이 올라도 다음 데이터 요청에서 동의 화면으로 넘어간다.
  - 회원 의존성 없이 `RequireUser` 로만 사용자를 받는 라우트가 생기면
    `tests/test_member_consent_gate.py` 가 실패한다(예외는 그 파일의 목록에 이유와 함께 적는다).
- 국외 이전 동의는 따로 받지 않는다(#2820). 계약 이행을 위한 처리 위탁·보관이라 처리방침 공개로
  갈음한다(「개인정보 보호법」 제28조의8 제1항 제3호). 위탁·이전 표는 `docs/privacy_processing.md`.
- **선택 동의 — 위치정보 이용(#3136)**: `location` 은 가입 필수가 아니다. 회원 앱이 헬스장 찾기에서
  현재 위치를 쓰기 전에 받고, MY 에서 철회한다. 필수 판정에 들지 않아 동의하지 않아도 데이터 API 는
  막히지 않는다. 가입·재동의의 `consents` 목록으로는 받지 않는다(넣으면 422).
  - `GET /users/me/consents/{kind}` — 지금 상태. `PUT` 은 지금 버전으로 동의, `DELETE` 는 철회
    (행은 남기고 `revoked_at` 만 적는다, 기록이 없어도 200). 세 경로 모두 회원 전용(`RequireMember`,
    필수 동의가 남았으면 403 `consent_required`, 트레이너는 403)이고, `kind` 는 선택 항목(`location`)만
    받는다 — 필수 항목·모르는 값은 경로에서 **422**.
  - 응답 `{ kind, agreed, current_version, version, agreed_at, revoked_at }`. `agreed` 는 **지금 버전**에
    철회하지 않은 동의가 있는가다. 위치기반서비스 이용약관 버전(`CURRENT_VERSIONS["location"]`)이
    오르면 옛 버전에만 동의한 계정은 `false` 가 되어 앱이 다시 묻는다. 나머지는 가장 최근 기록의 값이다.
  - 서버는 좌표를 저장하지 않는다. `GET /places/nearby` 는 동의 여부를 보지 않는다 — 기본 검색 영역의
    좌표와 기기 좌표를 서버가 구분할 수 없어, 동의 전에는 앱이 기기 좌표를 읽지도 보내지도 않는다.

### 가입 연락처 형식 (#1780)

`POST /auth/register` 와 `POST /auth/trainer/register` 는 `email`·`phone` 의 **형식을 서버가
본다**. 두 앱의 가입 화면(`oncare_ui` 의 `AppInputRules`)이 같은 것을 미리 걸러 주지만, 앱을
거치지 않은 요청까지 막는 것은 여기다. 어긋나면 **422** 이고, 중복 이메일(409)보다 먼저
걸린다.

| 필드 | 기준 | 저장 |
|---|---|---|
| `email` | `AppInputRules.email` 과 **같은 규칙**(로컬@도메인.최상위, 최대 255자) | 앞뒤 공백을 잘라낸 **소문자**(#2816) |
| `phone` | `010` 으로 시작하는 숫자 11자리. 하이픈·공백은 세지 않는다. 빈 값 허용(선택) | `010-1234-5678` 한 가지 표기 |

`email-validator`(`EmailStr`)를 쓰지 않는다. 그쪽은 RFC 2606 이 시험용으로 비워 둔 최상위
도메인(`.test`·`.invalid`·`localhost`)을 막는데, 앱은 통과시키므로 기준이 갈라진다 — 실 API
E2E 가 쓰는 `@oncare.test` 계정이 가입에서 떨어졌다. 두 규칙은 **함께 고쳐야 한다.**

**이메일은 대소문자를 구분하지 않는다(#2816).** 가입·이메일 변경은 소문자로 저장하고,
로그인·가입 중복 확인·이메일 변경 중복 확인·소셜 로그인 이메일 연결·트레이너 가입은 입력을
같은 규칙(`contact_format.normalize_email`: 앞뒤 공백 제거·소문자)으로 맞춘 뒤 `lower(email)`
로 비교한다. 그래서 `Admin@…` 로 가입하면 `admin@…` 과 같은 이메일로 보고 409 이고,
`Member@ONCARE.com` 으로 가입한 사람은 `member@oncare.com` 으로도 로그인된다. DB 에도
`lower(email)` 유니크 인덱스(`uq_users_email_lower`)가 있다. 마이그레이션 `0120` 이 기존 행을
소문자로 바꾸는데, 대소문자만 다른 계정이 이미 있으면 바꾸지 않고 겹치는 이메일·계정 id 를
출력하며 멈춘다(자동 병합 없음).

관리자 지정 스크립트(`scripts/grant_admin.py`, #3037)도 같은 규칙으로 찾는다. 대소문자만 같은
계정이 여럿이면 누구도 바꾸지 않는다.

전화번호는 `01012345678` 처럼 하이픈 없이 보내도 받는다. **표기에 대해서만** 앱보다 느슨한
쪽이라 앱을 통과한 값이 서버에서 막히는 일은 생기지 않는다. 시드와 기존 프로필이 이미 하이픈
표기라 정리할 데이터는 없다.

앞자리도 함께 본다. 숫자 개수만 세던 때는 `123-4567-8901` 처럼 걸 수 없는 번호가 그대로
저장됐다 — 트레이너가 담당 회원에게 연락하려고 보는 값이라, 자릿수만 맞는 값을 받아 두면
연락할 방법이 없는 것과 같다. 01X 번호는 2021-06-30 에 서비스가 끝나 지금 쓰이는 휴대전화는
전부 `010` 이다. **헬스장 대표번호는 이 규칙을 타지 않는다** — 지역번호·안심번호(`02-332-1720`·
`0502-5552-4212`)가 섞여 있어 휴대전화 3-4-4 를 걸면 정상 번호가 422 로 막힌다.

`PUT /users/me`(프로필 수정)도 **같은 기준**이다(#1883). 전에는 이 경로만 비어 있어, 이메일을
`asdf` 로 고친 회원이 원래 주소로 다시 로그인할 수 없었다(재설정 메일도 그 주소로 가므로
스스로 되돌릴 수 없다). 전화번호도 여기서 정리가 되돌려졌다.

여기에 한 가지가 더 붙는다: **있던 전화번호는 지울 수 없다**(422). 회원 가입 화면이 전화번호를
필수로 받는데(#1634) 이 화면에서 비울 수 있으면 그 필수가 무의미해지고, 트레이너가 담당 회원에게
연락할 방법이 사라진다. 반대로 **처음부터 없던 회원**(소셜 로그인 가입자와 #1634 이전 가입자는
연락처를 넣을 자리가 없었다)에게는 요구하지 않는다 — 이름만 고치려는 사람을 전화번호로 막는
화면이 된다. 이메일은 어느 쪽이든 비울 수 없다.

`PUT /trainer/me` 의 `phone` 도 **같은 기준**이다(#1914). 트레이너는 이메일을 바꿀 수 없어
계정 잠김 위험은 원래 없었지만, 같은 종류의 값을 두 앱이 다른 기준으로 받으면 나중에 이 번호를
회원 화면에 보일 때 그 자리에서 정리부터 해야 한다. 회원 쪽과 달리 **빈 값은 언제든 허용한다** —
트레이너 가입은 전화번호를 받지 않으므로(트레이너 웹 가입 화면에 전화번호 칸이 없다) 처음부터
없는 값이다.

같은 요청의 `gym_phone` 은 이제 직접 받지 않는다(#2543 — 보내면 409). 소속을 설정하면
`GymProfile.phone` 이 그대로 들어오고, 헬스장 대표번호는 휴대전화 3-4-4 가 아니므로
(`02-332-1720`·`0502-5552-4212`) 이 기준을 걸지 않는다.

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

### 비밀번호 정책 (#1555)

새로 정하는 비밀번호는 **서버가 기준을 본다.** 전에는 가입 스키마의 `password` 가 그냥
문자열이라, 앱을 거치지 않은 요청은 빈 문자열이나 한 글자로도 계정을 만들 수 있었다. 기준을
두는 곳은 `backend/app/services/password_policy.py` 의 `check_new_password` 하나이고, 두 앱의
가입 화면(`oncare_ui` 의 `AppInputRules.signUpPassword`)이 **같은 규칙**을 미리 보여 준다.

| 항목 | 기준 |
|---|---|
| 길이 | **8~64자**. 글자 수는 코드 포인트로 센다(이모지 한 개 = 1자, 앱은 `runes`) |
| 바이트 | UTF-8 **72바이트 이하**(bcrypt 가 보는 길이). 한글은 3바이트, 이모지는 4바이트라 64자 안에서도 걸릴 수 있다 |
| 구성 | 영문(`A-Za-z`)과 숫자(`0-9`)를 **각각 1자 이상**. 전각·아라비아 숫자는 숫자로 세지 않는다 |
| 공백 | **자르지 않는다.** 공백도 비밀번호의 일부이고, 로그인도 입력 그대로 비교한다. 공백만 친 값은 영문·숫자가 없어 `password_weak` |

**적용 경로**

| 경로 | 필드 |
|---|---|
| `POST /auth/register` | `password` |
| `POST /auth/trainer/register` | `password` |
| `POST /trainer/me/password` | `new_password` (`current_password` 는 기준을 타지 않는다) |
| `POST /users/me/password` | `new_password` (`current_password` 는 기준을 타지 않는다) (#2824) |
| `POST /auth/password-reset/confirm` | `new_password` (#2824) |

**어긋나면 422** 이고, `detail[].type` 에 코드가 실린다. 앱은 문장(`msg`)이 아니라 이 코드로
자기 로케일의 문구를 고른다. 검사 순서는 빈 값 → 상한 → 약함이다.

| `type` | 뜻 | `ctx` |
|---|---|---|
| `password_empty` | 빈 문자열 | — |
| `password_too_long` | 64자 초과 또는 72바이트 초과 | `max_length`·`max_bytes` |
| `password_weak` | 8자 미만, 또는 영문·숫자 중 하나가 없음 | `min_length` |

```json
{
  "detail": [
    {
      "type": "password_weak",
      "loc": ["body", "password"],
      "msg": "비밀번호는 영문과 숫자를 포함해 8자 이상이어야 합니다.",
      "input": "abcdefgh",
      "ctx": { "min_length": 8 }
    }
  ]
}
```

트레이너 가입도 비밀번호 검사가 스키마 단계라, 약한 비밀번호로 떨어진 요청은 계정을 남기지
않는다 — 고쳐서 같은 이메일로 다시 가입할 수 있다.

트레이너 가입은 소속 헬스장을 받지 않는다(#1627). 예전의 헬스장 초대 코드(`invite_code`)는
발급 경로가 없어 걷어 냈고, 소속은 가입 뒤 헬스장 찾기로 고른다(아래). 예전 앱이
`invite_code` 를 실어 보내도 무시하고 가입시킨다.

### 트레이너 소속 헬스장 찾기 (#2543)

| Method | Path | Body / Query → Response |
|---|---|---|
| GET | `/trainer/gyms/search` | `query`(1~100자, 이름·주소), `lat`·`lng`(선택, 쌍으로) → `[{ id, name, address, lat, lng, phone, distance_meters, registered }]` |
| PUT | `/trainer/me/gym` | `{ gym_id }` — `registered=true` 인 결과 → `TrainerMe` |
| PUT | `/trainer/me/gym/kakao` | `{ kakao_place_id(숫자), name }` — `registered=false` 인 결과 → `TrainerMe` |

- 검색은 **이미 `places` 에 있는 fitness 장소를 먼저**(이름·주소 부분 일치, 최대 10), 그 뒤에
  카카오 키워드 검색 결과를 싣는다. 카카오 결과 중 이미 등록된 곳은 `registered=true` 로 한 번만
  나온다. 카카오 결과는 `category_name` 에 `스포츠시설` 이 든 곳만 — 필라테스·크로스핏 스튜디오는
  들어가고 음식점·병원은 빠진다. 카카오 키가 없거나 호출이 실패하면 등록된 결과만 200 으로 준다.
- `distance_meters` 는 좌표를 보냈을 때만 채운다(카카오 결과만). `lat`·`lng` 는 지도 핀용이다.
- `PUT /trainer/me/gym/kakao` 는 **클라이언트가 보낸 이름·주소를 저장하지 않는다.** `name` 으로
  카카오를 다시 검색해 id 가 같은 헬스장을 찾고 그 값으로 `places`·`gym_profiles`
  (`is_partner=false`, 전화만)를 만든다. 찾지 못하거나 헬스장이 아니면 **404**, 카카오를 쓸 수
  없으면 **503**. 이미 등록된 id 면 카카오를 부르지 않고 소속만 바꾼다.
- `places.id` 는 카카오 장소 id 그대로다(시드의 카카오 발견 헬스장과 같은 규칙) — 같은 헬스장을
  여러 트레이너가 골라도 한 행이다.
- `PUT /trainer/me` 로 `gym_name`·`gym_address`·`gym_hours`·`gym_phone` 을 보내면 소속 유무와
  관계없이 **409** 이고, 함께 온 다른 필드도 반영하지 않는다. 헬스장 문자열은 소속에서만 파생된다.

### 트레이너 신고와 계정 관리 (#3008)

**트레이너 운영자 승인 절차는 없다.** 공개 가입(`POST /auth/trainer/register`)으로 생긴 트레이너는
소속(`PUT /trainer/me/gym`, 실재하는 카카오 장소)을 고르면 바로 회원 앱 디렉터리·헬스장 트레이너
목록·상세에 나오고, 상담 대상이 되며, 연결 코드와 담당 요청을 쓸 수 있다. 회원 연결은 여전히 회원의
수락(담당 요청 수락·상담 뒤 연결)이나 회원이 준 연결 코드로만 된다. 예전 승인 게이트(#2825)·반려
기록 잠금(#3009)·승인 알림(#3010)은 모두 걷었다.

- 마이그레이션 `0145_trainer_reports_no_approval` 은 남아 있던 `pending`·`rejected` 를 `approved` 로
  채우고 DB 기본값을 `approved` 로 바꾼다. `trainer_profiles.verification_*` 열은 기록용으로 남기고
  어디서도 읽지 않는다. `GET /trainer/me` 에는 승인 상태가 없다.
- 같은 응답의 `is_admin: bool` 은 운영자 계정인지다 — 트레이너 웹이 `신고·계정 관리` 메뉴를
  보일지 정하고, 실제 차단은 `RequireAdmin` 이 한다. 운영자 판별은 사용자 행의 `is_admin` 이다.
- 같은 응답의 `has_password: bool`(#3039)은 비밀번호로 로그인하는 계정인지다 — 탈퇴 본인 확인에서
  현재 비밀번호 칸과 소셜 다시 로그인 중 무엇을 보일지 고른다.

**회원 신고** — `POST /trainers/{trainer_id}/reports` (`RequireMember`)

| Body | Response |
|---|---|
| `{ reason: "impersonation"\|"inappropriate_message"\|"other", memo?: string(≤200) }` | **201** `TrainerReportOut { id, status: "open", created_at }` |

- `memo` 는 앞뒤 공백을 지운다. `reason="other"` 이면 `memo` 가 필요하다(없으면 422).
- 트레이너가 아니거나 없는 id 는 404, 트레이너 계정 403, 미인증 401.
- 같은 회원이 같은 트레이너를 **처리 전(`open`)에 다시 신고하면 409**
  `detail={ code: "report_already_open", message }`. 처리된 뒤 다시 신고하는 것은 된다. 다른 회원의
  신고는 따로 쌓인다(DB 부분 유니크 `uq_trainer_reports_open`).

**운영자 엔드포인트**(모두 `RequireAdmin` — 비관리자 403, 미인증 401)

| Method | Path | Body / Query → Response |
|---|---|---|
| GET | `/admin/trainer-reports` | `status`(`open` 기본·`closed`·`all`) → `[AdminTrainerReportOut]`, 최근 순 최대 200 |
| POST | `/admin/trainer-reports/{report_id}/close` | `{ outcome: "resolved"\|"dismissed" }` → `AdminTrainerReportOut` — 없음 404, 이미 처리 409. 감사 로그 `admin.trainer_report_close` |
| GET | `/admin/trainers` | `q`(이름·이메일 부분 일치, 대소문자 무시)·`state`(`all` 기본·`active`·`suspended`) → `[AdminTrainerOut]`, 처리 전 신고 많은 순 → 최근 가입 순, 최대 100 |
| POST | `/admin/users/{user_id}/suspend` | → `AdminUserStatusOut` — 없는 계정 404, 운영자 계정(자신 포함) 409 |
| POST | `/admin/users/{user_id}/unsuspend` | → `AdminUserStatusOut` — 없는 계정 404 |

`AdminTrainerReportOut = { id, trainer_id, trainer_name, trainer_email, trainer_is_active, reason, memo,
status, created_at, resolved_at }` — 신고한 회원은 싣지 않는다. `resolved` 는 조치함, `dismissed` 는
조치 없이 넘김이다. 신고 처리는 계정 상태를 바꾸지 않는다 — 조치가 필요하면 정지를 따로 부른다.

`AdminTrainerOut = { trainer_id, name, email, gym_name, gym_address, is_active, created_at,
open_reports }`. `AdminUserStatusOut = { user_id, role, is_active, released_clients }`.

계정 정지·해제(감사 로그 `admin.user_suspend`/`admin.user_unsuspend`, `target_user_id` 에 대상):

- 정지는 `is_active=false` 와 토큰 세대 올리기다 — 기존 접근·refresh 토큰이 바로 401 이 되고
  로그인도 401 이다.
- 트레이너를 정지하면 살아 있는 담당을 모두 해제한다. 트레이너가 직접 해제할 때(`DELETE
  /trainer/clients/{id}`)와 같은 경로라 회원에게 `member_trainer_disconnected` 알림이 가고, 아직
  시작하지 않은 PT 일정이 취소되고, PT 재등록 쿠폰이 환불된다. 대기 중 담당 요청은 `cancelled` 로
  거둔다. `released_clients` 는 이번에 해제한 수다. 정지된 트레이너는 디렉터리에서도 빠진다.
- 이미 정지된 계정을 다시 정지하면 토큰 세대는 그대로이고, 남은 담당이 있을 때만 마저 해제한다.
- 해제는 계정만 되살린다. 해제했던 담당 관계는 복구하지 않는다 — 회원의 새 동의가 필요하다.
- 회원 계정을 정지해도 그 회원의 담당 관계는 건드리지 않는다.
- 운영 화면은 트레이너 웹 `/admin/reports`(`신고·계정 관리`, 운영자 계정에만 메뉴가 보인다)다.

**로그인에는 걸지 않는다.** 이 기준 이전에 만든 계정은 비밀번호가 기준에 못 미쳐도 그대로
로그인되고, 트레이너는 `POST /trainer/me/password` 로 기준에 맞는 값으로 옮길 수 있다. 로그인에
72바이트를 넘는 비밀번호가 오면 **401**(불일치)이다 — bcrypt 5 가 72바이트 초과 입력에
ValueError 를 던져 500 이 나던 것을 `verify_password` 가 불일치로 돌려준다. 그런 값으로는
애초에 가입할 수 없으므로 맞을 수 있는 비밀번호가 없다.

회원 앱의 목업 백엔드(`local_api_interceptor`)와 트레이너 웹의 목업 저장소도 같은 규칙·같은
422 모양을 따른다. **서버·`AppInputRules`·목업 세 곳은 함께 고쳐야 한다.**

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

### 재사용 감지 뒤 세션 전체 폐기 · 세션 절대 수명 (#3086)

refresh 토큰에는 로그인 세션 이름 `sid`(무작위)와 최초 인증 시각 `auth_time`(epoch 초)이 실린다. 로그인·소셜 로그인·비밀번호 변경(`POST /users/me/password`·`POST /trainer/me/password`)은 새 세션을 열고, `POST /auth/refresh` 는 두 값을 **그대로 이어** 새 토큰에 싣는다. 같은 계정이라도 로그인마다(기기마다) `sid` 가 다르다.

- **재사용 감지 = 세션 폐기.** 회전으로 폐기된 토큰이 `REFRESH_REUSE_GRACE_SECONDS`(기본 30초)를 넘겨 다시 오면, 정상 사용자와 탈취자 중 누가 먼저 회전했는지 알 수 없으므로 그 `sid` 를 `revoked_sessions` 에 적는다. 이후 그 세션의 refresh 토큰은 모두 401 이고 `auth.refresh_session_revoked` 감사 로그가 남는다. 재사용 요청의 `auth.refresh_reuse` 감사 로그 `detail` 은 `session revoked: <sid>` 다. 다른 `sid`(다른 기기)는 영향이 없다.
- **동시 갱신 유예.** 웹 탭 두 개나 응답을 받기 전에 앱이 꺼진 경우처럼 정상 사용자도 같은 토큰을 두 번 보낼 수 있다. 회전된 지 유예 안에 다시 온 토큰은 그 요청만 401 이고 세션은 이어진다(`detail`: `within grace`).
- **로그아웃·옛 세대로 폐기된 토큰의 재사용**은 이미 끊긴 세션이라 세션을 따로 폐기하지 않는다(`detail`: `already revoked: logout`·`already revoked: stale`). 폐기 사유는 `revoked_refresh_tokens.reason`(`rotated`·`logout`·`stale`)에 남는다.
- **절대 수명.** `auth_time` 으로부터 `SESSION_MAX_DAYS`(모바일, 기본 90일)·`WEB_SESSION_MAX_DAYS`(웹, 기본 30일)가 지나면 `POST /auth/refresh` 는 401 + `auth.refresh_session_expired` 감사 로그다. 회전이 내는 refresh 토큰의 만료도 이 상한을 넘지 않게 잘린다. 두 앱은 지금처럼 refresh 401 → 세션 만료 안내 → 로그인 화면으로 간다.
- **배포 전 토큰.** `sid`·`auth_time` 이 없는 토큰은 끊기지 않고 첫 회전에서 새 `sid` 와 `auth_time=지금`을 받는다.
- 접근 토큰에는 `sid` 를 싣지 않는다. 세션이 끊겨도 이미 발급된 접근 토큰은 남은 수명(`ACCESS_TOKEN_EXPIRE_MINUTES`)까지 유효하다.
- `revoked_sessions` 의 `expires_at` 은 그 세션의 절대 수명이 끝나는 시각이고, 새 폐기가 생길 때마다 만료된 행을 정리한다.

### 웹 클라이언트의 짧은 refresh 토큰 (#2828)

회원 앱 웹·트레이너 웹 빌드는 **모든 요청**에 `X-Client-Platform: web` 을 싣는다(모바일은
보내지 않는다). 서버(`app/core/client_platform.py` 의 `RequestClientPlatformMiddleware`)가
이 값을 읽어, 웹에서 온 발급(`POST /auth/login`·`POST /auth/refresh`·`POST /auth/social/{provider}`·
`POST /trainer/me/password`)에는 **refresh 토큰 수명을 `WEB_REFRESH_TOKEN_EXPIRE_DAYS`(기본 7일)**로
준다. 모바일은 `REFRESH_TOKEN_EXPIRE_DAYS`(기본 30일) 그대로다. 접근 토큰 수명은 같다.

- 웹으로 발급된 refresh 토큰에는 `cli: "web"` 클레임이 붙는다. `POST /auth/refresh` 는 이
  클레임이 있으면 헤더가 없어도 웹 수명으로 회전한다 — 헤더를 빼서 30일짜리를 다시 얻을 수 없다.
- 헤더는 **수명을 줄이는 쪽으로만** 쓴다. 클레임이 없는 예전 토큰을 웹이 회전하면 그때부터
  웹 수명이다. 값은 대소문자·앞뒤 공백을 무시하고 `web` 일 때만 웹이다.
- 응답 모양은 바뀌지 않는다. 일회용·폐기·토큰 세대 규칙도 같다.

웹 빌드는 토큰을 브라우저 **sessionStorage**(탭 단위)에만 둔다 — 탭을 닫으면 다시 로그인한다.
예전 웹 빌드가 localStorage 에 남긴 토큰은 읽지 않고 지운다(두 앱의
`core/storage/secure_token_store.dart`). 모바일은 Keychain/Keystore 그대로다.

### API 응답 보안 헤더 (#2828)

모든 API 응답에 `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: no-referrer`, `Content-Security-Policy: default-src 'none'; frame-ancestors 'none';
base-uri 'none'; form-action 'none'` 이 붙는다(`app/core/security_headers.py`, `SECURITY_HEADERS=false`
면 끈다). 운영 또는 `FORCE_HTTPS=true` 면 HSTS 도 붙는다. FastAPI 문서 화면(`/docs`·`/redoc`)은
CDN·인라인 스크립트로 그려지므로 CSP 만 뺀다. 정적 웹(두 웹 앱)의 헤더는 정적 호스팅이 붙인다.

### 비밀번호 변경과 토큰 세대 (#2766)

`jti` 폐기는 한 장씩이라 **다른 기기에 나간 토큰은 끊지 못한다.** 그래서 계정마다 토큰
세대(`users.token_version`, 처음 0)를 두고, 발급하는 접근·refresh 토큰에 그 값을 `tv`
클레임으로 싣는다. 검증하는 쪽(`deps.py` 의 모든 의존성, `POST /auth/refresh`)은 토큰의
세대가 계정의 지금 세대와 다르면 **무효한 토큰과 같이** 다룬다 — 엄격 의존성은 401,
`CurrentUser` 는 무효 토큰과 같은 폴백 규칙, refresh 는 401 + `auth.refresh_stale` 감사 로그
(그 `jti` 는 폐기 표에도 적는다). `tv` 가 없는 예전 토큰은 0세대로 읽으므로 배포만으로
끊기는 세션은 없다. 정수가 아닌 `tv` 는 거부한다.

`POST /trainer/me/password` · `POST /users/me/password`(회원, #2824) 가 성공하면 세대를 1 올려 **그 전에 발급된 이 계정의 토큰이 모두
무효**가 된다. 요청한 기기도 예외가 아니어서, 응답에 새 세대 토큰 한 쌍을 담는다.

```json
{ "status": "changed", "access_token": "…", "refresh_token": "…", "token_type": "bearer" }
```

클라이언트는 이 토큰으로 저장소를 바꿔야 로그아웃되지 않는다(트레이너 웹
`TrainerPasswordChangeResult`, 회원 앱 `SessionController.adoptReissuedTokens`). 다른 기기는 다음 요청에서 401 → refresh 401 → 세션 만료
안내와 함께 로그인 화면으로 간다. 변경이 실패하면(400·422) 세대는 그대로다.
비밀번호 재설정(`POST /auth/password-reset/confirm`)도 같은 칸을 올린다 — 다만 새 토큰은
주지 않고 새 비밀번호로 다시 로그인하게 한다(아래).

### 회원 비밀번호 변경 (#2824)

`POST /users/me/password` (`RequireMember`, rate limit 버킷 `member-password-change`)

```json
{ "current_password": "…", "new_password": "…" }
```

트레이너 `POST /trainer/me/password` 와 같은 규약이다. 응답도 같은 `PasswordChanged`(위).

| 상황 | 응답 |
|---|---|
| 성공 | 200 + 새 토큰 한 쌍. 세대 +1 |
| 현재 비밀번호 불일치 | **400** `현재 비밀번호가 일치하지 않습니다.` (401 이 아니다 — 토큰은 유효) |
| 새 비밀번호가 지금과 같음 | 400 |
| 새 비밀번호 기준 미달 | 422 `password_weak`·`password_too_long`·`password_empty` |
| 소셜 로그인 전용 계정(비밀번호 없음) | **409** (실패 잠금에 세지 않는다) |
| 현재 비밀번호를 `LOGIN_LOCKOUT_SECONDS`(900초) 안에 `PASSWORD_CHANGE_MAX_FAILURES`(5)번 틀림 | 남은 시간 동안 **429** + `Retry-After`. 잠긴 동안에는 맞는 비밀번호도 확인하지 않는다(#3087) |

실패 잠금은 사용자 id 단위라 IP 를 바꿔도 같은 버킷이고, 트레이너와 같은 키·설정값을 쓴다
(`PasswordChangeGuard`). 틀린 시도는 감사 로그 `auth.password_change`(실패, `current_password_mismatch`)에
남고, 현재 비밀번호가 맞으면 실패 기록을 지운다. 회원 앱은 429 를 "시도가 너무 많아요" 안내로 보여 준다.

`GET /users/me/profile` 의 `has_password`(bool)가 false 면 소셜 로그인 전용 계정이다. 회원 앱은
이 값으로 MY 의 비밀번호 변경 대신 안내를 보여 준다.

### 가입 이메일 인증 (#3038)

가입하는 사람이 그 이메일의 주인인지 계정을 만들기 **전에** 확인한다. 예전에는 형식만 봐서, 남의
주소로 먼저 가입하면 그 주소를 믿는 기능(관리자 지정·재설정 메일·소셜 연결)이 가입한 사람 편이 됐다.

**1) 코드 받기** — `POST /auth/register/email-code`

```json
{ "email": "member@example.com", "purpose": "member_signup" }
```

→ **202** `{ "expires_in_minutes": 10, "resend_after_seconds": 60 }`

- 응답은 가입 여부와 무관하게 **같다**. 이미 가입된 주소에는 코드 대신 "이미 계정이 있다(로그인·비밀번호
  재설정 안내)" 메일이 간다 — 주인만 그 차이를 안다.
- 코드는 6자리 숫자, `SIGNUP_EMAIL_CODE_MINUTES`(10분) 동안 한 번. 새 코드를 받으면 앞의 코드는 닫힌다.
  표에는 서버 비밀값으로 만든 HMAC 만 남는다(`email_verification_codes`).
- 코드는 (소문자 이메일, 용도)에 묶인다. 회원 코드로 트레이너 가입을 할 수 없고, 화면에서 이메일을 바꾸면
  새 코드가 필요하다.
- 형식이 틀린 이메일·모르는 용도 422, 시도 한도 429, 서버에 메일 발송 수단이 없으면(운영인데 SMTP 가 빔)
  **503** `"지금은 인증 메일을 보낼 수 없습니다. 잠시 후 다시 시도해 주세요."`.

**2) 가입** — `POST /auth/register`·`POST /auth/trainer/register` 본문에 `email_code` 를 더한다.

| 상황 | 응답 |
|---|---|
| 이미 가입된 이메일 | **409** (코드보다 먼저 본다) |
| `email_code` 없음·빈 값 | **422** `detail={ code: "email_code_required", message }` |
| 틀림·만료·사용됨·다른 용도·틀린 횟수 초과 | **400** `detail={ code: "invalid_email_code", message }` — 까닭은 가르지 않는다 |
| 맞음 | **201**, `users.email_verified_at` 에 확인 시각 |

한 코드로 `SIGNUP_EMAIL_CODE_MAX_ATTEMPTS`(5)번 틀리면 그 코드는 맞는 값도 받지 않는다 — 6자리의 경우의
수를 묶는 장치다. 틀린 횟수는 가입이 실패해도 남는다. 코드 사용 표시는 계정 생성과 한 트랜잭션이라,
가입이 다른 이유로 실패하면 코드도 살아 있다.

`SIGNUP_EMAIL_VERIFICATION=false` 면 가입이 코드를 보지 않는다(백엔드 테스트·E2E 러너처럼 메일함이 없는
환경 전용). **운영(`ENV=prod`)에서는 끌 수 없다** — 설정 단계에서 기동을 거부한다. 데모(앱 mock)는 코드
`000000` 을 받는다.

### 탈퇴·로그인 이메일 변경 전 본인 확인 (#3039)

탈퇴(`DELETE /users/me`·`DELETE /trainer/me`)와 로그인 이메일을 **실제로** 바꾸는 `PUT /users/me` 는
접근 토큰만으로 처리하지 않는다. 토큰이 새거나 잠금 없는 기기를 남이 들면 계정을 지우거나 이메일을 자기
주소로 바꿔(재설정 메일까지 받아) 가져갈 수 있었다. 본문에 다음 중 하나를 더한다.

| 계정 | 보낼 값 |
|---|---|
| 비밀번호 있음(`has_password=true`) | `current_password` |
| 소셜 로그인 전용 | `social_provider` + `social_token` — 그 provider 로 방금 다시 로그인해 받은 토큰. 검증한 provider 계정이 **이 사용자에게 연결된** 것이어야 한다 |

실패는 모두 **400** 이다 — 토큰은 유효하므로 앱이 로그아웃으로 오인하면 안 된다(비밀번호 변경과 같은 규약).

| `detail.code` | 뜻 |
|---|---|
| `reauth_required` | 확인 값을 보내지 않았다(옛 빌드). 잠금에 세지 않는다 |
| `invalid_current_password` | 현재 비밀번호가 틀렸다 |
| `invalid_reauth` | 소셜 토큰 검증 실패, 또는 다른 사람의 provider 계정 |

연속 실패는 사용자 id 단위로 잠근다(429, 위 시도 제한 표). 실패는 감사 로그 `account.reauth_failed` 에 남는다.

`PUT /users/me` 는 이메일이 실제로 바뀔 때만(대소문자 무시 비교) 확인한다 — 이름·연락처만 고치는 저장은
예전과 같다. 중복 확인(409)은 본인 확인 **뒤**다(확인 없이 409 를 주면 가입 여부를 알아낼 수 있다). 이메일을
바꾸면 토큰 세대가 올라 다른 기기가 모두 로그아웃되고, 응답 `ProfileView` 의 `access_token`·`refresh_token`
(그 밖의 응답에서는 `null`)으로 이 기기가 이어 쓴다. **옛 주소로** 변경 안내 메일이 간다(새 주소는 가려서).

### 비밀번호 재설정 (#2824)

로그아웃 상태에서 메일로 계정을 되찾는 길. 회원·트레이너 공용이다.

**1) 요청** — `POST /auth/password-reset/request`

```json
{ "email": "member@example.com" }
```

→ **202** `{ "status": "requested", "expires_in_minutes": 30 }`

- **계정이 있든 없든 응답이 같다.** 가입되지 않은 이메일·쉬는 계정·소셜 로그인 전용 계정에는
  아무것도 보내지 않지만 응답으로는 구분할 수 없다(이메일 열거 방지). 실제로 보냈는지는 감사
  로그 `auth.password_reset_request` 의 `success` 에만 남는다.
- 메일에는 일회용 코드(`XXXX-XXXX-XXXX-XXXX`, 헷갈리는 글자를 뺀 32글자 16자 = 80비트)와,
  화면 주소가 설정돼 있으면 링크(`<PASSWORD_RESET_MEMBER_URL|PASSWORD_RESET_TRAINER_URL>?token=<코드>`)가
  실린다. 계정 역할로 주소를 고른다.
- 코드는 `PASSWORD_RESET_TOKEN_MINUTES`(기본 30분) 동안 한 번만 쓸 수 있다. 서버는 해시만
  저장한다(`password_reset_tokens`). 새로 요청하면 앞서 보낸 코드는 닫힌다.
- 시도 제한: IP 별 분당 한도(버킷 `auth-password-reset-request`) + 이메일 하나당
  `PASSWORD_RESET_EMAIL_PER_WINDOW`회/`PASSWORD_RESET_EMAIL_WINDOW_MINUTES`분(기본 3회/15분).
  이메일 한도는 계정이 없는 주소도 똑같이 세므로 429 로 가입 여부가 드러나지 않는다.
- 서버가 메일을 보낼 수 없으면 **503**(아래 메일 발송 설정).

**2) 확인** — `POST /auth/password-reset/confirm` (버킷 `auth-password-reset-confirm`)

```json
{ "token": "ABCD-EFGH-JKMN-PQRS", "new_password": "…" }
```

→ 200 `{ "status": "reset" }`

- 코드의 하이픈·공백·대소문자는 서버가 정규화한다.
- 코드가 없음·만료·이미 사용 → 모두 **400** `{"detail": {"code": "invalid_reset_token", "message": "…"}}`.
- 새 비밀번호는 가입과 같은 기준(422).
- 성공하면 세대가 1 올라 **모든 기기의 세션이 끊긴다**(#2766). 새 토큰은 주지 않는다 — 새 비밀번호로
  다시 로그인한다.

**메일 발송 설정**

| 환경변수 | 기본 | 뜻 |
|---|---|---|
| `MAIL_PROVIDER` | `auto` | `smtp`·`log`·`auto`(SMTP_HOST 와 MAIL_FROM 이 있으면 smtp, 없으면 log) |
| `MAIL_FROM` | — | 발신 주소(`On-Care <no-reply@…>` 형식 가능) |
| `SMTP_HOST`·`SMTP_PORT`·`SMTP_USERNAME`·`SMTP_PASSWORD` | —·587·—·— | SMTP 서버. AWS SES 는 SES SMTP 엔드포인트·SMTP 자격 증명을 넣는다 |
| `SMTP_STARTTLS`·`SMTP_SSL` | true·false | 587 STARTTLS / 465 TLS |
| `PASSWORD_RESET_MEMBER_URL`·`PASSWORD_RESET_TRAINER_URL` | — | 메일 링크가 여는 재설정 화면. 비우면 코드만 보낸다 |

`log` 는 보내지 않고 서버 로그에 남긴다(코드 본문은 DEBUG). 개발·스테이징에서는 이것으로도
재설정이 켜지지만, **운영(`ENV=prod`)에서 발송 수단이 없으면 재설정 요청은 503** 이고 기동 로그에
오류가 남는다. `MAIL_PROVIDER=smtp` 인데 `SMTP_HOST`·`MAIL_FROM` 이 비면 설정 오류로 기동이 멈춘다.

접근 토큰 수명은 기본 **60분**(`ACCESS_TOKEN_EXPIRE_MINUTES`, #2913), refresh 는 30일이다. 두 앱은
401 을 받으면 `POST /auth/refresh` 로 새 쌍을 받아 요청을 다시 보내므로 수명이 짧아도 화면은 끊기지
않는다.

### 시도 제한과 클라이언트 IP (#2815)

IP 단위 한도와 감사 로그 IP 는 같은 함수(`app/core/client_ip.py`)로 읽는다. 요청자가 넣은
`X-Forwarded-For` 는 믿지 않고, 앞단 프록시가 **덧붙인** 값만 본다 — 헤더를 오른쪽에서
`TRUSTED_PROXY_HOPS` 번째 값이 클라이언트 IP 다(미설정이면 운영 1, 그 밖 0 = 소켓 주소).
헤더 왼쪽을 바꿔 보내도 한도 버킷과 감사 로그 IP 가 바뀌지 않는다.

IP 를 바꿔 가며 한 계정을 노리는 시도는 계정 쪽 버킷이 막는다. 모두 기존과 같은
**429** `{"detail": "요청이 너무 많습니다. …"}` + `Retry-After` 다.

| 대상 | 버킷 | 한도 |
|---|---|---|
| `POST /auth/login` | IP | 분당 `RATE_LIMIT_AUTH_PER_MINUTE`(10) |
| `POST /auth/login` | **이메일(대소문자 무시) 연속 실패** | `LOGIN_LOCKOUT_SECONDS`(900초) 안에 `LOGIN_MAX_FAILURES`(5)번 틀리면 남은 시간 동안 429. 잠긴 동안에는 비밀번호를 확인하지 않는다. 성공하면 실패 기록을 지운다. 없는 이메일도 같이 센다 |
| `POST /trainer/pairing-code/preview`·`POST /trainer/pairing-code` | IP + **트레이너 id** | 각각 분당 10, 트레이너 id 는 하루 `PAIRING_REDEEM_PER_DAY`(30) 도 함께. 두 엔드포인트가 한 버킷 |
| `POST /auth/register/email-code` | IP + **이메일** + (이메일, 용도) | IP 는 분당 10. 같은 이메일은 `SIGNUP_EMAIL_CODE_WINDOW_MINUTES`(60분) 안에 `SIGNUP_EMAIL_CODE_PER_WINDOW`(5)번, 같은 (이메일, 용도)는 `SIGNUP_EMAIL_CODE_RESEND_SECONDS`(60초)에 한 번. 가입된 주소도 똑같이 센다(#3038) |
| `DELETE /users/me`·`DELETE /trainer/me`·이메일을 바꾸는 `PUT /users/me` | **사용자 id 연속 실패** | 본인 확인을 `LOGIN_LOCKOUT_SECONDS`(900초) 안에 `PASSWORD_CHANGE_MAX_FAILURES`(5)번 틀리면 남은 시간 동안 429. 값을 아예 보내지 않은 400 은 세지 않는다(#3039) |
| `POST /auth/register`·`POST /auth/trainer/register` | IP + **이메일(대소문자 무시)** | IP 는 분당 10. 같은 이메일은 시간당 `REGISTER_PER_EMAIL_PER_HOUR`(5) — 성공·409 를 가리지 않고 세고, 두 가입이 한 버킷이다(#2913). 409 문구는 그대로 |
| `POST /trainer/me/password`·`POST /users/me/password` | IP + **사용자 id 연속 실패** | IP 는 분당 10. 현재 비밀번호를 `LOGIN_LOCKOUT_SECONDS`(900초) 안에 `PASSWORD_CHANGE_MAX_FAILURES`(5)번 틀리면 남은 시간 동안 429(잠긴 동안 비밀번호를 확인하지 않는다). 틀린 시도는 감사 로그 `auth.password_change`(실패)에 남고, 성공하면 실패 기록을 지운다(#2913). 회원·트레이너가 같은 키 규칙·설정값을 쓴다(#3087) |

한도 저장소는 프로세스 메모리라 인스턴스가 여럿이면 한도도 그 배수가 된다. 운영 인스턴스가
하나를 넘게 되면 공유 저장소 구현으로 바꾼다(`app/core/rate_limit.py`).

### 의존성 네 갈래

엔드포인트가 어떤 의존성을 쓰느냐로 동작이 갈린다 (`app/api/deps.py`).

| 의존성 | 토큰 없을 때 | 역할 제한 |
|---|---|---|
| `CurrentUser` | 환경에 따라 데모 사용자 폴백 또는 401 (아래) | 트레이너 계정이면 **403**. 필수 동의가 남은 회원이면 403 `consent_required` (#3088) |
| `RequireUser` | 401 | 없음 |
| `RequireMember` | 401 | 회원만. 트레이너면 403. 필수 동의가 남았으면 403 `consent_required` (#3088) |
| `RequireTrainer` | 401 | 트레이너만. 회원이면 403 |
| `RequireAdmin` | 401 | `is_admin` 아니면 403 |

읽기 화면은 `CurrentUser`, 쓰기·삭제는 `RequireMember`, 트레이너 앱(`/v1/trainer/*`)은
`RequireTrainer` 를 쓴다. **데모 폴백이 있는 것은 `CurrentUser` 하나뿐**이고 나머지는 모두
유효 토큰을 요구한다 — 회원 데모 사용자가 트레이너 엔드포인트나 쓰기 경로로 새어 들어가지
않게 하기 위해서다.

회원의 `POST`·`PUT`·`PATCH`·`DELETE` 는 저장하지 않는 계산 요청(`POST /diet/nutrition`,
`POST /exercise/calories`, `POST /diet/analyze`)까지 포함해 전부 `RequireMember` 다(#2831).
만료된 토큰으로 기록을 저장하면 데모 계정에 쌓이는 대신 **401** 이 나고, 회원 앱은 refresh 뒤
같은 요청을 다시 보낸다. 새 쓰기 라우트가 `CurrentUser` 를 쓰면
`tests/test_write_route_auth_guard.py` 가 실패한다(예외는 그 파일의 목록에 이유와 함께 적는다).

### 데모 폴백은 환경으로 갈린다

`CurrentUser` 에 유효한 토큰이 없을 때의 동작은 설정이 정한다 (`app/core/config.py`).

```python
demo_fallback_enabled = allow_demo_fallback and not is_prod
```

- **기본값은 꺼짐**(#2821) — `ALLOW_DEMO_FALLBACK` 을 주지 않으면 어느 환경이든 401 이다. 환경변수를
  빠뜨린 배포 서버가 로그인 없는 요청을 데모 회원으로 처리하지 않게 하려는 것이다.
- **로컬 개발** — `.env.example` 이 `ALLOW_DEMO_FALLBACK=true` 로 켠다. 켜면 dev / staging 에서 데모
  사용자(`user-7d4e9a2c5f18`)로 응답한다. 프론트가 `USE_MOCK_API=false` 로 전환할 때 로그인 없이도
  화면이 뜨게 하려는 것이다. 켠 채 기동하면 WARN 로그가 남는다.
- **prod** — `ALLOW_DEMO_FALLBACK` 값과 무관하게 **항상 비활성**이고 401 을 낸다.
- 지금 어느 쪽으로 떠 있는지는 `GET /healthz` 의 `demo_fallback` 으로 읽는다. 배포 워크플로가
  배포 직후 이 값과 `env` 를 확인한다.

운영은 이 외에도 기동 시점에 막는 것이 있다(`_guard_prod_secrets`): 기본 `JWT_SECRET`,
CORS 와일드카드, 기본·짧은 `DEMO_LOGIN_PASSWORD` 로 켠 데모 시드, `AUTO_CREATE_TABLES=true`
는 모두 기동을 거부한다.

### 역할 분리

`users.role` 이 `member | trainer` 다. 두 앱은 **완전히 별개의 계정**을 쓴다 — 한 사람이 회원과
트레이너를 겸하지 않는다. 그래서 회원 API 는 트레이너 토큰을 403 으로 막고, 그 반대도 같다.
자세한 것은 [`docs/TRAINER_DOMAIN.md`](docs/TRAINER_DOMAIN.md).

### 사용자 id

**문자열**이다(`user-7d4e9a2c5f18`). 정수가 아니다. 데모 시드도 같은 규약을 따른다.

### 감사 기록 (#2830)

응답 형태는 바뀌지 않는다. 서버가 아래 행위를 `audit_logs` 에 남긴다(누가·누구의·무엇을·언제, 본문 없음).

- `GET /trainer/clients/{member_id}/…` 중 회원의 건강정보를 읽는 경로 — `trainer.client_read`,
  `resource` 는 `diet`(`/diet`·`/diet/days`·`/diet/photos/{id}`·`/diet-advice`·`/diet-recommendations`),
  `exercise`(`/exercise/weeks`·`/exercise-week`·`/exercise-advice`·`/history`·`/records/span`),
  `body`(`/health-profile`), `report`(`/report`·`/report/summary`·`/report/member-feedback`·`/report/goals`·`/reports/sent`).
  같은 (트레이너, 회원, 자원)은 10분(설정 `AUDIT_READ_DEDUPE_MINUTES`) 안에 한 번만 남는다. 404 로 끝나는 요청은 남지 않는다.
- 동의 발급 `consent.grant`(연결 코드 `pairing`·담당 요청 수락 `invite`·상담 신청 `consultation`),
  철회 `consent.revoke`(`DELETE /me/coach`·`/me/coach/trainer` 는 회원, `DELETE /trainer/clients/{id}` 는 트레이너),
  탈퇴 `account.withdraw`(`DELETE /users/me`·`DELETE /trainer/me`), 비밀번호 변경 `auth.password_change`
  (`POST /trainer/me/password`), 로그인 이메일 변경 `account.email_change`(#3039, 이메일 원문 없음).
  본 작업과 같은 트랜잭션이고 계정이 지워져도 남는다.
- 본인 확인 실패 `account.reauth_failed`(`detail` 에 `action=delete_account|change_email`·`via=password|social`),
  관리자 지정·해제 `admin.grant`·`admin.revoke`(`target_user_id` 에 대상, `scripts/grant_admin.py`), 가입 인증 코드
  요청 `auth.signup_code_request`·확인 실패 `auth.signup_code_verify`(이메일은 키를 둔 해시만).
- 보존 기간: 접속 기록 365일(`AUDIT_RETENTION_DAYS`), 열람·동의·탈퇴 기록 730일
  (`AUDIT_SENSITIVE_RETENTION_DAYS`). 서버 기동 때 지난 기록을 정리한다.

## 도메인 핵심 (놓치면 안 되는 차별점)

On-Care 의 식단은 칼로리뿐 아니라 **나트륨(sodium_mg)·당류(sugar_g)** 가 1급 지표다. 근거는
WHO 나트륨 권고와 **2025 한국인 영양소 섭취기준**(첨가당 총에너지 10% 이내, 나트륨 만성질환
위험감소섭취량)이고, 그 원문이 AI 코치의 공개 근거 문서로 적재된다. 예전에 이 자리에 있던
**고혈압·당뇨 위험군 특화 / DASH 식단 관점** 서술은 폐기된 스타트 단계의 타깃이다 — 지금
타깃은 PT 를 이용하는 회원과 이들을 관리하는 트레이너다(#1652).
