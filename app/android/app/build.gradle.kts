plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Notifications push FCM : applique `google-services.json`
    // (projet Firebase `e-system-church`, paquet
    // `ci.esystemchurch.esystem_church`).
    id("com.google.gms.google-services")
}

// ---------------------------------------------------------------------------
// Signature de release — correctif de la faille BASSE n°10 (audit du 14/11,
// re-vérifiée présente le 22/11) : l'APK de release était signée avec le
// keystore de débogage.
//
// Le keystore de release et ses mots de passe ne sont JAMAIS dans le dépôt :
// ils arrivent par variables d'environnement (secrets GitHub Actions en CI)
// ou, en local seulement, par `app/android/key.properties` (fichier ignoré
// par git — voir `app/android/.gitignore` et `key.properties.example`).
// Les variables d'environnement priment sur `key.properties`.
//
// Variables attendues :
//   KEYSTORE_PATH      chemin du keystore de release
//                      (en CI : ${{ runner.temp }}/release.keystore,
//                      chemin absolu posé par le workflow)
//   KEYSTORE_PASSWORD  mot de passe du keystore (secret KEYSTORE_PASSWORD)
//   KEY_ALIAS          alias de la clé (secret KEY_ALIAS)
//   KEY_PASSWORD       mot de passe de la clé (secret KEY_PASSWORD)
//
// Tant que ces valeurs sont absentes, la release retombe TEMPORAIREMENT sur
// la signature debug avec un avertissement explicite dans les logs : la CI
// actuelle n'a pas encore les secrets, et casser le build en attendant que
// Bouf les pose bloquerait toutes les APK de test. Dès que les 4 secrets
// sont posés, la release est signée avec le keystore dédié, sans autre
// changement de code.
// ---------------------------------------------------------------------------
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(envName: String, propertyName: String): String? =
    System.getenv(envName)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseKeystorePath = signingValue("KEYSTORE_PATH", "storeFile")
val releaseKeystorePassword = signingValue("KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("KEY_PASSWORD", "keyPassword")
val hasReleaseSigning =
    !releaseKeystorePath.isNullOrBlank() &&
        !releaseKeystorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

if (!hasReleaseSigning) {
    logger.warn(
        "Signature release : KEYSTORE_PATH / KEYSTORE_PASSWORD / KEY_ALIAS / " +
            "KEY_PASSWORD absents ou incomplets — repli TEMPORAIRE sur la " +
            "signature debug (faille BASSE n°10 non encore fermée en CI). " +
            "Poser les secrets GitHub Actions pour signer avec le keystore " +
            "de release dédié (voir app/android/key.properties.example)."
    )
}

android {
    namespace = "ci.esystemchurch.esystem_church"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ci.esystemchurch.esystem_church"
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
        // Nom affiché (AndroidManifest.xml, ${appLabel}) : la flavor
        // `demo` le surcharge par « e-System Church Démo ».
        manifestPlaceholders["appLabel"] = "e-System Church"
    }

    flavorDimensions += "app"

    productFlavors {
        // Application réelle : `flutter build apk --flavor prod`.
        create("prod") {
            dimension = "app"
        }
        // Version démo (données fictives, `lib/main_demo.dart`) :
        // s'installe À CÔTÉ de la vraie appli (suffixe `.demo`).
        // `flutter build apk --flavor demo -t lib/main_demo.dart`.
        create("demo") {
            dimension = "app"
            applicationIdSuffix = ".demo"
            versionNameSuffix = "-demo"
            manifestPlaceholders["appLabel"] = "e-System Church Démo"
        }
    }

    signingConfigs {
        // Créée uniquement quand les 4 valeurs de signature sont présentes ;
        // sinon la release utilise signingConfigs.debug (repli ci-dessus).
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Keystore de release dédié quand les secrets sont posés,
            // signature debug sinon (repli temporaire, avertissement en log).
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
