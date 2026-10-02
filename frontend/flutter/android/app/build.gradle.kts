import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리스 서명은 저장소 밖에서 받은 android/key.properties 로만 한다(#2823).
// 파일·키스토어는 .gitignore(android/.gitignore)로 제외되어 있고, 값은 저장소·이슈에
// 남기지 않는다. 보관·발급 절차는 docs/mobile_release.md 에 있다.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigning = releaseSigningKeys.all {
    !keystoreProperties.getProperty(it).isNullOrBlank()
}

android {
    // 앱 ID 는 스토어 등록 뒤 바꿀 수 없다. iOS 번들 ID·Kotlin 패키지 경로와 같은 값이어야
    // 하며 tool/ci/check_mobile_app_identity.py 가 검사한다(#2823).
    namespace = "com.csesudo.oncare"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.csesudo.oncare"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 디버그 키로 서명한 번들은 스토어가 받지 않고, PC 마다 서명이 달라 업데이트
            // 설치도 실패한다. 업로드 키가 없으면 아래 가드가 릴리스 빌드를 멈춘다.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// key.properties 가 없거나 비어 있으면 릴리스 서명 작업 전에 멈춘다. 디버그·프로필
// 빌드와 `flutter run` 은 영향을 받지 않는다.
gradle.taskGraph.whenReady {
    val needsReleaseSigning = allTasks.any { task ->
        task.project == project &&
            (task.name.startsWith("assembleRelease") ||
                task.name.startsWith("bundleRelease") ||
                task.name.startsWith("packageRelease") ||
                task.name.startsWith("signRelease"))
    }
    if (needsReleaseSigning && !hasReleaseSigning) {
        throw GradleException(
            "릴리스 서명 설정이 없습니다: android/key.properties 에 " +
                releaseSigningKeys.joinToString() +
                " 를 채우세요(docs/mobile_release.md). 디버그 키로는 릴리스를 만들지 않습니다.",
        )
    }
}
