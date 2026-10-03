# 개인정보 처리 위탁·국외 이전·보관·파기 — 원본 표 (#2820)

두 앱의 개인정보 처리방침 본문(`myLegalPrivacyBody`)은 ARB 에 있다. 이 문서는 그 본문이 따르는
**원본 표**다. 처리 구조(인프라·외부 API·보관 기간·탈퇴 처리)가 바뀌면 이 표를 먼저 고치고,
아래 "본문을 고칠 때" 절차대로 네 개의 ARB 와 버전 상수를 함께 맞춘다.

| 앱 | 한국어(원본) | 영문 |
| --- | --- | --- |
| 회원 앱 | `frontend/flutter/lib/l10n/app_ko.arb` | `frontend/flutter/lib/l10n/app_en.arb` |
| 트레이너 웹 | `frontend/flutter_trainer/lib/l10n/app_ko.arb` | `frontend/flutter_trainer/lib/l10n/app_en.arb` |

> 이 표와 처리방침 문안은 법률 검토 전의 초안이다. 스토어 제출·정식 출시 전에 법률 검토를 받고,
> 아래 "확정이 필요한 값" 을 채운다.

## 1. 처리 위탁·국외 이전

| 수탁자 | 위탁 업무 | 이전 국가 | 이전 항목 | 보유 기간 | 근거(코드·설정) |
| --- | --- | --- | --- | --- | --- |
| Amazon Web Services, Inc. | 서버 운영(App Runner), 채팅 사진·리포트 PDF 보관(S3) | 싱가포르(`ap-southeast-1`) | 서버가 처리하는 회원·트레이너 정보 전반, 채팅 첨부 사진·리포트 PDF | 탈퇴 또는 위탁 계약 종료 시까지 | `.github/workflows/backend-deploy.yml` `AWS_REGION`, `backend/app/core/config.py` `attachment_storage`·`attachment_s3_*`, `backend/docs/DEPLOY.md` 5-1·리전 |
| Neon | 데이터베이스 운영(Postgres + pgvector) | 싱가포르(App Runner 와 같은 리전) | 계정·프로필·식단(음식 사진 축소본 포함)·운동·건강 기록, 대화 기록, 검색 색인 | 탈퇴 또는 위탁 계약 종료 시까지 | `backend/docs/DEPLOY.md` 1·2절, `backend/.env.aws.example` `DATABASE_URL` |
| Google LLC (Gemini API) | 음식 사진 인식, AI 코치 답변·추천, 개인 기록 검색 색인(임베딩), 트레이너 AI 프로그램·루틴 후보·리포트 요약 | 미국 등 Google 데이터센터 소재 국가 | 음식 사진, 분석에 필요한 식단·운동 기록·신체 정보·건강 목표, AI 코치 대화, 트레이너가 입력한 코칭 조건과 담당 회원 운동 기록·주간 리포트 수치 | 요청 처리 후 수탁자 약관에서 정한 기간 | `config.py` `recognizer`·`coach_llm`·`embedder` 기본값 `gemini`, `rag_auto_ingest=True`(식단·운동 저장 때마다 색인), `services/trainer_report_summary_service.py`, `services/trainer_routine_options_service.py` |
| Functional Software, Inc. (Sentry) | 앱·서버 오류 수집 | 미국 | 오류 내용, 기기·브라우저·운영체제 종류, 앱 버전. 이름·이메일·IP·헤더·쿠키·요청 본문·지역 변수는 보내기 전에 지운다 | 수탁자 보관 기간 | `backend/app/core/error_tracking.py`(`send_default_pii=False`, `scrub_event`), `frontend/flutter/lib/core/observability/error_reporter.dart`, 트레이너 웹 `sentry_flutter` |
| 주식회사 카카오 | 헬스장·장소 검색, 지도 표시 | 대한민국(국외 이전 아님) | 장소 검색 좌표(회원이 현재 위치를 허용한 경우 그 좌표), 검색어 | 수탁자 보관 기간 | `backend/app/services/places/kakao.py`, `services/trainer_gym_search.py`, `shared/oncare_kakao_map`, 두 앱 `web/index.html` CSP |

국외 이전 동의는 따로 받지 않는다. 모두 계약 이행을 위한 처리 위탁·보관이라 「개인정보 보호법」
제28조의8 제1항 제3호에 따라 처리방침 공개로 갈음한다(`backend/app/services/signup_consent.py`).

**위탁 대상이 아닌 것**

- 소셜 로그인(카카오·구글·네이버·애플): 회원이 고른 로그인 수단에서 식별자·이메일·이름을 **받는**
  쪽이라 위탁이 아니다. 처리방침 1항 수집 항목에 적는다.
- 공공 식품영양성분 DB: 서버에 적재한 참조표(`food_nutrients`)를 조회할 뿐 외부로 보내지 않는다.
- OpenAI·LiteLLM: 설정으로 고를 수 있지만 운영 기본값과 `backend/.env.aws.example` 은 Gemini 다.
  운영에서 바꾸면 이 표와 처리방침에 수탁자를 더한다.
- 메일 발송(비밀번호 재설정): `mail_provider` 의 실제 발송 업체가 아직 정해지지 않았다. 정해지면 표에 더한다.

## 2. 보관 기간

| 기록 | 기간 | 근거 | 코드 |
| --- | --- | --- | --- |
| 계정과 서비스 기록 | 탈퇴 시까지 | — | `DELETE /users/me`, `DELETE /trainer/me` |
| 로그인 등 접속 기록(`audit_logs`, 일시·IP) | 1년 | 「통신비밀보호법」 로그인 기록 3개월 이상 | `config.py` `audit_retention_days=365` |
| 트레이너 열람 기록, 데이터 공유 동의·철회, 탈퇴 기록 | 2년 | 「개인정보의 안전성 확보조치 기준」 처리 기록 | `config.py` `audit_sensitive_retention_days=730`, `services/audit.py` `SENSITIVE_EVENTS` |
| 탈퇴 사유 | 회원과 잇지 않은 사유 코드·시각만 | 개인정보 아님 | `account_deletion_reasons` |

기간이 지난 감사 기록은 서버가 기동할 때 지운다(`audit.purge_expired_best_effort`, `app/main.py`).

## 3. 파기 — 실제 동작

**회원 탈퇴** (`backend/app/api/v1/users.py` `delete_me`)

1. 대기 중 상담 요청이 잡은 자리를 풀고, 예약을 취소하고, 관련 트레이너에게 알린다.
2. 탈퇴 감사 기록을 남긴다(2년 보관).
3. `users` 행을 지운다 — 프로필·식단(음식 사진 `diet_photos` 포함)·운동·알림·소셜 연결·개인 코치 문서(검색
   색인)·채팅·담당 연결이 `users.id` CASCADE 로 함께 지워진다.
4. 커밋 뒤에 채팅 첨부(사진·리포트 PDF) 파일을 저장소(로컬 디스크 또는 S3)에서 지운다
   (`services/attachment_cleanup.py`).

남는 것: 트레이너 일정표의 지난 수업 행(`trainer_schedule`)은 `member_id` 가 SET NULL 로 비워지고
`client_name`(표시 이름)과 일시가 트레이너의 업무 기록으로 남는다. 처리방침 10항에 그대로 적었다.

**트레이너 탈퇴** (`backend/app/api/v1/trainer.py` → `services/trainer_service.py` `delete_trainer_account`)

1. 이 트레이너 슬롯의 예약을 지우고, 담당 회원의 재등록 쿠폰을 취소하고, 담당·예약 회원에게 알린다.
2. `users` 행을 지운다 — 프로필·채팅·루틴·일정·슬롯·이력·알림이 CASCADE 로 지워진다.
   회원이 보낸 상담 요청은 `trainer_id`·`decided_by` 가 SET NULL 로 남는다.
3. 커밋 뒤에 채팅 첨부 파일을 지운다.

**방법**: 운영 DB 에서 행을 지우고 파일 저장소에서 객체를 지운다. S3 버킷에 버전 관리를 켜면 지운
객체가 이전 버전으로 남으므로, 켤 때는 이전 버전 만료 규칙을 함께 건다(`backend/docs/DEPLOY.md` 5-1).
DB 복구용 기록(Neon 의 복원 기간)에 남은 사본은 그 기간이 지나면 사라진다. 첨부 삭제가 실패하면
`탈퇴 첨부 삭제 실패` 경고 로그로 남아 다시 지울 수 있다.

## 4. 수집 항목 — 실제와 대조

| 항목 | 회원 앱 | 트레이너 웹 | 근거 |
| --- | --- | --- | --- |
| 이메일·비밀번호(해시)·이름 | ○ | ○ | `users` |
| 전화번호·생년월일·성별·키·체중·목표 | ○ | 전화번호만 | `health_profiles`, `trainer_profiles` |
| 소속 헬스장·자격증·경력·전문 분야 | — | ○ | `trainer_profiles` |
| 음식 사진 | ○ | — | `diet_photos` |
| 채팅 첨부 사진·리포트 PDF | ○ | ○ | `chat_messages`, `config.py` `chat_image_storage_dir`·`report_pdf_storage_dir` |
| 접속 기록(일시·IP) | ○ | ○ | `audit_logs.ip` |
| 현재 위치 | 헬스장 찾기에서 허용한 경우만, 저장 안 함(서버 요청 로그에도 남지 않음) | — | `frontend/flutter/.../gym_location_controller.dart`, `GET /places/nearby` |
| 서버 요청 로그 | method·경로(쿼리 제외)·상태·소요시간·요청 id 만. IP·쿼리(위치 좌표·검색어)·본문은 없음 | 같음 | `app/core/observability.py` `app.access`, `scripts/start.sh` `--no-access-log`(#3031) |
| 오류 정보 | ○ | ○ | Sentry(1절) |
| 광고·분석 쿠키 | 없음 | 없음 | 두 앱 `pubspec.yaml`, `web/index.html` CSP |

## 5. 보호책임자

처리방침에는 개인 성명 대신 직책(On-Care 서비스 운영팀 개인정보 보호책임자)과 저장소에 이미 쓰이던
고객 지원 주소 `support@oncare.com` 을 적는다.

## 6. 확정이 필요한 값 (#480)

- [ ] `support@oncare.com` 이 실제로 수신되는지 확인하고, 아니면 수신 확인된 주소로 네 ARB 를 함께 바꾼다.
- [ ] 보호책임자 성명(또는 직책)을 운영 주체가 정해지면 확정한다.
- [ ] 백엔드·S3·Neon 최종 리전(현재 싱가포르). 바뀌면 1절과 처리방침 7항의 국가를 고친다.
- [ ] Sentry 데이터 보관 지역(미국/EU)과 보관 기간 — `SENTRY_DSN` 을 만들 때 정해진다.
- [ ] 수탁자 정식 법인명·연락처(특히 Neon), Gemini API 의 입력 보관 기간 — 계약·약관 확인.
- [ ] 메일 발송 업체.

## 7. 본문을 고칠 때

1. 이 문서의 표를 먼저 고친다.
2. 네 ARB 의 `myLegalPrivacyBody` 를 같은 내용으로 고친다. 한국어가 원본이고, 영문은 같은 절 번호를 쓴다.
3. 본문 끝의 개정 이력에 한 줄을 더하고 `시행일`, `myLegalPrivacyEffectiveDate` 를 새 날짜로 바꾼다.
4. `backend/app/services/signup_consent.py` 의 `CURRENT_VERSIONS["privacy"]` 를 같은 날짜로 올린다 —
   옛 버전에만 동의한 계정은 다음 로그인 때 동의 화면을 다시 거친다.
   `backend/tests/test_privacy_policy_version.py` 가 버전과 본문 시행일이 같은지 본다.
5. 두 앱에서 `flutter gen-l10n` 을 돌린다.
