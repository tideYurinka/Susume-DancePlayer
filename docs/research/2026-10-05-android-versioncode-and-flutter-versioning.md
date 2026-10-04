# Android 降级安装语义 & Flutter 版本号独立控制

调研日期 2026-10-05。结论按 **claim → 原文片段 → URL → 置信度** 组织。
置信度取值：`confirmed`（一手来源直接写明 / 本机实测）、`inferred`（由一手来源合理推出）、`unconfirmed`（无法证实，不作猜测）。

本机工具链基线（用于实测项）：
- Flutter 3.47.2 stable，revision `d3b14c876900e553bc736ca19295fc09e3853e8e`（`/home/v2r/flutter`）
- Android SDK build-tools 36.0.0，platform android-36
- 被测工程：本仓库 `android/app/build.gradle.kts`，`pubspec.yaml` `version: 0.2.0+7`

---

## Part 1 — 普通（非系统）应用能否安装更低 versionCode

### 1.1 判定降级的代码只比较「严格小于」

- **Claim**：`checkDowngrade` 仅在 `after < before` 时抛 `INSTALL_FAILED_VERSION_DOWNGRADE`；相等版本码不会降级。
- **Snippet**（AOSP `main`，`PackageManagerServiceUtils.java`）：

```java
    private static void checkDowngrade(long beforeVersionCode, int beforeBaseRevisionCode,
            @NonNull String[] beforeSplitNames, @NonNull int[] beforeSplitRevisionCodes,
            @NonNull PackageInfoLite after) throws PackageManagerException {
        if (after.getLongVersionCode() < beforeVersionCode) {
            throw new PackageManagerException(INSTALL_FAILED_VERSION_DOWNGRADE,
                    "Update version code " + after.versionCode + " is older than current "
                            + beforeVersionCode);
        } else if (after.getLongVersionCode() == beforeVersionCode) {
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/PackageManagerServiceUtils.java
- **置信度**：`confirmed`

### 1.2 降级被拒时返回的确实是 `INSTALL_FAILED_VERSION_DOWNGRADE`

- **Claim**：`verifyReplacingVersionCode` 在降级不被允许时调用 `checkDowngrade`，并把异常映射为 `INSTALL_FAILED_VERSION_DOWNGRADE`。
- **Snippet**（AOSP `main`，`InstallPackageHelper.java`）：

```java
            } else if (dataOwnerPkg != null && !dataOwnerPkg.isSdkLibrary()) {
                if (!PackageManagerServiceUtils.isDowngradePermitted(installFlags,
                        dataOwnerPkg.isDebuggable())) {
                    // Downgrade is not permitted; a lower version of the app will not be allowed
                    try {
                        PackageManagerServiceUtils.checkDowngrade(dataOwnerPkg, pkgLite);
                    } catch (PackageManagerException e) {
                        String errorMsg = "Downgrade detected: " + e.getMessage();
                        Slog.w(TAG, errorMsg);
                        return Pair.create(
                                PackageManager.INSTALL_FAILED_VERSION_DOWNGRADE, errorMsg);
                    }
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/InstallPackageHelper.java
- **置信度**：`confirmed`（方法名 `verifyReplacingVersionCode`，位于该文件 ~L2801）

### 1.3 该错误码在公有常量里被 `@hide`

- **Claim**：`INSTALL_FAILED_VERSION_DOWNGRADE = -25` 标注 `@hide`（因此不在公开 SDK 常量面）。
- **Snippet**（AOSP `main`，`PackageManager.java`）：

```java
    /**
     * Installation return code: this is passed in the {@link PackageInstaller#EXTRA_LEGACY_STATUS}
     * if the new package has an older version code than the currently installed package.
     *
     * @hide
     */
    public static final int INSTALL_FAILED_VERSION_DOWNGRADE = -25;
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/content/pm/PackageManager.java
- **交叉验证**：本机 `android-36/android.jar` 反射面无该字段（`javap` 未列出），与 `@hide` 一致。`confirmed`

### 1.4 `SessionParams.setRequestDowngrade(boolean)` 是 `@hide @SystemApi`，普通应用不可用

- **Claim**：在 AOSP `main` 与 `android-14.0.0_r1` 两个版本中，`setRequestDowngrade` 都同时带 `/** {@hide} */` 与 `@SystemApi`。它不是 public SDK API。
- **Snippet**（AOSP `main`，`PackageInstaller.java`）：

```java
        /**
         * @deprecated use {@link #setRequestDowngrade(boolean)}.
         * {@hide}
         */
        @SystemApi
        @Deprecated
        public void setAllowDowngrade(boolean allowDowngrade) {
            setRequestDowngrade(allowDowngrade);
        }

        /** {@hide} */
        @SystemApi
        public void setRequestDowngrade(boolean requestDowngrade) {
            if (requestDowngrade) {
                installFlags |= PackageManager.INSTALL_REQUEST_DOWNGRADE;
            } else {
                installFlags &= ~PackageManager.INSTALL_REQUEST_DOWNGRADE;
            }
        }
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/content/pm/PackageInstaller.java
- **Android 14 交叉验证**：`https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-14.0.0_r1/core/java/android/content/pm/PackageInstaller.java` 中同一段同样是 `/** {@hide} */ @SystemApi`。
- **API level（已用 AOSP tag 逐版二分确认）**：`setRequestDowngrade(boolean)` 首次出现在 **Android 10（API 29）**，且从引入之初就是 `/** {@hide} */ @SystemApi`；Android 9 只有 `setAllowDowngrade`。验证方式：对 `android-9.0.0_r1` / `android-10.0.0_r1` / `android-11.0.0_r1` / `android-12.0.0_r1` / `android-13.0.0_r1` / `android-14.0.0_r1` 的 `PackageInstaller.java` 抓取并 grep：
  - `android-9.0.0_r1`：只有 `setAllowDowngrade`（无 `setRequestDowngrade`）
  - `android-10.0.0_r1`：`setRequestDowngrade` 已存在，注解为 `/** {@hide} */ @SystemApi`（`PackageInstaller.java` L1567–1575）
  - `android-11.0.0_r1` 起至 `main`：同上，无变化
  - URL 模板：`https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-10.0.0_r1/core/java/android/content/pm/PackageInstaller.java`
- **没有公开参考页**：因为它在 SDK 中同时是 `@hide` + `@SystemApi`，`developer.android.com` 上没有公开的 `setRequestDowngrade` API 参考条目；所谓「Android 14 加入」的说法与 AOSP 不符（Android 10 就有）。`confirmed`
- **对普通应用的含义**：`confirmed` —— 普通 (non-system, 非 platform 签名) 应用在编译期就无法引用它；可读的 `PackageInstaller.SessionParams` 公开面里没有降级开关。
- **本机验证**：`javap -p android/content/pm/PackageInstaller$SessionParams.class` 输出中没有 `setRequestDowngrade`。`confirmed`

### 1.5 即使想办法设上 `INSTALL_REQUEST_DOWNGRADE`，系统仍会再判定一次

- **Claim**：降级最终允许与否由 `isDowngradePermitted` 决定：必须「请求降级」 **且**（`Build.IS_DEBUGGABLE` 或**已安装版本**可调试 或 设置了 `INSTALL_ALLOW_DOWNGRADE`）。
- **Snippet**（AOSP `main`，`PackageManagerServiceUtils.java`）：

```java
    public static boolean isDowngradePermitted(int installFlags, boolean isAppDebuggable) {
        // ...
        // In case of user builds, downgrade is permitted only for the system server initiated
        // sessions. This is enforced by INSTALL_ALLOW_DOWNGRADE flag parameter.
        final boolean downgradeRequested =
                (installFlags & PackageManager.INSTALL_REQUEST_DOWNGRADE) != 0;
        if (!downgradeRequested) {
            return false;
        }
        final boolean isDebuggable = Build.IS_DEBUGGABLE || isAppDebuggable;
        if (isDebuggable) {
            return true;
        }
        return (installFlags & PackageManager.INSTALL_ALLOW_DOWNGRADE) != 0;
    }
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/PackageManagerServiceUtils.java
- **置信度**：`confirmed`
- **对自签名 release 应用的含义**：`inferred` —— 正式签名、`android:debuggable=false` 的 release 包，装在 user build（量产 ROM）上，`Build.IS_DEBUGGABLE=false` 且 `isAppDebuggable=false`，所以只有 `INSTALL_ALLOW_DOWNGRADE` 能放行，而该标志见 1.6。

### 1.6 `PackageManager.INSTALL_ALLOW_DOWNGRADE` 是 `@hide`，且系统只会替 system/root 或 debuggable build 设置

- **Claim A**：`INSTALL_ALLOW_DOWNGRADE = 0x00100000` 标注 `@hide`。
- **Snippet**（AOSP `main`，`PackageManager.java`）：

```java
    /**
     * Flag parameter for {@link #installPackage} to indicate that
     * {@link #INSTALL_REQUEST_DOWNGRADE} should be allowed.
     *
     * @hide
     */
    public static final int INSTALL_ALLOW_DOWNGRADE = 0x00100000;
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/content/pm/PackageManager.java
- **Claim B**：`PackageInstallerService.createSessionInternal()` 里，只有 `Build.IS_DEBUGGABLE` 或调用者是 system/root 时才**置位**该 flag，否则**清除**。
- **Snippet**（AOSP `main`，`PackageInstallerService.java`，方法 `int createSessionInternal(...)`）：

```java
        if (Build.IS_DEBUGGABLE || PackageManagerServiceUtils.isSystemOrRoot(callingUid)) {
            params.installFlags |= PackageManager.INSTALL_ALLOW_DOWNGRADE;
        } else {
            params.installFlags &= ~PackageManager.INSTALL_ALLOW_DOWNGRADE;
        }
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/PackageInstallerService.java
- **辅助片段**：

```java
    public static boolean isSystemOrRoot(int uid) {
        return uid == Process.SYSTEM_UID || uid == Process.ROOT_UID;
    }
```

（同文件 `PackageManagerServiceUtils.java`；`isSystemOrRootOrShell` 是另一个函数，含 `SHELL_UID`，**不**用于这里的降级判定。）
- **置信度**：`confirmed`（两段均逐字取自 AOSP main）
- **对普通第三方应用的含义**：`confirmed` —— `INSTALL_ALLOW_DOWNGRADE` 对普通应用不可用：常量 hidden，且即便手工置位也会在 `createSessionInternal` 被清掉。

### 1.7 AOSP 里遗留的告示：`INSTALL_ALLOW_DOWNGRADE` 尚未被积极强制

- **Claim**：`PackageInstallerSession.java` 里留有 `// TODO: enforce INSTALL_ALLOW_DOWNGRADE`。
- **Snippet**（AOSP `main`，`PackageInstallerSession.java`）：

```java
    // TODO: enforce INSTALL_ALLOW_TEST
    // TODO: enforce INSTALL_ALLOW_DOWNGRADE
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/PackageInstallerSession.java
- **置信度**：`confirmed`（存在该 TODO）。**这不改变 1.6 的结论**：`createSessionInternal` 已经会清除该 flag，所以 TODO 指的是更下层的二次强制。`inferred`

### 1.8 系统安装器 UI 没有「降级」确认入口（AOSP 层面）

- **Claim**：AOSP `packages/apps/PackageInstaller` 的 `res/values/strings.xml` 中不存在任何含 `downgrade` 的字符串。
- **证据**：抓取 https://android.googlesource.com/platform/packages/apps/PackageInstaller/+/refs/heads/main/res/values/strings.xml 后 `grep -i downgrade` 无匹配（1115 行）。
- **置信度**：`confirmed`（针对 AOSP 主线英文资源）。该 UI 没有可供用户点选以放行降级的对话框。
- **OEM 差异**：`unconfirmed` —— 未取得任何一手来源说明某家 OEM 的安装器提供「降级」确认弹窗；不猜测。中文「降级」提示在 AOSP 资源中查无实据。

### 1.9 相同签名 + 相同 versionCode 覆盖安装是允许的

- **Claim**：相等 versionCode 在 1.1 的比较中不触发降级；签名不一致才会失败。
- **Snippet A**（相等分支只检查 revision/split，不抛错）见 1.1。
- **Snippet B**（签名不匹配 → `INSTALL_FAILED_UPDATE_INCOMPATIBLE`）：

```java
                        if (!parsedPkgSigningDetails.checkCapability(oldPkgSigningDetails,
                                SigningDetails.CertCapabilities.INSTALLED_DATA)
                                && !oldPkgSigningDetails.checkCapability(parsedPkgSigningDetails,
                                SigningDetails.CertCapabilities.ROLLBACK)) {
                            // ...
                                throw new PrepareFailure(INSTALL_FAILED_UPDATE_INCOMPATIBLE,
                                        "New package has a different signature: " + pkgName11);
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/InstallPackageHelper.java
- **常量定义**：`INSTALL_FAILED_UPDATE_INCOMPATIBLE = -7`，注释写 "if a previously installed package of the same name has a different signature than the new package (and the old package's data was not removed)" —— https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/content/pm/PackageManager.java
- **置信度**：`confirmed`（代码比较运算符 + 常量注释）。**同签名的相等版本覆盖安装不报错**这一行为由代码直接支持；本报告未在真机复现。

### 1.10 `adb install -d` **不是**万能降级通道：只对 debuggable 包有效

- **Claim A**：`adb install -d` 只是给 session 加上 `INSTALL_REQUEST_DOWNGRADE`。
- **Snippet**（AOSP `main`，`PackageManagerShellCommand.java`，`runInstall()` 的选项 switch）：

```java
                case "-d":
                    sessionParams.installFlags |= PackageManager.INSTALL_REQUEST_DOWNGRADE;
                    break;
```

- **Claim B**：adb 自己的帮助文本就写明了限制。
- **Snippet**（同文件 `onHelp()`）：

```java
        pw.println("      -d: allow version code downgrade (debuggable packages only)");
```

- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/PackageManagerShellCommand.java
- **Claim C**：shell 走 `createSession(params, installerPackageName, null, ...)`（同文件 L3967），以 shell UID 进入 `isRootOrShell(callingUid)` 分支（`isRootOrShell` 只认 `ROOT_UID`/`SHELL_UID`），而这个分支**只**加 `INSTALL_FROM_ADB`，并**不**加 `INSTALL_ALLOW_DOWNGRADE`（后者只在 1.6 的 `Build.IS_DEBUGGABLE || isSystemOrRoot` 分支里加）。因此 shell 安装最终仍由 1.5 的 `isDowngradePermitted` 判定，只有「已安装包可调试」或「系统是 debuggable build」才放行。
- **URL**：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/PackageInstallerService.java
- **置信度**：`confirmed`（三段代码逐字）
- **对场景的结论**：`confirmed` —— 正式签名的 release 包（`android:debuggable=false`）装在 user build 上时，**`adb install -d` 同样会被拒**（`INSTALL_FAILED_VERSION_DOWNGRADE`）；降级能力仍只属于 system/root 或 debuggable build/包。即：**不是「adb 就能降级」，而是「debuggable 才能降级」**。

### 1.11 其它非 root 路径的评估

| 路径 | 结论 | 依据 / 置信度 |
| --- | --- | --- |
| 卸载后重装（`ACTION_DELETE` / `ACTION_UNINSTALL_PACKAGE`，或 `PackageInstaller` uninstall session） | 唯一通用可行路径，代价是丢本地数据 | `inferred`（卸载后不存在「已安装更高版本」这一前提，1.1 的检查自然不触发） |
| `setRequestDowngrade`（Android 10 / API 29 起，非「14+」） | 普通应用不可用（hidden + SystemApi，且 1.5/1.6 双重 gate） | `confirmed`，见 1.4–1.6 |
| `adb install -d` | 不是普通应用的替代品；它只设 `INSTALL_REQUEST_DOWNGRADE`，最终仍需「包/系统 debuggable」 | `confirmed`，见 1.10 |
| Play Core 应用内更新 | 不适用于 sideload 分发（Play Core 的更新流程依赖 Play Store 作为安装器） | 未取得一手引文，标记 `unconfirmed`（但由 1.5「需 debuggable 或 `INSTALL_ALLOW_DOWNGRADE`」可 `inferred` 出：Play 作为特权安装器时才具备该能力，第三方自托管没有） |
| `INSTALL_ALLOW_DOWNGRADE` | 普通应用不可用 | `confirmed`，见 1.6 |
| root（`su` 直接调用 PM 接口） | 可行（`isSystemOrRoot` 含 `ROOT_UID`） | `confirmed`，见 1.6 |

### 1.12 结论：常量 versionCode 是标准变通做法

- **Claim**：既然 `after == before` 通过 1.1 的检查，把 versionCode 固定成**同一个非递减值**即可持续覆盖安装。
- **置信度**：`confirmed`（由 1.1 + 1.9 直接推出）。注意代价：versionCode 恒定会使 Play Console / 任何「版本必须递增」的渠道拒绝更新（见 Part 2 的 2.4）。
- **未确认项**：本报告未在真机验证「相等 versionCode + 同签名」的实际安装交互（是否弹确认框、是否保留数据）。标记 `unconfirmed`。

---

## Part 2 — Flutter Android：独立控制 versionCode / versionName

### 2.1 `flutter.versionCode` / `flutter.versionName` 的真实来源是 `local.properties`，不是 pubspec 直读

- **Claim**：`flutter` 扩展的这两个属性是在插件 apply 时从**根工程** `local.properties` 读出的；缺失时默认 `"1"` / `"1.0"`。
- **Snippet**（本机 SDK `FlutterPlugin.kt` L120–134）：

```kotlin
        val flutterExtension: FlutterExtension =
            project.extensions.create("flutter", FlutterExtension::class.java)

        // TODO(gmackall): is this actually a different properties file than the previous one?
        val rootProjectLocalProperties = Properties()
        val rootProjectLocalPropertiesFile = rootProject.file("local.properties")
        if (rootProjectLocalPropertiesFile.exists()) {
            rootProjectLocalPropertiesFile.reader(StandardCharsets.UTF_8).use { reader ->
                rootProjectLocalProperties.load(reader)
            }
        }
        flutterExtension.flutterVersionCode =
            rootProjectLocalProperties.getProperty("flutter.versionCode", "1")
        flutterExtension.flutterVersionName =
            rootProjectLocalProperties.getProperty("flutter.versionName", "1.0")
```

- **URL**：https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt
- **本机路径**：`/home/v2r/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt`
- **实测佐证**：本仓库 `android/local.properties` 内容为 `flutter.versionName=0.2.0` / `flutter.versionCode=7`；对应 APK badging 为 `versionCode='7' versionName='0.2.0'`。
- **置信度**：`confirmed`

### 2.2 `flutter.versionCode` / `flutter.versionName` 是**即时求值**的 getter，不是 lateinit 变量

- **Claim**：两者是 Kotlin `val ... get()`，在 build 脚本里被求值的那一刻读取当前值——不存在「稍后再生效」的机制。
- **Snippet**（本机 SDK `FlutterExtension.kt` L59–82）：

```kotlin
    /** Returns flutterVersionCode as an integer with error handling. */
    fun getVersionCode(): Int {
        val versionCode =
            flutterVersionCode
                ?: throw GradleException("flutterVersionCode must not be null.")

        return versionCode.toIntOrNull()
            ?: throw GradleException("flutterVersionCode must be an integer.")
    }

    /** Returns flutterVersionName with error handling. */
    fun getVersionName(): String =
        flutterVersionName
            ?: throw GradleException("flutterVersionName must not be null.")

    // The default getter name that Kotlin creates conflicts with the above methods.
    @get:JvmName("getVersionCodeProperty")
    val versionCode: Int
        get() = getVersionCode()
```

- **URL**：https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt
- **置信度**：`confirmed`

### 2.3 在 `android { }` 里写字面量是有效的，且**字面量赢**

- **Claim**：Flutter 插件在 `plugins { id("dev.flutter.flutter-gradle-plugin") }` 应用时（即 build 脚本的 `plugins {}` 阶段）就把 `flutter` 扩展建好并填好值；`android { defaultConfig { ... } }` 在之后的脚本求值阶段执行。因此 `defaultConfig` 里写法面量会**覆盖** `flutter.versionCode`。本机实测：`versionCode = 4242` / `versionName = "9.9.9-beta01+ci"` 构建后 APK badging 为 `versionCode='4242' versionName='9.9.9-beta01+ci'`。
- **证据 A（顺序）**：上述 `FlutterPlugin.kt` L120–134 位于 `apply(project)` 内，属插件应用期；`android {}` 块是其后的脚本语句。
- **证据 B（实测，本仓库）**：临时把 `defaultConfig` 改为字面量后 `flutter build apk --release` 成功，`aapt2 dump badging` 输出：

```
package: name='top.yurinka.susume' versionCode='4242' versionName='9.9.9-beta01+ci' ...
```

（构建后已还原工程，`git status` 干净。）
- **置信度**：`confirmed`

### 2.4 `-P` + `project.findProperty` 同样有效，且比裸字面量更稳

- **Claim**：用 `project.findProperty(...)` 读取 CI 注入的 `-P` 值、否则回落到 `flutter.versionCode`，实测生效。
- **Snippet（临时实验代码，已还原）**：

```kotlin
        versionCode = (project.findProperty("ciVersionCode") as String?)?.toInt() ?: flutter.versionCode
        versionName = (project.findProperty("ciVersionName") as String?) ?: flutter.versionName
```

- **命令与结果**：`flutter build apk --release -PciVersionCode=5555 -PciVersionName=1.2.3-rc.1` → badging `versionCode='5555' versionName='1.2.3-rc.1'`
- **置信度**：`confirmed`
- **为什么 `-P` 更稳（`inferred`）**：
  1. 与 Flutter 插件读取 `project.findProperty(...)` 的既有风格一致（如 `force-version-code-ignoring-abi`、`code-size-directory`，见 `FlutterPluginUtils.kt` L317–322）。
  2. Gradle 配置缓存/up-to-date 判定会把 `-P` 属性视为构建输入，属性变化能可靠触发重新配置；写死在脚本里的字面量改动需要改文件。
  3. 同一个脚本可同时服务常量和渠道变量，不必为每个渠道改文件。
- **本机插件内既有先例**：

```kotlin
    @JvmStatic
    @JvmName("shouldForceVersionCodeIgnoringAbi")
    internal fun shouldForceVersionCodeIgnoringAbi(project: Project): Boolean =
        project.findProperty(PROP_FORCE_VERSION_CODE_IGNORING_ABI)?.toString()?.toBoolean() ?: false
```

（`FlutterPluginUtils.kt`；https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/gradle/src/main/kotlin/FlutterPluginUtils.kt）`confirmed`
- **两种写法都可行；最稳的组合**：`project.findProperty` 优先、`flutter.versionCode` 兜底（即上面的片段）。

### 2.5 `--build-number` / `--build-name` 的官方语义

- **Claim**：CLI 帮助文本原文——Android 上分别用作 `versionCode` / `versionName`；iOS/macOS 上用 `CFBundleVersion` / `CFBundleShortVersionString`；Windows 上用于产品/文件版本。
- **Snippet**（本机 `flutter build apk --help`，与 `flutter_command.dart` L741–765 的 `help:` 字符串一致）：

```
    --build-number                                           An identifier used as an internal version number.
                                                             Each build must have a unique identifier to differentiate it from previous builds.
                                                             It is used to determine whether one build is more recent than another, with higher numbers indicating more recent build.
                                                             On Android it is used as "versionCode".
                                                             On Xcode builds it is used as "CFBundleVersion".
                                                             On Windows it is used as the build suffix for the product and file versions.
    --build-name=<x.y.z>                                     A "x.y.z" string used as the version number shown to users.
                                                             ...
                                                             On Android it is used as "versionName".
                                                             On Xcode builds it is used as "CFBundleShortVersionString".
```

- **URL**：https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/runner/flutter_command.dart（`usesBuildNumberOption` / `usesBuildNameOption`）
- **可信度更高的公开文档**：官方 Android 部署文档原文 "Both the version and the build number can be overridden in Flutter's build by specifying `--build-name` and `--build-number`, respectively." —— https://github.com/flutter/website/blob/main/sites/docs/src/content/deployment/android.md
- **置信度**：`confirmed`
- **对 Gradle 的可见性（关键）**：`confirmed` —— 覆盖值会经 `writeLocalProperties` 写入 `android/local.properties` 的 `flutter.versionName` / `flutter.versionCode`，因此 Gradle 通过 `flutter.versionCode` 就能读到。本机 SDK 原文：

```dart
    final String? buildName = validatedBuildNameForPlatform(
      TargetPlatform.android_arm,
      buildInfo.buildName ?? project.manifest.buildName,
      globals.logger,
    );
    changeIfNecessary('flutter.versionName', buildName);
    final String? buildNumber = validatedBuildNumberForPlatform(
      TargetPlatform.android_arm,
      buildInfo.buildNumber ?? project.manifest.buildNumber,
      globals.logger,
    );
    changeIfNecessary('flutter.versionCode', buildNumber);
```

（`lib/src/android/gradle_utils.dart` L1204–1215）—— 优先级为「CLI flag > pubspec 的 `version:`」，`pubspec` 无需改动。
- **注意**：`changeIfNecessary` 只有在值不同时才写文件；因此 `--build-name/--build-number` 会**持久化覆盖** `android/local.properties`（该文件通常 gitignore），下次不带参数构建时 pubspec 值会再写回。`inferred`
- **iOS 影响**：`confirmed` —— 同一函数按平台分派，iOS/macOS 取 `CFBundleVersion`/`CFBundleShortVersionString`；因此 `--build-name`/`--build-number` **确实也会改 iOS 侧取值**（但这两个 flag 走的是各自平台的校验/清洗，见 2.6）。

### 2.6 flag 值的清洗规则（Android vs iOS）

- **Claim A**：Android 的 build-number 会剥离所有非数字字符并下限夹到 1。
- **Snippet**（本机 SDK `build_info.dart` L552–569）：

```dart
  if (targetPlatform == TargetPlatform.android_arm ||
      targetPlatform == TargetPlatform.android_arm64 ||
      targetPlatform == TargetPlatform.android_x64) {
    // See versionCode at https://developer.android.com/studio/publish/versioning
    final disallowed = RegExp(r'[^\d]');
    String tmpBuildNumberStr = buildNumber.replaceAll(disallowed, '');
    int tmpBuildNumberInt = int.tryParse(tmpBuildNumberStr) ?? 0;
    if (tmpBuildNumberInt < 1) {
      tmpBuildNumberInt = 1;
    }
```

- **Claim B**：Android 的 build-name **原样放行**，不做字符清洗。
- **Snippet**（同文件 L605–611）：

```dart
  if (targetPlatform == TargetPlatform.android ||
      targetPlatform == TargetPlatform.android_arm ||
      targetPlatform == TargetPlatform.android_arm64 ||
      targetPlatform == TargetPlatform.android_x64) {
    // See versionName at https://developer.android.com/studio/publish/versioning
    return buildName;
  }
```

- **Claim C**：iOS/macOS 走相反策略：build-name/build-number 剥离 `[^\d\.]`，build-name 补齐到 3 段。
- **Snippet**（同文件 L529–550 / L582–603）。
- **URL**：https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/build_info.dart
- **置信度**：`confirmed`
- **实践含义**：`--build-number=abc`（如误传非数字）会被静默改成 `1`；`--build-name=0.3.0-beta01` 在 Android 上会被原样使用。

### 2.7 pubspec `version:` 接受预发布后缀

- **Claim**：pubspec 的 `version` 允许 `-prerelease` 与 `+build` 后缀。
- **Snippet**（dart.dev 官方 pubspec 参考，"Version" 小节）：

> A version number is three numbers separated by dots, like `0.2.43`. It can also optionally have a build ( `+1`, `+2`, `+hotfix.oopsie`) or prerelease (`-dev.4`, `-alpha.12`, `-beta.7`, `-rc.5`) suffix.

- **URL**：https://dart.dev/tools/pub/pubspec
- **补充原文**（https://dart.dev/tools/pub/versioning）："The version numbers discussed in this guide might differ from the version number set in the package filename. They might include `-0` or `-beta`. These notations don't affect dependency resolution."
- **置信度**：`confirmed`
- **对 Flutter 工具链的含义（实测）**：`FlutterManifest.appVersion` 用 `Version.parse` 校验，本机 SDK 的正则为 `RegExp(r'^(\d+)(\.(\d+)(\.(\d+))?)?')` 且 `toString() => _text`（保留原始文本），因此 `0.3.0-beta01+8` 能通过并原样保留。实测（在 `flutter_tools` 包内 `dart run`）：

```
input=0.3.0-beta01+8 -> parsed=0.3.0-beta01+8
   buildName=0.3.0-beta01 buildNumber=8
input=1.0.0+build.5 -> parsed=1.0.0+build.5
   buildName=1.0.0 buildNumber=build.5
```

其中 `buildName`/`buildNumber` 由 `FlutterManifest` 按 `+` 切分：

```dart
  String? get buildName {
    final String? version = appVersion;
    if (version != null && version.contains('+')) {
      return version.split('+').elementAt(0);
    }
    return version;
  }
```

（本机 SDK `lib/src/flutter_manifest.dart` L190–208；https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/flutter_manifest.dart）
- **所以** `version: 0.3.0-beta01+8` 会让 APK 的 `versionName = 0.3.0-beta01`、`versionCode = 8`。`confirmed`（解析实测 + 代码路径）
- **注意**：`buildNumber = build.5` 这类非纯数字 build 号会在 Android 侧被 2.6 的清洗改成 `5`。`confirmed`

### 2.8 Android 构建接受带连字符的 `versionName`

- **Claim**：aapt2/manifest 对 `versionName` 没有「禁止 `-`」的限制；实测产物 badging 直接带上连字符。
- **实测证据**：`versionName = "9.9.9-beta01+ci"` 构建成功，`aapt2 dump badging` 输出 `versionName='9.9.9-beta01+ci'`；另一次 `1.2.3-rc.1` 同样成功。
- **置信度**：`confirmed`（构建期 + 打包期均通过）。
- **未确认项**：Google Play Console 上传时对 `versionName` 字符集是否有额外限制 —— `unconfirmed`（未取得一手来源）。

### 2.9 split APK 的 1000×ABI 偏移与 `force-version-code-ignoring-abi`

- **Claim**：开启按 ABI 拆分时，Flutter 用 `abiVersionCode * 1000 + versionCode` 覆盖每个输出的 versionCode；可用 `-P force-version-code-ignoring-abi=true` 禁掉。
- **Snippet A（插件实现）**（本机 SDK `FlutterPlugin.kt` L663–678）：

```kotlin
                    val versionCodeIfPresent: Int? = if (variant is ApkVariant) variant.versionCode else null
                    // ...
                    val abiVersionCode: Int? = FlutterPluginConstants.ABI_VERSION[filterIdentifier]
                    if (abiVersionCode != null && !FlutterPluginUtils.shouldForceVersionCodeIgnoringAbi(project)) {
                        output.versionCodeOverride = abiVersionCode * 1000 + (
                            versionCodeIfPresent
                                ?: variant.mergedFlavor.versionCode as Int
                        )
                    }
```

- **Snippet B（ABI 表）**（本机 SDK `FlutterPluginConstants.kt` L39–45）：`armeabi-v7a → 1`、`arm64-v8a → 2`、`x86_64 → 4`。
- **URL**：https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt 与 `.../FlutterPluginConstants.kt`
- **Snippet C（官方文档）**（Flutter 官方 Android 部署文档原文）：

> When using split APKs, the framework adds `ABI_VERSION * 1000` to the version code. This is because the Google Play Store doesn't allow multiple APKs for the same app to have the same version code. To force the default version code, specify the `-P force-version-code-ignoring-abi=true` flag during the build.

- **URL**：https://github.com/flutter/website/blob/main/sites/docs/src/content/deployment/android.md（渲染页 https://docs.flutter.dev/deployment/android）
- **置信度**：`confirmed`
- **本机实测旁证**：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 的 versionCode 为 `7`（= `2*1000 + 7` 的计算未生效于该产物）——这说明该 APK **不是**经 split 流程产出的 `output.versionCodeOverride`，即本工程当前未启用按 ABI 拆分。标记 `inferred`：**不要**据此认为偏移不存在；启用 `--split-per-abi` 时会生效。
- **常量 versionCode 的坑（`inferred`）**：
  - 若同时用 split APK 且**不**加 `force-version-code-ignoring-abi`，实际 versionCode 会变成 `abi*1000 + N`，三个产物各不相同；做自托管更新时必须知道用户装的是哪一个。
  - 对自托管单 APK 分发，**恒定的 versionCode** 是可行的（见 1.12），但它会让任何要求「版本递增」的渠道（Play Console）拒绝上传。
  - 该 flag 是 Flutter 插件的输入，参与 Gradle 配置缓存键；改它属于真实构建输入变化，不会命中陈旧缓存。`inferred`
- **Play Console 具体拒绝对应文案**：`unconfirmed`（未取得一手引文）。

---

## 未能确认清单（不猜测）

1. 任何 OEM 安装器是否会为降级提供用户确认弹窗（AOSP 侧无对应字符串）。
2. Play Console 对 `versionName` 字符集 / 恒定 versionCode 上传的确切拒绝文案。
3. 真机上「相等 versionCode + 同签名」覆盖安装的实际交互细节（是否弹确认框、数据保留情况）。
