// App de Android de Chivato Radar. Comparte con la de iPhone la base de radares
// (ios/Radares/Recursos/radares.json) y los audios de las voces (ios/Radares/Voces).
// Se compila en GitHub Actions (.github/workflows/android-compilar.yml).
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "es.mjtbapps.radares"
    compileSdk = 36

    defaultConfig {
        applicationId = "es.mjtbapps.radares"
        minSdk = 26
        targetSdk = 36
        // Google Play exige un número nuevo en cada subida: lo pone GitHub (número de ejecución).
        versionCode = (project.findProperty("codigoVersion") as String?)?.toIntOrNull() ?: 1
        versionName = "1.0"
    }

    // radares.json y las carpetas de voces (lucia/, pablo/…) quedan en la raíz de assets.
    sourceSets["main"].assets.srcDirs("../../ios/Radares/Recursos", "../../ios/Radares/Voces", "src/main/assets")

    // Firma fija: sin ella cada compilación tiene otra firma y hay que desinstalar para actualizar.
    // La clave llega por variables de entorno (secretos de GitHub), nunca en el repositorio.
    val keystore = System.getenv("CHIVATO_KEYSTORE")?.let { file(it) }?.takeIf { it.exists() }
    signingConfigs {
        if (keystore != null) {
            create("chivato") {
                storeFile = keystore
                storePassword = System.getenv("CHIVATO_KEY_PASSWORD")
                keyAlias = "chivato"
                keyPassword = System.getenv("CHIVATO_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            signingConfigs.findByName("chivato")?.let { signingConfig = it }
        }
        release {
            isMinifyEnabled = false
            // Sin la clave fija, la de depuración: así la APK de prueba se puede instalar.
            signingConfig = signingConfigs.findByName("chivato") ?: signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation(platform("androidx.compose:compose-bom:2025.04.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    // Los servicios de Google traen fragment 1.1.0, que rompe la petición de permisos.
    implementation("androidx.fragment:fragment:1.8.9")
    implementation("com.android.billingclient:billing-ktx:8.0.0")
    implementation("com.google.android.gms:play-services-ads:24.4.0")
    implementation("com.google.android.ump:user-messaging-platform:3.2.0")
    implementation("com.google.android.play:app-update-ktx:2.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    testImplementation("junit:junit:4.13.2")
    // org.json de Android está vacío en las pruebas locales.
    testImplementation("org.json:json:20240303")
}
