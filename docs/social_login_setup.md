# 카카오·구글 로그인 설정 (#330)

회원 앱(Android·iOS·웹)과 트레이너 웹의 카카오·구글 로그인을 실제로 켜는 절차입니다.
코드는 값이 없으면 그 버튼을 **'준비 중'으로 꺼 둔 채** 빌드되므로, 아래 등록을 끝낸 환경부터
하나씩 켜면 됩니다. 소셜 로그인은 카카오·구글 두 가지이고, 이메일 로그인은 그대로입니다.

- 앱에 들어가는 값(앱 키·client_id)은 모두 **공개 식별자**라 GitHub **변수(Variables)** 로 둡니다.
  비밀은 서버의 카카오 클라이언트 시크릿 하나뿐입니다.
- 값을 저장소 파일·이슈·PR·채팅에 붙이지 않습니다. 콘솔에서 복사해 변수·서버 환경에 바로 넣습니다.
- 데모 사이트(GitHub Pages)는 기본이 목업 빌드라 버튼을 누르면 기기 안 데모 계정으로 들어갑니다.
  실제 로그인은 실서버 빌드(운영 웹·스토어 앱, 데모의 수동 실서버 실행)에서만 동작합니다.

## 1. 어떤 값이 어디에 쓰이나

| 값 | 어디서 받나 | 앱 빌드 변수(`--dart-define`) | 서버 환경 변수 |
| --- | --- | --- | --- |
| 카카오 네이티브 앱 키 | 카카오 디벨로퍼스 > 앱 > 플랫폼 키 | `KAKAO_NATIVE_APP_KEY` (Android·iOS) | — |
| 카카오 REST API 키(로그인용) | 같은 곳 | `KAKAO_LOGIN_REST_API_KEY` (웹) | `KAKAO_LOGIN_REST_API_KEY` |
| 카카오 클라이언트 시크릿 | 카카오 로그인 > 보안 | — | `KAKAO_CLIENT_SECRET` (**비밀**) |
| 카카오 앱 ID(숫자) | 앱 > 일반 | — | `KAKAO_APP_ID` |
| 구글 웹 client_id | Google Cloud > 사용자 인증 정보 | `GOOGLE_WEB_CLIENT_ID` (웹·Android·iOS) | `GOOGLE_CLIENT_IDS` 에 포함 |
| 구글 iOS client_id | 같은 곳 | `GOOGLE_IOS_CLIENT_ID` (iOS) | `GOOGLE_CLIENT_IDS` 에 포함 |
| 구글 Android client_id | 같은 곳 | — (앱 서명 SHA-1 로 묶임) | `GOOGLE_CLIENT_IDS` 에 포함 |

카카오 REST API 키는 서버의 장소 검색 키(`KAKAO_REST_API_KEY`)와 **다른 변수**입니다. 같은 카카오 앱이면
값이 같을 수 있지만, 로그인 키는 `KAKAO_LOGIN_REST_API_KEY` 로 따로 넣습니다. 서버 쪽 형식 점검과 각
변수의 뜻은 `backend/.env.example` 과 [backend/docs/DEPLOY.md](../backend/docs/DEPLOY.md) 에 있습니다.

## 2. 로그인 흐름

| 환경 | 카카오 | 구글 |
| --- | --- | --- |
| Android·iOS | 카카오 SDK — 카카오톡 앱이 있으면 카카오톡, 없으면 카카오계정 웹 로그인. 받은 access_token 을 `POST /v1/auth/social/kakao` 로 보낸다 | Google Sign-In — ID 토큰을 `POST /v1/auth/social/google` 로 보낸다 |
| 웹(두 앱) | 카카오 인가 창을 **팝업**으로 열고, 같은 출처의 `kakao_login_callback.html` 이 받은 인가 코드를 앱에 돌려준다. 앱은 `POST /v1/auth/social/kakao/code` 로 코드를 access_token 으로 바꾼 뒤 모바일과 같은 엔드포인트로 로그인한다 | 구글이 그리는 로그인 버튼(Google Identity Services) — ID 토큰을 서버로 보낸다 |

웹에서 브라우저가 팝업을 막으면 "팝업을 허용해 달라"는 안내가 뜹니다.

## 3. 카카오 디벨로퍼스

[developers.kakao.com](https://developers.kakao.com) > 내 애플리케이션 > On-Care 앱.

1. **앱 키** — 네이티브 앱 키, REST API 키, 앱 ID(숫자)를 확인합니다.
2. **플랫폼 > Android** — 패키지명 `com.csesudo.oncare`, 키 해시를 등록합니다. 키 해시는 업로드 키와
   Play 앱 서명 키 **둘 다** 넣습니다(Play Console > 앱 무결성 > 앱 서명 키 인증서의 SHA-1 을 base64 로
   바꾼 값). 로컬 디버그 빌드로 시험하려면 디버그 키의 해시도 넣습니다.
   ```bash
   keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android \
     | openssl sha1 -binary | openssl base64
   ```
3. **플랫폼 > iOS** — 번들 ID `com.csesudo.oncare`.
4. **플랫폼 > Web** — 사이트 도메인에 웹을 여는 출처를 넣습니다(운영 도메인, 데모 도메인
   `https://ewhasudo.zapto.org`, 로컬 시험 주소).
5. **카카오 로그인 > 활성화** 를 켜고, **Redirect URI** 에 콜백 페이지를 등록합니다. 앱마다 경로가 다릅니다.
   - 회원 웹: `https://<도메인>/frontend/kakao_login_callback.html`
   - 트레이너 웹: `https://<도메인>/trainer/kakao_login_callback.html`
   - 로컬: `http://localhost:<포트>/kakao_login_callback.html`
6. **카카오 로그인 > 동의항목** — 닉네임(필수), 카카오계정(이메일)(선택)을 켭니다. 이메일 동의를 받지 못한
   계정도 로그인은 되고, 서버가 자리표시 이메일로 계정을 만듭니다.
7. **카카오 로그인 > 보안 > Client Secret** — 코드를 만들고 **사용함**으로 둡니다. 값은 서버
   `KAKAO_CLIENT_SECRET` 에만 넣습니다(앱·웹 빌드에는 넣지 않습니다).

## 4. Google Cloud

[console.cloud.google.com](https://console.cloud.google.com) > API 및 서비스.

1. **OAuth 동의 화면** — 앱 이름, 지원 이메일, 개인정보 처리방침·약관 주소를 넣고 범위는 `openid`·`email`·
   `profile` 만 씁니다. 시험 단계에서는 테스트 사용자를 등록하고, 공개 전에 게시 상태로 바꿉니다.
2. **사용자 인증 정보 > OAuth 클라이언트 ID** 를 세 개 만듭니다.
   - **웹 애플리케이션** — 승인된 JavaScript 원본에 웹 출처(운영 도메인, 데모 도메인, 로컬 주소)를 넣습니다.
     리디렉션 URI 는 쓰지 않습니다. 이 client_id 가 `GOOGLE_WEB_CLIENT_ID` 입니다.
   - **Android** — 패키지명 `com.csesudo.oncare`, SHA-1 인증서 지문(업로드 키·Play 앱 서명 키·필요하면 디버그
     키). 앱 빌드 변수는 없고, 서버 `GOOGLE_CLIENT_IDS` 에만 넣습니다.
   - **iOS** — 번들 ID `com.csesudo.oncare`. 이 client_id 가 `GOOGLE_IOS_CLIENT_ID` 입니다.
3. 서버 `GOOGLE_CLIENT_IDS` 에 세 client_id 를 콤마로 넣습니다. 목록에 없는 앱이 받은 토큰은 거부됩니다.

## 5. 값을 넣는 곳

### 서버

`KAKAO_APP_ID`, `KAKAO_LOGIN_REST_API_KEY`, `KAKAO_CLIENT_SECRET`, `GOOGLE_CLIENT_IDS`.
운영 배포의 비밀·파라미터 위치는 [backend/docs/DEPLOY.md](../backend/docs/DEPLOY.md) 를 따릅니다(AWS 리소스는 #480).
형식이 틀린 값(카카오 앱 ID 자리에 문자 키, 구글 자리에 client_id 가 아닌 값)은 기동에서 멈추고, 값을 비우면
그 provider 로그인만 거부한다는 경고가 남습니다.

### 웹 빌드(두 앱)

저장소 변수 `KAKAO_LOGIN_REST_API_KEY`, `GOOGLE_WEB_CLIENT_ID` 를 넣으면
[aws-frontend-deploy.yml](../.github/workflows/aws-frontend-deploy.yml)(운영)과
[deploy.yml](../.github/workflows/deploy.yml)(데모의 실서버 수동 실행)이 빌드에 넘깁니다.

```bash
gh variable set KAKAO_LOGIN_REST_API_KEY --body '<REST API 키>'
gh variable set GOOGLE_WEB_CLIENT_ID --body '<번호>-<해시>.apps.googleusercontent.com'
```

### 스토어 앱(Android·iOS)

Environment `mobile-release` 의 변수 `MEMBER_APP_KAKAO_NATIVE_APP_KEY`, `MEMBER_APP_GOOGLE_WEB_CLIENT_ID`,
`MEMBER_APP_GOOGLE_IOS_CLIENT_ID` — 자세한 표는 [mobile_release.md](mobile_release.md) 에 있습니다.
빌드 전에 `tool/check_release_defines.sh` 가 형식을 검사합니다.

- Android 는 Gradle 이 `KAKAO_NATIVE_APP_KEY` 로 카카오 리다이렉트 스킴(`kakao<키>`)을 매니페스트에 넣습니다.
  키가 없으면 아무 앱도 열지 않는 자리표시 스킴이 들어갑니다.
- iOS 는 서명 빌드 워크플로가 같은 값으로 `ios/Flutter/Social.xcconfig`(커밋하지 않음)를 만들어 URL 스킴
  (`kakao<키>`, 뒤집은 iOS client_id)을 채웁니다. iOS 서명 빌드에는 유료 Apple 개발자 계정이 필요해
  실기기 확인은 Android 를 먼저 합니다.

### 로컬 실행

```bash
cd frontend/flutter
flutter run -d chrome --web-port 5173 \
  --dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=http://localhost:8000/v1 \
  --dart-define=KAKAO_LOGIN_REST_API_KEY=<REST API 키> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<웹 client_id>

flutter run -d <안드로이드 기기> \
  --dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1 \
  --dart-define=KAKAO_NATIVE_APP_KEY=<네이티브 앱 키> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<웹 client_id>
```

iOS 시뮬레이터에서 시험하려면 `ios/Flutter/Social.xcconfig.example` 을 `Social.xcconfig` 로 복사해 스킴을 채우고
`--dart-define=GOOGLE_IOS_CLIENT_ID=…` 를 더합니다. 백엔드 실행은 [local_fullstack.md](local_fullstack.md) 를 따릅니다.

## 6. 확인

- 키를 넣지 않은 빌드: 두 버튼이 꺼져 있고 '준비 중' 안내가 보입니다(이메일 로그인은 그대로).
- 웹 카카오: 팝업에서 동의 → 팝업이 닫히고 홈으로 들어갑니다. 동의 화면에서 취소하면 아무 안내 없이 제자리입니다.
- 웹 구글: 구글 버튼 → 계정 선택 → 홈으로 들어갑니다.
- Android: 카카오톡이 설치된 기기와 없는 기기, 구글 계정 선택 창.
- 같은 카카오·구글 계정으로 다시 들어오면 같은 회원입니다.
