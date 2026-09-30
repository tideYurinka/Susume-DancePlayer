import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release 签名：凭据只在 android/key.properties 一处（该文件与
// keystore 都在 android/.gitignore 里）。本机没有这个文件时回落到 debug
// 签名，保证 `flutter run --release` 仍可用。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "top.yurinka.susume"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 本地通知（flutter_local_notifications 22）要求
        // 打开 core library desugaring 才能编译。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 定死的安装身份：装出去的包在系统里永久叫这个名字，
        // 改它等于换一个应用——已安装用户只能卸载重装，本机数据一起丢。
        applicationId = "top.yurinka.susume"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 节拍识别：DBN Viterbi 原生实现（lib/beat/dbn_native.dart 经 ffi 加载）。
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // 正式 keystore（PKCS12，store 与 key 共用一个密码）只在
    // android/key.properties 存在时启用；四项凭据全部取自该文件，
    // storeFile 的相对路径与 key.properties 同基准（按 android/ 解析），
    // 绝对路径照用。
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // 没有 key.properties 时用 debug key，让 `flutter run --release` 可用。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 当前 release 未开 minify；预置节拍识别（onnxruntime JNI）keep
            // 规则（proguard-rules.pro），将来开启 minify 必须真机回归节拍
            // 分析。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

// 出站分享 FileProvider：androidx.core 的 FileProvider 把包文件换 content
// URI 递出。
dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    // flutter_local_notifications 的 desugaring 运行时（插件 README 指定的
    // 最低版本）。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
