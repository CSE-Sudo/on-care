# 트레이너 도메인 · 회원↔트레이너 데이터 공유

> 트레이너 웹 백엔드와 회원측 "내 담당 코치" 미러의 설계·계약 문서.
> 회원 앱 계약은 [`API_CONTRACT.md`](../API_CONTRACT.md)를, 프론트 구조는
> [`frontend/flutter/docs/STRUCTURE.md`](../../frontend/flutter/docs/STRUCTURE.md)를 참고.
>
> 대상 작업: 트레이너 도메인(#249~#253), 회원측 미러(#254), 리뷰 후속(#261).

## 1. 한 줄 요약

트레이너 웹과 회원 앱은 **완전히 분리된 계정**(`users.role = 'member' | 'trainer'`)이지만
**같은 회원 데이터를 공유**한다. 트레이너가 담당하는 회원은 별도 복제본이 아니라 **실제
회원 User**이며, 트레이너 API는 회원이 회원 앱에서 남긴 `DietEntry`·`RoutineHistory`를
**그대로 읽어** 로스터를 집계한다. 별도 동기화 파이프라인이 없어 데이터가 어긋날 여지가
없다.

> **이름** — 화면과 문서는 담당 대상을 "회원"이라 부른다(#1676). 코드·API·테이블 이름은
> `client` 그대로다: `TrainerClient`, `/trainer/clients`, `trainer_clients`. 같은 대상을
> 가리키는 두 표기이니, 문서를 고칠 때 식별자까지 따라 바꾸지 않는다.

```text
회원 앱 ──기록──▶ diet_entries / routine_history ◀──조회── 트레이너 웹
                        (단일 원본, 실시간 공유)
```

## 2. 역할과 인증

- `users.role`: `member`(회원 앱) | `trainer`(트레이너 웹). 서버 기본값 `member`.
- 두 앱은 로그인 계정이 다르다. **앱 내 역할 전환 기능은 없다.**
- 인증 의존성(`app/api/deps.py`):
  - `get_current_user` — 토큰 있으면 그 사용자, 없으면 데모 회원(회원 앱 계약 유지).
    단, 비활성 계정은 기존 토큰을 포함해 401이며, **trainer 역할이 회원 데이터
    엔드포인트로 새어들지 않도록** 트레이너 계정엔 403.
  - `RequireTrainer` / `require_trainer` — 트레이너 전용 라우터 가드(회원 계정 403).
  - `RequireMember` / `require_member` — 회원 전용 라우터 가드.

## 3. 데이터 모델 (마이그레이션 `0012_trainer_domain`)

| 테이블 | 역할 |
|---|---|
| `users.role` | 계정 역할 컬럼(member\|trainer), 인덱스 |
| `trainer_profiles` | 트레이너 프로필(전문분야·경력·소속 짐) |
| `trainer_clients` | 트레이너↔회원 담당 링크(로스터의 정의) |
| `trainer_routines` | 트레이너/AI가 회원에게 배정한 루틴. PT 일정에 붙인 개인운동은 `schedule_id`·`status='scheduled'`·`delivery_kind` 를 갖는다(`0090_routine_schedule_link`, #2223) |
| `trainer_client_memos` | 트레이너가 회원별로 남긴 메모(직접 작성 + 채팅 인사이트, `0036_trainer_memos`) |
| `trainer_follow_up_tasks` | 트레이너가 회원별로 남긴 후속 관리 할 일(예정일·완료 상태, `0047_trainer_follow_up_task`) |
| `trainer_program_drafts` | 트레이너가 저장해 둔 프로그램 초안(세션 배열, 회원과 묶이지 않음, `0038`+`0039`) |
| `routine_history` | 회원 운동 완료 기록(회원 앱·PT 세션 공용 원본) |
| `chat_messages` | 트레이너↔회원 1:1 채팅 |
| `trainer_schedule` | 트레이너 오늘 타임라인(예약→수업→기록 루프) |

### 담당 링크 제약 (`trainer_clients`)

- `UNIQUE(trainer_id, member_id)` — 같은 트레이너에 같은 회원 중복 배정 금지.
- **`UNIQUE(member_id) WHERE active`** (partial unique index
  `uq_trainer_client_active_member`) — 회원측 API가 "현재 담당 코치 **1명**"을 전제하므로,
  회원당 **active 링크는 최대 1개**로 강제한다. 휴면(`active=false`) 이력은 여러 개 허용.
  이 인덱스는 `0012` 테이블 생성을 수정하지 않고 별도 `0013_trainer_active_coach_uq`
  마이그레이션으로 추가한다(이미 `0012`가 적용된 DB 에서도 확실히 생성되도록).

> 정책이 복수 담당으로 바뀌면 이 인덱스를 제거하고 회원측 코치·채팅·루틴 API를
> **목록 기반**으로 바꿔야 한다(현재는 단일 담당 가정).

### 담당 관계(`active`)와 관리 상태(`dormant`)는 다른 축 (#707)

트레이너 웹의 활성/휴면 배지는 `active` 가 아니라 **`dormant`** 다
(`0037_client_dormant`).

| 컬럼 | 뜻 | 누가 바꾸나 | 내려가면 |
|---|---|---|---|
| `active` | 담당 관계가 살아 있는가 | 상담 승인·헬스장 해제·탈퇴 등 시스템 | 회원측 '내 코치'가 사라지고 예약·코치 조회가 막힌다 |
| `dormant` | 트레이너가 지금 적극적으로 관리하는가 | 트레이너가 화면에서 직접 | 배지만 휴면이 된다. 담당·기록·식단·운동·채팅은 그대로 |

로스터의 `active` 필드는 둘의 AND 다(`trainer_service._roster_active`) — 담당이
해제된 과거 회원의 카드는 예나 지금이나 휴면으로 보여야 하기 때문이다. 그래서
담당이 이미 해제된 회원의 상태 전환은 409 다(되돌려 봐야 로스터가 휴면 그대로라
"저장했는데 그대로"가 된다). 담당 재배정은 상담 승인 경로의 몫이다.

### 트레이너 헬스장 소속 정책 (`0020_gym_profiles_trainer_fk`)

- 트레이너는 현재 **헬스장 한 곳**에만 소속한다. `TrainerProfile.gym_id`는
  `places.id`를 참조하는 단일 nullable FK이며, 복수 소속 관계 테이블은 두지 않는다.
- `gym_id`는 기존 프로필과 헬스장 삭제를 안전하게 처리하기 위해 nullable이다.
  헬스장 `Place`가 삭제되면 `ON DELETE SET NULL`로 소속만 해제되고 트레이너
  계정은 남는다. 트레이너 `User`가 삭제되면 프로필은 `ON DELETE CASCADE`로
  함께 삭제된다.
- 상담 요청은 `gym_id`가 실제로 존재하는 `Place`를 가리키고 그 장소의
  `category == "fitness"`일 때만 트레이너를 유효한 대상으로 인정한다. FK만으로는
  다른 카테고리를 막을 수 없어 `consultation_service._validate_target()`에서 검증한다.
- 소속 변경 이력은 **현재 보존하지 않는다**. 프로필의 `gym_id`를 교체하며,
  이력·복수 소속이 실제 요구되면 별도 관계 테이블로 확장한다.
- 관계 판단의 기준은 `gym_id`다. 기존 `gym_name`, `gym_address`, `gym_hours`,
  `gym_phone`은 트레이너 웹의 `gym {name, address, hours, phone}` 계약을
  유지하기 위한 호환 필드로 당분간 남겨 둔다.
- `gym_id`는 `PUT /trainer/me/gym`으로 설정·변경하고 `DELETE /trainer/me/gym`으로
  해제한다(#452). 시드(`seed_gyms.py`의 `gym_name` 이름 매칭 백필)는 기존 데이터를
  이어 주는 용도로 남는다.
- **호환 문자열 동기화 기준**: `gym_id`가 있으면 `gym_name`·`gym_address`·
  `gym_hours`·`gym_phone`은 소속 `Place`/`GymProfile`에서 파생된 사본이다. 소속을
  설정·변경하면 서버가 덮어쓰고, 해제하면 비운다. 그 동안 `PUT /trainer/me`로
  문자열만 따로 바꾸는 요청은 **409**다 — 소속과 화면이 어긋나기 때문이다.
  `gym_id`가 없는(레거시·해제 상태) 프로필에서는 예전처럼 직접 입력한다.

## 4. 트레이너 API (`/v1/trainer/*`, RequireTrainer)

| Method | Path | 설명 |
|---|---|---|
| GET | `/trainer/me` | 내 트레이너 프로필 |
| PUT | `/trainer/me` | 프로필 부분 수정(보낸 필드만; 이름/이메일은 계정 소관) |
| PUT | `/trainer/me/gym` | 소속 헬스장 설정·변경(fitness `Place`만; 없으면 404) |
| DELETE | `/trainer/me/gym` | 소속 해제(원래 없어도 200) |
| POST | `/trainer/me/password` | 비밀번호 변경(현재 비밀번호 확인) |
| GET | `/trainer/me/settings` | 알림 수신 설정 |
| PUT | `/trainer/me/settings` | 알림 수신 설정 부분 수정 |
| GET | `/trainer/clients` | 회원 로스터(회원 실데이터 집계) — 기본 50명, `after_id` 로 이어 받기 (#980) |
| PUT | `/trainer/clients/{member_id}/status` | 활성/휴면 전환(담당 관계는 유지, #707) |
| GET | `/trainer/clients/{member_id}/diet?date=` | 해당 회원의 실제 식단 기록 |
| GET | `/trainer/clients/{member_id}/diet/days?from=&to=` | 기간의 날짜별 식단 합계 — 회원 API `GET /diet/days` 와 같은 응답. 기간 그래프가 쓴다. `from` 생략 시 그 회원의 첫 기록일부터 (#2236) |
| GET | `/trainer/clients/{member_id}/records/span` | 그 회원이 식단·운동을 처음 남긴 날 — `전체` 그래프의 시작점 (#2079) |
| GET | `/trainer/clients/{member_id}/exercise/weeks?from=&to=` | 구간이 걸친 주들의 운동 집계 — 회원 API `GET /exercise/weeks` 와 같은 응답. `전체` 그래프가 쓴다 (#2247) |
| GET | `/trainer/clients/{member_id}/history` | 해당 회원 운동 기록(최신순) |
| DELETE | `/trainer/me` | 트레이너 탈퇴 — 담당 회원에게 알린 뒤 계정과 딸린 데이터 삭제 (#505) |
| GET | `/trainer/clients/{member_id}/routines` | 배정 루틴 |
| POST | `/trainer/clients/{member_id}/routines` | 루틴 배정(단건) |
| POST | `/trainer/clients/{member_id}/program` | 프로그램 배정 — 세션당 루틴 한 건 (#709). `delivery_kind`·`trainer_message`·`start_date`·`active_days` 로 프로그램 만들기의 `개인운동만` 전송을 받는다. `active_days` 만큼만 회원 목록에 걸어 둔다(`active_from`~`ended_on`, #2161) — `개인운동만` 은 7 을 보내 보낸 날부터 한 주 동안 걸리고, 다음 주 분은 트레이너가 다시 보낸다 (#2223) |
| POST | `/trainer/clients/{member_id}/program-schedule` | 프로그램 탭 `일정 추가` — 배정과 PT 일정 등록을 한 트랜잭션으로, `client_request_id` 로 재시도 멱등 (#1580). 고른 시간대와 겹치는 예정 세션에 연결하고 없으면 새 일정, 여럿이면 `session_id` 필수(아니면 409 + 후보) (#1581) |
| GET | `/trainer/schedule/{session_id}/routines` | 그 PT 일정에 붙어 있는(아직 보내지 않은) 개인운동 (#2223) |
| PUT | `/trainer/clients/{member_id}/routines/{routine_id}` | 루틴 부분 수정(이름·시간·종류·사유) |
| DELETE | `/trainer/clients/{member_id}/routines/{routine_id}` | 루틴 철회 |
| GET | `/trainer/clients/{member_id}/memos` | 회원 메모 목록(최신순) |
| POST | `/trainer/clients/{member_id}/memos` | 메모 작성 (`insight_id?` 로 채팅 인사이트 중복 방지) |
| PUT | `/trainer/clients/{member_id}/memos/{memo_id}` | 메모 본문 수정 |
| DELETE | `/trainer/clients/{member_id}/memos/{memo_id}` | 메모 삭제 |
| POST | `/trainer/schedule/recurring/preview` | 반복 설정이 만들 회차와 겹치는 기존 일정 |
| POST | `/trainer/schedule/recurring` | 주간 반복 회차 일괄 등록(전부 아니면 전무, 409 에 충돌 목록) |
| POST | `/trainer/schedule/{session_id}/cancel` | 일정 취소 기록(`source`=member\|trainer\|other, `reason?`) |
| POST | `/trainer/schedule/{session_id}/no-show` | 노쇼 기록 |
| GET | `/trainer/clients/{member_id}/follow-ups?include_completed=` | 회원 후속 관리 할 일(예정일 순, 기본 미완료) |
| POST | `/trainer/clients/{member_id}/follow-ups` | 후속 관리 등록 (`client_request_id?` 로 재시도 멱등) |
| GET | `/trainer/follow-ups?scope=due\|open` | 내 할 일 — `due` 는 오늘 예정 + 기한 지난 미완료 |
| PUT | `/trainer/follow-ups/{task_id}` | 할 일 수정(내용·예정일) |
| POST | `/trainer/follow-ups/{task_id}/complete` | 완료 처리(반복 요청 멱등) |
| GET | `/trainer/programs` | 저장한 프로그램 초안 목록(요약, 최근 수정 먼저) |
| POST | `/trainer/programs` | 프로그램 초안 저장 |
| GET | `/trainer/programs/{draft_id}` | 초안 상세(편집기로 불러오기) |
| PUT | `/trainer/programs/{draft_id}` | 초안 수정(`sessions` 는 통째로 교체) |
| DELETE | `/trainer/programs/{draft_id}` | 초안 삭제 |
| GET | `/trainer/clients/{member_id}/chat?before=&before_id=` | 채팅 스레드(커서 페이지네이션) |
| POST | `/trainer/clients/{member_id}/chat` | 메시지 전송 (`client_request_id?`) |
| POST | `/trainer/clients/{member_id}/chat/read` | 읽음 처리 |
| GET | `/trainer/chat/unread` | 회원별 미확인 수 |
| GET | `/trainer/schedule?date=` | 하루 타임라인 |
| GET | `/trainer/schedule?from=&to=&member_id=` | 구간 조회 / 회원 필터 |
| GET | `/trainer/schedule/booked-dates` | 예약 있는 날짜 |
| POST | `/trainer/schedule` | 예약 생성(예정, `client_request_id?`) |
| PUT | `/trainer/schedule/{id}` | 예약 수정 |
| DELETE | `/trainer/schedule/{id}` | 예약 삭제 |
| POST | `/trainer/schedule/{id}/complete` | 세션 완료(예정→완료) |
| GET | `/trainer/dashboard/task-progress` | 오늘 할 일 진행 상태 — 보관 기간(63일) 안의 날짜별 기록 |
| PUT | `/trainer/dashboard/task-progress/{date}` | 그날 진행 상태 통째로 저장(KST 오늘·어제만) |
| POST | `/trainer/clients/{member_id}/ai-coach` | 담당 회원 데이터 기반 AI 코칭 질의 |
| GET | `/trainer/clients/{member_id}/report?week_start=` | 주간 리포트(어느 요일을 줘도 그 주 월요일로 정규화) |
| POST | `/trainer/clients/{member_id}/report/send` | 리포트를 회원 채팅 스레드로 전송 |

채팅 발신과 스케줄 생성의 `client_request_id`는 선택값이다. 클라이언트는 한
사용자 행동에 한 번 생성하고 응답 유실 뒤 재시도에서 같은 값을 보낸다. 같은 사용자·
동작·키·payload면 처음 생성된 결과를 다시 반환하고, 같은 키에 다른 payload면
`409`다. 키가 없는 구버전 요청은 기존처럼 매번 새 행을 만든다. 채팅은 발신자까지
scope에 포함해 회원과 트레이너가 우연히 같은 키를 만들어도 충돌하지 않는다.

### 스케줄 구간 조회 (`from`/`to`)

주 캘린더가 7일치를 한 번에 읽기 위한 것 — 하루짜리 요청을 요일마다 반복하면 요청이
7배가 된다. `YYYY-MM-DD` 는 사전식 정렬이 곧 날짜순이라 문자열 범위 비교로 충분하다.
한쪽 끝만 온 구간·뒤집힌 구간·잘못된 형식은 **422** 다. 조용히 하루로 떨어뜨리면
클라이언트는 구간을 받았다고 믿는다. `member_id` 는 담당 링크를 먼저 확인한다.

### 건강 목표 숫자의 범위 (#1888)

건강 목표(일일 칼로리·나트륨·주간 운동량 등)는 **회원과 트레이너가 같은
`health_profiles` 컬럼을 고친다.** 그래서 범위도 한 벌이다 —
`app/schemas/health_goal_ranges.py` 에 두고 세 스키마가 나눠 쓴다:
`HealthGoalsUpdate`(회원 `PUT /users/me/health-goals`) ·
`OnboardingRequest`(`POST /users/me/onboarding`) ·
`MemberHealthProfileUpdate`(트레이너 `PUT /trainer/clients/{id}/health-profile`).
어긋나면 **422** 다.

한동안 이 제한이 트레이너 경로에만 있었다. 회원 경로는 제약 없는
`Optional[int]` 이라 `daily_calories: 99999999999` 가 **500**(`integer out of
range`)이었고, `-3000` 이나 주 100,000분(한 주는 10,080분이다) 같은 값은 그대로
**저장**됐다. 홈·운동 탭의 달성률이 음수나 0% 로 깨지고, 같은 값을 트레이너
리포트도 읽는다.

**되돌릴 수도 없었다.** 회원이 넣은 `-3000` 을 트레이너가 화면에서 고치려 하면
트레이너 스키마의 하한에 걸려 422 가 났다 — 잘못된 값을 넣은 문과 고치는 문이
다른 기준을 쓰면, 한쪽으로 들어온 값이 다른 쪽에서 고칠 수 없는 값이 된다.

`null` 은 그대로 **목표 해제**다. 범위는 값이 있을 때만 본다.

`conditions`(1000자)·`goals`(500자)의 길이 상한도 같은 자리에 있다. 컬럼이
`Text` 라 500 은 아니었지만, 회원 경로에만 상한이 없어 20만자가 200 으로
저장됐다.

두 앱 화면은 `oncare_ui` 의 `AppGoalRanges` 로 **같은 숫자**를 미리 보여 준다.
값을 바꿀 때는 서버 모듈과 그 파일을 함께 고친다 — 한쪽만 고치면 화면은
괜찮다는데 저장이 422 로 떨어지는 자리가 생긴다.

### 알림 수신 설정 (`/trainer/me/settings`)

기기 로컬이 아니라 **계정 단위** — 트레이너는 센터 PC 와 태블릿을 오간다. 값이 3개뿐이고
프로필과 수명이 같아 별도 테이블 대신 `trainer_profiles` 컬럼으로 뒀다
(`0019_trainer_noti_settings`). **기본값은 서버가 소유한다**(모두 켬 / 30분 전) —
클라이언트마다 기본값을 들고 있으면 기기별로 갈라진다. `reminder_lead_minutes` 는
`REMINDER_LEAD_OPTIONS`(10/30/60) 밖의 값을 422 로 거부한다.

### 오늘 할 일 진행 상태 (`/trainer/dashboard/task-progress`)

대시보드 `오늘 할 일` 의 체크(완료 표시)·삭제(오늘 목록에서 제외)와 `할 일 진행률`
그래프의 날짜별 요약이다. 알림 수신 설정과 같은 이유로 **계정 단위**다(#1633) —
체크는 트레이너 자신의 확인 표시지만, 기기마다 다르면 센터 PC 에서 끝낸 일이
태블릿에서 다시 할 일로 보이고 `지난 할 일` 상자도 기기별로 갈린다.

- **별도 테이블**(`trainer_daily_task_progress`, `0065_trainer_daily_task_progress`).
  그래프가 날짜별 이력을 읽어 프로필 컬럼 하나로는 담을 수 없다. (trainer_id, date)
  하나당 한 행이고 앱이 그날 목록 전체를 **통째로 덮어쓴다**(PUT).
- **보관 63일.** 그래프가 이번 주와 8주 전까지 되짚는 범위다. 쓸 때 오래된 행을 지운다.
- **오늘은 서버 KST 가 정한다.** PUT 은 KST 오늘·어제만 받고 그 밖은 422 다 —
  자정을 넘긴 화면은 받고, 기기 시계가 틀린 요청은 막는다. `지난 할 일` 은 어제 행의
  `pending_keys` 로 가른다.
- 미션 키(`report-<id>` 등)는 앱이 만들고 서버는 해석하지 않는다.
- 데모(`USE_MOCK_API=true`)는 계정이 없어 기기 로컬에 둔다.

### 트레이너용 AI 코칭 (`/trainer/clients/{id}/ai-coach`)

회원 앱의 `/ai-coach/chat` 과 **같은 RAG 파이프라인**(`services/coach/chat.answer`)을
쓰되, 검색 스코프가 호출자(트레이너)가 아니라 **담당 회원**이다. 트레이너가 자기
자신의(비어 있는) 기록으로 코칭받는 일을 막기 위한 구분이며, 접근 경계는 담당 링크
확인(`_require_client`) — 남의 회원이면 404 로 존재조차 드러내지 않는다.

### 주간 리포트 (`/trainer/clients/{id}/report`)

O2O 코칭의 재등록 고리. 세션 수·완료 수는 `trainer_schedule`, 이행률은
`routine_history`, 나트륨은 `diet_entries`에서 그 주만 집계한다 — 새로 수집하는
데이터는 없다. **기록이 없는 항목은 0 이 아니라 `null`** 로 내려간다("이행률 0%"는
"안 했다"는 거짓말이 되므로). 전송은 별도 리포트 함이 아니라 **회원이 이미 읽고 있는
채팅 스레드**로 들어간다.

### 다중 세션 프로그램 (#709)

편집기는 한 프로그램에 세션을 여러 개 만들 수 있는데 저장은 오랫동안 하나에서
멈춰 있었다. `0039_program_sessions` 가 세 곳을 함께 넓혔다.

| 곳 | 이전 | 이후 |
|---|---|---|
| 초안 | `session_name` + `exercises_json` | `sessions_json`(세션 배열, 순서 = 배열 순서) |
| 배정 | 프로그램 전체가 루틴 **한 건** | 세션당 루틴 한 건 + `program_name`/`session_name`/`session_order`/`exercises_json` |
| 일정 | `program_json` = `[{name,sets,reps,hold_seconds,weight}]` | 항목에 `session` 추가(없으면 빈 문자열) |

**세션이 하나뿐인 프로그램은 예전과 같은 모양이다** — 루틴 이름이 프로그램
이름이고 `session_name` 이 비어 회원 화면에 없던 세션 라벨이 생기지 않는다.
기존 행·기존 요청도 그대로 읽힌다(빠진 키는 빈 값).

`client_request_id` 는 프로그램 **전체**에 대해 멱등하다. 세션마다
`{key}#{index}` 로 나눠 저장하는데, `(trainer, member, client_request_id)` 유니크
제약이 한 키로 여러 행을 허용하지 않기 때문이다. 재시도는 먼저 배정된 세션들을
그대로 돌려준다 — 반쯤 겹친 배정이 남지 않는다.

### 버티는 운동의 초 (#1969)

플랭크·행잉처럼 **버티는** 운동은 한 세트를 몇 회가 아니라 몇 초로 잰다. 그 초를
담을 칸이 어디에도 없어, 트레이너는 `플랭크 3세트 · 60초` 를 **이름에** 적을
수밖에 없었고 이름에 적힌 글자는 어떤 집계에도 잡히지 않았다. 45초 홀드가
`reps: 3` 으로 적힌 데이터도 남아 있었다 — 45초를 "3회" 라고 말하는 값이다.

`0082_isometric_hold_seconds` 가 `hold_seconds` 를 네 곳에 같은 이름으로 열었다:
`trainer_routines`·`exercise_sessions` 컬럼과, `ProgramDraftExercise`·
`ProgramItem`·`ProgramTemplateExercise`·`RoutineOut` 스키마다.

**`reps` 와 한 자리를 나눠 쓴다.** 버티는 운동이면 `hold_seconds` 가 있고 `reps`
가 비며, 아니면 반대다 — 한 세트를 두 단위로 적으면 어느 쪽이 맞는지 알 수 없다.
둘이 함께 오면 서버가 초를 믿고 횟수를 버린다(`_drop_fields_not_in_type`,
`_reps_and_hold`): 초를 보내는 쪽은 이 칸을 아는 클라이언트이고, 횟수는 칸이
없던 시절처럼 초를 억지로 담아 보낸 값일 수 있다.

**어느 종목이 버티는 운동인지는 종목 참조표가 말한다.** `exercise_catalog.isometric`
이 그 표시이고 시드(`exercise_catalog_seed.py`)에서 온다. 이 값은 폼이 `횟수` 칸을
`초` 칸으로 바꿔 보이는 **기본값**일 뿐이고(`POST /exercise/calories` 응답의
`isometric`), 표에 없는 자유 입력 이름이 있으므로 트레이너·회원이 폼에서 곧바로
바꿀 수 있다.

**주간 집계는 초를 세지 않는다.** 홀드도 세트로 세어 `strength_sets` 에 그대로
들어가고(`sets_of`), 초는 그 세트가 얼마짜리였는지를 말할 뿐이다. 초는 분으로도
세트로도 곧바로 환산되지 않아, 새 집계 축을 만드는 대신 지금 축을 그대로 둔다.

### 반복 PT 일정 (#870)

주 2회 PT 를 하는 회원이 15명이면 매주 같은 일정을 30번 다시 입력해야 했다. 반복을
표현하지 못하면 그 입력이 매주 되풀이되고, 주차 누락·시간 오입력이 그대로 회원 앱에
나간다.

- **규칙 표를 두지 않는다.** 회차 행의 `series_id` 하나로 "한 번에 잡힌 것" 만 잇는다.
  만들고 나면 각 회차는 독립된 약속이라 개별로 옮기고 지우는 것이 실제 운영이고,
  규칙을 따로 저장하면 규칙과 실제 회차가 조용히 어긋난다. 그래서 시리즈 전체 수정도
  이번 범위가 아니다 — 개별 회차 수정·삭제가 기존 경로 그대로 동작한다.
- **전부 만들거나 하나도 만들지 않는다.** 겹치는 회차가 있으면 409 이고 본문에 겹친
  세션이 실린다. 일부만 만들면 트레이너는 몇 회차가 생겼는지 화면을 세어 봐야 알고,
  빠진 주는 나중에 발견된다.
- 겹침 판정은 `(date, time)` 이 같고 상태가 `예정|완료` 인 세션이다. 취소·노쇼 자리는
  비어 있다(#871).
- 회차 상한은 `MAX_SERIES_OCCURRENCES=52`. 종료일에 연도를 잘못 적어도 수백 건이
  조용히 생기지 않는다.
- 멱등키에서 시리즈 id 를 만든다(`_series_id_for`). 재시도가 이미 만든 시리즈를 다시
  찾아 같은 결과를 돌려주므로 회원 일정이 두 배가 되지 않는다.
- 회원 알림은 회차마다가 아니라 한 줄로 묶는다 — 8주치를 한 번에 잡으면 알림함이 같은
  문구 여덟 줄로 덮인다.

### 일정의 결말 — 완료·취소·노쇼 (#871)

`삭제` 하나가 서로 다른 두 일을 처리하고 있었다 — 잘못 만든 데이터를 없애는 일과,
실제로 있었던 약속이 진행되지 않았다는 사실. 뒤엣것까지 삭제로 처리하면 "왜 그 PT 가
진행되지 않았나" 가 사라져, 나중에 회원의 낮은 완료율을 잘못 읽는다.

- 상태값은 DB 계약값이라 한국어 표기를 유지한다: `예정|완료|취소|노쇼|공백`. 앱도 같은
  문자열로 거르므로(`ScheduleStatus`) 표기 체계를 바꾸면 기존 행이 어느 질의에도
  걸리지 않는다.
- 전이는 `예정` 에서만 갈라진다. `완료·취소·노쇼` 는 종료 상태(`SCHEDULE_TERMINAL`)라
  서로 뒤집히지 않고(409), 수정도 막힌다 — 이미 파생된 회원 운동 기록과 어긋난다.
- 같은 전이의 반복은 200 이고 시각·주체는 처음 값을 지킨다(중복 클릭·재시도).
- 취소는 `cancelled_at`·`cancellation_source`(member|trainer|other)·`cancellation_reason`
  을, 노쇼는 `no_show_at` 을 남긴다. 사유는 트레이너 내부 기록이라 회원 알림에 싣지 않는다.
- **회원의 예약 취소**는 트레이너 일정을 지우지 않고 `취소`(주체 member)로 남긴다. 좌석
  복구·예약 삭제는 그대로다. 탈퇴 경로는 계정이 사라지므로 지금처럼 일정을 지운다.
- 집계: 주간 리포트의 `sessions_booked` 는 `예정+완료` 만 센다. 진행되지 않은 약속을
  분모에 넣으면 트레이너 사정의 취소가 회원의 낮은 이행률로 보인다. 취소·노쇼에 패널티를
  주는 지표는 별도 정책이다.

### 회원 후속 관리 할 일 (#869)

트레이너가 "며칠 뒤 다시 확인할 것"을 남겨 두는 최소 업무 큐다. 메모
(`trainer_client_memos`)와 나누는 까닭은 답하는 질문이 다르기 때문이다 — 메모는
"이 회원에 대해 무엇을 알아 두었나", 할 일은 "언제까지 무엇을 해야 하나"다.

- **조회 범위를 서버가 정한다.** `scope=due` 는 오늘 예정과 **기한이 지난** 미완료를
  함께 준다. 지난 항목을 빼면 하루만 지나도 목록에서 사라져, 놓치지 않으려고 만든
  기능이 놓치는 경로가 된다. 오늘 기준은 `clock.today_iso()`(KST)다.
- **등록·완료가 모두 멱등하다.** 등록은 `(trainer_id, client_request_id)` 유니크로,
  완료는 이미 완료된 할 일에 200 을 돌려주고 `completed_at` 을 처음 값으로 지키는
  방식으로. 중복 클릭에 409 를 주면 화면은 이미 사라진 항목에 대해 오류를 띄운다.
- **소유권 경계가 두 겹이다.** 등록은 담당 관계(`_require_client`)를 요구하고, 등록
  뒤의 조회·수정·완료는 `trainer_id` 만 본다 — 담당이 해제돼도 내가 남긴 업무는
  내 것이라, 여기서 담당을 다시 요구하면 지울 수도 없는 항목이 목록에 남는다.
- **`context_type` 은 route 힌트**다(`general|diet|exercise|message|program|schedule`).
  새 deep-link 체계가 아니라 기존 화면 중 하나를 고르는 값이라 CHECK 제약으로 못
  박고, 앱은 모르는 값을 회원 상세로 떨어뜨린다.

자동 생성(나트륨 초과·unread 메시지 등)은 이 범위가 아니다. 다만 나중에 자동 업무
큐로 늘릴 수 있도록 특정 기능에 종속된 컬럼은 두지 않았다.

### 로스터 집계 (`build_roster`)

- 회원별 식단·기록과 최신 메시지·루틴을 **배치 조회**한다(N+1 방지).
  `chat_messages`·`trainer_routines`의 회원별 최신 1건은 **`DISTINCT ON (member_id)`**로 한 번에.
- `last_routine` 라벨은 `created_at`(UTC 저장)을 **시스템 로컬 시각으로 변환**해 계산한다
  (`_local_date_iso` → `astimezone().date()`). UTC `.date()`로 계산하면 자정 근처에서
  '오늘/어제'가 어긋난다. 운영은 `TZ=Asia/Seoul`.
- 채팅 스레드는 `(created_at, id)` **복합 커서**(`before`/`before_id`)로 페이지네이션 —
  같은 `created_at`이 여러 건이어도 안정적으로 끊어 읽는다.
- **로스터도 한 쪽만 준다**(기본 50명, `limit` 1~100). 쿼리 수는 인원과 무관하게
  상수지만 *한 쿼리가 읽는 양*은 인원만큼 자라고, 카드마다 붙는 집계도 함께 커진다. (#980)
- 로스터 커서는 다른 목록과 모양이 다르다 — 정렬키가 시각이 아니라 트레이너가 정한
  순서(`sort_order`)이고 그 값은 카드에 실리지 않아서, 받은 마지막 카드의 **회원 id**
  하나(`after_id`)만 넘기면 서버가 그 자리를 찾아 이어 준다. 명단에 없는 id 는 **422** 다
  — 조용히 첫 쪽을 돌려주면 이어 받기가 제자리를 돈다. 정렬 tie-break 는
  `created_at` 이 아니라 회원 id 이며(같은 `sort_order` 안에서만 차이), 담당 링크는
  만들 때마다 `max(sort_order) + 1` 을 받아 값이 겹치는 일 자체가 드물다.

### PT 관리 신호 (`client_signals.py`, #2203)

로스터 카드의 `signals` 는 "누가 흐름이 끊겼나, 누가 목표에서 벗어났나, 누가 불편을
호소하나" 에 답한다. 기준은 `app/services/client_signals.py` 한 곳에 상수로 있고, 저장하지
않고 로스터를 만들 때마다 계산한다(쿼리 수는 인원과 무관한 상수). 응답은 급한 순이다.

| `kind` | 신호 | 기준 | 근거 값 |
| --- | --- | --- | --- |
| `discomfort` | 통증·불편 | 최근 7일 이 트레이너와의 채팅의 회원 메시지, AI 챗봇의 회원 메시지(회원이 치운 줄 제외)에서 통증 표현(`coach/insights.detect`). 글만 본다 — 이모티콘은 본문이 비어 읽지 않는다 | — |
| `record_gap` | 기록 끊김 | 마지막 식단·운동 기록일(없으면 담당 시작일)에서 오늘까지 3일 이상 | `days`(30 에서 멈춤 = 30일 넘게) |
| `no_show` | 노쇼·취소 반복 | 최근 30일 이 트레이너의 PT 일정 중 `노쇼` + 회원 사정 `취소`(`cancellation_source=member`) 2회 이상. 트레이너 사정 취소는 세지 않는다 | `count` |
| `routine_missed` | 배정 루틴 미수행 | 어제까지 최근 3일 중 승인된 배정 루틴이 걸려 있던 날이 2일 이상인데 그 기간에 한 번도 완료하지 않음 | `days` |
| `exercise_goal_low` | 운동 목표 미달 | 이번 주 유형별 누적(유산소 분·근력 세트·스트레칭 분) ÷ (주간 목표 × 경과일/7), 유형마다 100% 상한, 셋의 평균이 50% 미만. 월·화는 판단하지 않는다. 목표가 없으면 회원 앱 기본값(150분·21세트·60분) | `percent` |
| `calorie_off` | 칼로리 목표 이탈 | 어제까지 최근 3일 중 기록한 날(2일 이상)의 평균이 개인 칼로리 목표(없으면 2,000kcal) 대비 ±15% 초과 | `percent`, `direction` |
| `protein_low` | 단백질 부족 | 건강 목표에 근력 향상·체중 감량이 있고 개인 단백질 목표가 있는 회원의 같은 창 평균이 목표의 75% 미만 | `percent`(목표 대비 섭취율) |

- **기록 끊김이면 기록에서 나오는 신호**(배정 루틴·운동 목표·칼로리·단백질)는 **내리지 않는다** —
  기록이 없으면 그것들도 자동으로 뜨므로 원인 하나를 배지 넷으로 말하게 된다.
- **담당을 맺은 지 3일이 안 된 회원**은 통증·불편만 본다.
- **담당 해제·휴면 회원**은 계산하지 않는다(빈 목록).
- **칼로리 ±15% 는 주간 리포트 요약과 같은 상수**다(`trainer_report_summary_service.CALORIE_TOLERANCE`
  가 `client_signals.CALORIE_TOLERANCE` 를 가리킨다). 판정 함수 `client_signals.calorie_off_target`
  를 다른 화면도 그대로 가져다 쓴다.
- 답장 대기는 서버 신호가 아니다. 안 읽은 메시지 수는 앱이 실시간으로 받아, 로스터 시점의 값으로
  굳히면 답장한 뒤에도 배지가 남는다.

## 5. 예약 → 수업 → 기록 루프

`trainer_schedule`의 예약을 완료하면 회원 `routine_history`로 적재되어
"트레이너가 지도한 PT 세션"이 회원 앱 운동 이력에도 나타난다(양방향 공유).

- **완료(`complete_session`)**: `예정` 슬롯만 완료 가능(공백 400, 미래 400).
  조건부 `UPDATE ... WHERE status='예정'` + `rowcount==1` 게이트로 **동시 완료 요청의
  중복 기록을 방지**. 기록 id는 슬롯 기준 결정론적(`sched-hist-{id}`)이라 재호출에도 멱등.
- **수정(`update_session`)**: `완료` 세션 수정은 **409**(기록과 스케줄이 어긋나지 않게).
  `member_id=""` 또는 명시적 `null`은 '배정 해제'로 해석해 **NULL** 저장한다.
  DB `NOT NULL`인 나머지 필드의 명시적 `null`은 요청 경계에서 **422**로 거부한다.
- **삭제(`delete_session`)**: `완료` 세션을 지우면 파생된 `sched-hist-{id}` 운동기록도
  **함께 삭제**(고아 레코드 방지 — 완료 시 적재의 역연산).

## 6. 회원측 "내 담당 코치" 미러 (`/v1/me/coach/*`, RequireMember)

트레이너가 배정한 데이터를 **회원 관점**으로 되비추는 읽기 미러 + 양방향 채팅.

| Method | Path | 설명 |
|---|---|---|
| GET | `/me/coach` | 내 담당 코치 요약(활성 담당 없으면 404) |
| GET | `/me/coach/routines?date=` | 받은 루틴 — 그날 걸려 있던 목록과 그날 완료(`date` 없으면 오늘, 미래는 422) |
| GET | `/me/coach/sessions` | 내 PT 세션(최근 100건) |
| GET | `/me/coach/chat` | 채팅 스레드 |
| GET | `/me/coach/chat/unread` | 미확인 수 |
| POST | `/me/coach/chat` | 코치에게 메시지 전송 (`client_request_id?`) |
| POST | `/me/coach/chat/read` | 읽음 처리 |
| DELETE | `/me/coach` | **헬스장 + 담당 트레이너** 해제(멱등, 204) |
| DELETE | `/me/coach/trainer` | **담당 트레이너만** 해제 — 헬스장은 유지(멱등, 204) |

- 담당 코치는 **active 링크**만 인정(`get_member_trainer_id` → `active.is_(True)`).
  휴면 링크만 있으면 코치 조회/발신 불가(404/빈 목록).
- `/me/coach/sessions`는 시간이 지나며 누적되는 PT 세션을 **최근 100건**으로 상한.

### 추천 개인운동은 매일 새로 체크하는 목록 (#2161)

트레이너가 목록을 바꾸기 전까지 같은 목록이 **날마다 미완료로 다시 시작**한다.

- `trainer_routines.active_from`(포함) ~ `ended_on`(이날부터 없음, 걸려 있는 동안 NULL)이
  목록에 걸린 기간이다. 배정은 배정한 날, AI 제안은 승인한 날부터 걸린다.
- **철회는 행을 지우지 않는다.** `DELETE /trainer/clients/{id}/routines/{rid}` 와 회원의
  `DELETE /me/coach/routines/{rid}` 는 `ended_on` 을 오늘로 찍는다 — 오늘 목록에서 바로
  빠지고, 지난 날짜에 걸려 있던 목록은 남는다. 이미 내려온 배정을 다시 철회하면 404.
  승인 전·거절한 후보는 회원 목록에 걸린 적이 없어 예전처럼 행째 지운다.
- 완료는 `(배정, 그날)` 에 한 번이다(`uq_exercise_sessions_routine_day`). `complete`·
  `DELETE …/complete` 는 **오늘**만 건드린다. 지난 날짜는 읽기 전용이다.
- `RoutineOut.completed` 는 조회한 **그날** 완료했는가다. 트레이너 배정 목록도 오늘 기준이다.
- 담당 없는 회원의 하루치 AI 추천은 만들 때 `active_from = 그날`, `ended_on = 다음 날`
  이라 그날 하루만 걸린다. 지난 날짜를 열어도 그날 추천을 새로 만들지 않는다.
- 지난 날짜는 **지금의 담당 기준**으로 읽는다(그 트레이너가 그날 걸어 둔 목록).

### 회원↔헬스장 링크 (#444)

회원의 "내 헬스장"은 `member_gyms`(회원당 1행, `member_id` PK)에 있다. 예전에는 담당
트레이너의 소속(`trainer_profiles.gym_id`)에서 **파생**시켜, 트레이너만 해제해도 헬스장이
함께 사라졌다 — 앱 MY 탭은 두 해제를 따로 제공하는데 서버가 그 구분을 표현하지 못했다.

- `GET /me/gym` (헬스장 라우터) — 내 헬스장. 응답은 `/gyms/{id}` 와 같은 `GymOut` 이라
  앱이 상세를 한 번 더 읽지 않는다. 연결이 없으면 404.
- `GET /me/coach` 의 `gym` 도 이 링크가 진실이다. 링크가 없는 회원(백필 이전 데이터)만
  예전처럼 트레이너 소속으로 폴백한다.
- 헬스장 해제가 트레이너까지 끊는 것은 의도다 — 떠난 헬스장의 트레이너를 담당으로 남길
  수 없다. 앱 mock(`MockGymRepository`)도 같은 규칙이다.
- 링크를 **만드는** 경로는 아직 시드/백필뿐이다. 담당 배정 자체가 시드로만 생기는 현재
  단계와 같다(헬스장 먼저 가입 → 트레이너 나중 선택 흐름은 후속).

## 7. 데모 시드 (`seed_trainer.py`, `seed_member_data.py`)

- 트레이너 계정 "김태오"(`trainer@oncare.com`) + 담당 회원 3명(김민수/이지수/박성호).
  회원 실데이터(식단·운동기록·채팅·루틴·스케줄)를 함께 시드해 **시드 단계부터 공유가 성립**.
- **멱등**: 결정론적 id + 존재 검사로 재기동에도 중복 없음. 날짜가 넘어가면 '오늘'이 새로
  시드되어 과거 데이터가 누적된다.
- **동시 기동 안전**: 시드 커밋은 `_safe_commit`으로 **UNIQUE 위반(SQLSTATE 23505)만**
  무시하고(다른 인스턴스가 먼저 넣은 경우), FK(23503)·NOT NULL(23502)·CHECK 등 **진짜
  오류는 재발생**시켜 데이터가 롤백된 채 조용히 기동되지 않게 한다.
- 이메일 충돌 등으로 회원 계정/링크가 없으면 그 회원 건강 데이터는 **건너뛴다**(FK 오류 방지).

## 8. 마이그레이션 선형화 주의

트레이너 마이그레이션은 `0012_trainer_domain` →
`0013_trainer_active_coach_uq` 뒤에 상담·트레이너 인덱스의 두 `0014` 분기를
`0015_merge_alembic_heads`로 합친다. 그 뒤는 `0016_drop_vitals` →
`0017_add_diet_exercise_goals` → `0018_diet_entry_sugar_g_float` →
`0019_trainer_noti_settings` → **`0020_gym_profiles_trainer_fk`** 순의 단일
chain이다. `0020`의 `down_revision`은 `0019_trainer_noti_settings`다.

배포는 이 순서를 따라 `alembic upgrade head`를 실행하며, CI에서
`alembic heads`가 하나인지 먼저 검증한다. 이미 별도 migration head를 적용한 DB는
`down_revision`을 임의로 바꾸지 말고 배포 문서의 merge revision 절차를 따른다.


## 트레이너 탈퇴 (#505)

회원 탈퇴(`DELETE /users/me`)와 대칭인 `DELETE /trainer/me`.

**담당 회원이 남아 있어도 막지 않는다.** 막으면 담당이 있는 트레이너는 계정을 영영
지울 수 없고, 그만두는 사람에게 "회원을 먼저 다 정리하라"고 요구하는 것은 현실적이지
않다. 대신 회원이 모르게 사라지지 않도록 알림을 남긴다 — 회원 앱의 '내 담당 코치'가
어느 날 조용히 비어 있으면 앱이 고장 난 것으로 읽힌다.

**삭제 순서가 중요하다.** `trainer_reservations` 는 회원·슬롯·일정을 모두
**RESTRICT** 로 참조한다. 슬롯과 일정은 트레이너 삭제 시 CASCADE 로 지워지므로,
예약 행을 먼저 치우지 않으면 그 CASCADE 가 FK 에서 막힌다.

| 데이터 | 처리 |
|---|---|
| 예약(`trainer_reservations`) | 먼저 삭제(좌석 복구 불필요 — 슬롯도 함께 사라진다) |
| 프로필·담당 링크·채팅·루틴·일정·슬롯·이력·알림 | `users.id` CASCADE |
| 상담 요청의 `trainer_id`·`decided_by` | SET NULL — 요청 이력은 남는다 |
| 상담 요청의 `slot_id`(회원이 고른 자리, #1873) | SET NULL — 슬롯이 CASCADE 로 지워져도 요청과 그 시각 사본(`preferred_date`·`preferred_time_slot`)은 남아 조회된다 |
| 회원↔헬스장 링크(`member_gyms`) | 그대로 — 트레이너와 별개다(#444) |

알림은 담당 회원과 **예약만 있는 회원** 모두에게 간다(문구는 다르다).
