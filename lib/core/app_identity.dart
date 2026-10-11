/// App 身份：显示名、一句话简介与随包应用图标各只有这一处字面量——
/// `MaterialApp.title`、关于页与贡献者名单页共用的**应用信息头**都从这里取。
///
/// 三份**安装身份**（见 `lib/help/GLOSSARY.md` 的「安装身份」与 ADR-0003）里，
/// 构建期的 flavor 是身份的唯一来源：`prod` 是**正式版**，`beta` 是**测试版**，
/// 不带 `--flavor` 的构建由 `pubspec.yaml` 的 `default-flavor: prod` 兜住。
library;

import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 安装身份：一个 Susume 在系统里可被独立安装、独立持有数据的那一份身份。
///
/// **调试版**不是这里的第三种取值——它是与正式版同一份身份叠了 `.debug` 后缀
/// 的开发机构建，随装随卸，不参与本模块的任何分支。
enum InstallIdentity {
  /// **正式版**：发给用户的那一份。
  official,

  /// **测试版**：发给特定测试者的那一份，与正式版并存、数据不互通。
  test,
}

/// 测试版那份 flavor 在 Gradle 侧的名字。它叫 `beta` 而不是 `test`：AGP 把
/// `test` 前缀留给单元测试源集（`ProductFlavor names cannot start with 'test'`），
/// 与词表术语**测试版**无关。
const String _testFlavor = 'beta';

/// 本机安装身份：构建期定死，运行期不再看包名。
const InstallIdentity buildInstallIdentity = appFlavor == _testFlavor
    ? InstallIdentity.test
    : InstallIdentity.official;

/// 测试版的构建标识：`--dart-define=SUSUME_BUILD_ID=<标识>` 注入（git 短哈希
/// 一类），正式版为空串。它只进诊断面——关于页与 `device.json`——不进用户可见
/// 的版本号。
const String appBuildId = String.fromEnvironment('SUSUME_BUILD_ID');

/// 本机安装身份注入点：按身份分支的模块（更新链路、**版本行**）从这里取；测试
/// 覆写注入固定身份，不必真的按 flavor 构建。
final installIdentityProvider = Provider<InstallIdentity>(
  (ref) => buildInstallIdentity,
);

/// 测试版构建标识注入点：关于页读它；测试覆写注入固定值。
final appBuildIdProvider = Provider<String>((ref) => appBuildId);

const String _officialDisplayName = 'Susume';
const String _testDisplayName = 'Susume 测试版';

/// 按**安装身份**取显示名。它抽成纯函数，是因为构建期注入的 flavor 在宿主测试
/// 里改不动：测试直测两个身份各自的取值，[appDisplayName] 只是本机那一份。
String displayNameFor(InstallIdentity identity) =>
    identity == InstallIdentity.test ? _testDisplayName : _officialDisplayName;

/// App 显示名：**测试版**在名字上带身份，因此桌面图标与**应用信息头**两处一眼
/// 可分。
const String appDisplayName = appFlavor == _testFlavor
    ? _testDisplayName
    : _officialDisplayName;

/// App 短名：首页顶栏那一处。身份标记由桌面名与**应用信息头**承担，顶栏只有
/// 一行的宽度，不承担。
const String appShortName = 'Susume';

/// App 的一句话简介：应用信息头里应用名之下的那一句。
const String appTagline = '为扒舞设计的舞蹈练习工具';

/// 随包的应用图标资产：应用信息头里那一枚圆形图标。
const String appIconAsset = 'assets/brand/app_icon_1024.png';
