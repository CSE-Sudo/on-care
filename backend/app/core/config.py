"""환경 설정. .env 에서 읽어옵니다."""
from __future__ import annotations

from functools import lru_cache
from typing import Literal, Optional

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# 개발 기본 시크릿(운영에서 그대로 쓰면 기동 차단)
DEFAULT_JWT_SECRET = "CHANGE_ME_dev_only_secret_key_please_replace_in_prod"
# 데모 계정(트레이너/회원 시드) 기본 로그인 비밀번호. 운영에서 데모 시드를 켜려면
# 반드시 이 기본값이 아닌 안전한 값으로 바꿔야 한다(아래 _guard_prod_secrets 가 강제).
DEFAULT_DEMO_PASSWORD = "oncare123"
# 운영에서 데모 시드를 켤 때 요구하는 DEMO_LOGIN_PASSWORD 최소 길이.
MIN_DEMO_PASSWORD_LEN = 12


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- 환경 ---
    env: str = "dev"  # dev | staging | prod

    # --- API ---
    api_v1_prefix: str = "/v1"
    app_version: str = "0.4.0"

    # --- Database ---
    database_url: str = "postgresql+psycopg://oncare:oncare@localhost:5432/oncare"
    # DB 커넥션 인출(연결 수립) 상한(초) — 네트워크 파티션/무응답 시 스레드 무한 점유 방지.
    db_connect_timeout_seconds: int = 5
    # 앱 기동 시 create_all() 로 테이블 생성 여부(개발 편의). 운영은 Alembic 을 정답으로 → false 권장.
    auto_create_tables: bool = True

    # --- JWT ---
    jwt_secret: str = DEFAULT_JWT_SECRET
    jwt_algorithm: str = "HS256"
    # 접근 토큰 수명(#2913). 두 앱 모두 401 을 받으면 refresh 로 새 토큰을 받아 요청을
    # 다시 보내므로 짧아도 사용자 체감이 없고, 새어 나간 토큰이 쓰일 수 있는 시간이
    # 줄어든다. 데모·개발 환경은 ACCESS_TOKEN_EXPIRE_MINUTES 로 길게 둘 수 있다.
    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 30
    # 웹 클라이언트(`X-Client-Platform: web`)가 받는 refresh 토큰 수명(#2828). 웹은
    # 토큰을 탭 단위 저장소에만 두므로 오래 갈 필요가 없고, 브라우저에서 새어 나갔을
    # 때 쓸 수 있는 기간을 줄인다. 모바일은 위 값을 그대로 쓴다.
    web_refresh_token_expire_days: int = 7
    # 토큰 없이 접근 시 데모 사용자로 폴백(개발 편의). 운영(prod)에서는 항상 비활성.
    # 기본은 꺼짐(#2821) — ENV 를 빠뜨린 채 뜬 서버가 로그인 없는 요청을 데모 회원으로
    # 처리하지 않게 한다. 로컬 개발은 .env.example 의 ALLOW_DEMO_FALLBACK=true 로 켠다.
    allow_demo_fallback: bool = False

    # --- 감사 로그 (#2830) ---
    # 트레이너의 회원 기록 열람(`trainer.client_read`)은 같은 (트레이너, 회원, 자원)
    # 조합을 이 시간(분) 안에 한 번만 남긴다 — 화면을 넘길 때마다 쌓이지 않게.
    audit_read_dedupe_minutes: int = 10
    # 보존 기간(일). 지난 기록은 기동 시 정리한다. 0 이면 정리하지 않는다.
    # 인증·계정 이벤트(접속 기록)는 1년, 건강정보 열람·동의·탈퇴 기록은 2년.
    audit_retention_days: int = 365
    audit_sensitive_retention_days: int = 730

    # --- 소셜 로그인 ---
    # Apple 로그인에서 허용할 `aud`(client_id) 목록, 콤마 구분.
    # iOS 앱은 번들 ID, 웹은 Service ID 로 서로 다른 aud 를 받으므로 복수를 허용한다.
    # 비어 있으면 Apple 로그인은 검증 불가로 **거부**된다(조용히 통과시키면 다른 앱용
    # Apple 토큰으로도 로그인이 뚫린다).
    apple_client_ids: str = ""

    # --- 장소(O2O) ---
    # 카카오 Local REST 키. 있으면 실검색, 없으면 시드 폴백(recognizer 팩토리와 같은 철학).
    kakao_rest_api_key: str = ""
    # auto: 키 있으면 kakao, 없으면 seed. 강제하려면 kakao|seed.
    places_provider: Literal["auto", "kakao", "seed"] = "auto"
    kakao_timeout_seconds: float = 3.0

    # --- 업로드 ---
    # 업로드 엔드포인트의 요청 본문 상한(바이트). 적용 경로는 main.py 의
    # RequestBodySizeLimitMiddleware 에 명시한다(전역 아님 — 대량 텍스트를 JSON
    # 으로 받는 엔드포인트까지 묶이면 기능이 잘린다).
    #
    # 회원 앱은 사진을 1600px·품질 85 로 재인코딩하고 8MiB 를 넘으면 보내지
    # 않지만, 그건 앱의 UX 보호일 뿐 API 직접 호출은 막지 못한다. 여기가 최후
    # 방어선이다.
    #
    # 값이 앱의 이미지 상한(8MiB)보다 큰 것은 의도한 것이다 — 이 한도는 multipart
    # 경계·필드까지 포함한 '요청 본문' 크기라, 8MiB 로 맞추면 정확히 8MiB 인 사진이
    # 프레이밍 오버헤드 때문에 억울하게 413 을 맞는다.
    max_upload_bytes: int = 10 * 1024 * 1024
    # 주간 리포트 PDF는 일반 파일 첨부가 아니라 전용 endpoint만 사용한다.
    # DB에는 metadata만 두고 실제 파일은 이 디렉터리에 보관한다.
    report_pdf_storage_dir: str = "data/report-pdfs"
    max_report_pdf_bytes: int = 8 * 1024 * 1024

    #: 채팅 이미지 첨부(#921). PDF 와 다른 자리에 두는 이유는 지우는 주기가
    #: 다르기 때문이다 — 리포트 PDF 는 그 주의 산출물이고, 코칭 사진은 대화의
    #: 일부로 남는다.
    chat_image_storage_dir: str = "data/chat-images"
    #: 사진 한 장의 상한. 휴대폰 카메라 원본을 그대로 올려도 걸리지 않을
    #: 정도이되, 대화 스레드가 파일 서버가 되지는 않을 정도.
    max_chat_image_bytes: int = 6 * 1024 * 1024
    #: 채팅 사진·리포트 PDF 경로의 **요청 본문** 상한은 파일 상한에 이만큼을 더한
    #: 값이다(#2832). multipart 경계·메시지 필드·client_request_id 가 함께 실려 오므로,
    #: 파일 상한과 똑같이 두면 상한에 딱 맞는 파일이 413 을 맞는다. 파일 자체의
    #: 상한은 핸들러가 바이트를 세어 따로 지킨다.
    upload_body_slack_bytes: int = 512 * 1024

    #: 채팅 첨부(사진·리포트 PDF) 바이트 저장소(#2817). auto 는 버킷 이름이 있으면
    #: s3, 없으면 local(위 두 디렉터리). 컨테이너 디스크는 재배포·스케일 아웃에서
    #: 비므로 운영은 s3 를 쓴다. 자격 증명은 실행 환경의 IAM 역할에서 받는다.
    attachment_storage: Literal["auto", "local", "s3"] = "auto"
    attachment_s3_bucket: str = ""
    attachment_s3_region: str = ""
    #: 키 접두사. 실제 키는 `<접두사>/chat-images/<id>.<ext>`·`.../report-pdfs/<id>.pdf`.
    attachment_s3_prefix: str = "chat-attachments"
    #: S3 호환 저장소·로컬 에뮬레이터를 쓸 때만. 비우면 AWS 기본 엔드포인트.
    attachment_s3_endpoint_url: str = ""

    # --- AI 엔진 ---
    recognizer: str = "gemini"        # gemini | claude(litellm) | yolo
    # 인식 후 공공 식품영양성분 DB 로 영양 수치 보강(정확도↑). 순수 LLM 비교실험 시 false.
    nutrition_db_enrich: bool = True
    #: 참조표에 바로 붙지 않는 운동 이름을 AI 로 종목에 접는다(#1312). 끄면 표
    #: 매칭만 쓰고, 안 붙는 이름은 유형 평균으로 떨어진다 — 인식기와 같은 규약이라
    #: 키가 없으면 이 값과 무관하게 조용히 폴백한다.
    exercise_name_ai: bool = True
    gemini_api_key: str = ""
    gemini_model: str = "gemini-flash-latest"  # 챗·인식 공용. 핀 버전은 은퇴로 404 → latest 별칭 사용
    # Gemini HTTP 타임아웃(초). 걸지 않으면 무응답 시 호출 스레드가 무기한 묶여
    # 워커 풀이 고갈된다(추천 경로는 스레드 풀에서 돈다).
    gemini_timeout_seconds: float = 30.0
    # 식단 사진 인식 HTTP 타임아웃(초, #2912). 사진 분석은 글 응답보다 오래 걸려
    # gemini_timeout_seconds 와 따로 둔다. Gemini·LiteLLM 비전 인식기가 함께 쓴다.
    recognizer_timeout_seconds: float = 60.0
    coach_llm: str = "gemini"         # openai | gemini | litellm
    openai_api_key: str = ""
    openai_chat_model: str = "gpt-4o"
    embedder: str = "gemini"          # openai | gemini | litellm
    openai_embed_model: str = "text-embedding-3-small"

    # --- LiteLLM 프록시 (OpenAI 호환) ---
    # 하나의 Virtual Key 로 뒤의 여러 모델(claude 등)을 호출.
    # base_url 을 넣으면 OpenAI SDK 가 이 프록시를 바라봄.
    litellm_base_url: str = ""
    litellm_api_key: str = ""                       # Virtual Key
    litellm_chat_model: str = "claude-sonnet-4-6"   # 코치/인식용 채팅 모델
    litellm_embed_model: str = ""                   # 프록시에 임베딩 모델 있으면 지정
    litellm_vision_model: str = "claude-sonnet-4-6" # 식단 인식(이미지)용

    # --- RAG ---
    # 임베딩 차원: 모델에 맞춰 바꿉니다. 바꾸면 재임베딩 필요(scripts/reembed).
    #   Gemini gemini-embedding-001        = 768 (현재 기본, EMBEDDER=gemini)
    #   OpenAI text-embedding-3-small/large = 1536 / 3072 (EMBEDDER=openai 시 EMBED_DIM=1536)
    embed_dim: int = 768
    # 청킹: 윈도우(문장 수)와 겹침(stride 보정). 최적값 찾으면 여기만 수정.
    chunk_window: int = 5      # 한 청크에 묶을 문장 수
    chunk_overlap: int = 1     # 청크 간 겹칠 문장 수
    # 검색: 개인 문서 / 공공 문서 각각 top-k
    retrieve_personal_k: int = 3
    retrieve_public_k: int = 3
    # 식단/운동/채팅 기록 시 개인 RAG 문서 자동 적재(코치가 내 최근 데이터를 검색하도록)
    rag_auto_ingest: bool = True
    # 시드 기록도 개인 문서로 적재할지 (#604). 데모 계정에서 회원 앱 AI 코치가
    # 시드된 식단·운동·대화를 근거로 답하게 한다. 멱등이라 최초 기동에서만 임베딩이
    # 돌지만, 실 임베딩 키로 처음 띄우면 그만큼 기동이 길어진다 — 끄고 싶으면 false.
    seed_rag_ingest: bool = True

    # --- 메일 발송(비밀번호 재설정, #2824) ---
    # auto: SMTP_HOST 와 MAIL_FROM 이 있으면 smtp, 없으면 log. log 는 실제로 보내지
    # 않고 서버 로그에만 남긴다(개발용). 운영에서 log 로 풀리면 재설정 요청은 503 으로
    # 꺼지고 기동 로그에 오류가 남는다(`mail_enabled`).
    # AWS SES 는 SMTP 인터페이스를 주므로 SES 도 이 smtp 구현으로 쓴다 — 계정·키는
    # 배포 환경변수로만 넣는다(코드·저장소에 두지 않는다).
    mail_provider: Literal["auto", "smtp", "log"] = "auto"
    mail_from: str = ""
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    # true: 평문 연결 뒤 STARTTLS(587). false 면 smtp_ssl 을 본다.
    smtp_starttls: bool = True
    # true: 처음부터 TLS(465). starttls 와 함께 켜면 ssl 이 우선한다.
    smtp_ssl: bool = False
    smtp_timeout_seconds: float = 10.0

    # --- 비밀번호 재설정(#2824) ---
    # 재설정 코드 유효 시간(분). 메일을 열어 바로 쓰는 일회용이라 짧게 둔다.
    password_reset_token_minutes: int = 30
    # 같은 이메일로 재설정 메일을 보낼 수 있는 횟수(아래 창 안에서). IP 버킷과 별개다
    # — 여러 IP 에서 한 사람에게 메일 폭탄을 보내는 것을 막는다.
    password_reset_email_per_window: int = 3
    password_reset_email_window_minutes: int = 15
    # 메일 속 링크가 여는 화면 주소. 비어 있으면 링크 없이 코드만 보낸다 — 앱에서
    # 코드를 붙여 넣어도 된다. `?token=` 이 붙는다.
    password_reset_member_url: str = ""
    password_reset_trainer_url: str = ""

    # --- 기타 ---
    cors_allow_origins: str = "http://localhost:3000,http://localhost:5173,http://127.0.0.1:3000"
    seed_demo_data: bool = True
    # 데모 계정(트레이너/회원 시드) 로그인 비밀번호. 운영에서 데모 계정에 데이터를 담아
    # 두고 싶으면 이 값을 안전하게 설정한다(기본값이면 운영 기동 차단).
    demo_login_password: str = DEFAULT_DEMO_PASSWORD
    # 관리자 이메일(콤마구분) — 기동 시 해당 사용자를 is_admin=True 로 승격
    admin_emails: str = ""

    # --- 운영 배포 하드닝 ---
    force_https: bool = False       # HTTP→HTTPS 리다이렉트(프록시 뒤면 X-Forwarded-Proto 신뢰)
    security_headers: bool = True   # 보안 응답 헤더(HSTS·nosniff·frame deny 등)
    # 루트 로거 레벨. 허용값만(임의 문자열 금지 — 오타로 로깅이 조용히 죽는 것 방지).
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"

    # --- 에러 추적(Sentry, #2839) ---
    # 처리하지 못한 예외를 외부 에러 추적 도구로 보낸다. DSN 은 배포 환경변수로만 넣고
    # 저장소에 두지 않는다. 비어 있거나 ENV=dev 면 초기화하지 않는다(개발·데모 오류는
    # 보내지 않음). 요청 본문·헤더·쿼리·지역 변수는 보내지 않는다(app/core/error_tracking.py).
    sentry_dsn: str = ""
    # 비우면 ENV 값(staging·prod)을 그대로 쓴다.
    sentry_environment: str = ""
    # 오류 이벤트 표본 비율(0~1). 성능 추적(APM)은 켜지 않는다.
    sentry_sample_rate: float = Field(default=1.0, ge=0.0, le=1.0)

    # --- Rate limit (인증 엔드포인트 브루트포스 방어) ---
    rate_limit_enabled: bool = True
    rate_limit_auth_per_minute: int = 10  # IP·엔드포인트당 분당 시도 한도
    # AI 코치 채팅 한도. 브루트포스 방어가 아니라 LLM 비용 가드라서 목적이 다르다.
    # 사람이 대화하는 속도로는 걸리지 않되, 폭주하는 클라이언트는 막는 값.
    # 회원 AI 코치(IP 버킷)와 트레이너 고객 AI 코치(트레이너 id 버킷, #1548)가 같이 쓴다.
    coach_chat_per_minute: int = 20
    # 회원 AI 코치 요청 본문 상한(#1549, 413). 필드 제한(질문 1000자·history 20턴×2000자)을
    # 다 채운 정상 요청이 JSON 이스케이프(`\uXXXX`, 글자당 6바이트)로 보내져도 들어가는 값.
    # 필드 검증보다 앞에서, 본문을 읽는 도중에 끊는다.
    coach_chat_max_body_bytes: int = 256 * 1024
    # AI 챗봇 하루 대화 한도(#2145). 분당 한도는 폭주하는 클라이언트를 막고, 이 값들은
    # 한 회원의 하루 비용을 묶는다. 무료를 다 쓰면 한 번에 `coach_chat_paid_cost` 포인트로
    # 하루 `coach_chat_paid_per_day` 번까지 더 보낸다. 날짜는 KST 로 센다.
    coach_chat_free_per_day: int = 5
    coach_chat_paid_cost: int = 50
    coach_chat_paid_per_day: int = 10
    # 트레이너 루틴 생성 한도. 채팅보다 낮게 잡는다 — 같은 LLM 비용에 회원 분석
    # 쿼리가 더 얹히고, 슬라이더·강도·메모를 바꿔 가며 "생성"을 연타하기 쉬운
    # UI 라 연타가 그대로 비용이 된다. 생성 왕복이 실측 3~6초라(#579) 사람이
    # 결과를 보고 조정하는 속도로는 분당 10회에 닿지 않는다.
    routine_options_per_minute: int = 10
    # 상담 요청 생성 한도(#1628). 트래픽이 아니라 **남에게 주는 피해**를 막는 정책이다
    # — 답을 기다리는 요청 하나가 트레이너 자리 하나를 최대 24시간 잠그고(#1873),
    # 신청·취소를 되풀이하면 트레이너 알림함이 찬다. 둘 다 DB 에서 세므로 재기동이나
    # 여러 인스턴스에도 값이 같다. 0 이면 그 한도를 끈다.
    # 동시에 답을 기다릴 수 있는 요청 수. 넘으면 409 `too_many_pending`.
    consultation_max_pending: int = 3
    # 24시간에 만들 수 있는 요청 수(취소·거절·만료 포함). 넘으면 429 + Retry-After.
    # 다른 한도와 같이 RATE_LIMIT_ENABLED=false 면 끈다.
    consultation_create_per_day: int = 10
    # 같은 이메일 로그인 연속 실패 잠금(#2815). IP 를 바꿔 가며 한 계정의 비밀번호를
    # 맞혀 보는 것을 막는다 — IP 한도만으로는 요청마다 주소를 바꾸면 끝없이 시도할 수
    # 있다. `login_lockout_seconds` 안에 `login_max_failures` 번 틀리면 그 이메일은
    # 남은 시간 동안 429 다. 성공하면 실패 기록을 지운다.
    login_max_failures: int = 5
    login_lockout_seconds: int = 15 * 60
    # 회원 연결 코드 미리보기·사용의 트레이너 하루 상한(#2815). 분당 한도(IP·트레이너
    # id)에 더해, 트레이너 계정이 공개 가입이라 한 계정이 하루 종일 코드를 훑는 것을
    # 막는다. 정상 사용(회원 한 명당 한두 번)으로는 닿지 않는 값.
    pairing_redeem_per_day: int = 30
    # 같은 이메일 가입 시도의 시간당 상한(#2913). 가입은 이미 있는 이메일에 409 를
    # 주므로, IP 한도만으로는 IP 를 바꿔 가며 특정 이메일의 가입 여부를 계속 물을 수
    # 있다. 회원·트레이너 가입이 한 버킷을 쓴다. 정상 가입(오타 몇 번)으로는 닿지 않는 값.
    register_per_email_per_hour: int = 5
    # 비밀번호 변경의 현재 비밀번호 연속 실패 잠금(#2913). 접근 토큰을 손에 넣은 쪽이
    # 현재 비밀번호를 맞혀 보는 것을 사용자 id 단위로 막는다. 창은 로그인 잠금과 같다
    # (`login_lockout_seconds`).
    password_change_max_failures: int = 5

    # --- 클라이언트 IP (#2815) ---
    # rate limit 키·감사 로그 IP 를 정할 때 믿는 앞단 프록시 수. `X-Forwarded-For` 를
    # 오른쪽에서 이 번째 값으로 읽는다(`app/core/client_ip.py`). 0 이면 헤더를 보지 않고
    # 소켓 주소를 쓴다. 비워 두면 운영(prod)은 1, 그 밖은 0 — 운영 배포(App Runner·
    # Railway·EC2+Nginx)는 모두 프록시 하나 뒤다. 프록시가 늘면 그 수로 맞춘다.
    trusted_proxy_hops: Optional[int] = Field(default=None, ge=0, le=5)

    @property
    def effective_proxy_hops(self) -> int:
        """실제로 쓰는 신뢰 프록시 홉 수(미설정이면 운영 1, 그 밖 0)."""
        if self.trusted_proxy_hops is not None:
            return self.trusted_proxy_hops
        return 1 if self.is_prod else 0

    #: API 문서(`/docs`·`/redoc`·`/openapi.json`) 공개 여부(#2834). 비워 두면 운영은
    #: 끄고 그 밖은 켠다. 문서는 엔드포인트 전체 목록·스키마·docstring 의 내부 설계
    #: 설명을 인증 없이 보여 준다 — 운영 스키마는 스테이징·로컬에서 본다. 꼭 운영에서
    #: 켜야 하면 `EXPOSE_API_DOCS=true` 로 명시한다.
    expose_api_docs: Optional[bool] = None

    @property
    def api_docs_enabled(self) -> bool:
        """실제로 문서를 여는가(미설정이면 운영 끔, 그 밖 켬)."""
        if self.expose_api_docs is not None:
            return self.expose_api_docs
        return not self.is_prod

    @property
    def admin_email_set(self) -> set[str]:
        return {e.strip().lower() for e in self.admin_emails.split(",") if e.strip()}

    @property
    def sqlalchemy_database_url(self) -> str:
        """SQLAlchemy 엔진용 DB URL(psycopg v3 드라이버를 명시).

        Railway/Neon/Supabase/Heroku 등 관리형 Postgres 는 DATABASE_URL 을
        `postgres://…` 또는 드라이버 없는 `postgresql://…` 로 준다. 이 프로젝트는
        psycopg **v3** 만 설치돼 있어(psycopg2 없음) bare `postgresql://` 는
        SQLAlchemy 가 기본값인 psycopg2 로 붙으려다 기동에 실패한다. 그래서 여기서
        psycopg v3 드라이버(`postgresql+psycopg://`)로 정규화해, 플랫폼이 준 URL 을
        그대로 붙여도 되게 한다(이미 +psycopg 이거나 postgres 계열이 아니면 그대로).
        """
        url = self.database_url
        if url.startswith("postgres://"):
            url = "postgresql://" + url[len("postgres://") :]
        if url.startswith("postgresql://"):
            url = "postgresql+psycopg://" + url[len("postgresql://") :]
        return url

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_allow_origins.split(",") if o.strip()]

    @property
    def is_cors_wildcard(self) -> bool:
        return "*" in self.cors_origin_list

    @property
    def is_prod(self) -> bool:
        return self.env.strip().lower() in ("prod", "production")

    @property
    def mail_backend(self) -> str:
        """실제로 쓸 메일 발송 수단(`smtp`|`log`). `auto` 를 여기서 푼다."""
        if self.mail_provider != "auto":
            return self.mail_provider
        return "smtp" if self.smtp_host.strip() and self.mail_from.strip() else "log"

    @property
    def mail_enabled(self) -> bool:
        """재설정 메일을 보낼 수 있는가.

        개발·스테이징은 log 발송으로도 켜 둔다(코드를 서버 로그에서 읽어 확인한다).
        운영은 실제 발송 수단이 있어야만 켠다 — 로그로만 남기는 재설정은 회원에게
        닿지 않을뿐더러, 로그를 읽을 수 있는 사람이 남의 계정을 되찾게 된다.
        """
        if self.mail_backend == "smtp":
            return bool(self.smtp_host.strip() and self.mail_from.strip())
        return not self.is_prod

    @property
    def demo_fallback_enabled(self) -> bool:
        """데모 사용자 폴백 허용 여부 — 운영에서는 설정과 무관하게 항상 비활성."""
        return self.allow_demo_fallback and not self.is_prod

    @model_validator(mode="after")
    def _guard_prod_secrets(self) -> "Settings":
        """운영 환경에서 안전하지 않은 기본값을 쓰면 기동을 막는다(fail-fast)."""
        # SMTP 를 명시해 놓고 서버·발신 주소를 비우면 설정 실수다. auto 와 달리 조용히
        # log 로 떨어뜨리지 않고 기동에서 드러낸다(#2824).
        if self.mail_provider == "smtp" and not (
            self.smtp_host.strip() and self.mail_from.strip()
        ):
            raise ValueError(
                "MAIL_PROVIDER=smtp 이면 SMTP_HOST 와 MAIL_FROM 을 함께 설정해야 합니다."
            )
        if self.is_prod:
            if not self.jwt_secret or self.jwt_secret == DEFAULT_JWT_SECRET:
                raise ValueError(
                    "운영(env=prod)에서는 JWT_SECRET 을 안전한 값으로 반드시 설정해야 합니다."
                )
            if self.is_cors_wildcard:
                raise ValueError(
                    "운영(env=prod)에서는 CORS 허용 출처를 명시해야 합니다(와일드카드 '*' 금지)."
                )
            # 운영에서 데모 시드를 켜면 트레이너/회원 데모 계정이 생성된다. 약한 비밀번호가
            # 그대로 운영 자격증명이 되는 것을 막는다: 기본값 금지 + 최소 길이 강제.
            # (빈 문자열·짧은 문자열·기본값 모두 거부. 원치 않으면 SEED_DEMO_DATA=false)
            if self.seed_demo_data:
                pw = self.demo_login_password or ""
                if pw == DEFAULT_DEMO_PASSWORD or len(pw) < MIN_DEMO_PASSWORD_LEN:
                    raise ValueError(
                        "운영(env=prod)에서 데모 시드(SEED_DEMO_DATA=true)를 켜려면 "
                        f"DEMO_LOGIN_PASSWORD 를 기본값이 아닌 {MIN_DEMO_PASSWORD_LEN}자 이상의 "
                        "안전한 값으로 설정해야 합니다(또는 SEED_DEMO_DATA=false)."
                    )
            # 운영은 Alembic 을 스키마의 유일한 변경 경로로 삼는다. create_all 이 켜져 있으면
            # ORM 정의만으로 테이블이 생겨 Alembic 이력과 어긋날 수 있으므로, 조용히 무시하지 않고
            # 기동을 거부한다(AUTO_CREATE_TABLES=false 를 명시하도록 강제).
            if self.auto_create_tables:
                raise ValueError(
                    "운영(env=prod)에서는 AUTO_CREATE_TABLES=false 로 두고 Alembic 을 스키마의 "
                    "유일한 소스로 삼아야 합니다."
                )
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
