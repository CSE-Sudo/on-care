# 회원 앱 모바일 릴리스 (Android / iOS)

회원 앱(`frontend/flutter`)을 스토어에 올릴 때의 서명·버전·제출 설정 기준입니다(#2823).
로컬 실행·디버그 APK 는 [local_fullstack.md](local_fullstack.md) 를 보세요.

## 1. 버전·빌드 번호 규칙

버전은 `frontend/flutter/pubspec.yaml` 의 `version: <이름>+<번호>` 한 곳에서 정합니다.
Android `versionName`/`versionCode`, iOS `CFBundleShortVersionString`/`CFBundleVersion` 은
Flutter 가 이 값에서 채웁니다.

| 부분 | 형식 | 올리는 때 |
| --- | --- | --- |
| 버전 이름 (`+` 앞) | `MAJOR.MINOR.PATCH` | 회원이 보는 변화가 있을 때. 기능 추가 → MINOR, 수정만 → PATCH, 첫 정식 출시 → `1.0.0` |
| 빌드 번호 (`+` 뒤) | 양의 정수 | **스토어(Play Console·App Store Connect)에 올리는 빌드마다 1씩.** 버전 이름이 바뀌어도 0 으로 되돌리지 않는다 |

- 빌드 번호는 두 스토어에서 같은 값을 씁니다. 한 번 올린 번호는 다시 쓸 수 없습니다(업로드 거부).
- 제출 빌드는 `--build-number` 로 덮어쓰지 않고, `pubspec.yaml` 을 올린 커밋을 main 에 넣은 뒤
  그 커밋에서 빌드합니다. 그래야 스토어의 빌드와 저장소 이력이 1:1 로 맞습니다.
- 커밋 제목 예: `chore(mobile): 1.0.1+12 릴리스 버전 갱신`.

## 2. Android 릴리스 서명

릴리스 빌드는 업로드 키로만 서명합니다. `android/app/build.gradle.kts` 가
`android/key.properties` 를 읽고, 파일이 없거나 항목이 비어 있으면
`assembleRelease`·`bundleRelease` 가 시작되기 전에 빌드를 멈춥니다(디버그·프로필 빌드는 영향 없음).

`frontend/flutter/android/key.properties` (저장소에 올리지 않음):

```properties
storeFile=<android/ 기준 키스토어 경로, 예: ../../../oncare-upload.jks>
storePassword=<키스토어 비밀번호>
keyAlias=<키 별칭>
keyPassword=<키 비밀번호>
```

- `storeFile` 은 `frontend/flutter/android/` 기준 상대 경로이거나 절대 경로입니다. 키스토어는
  저장소 **밖**에 두는 것을 권장합니다.
- `key.properties`·`*.jks`·`*.keystore` 는 `frontend/flutter/android/.gitignore` 로 제외되어
  있습니다. `git status` 에 보이면 커밋하지 말고 제외 설정부터 확인합니다.

빌드(define 파일은 [5절](#5-릴리스-빌드-설정-define-파일)):

```bash
cd frontend/flutter
bash tool/check_release_defines.sh config/release.json
flutter build appbundle --release --dart-define-from-file=config/release.json
# → build/app/outputs/bundle/release/app-release.aab
```

### 키 발급·보관 절차

1. **Play App Signing 을 사용합니다.** 앱 서명 키는 Google 이 보관하고, 팀은 업로드 키만
   갖습니다. 업로드 키를 잃어버려도 Play Console 에서 재설정을 요청할 수 있습니다.
2. 업로드 키는 키 보관 담당자 한 명이 만듭니다.
   ```bash
   keytool -genkey -v -keystore oncare-upload.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias upload
   ```
3. 키스토어 파일과 비밀번호는 **팀 비밀번호 관리자(공유 금고)** 에만 둡니다. 저장소·이슈·PR·
   채팅방·메일에 파일이나 값을 붙이지 않습니다.
4. 릴리스를 빌드하는 사람은 금고에서 키스토어를 받아 저장소 밖에 두고 `key.properties` 를
   로컬로 만듭니다. 빌드가 끝나면 공용 PC 에서는 둘 다 지웁니다.
5. 담당자가 바뀌면 금고 접근 권한을 넘기고, 유출이 의심되면 Play Console 에서 업로드 키를
   재설정합니다.

키 보관 담당자와 금고 위치는 팀이 정해 이 절에 이름(값이 아닌 위치)만 적습니다.

### 앱 데이터 백업 정책 (#3049)

회원 앱 데이터는 **Google 자동 백업과 기기 간 이전(새 폰으로 옮기기)에 싣지 않습니다.**

| 위치 | 내용 |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` `<application>` | `android:allowBackup="false"`, `android:fullBackupContent="@xml/backup_rules"`(Android 11 이하), `android:dataExtractionRules="@xml/data_extraction_rules"`(Android 12 이상) |
| `android/app/src/main/res/xml/data_extraction_rules.xml` | `<cloud-backup>`·`<device-transfer>` 두 절 모두 `root`·`file`·`database`·`sharedpref`·`external` 제외 |
| `android/app/src/main/res/xml/backup_rules.xml` | 같은 영역 제외 |
| `lib/core/storage/secure_token_store.dart` | 토큰 저장소 옵션 한 곳(`memberSecureStorage`), 안드로이드 `resetOnError: true` |

이유:

- 회원의 기록·프로필은 모두 서버에 있고, 기기에는 세션 토큰·화면 설정·데모 데이터만 남습니다. 백업으로 얻는 것이 없습니다.
- 토큰 저장소는 Android Keystore 키로 암호화되는데, 이 키는 기기 밖으로 나가지 않습니다. 새 기기에는 풀 수 없는 암호문만 넘어와 읽기·쓰기가 실패합니다. 새 설치 표식(SharedPreferences)까지 복원되면 새 설치 토큰 정리도 건너뜁니다.
- Android 12 이상의 기기 간 이전은 `allowBackup="false"` 만으로 막히지 않아 `data_extraction_rules.xml` 이 따로 필요합니다.
- 이미 복원된 기기에서도 `resetOnError` 가 풀 수 없는 저장소를 비우므로, 다시 로그인하면 토큰이 정상 저장됩니다.

릴리스 전 확인(실기기 또는 에뮬레이터, 릴리스 빌드 설치 후):

```bash
adb shell bmgr enable true
adb shell bmgr backupnow com.csesudo.oncare
# → 앱 데이터가 백업 대상이 아니라는 결과(백업 안 함)가 나와야 합니다.
```

Play Console 데이터 보안 양식의 백업 관련 항목은 이 정책(백업하지 않음)에 맞춰 적습니다.

## 3. iOS 제출 설정

| 항목 | 위치 | 내용 |
| --- | --- | --- |
| 수출 규정 | `ios/Runner/Info.plist` `ITSAppUsesNonExemptEncryption=false` | 표준 HTTPS 와 OS 키체인만 쓰고 자체 암호화가 없다. 암호화 라이브러리를 추가하면 다시 판단 |
| 개인정보 매니페스트 | `ios/Runner/PrivacyInfo.xcprivacy` | 추적 없음, 필수 사유 API(UserDefaults), 수집 데이터 유형 |
| 지원 언어 | `ios/Runner/Info.plist` `CFBundleLocalizations` = `ko`, `en` · `project.pbxproj` `knownRegions` | 앱 안 지원 언어(`AppLocalizations.supportedLocales`)와 같게. 개발 언어(`developmentRegion`)는 `en` — 앱 안 문구의 폴백과 같다 |
| 권한 문구 | `ios/Runner/ko.lproj/InfoPlist.strings`, `ios/Runner/en.lproj/InfoPlist.strings`, `Info.plist`(영어 폴백) | 카메라·사진(식단 사진·트레이너 채팅 사진), 위치(주변 헬스장 찾기) |

- App Store Connect 의 **개인정보 라벨**은 `PrivacyInfo.xcprivacy` 의 수집 항목과 같게 적습니다.
  수집 항목·플러그인이 바뀌면 두 곳을 함께 고칩니다.
- 개인정보 라벨 체크리스트(#3053) — `PrivacyInfo.xcprivacy` 와 한 줄씩 대조합니다.
  - [ ] 연락처 정보: 이름·이메일·전화번호 — 사용자에게 연결됨, 앱 기능
  - [ ] 건강 및 피트니스: 건강·피트니스 — 연결됨, 앱 기능
  - [ ] 사용자 콘텐츠: 사진, 이메일 또는 문자 메시지(채팅), **기타 사용자 콘텐츠(상담·예약 신청 내용)** — 연결됨, 앱 기능
  - [ ] 위치: 정확한 위치 — 연결됨, 앱 기능
  - [ ] 식별자: 사용자 ID — 연결됨, 앱 기능
  - [ ] **진단: 충돌 데이터, 기타 진단 데이터** — 사용자에게 **연결되지 않음**, 앱 기능(오류 수집 Sentry, 자동 세션 추적 포함)
  - [ ] 기타 데이터: 성별·생년월일·키 등 프로필 — 연결됨, 앱 기능
  - [ ] 추적: 하지 않음
- 오류 수집 SDK 를 빼거나 Sentry 세션 추적(`enableAutoSessionTracking`)을 끄면 진단 항목을 함께 고칩니다. 어긋나면 `test/platform/privacy_manifest_test.dart` 가 실패합니다.
- 권한 문구는 실제로 그 권한을 쓰는 화면과 맞아야 합니다. 새 용도가 생기면 문구도 고칩니다.
- **권한 문구는 세 곳을 함께 고칩니다**(#3048): `ko.lproj/InfoPlist.strings`, `en.lproj/InfoPlist.strings`, `Info.plist` 본문(영어 폴백). 권한 키를 새로 더할 때(예: 푸시 알림 #474)도 같습니다. 한 곳이라도 빠지면 `test/platform/ios_localizations_test.dart` 가 실패합니다.
- 릴리스 전에 기기 언어를 한국어·영어로 바꿔 가며 카메라·사진·위치 권한 창의 설명과 버튼이 그 언어로 뜨는지, 설정 → On-Care 에 언어 항목(한국어·영어)이 보이는지 확인합니다.
- iOS 빌드·서명은 Mac 과 Apple Developer 계정이 필요합니다. 서명 인증서·프로비저닝은
  Xcode 의 자동 서명(팀 계정)으로 하고, 인증서 파일도 저장소에 올리지 않습니다.

```bash
cd frontend/flutter
bash tool/check_release_defines.sh config/release.json
flutter build ipa --release --dart-define-from-file=config/release.json
```

## 3-1. 화면 방향 정책 (#3050)

| 기기 | 정책 | 위치 |
| --- | --- | --- |
| iPhone | 세로만 | `ios/Runner/Info.plist` `UISupportedInterfaceOrientations` = `UIInterfaceOrientationPortrait` 하나 |
| 안드로이드 휴대폰 | 세로만(앱 시작 시 런타임 고정) | `lib/core/platform/orientation_policy.dart`, `lib/app/bootstrap.dart` |
| iPad | 모든 방향 | `UISupportedInterfaceOrientations~ipad` 네 방향 유지 |
| 안드로이드 태블릿 | 모든 방향 | 런타임 고정을 적용하지 않음 |
| 웹 | 브라우저가 정함 | 적용하지 않음 |

- 휴대폰 판별: 기기 **화면**(분할 화면의 창 크기가 아님)의 짧은 변이 600 논리 픽셀 미만이면 휴대폰입니다(안드로이드 `sw600dp` 와 같은 경계). 크기를 알 수 없으면 고정하지 않습니다.
- 안드로이드 매니페스트의 `screenOrientation="portrait"` 는 태블릿까지 세로로 묶어 쓰지 않습니다.
- 태블릿을 모든 방향으로 두는 이유: 회원 앱 화면은 폭을 휴대폰 폭(`OnCareLayout.mobileContentMaxWidth`)으로 제한해 가운데 정렬하므로 가로에서도 쓸 수 있고, iPad 멀티태스킹(Split View)은 네 방향 지원을 요구합니다. 방향을 막으려면 `UIRequiresFullScreen` 까지 켜야 합니다.
- 대안(팀 결정 대기): `TARGETED_DEVICE_FAMILY = "1"`(iPhone 전용)로 내면 iPad 에서는 iPhone 호환 모드로 돌고 iPad 스크린샷 제출도 필요 없습니다. 다만 **iPad 지원으로 한 번 출시하면 되돌릴 수 없으므로** 첫 출시 전에만 고를 수 있습니다.

## 4. 앱 ID·앱 이름 (확정값)

아래 값은 스토어 등록 뒤 바꿀 수 없거나 바꾸기 어렵습니다. 첫 제출 전에 아래처럼 확정했습니다(#2823).

| 항목 | 값 | 반영 위치 |
| --- | --- | --- |
| 앱 ID | `com.csesudo.oncare` | Android `applicationId`·`namespace`(`android/app/build.gradle.kts`), Kotlin 패키지 경로 `android/app/src/main/kotlin/com/csesudo/oncare/`, iOS 번들 ID Runner `com.csesudo.oncare`·RunnerTests `com.csesudo.oncare.RunnerTests`(`ios/Runner.xcodeproj/project.pbxproj`) |
| 홈 화면 앱 이름 | `On-Care` | Android `android:label`(`AndroidManifest.xml`), iOS `CFBundleDisplayName`·`CFBundleName`(`Info.plist`), 웹 `manifest.json` `name`·`short_name`, `index.html` `apple-mobile-web-app-title` |

- 앱 ID 는 서비스 이름(`oncare`) 앞에 팀 조직(GitHub 조직 `CSE-Sudo`)을 붙였습니다. 앱 이름은
  소개 페이지·웹 앱과 같은 `On-Care` 하나로 쓰고, ko·en 에서 같은 표기라 따로 현지화하지 않습니다.
- `tool/ci/check_mobile_app_identity.py` 가 위 위치들이 같은 값인지, 릴리스 빌드가 디버그 키가
  아닌 `key.properties` 서명을 쓰는지 검사합니다. 회원 앱 CI(`user-app-ci.yml` 의
  `Mobile release config`)는 이 검사와 함께 `key.properties` 없이 `flutter build appbundle --release`
  가 서명 가드에서 멈추는지, 일회용 키로 서명 설정을 채우면 릴리스 작업이 가드를 통과하는지 확인합니다.
- 값을 바꿔야 하면 위 반영 위치와 검사 스크립트의 `EXPECTED_APP_ID`·`EXPECTED_APP_NAME` 을 한
  PR 에서 함께 고칩니다. 스토어에 한 번 등록한 뒤에는 앱 ID 를 바꾸지 않습니다.

### 외부 콘솔에 등록할 때

앱 ID 를 쓰는 외부 등록은 위 값 그대로 합니다. 저장소에 값·파일을 남기지 않는 것은 서명 키와 같습니다.

- Play Console 앱 생성(패키지 이름), App Store Connect 앱 생성과 Apple Developer 의 App ID(번들 ID).
- 모바일에서 카카오·네이버 등 네이티브 소셜 로그인 SDK 를 붙이면(#330) 각 개발자 콘솔에 패키지 이름·
  번들 ID 와 업로드 키·Play 앱 서명 키의 키 해시를 등록합니다. 지금 회원 앱 모바일 빌드는 이런 네이티브
  SDK 를 쓰지 않습니다.

### 헬스장 찾기 지도 (#3043)

모바일 빌드도 웹과 같은 카카오맵 JavaScript SDK 를 앱 안 WebView 로 띄웁니다. 네이티브 지도 SDK 가
아니므로 패키지 이름·키 해시 등록은 필요 없고, 웹과 같은 **JavaScript 키와 JavaScript SDK 도메인**
목록을 그대로 씁니다. 두 값은 5절의 `config/release.json` 에 `KAKAO_JS_KEY`·`KAKAO_MAP_ORIGIN` 키로
넣습니다(`check_release_defines.sh` 는 `KAKAO_MAP_ORIGIN` 이 경로 없는 `https://` 출처가 아니거나 로컬 주소면 멈춥니다).

- `KAKAO_JS_KEY` 를 빼고 빌드하면 지도를 띄우지 않습니다. 헬스장 목록은 그대로 쓸 수 있고, 지도 자리에는
  "지도를 불러오지 못했어요" 안내만 둡니다(위치와 무관한 핀을 그리지 않습니다).
- WebView 는 지도 문서를 `KAKAO_MAP_ORIGIN` 출처로 띄우고 그 출처로 SDK 를 부릅니다. 운영 빌드는
  **이미 허용 목록에 있는 운영 회원 웹 주소**(`https://` 포함, 경로 없이)를 넣습니다. 그래야 운영 키의
  허용 목록에 `localhost` 같은 개발용 주소를 더하지 않습니다(#2913, `backend/docs/DEPLOY.md`).
  앱이 실제로 그 주소에 요청을 보내지는 않습니다.
- 값을 비우면 로컬 개발용 `http://localhost` 입니다. 이 값은 개발용 카카오 앱 키와 함께만 씁니다.
- 지도가 뜨지 않으면(도메인 미등록·키 오류·네트워크 차단, 10초 제한) 같은 안내로 돌아갑니다.
- 데모 세션(`USE_MOCK_API=true` 빌드·실서버 데모 입장)은 키가 없을 때 예전 그림 지도를 그대로 씁니다.
- Android 는 `INTERNET` 권한이 이미 있고, iOS 는 SDK 가 `https` 라 ATS 예외가 필요 없습니다.

## 5. 릴리스 빌드 설정 (define 파일)

앱의 컴파일 타임 기본값은 로컬 개발용입니다(`ENV=dev`·`USE_MOCK_API=true`·예시 API 주소).
`--dart-define` 을 하나씩 적으면 하나를 빠뜨려도 빌드는 성공하고, 그 앱은 **개발 환경으로 판정된
운영 앱**(요청 로그·개발용 화면이 켜지고 오류 보고가 꺼짐)이나 **목업 데이터로 도는 앱**이 됩니다(#3022).
그래서 스토어 빌드는 define 파일 하나로만 합니다.

1. `frontend/flutter/config/release.example.json` 을 같은 폴더의 `release.json` 으로 복사하고 값을 채웁니다.
   `release.json` 은 `.gitignore` 로 제외되어 있습니다 — 커밋하지 않습니다.

   | 키 | 값 |
   | --- | --- |
   | `ENV` | `prod`(스토어). 내부 배포 빌드만 `staging` |
   | `USE_MOCK_API` | `false` |
   | `API_BASE_URL` | `https://<운영 API 도메인>/v1` — `/v1` 까지, 끝 `/` 없이 |
   | `SENTRY_DSN` | 회원 앱 Sentry 프로젝트의 DSN(`https://…`) |

2. 빌드 전에 `bash tool/check_release_defines.sh config/release.json` 을 돌립니다. 키가 빠졌거나 형식이
   틀리면(`ENV` 가 `prod`·`staging` 이 아님, 목업, `http://`·예시·로컬 주소, DSN 없음, 데모 전용 스위치
   `DEMO_BUILD`·`SHOW_DEMO_ENTRY`·`REAL_API` 가 남음) 빌드하지 말라는 오류와 함께 멈춥니다.
3. `flutter build appbundle|ipa --release --dart-define-from-file=config/release.json` 으로 빌드합니다.

빌드 단계를 건너뛰어도 앱이 한 번 더 막습니다. 릴리스 모드에서 `ENV` 가 `prod`·`staging` 이 아니거나,
데모 빌드 표시(`DEMO_BUILD=true`) 없이 목업이거나, API 주소가 `https://` 가 아니거나 예시·로컬
주소면 기동할 때 기능 화면 대신 **"이 빌드는 잘못 구성됐어요"** 안내와 고칠 설정 목록을 띄웁니다
(`AppConfig.releaseProblems`). `flutter run`(디버그)·테스트에는 적용되지 않습니다.

- `DEMO_BUILD=true` 는 데모 Pages 빌드(`.github/workflows/deploy.yml`)만 넘깁니다. 스토어 빌드에는 넣지 않습니다.
- Sentry 프로젝트 생성·DSN 발급은 #480 에서 합니다. 값은 팀 비밀번호 관리자에 두고 `release.json` 에만 적습니다.
