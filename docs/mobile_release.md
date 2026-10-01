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
- 권한 문구는 실제로 그 권한을 쓰는 화면과 맞아야 합니다. 새 용도가 생기면 문구도 고칩니다.
- iOS 빌드·서명은 Mac 과 Apple Developer 계정이 필요합니다. 서명 인증서·프로비저닝은
  Xcode 의 자동 서명(팀 계정)으로 하고, 인증서 파일도 저장소에 올리지 않습니다.

```bash
cd frontend/flutter
flutter build ipa --release \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=<운영 API 주소>
```

## 4. 첫 제출 전에 확정할 것

아래 값은 스토어 등록 뒤 바꿀 수 없거나 바꾸기 어렵습니다. 결정 후 Android·iOS·외부 콘솔
(카카오 개발자 콘솔 등)에 함께 반영합니다(#2823).

- 앱 ID: Android `applicationId`·`namespace`·Kotlin 패키지 경로, iOS 번들 ID(Runner·RunnerTests).
  현재 `com.barmi.oncare`.
- 홈 화면 앱 이름: Android `android:label`, iOS `CFBundleDisplayName`, 웹 `manifest.json`.
  현재 각각 `oncare`, `Oncare`, `On-Care` 로 다릅니다.
