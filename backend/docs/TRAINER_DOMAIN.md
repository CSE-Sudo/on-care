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
| `trainer_routines` | 트레이너/AI가 회원에게 배정한 루틴. PT 일정에 붙인 개인운동은 `schedule_id`·`status='scheduled'`·`delivery_kind` 를 갖는다(`0092_routine_schedule_link`, #2223) |
| `trainer_client_memos` | 트레이너가 회원별로 남긴 메모(직접 작성 + 채팅 인사이트 + 운동 기록 카드, `0036_trainer_memos`·`0106_trainer_memo_exercise_ref`). 분류 `category`(`exercise`·`diet`·`pain`·`life`, 빈 문자열 = 고르지 않음, `0129_trainer_memo_category`, #2622) |
| `trainer_follow_up_tasks` | 트레이너가 회원별로 남긴 후속 관리 할 일(예정일·완료 상태, `0047_trainer_follow_up_task`) |
| `trainer_program_drafts` | 트레이너가 저장해 둔 프로그램 초안(세션 배열, 회원과 묶이지 않음, `0038`+`0039`) |
| `routine_history` | 회원 운동 완료 기록(회원 앱·PT 세션 공용 원본) |
| `chat_messages` | 트레이너↔회원 1:1 채팅 |
| `trainer_schedule` | 트레이너 오늘 타임라인(예약→수업→기록 루프) |

### 글을 부르는 이름 — 메모와 피드백 (#2574)

두 앱의 화면 문구는 사람이 적는 글을 **메모**와 **피드백** 두 이름으로만 부른다.
`메시지`·`코멘트`·`소감`·`남긴 말`·`한 줄 메모` 같은 다른 이름은 쓰지 않는다.
채팅 기능의 `메시지`(메시지 탭·채팅 입력·`트레이너 메시지` 알림 분류)만 기능 이름이라 예외다.

| 이름 | 누가 읽나 | 해당하는 글 |
|---|---|---|
| 트레이너 피드백 | 회원 | PT 일정의 글(`trainer_schedule.note`, 회원 앱 `오늘의 피드백`), 리포트 피드백(`trainer_report_feedback`), 위저드·일정 추가에서 회원에게 전할 말 |
| 회원 피드백 | 트레이너 | 회원 주간 피드백과 그 안의 `한 줄 피드백`(`member_weekly_feedback`) |
| 메모 | 트레이너만 | 회원 상세 메모(`trainer_client_memos` — 직접 작성·채팅 감지·운동 기록 카드), 상담 일정의 글(`상담 메모`) |

같은 `trainer_schedule.note` 라도 PT 일정이면 피드백, 상담 일정이면 메모로 부른다.

**건강상태·주의사항**(`health_profiles.conditions` 에서 목표 칩을 뺀 글)은 메모도 피드백도 아니다(#2518).
회원(온보딩·MY 건강 목표)과 담당 트레이너(신체·목표 창)가 **같은 글을 함께 보고 고치는 공유 건강 정보**이고,
AI 코치 채팅·식단 조언·운동 추천 프롬프트가 읽는다. 그래서 회원 메모로 합치지 않는다.
트레이너 웹은 이 칸에 `회원에게도 보여요 · 추천할 때 참고해요` 를 달고, 편집 중에는 칸 이름 옆에
`트레이너만 볼 내용은 메모에 남겨 주세요.` 를 둔다 — 비공개로 남길 내용을 이 칸에 적으면 회원에게 그대로 보인다.
회원 앱은 `추천할 때 참고해요` 만 단다. 트레이너가 본다는 사실은 담당 연결 때 데이터 공유 동의로 이미 알린다.

개인운동 **한 건마다** 남기는 피드백은 양쪽 모두 없다 — 회원 쪽은 #1825, 트레이너 쪽은 #2517 에서
없앴고 저장 칸(`exercise_sessions.trainer_feedback`·`member_note`)도 지웠다(`0107_drop_routine_feedback`,
`0108_drop_member_note`, #2624).
개인운동에 대해 서로 할 말은 채팅으로 하고(회원의 불편은 채팅 감지로 모인다), 트레이너만 기억해 둘
것은 운동 기록 메모(#2332)로 남긴다. 응답의 `trainer_feedback`·`member_note` 칸은 옛 앱을 위해
빈 문자열로 남긴다.
회원 앱 응답은 완료된 PT 의 글만 싣고 상담 일정의 글은 싣지 않는다(#2515, 6절 `/me/coach/sessions`).

트레이너 웹 회원 상세의 `메모` 창은 `메모 | 피드백` 두 탭이다(#2615).

- **메모 탭**은 위 표의 회원 메모다. 직접 쓴 메모는 분류(`운동`·`식단`·`통증·부상`·`생활·일정`)를 하나 고를 수 있다(#2622).
  - 고르지 않으면 태그가 `직접 작성` 이다.
  - `운동` 에서 최근 14일 운동 기록을 이으면 운동 탭 카드에서 남긴 메모와 같은 운동 기록 메모가 된다.
  - 운동 기록 메모의 분류는 늘 `exercise`, 채팅 감지 메모는 비어 있고 둘 다 바꿀 수 없다.
- **피드백 탭**은 회원과 주고받은 피드백을 모아 보는 읽기 전용 목록이다. 완료 PT 의 글, 보낸 주간 리포트, 회원 주간 피드백을 한데 보여 준다.
  - 쓰고 고치는 곳은 원래 자리(스케줄 일정·리포트 주) 하나뿐이다.
  - 리포트는 초안(`trainer_report_feedback`)이 아니라 실제로 보낸 메시지(`chat_messages.report_week_start`)를 읽는다.

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
| `active` | 담당 관계가 살아 있는가 | 연결 코드·담당 요청 수락·헬스장 해제·탈퇴 등 시스템 | 회원측 '내 코치'가 사라지고 예약·코치 조회가 막힌다 |
| `dormant` | 트레이너가 지금 적극적으로 관리하는가 | 트레이너가 화면에서 직접 | 배지만 휴면이 된다. 담당·기록·식단·운동·채팅은 그대로 |

로스터의 `active` 필드는 둘의 AND 다(`trainer_service._roster_active`) — 담당이
해제된 과거 회원의 카드는 예나 지금이나 휴면으로 보여야 하기 때문이다. 그래서
담당이 이미 해제된 회원의 상태 전환은 409 다(되돌려 봐야 로스터가 휴면 그대로라
"저장했는데 그대로"가 된다). 담당 재배정은 회원이 동의하는 연결 경로(연결 코드·담당 요청)의 몫이다.

담당이 생기는 두 경로(연결 코드 `POST /trainer/pairing-code`·담당 요청 수락
`POST /me/coach/invites/{id}/accept`)는 같은 트랜잭션에서 그 회원에게 걸린 **대기 중 담당 요청**을
닫는다(#2894). 연결된 트레이너가 보낸 것은 `accepted`(연결 코드면 이 행이 이력 행이 되어 수락 행이 둘
남지 않는다), 다른 트레이너가 보낸 것은 `cancelled` 이고 그 트레이너에게 알림은 보내지 않는다.
연결이 실패하면 대기 요청도 그대로다. 정리 이전에 남은 행은 마이그레이션 `0128_close_stale_invites` 가 같은 기준으로 닫는다.

### 해제된 담당은 데이터 접근 경계 밖이다 (#2281)

담당 해제는 링크 행을 지우지 않고 `active=False` 로 내린다(`remove_client`). 그래서
트레이너 권한 확인(`trainer._require_client`)은 행이 있는지가 아니라 **`active`
까지** 본다. 해제된 회원은 남의 회원·없는 회원과 **같은 404·같은 문구**
(`담당 고객을 찾을 수 없습니다.`)다 — 다른 답을 주면 "예전에 담당했던 회원"이라는
사실이 응답만으로 드러난다.

| 구분 | 해제 뒤 |
|---|---|
| `/trainer/clients/{id}/…` 회원 단위 읽기·쓰기 전부(식단·사진·건강 정보·기록·조언·채팅·사진/PDF 전송·루틴·제안·프로그램·메모·할 일 등록·루틴 후보·AI 코치·리포트) | 404 |
| 회원을 붙이는 일정(`POST /trainer/schedule`·반복·`program-schedule`, `member_id` 로 옮기는 `PUT`, `member_id` 필터 조회) | 404 — 알림도 나가지 않는다 |
| 경로에 회원 id 가 없는 쓰기: 제안 승인·완료한 일정의 프로그램 전송 | 404 (`trainer_service.has_active_client_link`) |
| 해제 전에 잡아 둔 일정을 id 로 여는 쓰기: 개인운동 전송(`/routines/send`)·개인운동 처음 붙이기(`PUT /routines`, #2280)·완료(`/complete`)·수정(`PUT`)·되돌리기(`/reopen`) | 404 — 회원 운동 기록도 알림도 남지 않는다(`_ensure_session_member_linked`). 취소·삭제는 약속이 없어졌다는 통보·트레이너 자기 일정 정리라 그대로 열린다 |
| 트레이너 스케줄(일·구간 조회·예약 날짜 점·겹침 거절 응답) | 빼지 않고 **익명**으로 싣는다(#2589) — `member_detached`, 이름 `해제 회원`, `member_id`·글·프로그램·취소 사유는 비운다 |
| 해제 시점에 아직 시작하지 않은 `예정` 일정 | `취소`(사유 `담당 해제`)로 바꾸고 예약 좌석을 돌려준다(#2589). 알림은 해제 알림 한 건이 취소 수를 함께 전한다 |
| 해제 자체(`DELETE`)·재등록(`/registration`)·활성/휴면 전환(`/status`) | 링크를 직접 읽는다 — 다시 해제 404, 재등록 204(동의가 철회된 링크는 409, 아래 #1631), 상태 전환 409(기존 그대로) |
| 로스터 | 미등록(`registered=false`)으로 남는다 |
| 내가 남긴 할 일의 조회·수정·완료, 제안 치우기 | 그대로 — `trainer_id` 만 본다 |
| 해제 전 채팅 첨부 | 이미 막혀 있었다(`chat_attachments`) |

휴면(`dormant`)은 담당 해제가 아니므로 전부 그대로 열린다. 기록 자체는 지우지 않으므로
재등록하면 다시 열린다.

### 상담 수락은 등록이 아니다 (#2584)

회원은 담당 여부와 관계없이 헬스장 찾기 → 트레이너 상세 → 열린 상담 시간 → 상담 요청을
보낸다. 트레이너의 수락은 **상담 일정 확정**이다 — 담당 링크·헬스장 연결·건강 목표는 만들지
않는다. 등록하기로 하면 상담 현장에서 회원이 띄운 6자리 코드로 연결한다
(`redeem_pairing_code`). 수락만으로 담당이 되면 등록하지 않은 사람의 식단·기록까지 열린다.

| 단계 | 트레이너가 보는 것 | 동의 |
|---|---|---|
| 상담 요청·수락 | 이름·운동 목표·건강 목적·문의 글(인박스, 상담 일정 카드의 `상담 요청 내용`) | 신청 때 "상담 신청 정보 전달" 동의(`ConsultationRequest.data_consent_at`). 링크로 옮기지 않는다 |
| 코드 연결 뒤 | 식단·운동·신체 정보·건강 목표 | 코드 발급 때 공유 동의(발급 시각이 `TrainerClient.data_consent_at`) |

- 수락이 만드는 일정은 `type="상담"`·`note=""`·`consultation_id` 다. `note` 는 트레이너만
  보는 상담 메모 자리(#2574)라 회원 문의 글을 넣지 않는다.
- 상담 일정은 연결 여부와 관계없이 이름·요청 내용 그대로 트레이너 스케줄에 보이고, 연결 전에도
  메모 수정·완료·재개가 된다(`_is_consultation_booking` — `_ensure_session_member_linked` 가
  통과시킨다). 해제된 담당의 PT 일정은 `해제 회원` 익명 기록으로만 남고(#2589), 해제 때 남은
  일정을 거둘 때도 회원이 직접 신청한 상담은 거두지 않는다.
- 다른 트레이너의 담당 회원이어도 수락은 막지 않는다. 회원당 활성 담당 1명은 코드 연결이 지킨다.
- 코드로 연결되면 같은 트레이너·회원이라 상담 일정이 담당 회원 일정으로 그대로 이어지고,
  회원 건강 목표가 비어 있으면 그 트레이너에게 수락된 가장 최근 상담의 운동 목표로 채운다
  (`carry_consultation_into_link`, #1818). 회원이 마이페이지에서 고른 목표가 우선이다.
- 상담 일정을 취소하거나 진행 전에 삭제하면 상담 요청도 `cancelled`(처리자 = 트레이너)가 되고
  신청 때 잠근 자리가 풀린다(`consultation_service.withdraw_for_trainer_schedule`, #2758).
  날짜·시각을 옮기면 요청은 `accepted` 로 두고 옛 자리만 풀어 요청에서 끊는다
  (`release_slot_for_moved_schedule`) — 회원 응답의 시각은 일정 값을 따른다. 모두 일정 변경과
  같은 트랜잭션이다.

트레이너 웹은 회원 단위 요청이 404 로 돌아오면(`ClientAccessInterceptor`) 명단만
곧바로 다시 읽는다. 명단에서 빠진 회원은 상세·메시지·리포트가 원래의 '찾을 수 없음'
상태로 보여 준다.

### 담당 해제 = 데이터 공유 동의 철회 (#1631)

링크의 `data_consent_at`(동의 시각)은 #1022 에서 생겼지만, 해제해도 그대로 남아 같은
트레이너와 다시 이어지면 새 동의 없이 옛 동의가 되살아났다. 철회했다는 사실도 남지 않았다.
그래서 **담당 해제를 동의 철회로 본다.** 규칙은 `data_consent_service` 한 곳에 있다.

| 경로 | 동의 |
|---|---|
| 회원 해제(`DELETE /me/coach`·`/me/coach/trainer`)·트레이너 해제(`remove_client`) | `data_consent_at` 을 비우고 `data_consent_revoked_at` 에 시각(멱등 — 처음 시각 유지) |
| 회원·트레이너 탈퇴 | 링크 행이 `CASCADE` 로 사라진다 — 남는 동의가 없다 |
| 다른 트레이너로 옮김 | 옛 링크는 해제 때 철회, 새 링크는 새 동의 |
| 되살리기(`attach_member_to_trainer` — 담당 요청 수락·연결 코드) | 그 연결의 동의만 적는다(`grant`). 없으면 비운 채 둔다. 철회 시각은 이력으로 남긴다 |
| 트레이너 혼자 재등록(`restore_client`) | 동의가 철회된 링크면 409(`ClientConsentRequired`) — 회원이 끊은 관계를 트레이너가 혼자 되돌리면 동의하지 않은 트레이너에게 다시 묶인다 |

- **열람 판단**(`blocks_access`): 철회 시각이 있고 동의가 비어 있으면 막는다.
  `_require_client`·`has_active_client_link`(제안 승인·일정 id 경로)·`/program-schedule`·채팅 첨부·로스터 카드의 회원 데이터가 이 판단을 본다 — 해제된 회원과 같은
  404·같은 문구이고, 로스터 카드는 이름만 남는다. 동의 기능 이전 링크(둘 다 비어 있음)는 막지 않는다.
- 동의 없이 살아 있는 링크에 회원이 담당 요청을 수락하거나 연결 코드를 주면 그 시각이 새 동의다.
- **이미 트레이너에게 간 기록은 지우지 않는다.** 채팅·리포트·일정·루틴은 두 사람이 함께 쓴
  기록이다. 철회는 앞으로의 열람만 막는다. 다만 회원 앱의 코치 채팅·일정·배정 루틴은 "지금의
  담당" 기준으로 읽으므로(`get_member_trainer_id`) 해제한 동안은 회원에게도 보이지 않고, 같은
  트레이너와 다시 연결하면 다시 보인다. 회원 운동 기록에 적재된 PT 는 회원의 기록이라 계속 보인다.
  회원 앱의 해제 확인 창(#2387)과 개인정보 처리방침(5항)이 같은 규칙을 안내한다.
- 마이그레이션 `0097_data_consent_revocation` 이 이미 해제된 링크의 옛 동의를 비우고 철회 시각을 적는다.
- **끊은 트레이너의 말이 AI 추천을 계속 정하지 않는다.** 식단 AI 조언·추천 메뉴는 담당 트레이너의
  최근 메시지(`diet_coach_inputs.trainer_notes`)를 넣어 만든 뒤 보관하므로, 담당이 끝나는 경로(회원
  해제·트레이너 해제·트레이너 탈퇴)가 `forget_trainer_notes` 로 이번 주·전체 조언을 지우고 추천 메뉴
  리스트를 오늘로 만료시킨다(#2386). 회원이 받은 채팅 자체는 회원의 기록이라 그대로다.
- **회원 메모(`trainer_client_memos`)는 해제해도 남기고 열람만 막는다(#2520).** 채팅·리포트와 같은
  기준이다. 출처(`trainer` 직접·`chat_insight` 채팅 감지·`exercise_memo` 운동 기록)를 가리지 않는다.

  | 경로 | 메모 |
  |---|---|
  | 회원 해제·헬스장 해제·트레이너 해제(`remove_client`) | 행은 남는다. `_require_client` 가 404 로 막는다 |
  | 트레이너 혼자 재등록(`restore_client`) | 409 — 메모도 닫힌 채다 |
  | 회원의 새 동의로 같은 트레이너와 다시 연결 | 옛 메모가 그대로 다시 보인다 |
  | 다른 트레이너에게 옮김 | 새 트레이너에게 넘어가지 않는다 — 메모는 (트레이너, 회원) 쌍의 것이다 |
  | 트레이너 탈퇴·회원 탈퇴 | `trainer_id`·`member_id` 의 `users.id` `CASCADE` 로 함께 지워진다 |

  지우지 않는 까닭: 다시 보려면 회원의 새 동의가 꼭 있어야 하고(`restore_client` 409), 그때는
  채팅·리포트도 함께 다시 보인다. 채팅 감지 메모는 회원 글의 원문이 아니라 트레이너 웹이 만든
  요약(`무릎 불편 감지`)이고, 원본인 채팅이 남으므로 메모만 지워도 남는 정보는 줄지 않는다.
  해제된 동안 메모는 어디에도 쓰이지 않는다 — 메모를 읽는 AI 루틴 후보
  (`trainer_routine_options_service`)도 `_require_client` 를 지난 뒤에만 돈다. 식단 AI 조언을
  지우는 것(위 항목)은 해제된 동안에도 회원 화면에 끊은 트레이너의 말이 남기 때문이라 경우가 다르다.
  `test_data_consent_revocation.py` 의 메모 테스트가 이 기준을 고정한다.

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
  `gym_id`가 없는 프로필도 마찬가지로 **409**다(#2543). 예전에는 직접 입력을
  허용했지만, 직접 적은 이름은 `gym_id`가 비어 회원에게 노출되지 않는데도 트레이너
  화면에는 소속이 있어 보였다.
- **헬스장 찾기**(#2543): 트레이너는 `GET /trainer/gyms/search`로 헬스장을 찾아
  고른다. 이미 `places`에 있는 헬스장(`registered=true`)은 `PUT /trainer/me/gym`,
  카카오에서 찾은 새 헬스장은 `PUT /trainer/me/gym/kakao`로 고르며, 서버가 카카오를
  다시 검색해 확인한 뒤 `places`(`category='fitness'`)·`gym_profiles`(`is_partner=false`)에
  넣는다. `places.id`는 카카오 장소 id를 그대로 쓴다 — 시드의 카카오 발견 헬스장과
  같은 규칙이라 같은 헬스장은 한 행으로 모인다. 규칙: **목록에 들어가는 헬스장 =
  카카오에 있는 실제 헬스장(`스포츠시설` 카테고리)**.

### 트레이너 운영자 승인 (#2825, `0132_trainer_verification`)

헬스장이 실재해도 **그 사람이 그 헬스장 트레이너인지는** 소속 선택만으로 알 수 없다.
공개 가입 트레이너는 `TrainerProfile.verification_status='pending'` 으로 시작하고, 운영자가
`POST /admin/trainers/{id}/approve` 로 승인해야 회원에게 닿는다.

- 승인 전(`pending`)·반려(`rejected`) 트레이너는 회원 앱 디렉터리(`gym_service._trainer_query`),
  상담 대상(`consultation_service._validate_target`), 연결 코드·담당 요청 발송
  (`RequireApprovedTrainer`, 403 `trainer_not_approved`)에서 빠진다. 반려 뒤 남은 담당 요청은
  회원이 수락할 수 없다(404).
- 프로필·소속·비밀번호·탈퇴 같은 계정 관리는 승인과 무관하게 열려 있다 — 운영자가 판단할
  내용을 채워 두는 시간이다.
- 반려는 **새 연결만** 막는다. 이미 맺은 담당·받은 상담은 그대로다.
- 처리 시각·처리자·반려 사유는 `verification_decided_at`·`verification_decided_by`·
  `verification_note` 에 남고, `GET /trainer/me` 의 `verification` 으로 트레이너 웹에 간다.
- 기존 트레이너와 시드 트레이너는 `approved` 다(마이그레이션 백필·ORM 기본값). DB 기본값은
  `pending` 이라 ORM 밖에서 넣은 행은 닫힌 쪽에서 시작한다.

## 4. 트레이너 API (`/v1/trainer/*`, RequireTrainer)

| Method | Path | 설명 |
|---|---|---|
| GET | `/trainer/me` | 내 트레이너 프로필 |
| PUT | `/trainer/me` | 프로필 부분 수정(보낸 필드만; 이름/이메일은 계정 소관, `gym_*` 는 409) |
| PUT | `/trainer/me/gym` | 소속 헬스장 설정·변경(fitness `Place`만; 없으면 404) |
| GET | `/trainer/gyms/search?query=&lat=&lng=` | 소속으로 고를 헬스장 검색 — 등록된 헬스장 먼저, 카카오 결과 뒤(#2543) |
| PUT | `/trainer/me/gym/kakao` | 카카오 검색 결과로 소속 설정 `{kakao_place_id, name}` — 카카오로 재확인, 아니면 404, 카카오 불가 503(#2543) |
| DELETE | `/trainer/me/gym` | 소속 해제(원래 없어도 200) |
| POST | `/trainer/me/password` | 비밀번호 변경(현재 비밀번호 확인). 성공하면 토큰 세대를 올려 다른 기기 토큰을 끊고, 요청 기기용 새 토큰 한 쌍을 돌려준다(#2766) |
| GET | `/trainer/me/settings` | 알림 수신 설정 |
| PUT | `/trainer/me/settings` | 알림 수신 설정 부분 수정 |
| GET | `/trainer/clients` | 회원 로스터(회원 실데이터 집계) — 기본 50명, `after_id` 로 이어 받기 (#980) |
| PUT | `/trainer/clients/{member_id}/status` | 활성/휴면 전환(담당 관계는 유지, #707) |
| GET | `/trainer/clients/{member_id}/diet?date=` | 해당 회원의 실제 식단 기록 |
| GET | `/trainer/clients/{member_id}/diet/days?from=&to=` | 기간의 날짜별 식단 합계 — 회원 API `GET /diet/days` 와 같은 응답. 기간 그래프가 쓴다. `from` 생략 시 그 회원의 첫 기록일부터 (#2236) |
| GET | `/trainer/clients/{member_id}/records/span` | 그 회원이 식단·운동을 처음 남긴 날 — `전체` 그래프의 시작점 (#2079) |
| GET | `/trainer/clients/{member_id}/exercise/weeks?from=&to=` | 구간이 걸친 주들의 운동 집계 — 회원 API `GET /exercise/weeks` 와 같은 응답. `전체` 그래프가 쓴다 (#2247) |
| GET | `/trainer/clients/{member_id}/diet-recommendations` | 회원에게 추천할 AI 식단 후보(4주 추천 메뉴 리스트에서 급한 태그 순)와 지금 확정한 추천·해소 여부 (#2378) |
| PUT | `/trainer/clients/{member_id}/diet-recommendations` | 후보 하나를 확정·바꾸기 — 회원 앱 홈 `추천 식단` 첫 장의 `트레이너 추천` 이 된다. 리스트에 없는 메뉴는 422 (#2378) |
| GET | `/trainer/clients/{member_id}/history` | 해당 회원 운동 기록(최신순) |
| DELETE | `/trainer/me` | 트레이너 탈퇴 — 담당 회원에게 알린 뒤 계정과 딸린 데이터 삭제 (#505). 본문 `reasons`(선택, #2264) |
| GET | `/trainer/clients/{member_id}/routines` | 배정 루틴 |
| GET | `/trainer/clients/{member_id}/routines/unsent` | PT 에 붙여만 두고 아직 보내지 않은 개인운동 (#2225) |
| GET | `/trainer/clients/{member_id}/deliveries/latest` | 가장 최근 전송 한 묶음 — 종류·PT 일정·개인운동 (#2225) |
| POST | `/trainer/clients/{member_id}/routines` | 루틴 배정(단건). 시간은 `minutes` 또는 `duration_seconds` — 초가 오면 초가 기준이고 분은 반올림 (#2547). 근력은 `sets`·`reps` 또는 버티기 `hold_seconds` 를 저장한다 — 제안 생성·승인도 같다 (#2753) |
| POST | `/trainer/clients/{member_id}/program` | 프로그램 배정 — 세션당 루틴 한 건 (#709). `delivery_kind`·`trainer_message`·`start_date`·`active_days` 로 프로그램 만들기의 `개인운동만` 전송을 받는다. `active_days` 만큼만 회원 목록에 걸어 둔다(`active_from`~`ended_on`, #2161) — `개인운동만` 은 7 을 보내 보낸 날부터 한 주 동안 걸리고, 다음 주 분은 트레이너가 다시 보낸다 (#2223). 보낼 때 이 트레이너가 보내 둔 이전 개인운동(`delivery_kind` 있는 줄)은 PT 와 함께 보낼 때처럼 오늘부로 내린다 (#2514). `suggestion_ids` 로 개인운동을 채운 대기 중 AI 제안 id 를 받으면 배정과 같은 트랜잭션에서 그 제안을 `consumed` 로 닫는다 — 검토 목록·회원 목록 어디에도 다시 뜨지 않고 백로그 한도에서도 빠진다. 이 트레이너·이 회원의 대기 제안이 아닌 id 는 무시한다 (#2747) |
| POST | `/trainer/clients/{member_id}/program-schedule` | 프로그램 탭 `일정 추가` — 배정과 PT 일정 등록을 한 트랜잭션으로, `client_request_id` 로 재시도 멱등 (#1580). 고른 시간대와 겹치는 예정 세션에 연결하고 없으면 새 일정, 여럿이면 `session_id` 필수(아니면 409 + 후보) (#1581). `suggestion_ids` 는 `program` 과 같은 규약으로 같은 트랜잭션에서 대기 제안을 닫는다 — 등록이 실패하면 제안도 대기로 남는다 (#2747) |
| GET | `/trainer/schedule/{session_id}/routines` | 그 PT 일정에 붙어 있는 개인운동 — 보낸 것까지, 건마다 `pending_send` (#2223, #2224) |
| PUT | `/trainer/schedule/{session_id}/routines` | 그 PT 에 붙은 개인운동 고치기 — 보내지는 않는다 (#2224). 붙은 것이 없으면 처음 붙인다 — 일정 상세에서 코칭 탭의 개인운동 단계로 가 짠 것. 회원·PT 프로그램이 있고 아직 보내지 않은, 취소·노쇼가 아닌 PT 만이고 출처는 받은 그대로다 (#2280). `suggestion_ids` 를 주면 그 개인운동을 채운 이 회원의 대기 중 AI 제안을 같은 트랜잭션에서 `consumed` 로 닫는다 — 실패하면 대기로 남는다 (#2747) |
| PUT | `/trainer/clients/{member_id}/routines/{routine_id}` | 루틴 부분 수정(이름·시간·종류·사유). `duration_seconds` 를 보내면 분을 초에서 다시 접고, `minutes` 만 보내면 예전 초를 지운다 (#2547) |
| DELETE | `/trainer/clients/{member_id}/routines/{routine_id}` | 루틴 철회 |
| GET | `/trainer/clients/{member_id}/memos` | 회원 메모 목록(최신순) |
| POST | `/trainer/clients/{member_id}/memos` | 메모 작성 (`insight_id?` 로 채팅 인사이트 중복 방지, `source=exercise_memo` 는 `ref_id`(이력 카드) 또는 `ref_date`(회원 직접 기록 카드)로 기록을 가리키고 서버가 `ref_kind`·`ref_date`·`ref_name` 을 채운다 — 트레이너 화면에 보이지 않는 기록이면 404). `category`(`exercise`\|`diet`\|`pain`\|`life`\|빈 문자열)는 직접 메모가 고르고, `exercise_memo` 는 서버가 `exercise` 로 채운다(다른 값 422), `chat_insight` 는 분류를 보내면 422 (#2622) |
| PUT | `/trainer/clients/{member_id}/memos/{memo_id}` | 메모 본문·분류 수정. 분류는 직접 쓴 메모만 바뀐다 — 다른 출처의 분류를 바꾸려 하면 400, 지금 값 그대로면 통과 (#2622) |
| GET | `/trainer/clients/{member_id}/feedbacks` | 회원과 주고받은 피드백 모아 보기(최신순, 최근 90일, 최대 100건, #2615). `[{ id, kind(pt_session\|report\|weekly), direction(to_member\|from_member), date, body, schedule_id?, week_start?, at?, condition, intensity, pain_area, pain_on }]`. PT 는 내가 지도한 완료 PT(상담 제외)의 글, 리포트는 내가 보낸 리포트 메시지(주마다 가장 최근 하나), 주간 피드백은 이 담당이 시작된 주(`data_consent_at`)부터 |
| DELETE | `/trainer/clients/{member_id}/memos/{memo_id}` | 메모 삭제 |
| POST | `/trainer/schedule/recurring/preview` | 반복 설정이 만들 회차와 겹치는 기존 일정 |
| POST | `/trainer/schedule/recurring` | 주간 반복 회차 일괄 등록(전부 아니면 전무, 409 에 충돌 목록) |
| POST | `/trainer/schedule/{session_id}/cancel` | 일정 취소 기록(`source`=member\|trainer\|other, `reason?`). 회원 예약으로 생긴 일정이면 예약을 거두고 슬롯 좌석을 돌려준다(#2283). 상담 요청으로 생긴 일정이면 요청을 `cancelled` 로 바꾸고 신청 때 잠근 자리를 돌려준다(#2758) |
| POST | `/trainer/schedule/{session_id}/no-show` | 노쇼 기록. 시작 시각(KST) 전이면 400 (#2760) |
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
| GET | `/trainer/schedule?from=&to=&member_id=` | 구간 조회 / 회원 필터. 각 일정에 담당 회원 `member_id` 를 싣는다(가망 고객·공백은 null, #2586). 담당이 끊긴 회원의 일정은 `member_detached: true`·`해제 회원` 으로 가려 싣는다(#2589). 회원 예약 슬롯으로 생긴 일정은 `is_reservation: true` (#2756) |
| GET | `/trainer/schedule/booked-dates` | 예약 있는 날짜 |
| POST | `/trainer/schedule` | 예약 생성(예정, `client_request_id?`) |
| PUT | `/trainer/schedule/{id}` | 예약 수정. 완료·취소·노쇼 세션은 `note`·아직 보내지 않은 `program` 만(그 밖은 409, #2754). 회원 예약 일정도 `note`·`program` 만(#2756) |
| DELETE | `/trainer/schedule/{id}` | 예약 삭제. 회원 예약 일정은 409 — 취소로 거둔다(#2756) |
| POST | `/trainer/schedule/{id}/complete` | 세션 완료(예정→완료). 시작 시각(KST) 전이면 400 (#2760) |
| POST | `/trainer/schedule/{id}/reopen` | 완료 세션을 미래 날짜의 예정으로(`date`, 선택 `time`·`duration_minutes`). 겹치면 아무것도 바꾸지 않고 409 `schedule_overlap` (#2757) |
| GET | `/trainer/dashboard/task-progress` | 오늘 할 일 진행 상태 — 보관 기간(63일) 안의 날짜별 기록 |
| PUT | `/trainer/dashboard/task-progress/{date}` | 그날 진행 상태 통째로 저장(KST 오늘·어제만) |
| POST | `/trainer/dashboard/task-progress/{date}/keys` | 할 일 키 하나 체크·해제·삭제 — 그날 행에 그 키만 반영하고 합계는 서버가 다시 냄(KST 오늘·어제만, #2886) |
| POST | `/trainer/clients/{member_id}/ai-coach` | 담당 회원 데이터 기반 AI 코칭 질의 |
| GET | `/trainer/clients/{member_id}/report?week_start=` | 주간 리포트(어느 요일을 줘도 그 주 월요일로 정규화) |
| GET | `/trainer/clients/{member_id}/report/summary?week_start=` | 주간 리포트 AI 요약(머리 문장 + 근거 최대 3줄) |
| POST | `/trainer/clients/{member_id}/report/send` | 리포트를 회원 채팅 스레드로 전송 |
| POST | `/trainer/clients/{member_id}/report/send-pdf` | 리포트 PDF 를 회원 채팅 스레드로 전송 — `message` 필수, 공백뿐이면 422 (#2771) |

리포트 요약(`headline`·`points`)과 리포트 본문의 초안 문장(`message`, 본문 없이 보낸
`report/send` 가 쓰는 글)은 요청의 `Accept-Language` 언어로 만든다(#2298). `en` 이면
근거 문장·규칙 기반 머리 문장·모델 지시문이 모두 영어이고, 헤더가 없거나 `ko` 면
지금까지와 같은 한국어 문장이다. 판정(주의사항·기준값)은 언어와 무관하다. 저장하지
않고 요청마다 만드는 값이라 DB 에 언어가 남지 않는다 — 회원에게 실제로 나간 글만
채팅 행으로 남는다.

채팅 발신과 스케줄 생성의 `client_request_id`는 선택값이다. 클라이언트는 한
사용자 행동에 한 번 생성하고 응답 유실 뒤 재시도에서 같은 값을 보낸다. 같은 사용자·
동작·키·payload면 처음 생성된 결과를 다시 반환하고, 같은 키에 다른 payload면
`409`다. 키가 없는 구버전 요청은 기존처럼 매번 새 행을 만든다. 채팅은 발신자까지
scope에 포함해 회원과 트레이너가 우연히 같은 키를 만들어도 충돌하지 않는다.

### 시간 겹침 (#2284)

한 트레이너의 일정은 시간이 겹치면 안 된다. 겹침은 `(날짜, 시작 시각, 길이)` 로 만든
반열린 구간 `[시작, 끝)` 끼리 본다 — 10:00(60분)과 10:30 은 겹치고, 10:00–11:00 과
11:00 시작은 이어질 뿐이다. 길이 0인 일정은 시작 1분, 자정을 넘는 일정은 다음 날까지
차지한다. 시간을 차지하는 상태는 `예정`·`완료` 뿐이다(취소·노쇼·공백은 빈 시간).

판정은 `trainer_service.conflicting_sessions` 한 곳에 있고 아래 경로가 모두 쓴다.
겹치면 **409** `detail = { code: "schedule_overlap", message, conflicts[] }` 다.

| 경로 | 비교에서 빼는 것 |
|---|---|
| `POST /trainer/schedule` · `POST /trainer/schedule/recurring`(+ preview) | — |
| `PUT /trainer/schedule/{id}` (날짜·시각·길이를 바꿀 때만) | 자기 자신 |
| `POST /trainer/clients/{id}/program-schedule` (새 일정을 만들 때만) | — |
| `POST`·`PUT /trainer/reservation-slots` (열려 있는 자리만) | 그 자리의 예약이 만든 일정 |
| `POST /reservations` (회원) | — · 응답에 `conflicts` 없음 |
| `POST /trainer/consultations/{id}/accept` | — |

회원 예약 응답에는 `conflicts` 를 싣지 않는다 — 트레이너의 다른 일정(남의 이름·시각)이다.

반대 방향도 있다(#2761). 자리를 **연 뒤에** 그 시간에 일정이 생기면 위 경로들은 막지 않는다
— 일정 저장은 자리를 보지 않는다. 대신 자리 목록을 만들 때마다
`reservation_service.overlapped_slot_ids` 가 같은 규칙으로 판정해 `overlapped` 를 싣는다
(그 자리의 예약·상담이 만든 일정은 뺀다). 회원 목록은 마감, 상담 신청 폼은 제외, 트레이너
슬롯 창은 `일정과 겹침` 이다. 자리를 닫지 않으므로 일정을 취소·이동하면 다시 빈 자리가 된다.

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

`conditions`(1000자)의 길이 상한도 같은 자리에 있다. 컬럼이 `Text` 라 500 은
아니었지만, 회원 경로에만 상한이 없어 20만자가 200 으로 저장됐다. 자유 서술
회원 목표(`goals`)는 건강 목표 칩으로 대체되어 컬럼째 없앴다(#2358).
그 안에서 목표 칩을 뺀 글(건강상태·주의사항)은 500자로 한 번 더 막는다(#2618).
회원도 온보딩·MY 에서 같은 글을 적으므로 세 경로 모두 같은 검사
(`check_conditions_notes`)를 쓴다(#2619). 회원이 이 글을 고치면 담당 트레이너에게
`trainer_health_notes` 알림이 가고, 트레이너 웹은 누르면 신체·목표 창의 `건강 목표`
탭을 바로 연다. `바꾼 사람` 기록은 목표 칩(`focus_changed_*`)과 따로
`notes_changed_*`(`0131_health_notes_changed`)에 남긴다(#2942) — 하나로 묶으면 칩의
`마지막 변경` 이 주의사항만 고친 저장에도 움직인다. 두 앱 모두 `건강 목표`·
`건강상태·주의사항` 제목 줄 끝에 구획마다 `마지막 변경: 회원 · 10월 2일` 을 따로 단다
(트레이너 웹 편집 중에는 주의사항 줄 끝이 메모 안내로 바뀐다). 트레이너가 고친
주의사항은 회원에게 알리지 않고 이 줄로만 보인다 — 수치 목표와 같은 규칙이다.

두 앱 화면은 `oncare_ui` 의 `AppGoalRanges` 로 **같은 숫자**를 미리 보여 준다.
값을 바꿀 때는 서버 모듈과 그 파일을 함께 고친다 — 한쪽만 고치면 화면은
괜찮다는데 저장이 422 로 떨어지는 자리가 생긴다.


### 실효 단백질 목표 (#2898)

개인 단백질 목표 칸은 비어 있는 경우가 많다. 그때 식단 분석·조언·추천 식단은
**체중 × 1.2g, 체중도 없으면 60g** 으로 판단한다(`diet_coach_inputs.effective_protein_g`).
화면은 한동안 100g 을 분모로 써서, 하루 70g 을 먹은 날 카드는 "70 / 100g" 으로
모자라 보이는데 바로 아래 분석은 목표를 채웠다고 말할 수 있었다.

이제 서버가 같은 규칙으로 계산한 값을 내려 준다 — 트레이너 회원 건강 프로필의
`effective_daily_protein_g`, 주간 리포트의 `effective_protein_target`. 트레이너 웹
영양 요약 카드와 리포트 막대가 개인 목표가 없을 때 이 값을 쓰고, 옛 응답이면
같은 규칙을 앱에서 계산한다. 개인 목표 필드(`daily_protein_g`·`protein_target`)는
그대로 null 이라 '이 회원이 정한 목표'인지 기본값인지 계속 가를 수 있다.

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
  하나당 한 행이다.
- **체크·해제·삭제는 키 단위로 보낸다**(`POST …/{date}/keys`, #2886). 예전 앱은 그날
  목록 전체를 통째로 덮어써(PUT) 두 탭·기기에서 서로 다른 할 일을 체크하면 나중에
  도착한 쪽이 앞의 체크를 지웠다. 서버는 행을 잠그고(`FOR UPDATE`) 저장된 집합에 그
  키만 더하거나 빼며, 지운 키는 되살리지 않는다. 그날 목록은 요청의 `keys`(화면이
  보여 주는 미션) + 화면이 모르는 저장 키(`seen` 밖)이고, 합계·이월 완료(전날
  `pending_keys` 와 겹치는 완료)는 서버가 다시 낸다. 응답은 반영 뒤 그날 상태라 앱이
  다른 기기의 변경까지 받는다. PUT 은 옛 앱을 위해 남긴다.
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

LLM 비용 가드로 **트레이너 id 단위 분당 한도**(`COACH_CHAT_PER_MINUTE`, 기본 20)가 걸린다(#1548).
넘기면 429 + `Retry-After` 다. 버킷이 IP 가 아니라 트레이너라 같은 헬스장의 다른 트레이너가
한도를 대신 소진하지 않는다. 질문은 1000자까지다(회원 AI 코치와 같음).

### 주간 리포트 (`/trainer/clients/{id}/report`)

O2O 코칭의 재등록 고리. 세션 수·완료 수는 `trainer_schedule`, 이행률은
`routine_history`, 나트륨은 `diet_entries`에서 그 주만 집계한다 — 새로 수집하는
데이터는 없다. **기록이 없는 항목은 0 이 아니라 `null`** 로 내려간다("이행률 0%"는
"안 했다"는 거짓말이 되므로). 전송은 별도 리포트 함이 아니라 **회원이 이미 읽고 있는
채팅 스레드**로 들어간다.

**회원 본인 경로 (#2652)**: 회원 앱 결과지는 `GET /me/coach/weekly-report` 로 같은
`build_weekly_report` 를 부른다 — 같은 회원·같은 주면 두 앱이 **같은 값**을 읽는다.
두 가지만 다르다. 자동 초안 `message` 는 트레이너가 손보고 보낼 글이라 빈 문자열로
나가고, 담당 트레이너가 없어도(포인트 교환 리포트, #2022) 200 이며 그때 수업 칸은 0 이다.
트레이너 메모·다른 회원·리포트 요약 같은 트레이너 몫은 이 응답에 애초에 없다.

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
- 카드의 `age` 는 `HealthProfile.birth_date` 로 센 만 나이(KST 오늘 기준)다. 성별·목표와 같은
  배치 조회에서 읽고, 연결 확인 카드(`PairedMemberOut.age`)와 같은 `profile_format.age_on` 으로
  센다. 생년월일이 없거나 읽히지 않으면 `null` — 앱이 나이를 지어내지 않는다(#2744).
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

### AI 운동 추천의 언어 (#2301)

요청의 `Accept-Language`(#2297)로 언어를 고른다. 헤더가 없거나 `ko` 면 지금까지와 같은 한국어다.

- **개인운동 후보의 근거(`RoutineOut.evidence`)는 코드다** — `recent_pt_feedback`,
  `strength_heavy`, `blood_pressure_goal`, `low_cardio`, `recent_record`. `recent_pt_feedback` 은
  최근 완료한 PT 일정에 글이 있을 때만 붙는다(개인 운동 피드백은 #2517 에서 뺐다). 트레이너 웹이 화면
  언어로 바꿔 보여 주고, 모르는 값은 원문 그대로 보인다. 코드 도입 전에 문장으로 저장된 행은
  읽을 때 코드로 돌려준다(`routine_suggestion_service.LEGACY_EVIDENCE_LABELS`).
- **후보 이름·`reason`, AI A/B(`/routine-options`)의 이름·사유·근거 문장, 시작 템플릿
  (`starter:*`)** 은 요청한 트레이너의 언어로 만든다. AI 가 실패했을 때의 규칙형 폴백도 같다.
  `intensity`·`type` 은 번역하지 않는 계약값(한국어 Literal)이다.
- **AI 제안 사유는 트레이너가 읽는 판단 재료다(#2579).** `reason` 은 "이 회원의 어떤 기록 때문에
  올라왔나" 를 기록 숫자(최근 2주 운동 시간·근력 비중·PT 뒤 며칠)로 말한다. 회원에게 가지 않는다 —
  회원 응답은 근거가 있는 행(= AI 제안)의 `reason` 을 비우고, 회원 카드에는 효과 한 줄(`effect`,
  #2570)이 선다. 트레이너 웹 위저드는 이 문장을 운동 이름 바로 아래 라벨·근거 태그 없이 둔다.
  PT 메모는 내용을 읽지 않고 있는지만 보므로 문장에서 "피드백" 이라고 단정하지 않는다(#2374).
- **하루 후보는 최대 세 건이다(#2703).** 회복·유산소 후보 뒤에 세트·횟수가 있는 맨몸(0kg) 근력 후보
  하나가 온다 — 혈압 관리 회원은 벽 푸시업, 근력이 몰린 회원은 힙 브리지, 그 밖에는 맨몸 스쿼트.
  트레이너 웹 데모의 개인운동 단계(회원마다 세 건·근력 하나, #1321)를 실서버가 따른다. 검토 대기는
  하루치의 두 배(여섯 건)가 쌓이면 더 만들지 않는다.
- 트레이너가 저장한 템플릿과 회원 기록에서 온 운동 이름은 사람이 쓴 글이라 옮기지 않는다.

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
| POST | `/me/coach/routines/{id}/complete?date=` | 그날 완료(`date` 없으면 오늘). 지난 날짜는 그날 걸려 있던 배정만(#2506), 미래는 422 |
| DELETE | `/me/coach/routines/{id}/complete?date=` | 그날 완료 되돌리기(`date` 없으면 오늘) |
| GET | `/me/coach/sessions` | 내 PT 세션(최근 100건) |
| GET | `/me/coach/chat` | 채팅 스레드 |
| GET | `/me/coach/chat/unread` | 미확인 수 |
| POST | `/me/coach/chat` | 코치에게 메시지 전송 (`client_request_id?`) |
| POST | `/me/coach/chat/read` | 읽음 처리 |
| GET | `/me/coach/weekly-report?week_start=` | 내 주간 리포트 — 트레이너 리포트와 같은 값(`message` 는 빈 문자열, 담당 없어도 200, 미래 주는 422) (#2652) |
| DELETE | `/me/coach` | **헬스장 + 담당 트레이너** 해제(멱등, 204) |
| DELETE | `/me/coach/trainer` | **담당 트레이너만** 해제 — 헬스장은 유지(멱등, 204) |

- 담당 코치는 **active 링크**만 인정(`get_member_trainer_id` → `active.is_(True)`).
  휴면 링크만 있으면 코치 조회/발신 불가(404/빈 목록).
- `/me/coach/sessions`는 시간이 지나며 누적되는 PT 세션을 **최근 100건**으로 상한.
- `/me/coach/sessions`의 `note`는 **완료된 PT** 것만 싣는다(#2515). PT 일정의 `note`는 회원에게 보내는 트레이너 피드백이고, 상담 일정의 `note`는 트레이너만 보는 상담 메모다. 예정·취소·노쇼 PT 와 상담 일정의 `note`는 빈 문자열로 나간다. 트레이너 응답(`/trainer/schedule`)은 그대로 전부 준다.

### 추천 개인운동의 효과 한 줄 (#2570)

회원 앱 추천 개인운동 카드는 운동 이름 바로 아래에 `RoutineOut.effect` 를 한 줄로 보인다.
트레이너가 운동마다 효과를 적지 않아도 되게 **자동으로 채우고, 고치고 싶을 때만 고친다.**

- **저장은 트레이너가 적은 것만.** `trainer_routines.effect`(String(40), `0103_routine_effect`)는
  트레이너 웹이 보낸 글자다 — `PersonalRoutineItem.effect`(PT 에 붙인 개인운동·일정 개인운동 수정),
  `ProgramDraftExercise.effect`(`개인운동만`: 세션마다 운동이 하나라 그 운동의 효과가 배정의 효과).
- **비어 있으면 응답 때 채운다.** 운동 유형 × 회원 **첫** 건강 목표(`health_profiles.conditions`)
  문구표(`app/data/routine_effects.py`, 원본 `shared/routine_effects/routine_effects.json`)다.
  AI 를 부르지 않는다. 저장하지 않고 응답 때 채우는 이유는 배정 길이 여럿(단일 배정·AI 제안·
  담당 없는 회원의 자동 추천·프로그램·일정 개인운동)이라 한 곳(`_routine_out`)에서 채워야 빠짐이
  없고, 회원이 목표를 바꾸면 문구도 따라가야 해서다. 운동 여럿으로 짠 세션과 `기타` 유형은 비운다.
- **`reason` 과 섞지 않는다.** `reason` 은 AI 추천 사유(트레이너 판단 재료)거나 옛 배정의 운동 이름
  나열이다. 회원 앱은 효과가 있으면 `reason` 을 카드에 싣지 않고, 효과가 없는 옛 응답에서만
  예전처럼 `reason` 으로 떨어진다.
- **트레이너 웹 입력 칸**(위저드 개인운동 단계·스케줄 개인운동 창)은 같은 문구표로 자동 문구를
  placeholder 로 보인다. 비워 두면 싣지 않고, 효과만 고친 것은 운동을 고친 것이 아니라
  출처(`source`)를 바꾸지 않는다.

### 추천 개인운동은 매일 새로 체크하는 목록 (#2161)

트레이너가 목록을 바꾸기 전까지 같은 목록이 **날마다 미완료로 다시 시작**한다.

- `trainer_routines.active_from`(포함) ~ `ended_on`(이날부터 없음, 걸려 있는 동안 NULL)이
  목록에 걸린 기간이다. 배정은 배정한 날, AI 제안은 승인한 날부터 걸린다.
- **철회는 행을 지우지 않는다.** `DELETE /trainer/clients/{id}/routines/{rid}` 와 회원의
  `DELETE /me/coach/routines/{rid}` 는 `ended_on` 을 오늘로 찍는다 — 오늘 목록에서 바로
  빠지고, 지난 날짜에 걸려 있던 목록은 남는다. 이미 내려온 배정을 다시 철회하면 404.
  승인 전·거절한 후보는 회원 목록에 걸린 적이 없어 예전처럼 행째 지운다.
- 완료는 `(배정, 그날)` 에 한 번이다(`uq_exercise_sessions_routine_day`). `complete`·
  `DELETE …/complete` 는 `?date=` 가 없으면 **오늘**을 건드린다.
- **지난 날짜도 체크·해제할 수 있다**(#2506). 처음(#2161)에는 "뒤늦게 고치면 트레이너가 본
  기록과 갈린다" 는 이유로 읽기 전용이었지만, 식단·직접 기록한 운동은 지난 날짜도 고칠 수
  있고 둘 다 트레이너가 보는 기록이라 개인운동만 막을 근거가 약했다. 대신:
  - 그날 회원 목록에 걸려 있던 배정만 된다(그 뒤 내려왔어도 된다). 아니면 404, 미래는 422.
  - 기록은 그날 정오(`completed_at`)에 놓이고, 실제로 누른 때는 `created_at` 에 남는다 —
    트레이너 화면은 둘의 날이 다르면 "다음 날 이후 체크" 로 가른다.
  - 포인트 하루 한도는 **적립하는 날** 기준이라 몰아 체크해도 오늘 1회뿐이다. 보호권은
    그날 기준으로 환급되고 연속 기록은 다시 계산된다(직접 기록한 운동을 과거에 추가할 때와 같다).
  - 트레이너에게 알림은 가지 않는다.
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

마이그레이션은 단일 chain이고 계속 자라므로 끝을 문서에 적지 않는다. 현재 head 는
`cd backend && alembic heads` 로 확인하고, 새 마이그레이션의 `down_revision` 은 그 head 로 잡는다.
초기 트레이너 스택(`0012_trainer_domain` ~ `0020_gym_profiles_trainer_fk`)에서 두 `0014` 분기를
`0015_merge_alembic_heads`로 합친 기록은 [DEPLOY.md](DEPLOY.md) "마이그레이션 head 선형화" 절에 있다.

배포는 `alembic upgrade head`를 실행하며, CI에서
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

**탈퇴 사유(#2264).** 본문 `{"reasons": [...]}` 로 트레이너 탈퇴 화면에서 고른 사유를
보낼 수 있다(없어도 된다). 받는 값은 `rarely_used`·`hard_to_use`·`missing_feature`·
`leaving_work`·`found_alternative`·`other` 이고, 모르는 값은 버린다. 회원 사유와 같은
`account_deletion_reasons` 표에 **계정과 잇지 않고** `trainer_` 를 붙여 남긴다 —
표에 누가 썼는지가 없으니 코드만으로 회원·트레이너를 가른다.
