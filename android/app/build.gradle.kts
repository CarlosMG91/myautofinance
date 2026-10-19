import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local process environment only; never Gradle properties, Dart defines or CI secrets.
val signingEnvironment = listOf("STORE_FILE", "STORE_PASSWORD", "KEY_ALIAS", "KEY_PASSWORD")
    .associateWith { System.getenv("AUTOFINANCE_SIGNING_$it") }
val fixtureSigning = System.getenv("AUTOFINANCE_SIGNING_FIXTURE") == "1"
val publicCertificate = rootProject.file("../packaging/android/distribution-certificate.pem")
fun certificateDigest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
    .digest(bytes).joinToString("") { "%02x".format(it) }

tasks.register("verifyDistributionSigning") {
    group = "verification"
    description = "Comprueba la firma externa sin compilar ni instalar un APK."
}

// Validate only graphs that produce/sign a release. Debug and unit tests need no key.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name in setOf(
        "verifyDistributionSigning", "validateSigningRelease", "packageRelease", "assembleRelease", "bundleRelease", "signReleaseBundle"
    ) }) {
        fun signingError(code: String, message: String): Nothing =
            throw GradleException("APK-SIGNING[$code]: $message Consulta docs/ep-029/firma-distribucion.md.")
        if (signingEnvironment.values.any { it.isNullOrBlank() }) {
            signingError("MISSING_MATERIAL", "Falta material privado de distribución; release no usa firma debug.")
        }
        val storePath = signingEnvironment.getValue("STORE_FILE")!!
        val store = file(storePath)
        if (!File(storePath).isAbsolute || !store.isFile || store.canonicalFile.toPath().startsWith(rootProject.projectDir.parentFile.canonicalFile.toPath())) {
            signingError("INVALID_LOCATION", "El keystore debe existir fuera del repositorio.")
        }
        val expected = if (fixtureSigning) System.getenv("AUTOFINANCE_SIGNING_FIXTURE_SHA256") else null
        val production = if (publicCertificate.isFile) publicCertificate.inputStream().use {
            certificateDigest(CertificateFactory.getInstance("X.509").generateCertificate(it).encoded)
        } else null
        val defines = (project.findProperty("dart-defines") as? String).orEmpty().split(',').mapNotNull {
            runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull()
        }
        if (fixtureSigning && (!defines.contains("APP_ENV=test") || defines.any { it.startsWith("APP_ENV=") && it != "APP_ENV=test" } || expected == production || !expected.orEmpty().matches(Regex("[a-fA-F0-9]{64}")))) {
            signingError("INVALID_FIXTURE", "La clave efímera exige APP_ENV=test y certificado distinto del de distribución.")
        }
        if (!System.getenv("CI").isNullOrBlank() && !fixtureSigning) {
            signingError("PRIVATE_ONLY", "La firma de distribución solo se usa en entrega local privada.")
        }
        if (gradle.startParameter.isConfigurationCacheRequested) {
            signingError("CONFIGURATION_CACHE", "Desactiva configuration-cache para no serializar material privado.")
        }
        val certificate = try {
            val keyStore = KeyStore.getInstance("PKCS12")
            store.inputStream().use { keyStore.load(it, signingEnvironment.getValue("STORE_PASSWORD")!!.toCharArray()) }
            val alias = signingEnvironment.getValue("KEY_ALIAS")!!
            require(keyStore.getKey(alias, signingEnvironment.getValue("KEY_PASSWORD")!!.toCharArray()) is PrivateKey)
            keyStore.getCertificate(alias) as X509Certificate
        } catch (_: Exception) {
            signingError("INVALID_MATERIAL", "No se puede abrir la clave privada con el material suministrado.")
        }
        if (certificate.subjectX500Principal.name.contains("CN=Android Debug", ignoreCase = true) || certificateDigest(certificate.encoded) != (expected ?: production)) {
            signingError("CERTIFICATE_MISMATCH", "El certificado no coincide con la identidad pública esperada o es debug.")
        }
        try { certificate.checkValidity() } catch (_: Exception) {
            signingError("EXPIRED_CERTIFICATE", "El certificado no está vigente.")
        }
    }
}

android {
    namespace = "com.carlosmg91.myautofinance"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.carlosmg91.myautofinance"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Runner nativo sin dependencias adicionales; solo datos sintéticos.
        testApplicationId = "com.carlosmg91.myautofinance.storageaudit"
        testInstrumentationRunner = "com.carlosmg91.myautofinance.StorageAuditInstrumentation"
    }

    signingConfigs {
        create("distribution") {
            storeFile = signingEnvironment["STORE_FILE"]?.let { file(it) }
            storePassword = signingEnvironment["STORE_PASSWORD"]
            keyAlias = signingEnvironment["KEY_ALIAS"]
            keyPassword = signingEnvironment["KEY_PASSWORD"]
            storeType = "PKCS12"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("distribution")
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
