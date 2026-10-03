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

빌드:

```bash
cd frontend/flutter
flutter build appbundle --release \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=<운영 API 주소>
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

## 3. iOS 제출 설정

| 항목 | 위치 | 내용 |
| --- | --- | --- |
| 수출 규정 | `ios/Runner/Info.plist` `ITSAppUsesNonExemptEncryption=false` | 표준 HTTPS 와 OS 키체인만 쓰고 자체 암호화가 없다. 암호화 라이브러리를 추가하면 다시 판단 |
| 개인정보 매니페스트 | `ios/Runner/PrivacyInfo.xcprivacy` | 추적 없음, 필수 사유 API(UserDefaults), 수집 데이터 유형 |
| 권한 문구 | `ios/Runner/Info.plist` | 카메라·사진(식단 사진·트레이너 채팅 사진), 위치(주변 헬스장 찾기) |

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
- iOS 빌드·서명은 Mac 과 Apple Developer 계정이 필요합니다. 서명 인증서·프로비저닝은
  Xcode 의 자동 서명(팀 계정)으로 하고, 인증서 파일도 저장소에 올리지 않습니다.

```bash
cd frontend/flutter
flutter build ipa --release \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=<운영 API 주소>
```

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
  SDK 를 쓰지 않습니다(카카오 지도는 웹 전용).
