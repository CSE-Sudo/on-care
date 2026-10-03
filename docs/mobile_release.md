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

### 화면의 버전과 웹 배포

회원 앱 MY → 설정 → 고객 지원 하단과 트레이너 웹 MY 하단의 `… · 버전 <이름>` 은 빌드에서
읽은 버전 이름입니다(`package_info_plus`, 모바일은 `versionName`·`CFBundleShortVersionString`, 웹은
빌드의 `version.json`). 번역 문구에 숫자를 적지 않습니다(#3047). 읽지 못하면 앱 이름만 보입니다.

- 트레이너 웹(`frontend/flutter_trainer/pubspec.yaml`)도 같은 규칙으로 버전을 둡니다.
- 배포 워크플로(Pages·AWS)는 `--build-name`·`--build-number` 를 주입하지 않습니다. 주입하면 저장소
  이력과 배포물의 버전이 갈라집니다.
- 회원이나 트레이너가 보는 변화가 있는 웹 배포 전에는 그 앱의 버전 이름을 위 표대로 올리는 커밋을
  main 에 넣습니다. 웹만 배포할 때는 빌드 번호(`+` 뒤)를 올리지 않아도 됩니다. 빌드 번호는 스토어
  업로드에만 씁니다.

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

## 5. 최소 지원 버전 (강제 업데이트)

백엔드 환경 변수 `MIN_MEMBER_APP_VERSION` 보다 낮은 회원 앱 **모바일** 빌드는 업데이트 화면만
보입니다(#3045). 옛 빌드가 바뀐 API 응답을 읽어 화면마다 오류를 내는 일을 막는 장치이고, 첫 스토어
출시 빌드부터 들어 있어야 의미가 있습니다.

- 앱은 켤 때와 백그라운드에서 돌아올 때 `GET /version` 의 `min_app_version` 을 읽어 자기 버전
  이름(`pubspec.yaml` 의 `+` 앞)과 비교합니다. 빌드 번호는 비교하지 않습니다.
- 비어 있으면(기본) 검사하지 않습니다. 개발·데모·목업 빌드는 늘 비어 있습니다.
- `/version` 이 실패하거나 3초 안에 오지 않으면 평소처럼 진행합니다(fail-open). 이미 업데이트 화면이
  떠 있으면 다시 확인이 실패해도 그대로 둡니다.
- 웹 빌드(회원 앱 웹·트레이너 웹)는 검사하지 않습니다. 웹은 배포하면 곧 새 빌드를 받습니다.
- 값은 `MAJOR.MINOR.PATCH` 형식만 받습니다. 형식이 틀리면 백엔드가 뜨기 전에 설정 로드가
  실패합니다 — 오타 하나로 모든 회원이 막히지 않게 하기 위해서입니다.

### 올리는 때

호환되지 않는 API 변경(필드 형식·의미 변경, 필수 요청 값 추가 등)이나 보안 문제로 옛 빌드를 더 둘 수
없을 때만 올립니다. 기능 추가만으로는 올리지 않습니다 — 닫을 수 있는 권장 업데이트 안내는 없고, 이
값은 회원을 즉시 막습니다.

### 올리는 절차

1. 새 빌드를 두 스토어에 올리고 **심사를 통과해 회원이 받을 수 있는 상태인지** 확인합니다. Play
   Console 단계적 출시라면 100% 배포 뒤에 진행합니다. 스토어에 없는 버전을 요구하면 회원이 업데이트할
   방법 없이 막힙니다.
2. 운영 백엔드의 `MIN_MEMBER_APP_VERSION` 을 그 버전 이름으로 바꾸고 다시 배포합니다(운영 환경 변수는
   배포 담당이 관리합니다, #480).
3. 옛 빌드 기기에서 업데이트 화면이 뜨고 버튼이 스토어의 On-Care 페이지를 여는지 확인합니다.

### 되돌리는 법

`MIN_MEMBER_APP_VERSION` 을 비우거나 낮은 값으로 바꾸고 다시 배포합니다. 앱은 백그라운드에서
돌아오거나 다시 켤 때 확인해 업데이트 화면을 풉니다. 앱을 새로 낼 필요는 없습니다.

### iOS App Store ID

업데이트 버튼은 안드로이드에서 Play 스토어 앱(`market://details?id=com.csesudo.oncare`, 열리지 않으면
Play 스토어 웹 페이지)을 엽니다. iOS 는 App Store 의 앱 ID 가 필요한데, 이 값은 App Store Connect 에
앱을 만든 뒤에 정해집니다. 숫자 ID 를 빌드할 때 넣습니다.

```bash
flutter build ipa --release \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=<운영 API 주소> \
  --dart-define=IOS_APP_STORE_ID=<App Store Connect 의 Apple ID 숫자>
```

값이 없으면 iOS 업데이트 화면은 버튼 대신 "App Store 에서 On-Care 를 업데이트해 주세요" 문구만
보입니다. 첫 iOS 제출 전에 ID 를 넣어 빌드하는 것을 권장합니다.
