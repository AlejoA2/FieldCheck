plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Genera los recursos de Firebase a partir de `google-services.json`.
    id("com.google.gms.google-services")
}

android {
    // `namespace` y `applicationId` deben coincidir con el identificador de la
    // app registrado en la consola de Firebase: es esa coincidencia la que hace
    // que `google-services.json` se aplique a este build.
    namespace = "com.fieldcheck.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fieldcheck.app"

        // firebase_auth 6.x exige minSdk 23; el valor por defecto de Flutter (21)
        // hace fallar la resolución de dependencias en tiempo de compilación.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion

        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // La clave de depuración es suficiente para un prototipo de hackaton.
            // Sustituir por una clave propia antes de distribuir en Google Play.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}