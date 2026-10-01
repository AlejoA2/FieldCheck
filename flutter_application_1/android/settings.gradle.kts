pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // Plugin de Google Services: lee `android/app/google-services.json` y genera
    // los recursos que `firebase_core` necesita para inicializar Firebase en
    // Android. `apply false` porque la aplicación se hace en :app.
    //
    // Nota: el archivo NO se declara aquí ni en :app como dependencia. Los
    // plugins de FlutterFire (firebase_core, cloud_firestore, firebase_auth,
    // firebase_storage) ya declaran su propio `firebase-bom` y sus SDK de
    // producto; añadir un segundo BoM en :app duplicaría el catálogo de
    // versiones sin agregar nada.
    id("com.google.gms.google-services") version "4.5.0" apply false
}

include(":app")
