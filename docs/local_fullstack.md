# 로컬 풀스택 실행 (백엔드 + 회원 앱 + 트레이너 웹)

회원 앱(모바일)과 트레이너 웹을 **같은 백엔드·같은 DB** 로 띄우는 절차입니다. 회원↔트레이너 상호작용
(회원이 올린 식단을 트레이너가 보는 것 등)은 이 구성에서만 확인할 수 있습니다.

> 둘 다 `useMockApi` 기본값이 `true` 입니다. dart-define 없이 실행하면 각각
> **자기 로컬 drift DB** 를 보기 때문에, 둘 다 잘 도는 것처럼 보여도 서로의
> 데이터는 절대 보이지 않습니다. 상호작용을 확인하려면 아래 3단계를 모두 거쳐야 합니다.

## 1. 백엔드

```bash
cd backend
cp .env.example .env          # JWT_SECRET 은 openssl rand -hex 32 로 교체 권장
docker compose up -d --build
```

→ http://localhost:8000/docs (모든 경로는 `/v1/...`)

AI 키는 없어도 됩니다. `GEMINI_API_KEY` 가 비어 있으면 식단 인식이 오프라인 스텁으로
폴백해서 `/v1/diet/analyze` 가 그대로 동작합니다(CI 와 같은 경로).

### 기동에 실패하면: 오래된 볼륨

예전에 만들어 둔 `oncare_pgdata` 볼륨이 있으면 다음처럼 죽습니다.

```
alembic ... Running upgrade -> 0001_baseline
psycopg.errors.DuplicateTable: relation "users" already exists
```

`create_all()` 로 만들어진 스키마가 남아 있는데 `alembic_version` 이 없어서, 마이그레이션이
baseline 부터 다시 돌다 충돌하는 것입니다. 로컬 개발 DB 라 버리고 다시 만들면 됩니다.

```bash
docker compose down -v        # 볼륨 삭제 — 로컬 데이터가 사라집니다
docker compose up -d
```

확인:

```bash
docker compose ps             # app, db 모두 Up
docker compose logs app       # alembic upgrade 성공 후 uvicorn 기동
```

## 2. 회원 앱 (모바일)

로컬 검증은 Chrome 으로 띄우는 편이 빠릅니다. 실제 배포 타깃은 iOS/Android 입니다.


```bash
cd frontend/flutter
flutter run -d chrome \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://localhost:8000/v1
```

## 3. 트레이너 웹

```bash
cd frontend/flutter_trainer
bash tool/fetch_drift_wasm.sh   # 최초 1회
flutter run -d chrome \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://localhost:8000/v1
```

## 데모 계정

`SEED_DEMO_DATA=true`(기본값)면 시드 계정이 생성됩니다. 비밀번호는 모두
`.env` 의 `DEMO_LOGIN_PASSWORD`(기본 `oncare123`)입니다.

| 역할 | 이메일 | 비고 |
| --- | --- | --- |
| 트레이너 | `trainer@oncare.com` | 담당 회원 15명 |
| 회원 | `minsu@oncare.com` | 김민수 — 트레이너의 1번 회원, 기록이 가장 많다 |
| 회원 | `jisu@oncare.com` | 이지수 |
| 회원 | `sungho@oncare.com` | 박성호 |

> 시연에는 `minsu@oncare.com`(user-7d4e9a2c5f18)이 가장 편합니다 — 트레이너의 1번 회원이고
> 식단·운동·대화 시드가 셋 중 가장 두껍습니다. 한동안 빈 비밀번호 해시 때문에 로그인이
> 막혀 있었지만 #577 에서 고쳐졌습니다.
>
> 4~15번 회원은 로스터·차트가 동작할 최소 지표만 있고(#572) 상세 기록은 위 3명에게만
> 있습니다.

## 트레이너 웹 브라우저 E2E

트레이너 웹의 로그인·회원 상세·채팅·상담 거절·스케줄 핵심 흐름은 Flutter 공식
[`integration_test`](https://docs.flutter.dev/testing/integration-tests)와 ChromeDriver로
실 API를 확인합니다. 먼저 위 백엔드를 기본 데모 비밀번호(`oncare123`)로 띄운 뒤 두
터미널에서 실행합니다.

```bash
# 터미널 1 — 설치된 Chrome과 호환되는 ChromeDriver
chromedriver --port=4444

# 터미널 2
cd frontend/flutter_trainer
bash tool/fetch_drift_wasm.sh   # 최초 1회
bash tool/run_web_e2e.sh
```

테스트는 다음 계약을 고정합니다.

- 트레이너 계정은 `trainer@oncare.com`, 상담 fixture 준비 계정은
  `jisu@oncare.com`이며 둘 다 기본 `DEMO_LOGIN_PASSWORD=oncare123`을 사용합니다.
- `USE_MOCK_API=false`, `API_BASE_URL=http://localhost:8000/v1`가 아니면 즉시 실패합니다.
- 트레이너 토큰을 주입하지 않고 `trainer@oncare.com`으로 로그인 화면을 통과합니다.
- 회원/상담/스케줄 이동은 사이드바와 화면 안의 탭·버튼만 사용합니다.
- 채팅은 실행 시각이 포함된 고유 문구를 한 번 보내고 화면 재진입 뒤에도 한 건만 보이는지
  확인합니다. 채팅 삭제 API가 없으므로 이 문구는 로컬 DB에 남습니다.
- 상담 테스트는 `jisu@oncare.com`으로 기존 대기 요청을 재사용하거나 새 요청을 만든 뒤
  트레이너 화면에서 거절합니다. 승인과 달리 담당 회원 관계를 바꾸지 않으며, 다음 실행은
  다시 새 대기 요청을 만들 수 있습니다.

### 새로고침 검증의 범위

Flutter 3.44의 `integration_test` WebDriver 채널은 브라우저 스크린샷 명령만 제공하고,
실행 중인 테스트가 `location.reload()`를 호출하면 테스트 런타임 자체도 함께 종료됩니다.
따라서 이 스위트는 브라우저 URL을 그대로 둔 채 운영 앱 루트를 다시 부팅하여, 실제
새로고침의 앱 측 계약인 **보안 저장소 세션 복원**과 **현재 URL의 회원/하위 탭 복원**을
검증합니다. Chrome 프로세스 자체의 reload 이벤트까지 자동화해야 한다면 Flutter 공식
드라이버가 reload 명령을 지원할 때 별도 시나리오로 추가해야 합니다.

## 회원↔트레이너 예약·취소 E2E (#637)

트레이너가 연 자리를 회원이 예약하고, 그 예약이 트레이너 일정으로 파생됐다가, 회원이 취소하면
좌석과 일정이 함께 돌아오는 **양방향 흐름 전체**를 실 API로 검증합니다. 위 백엔드만 떠 있으면
됩니다 — ChromeDriver도 브라우저도 필요 없습니다.

```bash
bash tool/run_reservation_e2e.sh
```

### 왜 브라우저가 없는가

회원 앱의 배포 타깃은 iOS/Android지 웹이 아닙니다. 그래서 이 스위트는 브라우저 대신
`IntegrationTestWidgetsFlutterBinding`(LiveBinding)을 `flutter test`로 돌립니다. 실제 위젯
트리와 실제 HTTP가 그대로 동작하고, 트레이너 웹 스위트(ChromeDriver)보다 빠릅니다.
`flutter test` 기본 바인딩은 FakeAsync라 실 네트워크 응답이 영원히 오지 않으므로,
LiveBinding이 아니면 이 방식은 성립하지 않습니다.

VM에는 구현이 없는 플러그인 세 개(`shared_preferences`, `flutter_secure_storage`,
`path_provider`)는 하네스가 setUp에서 채웁니다.

### 단계 구성

두 앱은 **서로 다른 Dart 패키지**라 한 프로세스에 함께 띄울 수 없습니다. 그래서 한 시나리오를
단계로 쪼개 번갈아 실행하고, 단계 사이의 상태는 **서버 DB**와 **상태 파일(id만)** 로 넘깁니다.
잔여 좌석처럼 검증 대상인 값은 상태 파일에 담지 않습니다 — 담으면 서버가 아니라 앞 단계의
기억을 검증하게 됩니다.

| 순서 | 단계 | 앱 | 확인하는 것 |
| --- | --- | --- | --- |
| 1 | `create-slot` | 트레이너 웹 | UI로 연 슬롯의 정원·잔여 좌석이 서버와 일치 |
| 2 | `reserve` | 회원 앱 | 슬롯 노출 · 예약 · 좌석 감소 · 재시작·재로그인 후 유지 |
| 3 | `verify-schedule` | 트레이너 웹 | 그 예약이 만든 일정이 트레이너 화면에 표시 |
| 4 | `cancel` | 회원 앱 | 취소 · 좌석 복구 · 재예약 가능 |
| 5 | `verify-schedule-cancelled` | 트레이너 웹 | 일정이 `취소` 기록으로 남음 · 좌석이 정원까지 복구 |
| 6 | `edge-cases` | 회원 앱 | 중복·권한 없는 회원·동시 요청이 초과 예약을 못 만듦 |
| 7 | `cleanup` | 트레이너 웹 | 이번 실행이 연 슬롯을 닫음 |

실패하면 러너가 **어느 단계에서 멈췄는지와 상태 파일 경로**를 남깁니다. 그 단계만 따로 다시
돌릴 수도 있습니다.

```bash
cd frontend/flutter
flutter test test_e2e/reservation_member_test.dart \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://localhost:8000/v1 \
  --dart-define=E2E_PHASE=reserve \
  --dart-define=E2E_STATE_FILE=/tmp/oncare_e2e.json
```

### 반복 실행과 남는 데이터

매 실행은 **새 슬롯**을 엽니다. 앞선 실행이 중간에 죽어 예약이 남아 있어도 다음 실행은 그것을
건드리지 않습니다. 슬롯 삭제 API는 없고 닫기만 가능하므로(`DELETE /trainer/reservation-slots/{id}`
는 `is_closed`를 켭니다), 실행마다 **닫힌 슬롯이 하나씩 남습니다.** 닫힌 자리는 회원 조회에
나오지 않아 다음 실행과 간섭하지 않습니다.

### 테스트가 고정하는 계약

- 트레이너는 `trainer@oncare.com`, 회원은 `minsu@oncare.com`(`user-7d4e9a2c5f18`), 권한 밖 회원은
  `jisu@oncare.com`이며 모두 기본 `DEMO_LOGIN_PASSWORD=oncare123`을 씁니다.
- `USE_MOCK_API=false`가 아니거나 앱과 검증용 API 클라이언트의 `API_BASE_URL`이 다르면
  **즉시 실패합니다.** 목업으로 새면서 초록불이 뜨는 것을 막습니다.
- 화면 이동과 예약·취소는 사이드바·탭·버튼만 씁니다. 다만 "화면에 보였다"와 "서버에
  저장됐다"는 다른 주장이므로, 각 단계는 UI와 서버 응답을 **둘 다** 확인합니다.
- 슬롯 시각은 시트 기본값 10:00을 그대로 쓰고 날짜만 하루 뒤로 잡습니다 — `showTimePicker`
  다이얼을 흉내 내는 쪽이 깨질 거리가 더 많습니다.

## 회원↔트레이너 텍스트 채팅 E2E (#639)

회원이 보낸 메시지가 트레이너 화면에 도착하고, 트레이너 답장이 회원 화면에 돌아오는
왕복 전체를 실 API로 검증합니다. 예약 스위트와 같은 구조·같은 전제입니다.

```bash
bash tool/run_chat_e2e.sh
```

| 순서 | 단계 | 앱 | 확인하는 것 |
| --- | --- | --- | --- |
| 1 | `member-send` | 회원 앱 | UI 발신이 서버에 **한 건** 남는다 |
| 2 | `trainer-thread` | 트레이너 웹 | 수신 · 열린 화면 polling · 미읽음→읽음 · UI 답장 |
| 3 | `member-receive` | 회원 앱 | 답장 수신 · 열린 화면 polling · 읽음 · 재로그인 후 순서 유지 |
| 4 | `idempotency` | 회원 앱 | 같은 `client_request_id` 재시도가 한 건으로 접힌다 |
| 5 | `isolation` | 회원 앱 | 다른 회원 스레드로 새지 않는다 |
| 6 | 정리 | — | 메시지와 파생 개인 RAG 문서를 DB에서 삭제 |

### 열린 화면 polling을 어떻게 확인하는가

두 앱은 서로 다른 Dart 패키지라 한 프로세스에 함께 띄울 수 없습니다. 그래서 **한쪽 UI를 연
채로 상대 메시지를 API로 도착시키고**, 재진입 없이 화면에 나타나는지 봅니다. 검증 대상은
"상대 앱이 보냈다"가 아니라 "열린 화면이 새 메시지를 스스로 가져온다"이므로 이 방식으로
충분합니다. 상대 앱이 실제로 보내는 경로는 1·2단계가 UI로 직접 확인합니다.

### 재시도 멱등성

앱은 타임아웃 재시도에서 같은 `client_request_id`를 다시 씁니다(#605). UI로는 네트워크
타임아웃을 재현할 수 없어, 이 계약만 API로 확인합니다.

### 정리가 스위트의 일부입니다

채팅은 **삭제 API가 없습니다.** 지우지 않으면 실행할 때마다 데모 대화가 늘고, 채팅이 AI 코치
근거로 적재되므로(#580, #604) 코칭 답변까지 오염됩니다. 그래서 러너는 실패 경로에서도 정리를
돌립니다.

```bash
cd backend
docker compose exec -T app python - --marker <marker> <scripts/clean_e2e_chat.py
```

지우는 범위는 그 실행의 마커가 든 메시지와, 같은 마커가 든 그 사용자의 `chat` 문서뿐입니다.
마커는 실행마다 새로 만들어지므로 앞선 실행과 섞이지 않습니다. `scripts/e2e_sweep.py`가 쓰는
방식과 같고, 혼자 쓰는 로컬 데모 DB를 전제로 합니다.

> 스크립트를 `-m scripts.clean_e2e_chat`이 아니라 **stdin으로 흘려 넣습니다.** 모듈로 부르면
> 파일이 이미지에 들어간 뒤에만 동작해서, 고칠 때마다 이미지를 다시 만들어야 합니다.

### 시드 기록과 AI 코치

시드된 식단·운동·대화는 기동할 때 **개인 RAG 문서로도 적재**됩니다(#604). 그래서 데모
계정으로 회원 앱 AI 코치에 "이번 주 운동 어땠어?" 라고 물으면 시드 기록이 근거로
잡힙니다. 적재하지 않던 때는 기록이 있는데도 일반론만 나왔습니다.

멱등이라 재기동해도 다시 임베딩하지 않습니다. 실 임베딩 키(`EMBEDDER=gemini` 등)로
**처음** 띄우면 그만큼 기동이 길어지므로, 급할 때는 `.env` 에 `SEED_RAG_INGEST=false`
를 두면 됩니다(키가 없으면 오프라인 해시 임베더라 비용·지연 모두 없습니다).

## 회원↔트레이너 상담 처리 E2E (#640)

회원이 UI 폼으로 낸 상담이 트레이너 인박스에 도착하고, 승인·거절 결과가 회원 화면에
돌아오는 양방향 전체를 실 API로 검증합니다. 앞의 두 스위트와 같은 구조입니다.

```bash
bash tool/run_consultation_e2e.sh
```

| 순서 | 단계 | 앱 | 확인하는 것 |
| --- | --- | --- | --- |
| 1 | `member-request` | 회원 앱 | 새 회원 둘이 UI 폼으로 신청 → 서버에 입력값 그대로 |
| 2 | `trainer-accept` | 트레이너 웹 | 인박스에서 내용 확인 → 일정 잡아 승인 |
| 3 | `member-after-accept` | 회원 앱 | 승인·담당·일정이 돌아오고 재로그인 후에도 유지 |
| 4 | `trainer-reject` | 트레이너 웹 | 다른 요청을 사유와 함께 거절 |
| 5 | `member-after-reject` | 회원 앱 | 같은 사유가 보이고 다시 신청할 수 있다 |
| 6 | `empty-inbox` | 트레이너 웹 | 처리한 요청이 대기 목록에서 빠진다 |
| 7 | `edge-cases` | 회원 앱 | 중복 제출 · 남의 상담 조회 · 재처리 차단 |
| 8 | 정리 | — | 상담 일정과 계정 둘 삭제 |

### 왜 계정을 새로 만드는가

시드 회원 셋은 **이미 `trainer-demo` 담당**입니다. 그 회원으로는 "승인이 담당 연결을
만든다"를 검증할 수 없고, 한 번 승인해 버리면 다음 실행이 같은 상태에서 시작하지 못합니다.
그래서 실행마다 `POST /auth/register` 로 새로 만들고 끝나면 `DELETE /users/me` 로 지웁니다.

승인 사이클과 거절 사이클이 서로를 막으므로(승인 뒤에는 담당이 생깁니다) 계정을 둘 씁니다.

### 정리가 스위트의 일부입니다

계정을 지우면 상담과 담당 연결은 FK CASCADE로 함께 사라집니다. **일정은 아닙니다** —
`trainer_schedule.member_id` 는 `SET NULL` 이라, 승인이 만든 상담 일정이 주인 없이 남아
트레이너 달력에 유령처럼 쌓입니다. 그래서 러너는 **일정을 먼저 지우고** 계정을 지우며,
앞 단계가 실패해도 정리는 돕니다.

### 지연 목록에서 위젯을 잡는 법

추천 트레이너 목록(가로)과 상담 신청 폼(세로)은 **화면 밖 항목을 만들지 않습니다.**
`find.byKey` 로는 없는 것으로 보이고 `ensureVisible` 도 소용없어서, `scrollUntilVisible`
로 만들어 낸 뒤에 조작합니다. 선택지 칩은 문구가 아니라 **자리**(`consult-goal-1` 등)로
고릅니다 — 문구는 번역이 바뀌면 흔들립니다.

### 테스트가 고정하는 계약

* 일정 응답에는 `member_id` 가 **없습니다.** 회원별 일정은 `GET /trainer/schedule?member_id=`
  로 물어야 하고, 전체 목록을 받아 걸러 내면 아무것도 찾지 못합니다.
* 트레이너 인박스 필터는 `?status=pending|accepted|rejected|all` 입니다.

## 상호작용이 실제로 연결됐는지 확인

클라이언트 없이 API 로만 30초 안에 확인할 수 있습니다. 회원이 올린 식단이 트레이너 쪽에
나타나면 둘이 같은 DB 를 보고 있다는 뜻입니다.

```bash
M=$(curl -s -X POST http://localhost:8000/v1/auth/login \
      -d "username=jisu@oncare.com&password=oncare123" \
    | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
T=$(curl -s -X POST http://localhost:8000/v1/auth/login \
      -d "username=trainer@oncare.com&password=oncare123" \
    | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# 회원이 메시지를 보내면
curl -s -X POST http://localhost:8000/v1/me/coach/chat \
  -H "Authorization: Bearer $M" -H "Content-Type: application/json" \
  -d '{"text":"hello from member"}'

# 트레이너 스레드에 그대로 나타난다
curl -s -H "Authorization: Bearer $T" \
  http://localhost:8000/v1/trainer/clients/user-jisu/chat
```

로그인은 `OAuth2PasswordRequestForm` 이라 **JSON 이 아니라 폼 데이터**(`username=`)로
보냅니다. 이메일을 `username` 필드에 넣습니다.

### 전 경로 한 번에 훑기

위 확인은 채팅 하나만 봅니다. 46개 경로(식단·운동·채팅·로스터·예약·상담)를 한 번에
훑으려면:

```bash
cd backend
python -m scripts.e2e_sweep
```

통과/실패를 그룹별로 출력하고, 실패가 있으면 마지막에 목록으로 모아 줍니다. 그 목록만
화면으로 확인하면 됩니다.

만든 것은 모두 되돌립니다 — 식단·운동 세션은 삭제, 건강 목표는 원래 값으로 복구,
채팅과 **거기서 파생된 개인 RAG 문서**(#580 이후 식단·채팅이 AI 코치 근거로 적재됩니다)는
DB 에서 제거합니다. 둘 다 삭제 API 가 없어서입니다. 몇 번을 돌려도 데모 DB 가 그대로입니다.
정리에 실패하면 조용히 넘어가지 않고 `정리` 그룹이 FAIL 로 뜹니다.

> 원본만 지우면 부족합니다. 식단 엔트리를 지워도 그 기록으로 만들어진 RAG 문서는 남아
> AI 코칭 근거를 오염시킵니다. 그래서 실행 전 문서 최대 id 를 기준선으로 잡고, 그 뒤에
> 생긴 회원 문서 중 스윕이 만드는 종류(`chat`·`diet`)만 지웁니다.

> **혼자 쓰는 로컬 데모 DB 를 전제로 합니다.** 기준선은 '누가 만들었는지' 를 증명하지
> 못하므로, 스윕이 도는 동안 같은 회원(`jisu@oncare.com`)으로 앱을 쓰면 그때 생긴 문서도
> 지워질 수 있습니다. 삭제 건수를 기대값과 대조하므로, 예상 밖이 섞이면 `정리` 가 FAIL 로
> 드러납니다.

데이터를 쓰고 지우므로 기본은 로컬 `--base` 만 허용합니다. `--allow-remote` 로 원격을
가리키면 **정리를 아예 건너뜁니다**(`정리` 가 SKIP). DB 정리는 항상 로컬
`DATABASE_URL` 로 붙기 때문에, 그대로 실행하면 검증 대상도 아닌 로컬 데모 문서를 지우게
됩니다. 대신 원격에는 채팅과 RAG 문서가 남습니다. 배포 환경에 쓰는 것은 권하지 않습니다.

AI 코칭·루틴 생성은 이 스윕에서 제외했습니다. `GEMINI_API_KEY` 가 없으면 규칙 폴백이
200 을 돌려주어 **통과처럼 보이기** 때문입니다(#579 수정 후 #589 에서 검증).

## 알려진 함정

- **Windows(Git Bash)에서 `curl -F "image=@/tmp/x.jpg"`** 는 `curl: (26)` 로 실패합니다.
  Windows `curl.exe` 가 MSYS 경로를 못 읽습니다. `$(cygpath -w /tmp/x.jpg)` 로 변환하세요.
- **셸에서 한글이 든 JSON 을 `-d` 로 보내면** 콘솔 인코딩(cp949) 때문에 깨져
  `400 There was an error parsing the body` 가 납니다. 파일(`-d @body.json`)로 보내거나
  ASCII 로 확인하세요. 회원 앱·트레이너 웹이 보내는 요청은 정상입니다.
- CORS 는 `.env` 기본값이 `CORS_ALLOW_ORIGINS=*` 라 로컬 웹에서 그대로 붙습니다.
- **백엔드 테스트는 전용 DB(`oncare_test`)에 씁니다.** 데모 DB 와 섞이지 않으므로 손으로
  API 를 찔러 둔 데이터가 테스트를 깨뜨리지 않고, 테스트가 만든 계정이 데모에 쌓이지도
  않습니다. 최초 1회만 만들어 두면 됩니다 — 스키마와 데모 시드는 앱 기동이 채웁니다:

  ```bash
  createdb -h 127.0.0.1 -U oncare oncare_test
  psql -h 127.0.0.1 -d oncare_test -c 'CREATE EXTENSION IF NOT EXISTS vector'
  ```

  확장 생성은 superuser 로 해야 합니다(`oncare` 로는 안 됩니다). 다른 DB 로 돌리려면
  `DATABASE_URL` 을 직접 지정하세요 — 값이 있으면 그대로 씁니다(CI 가 그렇게 씁니다).
