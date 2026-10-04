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

// 测试签名（ADR-0003）：与正式签名**分开**的一把钥，凭据只在
// android/key-test.properties 一处（同样在 .gitignore 里）。测试版靠它原地
// 覆盖升级，正式版的升级凭据因此不落到测试者手里。缺这个文件时不留任何
// 回落（回落 debug 签名会让测试包逐机不同，测试者只能卸载重装——就地升级
// 这条不变量会静默失效），失败点落在真去签测试版的那一刻：见 signingConfigs
// 里 test 那一项的注释。
val testKeystoreProperties = Properties()
val testKeystorePropertiesFile = rootProject.file("key-test.properties")
val hasTestSigning = testKeystorePropertiesFile.exists()
if (hasTestSigning) {
    testKeystorePropertiesFile.inputStream().use { testKeystoreProperties.load(it) }
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
        // 这是**正式版**的身份；测试版与调试版只在这上面加后缀（见下方
        // productFlavors 与 buildTypes.debug），不改这一处字面量。
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
        // 测试 keystore 与正式那份同一套四项凭据、同一条解析规矩。缺
        // key-test.properties 时故意指向一个不存在的文件：空签名配置会被静默
        // 放过（实测 validateSigning 与 APK 路径上的签名版本任务都照样成功），
        // 指向不存在的文件至少让 `signingReport` 说实话，并让 bundle 那条路
        // 当场失败；APK 那条路由文件末尾的 requireTestSigning 明着挡。
        create("test") {
            if (hasTestSigning) {
                keyAlias = testKeystoreProperties.getProperty("keyAlias")
                keyPassword = testKeystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(testKeystoreProperties.getProperty("storeFile"))
                storePassword = testKeystoreProperties.getProperty("storePassword")
            } else {
                storeFile = rootProject.file("susume-test.jks")
            }
        }
    }

    buildTypes {
        release {
            // 这里**不选签名**：构建类型的 signingConfig 优先级高于 flavor，一旦
            // 在构建类型上写死，测试版就会被正式钥签掉（Gradle 不报错，只有
            // `./gradlew :app:signingReport` 看得见）。用哪把钥整条留给
            // productFlavors，本文件只有那一处。
            //
            // 当前 release 未开 minify；预置节拍识别（onnxruntime JNI）keep
            // 规则（proguard-rules.pro），将来开启 minify 必须真机回归节拍
            // 分析。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        // 调试版身份：`flutter run` 装的那一份与正式版同名同签名的日子到此为止。
        // 后缀只叠在正式身份之后，`prod` flavor 的 debug 构建就是它。
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    // 三份安装身份（ADR-0003）：flavor 决定「正式版 / 测试版」，构建类型再叠
    // 一层「调试版」后缀，四组 applicationId 里真正对外的是三个——正式版
    // （prod × release）、测试版（beta × release）、调试版（prod × debug）。
    // 身份字面量只留 defaultConfig 一处，flavor 只加后缀，身份护栏按这条纪律
    // 断言（见 test/release/android_identity_test.dart）。
    //
    // 测试版这份 flavor 叫 `beta` 而不是 `test`：AGP 把 `test` 前缀留给单元
    // 测试源集（`ProductFlavor names cannot start with 'test'`），这是构建侧
    // 的既有约束，与词表术语**测试版**无关——身份后缀仍是 `.test`。
    flavorDimensions += "install"

    productFlavors {
        create("prod") {
            dimension = "install"
            // 正式版的钥：没有 key.properties 时回落到 debug key，让
            // `flutter run --release` 仍可用。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        create("beta") {
            dimension = "install"
            // 测试版与正式版并存：换身份即换数据目录、换签名升级链。
            applicationIdSuffix = ".test"
            // 版本名带身份标记：安装器、关于页与诊断信息都读得出这是哪一份。
            // 构建标识（git 短哈希）另经 --dart-define 注入，不进版本名。
            versionNameSuffix = "-test"
            signingConfig = signingConfigs.getByName("test")
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

// 测试版打包前的前置检查（ADR-0003）：缺 android/key-test.properties 就直接
// 失败，并说清该做什么。**不靠 AGP 兜底**——实测 APK 路径上的签名版本任务
// （writeBetaReleaseSigningConfigVersions）缺钥也照样通过：失败要么晚到签名那
// 一刻（那时已白编了几分钟，措辞也是 Gradle 的），要么根本不失败。这一道只挂
// 在测试版的打包任务上：正式版与 flutter run 一概不受影响。
val requireTestSigning = tasks.register("requireTestSigning") {
    group = "verification"
    description = "构建测试版前确认测试 keystore 凭据存在"
    doLast {
        if (!hasTestSigning) {
            throw GradleException(
                "缺 android/key-test.properties：测试版必须用测试 keystore 签名" +
                    "（生成办法见 README「测试包」一节）；不回落正式钥，也不回落 " +
                    "debug 签名——回落会让测试包逐机签名不同，测试者只能卸载重装。",
            )
        }
    }
}

tasks.matching {
    it.name == "packageBetaRelease" || it.name == "bundleBetaRelease"
}.configureEach {
    dependsOn(requireTestSigning)
}

// 出站分享 FileProvider：androidx.core 的 FileProvider 把包文件换 content
// URI 递出。
dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    // flutter_local_notifications 的 desugaring 运行时（插件 README 指定的
    // 最低版本）。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
